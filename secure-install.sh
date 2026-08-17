#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-installer"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$STATE_DIR/install-$TIMESTAMP.log"
STATUS_FILE="$STATE_DIR/install-$TIMESTAMP.status"
OMF_INSTALLER="$STATE_DIR/omf-install-$TIMESTAMP.fish"
OMF_INSTALL_URL="https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install"
CATPPUCCIN_KDE_REPO_URL="https://github.com/catppuccin/kde"
CATPPUCCIN_KDE_DIR="$STATE_DIR/catppuccin-kde-$TIMESTAMP"

DRY_RUN=false
STOP_ON_ERROR=false
SKIP_OMF=false
ASSUME_YES=false

PACMAN_CORE_PACKAGES=(
  ghostty
  fish
  pkgfile
  wl-clipboard
)

PACMAN_DESKTOP_PACKAGES=(
  ark
  flameshot
  gparted
  kate
  libplasma
  qt5-graphicaleffects
  qt5-quickcontrols
  qt5-quickcontrols2
)

PACMAN_UTIL_PACKAGES=(
  cpupower
  eza
  fzf
  pv
  stow
  tree
  unzip
  viu
  wget
  power-profiles-daemon
)

PACMAN_THEME_PACKAGES=(
  catppuccin-gtk-theme-mocha
  nwg-look
  starship
  ttf-firacode-nerd
  ttf-hack-nerd
  ttf-jetbrains-mono-nerd
  ttf-meslo-nerd
  ttf-nerd-fonts-symbols-mono
)

AUR_PACKAGES=(
  ttf-ms-fonts
  ttf-vista-fonts
)

FAILURES=()

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Install bootstrap packages one at a time with logs.

Options:
  --dry-run        Print what would be installed without making changes
  --stop-on-error  Exit on the first failed step
  --skip-omf       Skip the Oh My Fish installation step
  --yes            Pass --noconfirm to pacman/yay and --yes to OMF
  -h, --help       Show this help text

Logs:
  Detailed log:  $LOG_FILE
  Step summary:  $STATUS_FILE
EOF
}

log() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$*" | tee -a "$LOG_FILE"
}

command_to_string() {
  local rendered=""
  local arg

  for arg in "$@"; do
    printf -v rendered '%s%q ' "$rendered" "$arg"
  done

  printf '%s' "${rendered% }"
}

record_status() {
  printf '%s\t%s\n' "$1" "$2" >>"$STATUS_FILE"
}

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log "Missing required command: $command_name"
    exit 1
  fi
}

run_step() {
  local step_name="$1"
  shift
  local -a command=("$@")
  local exit_code=0

  log ""
  log "STEP: $step_name"
  log "COMMAND: $(command_to_string "${command[@]}")"

  if [ "$DRY_RUN" = true ]; then
    record_status "DRY_RUN" "$step_name"
    return 0
  fi

  if "${command[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    record_status "OK" "$step_name"
    log "STEP OK: $step_name"
    return 0
  fi

  exit_code=${PIPESTATUS[0]}
  FAILURES+=("$step_name (exit $exit_code)")
  record_status "FAIL($exit_code)" "$step_name"
  log "STEP FAILED: $step_name (exit $exit_code)"

  if [ "$STOP_ON_ERROR" = true ]; then
    print_summary
    exit "$exit_code"
  fi

  return 0
}

install_package_group() {
  local manager="$1"
  local group_name="$2"
  local array_name="$3"
  local -n packages_ref="$array_name"
  local package_name
  local -a base_command

  log ""
  log "GROUP: $group_name"

  case "$manager" in
    pacman)
      base_command=(sudo pacman -S --needed)
      [ "$ASSUME_YES" = true ] && base_command+=(--noconfirm)
      ;;
    yay)
      if ! command -v yay >/dev/null 2>&1; then
        FAILURES+=("AUR packages (missing required command: yay)")
        record_status "FAIL" "AUR packages"
        log "Skipping AUR packages because yay is not installed"
        return 0
      fi
      base_command=(yay -S --needed)
      [ "$ASSUME_YES" = true ] && base_command+=(--noconfirm)
      ;;
    *)
      log "Unsupported package manager: $manager"
      exit 1
      ;;
  esac

  for package_name in "${packages_ref[@]}"; do
    run_step "$manager package: $package_name" "${base_command[@]}" "$package_name"
  done
}

install_omf() {
  local -a omf_command

  if [ "$SKIP_OMF" = true ]; then
    log "Skipping Oh My Fish installation"
    record_status "SKIPPED" "Oh My Fish"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    FAILURES+=("download Oh My Fish installer (missing required command: curl)")
    record_status "FAIL" "download Oh My Fish installer"
    log "Skipping OMF install because curl is not installed"
    return 0
  fi

  if ! command -v fish >/dev/null 2>&1; then
    FAILURES+=("install Oh My Fish (missing required command: fish)")
    record_status "FAIL" "install Oh My Fish"
    log "Skipping OMF install because fish is not installed"
    return 0
  fi

  run_step "download Oh My Fish installer" curl -fsSL "$OMF_INSTALL_URL" -o "$OMF_INSTALLER"

  if [ ! -e "$OMF_INSTALLER" ]; then
    return 0
  fi

  if [ ! -s "$OMF_INSTALLER" ]; then
    FAILURES+=("download Oh My Fish installer (empty file)")
    record_status "FAIL" "download Oh My Fish installer"
    log "Downloaded OMF installer file is empty: $OMF_INSTALLER"
    return 0
  fi

  chmod 700 "$OMF_INSTALLER"
  log "OMF installer saved locally for audit: $OMF_INSTALLER"

  omf_command=(fish "$OMF_INSTALLER" --noninteractive)
  [ "$ASSUME_YES" = true ] && omf_command+=(--yes)

  run_step "install Oh My Fish" "${omf_command[@]}"
}

install_catppuccin_kde() {
  if ! command -v git >/dev/null 2>&1; then
    FAILURES+=("clone Catppuccin KDE installer (missing required command: git)")
    record_status "FAIL" "clone Catppuccin KDE installer"
    log "Skipping Catppuccin KDE install because git is not installed"
    return 0
  fi

  if [ -d "$CATPPUCCIN_KDE_DIR" ] && [ "$DRY_RUN" = false ]; then
    rm -rf "$CATPPUCCIN_KDE_DIR"
  fi

  run_step "clone Catppuccin KDE installer" git clone --depth=1 "$CATPPUCCIN_KDE_REPO_URL" "$CATPPUCCIN_KDE_DIR"

  if [ ! -d "$CATPPUCCIN_KDE_DIR" ]; then
    return 0
  fi

  log "Starting upstream Catppuccin KDE installer."
  log "Choose Mocha with the Flamingo accent in the prompts to match this dotfiles setup."
  log "The upstream installer remains interactive by design."

  run_step "install Catppuccin KDE upstream theme" bash -lc 'cd "$1" && ./install.sh' _ "$CATPPUCCIN_KDE_DIR"
}

print_summary() {
  log ""
  log "Install log: $LOG_FILE"
  log "Step summary: $STATUS_FILE"

  if [ "${#FAILURES[@]}" -eq 0 ]; then
    log "All steps completed successfully."
    return 0
  fi

  log "Failures detected:"
  local failure
  for failure in "${FAILURES[@]}"; do
    log "  - $failure"
  done
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        ;;
      --stop-on-error)
        STOP_ON_ERROR=true
        ;;
      --skip-omf)
        SKIP_OMF=true
        ;;
      --yes)
        ASSUME_YES=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  mkdir -p "$STATE_DIR"
  : >"$LOG_FILE"
  : >"$STATUS_FILE"

  require_command sudo
  require_command pacman

  log "Starting secure package installation"
  log "State directory: $STATE_DIR"

  if [ "$DRY_RUN" = false ]; then
    log "Refreshing sudo credentials"
    sudo -v
  fi

  install_package_group pacman "Core packages" PACMAN_CORE_PACKAGES
  install_package_group pacman "Desktop packages" PACMAN_DESKTOP_PACKAGES
  install_package_group pacman "Utility packages" PACMAN_UTIL_PACKAGES
  install_package_group pacman "Theme packages" PACMAN_THEME_PACKAGES
  install_package_group yay "AUR packages" AUR_PACKAGES
  install_catppuccin_kde
  install_omf

  print_summary

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    exit 1
  fi
}

main "$@"

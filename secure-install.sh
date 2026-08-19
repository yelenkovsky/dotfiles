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
REMNOTE_DOWNLOAD_URL="https://backend.remnote.com/desktop/linux"
# RemNote's download endpoint rejects non-browser clients with 403. curl/wget
# send this so the script can follow the redirect to the AppImage. No extra
# setup is required at install time.
REMNOTE_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
REMNOTE_INSTALL_DIR="/opt/remnote"
REMNOTE_APPIMAGE_NAME="RemNote.AppImage"
REMNOTE_DOWNLOAD="$STATE_DIR/RemNote-$TIMESTAMP.AppImage"
REMNOTE_ICON_DIR="$STATE_DIR/remnote-icon-$TIMESTAMP"
TODOIST_DOWNLOAD_URL="https://todoist.com/linux_app/appimage"
TODOIST_INSTALL_DIR="/opt/todoist"
TODOIST_APPIMAGE_NAME="Todoist.AppImage"
TODOIST_DOWNLOAD="$STATE_DIR/Todoist-$TIMESTAMP.AppImage"
TODOIST_ICON_DIR="$STATE_DIR/todoist-icon-$TIMESTAMP"
NEXTCLOUD_LATEST_RELEASE_URL="https://github.com/nextcloud-releases/desktop/releases/latest"
NEXTCLOUD_INSTALL_DIR="/opt/nextcloud"
NEXTCLOUD_APPIMAGE_NAME="Nextcloud.AppImage"
NEXTCLOUD_DOWNLOAD="$STATE_DIR/Nextcloud-$TIMESTAMP.AppImage"
NEXTCLOUD_ICON_DIR="$STATE_DIR/nextcloud-icon-$TIMESTAMP"
NEXTCLOUD_DOWNLOAD_URL=""
PROTON_DRIVE_INDEX_URL="https://proton.me/download/drive/cli/index.html"
PROTON_DRIVE_PLATFORM="linux/x64"
PROTON_DRIVE_INDEX="$STATE_DIR/proton-drive-index-$TIMESTAMP.html"
PROTON_DRIVE_DOWNLOAD="$STATE_DIR/proton-drive-$TIMESTAMP"
PROTON_DRIVE_BIN="/usr/local/bin/proton-drive"
PASS_CLI_DOWNLOAD_URL="https://github.com/protonpass/pass-cli/releases/latest/download/pass-cli-linux-x86_64"
PASS_CLI_SHA256_URL="https://github.com/protonpass/pass-cli/releases/latest/download/pass-cli-linux-x86_64.sha256"
PASS_CLI_DOWNLOAD="$STATE_DIR/pass-cli-$TIMESTAMP"
PASS_CLI_SHA256_FILE="$STATE_DIR/pass-cli-$TIMESTAMP.sha256"
PASS_CLI_BIN="/usr/local/bin/pass-cli"

DRY_RUN=false
STOP_ON_ERROR=false
SKIP_OMF=false
SKIP_REMNOTE=false
SKIP_TODOIST=false
SKIP_NEXTCLOUD=false
SKIP_PROTON_DRIVE=false
SKIP_PASS_CLI=false
ASSUME_YES=false

PACMAN_CORE_PACKAGES=(
  ghostty
  fish
  vim
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
  --skip-remnote   Skip the RemNote AppImage download and install
  --skip-todoist   Skip the Todoist AppImage download and install
  --skip-nextcloud Skip the Nextcloud desktop AppImage download and install
  --skip-proton-drive  Skip the Proton Drive CLI download and install
  --skip-pass-cli  Skip the Proton Pass CLI download and install
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

download_remnote_appimage() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -A "$REMNOTE_USER_AGENT" -o "$REMNOTE_DOWNLOAD" "$REMNOTE_DOWNLOAD_URL"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget --tries=3 -U "$REMNOTE_USER_AGENT" -O "$REMNOTE_DOWNLOAD" "$REMNOTE_DOWNLOAD_URL"
    return
  fi

  log "Missing required command: curl or wget"
  return 127
}

extract_remnote_icon() {
  local icon=""

  mkdir -p "$REMNOTE_ICON_DIR"
  (
    cd "$REMNOTE_ICON_DIR"
    "$REMNOTE_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$REMNOTE_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$REMNOTE_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$REMNOTE_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/remnote.png
    log "Installed RemNote icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a RemNote icon; desktop entry will use the remnote icon name"
  return 0
}

install_remnote_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$REMNOTE_INSTALL_DIR"
  sudo install -D -m 755 "$REMNOTE_DOWNLOAD" "$REMNOTE_INSTALL_DIR/$REMNOTE_APPIMAGE_NAME"
  # RemNote's updater replaces this AppImage in place. Root ownership would
  # block self-update, so the installing user owns /opt/remnote.
  sudo chown -R "$owner:$group" "$REMNOTE_INSTALL_DIR"
  sudo chmod u+rwX "$REMNOTE_INSTALL_DIR" "$REMNOTE_INSTALL_DIR/$REMNOTE_APPIMAGE_NAME"
  sudo ln -sfn "$REMNOTE_INSTALL_DIR/$REMNOTE_APPIMAGE_NAME" /usr/local/bin/remnote
  sudo tee /usr/share/applications/remnote.desktop >/dev/null <<EOF
[Desktop Entry]
Name=RemNote
Comment=Note-taking and knowledge management
Exec=$REMNOTE_INSTALL_DIR/$REMNOTE_APPIMAGE_NAME --no-sandbox %U
Icon=remnote
Terminal=false
Type=Application
Categories=Office;Education;
StartupWMClass=RemNote
MimeType=x-scheme-handler/remnote;x-scheme-handler/rn;
EOF
  sudo chmod 644 /usr/share/applications/remnote.desktop
  extract_remnote_icon
  rm -rf "$REMNOTE_ICON_DIR" "$REMNOTE_DOWNLOAD"
}

install_remnote() {
  local file_size=0

  if [ "$SKIP_REMNOTE" = true ]; then
    log "Skipping RemNote installation"
    record_status "SKIPPED" "RemNote"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download RemNote AppImage (missing required command: curl or wget)")
    record_status "FAIL" "download RemNote AppImage"
    log "Skipping RemNote install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download RemNote AppImage" download_remnote_appimage

  if [ ! -e "$REMNOTE_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$REMNOTE_DOWNLOAD" ]; then
    FAILURES+=("download RemNote AppImage (empty file)")
    record_status "FAIL" "download RemNote AppImage"
    log "Downloaded RemNote file is empty: $REMNOTE_DOWNLOAD"
    return 0
  fi

  # Reject empty/tiny files and HTML error pages before writing under /opt.
  file_size="$(stat -c%s "$REMNOTE_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download RemNote AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download RemNote AppImage"
    log "Downloaded RemNote file looks too small to be an AppImage: $REMNOTE_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$REMNOTE_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download RemNote AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download RemNote AppImage"
    log "Downloaded RemNote file is not an ELF AppImage: $REMNOTE_DOWNLOAD"
    return 0
  fi

  chmod 700 "$REMNOTE_DOWNLOAD"
  log "Verified RemNote AppImage ($file_size bytes); installing to $REMNOTE_INSTALL_DIR"

  run_step "install RemNote AppImage" install_remnote_files
}

download_todoist_appimage() {
  download_url_to_file "$TODOIST_DOWNLOAD" "$TODOIST_DOWNLOAD_URL"
}

extract_todoist_icon() {
  local icon=""

  mkdir -p "$TODOIST_ICON_DIR"
  (
    cd "$TODOIST_ICON_DIR"
    "$TODOIST_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$TODOIST_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$TODOIST_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$TODOIST_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/todoist.png
    log "Installed Todoist icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Todoist icon; desktop entry will use the todoist icon name"
  return 0
}

install_todoist_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$TODOIST_INSTALL_DIR"
  sudo install -D -m 755 "$TODOIST_DOWNLOAD" "$TODOIST_INSTALL_DIR/$TODOIST_APPIMAGE_NAME"
  # Todoist's updater replaces this AppImage in place. Root ownership would
  # block self-update, so the installing user owns /opt/todoist.
  sudo chown -R "$owner:$group" "$TODOIST_INSTALL_DIR"
  sudo chmod u+rwX "$TODOIST_INSTALL_DIR" "$TODOIST_INSTALL_DIR/$TODOIST_APPIMAGE_NAME"
  sudo ln -sfn "$TODOIST_INSTALL_DIR/$TODOIST_APPIMAGE_NAME" /usr/local/bin/todoist
  sudo tee /usr/share/applications/todoist.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Todoist
Comment=The Best To-Do List App and Task Manager
Exec=env DESKTOPINTEGRATION=false $TODOIST_INSTALL_DIR/$TODOIST_APPIMAGE_NAME --no-sandbox %U
Icon=todoist
Terminal=false
Type=Application
Categories=Office;
StartupWMClass=todoist
MimeType=x-scheme-handler/todoist;x-scheme-handler/com.todoist;
EOF
  sudo chmod 644 /usr/share/applications/todoist.desktop
  extract_todoist_icon
  rm -rf "$TODOIST_ICON_DIR" "$TODOIST_DOWNLOAD"
}

install_todoist() {
  local file_size=0

  if [ "$SKIP_TODOIST" = true ]; then
    log "Skipping Todoist installation"
    record_status "SKIPPED" "Todoist"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Todoist AppImage (missing required command: curl or wget)")
    record_status "FAIL" "download Todoist AppImage"
    log "Skipping Todoist install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Todoist AppImage" download_todoist_appimage

  if [ ! -e "$TODOIST_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$TODOIST_DOWNLOAD" ]; then
    FAILURES+=("download Todoist AppImage (empty file)")
    record_status "FAIL" "download Todoist AppImage"
    log "Downloaded Todoist file is empty: $TODOIST_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$TODOIST_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Todoist AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Todoist AppImage"
    log "Downloaded Todoist file looks too small to be an AppImage: $TODOIST_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$TODOIST_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Todoist AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Todoist AppImage"
    log "Downloaded Todoist file is not an ELF AppImage: $TODOIST_DOWNLOAD"
    return 0
  fi

  chmod 700 "$TODOIST_DOWNLOAD"
  log "Verified Todoist AppImage ($file_size bytes); installing to $TODOIST_INSTALL_DIR"

  run_step "install Todoist AppImage" install_todoist_files
}

# Asset names include the version (Nextcloud-34.0.2-x86_64.AppImage), so there is
# no stable latest/download URL. Follow /releases/latest to the current tag, or
# use gh when it is available (avoids unauthenticated API rate limits).
resolve_nextcloud_appimage_url() {
  local effective=""
  local tag=""
  local version=""

  if command -v gh >/dev/null 2>&1; then
    NEXTCLOUD_DOWNLOAD_URL="$(
      gh api repos/nextcloud-releases/desktop/releases/latest \
        --jq '.assets[] | select(.name | test("x86_64\\.AppImage$")) | .browser_download_url' \
        | head -1
    )"
  elif command -v curl >/dev/null 2>&1; then
    effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$NEXTCLOUD_LATEST_RELEASE_URL")"
    tag="${effective##*/}"
    version="${tag#v}"
    NEXTCLOUD_DOWNLOAD_URL="https://github.com/nextcloud-releases/desktop/releases/download/${tag}/Nextcloud-${version}-x86_64.AppImage"
  else
    log "Missing required command: gh or curl"
    return 127
  fi

  case "$NEXTCLOUD_DOWNLOAD_URL" in
    https://github.com/nextcloud-releases/desktop/releases/download/*/Nextcloud-*-x86_64.AppImage) ;;
    *)
      log "Could not resolve a Nextcloud x86_64 AppImage URL from $NEXTCLOUD_LATEST_RELEASE_URL"
      return 1
      ;;
  esac

  log "Nextcloud desktop AppImage: $NEXTCLOUD_DOWNLOAD_URL"
  return 0
}

download_nextcloud_appimage() {
  download_url_to_file "$NEXTCLOUD_DOWNLOAD" "$NEXTCLOUD_DOWNLOAD_URL"
}

extract_nextcloud_icon() {
  local icon=""

  mkdir -p "$NEXTCLOUD_ICON_DIR"
  (
    cd "$NEXTCLOUD_ICON_DIR"
    "$NEXTCLOUD_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$NEXTCLOUD_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$NEXTCLOUD_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$NEXTCLOUD_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/Nextcloud.png
    log "Installed Nextcloud icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Nextcloud icon; desktop entry will use the Nextcloud icon name"
  return 0
}

install_nextcloud_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$NEXTCLOUD_INSTALL_DIR"
  sudo install -D -m 755 "$NEXTCLOUD_DOWNLOAD" "$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME"
  # The updater replaces this AppImage in place. Root ownership would block
  # self-update, so the installing user owns /opt/nextcloud.
  sudo chown -R "$owner:$group" "$NEXTCLOUD_INSTALL_DIR"
  sudo chmod u+rwX "$NEXTCLOUD_INSTALL_DIR" "$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME"
  sudo ln -sfn "$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME" /usr/local/bin/nextcloud
  sudo tee /usr/share/applications/nextcloud.desktop >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Nextcloud Desktop
GenericName=Folder Sync
Comment=Nextcloud desktop synchronization client
Exec=$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME %u
Icon=Nextcloud
Terminal=false
Categories=Utility;Network;FileTransfer;
Keywords=Nextcloud;syncing;file;sharing;
MimeType=application/vnd.nextcloud;x-scheme-handler/nc;
StartupWMClass=Nextcloud
SingleMainWindow=true
EOF
  sudo chmod 644 /usr/share/applications/nextcloud.desktop
  extract_nextcloud_icon
  rm -rf "$NEXTCLOUD_ICON_DIR" "$NEXTCLOUD_DOWNLOAD"
}

install_nextcloud() {
  local file_size=0

  if [ "$SKIP_NEXTCLOUD" = true ]; then
    log "Skipping Nextcloud desktop installation"
    record_status "SKIPPED" "Nextcloud desktop"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Nextcloud AppImage URL (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Nextcloud AppImage URL"
    log "Skipping Nextcloud install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_nextcloud_appimage_url; then
    FAILURES+=("resolve Nextcloud x86_64 AppImage URL")
    record_status "FAIL" "resolve Nextcloud x86_64 AppImage URL"
    return 0
  fi

  run_step "download Nextcloud desktop AppImage" download_nextcloud_appimage

  if [ ! -e "$NEXTCLOUD_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$NEXTCLOUD_DOWNLOAD" ]; then
    FAILURES+=("download Nextcloud desktop AppImage (empty file)")
    record_status "FAIL" "download Nextcloud desktop AppImage"
    log "Downloaded Nextcloud file is empty: $NEXTCLOUD_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$NEXTCLOUD_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Nextcloud desktop AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Nextcloud desktop AppImage"
    log "Downloaded Nextcloud file looks too small to be an AppImage: $NEXTCLOUD_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$NEXTCLOUD_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Nextcloud desktop AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Nextcloud desktop AppImage"
    log "Downloaded Nextcloud file is not an ELF AppImage: $NEXTCLOUD_DOWNLOAD"
    return 0
  fi

  chmod 700 "$NEXTCLOUD_DOWNLOAD"
  log "Verified Nextcloud AppImage ($file_size bytes); installing to $NEXTCLOUD_INSTALL_DIR"

  run_step "install Nextcloud desktop AppImage" install_nextcloud_files
}

download_url_to_file() {
  local dest="$1"
  local url="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget --tries=3 -O "$dest" "$url"
    return
  fi

  log "Missing required command: curl or wget"
  return 127
}

download_proton_drive_index() {
  download_url_to_file "$PROTON_DRIVE_INDEX" "$PROTON_DRIVE_INDEX_URL"
}

# The index lists linux/x64, linux/x64-baseline, and linux/x64-musl.
# Match the platform cell exactly so we take the glibc x86_64 build.
parse_proton_drive_linux_x64() {
  local parsed

  parsed="$(awk -v platform="$PROTON_DRIVE_PLATFORM" '
    BEGIN { RS = "<tr>" }
    index($0, "<td>" platform "</td>") {
      if (match($0, /href="[^"]+"/)) {
        url = substr($0, RSTART + 6, RLENGTH - 7)
      }
      if (match($0, /<code>[a-f0-9]+<\/code>/)) {
        hash = substr($0, RSTART + 6, RLENGTH - 13)
      }
      print url "\t" hash
      exit
    }
  ' "$PROTON_DRIVE_INDEX")"

  PROTON_DRIVE_URL="${parsed%%$'\t'*}"
  PROTON_DRIVE_SHA512="${parsed#*$'\t'}"

  if [ -z "$PROTON_DRIVE_URL" ] || [ -z "$PROTON_DRIVE_SHA512" ] || [ "$PROTON_DRIVE_URL" = "$PROTON_DRIVE_SHA512" ]; then
    return 1
  fi

  case "$PROTON_DRIVE_URL" in
    */linux-x64/proton-drive) ;;
    *)
      log "Parsed Proton Drive URL is not the linux-x64 binary: $PROTON_DRIVE_URL"
      return 1
      ;;
  esac

  log "Proton Drive CLI ($PROTON_DRIVE_PLATFORM): $PROTON_DRIVE_URL"
  return 0
}

download_proton_drive_binary() {
  download_url_to_file "$PROTON_DRIVE_DOWNLOAD" "$PROTON_DRIVE_URL"
}

install_proton_drive_files() {
  sudo install -D -m 755 "$PROTON_DRIVE_DOWNLOAD" "$PROTON_DRIVE_BIN"
  rm -f "$PROTON_DRIVE_DOWNLOAD" "$PROTON_DRIVE_INDEX"
}

install_proton_drive() {
  local actual_hash=""

  if [ "$SKIP_PROTON_DRIVE" = true ]; then
    log "Skipping Proton Drive CLI installation"
    record_status "SKIPPED" "Proton Drive CLI"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Proton Drive index (missing required command: curl or wget)")
    record_status "FAIL" "download Proton Drive index"
    log "Skipping Proton Drive install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Proton Drive CLI index" download_proton_drive_index

  if [ ! -s "$PROTON_DRIVE_INDEX" ]; then
    if [ "$DRY_RUN" = true ]; then
      return 0
    fi
    return 0
  fi

  if ! parse_proton_drive_linux_x64; then
    FAILURES+=("parse Proton Drive linux/x64 download from index")
    record_status "FAIL" "parse Proton Drive linux/x64 download from index"
    log "Could not find the $PROTON_DRIVE_PLATFORM row in $PROTON_DRIVE_INDEX_URL"
    return 0
  fi

  run_step "download Proton Drive CLI" download_proton_drive_binary

  if [ ! -e "$PROTON_DRIVE_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$PROTON_DRIVE_DOWNLOAD" ]; then
    FAILURES+=("download Proton Drive CLI (empty file)")
    record_status "FAIL" "download Proton Drive CLI"
    log "Downloaded Proton Drive file is empty: $PROTON_DRIVE_DOWNLOAD"
    return 0
  fi

  if [ "$(head -c 4 "$PROTON_DRIVE_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Proton Drive CLI (not an ELF binary)")
    record_status "FAIL" "download Proton Drive CLI"
    log "Downloaded Proton Drive file is not an ELF binary: $PROTON_DRIVE_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha512sum "$PROTON_DRIVE_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$PROTON_DRIVE_SHA512" ]; then
    FAILURES+=("verify Proton Drive CLI checksum")
    record_status "FAIL" "verify Proton Drive CLI checksum"
    log "Proton Drive SHA-512 mismatch (expected $PROTON_DRIVE_SHA512, got $actual_hash)"
    return 0
  fi

  chmod 700 "$PROTON_DRIVE_DOWNLOAD"
  log "Verified Proton Drive CLI SHA-512; installing to $PROTON_DRIVE_BIN"

  run_step "install Proton Drive CLI" install_proton_drive_files
}

download_pass_cli_files() {
  download_url_to_file "$PASS_CLI_SHA256_FILE" "$PASS_CLI_SHA256_URL"
  download_url_to_file "$PASS_CLI_DOWNLOAD" "$PASS_CLI_DOWNLOAD_URL"
}

install_pass_cli_files() {
  sudo install -D -m 755 "$PASS_CLI_DOWNLOAD" "$PASS_CLI_BIN"
  rm -f "$PASS_CLI_DOWNLOAD" "$PASS_CLI_SHA256_FILE"
}

install_pass_cli() {
  local expected_hash=""
  local actual_hash=""

  if [ "$SKIP_PASS_CLI" = true ]; then
    log "Skipping Proton Pass CLI installation"
    record_status "SKIPPED" "Proton Pass CLI"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Proton Pass CLI (missing required command: curl or wget)")
    record_status "FAIL" "download Proton Pass CLI"
    log "Skipping Proton Pass CLI install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Proton Pass CLI" download_pass_cli_files

  if [ ! -e "$PASS_CLI_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$PASS_CLI_DOWNLOAD" ]; then
    FAILURES+=("download Proton Pass CLI (empty file)")
    record_status "FAIL" "download Proton Pass CLI"
    log "Downloaded Proton Pass CLI file is empty: $PASS_CLI_DOWNLOAD"
    return 0
  fi

  if [ "$(head -c 4 "$PASS_CLI_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Proton Pass CLI (not an ELF binary)")
    record_status "FAIL" "download Proton Pass CLI"
    log "Downloaded Proton Pass CLI file is not an ELF binary: $PASS_CLI_DOWNLOAD"
    return 0
  fi

  if [ ! -s "$PASS_CLI_SHA256_FILE" ]; then
    FAILURES+=("download Proton Pass CLI checksum (empty file)")
    record_status "FAIL" "download Proton Pass CLI checksum"
    log "Downloaded Proton Pass CLI checksum file is empty: $PASS_CLI_SHA256_FILE"
    return 0
  fi

  expected_hash="$(awk '{ print $1 }' "$PASS_CLI_SHA256_FILE")"
  actual_hash="$(sha256sum "$PASS_CLI_DOWNLOAD" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    FAILURES+=("verify Proton Pass CLI checksum")
    record_status "FAIL" "verify Proton Pass CLI checksum"
    log "Proton Pass CLI SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 0
  fi

  chmod 700 "$PASS_CLI_DOWNLOAD"
  log "Verified Proton Pass CLI SHA-256; installing to $PASS_CLI_BIN"

  run_step "install Proton Pass CLI" install_pass_cli_files
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
      --skip-remnote)
        SKIP_REMNOTE=true
        ;;
      --skip-todoist)
        SKIP_TODOIST=true
        ;;
      --skip-nextcloud)
        SKIP_NEXTCLOUD=true
        ;;
      --skip-proton-drive)
        SKIP_PROTON_DRIVE=true
        ;;
      --skip-pass-cli)
        SKIP_PASS_CLI=true
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
  install_remnote
  install_todoist
  install_nextcloud
  install_proton_drive
  install_pass_cli

  print_summary

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    exit 1
  fi
}

main "$@"

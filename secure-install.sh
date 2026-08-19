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
NEXTCLOUD_SIG="$STATE_DIR/Nextcloud-$TIMESTAMP.AppImage.asc"
NEXTCLOUD_GPG_KEY="$STATE_DIR/nextcloud-signing-key-$TIMESTAMP.asc"
NEXTCLOUD_GPG_HOME="$STATE_DIR/nextcloud-gnupg-$TIMESTAMP"
NEXTCLOUD_ICON_DIR="$STATE_DIR/nextcloud-icon-$TIMESTAMP"
NEXTCLOUD_DOWNLOAD_URL=""
NEXTCLOUD_GPG_KEY_URL="https://nextcloud.com/nextcloud.asc"
# Nextcloud Security <security@nextcloud.com>; pin so a swapped key file cannot pass.
NEXTCLOUD_GPG_FINGERPRINT="28806A878AE423A28372792ED75899B9A724937A"
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
PROTON_PASS_VERSION_URL="https://proton.me/download/pass/linux/version.json"
PROTON_PASS_VERSION_JSON="$STATE_DIR/proton-pass-$TIMESTAMP.json"
PROTON_PASS_DEB="$STATE_DIR/proton-pass-$TIMESTAMP.deb"
PROTON_PASS_INSTALL_DIR="/opt/proton-pass"
PROTON_PASS_DEB_URL=""
PROTON_PASS_SHA512=""
BETTERBIRD_GETLOC_URL="https://www.betterbird.eu/downloads/getloc.php?os=linux&lang=en-US&version=release"
BETTERBIRD_SHA256_DIR="https://www.betterbird.eu/downloads"
BETTERBIRD_INSTALL_DIR="/opt/betterbird"
BETTERBIRD_DOWNLOAD="$STATE_DIR/betterbird-$TIMESTAMP.tar.xz"
BETTERBIRD_SHA256_FILE="$STATE_DIR/betterbird-$TIMESTAMP.sha256"
BETTERBIRD_DOWNLOAD_URL=""
BETTERBIRD_SHA256=""
BRAVE_ORIGIN_NIGHTLY_RELEASES_API="https://api.github.com/repos/brave/brave-browser/releases?per_page=20"
BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR="/opt/brave-origin-nightly"
BRAVE_ORIGIN_NIGHTLY_DOWNLOAD="$STATE_DIR/brave-origin-nightly-$TIMESTAMP.zip"
BRAVE_ORIGIN_NIGHTLY_SHA256_FILE="$STATE_DIR/brave-origin-nightly-$TIMESTAMP.zip.sha256"
BRAVE_ORIGIN_NIGHTLY_SIG="$STATE_DIR/brave-origin-nightly-$TIMESTAMP.zip.sha256.asc"
BRAVE_ORIGIN_NIGHTLY_GPG_KEY="$STATE_DIR/brave-signing-key-$TIMESTAMP.asc"
BRAVE_ORIGIN_NIGHTLY_GPG_HOME="$STATE_DIR/brave-gnupg-$TIMESTAMP"
BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL=""
BRAVE_ORIGIN_NIGHTLY_SHA256=""
BRAVE_GPG_KEY_URL="https://keys.openpgp.org/vks/v1/by-fingerprint/D16166072CACDF2C9429CBF11BF41E37D039F691"
# Brave Linux packaging key from https://brave.com/origin/linux/nightly/
BRAVE_GPG_FINGERPRINT="D16166072CACDF2C9429CBF11BF41E37D039F691"

DRY_RUN=false
STOP_ON_ERROR=false
SKIP_OMF=false
SKIP_REMNOTE=false
SKIP_TODOIST=false
SKIP_NEXTCLOUD=false
SKIP_PROTON_DRIVE=false
SKIP_PASS_CLI=false
SKIP_PROTON_PASS=false
SKIP_BETTERBIRD=false
SKIP_BRAVE_ORIGIN_NIGHTLY=false
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
  gnupg
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
  --skip-proton-pass  Skip the Proton Pass desktop .deb extract and install
  --skip-betterbird Skip the Betterbird tarball download and install
  --skip-brave-origin-nightly  Skip the Brave Origin Nightly zip download and install
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
  download_url_to_file "$NEXTCLOUD_SIG" "${NEXTCLOUD_DOWNLOAD_URL}.asc"
  download_url_to_file "$NEXTCLOUD_GPG_KEY" "$NEXTCLOUD_GPG_KEY_URL"
}

verify_nextcloud_appimage_signature() {
  local imported_fingerprint=""
  local status=""

  rm -rf "$NEXTCLOUD_GPG_HOME"
  mkdir -m 700 -p "$NEXTCLOUD_GPG_HOME"

  status="$(
    export GNUPGHOME="$NEXTCLOUD_GPG_HOME"
    gpg --batch --import "$NEXTCLOUD_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$NEXTCLOUD_GPG_FINGERPRINT" ]; then
    log "Nextcloud signing key fingerprint mismatch (expected $NEXTCLOUD_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$NEXTCLOUD_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$NEXTCLOUD_SIG" "$NEXTCLOUD_DOWNLOAD" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | grep -q "VALIDSIG $NEXTCLOUD_GPG_FINGERPRINT"; then
    log "Nextcloud AppImage GPG verification failed"
    return 1
  fi

  log "Verified Nextcloud AppImage GPG signature (VALIDSIG $NEXTCLOUD_GPG_FINGERPRINT)"
  return 0
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
  rm -rf "$NEXTCLOUD_ICON_DIR" "$NEXTCLOUD_DOWNLOAD" "$NEXTCLOUD_SIG" "$NEXTCLOUD_GPG_KEY" "$NEXTCLOUD_GPG_HOME"
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

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Nextcloud AppImage signature (missing required command: gpg)")
    record_status "FAIL" "verify Nextcloud AppImage signature"
    log "Skipping Nextcloud install because gpg is not installed"
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

  if [ ! -s "$NEXTCLOUD_SIG" ]; then
    FAILURES+=("download Nextcloud AppImage signature (empty file)")
    record_status "FAIL" "download Nextcloud AppImage signature"
    log "Downloaded Nextcloud signature is empty: $NEXTCLOUD_SIG"
    return 0
  fi

  if ! verify_nextcloud_appimage_signature; then
    FAILURES+=("verify Nextcloud AppImage GPG signature")
    record_status "FAIL" "verify Nextcloud AppImage GPG signature"
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

download_proton_pass_version_json() {
  download_url_to_file "$PROTON_PASS_VERSION_JSON" "$PROTON_PASS_VERSION_URL"
}

# Official Linux builds are versioned .deb/.rpm only. Take the first Stable amd64
# .deb from version.json (not RPM, not Beta).
parse_proton_pass_deb() {
  local parsed

  parsed="$(awk '
    /"Url":/ && /proton-pass_.*_amd64\.deb/ && url == "" {
      if (match($0, /https:[^"]+/)) {
        url = substr($0, RSTART, RLENGTH)
      }
      next
    }
    url != "" && /Sha512CheckSum/ {
      if (match($0, /[a-f0-9]{128}/)) {
        print url "\t" substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$PROTON_PASS_VERSION_JSON")"

  PROTON_PASS_DEB_URL="${parsed%%$'\t'*}"
  PROTON_PASS_SHA512="${parsed#*$'\t'}"

  case "$PROTON_PASS_DEB_URL" in
    https://proton.me/download/pass/linux/proton-pass_*_amd64.deb) ;;
    *)
      log "Could not parse a Proton Pass amd64 .deb URL from $PROTON_PASS_VERSION_URL"
      return 1
      ;;
  esac

  if [ -z "$PROTON_PASS_SHA512" ] || [ "$PROTON_PASS_DEB_URL" = "$PROTON_PASS_SHA512" ]; then
    log "Could not parse the Proton Pass SHA-512 from $PROTON_PASS_VERSION_URL"
    return 1
  fi

  log "Proton Pass desktop: $PROTON_PASS_DEB_URL"
  return 0
}

download_proton_pass_deb() {
  download_url_to_file "$PROTON_PASS_DEB" "$PROTON_PASS_DEB_URL"
}

install_proton_pass_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/proton-pass-extract-$TIMESTAMP"
  local data=""
  local binary=""
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$PROTON_PASS_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Proton Pass .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  binary="$(find "$work" -type f -name 'Proton Pass' | head -1)"
  if [ -z "$binary" ]; then
    log "Proton Pass .deb does not contain a Proton Pass binary"
    return 1
  fi
  appdir="$(dirname "$binary")"

  sudo mkdir -p "$PROTON_PASS_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$PROTON_PASS_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$PROTON_PASS_INSTALL_DIR"
  sudo chmod u+rwX "$PROTON_PASS_INSTALL_DIR"
  sudo chmod 755 "$PROTON_PASS_INSTALL_DIR/Proton Pass"
  sudo ln -sfn "$PROTON_PASS_INSTALL_DIR/Proton Pass" /usr/local/bin/proton-pass

  sudo tee /usr/share/applications/proton-pass.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Proton Pass
Comment=Proton Pass desktop application
GenericName=Password Manager
Exec="/opt/proton-pass/Proton Pass" --no-sandbox %U
Icon=proton-pass
Type=Application
StartupNotify=true
Categories=Utility;
StartupWMClass=Proton Pass
EOF
  sudo chmod 644 /usr/share/applications/proton-pass.desktop

  icon="$(find "$work" -type f -name 'proton-pass.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/proton-pass.png
  fi

  rm -rf "$work" "$PROTON_PASS_DEB" "$PROTON_PASS_VERSION_JSON"
}

install_proton_pass() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_PROTON_PASS" = true ]; then
    log "Skipping Proton Pass desktop installation"
    record_status "SKIPPED" "Proton Pass desktop"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Proton Pass version metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Proton Pass version metadata"
    log "Skipping Proton Pass desktop install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Proton Pass .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Proton Pass .deb"
    log "Skipping Proton Pass desktop install because bsdtar is not installed"
    return 0
  fi

  run_step "download Proton Pass version metadata" download_proton_pass_version_json

  if [ ! -s "$PROTON_PASS_VERSION_JSON" ]; then
    return 0
  fi

  if ! parse_proton_pass_deb; then
    FAILURES+=("parse Proton Pass amd64 .deb URL")
    record_status "FAIL" "parse Proton Pass amd64 .deb URL"
    return 0
  fi

  run_step "download Proton Pass desktop .deb" download_proton_pass_deb

  if [ ! -e "$PROTON_PASS_DEB" ]; then
    return 0
  fi

  if [ ! -s "$PROTON_PASS_DEB" ]; then
    FAILURES+=("download Proton Pass desktop .deb (empty file)")
    record_status "FAIL" "download Proton Pass desktop .deb"
    log "Downloaded Proton Pass file is empty: $PROTON_PASS_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$PROTON_PASS_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Proton Pass desktop .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Proton Pass desktop .deb"
    log "Downloaded Proton Pass file looks too small to be a .deb: $PROTON_PASS_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$PROTON_PASS_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Proton Pass desktop .deb (not an ar archive)")
    record_status "FAIL" "download Proton Pass desktop .deb"
    log "Downloaded Proton Pass file is not a .deb ar archive: $PROTON_PASS_DEB"
    return 0
  fi

  actual_hash="$(sha512sum "$PROTON_PASS_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$PROTON_PASS_SHA512" ]; then
    FAILURES+=("verify Proton Pass desktop checksum")
    record_status "FAIL" "verify Proton Pass desktop checksum"
    log "Proton Pass SHA-512 mismatch (expected $PROTON_PASS_SHA512, got $actual_hash)"
    return 0
  fi

  log "Verified Proton Pass .deb SHA-512; extracting to $PROTON_PASS_INSTALL_DIR"

  run_step "install Proton Pass desktop" install_proton_pass_files
}

resolve_betterbird_download() {
  local filename=""
  local series=""

  BETTERBIRD_DOWNLOAD_URL="$(tr -d '\r\n' < <(curl -fsSL "$BETTERBIRD_GETLOC_URL" 2>/dev/null || wget -qO- "$BETTERBIRD_GETLOC_URL"))"

  case "$BETTERBIRD_DOWNLOAD_URL" in
    https://www.betterbird.eu/downloads/*/betterbird-*.en-US.linux-x86_64.tar.xz) ;;
    *)
      log "Could not resolve a Betterbird linux-x86_64 tarball from $BETTERBIRD_GETLOC_URL"
      return 1
      ;;
  esac

  filename="${BETTERBIRD_DOWNLOAD_URL##*/}"
  series="$(printf '%s\n' "$filename" | sed -n 's/^betterbird-\([0-9][0-9]*\).*/\1/p')"
  if [ -z "$series" ]; then
    log "Could not parse Betterbird ESR series from $filename"
    return 1
  fi

  download_url_to_file "$BETTERBIRD_SHA256_FILE" "$BETTERBIRD_SHA256_DIR/sha256-${series}.txt"
  BETTERBIRD_SHA256="$(
    awk -v name="$filename" '
      {
        file = $2
        sub(/^\*/, "", file)
        if (file == name) {
          print $1
          exit
        }
      }
    ' "$BETTERBIRD_SHA256_FILE"
  )"

  if [ -z "$BETTERBIRD_SHA256" ]; then
    log "No SHA-256 for $filename in sha256-${series}.txt"
    return 1
  fi

  log "Betterbird tarball: $BETTERBIRD_DOWNLOAD_URL"
  return 0
}

download_betterbird_tarball() {
  download_url_to_file "$BETTERBIRD_DOWNLOAD" "$BETTERBIRD_DOWNLOAD_URL"
}

install_betterbird_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/betterbird-extract-$TIMESTAMP"
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$BETTERBIRD_DOWNLOAD"

  if [ -x "$work/betterbird/betterbird" ]; then
    appdir="$work/betterbird"
  else
    appdir="$(find "$work" -type f -name betterbird -printf '%h\n' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/betterbird" ]; then
    log "Betterbird tarball does not contain a betterbird binary"
    return 1
  fi

  sudo mkdir -p "$BETTERBIRD_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$BETTERBIRD_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$BETTERBIRD_INSTALL_DIR"
  sudo chmod u+rwX "$BETTERBIRD_INSTALL_DIR"
  sudo chmod 755 "$BETTERBIRD_INSTALL_DIR/betterbird"
  sudo ln -sfn "$BETTERBIRD_INSTALL_DIR/betterbird" /usr/local/bin/betterbird

  sudo tee /usr/share/applications/betterbird.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Betterbird
GenericName=Mail Client
Comment=Betterbird mail and news client
Exec=$BETTERBIRD_INSTALL_DIR/betterbird %u
Icon=betterbird
Terminal=false
Type=Application
Categories=Network;Email;News;
MimeType=x-scheme-handler/mailto;x-scheme-handler/mid;message/rfc822;
StartupWMClass=betterbird
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/betterbird.desktop

  icon="$(find "$appdir" -type f \( -name 'default128.png' -o -name 'betterbird.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/betterbird.png
  fi

  rm -rf "$work" "$BETTERBIRD_DOWNLOAD" "$BETTERBIRD_SHA256_FILE"
}

install_betterbird() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_BETTERBIRD" = true ]; then
    log "Skipping Betterbird installation"
    record_status "SKIPPED" "Betterbird"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("resolve Betterbird download (missing required command: curl or wget)")
    record_status "FAIL" "resolve Betterbird download"
    log "Skipping Betterbird install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Betterbird tarball (missing required command: bsdtar)")
    record_status "FAIL" "extract Betterbird tarball"
    log "Skipping Betterbird install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_betterbird_download; then
    FAILURES+=("resolve Betterbird linux-x86_64 tarball")
    record_status "FAIL" "resolve Betterbird linux-x86_64 tarball"
    return 0
  fi

  run_step "download Betterbird tarball" download_betterbird_tarball

  if [ ! -e "$BETTERBIRD_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$BETTERBIRD_DOWNLOAD" ]; then
    FAILURES+=("download Betterbird tarball (empty file)")
    record_status "FAIL" "download Betterbird tarball"
    log "Downloaded Betterbird file is empty: $BETTERBIRD_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$BETTERBIRD_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Betterbird tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Betterbird tarball"
    log "Downloaded Betterbird file looks too small: $BETTERBIRD_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  actual_hash="$(sha256sum "$BETTERBIRD_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$BETTERBIRD_SHA256" ]; then
    FAILURES+=("verify Betterbird checksum")
    record_status "FAIL" "verify Betterbird checksum"
    log "Betterbird SHA-256 mismatch (expected $BETTERBIRD_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Betterbird SHA-256; extracting to $BETTERBIRD_INSTALL_DIR"

  run_step "install Betterbird" install_betterbird_files
}

resolve_brave_origin_nightly_url() {
  local json="$STATE_DIR/brave-origin-nightly-releases-$TIMESTAMP.json"

  if command -v gh >/dev/null 2>&1; then
    BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL="$(
      gh api 'repos/brave/brave-browser/releases?per_page=20' \
        --jq '.[] | .assets[] | select(.name | test("^brave-origin-nightly-[0-9.]+-linux-amd64\\.zip$")) | .browser_download_url' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$BRAVE_ORIGIN_NIGHTLY_RELEASES_API"
    BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL="$(
      grep -oE 'https://github.com/brave/brave-browser/releases/download/[^"]+/brave-origin-nightly-[0-9.]+-linux-amd64\.zip"' "$json" \
        | head -1 \
        | tr -d '"'
    )"
    rm -f "$json"
  fi

  case "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL" in
    https://github.com/brave/brave-browser/releases/download/*/brave-origin-nightly-*-linux-amd64.zip) ;;
    *)
      log "Could not resolve a Brave Origin Nightly linux-amd64 zip from GitHub releases"
      return 1
      ;;
  esac

  log "Brave Origin Nightly zip: $BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL"
  return 0
}

download_brave_origin_nightly_files() {
  download_url_to_file "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD" "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL"
  download_url_to_file "$BRAVE_ORIGIN_NIGHTLY_SHA256_FILE" "${BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL}.sha256"
  download_url_to_file "$BRAVE_ORIGIN_NIGHTLY_SIG" "${BRAVE_ORIGIN_NIGHTLY_DOWNLOAD_URL}.sha256.asc"
  download_url_to_file "$BRAVE_ORIGIN_NIGHTLY_GPG_KEY" "$BRAVE_GPG_KEY_URL"
}

verify_brave_origin_nightly() {
  local imported_fingerprint=""
  local status=""
  local actual_hash=""

  rm -rf "$BRAVE_ORIGIN_NIGHTLY_GPG_HOME"
  mkdir -m 700 -p "$BRAVE_ORIGIN_NIGHTLY_GPG_HOME"

  status="$(
    export GNUPGHOME="$BRAVE_ORIGIN_NIGHTLY_GPG_HOME"
    gpg --batch --import "$BRAVE_ORIGIN_NIGHTLY_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$BRAVE_GPG_FINGERPRINT" ]; then
    log "Brave signing key fingerprint mismatch (expected $BRAVE_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$BRAVE_ORIGIN_NIGHTLY_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$BRAVE_ORIGIN_NIGHTLY_SIG" "$BRAVE_ORIGIN_NIGHTLY_SHA256_FILE" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | grep -q "VALIDSIG $BRAVE_GPG_FINGERPRINT"; then
    log "Brave Origin Nightly SHA-256 signature GPG verification failed"
    return 1
  fi

  BRAVE_ORIGIN_NIGHTLY_SHA256="$(awk '{ print $1 }' "$BRAVE_ORIGIN_NIGHTLY_SHA256_FILE")"
  actual_hash="$(sha256sum "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD" | awk '{ print $1 }')"
  if [ -z "$BRAVE_ORIGIN_NIGHTLY_SHA256" ] || [ "$actual_hash" != "$BRAVE_ORIGIN_NIGHTLY_SHA256" ]; then
    log "Brave Origin Nightly SHA-256 mismatch (expected $BRAVE_ORIGIN_NIGHTLY_SHA256, got $actual_hash)"
    return 1
  fi

  log "Verified Brave Origin Nightly SHA-256 and GPG signature"
  return 0
}

install_brave_origin_nightly_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/brave-origin-nightly-extract-$TIMESTAMP"
  local binary=""
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD"

  binary="$(find "$work" -type f \( -name brave-origin-nightly -o -name brave \) | head -1)"
  if [ -z "$binary" ]; then
    log "Brave Origin Nightly zip does not contain a brave binary"
    return 1
  fi
  appdir="$(dirname "$binary")"

  sudo mkdir -p "$BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR"
  sudo chmod u+rwX "$BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR"
  sudo chmod 755 "$BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR/$(basename "$binary")"
  sudo ln -sfn "$BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR/$(basename "$binary")" /usr/local/bin/brave-origin-nightly

  sudo tee /usr/share/applications/brave-origin-nightly.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Brave Origin Nightly
Comment=Brave Origin Nightly web browser
Exec=$BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR/$(basename "$binary") --no-sandbox %U
Icon=brave-origin-nightly
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=brave-origin-nightly
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/brave-origin-nightly.desktop

  icon="$(find "$appdir" -type f \( -name 'product_logo_128.png' -o -name 'brave.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/brave-origin-nightly.png
  fi

  rm -rf "$work" "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD" "$BRAVE_ORIGIN_NIGHTLY_SHA256_FILE" "$BRAVE_ORIGIN_NIGHTLY_SIG" "$BRAVE_ORIGIN_NIGHTLY_GPG_KEY" "$BRAVE_ORIGIN_NIGHTLY_GPG_HOME"
}

install_brave_origin_nightly() {
  local file_size=0

  if [ "$SKIP_BRAVE_ORIGIN_NIGHTLY" = true ]; then
    log "Skipping Brave Origin Nightly installation"
    record_status "SKIPPED" "Brave Origin Nightly"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Brave Origin Nightly zip (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Brave Origin Nightly zip"
    log "Skipping Brave Origin Nightly install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Brave Origin Nightly signature (missing required command: gpg)")
    record_status "FAIL" "verify Brave Origin Nightly signature"
    log "Skipping Brave Origin Nightly install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Brave Origin Nightly zip (missing required command: bsdtar)")
    record_status "FAIL" "extract Brave Origin Nightly zip"
    log "Skipping Brave Origin Nightly install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_brave_origin_nightly_url; then
    FAILURES+=("resolve Brave Origin Nightly linux-amd64 zip")
    record_status "FAIL" "resolve Brave Origin Nightly linux-amd64 zip"
    return 0
  fi

  run_step "download Brave Origin Nightly zip" download_brave_origin_nightly_files

  if [ ! -e "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD" ]; then
    FAILURES+=("download Brave Origin Nightly zip (empty file)")
    record_status "FAIL" "download Brave Origin Nightly zip"
    log "Downloaded Brave Origin Nightly file is empty: $BRAVE_ORIGIN_NIGHTLY_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Brave Origin Nightly zip (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Brave Origin Nightly zip"
    log "Downloaded Brave Origin Nightly file looks too small: $BRAVE_ORIGIN_NIGHTLY_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 2 "$BRAVE_ORIGIN_NIGHTLY_DOWNLOAD")" != 'PK' ]; then
    FAILURES+=("download Brave Origin Nightly zip (not a zip archive)")
    record_status "FAIL" "download Brave Origin Nightly zip"
    log "Downloaded Brave Origin Nightly file is not a zip archive: $BRAVE_ORIGIN_NIGHTLY_DOWNLOAD"
    return 0
  fi

  if [ ! -s "$BRAVE_ORIGIN_NIGHTLY_SHA256_FILE" ] || [ ! -s "$BRAVE_ORIGIN_NIGHTLY_SIG" ]; then
    FAILURES+=("download Brave Origin Nightly checksum or signature")
    record_status "FAIL" "download Brave Origin Nightly checksum or signature"
    log "Missing Brave Origin Nightly .sha256 or .sha256.asc"
    return 0
  fi

  if ! verify_brave_origin_nightly; then
    FAILURES+=("verify Brave Origin Nightly SHA-256 and GPG signature")
    record_status "FAIL" "verify Brave Origin Nightly SHA-256 and GPG signature"
    return 0
  fi

  log "Verified Brave Origin Nightly ($file_size bytes); installing to $BRAVE_ORIGIN_NIGHTLY_INSTALL_DIR"

  run_step "install Brave Origin Nightly" install_brave_origin_nightly_files
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
      --skip-proton-pass)
        SKIP_PROTON_PASS=true
        ;;
      --skip-betterbird)
        SKIP_BETTERBIRD=true
        ;;
      --skip-brave-origin-nightly)
        SKIP_BRAVE_ORIGIN_NIGHTLY=true
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
  install_proton_pass
  install_betterbird
  install_brave_origin_nightly

  print_summary

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    exit 1
  fi
}

main "$@"

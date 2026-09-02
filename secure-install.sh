#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-installer"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$STATE_DIR/install-$TIMESTAMP.log"
STATUS_FILE="$STATE_DIR/install-$TIMESTAMP.status"
OMF_INSTALLER="$STATE_DIR/omf-install-$TIMESTAMP.fish"
OMF_INSTALL_URL="https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install"
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
PROTON_BRIDGE_LATEST_RELEASE_URL="https://github.com/ProtonMail/proton-bridge/releases/latest"
PROTON_BRIDGE_GPG_KEY_URL="https://github.com/ProtonMail/proton-bridge/releases/latest/download/bridge_pubkey.gpg"
# Proton Technologies AG (ProtonMail Bridge developers) <bridge@protonmail.ch>
PROTON_BRIDGE_GPG_FINGERPRINT="D51E64D3E63EDC3EEF7864CEE2C75D68E6234B07"
PROTON_BRIDGE_DEB="$STATE_DIR/proton-bridge-$TIMESTAMP.deb"
PROTON_BRIDGE_SIG="$STATE_DIR/proton-bridge-$TIMESTAMP.deb.sig"
PROTON_BRIDGE_GPG_KEY="$STATE_DIR/proton-bridge-signing-key-$TIMESTAMP.gpg"
PROTON_BRIDGE_GPG_HOME="$STATE_DIR/proton-bridge-gnupg-$TIMESTAMP"
PROTON_BRIDGE_INSTALL_DIR="/opt/proton-bridge"
PROTON_BRIDGE_DOWNLOAD_URL=""
# Vendor PKGBUILD runtime dep for the `bridge` backend (libfido2.so.1).
PROTON_BRIDGE_RUNTIME_PACKAGES=(
  libfido2
)
BETTERBIRD_GETLOC_URL="https://www.betterbird.eu/downloads/getloc.php?os=linux&lang=en-US&version=release"
BETTERBIRD_SHA256_DIR="https://www.betterbird.eu/downloads"
BETTERBIRD_INSTALL_DIR="/opt/betterbird"
BETTERBIRD_DOWNLOAD="$STATE_DIR/betterbird-$TIMESTAMP.tar.xz"
BETTERBIRD_SHA256_FILE="$STATE_DIR/betterbird-$TIMESTAMP.sha256"
BETTERBIRD_DOWNLOAD_URL=""
BETTERBIRD_SHA256=""
# Official linux-x86_64 glibc tarball via the unversioned release redirect.
# Zotero does not publish SHA-256 next to the file; verify xz magic + size.
ZOTERO_DOWNLOAD_URL="https://www.zotero.org/download/client/dl?channel=release&platform=linux-x86_64"
ZOTERO_INSTALL_DIR="/opt/zotero"
ZOTERO_DOWNLOAD="$STATE_DIR/zotero-$TIMESTAMP.tar.xz"
ELEMENT_PACKAGES_URL="https://packages.element.io/debian/dists/default/main/binary-amd64/Packages"
ELEMENT_INRELEASE_URL="https://packages.element.io/debian/dists/default/InRelease"
ELEMENT_GPG_KEY_URL="https://packages.element.io/debian/element-io-archive-keyring.gpg"
# riot.im packages <packages@riot.im>; pin so a swapped keyring cannot pass.
ELEMENT_GPG_FINGERPRINT="12D4CD600C2240A9F4A82071D7B0B66941D01538"
ELEMENT_PACKAGES="$STATE_DIR/element-desktop-$TIMESTAMP.Packages"
ELEMENT_INRELEASE="$STATE_DIR/element-desktop-$TIMESTAMP.InRelease"
ELEMENT_GPG_KEY="$STATE_DIR/element-desktop-signing-key-$TIMESTAMP.gpg"
ELEMENT_GPG_HOME="$STATE_DIR/element-desktop-gnupg-$TIMESTAMP"
ELEMENT_DEB="$STATE_DIR/element-desktop-$TIMESTAMP.deb"
ELEMENT_INSTALL_DIR="/opt/element-desktop"
ELEMENT_DEB_URL=""
ELEMENT_SHA256=""
# Community Edition linux-x86_64 tarball via the unversioned /files/latest URL.
DBEAVER_DOWNLOAD_URL="https://dbeaver.io/files/dbeaver-ce-latest-linux-x86_64.tar.gz"
DBEAVER_SHA256_URL="https://dbeaver.io/files/checksum/dbeaver-ce-latest-linux-x86_64.tar.gz.sha256"
DBEAVER_INSTALL_DIR="/opt/dbeaver"
DBEAVER_DOWNLOAD="$STATE_DIR/dbeaver-$TIMESTAMP.tar.gz"
DBEAVER_SHA256_FILE="$STATE_DIR/dbeaver-$TIMESTAMP.sha256"
APPIMAGELAUNCHER_RELEASES_API="https://api.github.com/repos/TheAssassin/AppImageLauncher/releases/latest"
APPIMAGELAUNCHER_INSTALL_DIR="/opt/appimagelauncher"
APPIMAGELAUNCHER_APPIMAGE_NAME="AppImageLauncher.AppImage"
APPIMAGELAUNCHER_DOWNLOAD="$STATE_DIR/appimagelauncher-$TIMESTAMP.AppImage"
APPIMAGELAUNCHER_DOWNLOAD_URL=""
APPIMAGELAUNCHER_SHA256=""
# Newest desktop linux amd64 .deb (stable or beta; not arm64, not rpm, not
# android). Website latest-beta returns HTML to non-wget clients.
MULLVAD_RELEASES_API="https://api.github.com/repos/mullvad/mullvadvpn-app/releases?per_page=30"
MULLVAD_GPG_KEY_URL="https://mullvad.net/media/mullvad-code-signing.asc"
# Mullvad (code signing) <admin@mullvad.net>
MULLVAD_GPG_FINGERPRINT="A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF"
MULLVAD_INSTALL_DIR="/opt/Mullvad VPN"
MULLVAD_DEB="$STATE_DIR/mullvad-vpn-$TIMESTAMP.deb"
MULLVAD_SIG="$STATE_DIR/mullvad-vpn-$TIMESTAMP.deb.asc"
MULLVAD_GPG_KEY="$STATE_DIR/mullvad-signing-key-$TIMESTAMP.asc"
MULLVAD_GPG_HOME="$STATE_DIR/mullvad-gnupg-$TIMESTAMP"
MULLVAD_DOWNLOAD_URL=""
MULLVAD_SHA256=""
MULLVAD_RUNTIME_PACKAGES=(
  dbus
  iputils
  libayatana-appindicator
  libnotify
  libxss
  nss
)
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
# Official linux/x64 glibc AppImage from the dev (nightly) track, not arm64
# and not releaseTrack=stable. Cursor does not publish SHA-256 next to the
# file; verify ELF + size instead.
CURSOR_DOWNLOAD_API_URL="https://cursor.com/api/download?platform=linux-x64&releaseTrack=dev"
CURSOR_API_JSON="$STATE_DIR/cursor-download-$TIMESTAMP.json"
CURSOR_INSTALL_DIR="/opt/cursor"
CURSOR_APPIMAGE_NAME="Cursor.AppImage"
CURSOR_DOWNLOAD="$STATE_DIR/Cursor-$TIMESTAMP.AppImage"
CURSOR_ICON_DIR="$STATE_DIR/cursor-icon-$TIMESTAMP"
CURSOR_DOWNLOAD_URL=""
# Public Origin CLI: parse linux-x64 + SHA-256 from install.sh (do not pipe it
# to sh). Artifacts stay under the co/ CDN prefix; only the installer is origin/.
ORIGIN_CLI_INSTALL_SH_URL="https://downloads.cursor.com/origin/install.sh"
ORIGIN_CLI_INSTALL_SH="$STATE_DIR/origin-cli-install-$TIMESTAMP.sh"
ORIGIN_CLI_DOWNLOAD="$STATE_DIR/origin-cli-$TIMESTAMP.tar.gz"
ORIGIN_CLI_EXTRACT="$STATE_DIR/origin-cli-extract-$TIMESTAMP"
ORIGIN_CLI_BIN="/usr/local/bin/origin"
ORIGIN_CLI_URL=""
ORIGIN_CLI_SHA256=""
# Official amd64 spotify-client from the vendor Debian repo (not snap, not i386).
SPOTIFY_PACKAGES_URL="https://repository.spotify.com/dists/stable/non-free/binary-amd64/Packages"
SPOTIFY_INRELEASE_URL="https://repository.spotify.com/dists/stable/InRelease"
SPOTIFY_GPG_KEY_URL="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc"
# Spotify Public Repository Signing Key <tux@spotify.com>; pin so a swapped key cannot pass.
SPOTIFY_GPG_FINGERPRINT="E1096BCBFF6D418796DE78515384CE82BA52C83A"
SPOTIFY_PACKAGES="$STATE_DIR/spotify-$TIMESTAMP.Packages"
SPOTIFY_INRELEASE="$STATE_DIR/spotify-$TIMESTAMP.InRelease"
SPOTIFY_GPG_KEY="$STATE_DIR/spotify-signing-key-$TIMESTAMP.asc"
SPOTIFY_GPG_HOME="$STATE_DIR/spotify-gnupg-$TIMESTAMP"
SPOTIFY_DEB="$STATE_DIR/spotify-$TIMESTAMP.deb"
SPOTIFY_INSTALL_DIR="/opt/spotify"
SPOTIFY_DEB_URL=""
SPOTIFY_SHA256=""
SPOTIFY_RUNTIME_PACKAGES=(
  alsa-lib
  gtk3
  libayatana-appindicator
  libsm
  libxss
  libxtst
  nss
  xdg-utils
)
POMOTROID_RELEASES_API="https://api.github.com/repos/Splode/pomotroid/releases/latest"
POMOTROID_INSTALL_DIR="/opt/pomotroid"
POMOTROID_APPIMAGE_NAME="Pomotroid.AppImage"
POMOTROID_DOWNLOAD="$STATE_DIR/pomotroid-$TIMESTAMP.AppImage"
POMOTROID_ICON_DIR="$STATE_DIR/pomotroid-icon-$TIMESTAMP"
POMOTROID_DOWNLOAD_URL=""
POMOTROID_SHA256=""
DEBTAP_RELEASES_API="https://api.github.com/repos/helixarch/debtap/releases/latest"
DEBTAP_TARBALL="$STATE_DIR/debtap-$TIMESTAMP.tar.gz"
DEBTAP_EXTRACT="$STATE_DIR/debtap-extract-$TIMESTAMP"
DEBTAP_BIN="/usr/local/bin/debtap"
DEBTAP_TARBALL_URL=""
DEBTAP_RUNTIME_PACKAGES=(
  binutils
  fakeroot
  file
)
# Official linux-x64 zip from the Grayjay desktop page (not arm64, not
# Windows/macOS). FUTO does not publish SHA-256 next to the file; verify zip
# magic + size. In-app update can rewrite the user-owned /opt tree.
GRAYJAY_DOWNLOAD_URL="https://updater.grayjay.app/Apps/Grayjay.Desktop/Grayjay.Desktop-linux-x64.zip"
GRAYJAY_INSTALL_DIR="/opt/grayjay"
GRAYJAY_DOWNLOAD="$STATE_DIR/grayjay-$TIMESTAMP.zip"
GRAYJAY_RUNTIME_PACKAGES=(
  at-spi2-core
  gtk3
  libappindicator-gtk3
  libnotify
  libsecret
  libxss
  libxtst
  nss
  xdg-utils
)
# Official linux/x64 glibc amd64 .deb from the Linux download page (not rpm,
# not arm64). SHA-256 is published next to the file on the CDN.
SLACK_DOWNLOADS_URL="https://slack.com/downloads/instructions/linux?ddl=1&build=deb"
SLACK_INDEX="$STATE_DIR/slack-downloads-$TIMESTAMP.html"
SLACK_DEB="$STATE_DIR/slack-$TIMESTAMP.deb"
SLACK_SHA256_FILE="$STATE_DIR/slack-$TIMESTAMP.deb.sha256"
SLACK_INSTALL_DIR="/opt/slack"
SLACK_DEB_URL=""
SLACK_SHA256=""
SLACK_RUNTIME_PACKAGES=(
  at-spi2-core
  gtk3
  libappindicator-gtk3
  libnotify
  libxss
  libxtst
  nss
  xdg-utils
)

DRY_RUN=false
STOP_ON_ERROR=false
SKIP_OMF=false
SKIP_REMNOTE=false
SKIP_TODOIST=false
SKIP_NEXTCLOUD=false
SKIP_PROTON_DRIVE=false
SKIP_PASS_CLI=false
SKIP_PROTON_PASS=false
SKIP_PROTON_BRIDGE=false
SKIP_BETTERBIRD=false
SKIP_ZOTERO=false
SKIP_ELEMENT=false
SKIP_DBEAVER=false
SKIP_APPIMAGELAUNCHER=false
SKIP_MULLVAD=false
SKIP_BRAVE_ORIGIN_NIGHTLY=false
SKIP_CURSOR=false
SKIP_ORIGIN_CLI=false
SKIP_SPOTIFY=false
SKIP_POMOTROID=false
SKIP_DEBTAP=false
SKIP_GRAYJAY=false
SKIP_SLACK=false
ASSUME_YES=false

PACMAN_CORE_PACKAGES=(
  ghostty
  fish
  vim
  pkgfile
  wl-clipboard
)

PACMAN_DESKTOP_PACKAGES=(
  file-roller
  flameshot
  gparted
  # kdeconnect
  # kleopatra
  kompare
  krename
  krusader
  qbittorrent
  remmina
  unrar
  vlc
  vlc-plugins-all
)

PACMAN_UTIL_PACKAGES=(
  cpupower
  eza
  fuse2
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

PACMAN_FONT_PACKAGES=(
  starship
  ttf-firacode-nerd
  ttf-hack-nerd
  ttf-meslo-nerd
  ttf-nerd-fonts-symbols-mono
)

PACMAN_GAMING_PACKAGES=(
  steam
  gamemode
  lib32-gamemode
  mangohud
  lib32-mangohud
)

AUR_PACKAGES=(
  masterpdfeditor-free
  mangojuice
  proton-cachyos-slr
  optimus-manager-git
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
  --skip-proton-pass  Skip the Proton Pass desktop Stable .deb extract and install
  --skip-proton-bridge  Skip the Proton Mail Bridge amd64 .deb extract and install
  --skip-betterbird Skip the Betterbird tarball download and install
  --skip-zotero    Skip the Zotero linux-x86_64 tarball download and install
  --skip-element   Skip the Element Desktop amd64 .deb extract and install
  --skip-dbeaver   Skip the DBeaver CE linux-x86_64 tarball download and install
  --skip-appimagelauncher  Skip the AppImageLauncher x86_64 AppImage download and install
  --skip-mullvad   Skip the Mullvad VPN amd64 .deb extract and install
  --skip-brave-origin-nightly  Skip the Brave Origin Nightly zip download and install
  --skip-cursor    Skip the Cursor nightly (dev) AppImage download and install
  --skip-origin-cli  Skip the Cursor Origin CLI tarball download and install
  --skip-spotify   Skip the Spotify amd64 .deb extract and install
  --skip-pomotroid Skip the Pomotroid amd64 AppImage download and install
  --skip-debtap    Skip the debtap GitHub tarball download and install
  --skip-grayjay   Skip the Grayjay linux-x64 zip download and install
  --skip-slack     Skip the Slack amd64 .deb extract and install
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
    /"CategoryName":/ {
      in_stable = ($0 ~ /"Stable"/)
      next
    }
    in_stable && /"Url":/ && /proton-pass_.*_amd64\.deb/ && url == "" {
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

# Asset names include the version (protonmail-bridge_3.26.0-1_amd64.deb), so
# there is no stable latest/download URL. Follow /releases/latest, or use gh.
resolve_proton_bridge_deb_url() {
  local effective=""
  local tag=""
  local assets=""
  local rel=""

  if command -v gh >/dev/null 2>&1; then
    PROTON_BRIDGE_DOWNLOAD_URL="$(
      gh api repos/ProtonMail/proton-bridge/releases/latest \
        --jq '.assets[] | select(.name | test("^protonmail-bridge_[0-9.]+-[0-9]+_amd64\\.deb$")) | .browser_download_url' \
        | head -1
    )"
  elif command -v curl >/dev/null 2>&1; then
    effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$PROTON_BRIDGE_LATEST_RELEASE_URL")"
    tag="${effective##*/}"
    assets="$STATE_DIR/proton-bridge-assets-$TIMESTAMP.html"
    download_url_to_file "$assets" "https://github.com/ProtonMail/proton-bridge/releases/expanded_assets/${tag}"
    PROTON_BRIDGE_DOWNLOAD_URL="$(
      grep -oE 'https://github.com/ProtonMail/proton-bridge/releases/download/[^"]+/protonmail-bridge_[0-9.]+-[0-9]+_amd64\.deb' "$assets" \
        | head -1
    )"
    if [ -z "$PROTON_BRIDGE_DOWNLOAD_URL" ]; then
      rel="$(
        grep -oE '/ProtonMail/proton-bridge/releases/download/[^"]+/protonmail-bridge_[0-9.]+-[0-9]+_amd64\.deb' "$assets" \
          | head -1
      )"
      if [ -n "$rel" ]; then
        PROTON_BRIDGE_DOWNLOAD_URL="https://github.com${rel}"
      fi
    fi
    rm -f "$assets"
  else
    log "Missing required command: gh or curl"
    return 127
  fi

  case "$PROTON_BRIDGE_DOWNLOAD_URL" in
    https://github.com/ProtonMail/proton-bridge/releases/download/*/protonmail-bridge_*_amd64.deb) ;;
    *)
      log "Could not resolve a Proton Mail Bridge amd64 .deb URL from $PROTON_BRIDGE_LATEST_RELEASE_URL"
      return 1
      ;;
  esac

  log "Proton Mail Bridge .deb: $PROTON_BRIDGE_DOWNLOAD_URL"
  return 0
}

download_proton_bridge_files() {
  download_url_to_file "$PROTON_BRIDGE_DEB" "$PROTON_BRIDGE_DOWNLOAD_URL"
  download_url_to_file "$PROTON_BRIDGE_SIG" "${PROTON_BRIDGE_DOWNLOAD_URL}.sig"
  download_url_to_file "$PROTON_BRIDGE_GPG_KEY" "$PROTON_BRIDGE_GPG_KEY_URL"
}

verify_proton_bridge_signature() {
  local imported_fingerprint=""
  local status=""

  rm -rf "$PROTON_BRIDGE_GPG_HOME"
  mkdir -m 700 -p "$PROTON_BRIDGE_GPG_HOME"

  status="$(
    export GNUPGHOME="$PROTON_BRIDGE_GPG_HOME"
    gpg --batch --import "$PROTON_BRIDGE_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$PROTON_BRIDGE_GPG_FINGERPRINT" ]; then
    log "Proton Mail Bridge signing key fingerprint mismatch (expected $PROTON_BRIDGE_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$PROTON_BRIDGE_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$PROTON_BRIDGE_SIG" "$PROTON_BRIDGE_DEB" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | grep -q "VALIDSIG $PROTON_BRIDGE_GPG_FINGERPRINT"; then
    log "Proton Mail Bridge .deb GPG verification failed"
    return 1
  fi

  log "Verified Proton Mail Bridge .deb GPG signature (VALIDSIG $PROTON_BRIDGE_GPG_FINGERPRINT)"
  return 0
}

install_proton_bridge_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/proton-bridge-extract-$TIMESTAMP"
  local data=""
  local binary=""
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$PROTON_BRIDGE_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Proton Mail Bridge .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/usr/lib/protonmail/bridge/proton-bridge" ]; then
    appdir="$work/usr/lib/protonmail/bridge"
  else
    binary="$(find "$work" -type f -name proton-bridge | head -1)"
    if [ -n "$binary" ]; then
      appdir="$(dirname "$binary")"
    fi
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/proton-bridge" ]; then
    log "Proton Mail Bridge .deb does not contain a proton-bridge binary"
    return 1
  fi

  sudo mkdir -p "$PROTON_BRIDGE_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$PROTON_BRIDGE_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$PROTON_BRIDGE_INSTALL_DIR"
  sudo chmod u+rwX "$PROTON_BRIDGE_INSTALL_DIR"
  sudo chmod 755 "$PROTON_BRIDGE_INSTALL_DIR/proton-bridge"
  sudo ln -sfn "$PROTON_BRIDGE_INSTALL_DIR/proton-bridge" /usr/local/bin/protonmail-bridge

  sudo tee /usr/share/applications/protonmail-bridge.desktop >/dev/null <<EOF
[Desktop Entry]
Type=Application
Version=1.1
Name=Proton Mail Bridge
GenericName=Proton Mail Bridge for Linux
Comment=Proton Mail Bridge encrypts and decrypts messages for a local mail client
Exec=$PROTON_BRIDGE_INSTALL_DIR/proton-bridge
Icon=protonmail-bridge
Terminal=false
Categories=Office;Email;Network;
StartupWMClass=Proton Mail Bridge
EOF
  sudo chmod 644 /usr/share/applications/protonmail-bridge.desktop

  icon="$(find "$work" -type f \( -name 'protonmail-bridge.svg' -o -name 'protonmail-bridge.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    case "$icon" in
      *.svg)
        sudo install -D -m 644 "$icon" /usr/share/icons/hicolor/scalable/apps/protonmail-bridge.svg
        ;;
      *)
        sudo install -D -m 644 "$icon" /usr/share/pixmaps/protonmail-bridge.png
        ;;
    esac
  fi

  rm -rf "$work" "$PROTON_BRIDGE_DEB" "$PROTON_BRIDGE_SIG" "$PROTON_BRIDGE_GPG_KEY" "$PROTON_BRIDGE_GPG_HOME"
}

install_proton_bridge() {
  local file_size=0

  if [ "$SKIP_PROTON_BRIDGE" = true ]; then
    log "Skipping Proton Mail Bridge installation"
    record_status "SKIPPED" "Proton Mail Bridge"
    return 0
  fi

  install_package_group pacman "Proton Mail Bridge runtime packages" PROTON_BRIDGE_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Proton Mail Bridge .deb (missing required command: curl or gh)")
    record_status "FAIL" "resolve Proton Mail Bridge .deb"
    log "Skipping Proton Mail Bridge install because curl and gh are not installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Proton Mail Bridge signature (missing required command: gpg)")
    record_status "FAIL" "verify Proton Mail Bridge signature"
    log "Skipping Proton Mail Bridge install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Proton Mail Bridge .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Proton Mail Bridge .deb"
    log "Skipping Proton Mail Bridge install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_proton_bridge_deb_url; then
    FAILURES+=("resolve Proton Mail Bridge amd64 .deb URL")
    record_status "FAIL" "resolve Proton Mail Bridge amd64 .deb URL"
    return 0
  fi

  run_step "download Proton Mail Bridge .deb" download_proton_bridge_files

  if [ ! -e "$PROTON_BRIDGE_DEB" ]; then
    return 0
  fi

  if [ ! -s "$PROTON_BRIDGE_DEB" ]; then
    FAILURES+=("download Proton Mail Bridge .deb (empty file)")
    record_status "FAIL" "download Proton Mail Bridge .deb"
    log "Downloaded Proton Mail Bridge file is empty: $PROTON_BRIDGE_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$PROTON_BRIDGE_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Proton Mail Bridge .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Proton Mail Bridge .deb"
    log "Downloaded Proton Mail Bridge file looks too small to be a .deb: $PROTON_BRIDGE_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$PROTON_BRIDGE_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Proton Mail Bridge .deb (not an ar archive)")
    record_status "FAIL" "download Proton Mail Bridge .deb"
    log "Downloaded Proton Mail Bridge file is not a .deb ar archive: $PROTON_BRIDGE_DEB"
    return 0
  fi

  if [ ! -s "$PROTON_BRIDGE_SIG" ]; then
    FAILURES+=("download Proton Mail Bridge signature (empty file)")
    record_status "FAIL" "download Proton Mail Bridge signature"
    log "Downloaded Proton Mail Bridge signature is empty: $PROTON_BRIDGE_SIG"
    return 0
  fi

  if ! verify_proton_bridge_signature; then
    FAILURES+=("verify Proton Mail Bridge GPG signature")
    record_status "FAIL" "verify Proton Mail Bridge GPG signature"
    return 0
  fi

  log "Verified Proton Mail Bridge .deb ($file_size bytes); extracting to $PROTON_BRIDGE_INSTALL_DIR"

  run_step "install Proton Mail Bridge" install_proton_bridge_files
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

download_zotero_tarball() {
  download_url_to_file "$ZOTERO_DOWNLOAD" "$ZOTERO_DOWNLOAD_URL"
}

install_zotero_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/zotero-extract-$TIMESTAMP"
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$ZOTERO_DOWNLOAD"

  if [ -x "$work/Zotero_linux-x86_64/zotero" ]; then
    appdir="$work/Zotero_linux-x86_64"
  else
    appdir="$(find "$work" -type f -name zotero -printf '%h\n' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/zotero" ] || [ ! -x "$appdir/zotero-bin" ]; then
    log "Zotero tarball does not contain zotero and zotero-bin"
    return 1
  fi

  if [ "$(head -c 4 "$appdir/zotero-bin")" != $'\x7fELF' ]; then
    log "Zotero zotero-bin is not an ELF binary"
    return 1
  fi

  sudo mkdir -p "$ZOTERO_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$ZOTERO_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$ZOTERO_INSTALL_DIR"
  sudo chmod u+rwX "$ZOTERO_INSTALL_DIR"
  sudo chmod 755 "$ZOTERO_INSTALL_DIR/zotero" "$ZOTERO_INSTALL_DIR/zotero-bin"
  sudo ln -sfn "$ZOTERO_INSTALL_DIR/zotero" /usr/local/bin/zotero

  sudo tee /usr/share/applications/zotero.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Zotero
Comment=Collect, organize, cite, and share research
Exec=$ZOTERO_INSTALL_DIR/zotero %U
Icon=zotero
Terminal=false
Type=Application
Categories=Office;Education;
MimeType=text/plain;x-scheme-handler/zotero;application/x-research-info-systems;text/x-research-info-systems;text/ris;application/x-endnote-refer;application/x-inst-for-Scientific-info;application/mods+xml;application/rdf+xml;application/x-bibtex;text/x-bibtex;application/marc;application/vnd.citationstyles.style+xml
StartupWMClass=Zotero
StartupNotify=true
X-GNOME-SingleWindow=true
EOF
  sudo chmod 644 /usr/share/applications/zotero.desktop

  icon="$(find "$appdir/icons" -type f \( -name 'icon128.png' -o -name 'icon64.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/zotero.png
  fi

  rm -rf "$work" "$ZOTERO_DOWNLOAD"
}

install_zotero() {
  local file_size=0

  if [ "$SKIP_ZOTERO" = true ]; then
    log "Skipping Zotero installation"
    record_status "SKIPPED" "Zotero"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Zotero tarball (missing required command: curl or wget)")
    record_status "FAIL" "download Zotero tarball"
    log "Skipping Zotero install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Zotero tarball (missing required command: bsdtar)")
    record_status "FAIL" "extract Zotero tarball"
    log "Skipping Zotero install because bsdtar is not installed"
    return 0
  fi

  run_step "download Zotero tarball" download_zotero_tarball

  if [ ! -e "$ZOTERO_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$ZOTERO_DOWNLOAD" ]; then
    FAILURES+=("download Zotero tarball (empty file)")
    record_status "FAIL" "download Zotero tarball"
    log "Downloaded Zotero file is empty: $ZOTERO_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$ZOTERO_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Zotero tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Zotero tarball"
    log "Downloaded Zotero file looks too small: $ZOTERO_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  # XZ magic is fd 37 7a 58 5a 00; skip the trailing NUL so command substitution
  # does not strip it and break the comparison.
  if [ "$(head -c 5 "$ZOTERO_DOWNLOAD")" != $'\xfd7zXZ' ]; then
    FAILURES+=("download Zotero tarball (not an xz archive)")
    record_status "FAIL" "download Zotero tarball"
    log "Downloaded Zotero file is not an xz archive: $ZOTERO_DOWNLOAD"
    return 0
  fi

  log "Verified Zotero tarball ($file_size bytes); extracting to $ZOTERO_INSTALL_DIR"

  run_step "install Zotero" install_zotero_files
}

download_element_metadata() {
  download_url_to_file "$ELEMENT_PACKAGES" "$ELEMENT_PACKAGES_URL"
  download_url_to_file "$ELEMENT_INRELEASE" "$ELEMENT_INRELEASE_URL"
  download_url_to_file "$ELEMENT_GPG_KEY" "$ELEMENT_GPG_KEY_URL"
}

verify_element_packages_signature() {
  local imported_fingerprint=""
  local status=""
  local expected_hash=""
  local actual_hash=""

  rm -rf "$ELEMENT_GPG_HOME"
  mkdir -m 700 -p "$ELEMENT_GPG_HOME"

  status="$(
    export GNUPGHOME="$ELEMENT_GPG_HOME"
    gpg --batch --import "$ELEMENT_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$ELEMENT_GPG_FINGERPRINT" ]; then
    log "Element signing key fingerprint mismatch (expected $ELEMENT_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$ELEMENT_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$ELEMENT_INRELEASE" 2>/dev/null
  )" || true

  # InRelease is signed with the signing subkey. VALIDSIG's first fingerprint is
  # that subkey; the primary fingerprint is the last field.
  if ! printf '%s\n' "$status" | awk -v fpr="$ELEMENT_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Element InRelease GPG verification failed"
    return 1
  fi

  expected_hash="$(
    awk '
      $0 == "SHA256:" { in_sha = 1; next }
      in_sha && /^[A-Z]/ { in_sha = 0 }
      in_sha && $3 == "main/binary-amd64/Packages" { print $1; exit }
    ' "$ELEMENT_INRELEASE"
  )"
  actual_hash="$(sha256sum "$ELEMENT_PACKAGES" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    log "Element Packages SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 1
  fi

  log "Verified Element Packages GPG signature and SHA-256"
  return 0
}

parse_element_deb() {
  local parsed=""

  parsed="$(
    awk '
      $0 == "Package: element-desktop" { inpkg = 1; file = ""; hash = ""; next }
      inpkg && /^Package:/ { inpkg = 0 }
      inpkg && /^Filename:/ { file = $2 }
      inpkg && /^SHA256:/ { hash = $2 }
      END {
        if (file != "" && hash != "") {
          print file "\t" hash
        }
      }
    ' "$ELEMENT_PACKAGES"
  )"

  ELEMENT_DEB_URL="https://packages.element.io/debian/${parsed%%$'\t'*}"
  ELEMENT_SHA256="${parsed#*$'\t'}"

  case "$ELEMENT_DEB_URL" in
    https://packages.element.io/debian/pool/main/e/element-desktop/element-desktop_*_amd64.deb) ;;
    *)
      log "Could not parse an Element Desktop amd64 .deb URL from $ELEMENT_PACKAGES_URL"
      return 1
      ;;
  esac

  if [ -z "$ELEMENT_SHA256" ] || [ "$ELEMENT_DEB_URL" = "$ELEMENT_SHA256" ]; then
    log "Could not parse the Element Desktop SHA-256 from $ELEMENT_PACKAGES_URL"
    return 1
  fi

  log "Element Desktop: $ELEMENT_DEB_URL"
  return 0
}

download_element_deb() {
  download_url_to_file "$ELEMENT_DEB" "$ELEMENT_DEB_URL"
}

install_element_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/element-desktop-extract-$TIMESTAMP"
  local data=""
  local binary=""
  local appdir=""
  local icon=""
  local candidate=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$ELEMENT_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Element Desktop .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/opt/Element/element-desktop" ]; then
    appdir="$work/opt/Element"
  else
    while IFS= read -r candidate; do
      if [ "$(head -c 4 "$candidate")" = $'\x7fELF' ]; then
        binary="$candidate"
        break
      fi
    done < <(find "$work" -type f -name element-desktop)
    if [ -n "$binary" ]; then
      appdir="$(dirname "$binary")"
    fi
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/element-desktop" ]; then
    log "Element Desktop .deb does not contain an element-desktop binary"
    return 1
  fi

  sudo mkdir -p "$ELEMENT_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$ELEMENT_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$ELEMENT_INSTALL_DIR"
  sudo chmod u+rwX "$ELEMENT_INSTALL_DIR"
  sudo chmod 755 "$ELEMENT_INSTALL_DIR/element-desktop"
  # Hyprland is not a desktop Electron auto-detects; pin gnome-libsecret
  # (same as chromium-flags.conf on this machine).
  sudo tee /usr/local/bin/element-desktop >/dev/null <<EOF
#!/bin/bash
exec $ELEMENT_INSTALL_DIR/element-desktop --password-store=gnome-libsecret --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/element-desktop

  sudo tee /usr/share/applications/element-desktop.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Element
Comment=Secure Matrix messenger
GenericName=Matrix Client
Exec=$ELEMENT_INSTALL_DIR/element-desktop --password-store=gnome-libsecret --no-sandbox %U
Icon=element-desktop
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
MimeType=x-scheme-handler/element;x-scheme-handler/io.element.desktop;
StartupWMClass=Element
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/element-desktop.desktop

  icon="$(find "$work" -type f \( -name 'element.png' -o -name 'element-desktop.png' -o -name 'io.element.desktop.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/element-desktop.png
  fi

  rm -rf "$work" "$ELEMENT_DEB" "$ELEMENT_PACKAGES" "$ELEMENT_INRELEASE" "$ELEMENT_GPG_KEY" "$ELEMENT_GPG_HOME"
}

install_element() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_ELEMENT" = true ]; then
    log "Skipping Element Desktop installation"
    record_status "SKIPPED" "Element Desktop"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Element metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Element metadata"
    log "Skipping Element Desktop install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Element Packages signature (missing required command: gpg)")
    record_status "FAIL" "verify Element Packages signature"
    log "Skipping Element Desktop install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Element Desktop .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Element Desktop .deb"
    log "Skipping Element Desktop install because bsdtar is not installed"
    return 0
  fi

  run_step "download Element metadata" download_element_metadata

  if [ ! -s "$ELEMENT_PACKAGES" ] || [ ! -s "$ELEMENT_INRELEASE" ]; then
    return 0
  fi

  if ! verify_element_packages_signature; then
    FAILURES+=("verify Element Packages GPG signature")
    record_status "FAIL" "verify Element Packages GPG signature"
    return 0
  fi

  if ! parse_element_deb; then
    FAILURES+=("parse Element Desktop amd64 .deb URL")
    record_status "FAIL" "parse Element Desktop amd64 .deb URL"
    return 0
  fi

  run_step "download Element Desktop .deb" download_element_deb

  if [ ! -e "$ELEMENT_DEB" ]; then
    return 0
  fi

  if [ ! -s "$ELEMENT_DEB" ]; then
    FAILURES+=("download Element Desktop .deb (empty file)")
    record_status "FAIL" "download Element Desktop .deb"
    log "Downloaded Element Desktop file is empty: $ELEMENT_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$ELEMENT_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Element Desktop .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Element Desktop .deb"
    log "Downloaded Element Desktop file looks too small to be a .deb: $ELEMENT_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$ELEMENT_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Element Desktop .deb (not an ar archive)")
    record_status "FAIL" "download Element Desktop .deb"
    log "Downloaded Element Desktop file is not a .deb ar archive: $ELEMENT_DEB"
    return 0
  fi

  actual_hash="$(sha256sum "$ELEMENT_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$ELEMENT_SHA256" ]; then
    FAILURES+=("verify Element Desktop checksum")
    record_status "FAIL" "verify Element Desktop checksum"
    log "Element Desktop SHA-256 mismatch (expected $ELEMENT_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Element Desktop .deb SHA-256; extracting to $ELEMENT_INSTALL_DIR"

  run_step "install Element Desktop" install_element_files
}

download_dbeaver_files() {
  download_url_to_file "$DBEAVER_DOWNLOAD" "$DBEAVER_DOWNLOAD_URL"
  download_url_to_file "$DBEAVER_SHA256_FILE" "$DBEAVER_SHA256_URL"
}

install_dbeaver_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/dbeaver-extract-$TIMESTAMP"
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$DBEAVER_DOWNLOAD"

  if [ -x "$work/dbeaver/dbeaver" ]; then
    appdir="$work/dbeaver"
  else
    appdir="$(find "$work" -type f -name dbeaver -printf '%h\n' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/dbeaver" ]; then
    log "DBeaver tarball does not contain a dbeaver launcher"
    return 1
  fi

  sudo mkdir -p "$DBEAVER_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$DBEAVER_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$DBEAVER_INSTALL_DIR"
  sudo chmod u+rwX "$DBEAVER_INSTALL_DIR"
  sudo chmod 755 "$DBEAVER_INSTALL_DIR/dbeaver"
  sudo ln -sfn "$DBEAVER_INSTALL_DIR/dbeaver" /usr/local/bin/dbeaver

  sudo tee /usr/share/applications/dbeaver.desktop >/dev/null <<EOF
[Desktop Entry]
Name=DBeaver
Comment=Universal database tool
GenericName=Database Manager
Exec=$DBEAVER_INSTALL_DIR/dbeaver
Icon=dbeaver
Terminal=false
Type=Application
Categories=Development;Database;
StartupWMClass=DBeaver
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/dbeaver.desktop

  icon="$(find "$appdir" -type f \( -name 'dbeaver.png' -o -name 'dbeaver128.png' -o -name 'icon.xpm' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/dbeaver.png
  fi

  rm -rf "$work" "$DBEAVER_DOWNLOAD" "$DBEAVER_SHA256_FILE"
}

install_dbeaver() {
  local file_size=0
  local actual_hash=""
  local expected_hash=""

  if [ "$SKIP_DBEAVER" = true ]; then
    log "Skipping DBeaver installation"
    record_status "SKIPPED" "DBeaver"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download DBeaver tarball (missing required command: curl or wget)")
    record_status "FAIL" "download DBeaver tarball"
    log "Skipping DBeaver install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract DBeaver tarball (missing required command: bsdtar)")
    record_status "FAIL" "extract DBeaver tarball"
    log "Skipping DBeaver install because bsdtar is not installed"
    return 0
  fi

  run_step "download DBeaver tarball" download_dbeaver_files

  if [ ! -e "$DBEAVER_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$DBEAVER_DOWNLOAD" ]; then
    FAILURES+=("download DBeaver tarball (empty file)")
    record_status "FAIL" "download DBeaver tarball"
    log "Downloaded DBeaver file is empty: $DBEAVER_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$DBEAVER_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download DBeaver tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download DBeaver tarball"
    log "Downloaded DBeaver file looks too small: $DBEAVER_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 2 "$DBEAVER_DOWNLOAD")" != $'\x1f\x8b' ]; then
    FAILURES+=("download DBeaver tarball (not a gzip archive)")
    record_status "FAIL" "download DBeaver tarball"
    log "Downloaded DBeaver file is not a gzip archive: $DBEAVER_DOWNLOAD"
    return 0
  fi

  if [ ! -s "$DBEAVER_SHA256_FILE" ]; then
    FAILURES+=("download DBeaver checksum (empty file)")
    record_status "FAIL" "download DBeaver checksum"
    log "Downloaded DBeaver checksum file is empty: $DBEAVER_SHA256_FILE"
    return 0
  fi

  expected_hash="$(awk '{ print $1 }' "$DBEAVER_SHA256_FILE")"
  actual_hash="$(sha256sum "$DBEAVER_DOWNLOAD" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    FAILURES+=("verify DBeaver checksum")
    record_status "FAIL" "verify DBeaver checksum"
    log "DBeaver SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 0
  fi

  log "Verified DBeaver SHA-256; extracting to $DBEAVER_INSTALL_DIR"

  run_step "install DBeaver" install_dbeaver_files
}

resolve_mullvad_deb_url() {
  local json="$STATE_DIR/mullvad-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api 'repos/mullvad/mullvadvpn-app/releases?per_page=30' \
        --jq '
          [.[] | select(.tag_name | test("^[0-9]"))]
          | .[0].assets[]
          | select(.name | test("^MullvadVPN-.*_amd64\\.deb$"))
          | "\(.browser_download_url)\t\(.digest)"
        ' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$MULLVAD_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)

for release in releases:
    tag = release.get("tag_name") or ""
    if not re.match(r"^[0-9]", tag):
        continue
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if re.match(r"^MullvadVPN-.*_amd64\.deb$", name):
            digest = asset.get("digest") or ""
            if digest.startswith("sha256:"):
                digest = digest[7:]
            print(asset["browser_download_url"] + "\t" + digest)
            raise SystemExit
PY
      )"
    fi
    rm -f "$json"
  fi

  MULLVAD_DOWNLOAD_URL="${parsed%%$'\t'*}"
  MULLVAD_SHA256="${parsed#*$'\t'}"
  MULLVAD_SHA256="${MULLVAD_SHA256#sha256:}"

  case "$MULLVAD_DOWNLOAD_URL" in
    https://github.com/mullvad/mullvadvpn-app/releases/download/*/MullvadVPN-*_amd64.deb) ;;
    *)
      log "Could not resolve a Mullvad VPN amd64 .deb from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$MULLVAD_SHA256" ] || [ "$MULLVAD_DOWNLOAD_URL" = "$MULLVAD_SHA256" ]; then
    log "Could not parse the Mullvad VPN SHA-256 from GitHub releases"
    return 1
  fi

  log "Mullvad VPN .deb: $MULLVAD_DOWNLOAD_URL"
  return 0
}

download_mullvad_files() {
  download_url_to_file "$MULLVAD_DEB" "$MULLVAD_DOWNLOAD_URL"
  download_url_to_file "$MULLVAD_SIG" "${MULLVAD_DOWNLOAD_URL}.asc"
  download_url_to_file "$MULLVAD_GPG_KEY" "$MULLVAD_GPG_KEY_URL"
}

verify_mullvad_signature() {
  local imported_fingerprint=""
  local status=""

  rm -rf "$MULLVAD_GPG_HOME"
  mkdir -m 700 -p "$MULLVAD_GPG_HOME"

  status="$(
    export GNUPGHOME="$MULLVAD_GPG_HOME"
    gpg --batch --import "$MULLVAD_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$MULLVAD_GPG_FINGERPRINT" ]; then
    log "Mullvad VPN signing key fingerprint mismatch (expected $MULLVAD_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$MULLVAD_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$MULLVAD_SIG" "$MULLVAD_DEB" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | awk -v fpr="$MULLVAD_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Mullvad VPN .deb GPG verification failed"
    return 1
  fi

  log "Verified Mullvad VPN .deb GPG signature (VALIDSIG $MULLVAD_GPG_FINGERPRINT)"
  return 0
}

install_mullvad_files() {
  local work="$STATE_DIR/mullvad-extract-$TIMESTAMP"
  local data=""
  local appdir=""
  local unit=""
  local desktop=""
  local icon=""
  local bin=""

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$MULLVAD_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Mullvad VPN .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/opt/Mullvad VPN/mullvad-vpn" ]; then
    appdir="$work/opt/Mullvad VPN"
  else
    appdir="$(find "$work" -type d -name 'Mullvad VPN' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/mullvad-vpn" ]; then
    log "Mullvad VPN .deb does not contain /opt/Mullvad VPN/mullvad-vpn"
    return 1
  fi

  if [ ! -x "$work/usr/bin/mullvad-daemon" ]; then
    log "Mullvad VPN .deb does not contain usr/bin/mullvad-daemon"
    return 1
  fi

  sudo mkdir -p "$MULLVAD_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$MULLVAD_INSTALL_DIR"/
  sudo chmod 755 "$MULLVAD_INSTALL_DIR/mullvad-vpn"

  for bin in mullvad mullvad-daemon mullvad-exclude mullvad-problem-report; do
    if [ -f "$work/usr/bin/$bin" ]; then
      sudo install -D -m 755 "$work/usr/bin/$bin" "/usr/local/bin/$bin"
    fi
  done
  if [ -f /usr/local/bin/mullvad-exclude ]; then
    sudo chmod u+s /usr/local/bin/mullvad-exclude
  fi

  sudo tee /usr/local/bin/mullvad-vpn >/dev/null <<EOF
#!/bin/bash
exec "$MULLVAD_INSTALL_DIR/mullvad-vpn" --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/mullvad-vpn

  for unit in "$work"/usr/lib/systemd/system/mullvad-*.service; do
    [ -f "$unit" ] || continue
    sudo install -D -m 644 "$unit" "/usr/lib/systemd/system/$(basename "$unit")"
    sudo sed -i 's|/usr/bin/mullvad-daemon|/usr/local/bin/mullvad-daemon|g' \
      "/usr/lib/systemd/system/$(basename "$unit")"
  done

  if [ -d "$work/usr/share/dbus-1" ]; then
    sudo mkdir -p /usr/share/dbus-1
    sudo cp -a "$work/usr/share/dbus-1"/. /usr/share/dbus-1/
  fi
  if [ -d "$work/usr/share/polkit-1" ]; then
    sudo mkdir -p /usr/share/polkit-1
    sudo cp -a "$work/usr/share/polkit-1"/. /usr/share/polkit-1/
  fi

  desktop="$(find "$work" -type f -name 'mullvad-vpn.desktop' | head -1)"
  if [ -n "$desktop" ]; then
    sudo install -D -m 644 "$desktop" /usr/share/applications/mullvad-vpn.desktop
    sudo sed -i 's|^Exec=.*|Exec=/usr/local/bin/mullvad-vpn %U|' /usr/share/applications/mullvad-vpn.desktop
  else
    sudo tee /usr/share/applications/mullvad-vpn.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Mullvad VPN
Comment=Mullvad VPN client
Exec=/usr/local/bin/mullvad-vpn %U
Icon=mullvad-vpn
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
EOF
    sudo chmod 644 /usr/share/applications/mullvad-vpn.desktop
  fi

  icon="$(find "$work" -type f \( -name 'mullvad-vpn.png' -o -name 'mullvad.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/mullvad-vpn.png
  elif [ -d "$work/usr/share/icons" ]; then
    sudo cp -a "$work/usr/share/icons"/. /usr/share/icons/
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl daemon-reload
    sudo systemctl enable mullvad-daemon.service
    sudo systemctl enable mullvad-early-boot-blocking.service
    sudo systemctl restart mullvad-daemon.service || log "Failed to restart mullvad-daemon.service"
  fi

  rm -rf "$work" "$MULLVAD_DEB" "$MULLVAD_SIG" "$MULLVAD_GPG_KEY" "$MULLVAD_GPG_HOME"
}

install_mullvad() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_MULLVAD" = true ]; then
    log "Skipping Mullvad VPN installation"
    record_status "SKIPPED" "Mullvad VPN"
    return 0
  fi

  install_package_group pacman "Mullvad VPN runtime packages" MULLVAD_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Mullvad VPN .deb (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Mullvad VPN .deb"
    log "Skipping Mullvad VPN install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Mullvad VPN signature (missing required command: gpg)")
    record_status "FAIL" "verify Mullvad VPN signature"
    log "Skipping Mullvad VPN install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Mullvad VPN .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Mullvad VPN .deb"
    log "Skipping Mullvad VPN install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_mullvad_deb_url; then
    FAILURES+=("resolve Mullvad VPN amd64 .deb URL")
    record_status "FAIL" "resolve Mullvad VPN amd64 .deb URL"
    return 0
  fi

  run_step "download Mullvad VPN .deb" download_mullvad_files

  if [ ! -e "$MULLVAD_DEB" ]; then
    return 0
  fi

  if [ ! -s "$MULLVAD_DEB" ]; then
    FAILURES+=("download Mullvad VPN .deb (empty file)")
    record_status "FAIL" "download Mullvad VPN .deb"
    log "Downloaded Mullvad VPN file is empty: $MULLVAD_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$MULLVAD_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Mullvad VPN .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Mullvad VPN .deb"
    log "Downloaded Mullvad VPN file looks too small to be a .deb: $MULLVAD_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$MULLVAD_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Mullvad VPN .deb (not an ar archive)")
    record_status "FAIL" "download Mullvad VPN .deb"
    log "Downloaded Mullvad VPN file is not a .deb ar archive: $MULLVAD_DEB"
    return 0
  fi

  if [ ! -s "$MULLVAD_SIG" ]; then
    FAILURES+=("download Mullvad VPN signature (empty file)")
    record_status "FAIL" "download Mullvad VPN signature"
    log "Downloaded Mullvad VPN signature is empty: $MULLVAD_SIG"
    return 0
  fi

  actual_hash="$(sha256sum "$MULLVAD_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$MULLVAD_SHA256" ]; then
    FAILURES+=("verify Mullvad VPN checksum")
    record_status "FAIL" "verify Mullvad VPN checksum"
    log "Mullvad VPN SHA-256 mismatch (expected $MULLVAD_SHA256, got $actual_hash)"
    return 0
  fi

  if ! verify_mullvad_signature; then
    FAILURES+=("verify Mullvad VPN GPG signature")
    record_status "FAIL" "verify Mullvad VPN GPG signature"
    return 0
  fi

  log "Verified Mullvad VPN .deb ($file_size bytes); extracting to $MULLVAD_INSTALL_DIR"

  run_step "install Mullvad VPN" install_mullvad_files
}

resolve_appimagelauncher_url() {
  local json="$STATE_DIR/appimagelauncher-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/TheAssassin/AppImageLauncher/releases/latest \
        --jq '.assets[] | select(.name | test("^appimagelauncher-lite-.*-x86_64\\.AppImage$")) | "\(.browser_download_url)\t\(.digest)"' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$APPIMAGELAUNCHER_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.startswith("appimagelauncher-lite-") and name.endswith("-x86_64.AppImage"):
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            print(asset["browser_download_url"] + "\t" + digest[7:])
        break
PY
      )"
    fi
    rm -f "$json"
  fi

  APPIMAGELAUNCHER_DOWNLOAD_URL="${parsed%%$'\t'*}"
  APPIMAGELAUNCHER_SHA256="${parsed#*$'\t'}"
  APPIMAGELAUNCHER_SHA256="${APPIMAGELAUNCHER_SHA256#sha256:}"

  case "$APPIMAGELAUNCHER_DOWNLOAD_URL" in
    https://github.com/TheAssassin/AppImageLauncher/releases/download/*/appimagelauncher-lite-*-x86_64.AppImage) ;;
    *)
      log "Could not resolve an AppImageLauncher x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$APPIMAGELAUNCHER_SHA256" ] || [ "$APPIMAGELAUNCHER_DOWNLOAD_URL" = "$APPIMAGELAUNCHER_SHA256" ]; then
    log "Could not parse the AppImageLauncher SHA-256 from GitHub releases"
    return 1
  fi

  log "AppImageLauncher AppImage: $APPIMAGELAUNCHER_DOWNLOAD_URL"
  return 0
}

download_appimagelauncher_appimage() {
  download_url_to_file "$APPIMAGELAUNCHER_DOWNLOAD" "$APPIMAGELAUNCHER_DOWNLOAD_URL"
}

install_appimagelauncher_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$APPIMAGELAUNCHER_INSTALL_DIR"
  sudo install -D -m 755 "$APPIMAGELAUNCHER_DOWNLOAD" "$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME"
  sudo chown -R "$owner:$group" "$APPIMAGELAUNCHER_INSTALL_DIR"
  sudo chmod u+rwX "$APPIMAGELAUNCHER_INSTALL_DIR" "$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME"
  sudo ln -sfn "$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME" /usr/local/bin/appimagelauncher

  sudo tee /usr/share/applications/appimagelauncher.desktop >/dev/null <<EOF
[Desktop Entry]
Name=AppImageLauncher
Comment=Integrate and run AppImage applications
Exec=$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME %U
Icon=appimagelauncher
Terminal=false
Type=Application
Categories=Utility;System;
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/appimagelauncher.desktop

  rm -f "$APPIMAGELAUNCHER_DOWNLOAD"
}

install_appimagelauncher() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_APPIMAGELAUNCHER" = true ]; then
    log "Skipping AppImageLauncher installation"
    record_status "SKIPPED" "AppImageLauncher"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve AppImageLauncher AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve AppImageLauncher AppImage"
    log "Skipping AppImageLauncher install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_appimagelauncher_url; then
    FAILURES+=("resolve AppImageLauncher x86_64 AppImage")
    record_status "FAIL" "resolve AppImageLauncher x86_64 AppImage"
    return 0
  fi

  run_step "download AppImageLauncher AppImage" download_appimagelauncher_appimage

  if [ ! -e "$APPIMAGELAUNCHER_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$APPIMAGELAUNCHER_DOWNLOAD" ]; then
    FAILURES+=("download AppImageLauncher AppImage (empty file)")
    record_status "FAIL" "download AppImageLauncher AppImage"
    log "Downloaded AppImageLauncher file is empty: $APPIMAGELAUNCHER_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$APPIMAGELAUNCHER_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download AppImageLauncher AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download AppImageLauncher AppImage"
    log "Downloaded AppImageLauncher file looks too small: $APPIMAGELAUNCHER_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$APPIMAGELAUNCHER_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download AppImageLauncher AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download AppImageLauncher AppImage"
    log "Downloaded AppImageLauncher file is not an ELF AppImage: $APPIMAGELAUNCHER_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha256sum "$APPIMAGELAUNCHER_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$APPIMAGELAUNCHER_SHA256" ]; then
    FAILURES+=("verify AppImageLauncher checksum")
    record_status "FAIL" "verify AppImageLauncher checksum"
    log "AppImageLauncher SHA-256 mismatch (expected $APPIMAGELAUNCHER_SHA256, got $actual_hash)"
    return 0
  fi

  chmod 700 "$APPIMAGELAUNCHER_DOWNLOAD"
  log "Verified AppImageLauncher AppImage ($file_size bytes); installing to $APPIMAGELAUNCHER_INSTALL_DIR"

  run_step "install AppImageLauncher AppImage" install_appimagelauncher_files
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

download_cursor_api_json() {
  download_url_to_file "$CURSOR_API_JSON" "$CURSOR_DOWNLOAD_API_URL"
}

# Match linux/x64 AppImage only (not arm64, not .deb/.rpm).
parse_cursor_appimage_url() {
  CURSOR_DOWNLOAD_URL="$(awk '
    /"downloadUrl":/ && /linux\/x64\/Cursor-.*-x86_64\.AppImage/ {
      if (match($0, /https:[^"]+/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$CURSOR_API_JSON")"

  case "$CURSOR_DOWNLOAD_URL" in
    https://downloads.cursor.com/production/*/linux/x64/Cursor-*-x86_64.AppImage) ;;
    *)
      log "Could not parse a Cursor linux/x64 AppImage URL from $CURSOR_DOWNLOAD_API_URL"
      return 1
      ;;
  esac

  log "Cursor AppImage: $CURSOR_DOWNLOAD_URL"
  return 0
}

download_cursor_appimage() {
  download_url_to_file "$CURSOR_DOWNLOAD" "$CURSOR_DOWNLOAD_URL"
}

extract_cursor_icon() {
  local icon=""

  mkdir -p "$CURSOR_ICON_DIR"
  (
    cd "$CURSOR_ICON_DIR"
    "$CURSOR_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$CURSOR_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$CURSOR_DOWNLOAD" --appimage-extract 'usr/share/pixmaps/*' >/dev/null 2>&1 || true
    "$CURSOR_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$CURSOR_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/cursor.png
    log "Installed Cursor icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Cursor icon; desktop entry will use the cursor icon name"
  return 0
}

install_cursor_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$CURSOR_INSTALL_DIR"
  sudo install -D -m 755 "$CURSOR_DOWNLOAD" "$CURSOR_INSTALL_DIR/$CURSOR_APPIMAGE_NAME"
  # Cursor's updater replaces this AppImage in place. Root ownership would
  # block self-update, so the installing user owns /opt/cursor.
  sudo chown -R "$owner:$group" "$CURSOR_INSTALL_DIR"
  sudo chmod u+rwX "$CURSOR_INSTALL_DIR" "$CURSOR_INSTALL_DIR/$CURSOR_APPIMAGE_NAME"
  # Hyprland is not a desktop Electron auto-detects; pin gnome-libsecret
  # (same as chromium-flags.conf and Element on this machine).
  sudo tee /usr/local/bin/cursor >/dev/null <<EOF
#!/bin/bash
exec $CURSOR_INSTALL_DIR/$CURSOR_APPIMAGE_NAME --password-store=gnome-libsecret --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/cursor
  sudo tee /usr/share/applications/cursor.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Cursor
Comment=The AI Code Editor (nightly)
Exec=$CURSOR_INSTALL_DIR/$CURSOR_APPIMAGE_NAME --password-store=gnome-libsecret --no-sandbox %U
Icon=cursor
Terminal=false
Type=Application
Categories=Development;TextEditor;IDE;
StartupWMClass=Cursor
MimeType=x-scheme-handler/cursor;
EOF
  sudo chmod 644 /usr/share/applications/cursor.desktop
  extract_cursor_icon
  rm -rf "$CURSOR_ICON_DIR" "$CURSOR_DOWNLOAD" "$CURSOR_API_JSON"
}

install_cursor() {
  local file_size=0

  if [ "$SKIP_CURSOR" = true ]; then
    log "Skipping Cursor installation"
    record_status "SKIPPED" "Cursor"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Cursor AppImage (missing required command: curl or wget)")
    record_status "FAIL" "download Cursor AppImage"
    log "Skipping Cursor install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Cursor download API JSON" download_cursor_api_json

  if [ ! -e "$CURSOR_API_JSON" ]; then
    return 0
  fi

  if ! parse_cursor_appimage_url; then
    FAILURES+=("resolve Cursor linux/x64 AppImage URL")
    record_status "FAIL" "resolve Cursor linux/x64 AppImage URL"
    return 0
  fi

  run_step "download Cursor AppImage" download_cursor_appimage

  if [ ! -e "$CURSOR_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$CURSOR_DOWNLOAD" ]; then
    FAILURES+=("download Cursor AppImage (empty file)")
    record_status "FAIL" "download Cursor AppImage"
    log "Downloaded Cursor file is empty: $CURSOR_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$CURSOR_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Cursor AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Cursor AppImage"
    log "Downloaded Cursor file looks too small to be an AppImage: $CURSOR_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$CURSOR_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Cursor AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Cursor AppImage"
    log "Downloaded Cursor file is not an ELF AppImage: $CURSOR_DOWNLOAD"
    return 0
  fi

  chmod 700 "$CURSOR_DOWNLOAD"
  log "Verified Cursor AppImage ($file_size bytes); installing to $CURSOR_INSTALL_DIR"

  run_step "install Cursor AppImage" install_cursor_files
}

download_origin_cli_install_sh() {
  download_url_to_file "$ORIGIN_CLI_INSTALL_SH" "$ORIGIN_CLI_INSTALL_SH_URL"
}

# install.sh bakes stable and latest. Take the default stable linux-x64 glibc
# tarball (not musl, not arm64, not darwin).
parse_origin_cli_linux_x64() {
  local parsed

  parsed="$(awk '
    /^stable\)/ {
      in_stable = 1
      in_linux_x64 = 0
      next
    }
    in_stable && /^latest\)/ {
      in_stable = 0
      in_linux_x64 = 0
      next
    }
    in_stable && /linux-x64\)/ {
      in_linux_x64 = 1
      next
    }
    in_stable && in_linux_x64 && /darwin-|linux-arm64|^\*\)/ {
      in_linux_x64 = 0
      next
    }
    in_stable && in_linux_x64 && /url="/ {
      if (match($0, /https:[^"]+/)) {
        url = substr($0, RSTART, RLENGTH)
      }
      next
    }
    in_stable && in_linux_x64 && /sha="/ {
      if (match($0, /[a-f0-9]{64}/)) {
        print url "\t" substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$ORIGIN_CLI_INSTALL_SH")"

  ORIGIN_CLI_URL="${parsed%%$'\t'*}"
  ORIGIN_CLI_SHA256="${parsed#*$'\t'}"

  case "$ORIGIN_CLI_URL" in
    https://downloads.cursor.com/co/*/linux-x64/co.tar.gz) ;;
    *)
      log "Could not parse a Origin CLI linux-x64 tarball URL from $ORIGIN_CLI_INSTALL_SH_URL"
      return 1
      ;;
  esac

  if [ -z "$ORIGIN_CLI_SHA256" ] || [ "$ORIGIN_CLI_URL" = "$ORIGIN_CLI_SHA256" ]; then
    log "Could not parse the Origin CLI SHA-256 from $ORIGIN_CLI_INSTALL_SH_URL"
    return 1
  fi

  log "Origin CLI tarball: $ORIGIN_CLI_URL"
  return 0
}

download_origin_cli_tarball() {
  download_url_to_file "$ORIGIN_CLI_DOWNLOAD" "$ORIGIN_CLI_URL"
}

install_origin_cli_files() {
  rm -rf "$ORIGIN_CLI_EXTRACT"
  mkdir -p "$ORIGIN_CLI_EXTRACT"
  tar --no-same-owner -xzf "$ORIGIN_CLI_DOWNLOAD" -C "$ORIGIN_CLI_EXTRACT"

  if [ -L "$ORIGIN_CLI_EXTRACT/origin" ] || [ ! -f "$ORIGIN_CLI_EXTRACT/origin" ]; then
    log "Origin CLI tarball did not contain a regular origin binary"
    rm -rf "$ORIGIN_CLI_EXTRACT"
    return 1
  fi

  if [ "$(head -c 4 "$ORIGIN_CLI_EXTRACT/origin")" != $'\x7fELF' ]; then
    log "Origin CLI tarball origin member is not an ELF binary"
    rm -rf "$ORIGIN_CLI_EXTRACT"
    return 1
  fi

  sudo install -D -m 755 "$ORIGIN_CLI_EXTRACT/origin" "$ORIGIN_CLI_BIN"
  rm -rf "$ORIGIN_CLI_EXTRACT" "$ORIGIN_CLI_DOWNLOAD" "$ORIGIN_CLI_INSTALL_SH"
}

install_origin_cli() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_ORIGIN_CLI" = true ]; then
    log "Skipping Origin CLI installation"
    record_status "SKIPPED" "Origin CLI"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Origin CLI installer (missing required command: curl or wget)")
    record_status "FAIL" "download Origin CLI installer"
    log "Skipping Origin CLI install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v tar >/dev/null 2>&1; then
    FAILURES+=("extract Origin CLI tarball (missing required command: tar)")
    record_status "FAIL" "extract Origin CLI tarball"
    log "Skipping Origin CLI install because tar is not installed"
    return 0
  fi

  if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    FAILURES+=("install Origin CLI (musl libc is not supported)")
    record_status "FAIL" "install Origin CLI"
    log "Skipping Origin CLI install because musl libc is not supported (glibc only)"
    return 0
  fi

  run_step "download Origin CLI installer metadata" download_origin_cli_install_sh

  if [ ! -s "$ORIGIN_CLI_INSTALL_SH" ]; then
    if [ "$DRY_RUN" = true ]; then
      return 0
    fi
    return 0
  fi

  if ! parse_origin_cli_linux_x64; then
    FAILURES+=("parse Origin CLI linux-x64 tarball from installer")
    record_status "FAIL" "parse Origin CLI linux-x64 tarball from installer"
    return 0
  fi

  run_step "download Origin CLI tarball" download_origin_cli_tarball

  if [ ! -e "$ORIGIN_CLI_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$ORIGIN_CLI_DOWNLOAD" ]; then
    FAILURES+=("download Origin CLI tarball (empty file)")
    record_status "FAIL" "download Origin CLI tarball"
    log "Downloaded Origin CLI file is empty: $ORIGIN_CLI_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$ORIGIN_CLI_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Origin CLI tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Origin CLI tarball"
    log "Downloaded Origin CLI file looks too small: $ORIGIN_CLI_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  actual_hash="$(sha256sum "$ORIGIN_CLI_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$ORIGIN_CLI_SHA256" ]; then
    FAILURES+=("verify Origin CLI checksum")
    record_status "FAIL" "verify Origin CLI checksum"
    log "Origin CLI SHA-256 mismatch (expected $ORIGIN_CLI_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Origin CLI SHA-256; installing to $ORIGIN_CLI_BIN"

  run_step "install Origin CLI" install_origin_cli_files
}

download_spotify_metadata() {
  download_url_to_file "$SPOTIFY_PACKAGES" "$SPOTIFY_PACKAGES_URL"
  download_url_to_file "$SPOTIFY_INRELEASE" "$SPOTIFY_INRELEASE_URL"
  download_url_to_file "$SPOTIFY_GPG_KEY" "$SPOTIFY_GPG_KEY_URL"
}

verify_spotify_packages_signature() {
  local imported_fingerprint=""
  local status=""
  local expected_hash=""
  local actual_hash=""

  rm -rf "$SPOTIFY_GPG_HOME"
  mkdir -m 700 -p "$SPOTIFY_GPG_HOME"

  status="$(
    export GNUPGHOME="$SPOTIFY_GPG_HOME"
    gpg --batch --import "$SPOTIFY_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$SPOTIFY_GPG_FINGERPRINT" ]; then
    log "Spotify signing key fingerprint mismatch (expected $SPOTIFY_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$SPOTIFY_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$SPOTIFY_INRELEASE" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | awk -v fpr="$SPOTIFY_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Spotify InRelease GPG verification failed"
    return 1
  fi

  expected_hash="$(
    awk '
      $0 == "SHA256:" { in_sha = 1; next }
      in_sha && /^[A-Z]/ { in_sha = 0 }
      in_sha && $3 == "non-free/binary-amd64/Packages" { print $1; exit }
    ' "$SPOTIFY_INRELEASE"
  )"
  actual_hash="$(sha256sum "$SPOTIFY_PACKAGES" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    log "Spotify Packages SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 1
  fi

  log "Verified Spotify Packages GPG signature and SHA-256"
  return 0
}

parse_spotify_deb() {
  local parsed=""

  parsed="$(
    awk '
      $0 == "Package: spotify-client" { inpkg = 1; file = ""; hash = ""; next }
      inpkg && /^Package:/ { inpkg = 0 }
      inpkg && /^Filename:/ { file = $2 }
      inpkg && /^SHA256:/ { hash = $2 }
      END {
        if (file != "" && hash != "") {
          print file "\t" hash
        }
      }
    ' "$SPOTIFY_PACKAGES"
  )"

  SPOTIFY_DEB_URL="https://repository.spotify.com/${parsed%%$'\t'*}"
  SPOTIFY_SHA256="${parsed#*$'\t'}"

  case "$SPOTIFY_DEB_URL" in
    https://repository.spotify.com/pool/non-free/s/spotify-client/spotify-client_*_amd64.deb) ;;
    *)
      log "Could not parse a Spotify amd64 .deb URL from $SPOTIFY_PACKAGES_URL"
      return 1
      ;;
  esac

  if [ -z "$SPOTIFY_SHA256" ] || [ "$SPOTIFY_DEB_URL" = "$SPOTIFY_SHA256" ]; then
    log "Could not parse the Spotify SHA-256 from $SPOTIFY_PACKAGES_URL"
    return 1
  fi

  log "Spotify: $SPOTIFY_DEB_URL"
  return 0
}

download_spotify_deb() {
  download_url_to_file "$SPOTIFY_DEB" "$SPOTIFY_DEB_URL"
}

install_spotify_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/spotify-extract-$TIMESTAMP"
  local data=""
  local appdir=""
  local icon=""
  local candidate=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$SPOTIFY_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Spotify .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/usr/share/spotify/spotify" ]; then
    appdir="$work/usr/share/spotify"
  else
    while IFS= read -r candidate; do
      if [ "$(head -c 4 "$candidate")" = $'\x7fELF' ]; then
        appdir="$(dirname "$candidate")"
        break
      fi
    done < <(find "$work" -type f -name spotify)
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/spotify" ]; then
    log "Spotify .deb does not contain a spotify binary"
    return 1
  fi

  sudo mkdir -p "$SPOTIFY_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$SPOTIFY_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$SPOTIFY_INSTALL_DIR"
  sudo chmod u+rwX "$SPOTIFY_INSTALL_DIR"
  sudo chmod 755 "$SPOTIFY_INSTALL_DIR/spotify"
  sudo tee /usr/local/bin/spotify >/dev/null <<EOF
#!/bin/bash
exec $SPOTIFY_INSTALL_DIR/spotify --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/spotify

  sudo tee /usr/share/applications/spotify.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Spotify
GenericName=Music Player
Comment=Spotify streaming music client
Exec=/usr/local/bin/spotify %U
Icon=spotify-client
Terminal=false
Type=Application
Categories=Audio;Music;Player;AudioVideo;
MimeType=x-scheme-handler/spotify;
StartupWMClass=spotify
EOF
  sudo chmod 644 /usr/share/applications/spotify.desktop

  icon="$(find "$work" -type f \( -name 'spotify-linux-*.png' -o -name 'spotify-client.png' -o -name 'spotify.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/spotify-client.png
  fi

  rm -rf "$work" "$SPOTIFY_DEB" "$SPOTIFY_PACKAGES" "$SPOTIFY_INRELEASE" "$SPOTIFY_GPG_KEY" "$SPOTIFY_GPG_HOME"
}

install_spotify() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_SPOTIFY" = true ]; then
    log "Skipping Spotify installation"
    record_status "SKIPPED" "Spotify"
    return 0
  fi

  install_package_group pacman "Spotify runtime packages" SPOTIFY_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Spotify metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Spotify metadata"
    log "Skipping Spotify install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Spotify Packages signature (missing required command: gpg)")
    record_status "FAIL" "verify Spotify Packages signature"
    log "Skipping Spotify install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Spotify .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Spotify .deb"
    log "Skipping Spotify install because bsdtar is not installed"
    return 0
  fi

  run_step "download Spotify metadata" download_spotify_metadata

  if [ ! -s "$SPOTIFY_PACKAGES" ] || [ ! -s "$SPOTIFY_INRELEASE" ]; then
    return 0
  fi

  if ! verify_spotify_packages_signature; then
    FAILURES+=("verify Spotify Packages GPG signature")
    record_status "FAIL" "verify Spotify Packages GPG signature"
    return 0
  fi

  if ! parse_spotify_deb; then
    FAILURES+=("parse Spotify amd64 .deb URL")
    record_status "FAIL" "parse Spotify amd64 .deb URL"
    return 0
  fi

  run_step "download Spotify .deb" download_spotify_deb

  if [ ! -e "$SPOTIFY_DEB" ]; then
    return 0
  fi

  if [ ! -s "$SPOTIFY_DEB" ]; then
    FAILURES+=("download Spotify .deb (empty file)")
    record_status "FAIL" "download Spotify .deb"
    log "Downloaded Spotify file is empty: $SPOTIFY_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$SPOTIFY_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Spotify .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Spotify .deb"
    log "Downloaded Spotify file looks too small to be a .deb: $SPOTIFY_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$SPOTIFY_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Spotify .deb (not an ar archive)")
    record_status "FAIL" "download Spotify .deb"
    log "Downloaded Spotify file is not a .deb ar archive: $SPOTIFY_DEB"
    return 0
  fi

  actual_hash="$(sha256sum "$SPOTIFY_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$SPOTIFY_SHA256" ]; then
    FAILURES+=("verify Spotify checksum")
    record_status "FAIL" "verify Spotify checksum"
    log "Spotify SHA-256 mismatch (expected $SPOTIFY_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Spotify .deb ($file_size bytes); extracting to $SPOTIFY_INSTALL_DIR"

  run_step "install Spotify" install_spotify_files
}

resolve_pomotroid_url() {
  local json="$STATE_DIR/pomotroid-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/Splode/pomotroid/releases/latest \
        --jq '.assets[] | select(.name | test("^Pomotroid_.*_amd64\\.AppImage$")) | "\(.browser_download_url)\t\(.digest)"' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$POMOTROID_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if re.match(r"^Pomotroid_.*_amd64\.AppImage$", name):
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            digest = digest[7:]
        print(asset["browser_download_url"] + "\t" + digest)
        break
PY
      )"
    fi
    rm -f "$json"
  fi

  POMOTROID_DOWNLOAD_URL="${parsed%%$'\t'*}"
  POMOTROID_SHA256="${parsed#*$'\t'}"
  POMOTROID_SHA256="${POMOTROID_SHA256#sha256:}"

  case "$POMOTROID_DOWNLOAD_URL" in
    https://github.com/Splode/pomotroid/releases/download/*/Pomotroid_*_amd64.AppImage) ;;
    *)
      log "Could not resolve a Pomotroid amd64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$POMOTROID_SHA256" ] || [ "$POMOTROID_DOWNLOAD_URL" = "$POMOTROID_SHA256" ]; then
    log "Could not parse the Pomotroid SHA-256 from GitHub releases"
    return 1
  fi

  log "Pomotroid AppImage: $POMOTROID_DOWNLOAD_URL"
  return 0
}

download_pomotroid_appimage() {
  download_url_to_file "$POMOTROID_DOWNLOAD" "$POMOTROID_DOWNLOAD_URL"
}

extract_pomotroid_icon() {
  local icon=""

  mkdir -p "$POMOTROID_ICON_DIR"
  (
    cd "$POMOTROID_ICON_DIR"
    "$POMOTROID_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$POMOTROID_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$POMOTROID_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$POMOTROID_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/pomotroid.png
    log "Installed Pomotroid icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Pomotroid icon; desktop entry will use the pomotroid icon name"
  return 0
}

install_pomotroid_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$POMOTROID_INSTALL_DIR"
  sudo install -D -m 755 "$POMOTROID_DOWNLOAD" "$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME"
  sudo chown -R "$owner:$group" "$POMOTROID_INSTALL_DIR"
  sudo chmod u+rwX "$POMOTROID_INSTALL_DIR" "$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME"
  sudo ln -sfn "$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME" /usr/local/bin/pomotroid

  sudo tee /usr/share/applications/pomotroid.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Pomotroid
Comment=Simple and configurable Pomodoro timer
Exec=$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME --no-sandbox %U
Icon=pomotroid
Terminal=false
Type=Application
Categories=Office;Utility;
StartupWMClass=pomotroid
EOF
  sudo chmod 644 /usr/share/applications/pomotroid.desktop
  extract_pomotroid_icon
  rm -rf "$POMOTROID_ICON_DIR" "$POMOTROID_DOWNLOAD"
}

install_pomotroid() {
  local file_size=0
  local actual_hash=""

  if [ "$SKIP_POMOTROID" = true ]; then
    log "Skipping Pomotroid installation"
    record_status "SKIPPED" "Pomotroid"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Pomotroid AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Pomotroid AppImage"
    log "Skipping Pomotroid install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_pomotroid_url; then
    FAILURES+=("resolve Pomotroid amd64 AppImage")
    record_status "FAIL" "resolve Pomotroid amd64 AppImage"
    return 0
  fi

  run_step "download Pomotroid AppImage" download_pomotroid_appimage

  if [ ! -e "$POMOTROID_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$POMOTROID_DOWNLOAD" ]; then
    FAILURES+=("download Pomotroid AppImage (empty file)")
    record_status "FAIL" "download Pomotroid AppImage"
    log "Downloaded Pomotroid file is empty: $POMOTROID_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$POMOTROID_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Pomotroid AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Pomotroid AppImage"
    log "Downloaded Pomotroid file looks too small: $POMOTROID_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$POMOTROID_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Pomotroid AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Pomotroid AppImage"
    log "Downloaded Pomotroid file is not an ELF AppImage: $POMOTROID_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha256sum "$POMOTROID_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$POMOTROID_SHA256" ]; then
    FAILURES+=("verify Pomotroid checksum")
    record_status "FAIL" "verify Pomotroid checksum"
    log "Pomotroid SHA-256 mismatch (expected $POMOTROID_SHA256, got $actual_hash)"
    return 0
  fi

  chmod 700 "$POMOTROID_DOWNLOAD"
  log "Verified Pomotroid AppImage ($file_size bytes); installing to $POMOTROID_INSTALL_DIR"

  run_step "install Pomotroid AppImage" install_pomotroid_files
}

resolve_debtap_url() {
  local json="$STATE_DIR/debtap-releases-$TIMESTAMP.json"

  if command -v gh >/dev/null 2>&1; then
    DEBTAP_TARBALL_URL="$(gh api repos/helixarch/debtap/releases/latest --jq .tarball_url)"
  else
    download_url_to_file "$json" "$DEBTAP_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      DEBTAP_TARBALL_URL="$(
        python3 - "$json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("tarball_url") or "")
PY
      )"
    fi
    rm -f "$json"
  fi

  case "$DEBTAP_TARBALL_URL" in
    https://api.github.com/repos/helixarch/debtap/tarball/*) ;;
    *)
      log "Could not resolve a debtap source tarball from GitHub releases"
      return 1
      ;;
  esac

  log "debtap tarball: $DEBTAP_TARBALL_URL"
  return 0
}

download_debtap_tarball() {
  download_url_to_file "$DEBTAP_TARBALL" "$DEBTAP_TARBALL_URL"
}

install_debtap_files() {
  local script=""

  rm -rf "$DEBTAP_EXTRACT"
  mkdir -p "$DEBTAP_EXTRACT"
  bsdtar -C "$DEBTAP_EXTRACT" -xf "$DEBTAP_TARBALL"
  script="$(find "$DEBTAP_EXTRACT" -type f -name debtap | head -1)"
  if [ -z "$script" ] || [ ! -s "$script" ]; then
    log "debtap tarball does not contain a debtap script"
    return 1
  fi
  if ! grep -q '^#!/usr/bin/bash' "$script"; then
    log "debtap script is missing the expected bash shebang"
    return 1
  fi

  sudo install -D -m 755 "$script" "$DEBTAP_BIN"
  rm -rf "$DEBTAP_EXTRACT" "$DEBTAP_TARBALL"
}

install_debtap() {
  local file_size=0

  if [ "$SKIP_DEBTAP" = true ]; then
    log "Skipping debtap installation"
    record_status "SKIPPED" "debtap"
    return 0
  fi

  install_package_group pacman "debtap runtime packages" DEBTAP_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve debtap tarball (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve debtap tarball"
    log "Skipping debtap install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract debtap tarball (missing required command: bsdtar)")
    record_status "FAIL" "extract debtap tarball"
    log "Skipping debtap install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_debtap_url; then
    FAILURES+=("resolve debtap GitHub tarball")
    record_status "FAIL" "resolve debtap GitHub tarball"
    return 0
  fi

  run_step "download debtap tarball" download_debtap_tarball

  if [ ! -e "$DEBTAP_TARBALL" ]; then
    return 0
  fi

  if [ ! -s "$DEBTAP_TARBALL" ]; then
    FAILURES+=("download debtap tarball (empty file)")
    record_status "FAIL" "download debtap tarball"
    log "Downloaded debtap file is empty: $DEBTAP_TARBALL"
    return 0
  fi

  file_size="$(stat -c%s "$DEBTAP_TARBALL")"
  if [ "$file_size" -lt 10000 ]; then
    FAILURES+=("download debtap tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download debtap tarball"
    log "Downloaded debtap file looks too small: $DEBTAP_TARBALL ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 2 "$DEBTAP_TARBALL")" != $'\x1f\x8b' ]; then
    FAILURES+=("download debtap tarball (not a gzip archive)")
    record_status "FAIL" "download debtap tarball"
    log "Downloaded debtap file is not a gzip archive: $DEBTAP_TARBALL"
    return 0
  fi

  log "Verified debtap tarball ($file_size bytes); installing to $DEBTAP_BIN"

  run_step "install debtap" install_debtap_files
}

download_grayjay_zip() {
  download_url_to_file "$GRAYJAY_DOWNLOAD" "$GRAYJAY_DOWNLOAD_URL"
}

install_grayjay_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/grayjay-extract-$TIMESTAMP"
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$GRAYJAY_DOWNLOAD"

  if [ -x "$work/Grayjay" ]; then
    appdir="$work"
  else
    appdir="$(find "$work" -type f -name Grayjay -printf '%h\n' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/Grayjay" ]; then
    log "Grayjay zip does not contain a Grayjay launcher"
    return 1
  fi

  if [ "$(head -c 4 "$appdir/Grayjay")" != $'\x7fELF' ]; then
    log "Grayjay launcher is not an ELF binary"
    return 1
  fi

  # Portable mode stores data next to the binary. Drop it so user data goes
  # to XDG dirs while the user-owned /opt tree stays free for in-app updates.
  rm -f "$appdir/Portable"

  sudo mkdir -p "$GRAYJAY_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$GRAYJAY_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$GRAYJAY_INSTALL_DIR"
  sudo chmod u+rwX "$GRAYJAY_INSTALL_DIR"
  sudo chmod 755 "$GRAYJAY_INSTALL_DIR/Grayjay"
  # CEF resolves resources from cwd; chrome-sandbox cannot be setuid on a
  # user-owned tree.
  sudo tee /usr/local/bin/grayjay >/dev/null <<EOF
#!/bin/bash
cd "$GRAYJAY_INSTALL_DIR" || exit 1
exec ./Grayjay --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/grayjay

  sudo tee /usr/share/applications/grayjay.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Grayjay
Comment=Follow creators, not platforms
GenericName=Media Aggregator
Exec=/usr/local/bin/grayjay %U
Icon=grayjay
Terminal=false
Type=Application
Categories=AudioVideo;Video;Network;
StartupWMClass=Grayjay
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/grayjay.desktop

  icon="$(find "$appdir" -type f \( -name 'grayjay.png' -o -name 'Grayjay.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/grayjay.png
  fi

  rm -rf "$work" "$GRAYJAY_DOWNLOAD"
}

install_grayjay() {
  local file_size=0

  if [ "$SKIP_GRAYJAY" = true ]; then
    log "Skipping Grayjay installation"
    record_status "SKIPPED" "Grayjay"
    return 0
  fi

  install_package_group pacman "Grayjay runtime packages" GRAYJAY_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Grayjay zip (missing required command: curl or wget)")
    record_status "FAIL" "download Grayjay zip"
    log "Skipping Grayjay install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Grayjay zip (missing required command: bsdtar)")
    record_status "FAIL" "extract Grayjay zip"
    log "Skipping Grayjay install because bsdtar is not installed"
    return 0
  fi

  run_step "download Grayjay zip" download_grayjay_zip

  if [ ! -e "$GRAYJAY_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$GRAYJAY_DOWNLOAD" ]; then
    FAILURES+=("download Grayjay zip (empty file)")
    record_status "FAIL" "download Grayjay zip"
    log "Downloaded Grayjay file is empty: $GRAYJAY_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$GRAYJAY_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Grayjay zip (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Grayjay zip"
    log "Downloaded Grayjay file looks too small: $GRAYJAY_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 2 "$GRAYJAY_DOWNLOAD")" != $'PK' ]; then
    FAILURES+=("download Grayjay zip (not a zip archive)")
    record_status "FAIL" "download Grayjay zip"
    log "Downloaded Grayjay file is not a zip archive: $GRAYJAY_DOWNLOAD"
    return 0
  fi

  log "Verified Grayjay zip ($file_size bytes); extracting to $GRAYJAY_INSTALL_DIR"

  run_step "install Grayjay" install_grayjay_files
}

download_slack_index() {
  download_url_to_file "$SLACK_INDEX" "$SLACK_DOWNLOADS_URL"
}

# The instructions page lists linux/x64 rpm and amd64 .deb CDN URLs. Match the
# amd64 .deb path exactly (not el8 rpm, not arm64).
parse_slack_deb() {
  local url=""

  url="$(
    grep -oE 'https://downloads\.slack-edge\.com/desktop-releases/linux/x64/[0-9.]+/slack-desktop-[0-9.]+-amd64\.deb' "$SLACK_INDEX" \
      | head -1
  )"

  case "$url" in
    https://downloads.slack-edge.com/desktop-releases/linux/x64/*/slack-desktop-*-amd64.deb) ;;
    *)
      log "Could not parse a Slack linux/x64 amd64 .deb URL from $SLACK_DOWNLOADS_URL"
      return 1
      ;;
  esac

  SLACK_DEB_URL="$url"
  log "Slack desktop: $SLACK_DEB_URL"
  return 0
}

download_slack_files() {
  download_url_to_file "$SLACK_DEB" "$SLACK_DEB_URL"
  download_url_to_file "$SLACK_SHA256_FILE" "${SLACK_DEB_URL}.sha256"
}

install_slack_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/slack-extract-$TIMESTAMP"
  local data=""
  local appdir=""
  local icon=""
  local candidate=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$SLACK_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Slack .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/usr/lib/slack/slack" ]; then
    appdir="$work/usr/lib/slack"
  else
    while IFS= read -r candidate; do
      if [ "$(head -c 4 "$candidate")" = $'\x7fELF' ]; then
        appdir="$(dirname "$candidate")"
        break
      fi
    done < <(find "$work" -type f -name slack)
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/slack" ]; then
    log "Slack .deb does not contain a slack binary"
    return 1
  fi

  sudo mkdir -p "$SLACK_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$SLACK_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$SLACK_INSTALL_DIR"
  sudo chmod u+rwX "$SLACK_INSTALL_DIR"
  sudo chmod 755 "$SLACK_INSTALL_DIR/slack"
  sudo tee /usr/local/bin/slack >/dev/null <<EOF
#!/bin/bash
exec $SLACK_INSTALL_DIR/slack --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/slack

  sudo tee /usr/share/applications/slack.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Slack
Comment=Slack Desktop
GenericName=Slack Client for Linux
Exec=/usr/local/bin/slack %U
Icon=slack
Terminal=false
Type=Application
StartupNotify=true
Categories=Network;InstantMessaging;
MimeType=x-scheme-handler/slack;
StartupWMClass=Slack
EOF
  sudo chmod 644 /usr/share/applications/slack.desktop

  icon="$(find "$work" -type f \( -name 'slack.png' -o -name 'slack-desktop.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/slack.png
  fi

  rm -rf "$work" "$SLACK_DEB" "$SLACK_SHA256_FILE" "$SLACK_INDEX"
}

install_slack() {
  local file_size=0
  local expected_hash=""
  local actual_hash=""

  if [ "$SKIP_SLACK" = true ]; then
    log "Skipping Slack installation"
    record_status "SKIPPED" "Slack"
    return 0
  fi

  install_package_group pacman "Slack runtime packages" SLACK_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Slack metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Slack metadata"
    log "Skipping Slack install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Slack .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Slack .deb"
    log "Skipping Slack install because bsdtar is not installed"
    return 0
  fi

  run_step "download Slack download page" download_slack_index

  if [ ! -s "$SLACK_INDEX" ]; then
    return 0
  fi

  if ! parse_slack_deb; then
    FAILURES+=("parse Slack linux/x64 amd64 .deb URL")
    record_status "FAIL" "parse Slack linux/x64 amd64 .deb URL"
    return 0
  fi

  run_step "download Slack .deb" download_slack_files

  if [ ! -e "$SLACK_DEB" ]; then
    return 0
  fi

  if [ ! -s "$SLACK_DEB" ]; then
    FAILURES+=("download Slack .deb (empty file)")
    record_status "FAIL" "download Slack .deb"
    log "Downloaded Slack file is empty: $SLACK_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$SLACK_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Slack .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Slack .deb"
    log "Downloaded Slack file looks too small to be a .deb: $SLACK_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$SLACK_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Slack .deb (not an ar archive)")
    record_status "FAIL" "download Slack .deb"
    log "Downloaded Slack file is not a .deb ar archive: $SLACK_DEB"
    return 0
  fi

  if [ ! -s "$SLACK_SHA256_FILE" ]; then
    FAILURES+=("download Slack checksum (empty file)")
    record_status "FAIL" "download Slack checksum"
    log "Downloaded Slack checksum file is empty: $SLACK_SHA256_FILE"
    return 0
  fi

  expected_hash="$(awk '{ print $1 }' "$SLACK_SHA256_FILE")"
  actual_hash="$(sha256sum "$SLACK_DEB" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    FAILURES+=("verify Slack checksum")
    record_status "FAIL" "verify Slack checksum"
    log "Slack SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 0
  fi

  log "Verified Slack .deb SHA-256; extracting to $SLACK_INSTALL_DIR"

  run_step "install Slack" install_slack_files
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
      --skip-proton-bridge)
        SKIP_PROTON_BRIDGE=true
        ;;
      --skip-betterbird)
        SKIP_BETTERBIRD=true
        ;;
      --skip-zotero)
        SKIP_ZOTERO=true
        ;;
      --skip-element)
        SKIP_ELEMENT=true
        ;;
      --skip-dbeaver)
        SKIP_DBEAVER=true
        ;;
      --skip-appimagelauncher)
        SKIP_APPIMAGELAUNCHER=true
        ;;
      --skip-mullvad)
        SKIP_MULLVAD=true
        ;;
      --skip-brave-origin-nightly)
        SKIP_BRAVE_ORIGIN_NIGHTLY=true
        ;;
      --skip-cursor)
        SKIP_CURSOR=true
        ;;
      --skip-origin-cli)
        SKIP_ORIGIN_CLI=true
        ;;
      --skip-spotify)
        SKIP_SPOTIFY=true
        ;;
      --skip-pomotroid)
        SKIP_POMOTROID=true
        ;;
      --skip-debtap)
        SKIP_DEBTAP=true
        ;;
      --skip-grayjay)
        SKIP_GRAYJAY=true
        ;;
      --skip-slack)
        SKIP_SLACK=true
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
  install_package_group pacman "Fonts and prompt" PACMAN_FONT_PACKAGES
  install_package_group pacman "Gaming packages" PACMAN_GAMING_PACKAGES
  install_package_group yay "AUR packages" AUR_PACKAGES
  install_omf
  install_appimagelauncher
  install_remnote
  install_todoist
  install_nextcloud
  install_proton_drive
  install_pass_cli
  install_proton_pass
  install_proton_bridge
  install_betterbird
  install_zotero
  install_element
  install_dbeaver
  install_mullvad
  install_brave_origin_nightly
  install_cursor
  install_origin_cli
  install_spotify
  install_pomotroid
  install_debtap
  install_grayjay
  install_slack

  print_summary

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    exit 1
  fi
}

main "$@"

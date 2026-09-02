register_package proton-bridge 150 "Proton Mail Bridge" install_proton_bridge

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

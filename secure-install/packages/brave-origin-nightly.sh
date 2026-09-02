register_package brave-origin-nightly 210 "Brave Origin Nightly" install_brave_origin_nightly

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

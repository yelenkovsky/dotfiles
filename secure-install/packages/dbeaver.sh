register_package dbeaver 190 "DBeaver CE" install_dbeaver

# Community Edition linux-x86_64 tarball via the unversioned /files/latest URL.
DBEAVER_DOWNLOAD_URL="https://dbeaver.io/files/dbeaver-ce-latest-linux-x86_64.tar.gz"
DBEAVER_SHA256_URL="https://dbeaver.io/files/checksum/dbeaver-ce-latest-linux-x86_64.tar.gz.sha256"
DBEAVER_INSTALL_DIR="/opt/dbeaver"
DBEAVER_DOWNLOAD="$STATE_DIR/dbeaver-$TIMESTAMP.tar.gz"
DBEAVER_SHA256_FILE="$STATE_DIR/dbeaver-$TIMESTAMP.sha256"

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

register_package zotero 170 "Zotero" install_zotero

# Official linux-x86_64 glibc tarball via the unversioned release redirect.
# Zotero does not publish SHA-256 next to the file; verify xz magic + size.
ZOTERO_DOWNLOAD_URL="https://www.zotero.org/download/client/dl?channel=release&platform=linux-x86_64"
ZOTERO_INSTALL_DIR="/opt/zotero"
ZOTERO_DOWNLOAD="$STATE_DIR/zotero-$TIMESTAMP.tar.xz"

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

register_package remnote 90 "RemNote AppImage" install_remnote

REMNOTE_DOWNLOAD_URL="https://backend.remnote.com/desktop/linux"
# RemNote's download endpoint rejects non-browser clients with 403. curl/wget
# send this so the script can follow the redirect to the AppImage. No extra
# setup is required at install time.
REMNOTE_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
REMNOTE_INSTALL_DIR="/opt/remnote"
REMNOTE_APPIMAGE_NAME="RemNote.AppImage"
REMNOTE_DOWNLOAD="$STATE_DIR/RemNote-$TIMESTAMP.AppImage"
REMNOTE_ICON_DIR="$STATE_DIR/remnote-icon-$TIMESTAMP"

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

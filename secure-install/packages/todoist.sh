register_package todoist 100 "Todoist AppImage" install_todoist

TODOIST_DOWNLOAD_URL="https://todoist.com/linux_app/appimage"
TODOIST_INSTALL_DIR="/opt/todoist"
TODOIST_APPIMAGE_NAME="Todoist.AppImage"
TODOIST_DOWNLOAD="$STATE_DIR/Todoist-$TIMESTAMP.AppImage"
TODOIST_ICON_DIR="$STATE_DIR/todoist-icon-$TIMESTAMP"

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

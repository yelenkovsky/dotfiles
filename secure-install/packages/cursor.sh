register_package cursor 220 "Cursor nightly (dev) AppImage" install_cursor

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

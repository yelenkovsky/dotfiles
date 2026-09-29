register_package grok-bot 225 "Grok Bot desktop AppImage" install_grok_bot

# Official linux/x64 glibc AppImage from the stable release feed. downloadUrl
# is the AppImage; debUrl and rpmUrl on the same feed are ignored. Cursor does
# not publish SHA-256 next to the file; verify ELF + size instead.
GROK_BOT_DOWNLOAD_API_URL="https://api2.cursor.sh/updates/api/download/stable/linux-x64/sand"
GROK_BOT_API_JSON="$STATE_DIR/grok-bot-download-$TIMESTAMP.json"
GROK_BOT_INSTALL_DIR="/opt/grok-bot"
GROK_BOT_APPIMAGE_NAME="Grok_Bot.AppImage"
GROK_BOT_DOWNLOAD="$STATE_DIR/grok-bot-$TIMESTAMP.AppImage"
GROK_BOT_ICON_DIR="$STATE_DIR/grok-bot-icon-$TIMESTAMP"
GROK_BOT_DOWNLOAD_URL=""
GROK_BOT_RUNTIME_PACKAGES=(
  alsa-lib
  at-spi2-core
  gnome-keyring
  gtk3
  libnotify
  libsecret
  libxss
  libxtst
  mesa
  nss
  xdg-utils
)

download_grok_bot_api_json() {
  download_url_to_file "$GROK_BOT_API_JSON" "$GROK_BOT_DOWNLOAD_API_URL"
}

# Match linux/x64 AppImage only (not arm64, not .deb/.rpm).
parse_grok_bot_appimage_url() {
  GROK_BOT_DOWNLOAD_URL="$(awk '
    match($0, /"downloadUrl":"https:[^"]+\/linux\/x64\/Grok_Bot_[^"]+\.AppImage"/) {
      url = substr($0, RSTART, RLENGTH)
      sub(/^"downloadUrl":"/, "", url)
      sub(/"$/, "", url)
      print url
      exit
    }
  ' "$GROK_BOT_API_JSON")"

  case "$GROK_BOT_DOWNLOAD_URL" in
    https://downloads.cursor.com/grokbot/stable/*/linux/x64/Grok_Bot_*.AppImage) ;;
    *)
      log "Could not parse a Grok Bot linux/x64 AppImage URL from $GROK_BOT_DOWNLOAD_API_URL"
      return 1
      ;;
  esac

  log "Grok Bot AppImage: $GROK_BOT_DOWNLOAD_URL"
  return 0
}

download_grok_bot_appimage() {
  download_url_to_file "$GROK_BOT_DOWNLOAD" "$GROK_BOT_DOWNLOAD_URL"
}

extract_grok_bot_icon() {
  local icon=""

  mkdir -p "$GROK_BOT_ICON_DIR"
  (
    cd "$GROK_BOT_ICON_DIR"
    "$GROK_BOT_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$GROK_BOT_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$GROK_BOT_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$GROK_BOT_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/grok-bot.png
    log "Installed Grok Bot icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Grok Bot icon; desktop entry will use the grok-bot icon name"
  return 0
}

install_grok_bot_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  # Earlier installs unpacked the .deb into this directory. Replace that tree
  # with the AppImage so the old binary is not left beside it.
  sudo rm -rf "$GROK_BOT_INSTALL_DIR"
  sudo install -D -m 755 "$GROK_BOT_DOWNLOAD" "$GROK_BOT_INSTALL_DIR/$GROK_BOT_APPIMAGE_NAME"
  # The updater replaces this AppImage in place. Root ownership would block
  # self-update, so the installing user owns /opt/grok-bot.
  sudo chown -R "$owner:$group" "$GROK_BOT_INSTALL_DIR"
  sudo chmod u+rwX "$GROK_BOT_INSTALL_DIR" "$GROK_BOT_INSTALL_DIR/$GROK_BOT_APPIMAGE_NAME"
  # Hyprland is not a desktop Electron auto-detects; pin gnome-libsecret
  # (same as chromium-flags.conf and Cursor on this machine). chrome-sandbox
  # cannot be setuid on a user-owned tree. Remove any previous path first so
  # tee cannot follow a symlink into the AppImage.
  sudo rm -f /usr/local/bin/grok-bot
  sudo tee /usr/local/bin/grok-bot >/dev/null <<EOF
#!/bin/bash
exec $GROK_BOT_INSTALL_DIR/$GROK_BOT_APPIMAGE_NAME --password-store=gnome-libsecret --no-sandbox --ozone-platform-hint=auto "\$@"
EOF
  sudo chmod 755 /usr/local/bin/grok-bot

  sudo tee /usr/share/applications/grok-bot.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Grok Bot
Comment=Grok Bot desktop agent
Exec=/usr/local/bin/grok-bot %U
Icon=grok-bot
Terminal=false
Type=Application
Categories=Development;Network;
MimeType=x-scheme-handler/grokbot;x-scheme-handler/sand;
StartupWMClass=Grok Bot
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/grok-bot.desktop
  extract_grok_bot_icon
  rm -rf "$GROK_BOT_ICON_DIR" "$GROK_BOT_DOWNLOAD" "$GROK_BOT_API_JSON"
}

install_grok_bot() {
  local file_size=0

  install_package_group pacman "Grok Bot runtime packages" GROK_BOT_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Grok Bot AppImage (missing required command: curl or wget)")
    record_status "FAIL" "download Grok Bot AppImage"
    log "Skipping Grok Bot install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Grok Bot release feed" download_grok_bot_api_json

  if [ ! -s "$GROK_BOT_API_JSON" ]; then
    return 0
  fi

  if ! parse_grok_bot_appimage_url; then
    FAILURES+=("resolve Grok Bot linux/x64 AppImage URL")
    record_status "FAIL" "resolve Grok Bot linux/x64 AppImage URL"
    return 0
  fi

  run_step "download Grok Bot AppImage" download_grok_bot_appimage

  if [ ! -e "$GROK_BOT_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$GROK_BOT_DOWNLOAD" ]; then
    FAILURES+=("download Grok Bot AppImage (empty file)")
    record_status "FAIL" "download Grok Bot AppImage"
    log "Downloaded Grok Bot file is empty: $GROK_BOT_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$GROK_BOT_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Grok Bot AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Grok Bot AppImage"
    log "Downloaded Grok Bot file looks too small to be an AppImage: $GROK_BOT_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$GROK_BOT_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Grok Bot AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Grok Bot AppImage"
    log "Downloaded Grok Bot file is not an ELF AppImage: $GROK_BOT_DOWNLOAD"
    return 0
  fi

  chmod 700 "$GROK_BOT_DOWNLOAD"
  log "Verified Grok Bot AppImage ($file_size bytes); installing to $GROK_BOT_INSTALL_DIR"

  run_step "install Grok Bot AppImage" install_grok_bot_files
}

register_package grayjay 270 "Grayjay" install_grayjay

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
register_update_check grayjay "$GRAYJAY_DOWNLOAD"
register_changelog grayjay 'https://gitlab.futo.org/videostreaming/Grayjay.Desktop/-/tags'

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

  # Stage, swap and only then drop the old tree, so a failed copy keeps the
  # working install and a running app never sees a half-copied directory.
  replace_install_tree "$appdir" "$GRAYJAY_INSTALL_DIR" "$owner:$group" || return 1
  sudo chmod 755 "$GRAYJAY_INSTALL_DIR/Grayjay" || return 1
  # CEF resolves resources from cwd; chrome-sandbox cannot be setuid on a
  # user-owned tree. Grayjay passes its own arguments on to CEF, so extra
  # Chromium flags come from ~/.config/grayjay-flags.conf, one per line (e.g.
  # --disable-accelerated-video-decode: on the AMD iGPU decoded frames fail to
  # import into GL and videos play sound only).
  sudo tee /usr/local/bin/grayjay >/dev/null <<EOF || return 1
#!/bin/bash
flags_file="\${XDG_CONFIG_HOME:-\$HOME/.config}/grayjay-flags.conf"
flags=()
if [ -f "\$flags_file" ]; then
  while IFS= read -r line; do
    line="\${line%%#*}"
    read -r -a words <<<"\$line"
    flags+=("\${words[@]}")
  done <"\$flags_file"
fi
cd "$GRAYJAY_INSTALL_DIR" || exit 1
exec ./Grayjay --no-sandbox "\${flags[@]}" "\$@"
EOF
  sudo chmod 755 /usr/local/bin/grayjay || return 1

  sudo tee /usr/share/applications/grayjay.desktop >/dev/null <<EOF || return 1
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
  sudo chmod 644 /usr/share/applications/grayjay.desktop || return 1

  icon="$(find "$appdir" -type f \( -name 'grayjay.png' -o -name 'Grayjay.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/grayjay.png || return 1
  fi

  rm -rf "$work" "$GRAYJAY_DOWNLOAD"
}

install_grayjay() {
  local file_size=0

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

  close_running_app --relaunch /usr/local/bin/grayjay "Grayjay" "$GRAYJAY_INSTALL_DIR"

  run_step "install Grayjay" install_grayjay_files
}

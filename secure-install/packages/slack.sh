register_package slack 280 "Slack" install_slack

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

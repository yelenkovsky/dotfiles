register_package betterbird 160 "Betterbird" install_betterbird

BETTERBIRD_GETLOC_URL="https://www.betterbird.eu/downloads/getloc.php?os=linux&lang=en-US&version=release"
BETTERBIRD_SHA256_DIR="https://www.betterbird.eu/downloads"
BETTERBIRD_INSTALL_DIR="/opt/betterbird"
BETTERBIRD_DOWNLOAD="$STATE_DIR/betterbird-$TIMESTAMP.tar.xz"
BETTERBIRD_SHA256_FILE="$STATE_DIR/betterbird-$TIMESTAMP.sha256"
BETTERBIRD_DOWNLOAD_URL=""
BETTERBIRD_SHA256=""

resolve_betterbird_download() {
  local filename=""
  local series=""

  BETTERBIRD_DOWNLOAD_URL="$(tr -d '\r\n' < <(curl -fsSL "$BETTERBIRD_GETLOC_URL" 2>/dev/null || wget -qO- "$BETTERBIRD_GETLOC_URL"))"

  case "$BETTERBIRD_DOWNLOAD_URL" in
    https://www.betterbird.eu/downloads/*/betterbird-*.en-US.linux-x86_64.tar.xz) ;;
    *)
      log "Could not resolve a Betterbird linux-x86_64 tarball from $BETTERBIRD_GETLOC_URL"
      return 1
      ;;
  esac

  filename="${BETTERBIRD_DOWNLOAD_URL##*/}"
  series="$(printf '%s\n' "$filename" | sed -n 's/^betterbird-\([0-9][0-9]*\).*/\1/p')"
  if [ -z "$series" ]; then
    log "Could not parse Betterbird ESR series from $filename"
    return 1
  fi

  download_url_to_file "$BETTERBIRD_SHA256_FILE" "$BETTERBIRD_SHA256_DIR/sha256-${series}.txt"
  BETTERBIRD_SHA256="$(
    awk -v name="$filename" '
      {
        file = $2
        sub(/^\*/, "", file)
        if (file == name) {
          print $1
          exit
        }
      }
    ' "$BETTERBIRD_SHA256_FILE"
  )"

  if [ -z "$BETTERBIRD_SHA256" ]; then
    log "No SHA-256 for $filename in sha256-${series}.txt"
    return 1
  fi

  log "Betterbird tarball: $BETTERBIRD_DOWNLOAD_URL"
  return 0
}

download_betterbird_tarball() {
  download_url_to_file "$BETTERBIRD_DOWNLOAD" "$BETTERBIRD_DOWNLOAD_URL"
}

install_betterbird_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/betterbird-extract-$TIMESTAMP"
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$BETTERBIRD_DOWNLOAD"

  if [ -x "$work/betterbird/betterbird" ]; then
    appdir="$work/betterbird"
  else
    appdir="$(find "$work" -type f -name betterbird -printf '%h\n' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/betterbird" ]; then
    log "Betterbird tarball does not contain a betterbird binary"
    return 1
  fi

  sudo mkdir -p "$BETTERBIRD_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$BETTERBIRD_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$BETTERBIRD_INSTALL_DIR"
  sudo chmod u+rwX "$BETTERBIRD_INSTALL_DIR"
  sudo chmod 755 "$BETTERBIRD_INSTALL_DIR/betterbird"
  sudo ln -sfn "$BETTERBIRD_INSTALL_DIR/betterbird" /usr/local/bin/betterbird

  sudo tee /usr/share/applications/betterbird.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Betterbird
GenericName=Mail Client
Comment=Betterbird mail and news client
Exec=$BETTERBIRD_INSTALL_DIR/betterbird %u
Icon=betterbird
Terminal=false
Type=Application
Categories=Network;Email;News;
MimeType=x-scheme-handler/mailto;x-scheme-handler/mid;message/rfc822;
StartupWMClass=betterbird
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/betterbird.desktop

  icon="$(find "$appdir" -type f \( -name 'default128.png' -o -name 'betterbird.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/betterbird.png
  fi

  rm -rf "$work" "$BETTERBIRD_DOWNLOAD" "$BETTERBIRD_SHA256_FILE"
}

install_betterbird() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("resolve Betterbird download (missing required command: curl or wget)")
    record_status "FAIL" "resolve Betterbird download"
    log "Skipping Betterbird install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Betterbird tarball (missing required command: bsdtar)")
    record_status "FAIL" "extract Betterbird tarball"
    log "Skipping Betterbird install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_betterbird_download; then
    FAILURES+=("resolve Betterbird linux-x86_64 tarball")
    record_status "FAIL" "resolve Betterbird linux-x86_64 tarball"
    return 0
  fi

  run_step "download Betterbird tarball" download_betterbird_tarball

  if [ ! -e "$BETTERBIRD_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$BETTERBIRD_DOWNLOAD" ]; then
    FAILURES+=("download Betterbird tarball (empty file)")
    record_status "FAIL" "download Betterbird tarball"
    log "Downloaded Betterbird file is empty: $BETTERBIRD_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$BETTERBIRD_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Betterbird tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Betterbird tarball"
    log "Downloaded Betterbird file looks too small: $BETTERBIRD_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  actual_hash="$(sha256sum "$BETTERBIRD_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$BETTERBIRD_SHA256" ]; then
    FAILURES+=("verify Betterbird checksum")
    record_status "FAIL" "verify Betterbird checksum"
    log "Betterbird SHA-256 mismatch (expected $BETTERBIRD_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Betterbird SHA-256; extracting to $BETTERBIRD_INSTALL_DIR"

  run_step "install Betterbird" install_betterbird_files
}

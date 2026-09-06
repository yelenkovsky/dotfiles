register_package audiorelay 290 "AudioRelay desktop" install_audiorelay

# Official linux x86_64 glibc tarball from the unversioned downloads API.
# linuxArchive is the .tar.gz; linuxDeb is Debian-only and must not be used.
# AudioRelay does not publish SHA-256 next to the file; verify gzip magic + size.
AUDIORELAY_DOWNLOADS_API="https://api.audiorelay.net/downloads"
AUDIORELAY_INSTALL_DIR="/opt/audiorelay"
AUDIORELAY_DOWNLOAD="$STATE_DIR/audiorelay-$TIMESTAMP.tar.gz"
AUDIORELAY_API_JSON="$STATE_DIR/audiorelay-downloads-$TIMESTAMP.json"
AUDIORELAY_DOWNLOAD_URL=""

resolve_audiorelay_download() {
  download_url_to_file "$AUDIORELAY_API_JSON" "$AUDIORELAY_DOWNLOADS_API"

  AUDIORELAY_DOWNLOAD_URL="$(
    python3 - "$AUDIORELAY_API_JSON" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

url = (data.get("linuxArchive") or {}).get("downloadUrl") or ""
print(url)
PY
  )"

  case "$AUDIORELAY_DOWNLOAD_URL" in
    https://dl.audiorelay.net/setups/linux/audiorelay-*.tar.gz) ;;
    *)
      log "Could not resolve a Linux AudioRelay tarball from $AUDIORELAY_DOWNLOADS_API"
      return 1
      ;;
  esac

  log "AudioRelay tarball: $AUDIORELAY_DOWNLOAD_URL"
  return 0
}

download_audiorelay_tarball() {
  download_url_to_file "$AUDIORELAY_DOWNLOAD" "$AUDIORELAY_DOWNLOAD_URL"
}

install_audiorelay_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/audiorelay-extract-$TIMESTAMP"
  local launcher=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$AUDIORELAY_DOWNLOAD"

  if [ -x "$work/bin/AudioRelay" ]; then
    launcher="$work/bin/AudioRelay"
  else
    launcher="$(find "$work" -type f -name AudioRelay -printf '%p\n' | head -1)"
  fi

  if [ -z "$launcher" ] || [ ! -x "$launcher" ]; then
    log "AudioRelay tarball does not contain a bin/AudioRelay launcher"
    return 1
  fi

  if [ "$(head -c 4 "$launcher")" != $'\x7fELF' ]; then
    log "AudioRelay launcher is not an ELF binary"
    return 1
  fi

  sudo mkdir -p "$AUDIORELAY_INSTALL_DIR"
  sudo cp -a "$work"/. "$AUDIORELAY_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$AUDIORELAY_INSTALL_DIR"
  sudo chmod u+rwX "$AUDIORELAY_INSTALL_DIR"
  sudo chmod 755 "$AUDIORELAY_INSTALL_DIR/bin/AudioRelay"

  sudo tee /usr/local/bin/audiorelay >/dev/null <<EOF
#!/bin/bash
export _JAVA_AWT_WM_NONREPARENTING=1
exec "$AUDIORELAY_INSTALL_DIR/bin/AudioRelay" "\$@"
EOF
  sudo chmod 755 /usr/local/bin/audiorelay

  sudo tee /usr/share/applications/audiorelay.desktop >/dev/null <<EOF
[Desktop Entry]
Name=AudioRelay
Comment=Stream audio between phone and PC
Exec=/usr/local/bin/audiorelay
Icon=audiorelay
Terminal=false
Type=Application
Categories=AudioVideo;Audio;
StartupWMClass=com-azefsw-audioconnect-desktop-app-MainKt
EOF
  sudo chmod 644 /usr/share/applications/audiorelay.desktop

  icon="$AUDIORELAY_INSTALL_DIR/lib/AudioRelay.png"
  if [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/audiorelay.png
  fi

  rm -rf "$work" "$AUDIORELAY_DOWNLOAD" "$AUDIORELAY_API_JSON"
}

audiorelay_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  if ! sudo ufw status | grep -q '^Status: active'; then
    log "UFW not active; skip AudioRelay firewall rules"
    return 0
  fi

  sudo ufw allow 59100:59200/tcp comment AudioRelay
  sudo ufw allow 59100:59200/udp comment AudioRelay
}

install_audiorelay() {
  local file_size=0

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("resolve AudioRelay download (missing required command: curl or wget)")
    record_status "FAIL" "resolve AudioRelay download"
    log "Skipping AudioRelay install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    FAILURES+=("resolve AudioRelay download (missing required command: python3)")
    record_status "FAIL" "resolve AudioRelay download"
    log "Skipping AudioRelay install because python3 is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract AudioRelay tarball (missing required command: bsdtar)")
    record_status "FAIL" "extract AudioRelay tarball"
    log "Skipping AudioRelay install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_audiorelay_download; then
    FAILURES+=("resolve AudioRelay linux tarball")
    record_status "FAIL" "resolve AudioRelay linux tarball"
    return 0
  fi

  run_step "download AudioRelay tarball" download_audiorelay_tarball

  if [ ! -e "$AUDIORELAY_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$AUDIORELAY_DOWNLOAD" ]; then
    FAILURES+=("download AudioRelay tarball (empty file)")
    record_status "FAIL" "download AudioRelay tarball"
    log "Downloaded AudioRelay file is empty: $AUDIORELAY_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$AUDIORELAY_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download AudioRelay tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download AudioRelay tarball"
    log "Downloaded AudioRelay file looks too small: $AUDIORELAY_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 2 "$AUDIORELAY_DOWNLOAD")" != $'\x1f\x8b' ]; then
    FAILURES+=("download AudioRelay tarball (not a gzip archive)")
    record_status "FAIL" "download AudioRelay tarball"
    log "Downloaded AudioRelay file is not a gzip archive: $AUDIORELAY_DOWNLOAD"
    return 0
  fi

  log "Verified AudioRelay tarball ($file_size bytes); extracting to $AUDIORELAY_INSTALL_DIR"

  run_step "install AudioRelay" install_audiorelay_files
  run_step "allow AudioRelay through UFW" audiorelay_ufw
}

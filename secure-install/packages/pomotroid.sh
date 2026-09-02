register_package pomotroid 250 "Pomotroid AppImage" install_pomotroid

POMOTROID_RELEASES_API="https://api.github.com/repos/Splode/pomotroid/releases/latest"
POMOTROID_INSTALL_DIR="/opt/pomotroid"
POMOTROID_APPIMAGE_NAME="Pomotroid.AppImage"
POMOTROID_DOWNLOAD="$STATE_DIR/pomotroid-$TIMESTAMP.AppImage"
POMOTROID_ICON_DIR="$STATE_DIR/pomotroid-icon-$TIMESTAMP"
POMOTROID_DOWNLOAD_URL=""
POMOTROID_SHA256=""

resolve_pomotroid_url() {
  local json="$STATE_DIR/pomotroid-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/Splode/pomotroid/releases/latest \
        --jq '.assets[] | select(.name | test("^Pomotroid_.*_amd64\\.AppImage$")) | "\(.browser_download_url)\t\(.digest)"' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$POMOTROID_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if re.match(r"^Pomotroid_.*_amd64\.AppImage$", name):
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            digest = digest[7:]
        print(asset["browser_download_url"] + "\t" + digest)
        break
PY
      )"
    fi
    rm -f "$json"
  fi

  POMOTROID_DOWNLOAD_URL="${parsed%%$'\t'*}"
  POMOTROID_SHA256="${parsed#*$'\t'}"
  POMOTROID_SHA256="${POMOTROID_SHA256#sha256:}"

  case "$POMOTROID_DOWNLOAD_URL" in
    https://github.com/Splode/pomotroid/releases/download/*/Pomotroid_*_amd64.AppImage) ;;
    *)
      log "Could not resolve a Pomotroid amd64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$POMOTROID_SHA256" ] || [ "$POMOTROID_DOWNLOAD_URL" = "$POMOTROID_SHA256" ]; then
    log "Could not parse the Pomotroid SHA-256 from GitHub releases"
    return 1
  fi

  log "Pomotroid AppImage: $POMOTROID_DOWNLOAD_URL"
  return 0
}

download_pomotroid_appimage() {
  download_url_to_file "$POMOTROID_DOWNLOAD" "$POMOTROID_DOWNLOAD_URL"
}

extract_pomotroid_icon() {
  local icon=""

  mkdir -p "$POMOTROID_ICON_DIR"
  (
    cd "$POMOTROID_ICON_DIR"
    "$POMOTROID_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$POMOTROID_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$POMOTROID_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$POMOTROID_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/pomotroid.png
    log "Installed Pomotroid icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Pomotroid icon; desktop entry will use the pomotroid icon name"
  return 0
}

install_pomotroid_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$POMOTROID_INSTALL_DIR"
  sudo install -D -m 755 "$POMOTROID_DOWNLOAD" "$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME"
  sudo chown -R "$owner:$group" "$POMOTROID_INSTALL_DIR"
  sudo chmod u+rwX "$POMOTROID_INSTALL_DIR" "$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME"
  sudo ln -sfn "$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME" /usr/local/bin/pomotroid

  sudo tee /usr/share/applications/pomotroid.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Pomotroid
Comment=Simple and configurable Pomodoro timer
Exec=$POMOTROID_INSTALL_DIR/$POMOTROID_APPIMAGE_NAME --no-sandbox %U
Icon=pomotroid
Terminal=false
Type=Application
Categories=Office;Utility;
StartupWMClass=pomotroid
EOF
  sudo chmod 644 /usr/share/applications/pomotroid.desktop
  extract_pomotroid_icon
  rm -rf "$POMOTROID_ICON_DIR" "$POMOTROID_DOWNLOAD"
}

install_pomotroid() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Pomotroid AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Pomotroid AppImage"
    log "Skipping Pomotroid install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_pomotroid_url; then
    FAILURES+=("resolve Pomotroid amd64 AppImage")
    record_status "FAIL" "resolve Pomotroid amd64 AppImage"
    return 0
  fi

  run_step "download Pomotroid AppImage" download_pomotroid_appimage

  if [ ! -e "$POMOTROID_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$POMOTROID_DOWNLOAD" ]; then
    FAILURES+=("download Pomotroid AppImage (empty file)")
    record_status "FAIL" "download Pomotroid AppImage"
    log "Downloaded Pomotroid file is empty: $POMOTROID_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$POMOTROID_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Pomotroid AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Pomotroid AppImage"
    log "Downloaded Pomotroid file looks too small: $POMOTROID_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$POMOTROID_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Pomotroid AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Pomotroid AppImage"
    log "Downloaded Pomotroid file is not an ELF AppImage: $POMOTROID_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha256sum "$POMOTROID_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$POMOTROID_SHA256" ]; then
    FAILURES+=("verify Pomotroid checksum")
    record_status "FAIL" "verify Pomotroid checksum"
    log "Pomotroid SHA-256 mismatch (expected $POMOTROID_SHA256, got $actual_hash)"
    return 0
  fi

  chmod 700 "$POMOTROID_DOWNLOAD"
  log "Verified Pomotroid AppImage ($file_size bytes); installing to $POMOTROID_INSTALL_DIR"

  run_step "install Pomotroid AppImage" install_pomotroid_files
}

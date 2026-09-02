register_package appimagelauncher 80 "AppImageLauncher x86_64 AppImage" install_appimagelauncher

APPIMAGELAUNCHER_RELEASES_API="https://api.github.com/repos/TheAssassin/AppImageLauncher/releases/latest"
APPIMAGELAUNCHER_INSTALL_DIR="/opt/appimagelauncher"
APPIMAGELAUNCHER_APPIMAGE_NAME="AppImageLauncher.AppImage"
APPIMAGELAUNCHER_DOWNLOAD="$STATE_DIR/appimagelauncher-$TIMESTAMP.AppImage"
APPIMAGELAUNCHER_DOWNLOAD_URL=""
APPIMAGELAUNCHER_SHA256=""

resolve_appimagelauncher_url() {
  local json="$STATE_DIR/appimagelauncher-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/TheAssassin/AppImageLauncher/releases/latest \
        --jq '.assets[] | select(.name | test("^appimagelauncher-lite-.*-x86_64\\.AppImage$")) | "\(.browser_download_url)\t\(.digest)"' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$APPIMAGELAUNCHER_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.startswith("appimagelauncher-lite-") and name.endswith("-x86_64.AppImage"):
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            print(asset["browser_download_url"] + "\t" + digest[7:])
        break
PY
      )"
    fi
    rm -f "$json"
  fi

  APPIMAGELAUNCHER_DOWNLOAD_URL="${parsed%%$'\t'*}"
  APPIMAGELAUNCHER_SHA256="${parsed#*$'\t'}"
  APPIMAGELAUNCHER_SHA256="${APPIMAGELAUNCHER_SHA256#sha256:}"

  case "$APPIMAGELAUNCHER_DOWNLOAD_URL" in
    https://github.com/TheAssassin/AppImageLauncher/releases/download/*/appimagelauncher-lite-*-x86_64.AppImage) ;;
    *)
      log "Could not resolve an AppImageLauncher x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$APPIMAGELAUNCHER_SHA256" ] || [ "$APPIMAGELAUNCHER_DOWNLOAD_URL" = "$APPIMAGELAUNCHER_SHA256" ]; then
    log "Could not parse the AppImageLauncher SHA-256 from GitHub releases"
    return 1
  fi

  log "AppImageLauncher AppImage: $APPIMAGELAUNCHER_DOWNLOAD_URL"
  return 0
}

download_appimagelauncher_appimage() {
  download_url_to_file "$APPIMAGELAUNCHER_DOWNLOAD" "$APPIMAGELAUNCHER_DOWNLOAD_URL"
}

install_appimagelauncher_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$APPIMAGELAUNCHER_INSTALL_DIR"
  sudo install -D -m 755 "$APPIMAGELAUNCHER_DOWNLOAD" "$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME"
  sudo chown -R "$owner:$group" "$APPIMAGELAUNCHER_INSTALL_DIR"
  sudo chmod u+rwX "$APPIMAGELAUNCHER_INSTALL_DIR" "$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME"
  sudo ln -sfn "$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME" /usr/local/bin/appimagelauncher

  sudo tee /usr/share/applications/appimagelauncher.desktop >/dev/null <<EOF
[Desktop Entry]
Name=AppImageLauncher
Comment=Integrate and run AppImage applications
Exec=$APPIMAGELAUNCHER_INSTALL_DIR/$APPIMAGELAUNCHER_APPIMAGE_NAME %U
Icon=appimagelauncher
Terminal=false
Type=Application
Categories=Utility;System;
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/appimagelauncher.desktop

  rm -f "$APPIMAGELAUNCHER_DOWNLOAD"
}

install_appimagelauncher() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve AppImageLauncher AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve AppImageLauncher AppImage"
    log "Skipping AppImageLauncher install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_appimagelauncher_url; then
    FAILURES+=("resolve AppImageLauncher x86_64 AppImage")
    record_status "FAIL" "resolve AppImageLauncher x86_64 AppImage"
    return 0
  fi

  run_step "download AppImageLauncher AppImage" download_appimagelauncher_appimage

  if [ ! -e "$APPIMAGELAUNCHER_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$APPIMAGELAUNCHER_DOWNLOAD" ]; then
    FAILURES+=("download AppImageLauncher AppImage (empty file)")
    record_status "FAIL" "download AppImageLauncher AppImage"
    log "Downloaded AppImageLauncher file is empty: $APPIMAGELAUNCHER_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$APPIMAGELAUNCHER_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download AppImageLauncher AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download AppImageLauncher AppImage"
    log "Downloaded AppImageLauncher file looks too small: $APPIMAGELAUNCHER_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$APPIMAGELAUNCHER_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download AppImageLauncher AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download AppImageLauncher AppImage"
    log "Downloaded AppImageLauncher file is not an ELF AppImage: $APPIMAGELAUNCHER_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha256sum "$APPIMAGELAUNCHER_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$APPIMAGELAUNCHER_SHA256" ]; then
    FAILURES+=("verify AppImageLauncher checksum")
    record_status "FAIL" "verify AppImageLauncher checksum"
    log "AppImageLauncher SHA-256 mismatch (expected $APPIMAGELAUNCHER_SHA256, got $actual_hash)"
    return 0
  fi

  chmod 700 "$APPIMAGELAUNCHER_DOWNLOAD"
  log "Verified AppImageLauncher AppImage ($file_size bytes); installing to $APPIMAGELAUNCHER_INSTALL_DIR"

  run_step "install AppImageLauncher AppImage" install_appimagelauncher_files
}

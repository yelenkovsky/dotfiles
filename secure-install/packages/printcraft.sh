register_package printcraft 350 "PrintCraft PDF workbench" install_printcraft

# Latest GitHub release, linux x86_64 AppImage only.
# PrintCraft publishes SHA256SUMS.txt next to the assets; that checksum is required.
PRINTCRAFT_RELEASES_API="https://api.github.com/repos/storytold/printcraft/releases/latest"
PRINTCRAFT_INSTALL_DIR="/opt/printcraft"
PRINTCRAFT_APPIMAGE_NAME="PrintCraft.AppImage"
PRINTCRAFT_DOWNLOAD="$STATE_DIR/printcraft-$TIMESTAMP.AppImage"
PRINTCRAFT_SUMS_FILE="$STATE_DIR/printcraft-$TIMESTAMP.SHA256SUMS.txt"
PRINTCRAFT_ICON_DIR="$STATE_DIR/printcraft-icon-$TIMESTAMP"
PRINTCRAFT_DOWNLOAD_URL=""
PRINTCRAFT_SUMS_URL=""
PRINTCRAFT_ASSET_NAME=""

resolve_printcraft_urls() {
  local json="$STATE_DIR/printcraft-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/storytold/printcraft/releases/latest \
        --jq '.assets[] | select(.name | test("^printcraft-[0-9].*-linux-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$PRINTCRAFT_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^printcraft-[0-9].*-linux-x86_64\.AppImage$")
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if pattern.fullmatch(name):
        print(name + "\t" + asset["browser_download_url"])
PY
      )"
    fi
    rm -f "$json"
  fi

  while IFS=$'\t' read -r name url; do
    [ -n "$name" ] || continue
    PRINTCRAFT_ASSET_NAME="$name"
    PRINTCRAFT_DOWNLOAD_URL="$url"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one PrintCraft linux x86_64 AppImage, found $count"
    return 1
  fi

  case "$PRINTCRAFT_DOWNLOAD_URL" in
    https://github.com/storytold/printcraft/releases/download/*/printcraft-*-linux-x86_64.AppImage) ;;
    *)
      log "Could not resolve the PrintCraft x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  PRINTCRAFT_SUMS_URL="${PRINTCRAFT_DOWNLOAD_URL%/*}/SHA256SUMS.txt"
  case "$PRINTCRAFT_SUMS_URL" in
    https://github.com/storytold/printcraft/releases/download/*/SHA256SUMS.txt) ;;
    *)
      log "Could not resolve PrintCraft SHA256SUMS.txt"
      return 1
      ;;
  esac

  log "PrintCraft AppImage: $PRINTCRAFT_DOWNLOAD_URL"
  return 0
}

download_printcraft_appimage() {
  download_url_to_file "$PRINTCRAFT_DOWNLOAD" "$PRINTCRAFT_DOWNLOAD_URL"
  download_url_to_file "$PRINTCRAFT_SUMS_FILE" "$PRINTCRAFT_SUMS_URL"
}

verify_printcraft_published_sha256() {
  local expected=""
  local actual=""

  if [ ! -s "$PRINTCRAFT_DOWNLOAD" ]; then
    log "Downloaded PrintCraft file is empty: $PRINTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$PRINTCRAFT_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded PrintCraft file looks too small: $PRINTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 4 "$PRINTCRAFT_DOWNLOAD")" != $'\x7fELF' ]; then
    log "Downloaded PrintCraft file is not an ELF AppImage: $PRINTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 11 "$PRINTCRAFT_DOWNLOAD" | tail -c 3)" != $'AI\x02' ]; then
    log "Downloaded PrintCraft file is not an AppImage: $PRINTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ ! -s "$PRINTCRAFT_SUMS_FILE" ]; then
    log "Missing published SHA256SUMS.txt for $PRINTCRAFT_ASSET_NAME"
    return 1
  fi

  expected="$(
    awk -v name="$PRINTCRAFT_ASSET_NAME" '
      {
        gsub(/\r/, "")
        if ($2 == name) {
          print $1
          exit
        }
      }
    ' "$PRINTCRAFT_SUMS_FILE"
  )"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $PRINTCRAFT_ASSET_NAME is missing or not a 64-hex digest"
    return 1
  fi

  actual="$(sha256sum "$PRINTCRAFT_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $PRINTCRAFT_ASSET_NAME (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

extract_printcraft_icon() {
  local svg=""
  local png=""

  mkdir -p "$PRINTCRAFT_ICON_DIR"
  (
    cd "$PRINTCRAFT_ICON_DIR"
    "$PRINTCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/scalable/apps/*.svg' >/dev/null 2>&1 || true
    "$PRINTCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*.png' >/dev/null 2>&1 || true
  )

  svg="$(find "$PRINTCRAFT_ICON_DIR" -type f -name '*.svg' -print -quit)"
  png="$(find "$PRINTCRAFT_ICON_DIR" -type f -name '*.png' -print -quit)"

  if [ -n "$svg" ] && [ -f "$svg" ]; then
    sudo install -D -m 644 "$svg" /usr/share/icons/hicolor/scalable/apps/printcraft.svg
    log "Installed PrintCraft icon from AppImage: $svg"
  fi

  if [ -n "$png" ] && [ -f "$png" ]; then
    sudo install -D -m 644 "$png" /usr/share/icons/hicolor/512x512/apps/printcraft.png
    log "Installed PrintCraft icon from AppImage: $png"
  fi

  if [ -z "$svg" ] && [ -z "$png" ]; then
    log "Could not extract a PrintCraft icon; desktop entry will use the printcraft icon name"
  fi

  return 0
}

install_printcraft_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$PRINTCRAFT_INSTALL_DIR"
  sudo install -D -m 755 "$PRINTCRAFT_DOWNLOAD" "$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME"
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$PRINTCRAFT_INSTALL_DIR"
  sudo chmod u+rwX "$PRINTCRAFT_INSTALL_DIR" "$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME"
  sudo ln -sfn "$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME" /usr/local/bin/printcraft

  sudo tee /usr/share/applications/printcraft.desktop >/dev/null <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=PrintCraft
GenericName=PDF Editor
Comment=Read, organize, combine, split and secure PDFs
Exec=$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME %F
TryExec=$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME
Icon=printcraft
Terminal=false
StartupNotify=true
StartupWMClass=printcraft
Categories=Office;Viewer;Graphics;
Keywords=pdf;viewer;editor;annotate;sign;forms;merge;split;
MimeType=application/pdf;
EOF
  sudo chmod 644 /usr/share/applications/printcraft.desktop
  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  extract_printcraft_icon
  rm -rf "$PRINTCRAFT_ICON_DIR" "$PRINTCRAFT_DOWNLOAD" "$PRINTCRAFT_SUMS_FILE"
}

install_printcraft() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve PrintCraft AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve PrintCraft AppImage"
    log "Skipping PrintCraft install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_printcraft_urls; then
    FAILURES+=("resolve PrintCraft x86_64 AppImage")
    record_status "FAIL" "resolve PrintCraft x86_64 AppImage"
    return 0
  fi

  run_step "download PrintCraft AppImage" download_printcraft_appimage

  if [ ! -e "$PRINTCRAFT_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_printcraft_published_sha256; then
    FAILURES+=("verify PrintCraft checksum")
    record_status "FAIL" "verify PrintCraft checksum"
    return 0
  fi

  chmod 700 "$PRINTCRAFT_DOWNLOAD"
  log "Verified PrintCraft AppImage; installing to $PRINTCRAFT_INSTALL_DIR"

  run_step "install PrintCraft AppImage" install_printcraft_files
}

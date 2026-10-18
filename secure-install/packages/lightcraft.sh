register_package lightcraft 390 "LightCraft photo library and raw developer" install_lightcraft

# Latest GitHub release, linux x86_64 AppImage only. Same author and release
# layout as PdfCraft: SHA256SUMS.txt is published next to the assets, and that
# checksum is required.
LIGHTCRAFT_REPO="storytold/lightcraft"
LIGHTCRAFT_RELEASES_API="https://api.github.com/repos/$LIGHTCRAFT_REPO/releases/latest"
LIGHTCRAFT_APP_ID="ai.storyteller.lightcraft"
LIGHTCRAFT_INSTALL_DIR="/opt/lightcraft"
LIGHTCRAFT_APPIMAGE_NAME="LightCraft.AppImage"
LIGHTCRAFT_DOWNLOAD="$STATE_DIR/lightcraft-$TIMESTAMP.AppImage"
LIGHTCRAFT_SUMS_FILE="$STATE_DIR/lightcraft-$TIMESTAMP.SHA256SUMS.txt"
LIGHTCRAFT_EXTRACT_DIR="$STATE_DIR/lightcraft-extract-$TIMESTAMP"
LIGHTCRAFT_DOWNLOAD_URL=""
LIGHTCRAFT_SUMS_URL=""
LIGHTCRAFT_ASSET_NAME=""
# Upstream's MimeType list. LightCraft is made the default opener for all of
# them; GIF, SVG and other types it does not list stay with imv.
LIGHTCRAFT_MIME_TYPES=(
  image/heic image/heif image/jpeg image/png image/tiff image/webp
  image/x-adobe-dng image/x-sony-arw image/x-canon-cr2 image/x-canon-cr3
  image/x-nikon-nef image/x-fuji-raf image/x-olympus-orf image/x-panasonic-rw2
  image/x-panasonic-rw image/x-pentax-pef
)
register_update_check lightcraft "$LIGHTCRAFT_DOWNLOAD"
register_changelog lightcraft 'https://github.com/storytold/lightcraft/releases/tag/{version}' '/releases/download/([^/]+)/' 'https://github.com/storytold/lightcraft/releases'

resolve_lightcraft_urls() {
  local json="$STATE_DIR/lightcraft-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api "repos/$LIGHTCRAFT_REPO/releases/latest" \
        --jq '.assets[] | select(.name | test("^lightcraft-[0-9][^/]*-linux-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$LIGHTCRAFT_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^lightcraft-[0-9][^/]*-linux-x86_64\.AppImage$")
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
    LIGHTCRAFT_ASSET_NAME="$name"
    LIGHTCRAFT_DOWNLOAD_URL="$url"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one LightCraft linux x86_64 AppImage, found $count"
    return 1
  fi

  case "$LIGHTCRAFT_DOWNLOAD_URL" in
    "https://github.com/$LIGHTCRAFT_REPO/releases/download/"v[0-9]*/lightcraft-*-linux-x86_64.AppImage) ;;
    *)
      log "Could not resolve the LightCraft x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  LIGHTCRAFT_SUMS_URL="${LIGHTCRAFT_DOWNLOAD_URL%/*}/SHA256SUMS.txt"

  log "LightCraft AppImage: $LIGHTCRAFT_DOWNLOAD_URL"
  return 0
}

download_lightcraft_appimage() {
  download_url_to_file "$LIGHTCRAFT_DOWNLOAD" "$LIGHTCRAFT_DOWNLOAD_URL" || return 1
  download_url_to_file "$LIGHTCRAFT_SUMS_FILE" "$LIGHTCRAFT_SUMS_URL"
}

verify_lightcraft_published_sha256() {
  local expected=""
  local actual=""

  if [ ! -s "$LIGHTCRAFT_DOWNLOAD" ]; then
    log "Downloaded LightCraft file is empty: $LIGHTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$LIGHTCRAFT_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded LightCraft file looks too small: $LIGHTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 4 "$LIGHTCRAFT_DOWNLOAD")" != $'\x7fELF' ]; then
    log "Downloaded LightCraft file is not an ELF AppImage: $LIGHTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 11 "$LIGHTCRAFT_DOWNLOAD" | tail -c 3)" != $'AI\x02' ]; then
    log "Downloaded LightCraft file is not an AppImage: $LIGHTCRAFT_ASSET_NAME"
    return 1
  fi

  if [ ! -s "$LIGHTCRAFT_SUMS_FILE" ]; then
    log "Missing published SHA256SUMS.txt for $LIGHTCRAFT_ASSET_NAME"
    return 1
  fi

  expected="$(
    awk -v name="$LIGHTCRAFT_ASSET_NAME" '
      {
        gsub(/\r/, "")
        if ($2 == name) {
          print $1
          exit
        }
      }
    ' "$LIGHTCRAFT_SUMS_FILE"
  )"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $LIGHTCRAFT_ASSET_NAME is missing or not a 64-hex digest"
    return 1
  fi

  actual="$(sha256sum "$LIGHTCRAFT_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $LIGHTCRAFT_ASSET_NAME (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

# Only after the checksum passed: pull the hicolor icons out of the AppImage.
extract_lightcraft_icons() {
  rm -rf "$LIGHTCRAFT_EXTRACT_DIR"
  mkdir -p "$LIGHTCRAFT_EXTRACT_DIR"
  (
    cd "$LIGHTCRAFT_EXTRACT_DIR"
    "$LIGHTCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/*' >/dev/null 2>&1 || true
  )
}

install_lightcraft_files() {
  local owner="$USER"
  local group
  local icons="$LIGHTCRAFT_EXTRACT_DIR/squashfs-root/usr/share/icons/hicolor"
  local icon rel

  group="$(id -gn "$owner")"

  # Install beside the old file and rename over it, so a running copy never
  # sees a half-written AppImage and a failed copy leaves the old one.
  sudo mkdir -p "$LIGHTCRAFT_INSTALL_DIR" || return 1
  sudo install -m 755 "$LIGHTCRAFT_DOWNLOAD" "$LIGHTCRAFT_INSTALL_DIR/$LIGHTCRAFT_APPIMAGE_NAME.new" || return 1
  sudo mv -f "$LIGHTCRAFT_INSTALL_DIR/$LIGHTCRAFT_APPIMAGE_NAME.new" "$LIGHTCRAFT_INSTALL_DIR/$LIGHTCRAFT_APPIMAGE_NAME" || return 1
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$LIGHTCRAFT_INSTALL_DIR" || return 1
  sudo ln -sfn "$LIGHTCRAFT_INSTALL_DIR/$LIGHTCRAFT_APPIMAGE_NAME" /usr/local/bin/lightcraft || return 1

  # Upstream's desktop entry (packaging/linux), with Exec pointed at the
  # installed launcher.
  sudo tee "/usr/share/applications/$LIGHTCRAFT_APP_ID.desktop" >/dev/null <<EOF || return 1
[Desktop Entry]
Type=Application
Name=LightCraft
GenericName=Photo Library and Raw Developer
Comment=Organise photos and develop raw files, non-destructively
Exec=/usr/local/bin/lightcraft %F
TryExec=/usr/local/bin/lightcraft
Icon=$LIGHTCRAFT_APP_ID
Terminal=false
StartupNotify=true
StartupWMClass=$LIGHTCRAFT_APP_ID
Categories=Graphics;2DGraphics;RasterGraphics;Photography;
Keywords=photo;raw;camera;library;develop;
MimeType=$(printf '%s;' "${LIGHTCRAFT_MIME_TYPES[@]}")
EOF
  sudo chmod 644 "/usr/share/applications/$LIGHTCRAFT_APP_ID.desktop" || return 1

  if [ -d "$icons" ]; then
    while IFS= read -r icon; do
      rel="${icon#"$icons"/}"
      sudo install -D -m 644 "$icon" "/usr/share/icons/hicolor/$rel" || return 1
    done < <(find "$icons" -type f -name "$LIGHTCRAFT_APP_ID.*")
  else
    log "Could not extract LightCraft icons; the desktop entry will use the $LIGHTCRAFT_APP_ID icon name"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
  fi

  set_default_app "$LIGHTCRAFT_APP_ID.desktop" "LightCraft" "${LIGHTCRAFT_MIME_TYPES[@]}"

  rm -rf "$LIGHTCRAFT_EXTRACT_DIR" "$LIGHTCRAFT_DOWNLOAD" "$LIGHTCRAFT_SUMS_FILE"
}

install_lightcraft() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve LightCraft AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve LightCraft AppImage"
    log "Skipping LightCraft install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_lightcraft_urls; then
    FAILURES+=("resolve LightCraft x86_64 AppImage")
    record_status "FAIL" "resolve LightCraft x86_64 AppImage"
    return 0
  fi

  run_step "download LightCraft AppImage" download_lightcraft_appimage

  if [ ! -e "$LIGHTCRAFT_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_lightcraft_published_sha256; then
    FAILURES+=("verify LightCraft checksum")
    record_status "FAIL" "verify LightCraft checksum"
    return 0
  fi

  chmod 700 "$LIGHTCRAFT_DOWNLOAD"
  extract_lightcraft_icons

  log "Verified LightCraft AppImage; installing to $LIGHTCRAFT_INSTALL_DIR"

  close_running_app "LightCraft" "$LIGHTCRAFT_INSTALL_DIR"

  run_step "install LightCraft AppImage" install_lightcraft_files
}

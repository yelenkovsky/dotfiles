register_package gridcraft 370 "GridCraft spreadsheet (XLSX/ODS/CSV)" install_gridcraft

# Latest GitHub release, linux x86_64 AppImage only. Same author and release
# layout as PdfCraft: SHA256SUMS.txt is published next to the assets, and that
# checksum is required.
GRIDCRAFT_REPO="storytold/gridcraft"
GRIDCRAFT_RELEASES_API="https://api.github.com/repos/$GRIDCRAFT_REPO/releases/latest"
GRIDCRAFT_APP_ID="ai.storyteller.gridcraft"
GRIDCRAFT_INSTALL_DIR="/opt/gridcraft"
GRIDCRAFT_APPIMAGE_NAME="GridCraft.AppImage"
GRIDCRAFT_DOWNLOAD="$STATE_DIR/gridcraft-$TIMESTAMP.AppImage"
GRIDCRAFT_SUMS_FILE="$STATE_DIR/gridcraft-$TIMESTAMP.SHA256SUMS.txt"
GRIDCRAFT_EXTRACT_DIR="$STATE_DIR/gridcraft-extract-$TIMESTAMP"
GRIDCRAFT_DOWNLOAD_URL=""
GRIDCRAFT_SUMS_URL=""
GRIDCRAFT_ASSET_NAME=""
# Upstream's MimeType list. GridCraft is made the default opener for all of
# them, plus the application/csv and text/x-csv aliases some apps use.
GRIDCRAFT_MIME_TYPES=(
  application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  application/vnd.ms-excel.sheet.macroEnabled.12
  application/vnd.ms-excel.sheet.binary.macroEnabled.12
  application/vnd.oasis.opendocument.spreadsheet
  text/csv text/tab-separated-values
)
GRIDCRAFT_DEFAULT_TYPES=("${GRIDCRAFT_MIME_TYPES[@]}" application/csv text/x-csv)
register_update_check gridcraft "$GRIDCRAFT_DOWNLOAD"
register_changelog gridcraft 'https://github.com/storytold/gridcraft/releases/tag/{version}' '/releases/download/([^/]+)/' 'https://github.com/storytold/gridcraft/releases'

resolve_gridcraft_urls() {
  local json="$STATE_DIR/gridcraft-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api "repos/$GRIDCRAFT_REPO/releases/latest" \
        --jq '.assets[] | select(.name | test("^gridcraft-[0-9][^/]*-linux-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$GRIDCRAFT_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^gridcraft-[0-9][^/]*-linux-x86_64\.AppImage$")
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
    GRIDCRAFT_ASSET_NAME="$name"
    GRIDCRAFT_DOWNLOAD_URL="$url"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one GridCraft linux x86_64 AppImage, found $count"
    return 1
  fi

  case "$GRIDCRAFT_DOWNLOAD_URL" in
    "https://github.com/$GRIDCRAFT_REPO/releases/download/"v[0-9]*/gridcraft-*-linux-x86_64.AppImage) ;;
    *)
      log "Could not resolve the GridCraft x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  GRIDCRAFT_SUMS_URL="${GRIDCRAFT_DOWNLOAD_URL%/*}/SHA256SUMS.txt"

  log "GridCraft AppImage: $GRIDCRAFT_DOWNLOAD_URL"
  return 0
}

download_gridcraft_appimage() {
  download_url_to_file "$GRIDCRAFT_DOWNLOAD" "$GRIDCRAFT_DOWNLOAD_URL" || return 1
  download_url_to_file "$GRIDCRAFT_SUMS_FILE" "$GRIDCRAFT_SUMS_URL"
}

verify_gridcraft_published_sha256() {
  local expected=""
  local actual=""

  if [ ! -s "$GRIDCRAFT_DOWNLOAD" ]; then
    log "Downloaded GridCraft file is empty: $GRIDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$GRIDCRAFT_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded GridCraft file looks too small: $GRIDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 4 "$GRIDCRAFT_DOWNLOAD")" != $'\x7fELF' ]; then
    log "Downloaded GridCraft file is not an ELF AppImage: $GRIDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 11 "$GRIDCRAFT_DOWNLOAD" | tail -c 3)" != $'AI\x02' ]; then
    log "Downloaded GridCraft file is not an AppImage: $GRIDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ ! -s "$GRIDCRAFT_SUMS_FILE" ]; then
    log "Missing published SHA256SUMS.txt for $GRIDCRAFT_ASSET_NAME"
    return 1
  fi

  expected="$(
    awk -v name="$GRIDCRAFT_ASSET_NAME" '
      {
        gsub(/\r/, "")
        if ($2 == name) {
          print $1
          exit
        }
      }
    ' "$GRIDCRAFT_SUMS_FILE"
  )"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $GRIDCRAFT_ASSET_NAME is missing or not a 64-hex digest"
    return 1
  fi

  actual="$(sha256sum "$GRIDCRAFT_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $GRIDCRAFT_ASSET_NAME (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

# Only after the checksum passed: pull the hicolor icons out of the AppImage.
extract_gridcraft_icons() {
  rm -rf "$GRIDCRAFT_EXTRACT_DIR"
  mkdir -p "$GRIDCRAFT_EXTRACT_DIR"
  (
    cd "$GRIDCRAFT_EXTRACT_DIR"
    "$GRIDCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/*' >/dev/null 2>&1 || true
  )
}

install_gridcraft_files() {
  local owner="$USER"
  local group
  local icons="$GRIDCRAFT_EXTRACT_DIR/squashfs-root/usr/share/icons/hicolor"
  local icon rel

  group="$(id -gn "$owner")"

  # Install beside the old file and rename over it, so a running copy never
  # sees a half-written AppImage and a failed copy leaves the old one.
  sudo mkdir -p "$GRIDCRAFT_INSTALL_DIR" || return 1
  sudo install -m 755 "$GRIDCRAFT_DOWNLOAD" "$GRIDCRAFT_INSTALL_DIR/$GRIDCRAFT_APPIMAGE_NAME.new" || return 1
  sudo mv -f "$GRIDCRAFT_INSTALL_DIR/$GRIDCRAFT_APPIMAGE_NAME.new" "$GRIDCRAFT_INSTALL_DIR/$GRIDCRAFT_APPIMAGE_NAME" || return 1
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$GRIDCRAFT_INSTALL_DIR" || return 1
  sudo ln -sfn "$GRIDCRAFT_INSTALL_DIR/$GRIDCRAFT_APPIMAGE_NAME" /usr/local/bin/gridcraft || return 1

  # Upstream's desktop entry (packaging/linux), with Exec pointed at the
  # installed launcher.
  sudo tee "/usr/share/applications/$GRIDCRAFT_APP_ID.desktop" >/dev/null <<EOF || return 1
[Desktop Entry]
Type=Application
Name=GridCraft
GenericName=Spreadsheet
Comment=Calculate, analyse and chart data in workbooks
Exec=/usr/local/bin/gridcraft %F
TryExec=/usr/local/bin/gridcraft
Icon=$GRIDCRAFT_APP_ID
Terminal=false
StartupNotify=true
StartupWMClass=$GRIDCRAFT_APP_ID
Categories=Office;Spreadsheet;
MimeType=$(printf '%s;' "${GRIDCRAFT_MIME_TYPES[@]}")
Keywords=spreadsheet;workbook;sheet;table;formula;chart;pivot;xlsx;xlsb;ods;csv;tsv;excel;
EOF
  sudo chmod 644 "/usr/share/applications/$GRIDCRAFT_APP_ID.desktop" || return 1

  if [ -d "$icons" ]; then
    while IFS= read -r icon; do
      rel="${icon#"$icons"/}"
      sudo install -D -m 644 "$icon" "/usr/share/icons/hicolor/$rel" || return 1
    done < <(find "$icons" -type f -name "$GRIDCRAFT_APP_ID.*")
  else
    log "Could not extract GridCraft icons; the desktop entry will use the $GRIDCRAFT_APP_ID icon name"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
  fi

  set_default_app "$GRIDCRAFT_APP_ID.desktop" "GridCraft" "${GRIDCRAFT_DEFAULT_TYPES[@]}"

  rm -rf "$GRIDCRAFT_EXTRACT_DIR" "$GRIDCRAFT_DOWNLOAD" "$GRIDCRAFT_SUMS_FILE"
}

install_gridcraft() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve GridCraft AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve GridCraft AppImage"
    log "Skipping GridCraft install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_gridcraft_urls; then
    FAILURES+=("resolve GridCraft x86_64 AppImage")
    record_status "FAIL" "resolve GridCraft x86_64 AppImage"
    return 0
  fi

  run_step "download GridCraft AppImage" download_gridcraft_appimage

  if [ ! -e "$GRIDCRAFT_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_gridcraft_published_sha256; then
    FAILURES+=("verify GridCraft checksum")
    record_status "FAIL" "verify GridCraft checksum"
    return 0
  fi

  chmod 700 "$GRIDCRAFT_DOWNLOAD"
  extract_gridcraft_icons

  log "Verified GridCraft AppImage; installing to $GRIDCRAFT_INSTALL_DIR"

  close_running_app "GridCraft" "$GRIDCRAFT_INSTALL_DIR" || return 0

  run_step "install GridCraft AppImage" install_gridcraft_files
}

register_package pdfcraft 350 "PdfCraft PDF workbench (formerly PrintCraft)" install_pdfcraft

# Latest GitHub release, linux x86_64 AppImage only. The project was renamed
# from storytold/printcraft in v0.6.0 (same owner; GitHub redirects the old
# name). PdfCraft publishes SHA256SUMS.txt next to the assets; that checksum is
# required. Since the rename the AppImage bundles its OCR models
# (usr/share/pdfcraft/models), so nothing else is downloaded.
PDFCRAFT_REPO="storytold/pdfcraft"
PDFCRAFT_RELEASES_API="https://api.github.com/repos/$PDFCRAFT_REPO/releases/latest"
PDFCRAFT_APP_ID="ai.storyteller.pdfcraft"
PDFCRAFT_INSTALL_DIR="/opt/pdfcraft"
PDFCRAFT_APPIMAGE_NAME="PdfCraft.AppImage"
PDFCRAFT_DOWNLOAD="$STATE_DIR/pdfcraft-$TIMESTAMP.AppImage"
PDFCRAFT_SUMS_FILE="$STATE_DIR/pdfcraft-$TIMESTAMP.SHA256SUMS.txt"
PDFCRAFT_EXTRACT_DIR="$STATE_DIR/pdfcraft-extract-$TIMESTAMP"
PDFCRAFT_DOWNLOAD_URL=""
PDFCRAFT_SUMS_URL=""
PDFCRAFT_ASSET_NAME=""
register_update_check pdfcraft "$PDFCRAFT_DOWNLOAD"
register_changelog pdfcraft 'https://github.com/storytold/pdfcraft/releases/tag/{version}' '/releases/download/([^/]+)/' 'https://github.com/storytold/pdfcraft/releases'

# What the PrintCraft installer left behind. Settings in
# ~/.local/share/printcraft are not touched: PdfCraft moves them on first start.
PRINTCRAFT_LEGACY_INSTALL_DIR="/opt/printcraft"
PRINTCRAFT_LEGACY_FILES=(
  /usr/local/bin/printcraft
  /usr/share/applications/printcraft.desktop
  /usr/share/icons/hicolor/scalable/apps/printcraft.svg
  /usr/share/icons/hicolor/512x512/apps/printcraft.png
)

resolve_pdfcraft_urls() {
  local json="$STATE_DIR/pdfcraft-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api "repos/$PDFCRAFT_REPO/releases/latest" \
        --jq '.assets[] | select(.name | test("^pdfcraft-[0-9][^/]*-linux-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$PDFCRAFT_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^pdfcraft-[0-9][^/]*-linux-x86_64\.AppImage$")
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
    PDFCRAFT_ASSET_NAME="$name"
    PDFCRAFT_DOWNLOAD_URL="$url"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one PdfCraft linux x86_64 AppImage, found $count"
    return 1
  fi

  case "$PDFCRAFT_DOWNLOAD_URL" in
    "https://github.com/$PDFCRAFT_REPO/releases/download/"v[0-9]*/pdfcraft-*-linux-x86_64.AppImage) ;;
    *)
      log "Could not resolve the PdfCraft x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  PDFCRAFT_SUMS_URL="${PDFCRAFT_DOWNLOAD_URL%/*}/SHA256SUMS.txt"

  log "PdfCraft AppImage: $PDFCRAFT_DOWNLOAD_URL"
  return 0
}

download_pdfcraft_appimage() {
  download_url_to_file "$PDFCRAFT_DOWNLOAD" "$PDFCRAFT_DOWNLOAD_URL" || return 1
  download_url_to_file "$PDFCRAFT_SUMS_FILE" "$PDFCRAFT_SUMS_URL"
}

verify_pdfcraft_published_sha256() {
  local expected=""
  local actual=""

  if [ ! -s "$PDFCRAFT_DOWNLOAD" ]; then
    log "Downloaded PdfCraft file is empty: $PDFCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$PDFCRAFT_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded PdfCraft file looks too small: $PDFCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 4 "$PDFCRAFT_DOWNLOAD")" != $'\x7fELF' ]; then
    log "Downloaded PdfCraft file is not an ELF AppImage: $PDFCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 11 "$PDFCRAFT_DOWNLOAD" | tail -c 3)" != $'AI\x02' ]; then
    log "Downloaded PdfCraft file is not an AppImage: $PDFCRAFT_ASSET_NAME"
    return 1
  fi

  if [ ! -s "$PDFCRAFT_SUMS_FILE" ]; then
    log "Missing published SHA256SUMS.txt for $PDFCRAFT_ASSET_NAME"
    return 1
  fi

  expected="$(
    awk -v name="$PDFCRAFT_ASSET_NAME" '
      {
        gsub(/\r/, "")
        if ($2 == name) {
          print $1
          exit
        }
      }
    ' "$PDFCRAFT_SUMS_FILE"
  )"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $PDFCRAFT_ASSET_NAME is missing or not a 64-hex digest"
    return 1
  fi

  actual="$(sha256sum "$PDFCRAFT_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $PDFCRAFT_ASSET_NAME (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

# The OCR models must be inside the AppImage now; refuse a build without them
# rather than install a PdfCraft whose text recognition cannot work.
verify_pdfcraft_bundled_models() {
  local model

  rm -rf "$PDFCRAFT_EXTRACT_DIR"
  mkdir -p "$PDFCRAFT_EXTRACT_DIR"
  (
    cd "$PDFCRAFT_EXTRACT_DIR"
    "$PDFCRAFT_DOWNLOAD" --appimage-extract 'usr/share/pdfcraft/models/*' >/dev/null 2>&1 || true
    "$PDFCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/*' >/dev/null 2>&1 || true
  )

  for model in text-detection.rten text-recognition.rten; do
    if [ ! -s "$PDFCRAFT_EXTRACT_DIR/squashfs-root/usr/share/pdfcraft/models/$model" ]; then
      log "PdfCraft AppImage does not bundle the OCR model $model"
      return 1
    fi
  done

  return 0
}

# PrintCraft was the PDF default; hand that over so PDFs keep opening. A
# default the user set to anything else is left alone.
move_pdf_default_to_pdfcraft() {
  local list="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"

  [ -f "$list" ] || return 0
  grep -q 'printcraft\.desktop' "$list" || return 0
  sed -i "s/\bprintcraft\.desktop\b/$PDFCRAFT_APP_ID.desktop/g" "$list"
  log "Moved the PDF default from printcraft.desktop to $PDFCRAFT_APP_ID.desktop in $list"
}

remove_printcraft_leftovers() {
  local file

  if [ -d "$PRINTCRAFT_LEGACY_INSTALL_DIR" ]; then
    sudo rm -rf "$PRINTCRAFT_LEGACY_INSTALL_DIR" || return 1
    log "Removed the old PrintCraft install at $PRINTCRAFT_LEGACY_INSTALL_DIR"
  fi

  for file in "${PRINTCRAFT_LEGACY_FILES[@]}"; do
    if [ -e "$file" ] || [ -L "$file" ]; then
      sudo rm -f "$file" || return 1
    fi
  done
}

install_pdfcraft_files() {
  local owner="$USER"
  local group
  local icons="$PDFCRAFT_EXTRACT_DIR/squashfs-root/usr/share/icons/hicolor"
  local icon rel

  group="$(id -gn "$owner")"

  # Install beside the old file and rename over it, so a running copy never
  # sees a half-written AppImage and a failed copy leaves the old one.
  sudo mkdir -p "$PDFCRAFT_INSTALL_DIR" || return 1
  sudo install -m 755 "$PDFCRAFT_DOWNLOAD" "$PDFCRAFT_INSTALL_DIR/$PDFCRAFT_APPIMAGE_NAME.new" || return 1
  sudo mv -f "$PDFCRAFT_INSTALL_DIR/$PDFCRAFT_APPIMAGE_NAME.new" "$PDFCRAFT_INSTALL_DIR/$PDFCRAFT_APPIMAGE_NAME" || return 1
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$PDFCRAFT_INSTALL_DIR" || return 1
  sudo ln -sfn "$PDFCRAFT_INSTALL_DIR/$PDFCRAFT_APPIMAGE_NAME" /usr/local/bin/pdfcraft || return 1

  # Upstream's desktop entry, with Exec pointed at the installed launcher.
  sudo tee "/usr/share/applications/$PDFCRAFT_APP_ID.desktop" >/dev/null <<EOF || return 1
[Desktop Entry]
Type=Application
Name=PdfCraft
GenericName=PDF Editor
Comment=Read, organize, combine, split and secure PDFs
Exec=/usr/local/bin/pdfcraft %U
TryExec=/usr/local/bin/pdfcraft
Icon=$PDFCRAFT_APP_ID
Terminal=false
StartupNotify=true
StartupWMClass=pdfcraft
Categories=Office;Viewer;
Keywords=pdf;viewer;editor;annotate;sign;forms;merge;split;
MimeType=application/pdf;
EOF
  sudo chmod 644 "/usr/share/applications/$PDFCRAFT_APP_ID.desktop" || return 1

  if [ -d "$icons" ]; then
    while IFS= read -r icon; do
      rel="${icon#"$icons"/}"
      sudo install -D -m 644 "$icon" "/usr/share/icons/hicolor/$rel" || return 1
    done < <(find "$icons" -type f -name "$PDFCRAFT_APP_ID.*")
  else
    log "Could not extract PdfCraft icons; the desktop entry will use the $PDFCRAFT_APP_ID icon name"
  fi

  remove_printcraft_leftovers || return 1
  move_pdf_default_to_pdfcraft

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
  fi

  rm -rf "$PDFCRAFT_EXTRACT_DIR" "$PDFCRAFT_DOWNLOAD" "$PDFCRAFT_SUMS_FILE"
}

install_pdfcraft() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve PdfCraft AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve PdfCraft AppImage"
    log "Skipping PdfCraft install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_pdfcraft_urls; then
    FAILURES+=("resolve PdfCraft x86_64 AppImage")
    record_status "FAIL" "resolve PdfCraft x86_64 AppImage"
    return 0
  fi

  run_step "download PdfCraft AppImage" download_pdfcraft_appimage

  if [ ! -e "$PDFCRAFT_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_pdfcraft_published_sha256; then
    FAILURES+=("verify PdfCraft checksum")
    record_status "FAIL" "verify PdfCraft checksum"
    return 0
  fi

  chmod 700 "$PDFCRAFT_DOWNLOAD"

  if ! verify_pdfcraft_bundled_models; then
    FAILURES+=("verify PdfCraft bundled OCR models")
    record_status "FAIL" "verify PdfCraft bundled OCR models"
    return 0
  fi

  log "Verified PdfCraft AppImage and its OCR models; installing to $PDFCRAFT_INSTALL_DIR"

  close_running_app "PdfCraft" "$PDFCRAFT_INSTALL_DIR" "$PRINTCRAFT_LEGACY_INSTALL_DIR"

  run_step "install PdfCraft AppImage" install_pdfcraft_files
}

register_package wordcraft 380 "WordCraft word processor (DOCX/ODT)" install_wordcraft

# Latest GitHub release, linux x86_64 AppImage only. Same author and release
# layout as PdfCraft: SHA256SUMS.txt is published next to the assets, and that
# checksum is required.
WORDCRAFT_REPO="storytold/wordcraft"
WORDCRAFT_RELEASES_API="https://api.github.com/repos/$WORDCRAFT_REPO/releases/latest"
WORDCRAFT_APP_ID="ai.storyteller.wordcraft"
WORDCRAFT_INSTALL_DIR="/opt/wordcraft"
WORDCRAFT_APPIMAGE_NAME="WordCraft.AppImage"
WORDCRAFT_DOWNLOAD="$STATE_DIR/wordcraft-$TIMESTAMP.AppImage"
WORDCRAFT_SUMS_FILE="$STATE_DIR/wordcraft-$TIMESTAMP.SHA256SUMS.txt"
WORDCRAFT_EXTRACT_DIR="$STATE_DIR/wordcraft-extract-$TIMESTAMP"
WORDCRAFT_DOWNLOAD_URL=""
WORDCRAFT_SUMS_URL=""
WORDCRAFT_ASSET_NAME=""
# The MimeType list in the desktop entry. WordCraft is made the default opener
# for all of them; plain text, Markdown and HTML keep their own defaults.
WORDCRAFT_MIME_TYPES=(
  application/vnd.openxmlformats-officedocument.wordprocessingml.document
  application/vnd.ms-word.document.macroEnabled.12
  application/vnd.openxmlformats-officedocument.wordprocessingml.template
  application/vnd.ms-word.template.macroEnabled.12
  application/msword application/msword-template
  application/vnd.oasis.opendocument.text application/rtf text/rtf
)
register_update_check wordcraft "$WORDCRAFT_DOWNLOAD"
register_changelog wordcraft 'https://github.com/storytold/wordcraft/releases/tag/{version}' '/releases/download/([^/]+)/' 'https://github.com/storytold/wordcraft/releases'

resolve_wordcraft_urls() {
  local json="$STATE_DIR/wordcraft-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api "repos/$WORDCRAFT_REPO/releases/latest" \
        --jq '.assets[] | select(.name | test("^wordcraft-[0-9][^/]*-linux-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$WORDCRAFT_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^wordcraft-[0-9][^/]*-linux-x86_64\.AppImage$")
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
    WORDCRAFT_ASSET_NAME="$name"
    WORDCRAFT_DOWNLOAD_URL="$url"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one WordCraft linux x86_64 AppImage, found $count"
    return 1
  fi

  case "$WORDCRAFT_DOWNLOAD_URL" in
    "https://github.com/$WORDCRAFT_REPO/releases/download/"v[0-9]*/wordcraft-*-linux-x86_64.AppImage) ;;
    *)
      log "Could not resolve the WordCraft x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  WORDCRAFT_SUMS_URL="${WORDCRAFT_DOWNLOAD_URL%/*}/SHA256SUMS.txt"

  log "WordCraft AppImage: $WORDCRAFT_DOWNLOAD_URL"
  return 0
}

download_wordcraft_appimage() {
  download_url_to_file "$WORDCRAFT_DOWNLOAD" "$WORDCRAFT_DOWNLOAD_URL" || return 1
  download_url_to_file "$WORDCRAFT_SUMS_FILE" "$WORDCRAFT_SUMS_URL"
}

verify_wordcraft_published_sha256() {
  local expected=""
  local actual=""

  if [ ! -s "$WORDCRAFT_DOWNLOAD" ]; then
    log "Downloaded WordCraft file is empty: $WORDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$WORDCRAFT_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded WordCraft file looks too small: $WORDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 4 "$WORDCRAFT_DOWNLOAD")" != $'\x7fELF' ]; then
    log "Downloaded WordCraft file is not an ELF AppImage: $WORDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 11 "$WORDCRAFT_DOWNLOAD" | tail -c 3)" != $'AI\x02' ]; then
    log "Downloaded WordCraft file is not an AppImage: $WORDCRAFT_ASSET_NAME"
    return 1
  fi

  if [ ! -s "$WORDCRAFT_SUMS_FILE" ]; then
    log "Missing published SHA256SUMS.txt for $WORDCRAFT_ASSET_NAME"
    return 1
  fi

  expected="$(
    awk -v name="$WORDCRAFT_ASSET_NAME" '
      {
        gsub(/\r/, "")
        if ($2 == name) {
          print $1
          exit
        }
      }
    ' "$WORDCRAFT_SUMS_FILE"
  )"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $WORDCRAFT_ASSET_NAME is missing or not a 64-hex digest"
    return 1
  fi

  actual="$(sha256sum "$WORDCRAFT_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $WORDCRAFT_ASSET_NAME (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

# Only after the checksum passed: pull the hicolor icons out of the AppImage.
extract_wordcraft_icons() {
  rm -rf "$WORDCRAFT_EXTRACT_DIR"
  mkdir -p "$WORDCRAFT_EXTRACT_DIR"
  (
    cd "$WORDCRAFT_EXTRACT_DIR"
    "$WORDCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/*' >/dev/null 2>&1 || true
  )
}

install_wordcraft_files() {
  local owner="$USER"
  local group
  local icons="$WORDCRAFT_EXTRACT_DIR/squashfs-root/usr/share/icons/hicolor"
  local icon rel

  group="$(id -gn "$owner")"

  # Install beside the old file and rename over it, so a running copy never
  # sees a half-written AppImage and a failed copy leaves the old one.
  sudo mkdir -p "$WORDCRAFT_INSTALL_DIR" || return 1
  sudo install -m 755 "$WORDCRAFT_DOWNLOAD" "$WORDCRAFT_INSTALL_DIR/$WORDCRAFT_APPIMAGE_NAME.new" || return 1
  sudo mv -f "$WORDCRAFT_INSTALL_DIR/$WORDCRAFT_APPIMAGE_NAME.new" "$WORDCRAFT_INSTALL_DIR/$WORDCRAFT_APPIMAGE_NAME" || return 1
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$WORDCRAFT_INSTALL_DIR" || return 1
  sudo ln -sfn "$WORDCRAFT_INSTALL_DIR/$WORDCRAFT_APPIMAGE_NAME" /usr/local/bin/wordcraft || return 1

  # Upstream's desktop entry (packaging/linux), with Exec pointed at the
  # installed launcher.
  # Upstream also lists text/plain, text/html, text/markdown and text/x-tex; those
  # are left out so WordCraft does not become the default for plain text files.
  sudo tee "/usr/share/applications/$WORDCRAFT_APP_ID.desktop" >/dev/null <<EOF || return 1
[Desktop Entry]
Type=Application
Name=WordCraft
GenericName=Word Processor
Comment=Write and design documents; open and save Word files
Exec=/usr/local/bin/wordcraft %F
TryExec=/usr/local/bin/wordcraft
Icon=$WORDCRAFT_APP_ID
Terminal=false
StartupNotify=true
StartupWMClass=$WORDCRAFT_APP_ID
Categories=Office;WordProcessor;
Keywords=word;processor;document;docx;writer;text;letter;report;
MimeType=$(printf '%s;' "${WORDCRAFT_MIME_TYPES[@]}")
EOF
  sudo chmod 644 "/usr/share/applications/$WORDCRAFT_APP_ID.desktop" || return 1

  if [ -d "$icons" ]; then
    while IFS= read -r icon; do
      rel="${icon#"$icons"/}"
      sudo install -D -m 644 "$icon" "/usr/share/icons/hicolor/$rel" || return 1
    done < <(find "$icons" -type f -name "$WORDCRAFT_APP_ID.*")
  else
    log "Could not extract WordCraft icons; the desktop entry will use the $WORDCRAFT_APP_ID icon name"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
  fi

  set_default_app "$WORDCRAFT_APP_ID.desktop" "WordCraft" "${WORDCRAFT_MIME_TYPES[@]}"

  rm -rf "$WORDCRAFT_EXTRACT_DIR" "$WORDCRAFT_DOWNLOAD" "$WORDCRAFT_SUMS_FILE"
}

install_wordcraft() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve WordCraft AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve WordCraft AppImage"
    log "Skipping WordCraft install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_wordcraft_urls; then
    FAILURES+=("resolve WordCraft x86_64 AppImage")
    record_status "FAIL" "resolve WordCraft x86_64 AppImage"
    return 0
  fi

  run_step "download WordCraft AppImage" download_wordcraft_appimage

  if [ ! -e "$WORDCRAFT_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_wordcraft_published_sha256; then
    FAILURES+=("verify WordCraft checksum")
    record_status "FAIL" "verify WordCraft checksum"
    return 0
  fi

  chmod 700 "$WORDCRAFT_DOWNLOAD"
  extract_wordcraft_icons

  log "Verified WordCraft AppImage; installing to $WORDCRAFT_INSTALL_DIR"

  close_running_app "WordCraft" "$WORDCRAFT_INSTALL_DIR" || return 0

  run_step "install WordCraft AppImage" install_wordcraft_files
}

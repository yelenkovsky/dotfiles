# shellcheck shell=bash
register_package deckcraft 400 "DeckCraft presentations (PPTX)" install_deckcraft

# Latest GitHub release, linux x86_64 AppImage only. Same author and release
# layout as PdfCraft: SHA256SUMS.txt is published next to the assets, and that
# checksum is required.
DECKCRAFT_REPO="storytold/deckcraft"
DECKCRAFT_RELEASES_API="https://api.github.com/repos/$DECKCRAFT_REPO/releases/latest"
DECKCRAFT_APP_ID="ai.storyteller.deckcraft"
DECKCRAFT_INSTALL_DIR="/opt/deckcraft"
DECKCRAFT_APPIMAGE_NAME="DeckCraft.AppImage"
DECKCRAFT_DOWNLOAD="$STATE_DIR/deckcraft-$TIMESTAMP.AppImage"
DECKCRAFT_SUMS_FILE="$STATE_DIR/deckcraft-$TIMESTAMP.SHA256SUMS.txt"
DECKCRAFT_EXTRACT_DIR="$STATE_DIR/deckcraft-extract-$TIMESTAMP"
DECKCRAFT_DOWNLOAD_URL=""
DECKCRAFT_SUMS_URL=""
DECKCRAFT_ASSET_NAME=""
# Upstream's MimeType list. DeckCraft is made the default opener for all of
# them (application/x-deckcraft is its own project format).
DECKCRAFT_MIME_TYPES=(
  application/x-deckcraft
  application/vnd.openxmlformats-officedocument.presentationml.presentation
  application/vnd.openxmlformats-officedocument.presentationml.template
  application/vnd.openxmlformats-officedocument.presentationml.slideshow
)
register_update_check deckcraft "$DECKCRAFT_DOWNLOAD"
register_changelog deckcraft 'https://github.com/storytold/deckcraft/releases/tag/{version}' '/releases/download/([^/]+)/' 'https://github.com/storytold/deckcraft/releases'

resolve_deckcraft_urls() {
  local json="$STATE_DIR/deckcraft-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api "repos/$DECKCRAFT_REPO/releases/latest" \
        --jq '.assets[] | select(.name | test("^deckcraft-[0-9][^/]*-linux-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$DECKCRAFT_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^deckcraft-[0-9][^/]*-linux-x86_64\.AppImage$")
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
    DECKCRAFT_ASSET_NAME="$name"
    DECKCRAFT_DOWNLOAD_URL="$url"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one DeckCraft linux x86_64 AppImage, found $count"
    return 1
  fi

  case "$DECKCRAFT_DOWNLOAD_URL" in
    "https://github.com/$DECKCRAFT_REPO/releases/download/"v[0-9]*/deckcraft-*-linux-x86_64.AppImage) ;;
    *)
      log "Could not resolve the DeckCraft x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  DECKCRAFT_SUMS_URL="${DECKCRAFT_DOWNLOAD_URL%/*}/SHA256SUMS.txt"

  log "DeckCraft AppImage: $DECKCRAFT_DOWNLOAD_URL"
  return 0
}

download_deckcraft_appimage() {
  download_url_to_file "$DECKCRAFT_DOWNLOAD" "$DECKCRAFT_DOWNLOAD_URL" || return 1
  download_url_to_file "$DECKCRAFT_SUMS_FILE" "$DECKCRAFT_SUMS_URL"
}

verify_deckcraft_published_sha256() {
  local expected=""
  local actual=""

  if [ ! -s "$DECKCRAFT_DOWNLOAD" ]; then
    log "Downloaded DeckCraft file is empty: $DECKCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$DECKCRAFT_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded DeckCraft file looks too small: $DECKCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 4 "$DECKCRAFT_DOWNLOAD")" != $'\x7fELF' ]; then
    log "Downloaded DeckCraft file is not an ELF AppImage: $DECKCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 11 "$DECKCRAFT_DOWNLOAD" | tail -c 3)" != $'AI\x02' ]; then
    log "Downloaded DeckCraft file is not an AppImage: $DECKCRAFT_ASSET_NAME"
    return 1
  fi

  if [ ! -s "$DECKCRAFT_SUMS_FILE" ]; then
    log "Missing published SHA256SUMS.txt for $DECKCRAFT_ASSET_NAME"
    return 1
  fi

  expected="$(
    awk -v name="$DECKCRAFT_ASSET_NAME" '
      {
        gsub(/\r/, "")
        if ($2 == name) {
          print $1
          exit
        }
      }
    ' "$DECKCRAFT_SUMS_FILE"
  )"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $DECKCRAFT_ASSET_NAME is missing or not a 64-hex digest"
    return 1
  fi

  actual="$(sha256sum "$DECKCRAFT_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $DECKCRAFT_ASSET_NAME (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

# Only after the checksum passed: pull the hicolor icons out of the AppImage.
extract_deckcraft_icons() {
  rm -rf "$DECKCRAFT_EXTRACT_DIR"
  mkdir -p "$DECKCRAFT_EXTRACT_DIR"
  (
    cd "$DECKCRAFT_EXTRACT_DIR" || exit 1
    "$DECKCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/*' >/dev/null 2>&1 || true
  )
}

install_deckcraft_files() {
  local owner="$USER"
  local group
  local icons="$DECKCRAFT_EXTRACT_DIR/squashfs-root/usr/share/icons/hicolor"
  local icon rel

  group="$(id -gn "$owner")"

  # Install beside the old file and rename over it, so a running copy never
  # sees a half-written AppImage and a failed copy leaves the old one.
  sudo mkdir -p "$DECKCRAFT_INSTALL_DIR" || return 1
  sudo install -m 755 "$DECKCRAFT_DOWNLOAD" "$DECKCRAFT_INSTALL_DIR/$DECKCRAFT_APPIMAGE_NAME.new" || return 1
  sudo mv -f "$DECKCRAFT_INSTALL_DIR/$DECKCRAFT_APPIMAGE_NAME.new" "$DECKCRAFT_INSTALL_DIR/$DECKCRAFT_APPIMAGE_NAME" || return 1
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$DECKCRAFT_INSTALL_DIR" || return 1
  sudo ln -sfn "$DECKCRAFT_INSTALL_DIR/$DECKCRAFT_APPIMAGE_NAME" /usr/local/bin/deckcraft || return 1

  # Upstream's desktop entry (packaging/linux), with Exec pointed at the
  # installed launcher.
  # Upstream also lists text/plain, text/html, text/markdown and text/x-tex; those
  # are left out so DeckCraft does not become the default for plain text files.
  sudo tee "/usr/share/applications/$DECKCRAFT_APP_ID.desktop" >/dev/null <<EOF || return 1
[Desktop Entry]
Type=Application
Name=DeckCraft
GenericName=Presentation
Comment=Create and present slide decks
Exec=/usr/local/bin/deckcraft %F
TryExec=/usr/local/bin/deckcraft
Icon=$DECKCRAFT_APP_ID
Terminal=false
StartupNotify=true
StartupWMClass=$DECKCRAFT_APP_ID
Categories=Office;Presentation;
Keywords=presentation;slides;slide show;deck;pptx;keynote;powerpoint;
MimeType=$(printf '%s;' "${DECKCRAFT_MIME_TYPES[@]}")
EOF
  sudo chmod 644 "/usr/share/applications/$DECKCRAFT_APP_ID.desktop" || return 1

  if [ -d "$icons" ]; then
    while IFS= read -r icon; do
      rel="${icon#"$icons"/}"
      sudo install -D -m 644 "$icon" "/usr/share/icons/hicolor/$rel" || return 1
    done < <(find "$icons" -type f -name "$DECKCRAFT_APP_ID.*")
  else
    log "Could not extract DeckCraft icons; the desktop entry will use the $DECKCRAFT_APP_ID icon name"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
  fi

  set_default_app "$DECKCRAFT_APP_ID.desktop" "DeckCraft" "${DECKCRAFT_MIME_TYPES[@]}"

  rm -rf "$DECKCRAFT_EXTRACT_DIR" "$DECKCRAFT_DOWNLOAD" "$DECKCRAFT_SUMS_FILE"
}

install_deckcraft() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve DeckCraft AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve DeckCraft AppImage"
    log "Skipping DeckCraft install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_deckcraft_urls; then
    FAILURES+=("resolve DeckCraft x86_64 AppImage")
    record_status "FAIL" "resolve DeckCraft x86_64 AppImage"
    return 0
  fi

  run_step "download DeckCraft AppImage" download_deckcraft_appimage

  if [ ! -e "$DECKCRAFT_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_deckcraft_published_sha256; then
    FAILURES+=("verify DeckCraft checksum")
    record_status "FAIL" "verify DeckCraft checksum"
    return 0
  fi

  chmod 700 "$DECKCRAFT_DOWNLOAD"
  extract_deckcraft_icons

  log "Verified DeckCraft AppImage; installing to $DECKCRAFT_INSTALL_DIR"

  close_running_app "DeckCraft" "$DECKCRAFT_INSTALL_DIR" || return 0

  run_step "install DeckCraft AppImage" install_deckcraft_files
}

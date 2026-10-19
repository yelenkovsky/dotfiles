register_package cadcraft 360 "CADCraft 2D drafting (DXF/DWG)" install_cadcraft

# Latest GitHub release, linux x86_64 AppImage only. Same author and release
# layout as PdfCraft: SHA256SUMS.txt is published next to the assets, and that
# checksum is required.
CADCRAFT_REPO="storytold/cadcraft"
CADCRAFT_RELEASES_API="https://api.github.com/repos/$CADCRAFT_REPO/releases/latest"
CADCRAFT_APP_ID="ai.storyteller.cadcraft"
CADCRAFT_INSTALL_DIR="/opt/cadcraft"
CADCRAFT_APPIMAGE_NAME="CADCraft.AppImage"
# Headless CLI shipped inside the AppImage (usr/bin). Running the AppImage
# always starts the GUI, so the CLI is copied out for the Claude Code MCP
# server (`cadcraft-cli mcp`).
CADCRAFT_CLI_NAME="cadcraft-cli"
CADCRAFT_MCP_NAME="cadcraft"
CADCRAFT_DOWNLOAD="$STATE_DIR/cadcraft-$TIMESTAMP.AppImage"
CADCRAFT_SUMS_FILE="$STATE_DIR/cadcraft-$TIMESTAMP.SHA256SUMS.txt"
CADCRAFT_EXTRACT_DIR="$STATE_DIR/cadcraft-extract-$TIMESTAMP"
CADCRAFT_DOWNLOAD_URL=""
CADCRAFT_SUMS_URL=""
CADCRAFT_ASSET_NAME=""
# Upstream's MimeType list. CADCraft is made the default opener for all of
# them, plus the application/dxf and application/dwg aliases some apps use.
CADCRAFT_MIME_TYPES=(image/vnd.dxf image/vnd.dwg application/x-dxf application/acad)
CADCRAFT_DEFAULT_TYPES=("${CADCRAFT_MIME_TYPES[@]}" application/dxf application/dwg)
register_update_check cadcraft "$CADCRAFT_DOWNLOAD"
register_changelog cadcraft 'https://github.com/storytold/cadcraft/releases/tag/{version}' '/releases/download/([^/]+)/' 'https://github.com/storytold/cadcraft/releases'

resolve_cadcraft_urls() {
  local json="$STATE_DIR/cadcraft-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api "repos/$CADCRAFT_REPO/releases/latest" \
        --jq '.assets[] | select(.name | test("^cadcraft-[0-9][^/]*-linux-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$CADCRAFT_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^cadcraft-[0-9][^/]*-linux-x86_64\.AppImage$")
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
    CADCRAFT_ASSET_NAME="$name"
    CADCRAFT_DOWNLOAD_URL="$url"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one CADCraft linux x86_64 AppImage, found $count"
    return 1
  fi

  case "$CADCRAFT_DOWNLOAD_URL" in
    "https://github.com/$CADCRAFT_REPO/releases/download/"v[0-9]*/cadcraft-*-linux-x86_64.AppImage) ;;
    *)
      log "Could not resolve the CADCraft x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  CADCRAFT_SUMS_URL="${CADCRAFT_DOWNLOAD_URL%/*}/SHA256SUMS.txt"

  log "CADCraft AppImage: $CADCRAFT_DOWNLOAD_URL"
  return 0
}

download_cadcraft_appimage() {
  download_url_to_file "$CADCRAFT_DOWNLOAD" "$CADCRAFT_DOWNLOAD_URL" || return 1
  download_url_to_file "$CADCRAFT_SUMS_FILE" "$CADCRAFT_SUMS_URL"
}

verify_cadcraft_published_sha256() {
  local expected=""
  local actual=""

  if [ ! -s "$CADCRAFT_DOWNLOAD" ]; then
    log "Downloaded CADCraft file is empty: $CADCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$CADCRAFT_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded CADCraft file looks too small: $CADCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 4 "$CADCRAFT_DOWNLOAD")" != $'\x7fELF' ]; then
    log "Downloaded CADCraft file is not an ELF AppImage: $CADCRAFT_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 11 "$CADCRAFT_DOWNLOAD" | tail -c 3)" != $'AI\x02' ]; then
    log "Downloaded CADCraft file is not an AppImage: $CADCRAFT_ASSET_NAME"
    return 1
  fi

  if [ ! -s "$CADCRAFT_SUMS_FILE" ]; then
    log "Missing published SHA256SUMS.txt for $CADCRAFT_ASSET_NAME"
    return 1
  fi

  expected="$(
    awk -v name="$CADCRAFT_ASSET_NAME" '
      {
        gsub(/\r/, "")
        if ($2 == name) {
          print $1
          exit
        }
      }
    ' "$CADCRAFT_SUMS_FILE"
  )"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $CADCRAFT_ASSET_NAME is missing or not a 64-hex digest"
    return 1
  fi

  actual="$(sha256sum "$CADCRAFT_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $CADCRAFT_ASSET_NAME (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

# Only after the checksum passed: pull the hicolor icons and the CLI out of
# the AppImage.
extract_cadcraft_files() {
  rm -rf "$CADCRAFT_EXTRACT_DIR"
  mkdir -p "$CADCRAFT_EXTRACT_DIR"
  (
    cd "$CADCRAFT_EXTRACT_DIR"
    "$CADCRAFT_DOWNLOAD" --appimage-extract 'usr/share/icons/*' >/dev/null 2>&1 || true
    "$CADCRAFT_DOWNLOAD" --appimage-extract "usr/bin/$CADCRAFT_CLI_NAME" >/dev/null 2>&1 || true
  )
}

install_cadcraft_files() {
  local owner="$USER"
  local group
  local icons="$CADCRAFT_EXTRACT_DIR/squashfs-root/usr/share/icons/hicolor"
  local cli="$CADCRAFT_EXTRACT_DIR/squashfs-root/usr/bin/$CADCRAFT_CLI_NAME"
  local icon rel

  group="$(id -gn "$owner")"

  # Install beside the old file and rename over it, so a running copy never
  # sees a half-written AppImage and a failed copy leaves the old one.
  sudo mkdir -p "$CADCRAFT_INSTALL_DIR" || return 1
  sudo install -m 755 "$CADCRAFT_DOWNLOAD" "$CADCRAFT_INSTALL_DIR/$CADCRAFT_APPIMAGE_NAME.new" || return 1
  sudo mv -f "$CADCRAFT_INSTALL_DIR/$CADCRAFT_APPIMAGE_NAME.new" "$CADCRAFT_INSTALL_DIR/$CADCRAFT_APPIMAGE_NAME" || return 1
  # Same rename for the CLI: MCP servers that are running keep the old file
  # and get the new one on their next start.
  if [ -x "$cli" ] && [ "$(head -c 4 "$cli")" = $'\x7fELF' ]; then
    sudo install -m 755 "$cli" "$CADCRAFT_INSTALL_DIR/$CADCRAFT_CLI_NAME.new" || return 1
    sudo mv -f "$CADCRAFT_INSTALL_DIR/$CADCRAFT_CLI_NAME.new" "$CADCRAFT_INSTALL_DIR/$CADCRAFT_CLI_NAME" || return 1
    sudo ln -sfn "$CADCRAFT_INSTALL_DIR/$CADCRAFT_CLI_NAME" "/usr/local/bin/$CADCRAFT_CLI_NAME" || return 1
  else
    log "Could not extract $CADCRAFT_CLI_NAME from the AppImage; keeping the installed copy, if any"
  fi
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$CADCRAFT_INSTALL_DIR" || return 1
  sudo ln -sfn "$CADCRAFT_INSTALL_DIR/$CADCRAFT_APPIMAGE_NAME" /usr/local/bin/cadcraft || return 1

  # Upstream's desktop entry (packaging/linux), with Exec pointed at the
  # installed launcher.
  sudo tee "/usr/share/applications/$CADCRAFT_APP_ID.desktop" >/dev/null <<EOF || return 1
[Desktop Entry]
Type=Application
Name=CADCraft
GenericName=Computer-Aided Design
Comment=Draft, dimension and plot 2D drawings; open DXF and DWG files
Exec=/usr/local/bin/cadcraft %F
TryExec=/usr/local/bin/cadcraft
Icon=$CADCRAFT_APP_ID
Terminal=false
StartupNotify=true
StartupWMClass=$CADCRAFT_APP_ID
Categories=Graphics;Engineering;VectorGraphics;
MimeType=$(printf '%s;' "${CADCRAFT_MIME_TYPES[@]}")
Keywords=cad;drafting;dxf;dwg;drawing;engineering;architecture;mechanical;
EOF
  sudo chmod 644 "/usr/share/applications/$CADCRAFT_APP_ID.desktop" || return 1

  if [ -d "$icons" ]; then
    while IFS= read -r icon; do
      rel="${icon#"$icons"/}"
      sudo install -D -m 644 "$icon" "/usr/share/icons/hicolor/$rel" || return 1
    done < <(find "$icons" -type f -name "$CADCRAFT_APP_ID.*")
  else
    log "Could not extract CADCraft icons; the desktop entry will use the $CADCRAFT_APP_ID icon name"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
  fi

  set_default_app "$CADCRAFT_APP_ID.desktop" "CADCraft" "${CADCRAFT_DEFAULT_TYPES[@]}"

  rm -rf "$CADCRAFT_EXTRACT_DIR" "$CADCRAFT_DOWNLOAD" "$CADCRAFT_SUMS_FILE"
}

# Add the CLI to Claude Code as a user-scope MCP server, unless a server of
# that name already exists (left alone, so a hand-edited entry survives).
register_cadcraft_mcp() {
  if claude mcp get "$CADCRAFT_MCP_NAME" >/dev/null 2>&1; then
    log "Claude Code already has the $CADCRAFT_MCP_NAME MCP server"
    return 0
  fi
  claude mcp add --scope user "$CADCRAFT_MCP_NAME" -- "$CADCRAFT_INSTALL_DIR/$CADCRAFT_CLI_NAME" mcp
}

install_cadcraft() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve CADCraft AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve CADCraft AppImage"
    log "Skipping CADCraft install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_cadcraft_urls; then
    FAILURES+=("resolve CADCraft x86_64 AppImage")
    record_status "FAIL" "resolve CADCraft x86_64 AppImage"
    return 0
  fi

  run_step "download CADCraft AppImage" download_cadcraft_appimage

  if [ ! -e "$CADCRAFT_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_cadcraft_published_sha256; then
    FAILURES+=("verify CADCraft checksum")
    record_status "FAIL" "verify CADCraft checksum"
    return 0
  fi

  chmod 700 "$CADCRAFT_DOWNLOAD"
  extract_cadcraft_files

  log "Verified CADCraft AppImage; installing to $CADCRAFT_INSTALL_DIR"

  # Only the GUI: the whole install dir would also match the cadcraft-cli
  # MCP servers Claude Code is running, which survive the rename above.
  close_running_app "CADCraft" "$CADCRAFT_INSTALL_DIR/$CADCRAFT_APPIMAGE_NAME" || return 0

  run_step "install CADCraft AppImage" install_cadcraft_files

  if [ -x "$CADCRAFT_INSTALL_DIR/$CADCRAFT_CLI_NAME" ] && command -v claude >/dev/null 2>&1; then
    run_step "register CADCraft MCP server in Claude Code" register_cadcraft_mcp
  fi
}

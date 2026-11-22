# shellcheck shell=bash
register_package freetube 275 "FreeTube" install_freetube

# Newest GitHub release, linux x64 portable zip only (not arm64, armv7l,
# AppImage, .deb, .rpm or .pacman). FreeTube publishes only prereleases
# (v0.x.y-beta), so releases/latest is a 404: take the newest non-draft entry
# of the release list instead. FreeTube publishes no checksum file or
# signature; the SHA-256 is GitHub's asset digest, and it is required.
#
# The tree goes to /opt/FreeTube, where the upstream .deb/.pacman and the AUR
# freetube-bin package put it. User data stays in ~/.config/FreeTube and is
# never touched here.
FREETUBE_REPO="FreeTubeApp/FreeTube"
FREETUBE_RELEASES_API="https://api.github.com/repos/$FREETUBE_REPO/releases?per_page=10"
FREETUBE_INSTALL_DIR="/opt/FreeTube"
FREETUBE_ASSET_PATTERN='^freetube-[0-9][^/]*-linux-x64-portable\.zip$'
FREETUBE_DOWNLOAD="$STATE_DIR/freetube-$TIMESTAMP.zip"
FREETUBE_DOWNLOAD_URL=""
FREETUBE_ASSET_NAME=""
FREETUBE_SHA256=""
# shellcheck disable=SC2034  # passed by name to install_package_group (local -n)
FREETUBE_RUNTIME_PACKAGES=(
  at-spi2-core
  gtk3
  libnotify
  libsecret
  libxss
  libxtst
  nss
  ttf-liberation
  xdg-utils
)
register_update_check freetube "$FREETUBE_DOWNLOAD"
register_changelog freetube 'https://github.com/FreeTubeApp/FreeTube/releases/tag/{version}' '/releases/download/([^/]+)/' 'https://github.com/FreeTubeApp/FreeTube/releases'

resolve_freetube_url() {
  local json="$STATE_DIR/freetube-releases-$TIMESTAMP.json"
  local parsed=""
  local name=""
  local url=""
  local digest=""
  local count=0

  if command -v gh >/dev/null 2>&1; then
    # gh's --jq takes no --arg, so the regex goes into a jq string literal,
    # where each backslash must be doubled.
    local jq_pattern="${FREETUBE_ASSET_PATTERN//\\/\\\\}"
    parsed="$(
      gh api "repos/$FREETUBE_REPO/releases?per_page=10" \
        --jq "[.[] | select(.draft | not)][0].assets[] | select(.name | test(\"$jq_pattern\")) | \"\(.name)\t\(.browser_download_url)\t\(.digest // \"\")\""
    )"
  else
    download_url_to_file "$json" "$FREETUBE_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 -I - "$json" "$FREETUBE_ASSET_PATTERN" <<'PY'
import json
import re
import sys

pattern = re.compile(sys.argv[2])
with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)

release = next((r for r in releases if not r.get("draft")), None)
for asset in (release or {}).get("assets", []):
    name = asset.get("name", "")
    if pattern.fullmatch(name):
        print(name + "\t" + asset["browser_download_url"] + "\t" + (asset.get("digest") or ""))
PY
      )"
    fi
    rm -f "$json"
  fi

  while IFS=$'\t' read -r name url digest; do
    [ -n "$name" ] || continue
    FREETUBE_ASSET_NAME="$name"
    FREETUBE_DOWNLOAD_URL="$url"
    FREETUBE_SHA256="${digest#sha256:}"
    count=$((count + 1))
  done <<< "$parsed"

  if [ "$count" -ne 1 ]; then
    log "Expected one FreeTube linux x64 portable zip in the newest release, found $count"
    return 1
  fi

  case "$FREETUBE_DOWNLOAD_URL" in
    "https://github.com/$FREETUBE_REPO/releases/download/"v[0-9]*/freetube-*-linux-x64-portable.zip) ;;
    *)
      log "Could not resolve the FreeTube linux x64 zip from GitHub releases"
      return 1
      ;;
  esac

  FREETUBE_SHA256="${FREETUBE_SHA256,,}"
  if [[ ! "$FREETUBE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    log "GitHub gives no SHA-256 digest for $FREETUBE_ASSET_NAME; refusing to install it unverified"
    return 1
  fi

  log "FreeTube zip: $FREETUBE_DOWNLOAD_URL"
  return 0
}

download_freetube_zip() {
  download_url_to_file "$FREETUBE_DOWNLOAD" "$FREETUBE_DOWNLOAD_URL"
}

verify_freetube_zip() {
  local actual=""

  if [ ! -s "$FREETUBE_DOWNLOAD" ]; then
    log "Downloaded FreeTube file is empty: $FREETUBE_ASSET_NAME"
    return 1
  fi

  if [ "$(stat -c%s "$FREETUBE_DOWNLOAD")" -lt 10000000 ]; then
    log "Downloaded FreeTube file looks too small: $FREETUBE_ASSET_NAME"
    return 1
  fi

  if [ "$(head -c 2 "$FREETUBE_DOWNLOAD")" != 'PK' ]; then
    log "Downloaded FreeTube file is not a zip archive: $FREETUBE_ASSET_NAME"
    return 1
  fi

  actual="$(sha256sum "$FREETUBE_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual" != "$FREETUBE_SHA256" ]; then
    log "SHA-256 mismatch for $FREETUBE_ASSET_NAME (expected $FREETUBE_SHA256, got $actual)"
    return 1
  fi

  return 0
}

# The zip has no icon file; the app's own colour icon is inside app.asar. An
# asar is an 8-byte prefix (the second uint32 is the header length), a JSON
# index, then the file data at the offsets the index gives. Best effort: no
# python3 or no icon only means the desktop entry falls back to the icon name.
extract_freetube_icon() {
  local asar="$1"
  local out="$2"

  command -v python3 >/dev/null 2>&1 || return 1
  python3 -I - "$asar" "$out" <<'PY'
import json
import struct
import sys

with open(sys.argv[1], "rb") as handle:
    prefix = handle.read(16)
    header_size = struct.unpack("<I", prefix[4:8])[0]
    json_size = struct.unpack("<I", prefix[12:16])[0]
    index = json.loads(handle.read(json_size))
    entry = index
    for part in ("dist", "imgs", "iconColorSmall.svg"):
        entry = entry["files"][part]
    handle.seek(8 + header_size + int(entry["offset"]))
    data = handle.read(int(entry["size"]))

if b"<svg" not in data[:512]:
    sys.exit(1)
with open(sys.argv[2], "wb") as handle:
    handle.write(data)
PY
}

install_freetube_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/freetube-extract-$TIMESTAMP"
  local appdir=""
  local icon="$STATE_DIR/freetube-icon-$TIMESTAMP.svg"

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$FREETUBE_DOWNLOAD" || return 1

  if [ -f "$work/freetube" ]; then
    appdir="$work"
  else
    appdir="$(find "$work" -type f -name freetube -printf '%h\n' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -f "$appdir/freetube" ] || [ ! -f "$appdir/resources/app.asar" ]; then
    log "FreeTube zip does not contain the freetube launcher and resources/app.asar"
    return 1
  fi

  if [ "$(head -c 4 "$appdir/freetube")" != $'\x7fELF' ]; then
    log "FreeTube launcher is not an ELF binary"
    return 1
  fi

  # Stage, swap and only then drop the old tree, so a failed copy keeps the
  # working install. Refuses while the AUR freetube-bin package owns the dir.
  replace_install_tree "$appdir" "$FREETUBE_INSTALL_DIR" "$owner:$group" || return 1
  sudo chmod -R go-w "$FREETUBE_INSTALL_DIR" || return 1
  sudo chmod 755 "$FREETUBE_INSTALL_DIR/freetube" || return 1

  # freetube-bin's /usr/bin/freetube symlink outlives a --dbonly handover and
  # comes before /usr/local/bin on PATH; it starts FreeTube without
  # --no-sandbox, which a user-owned chrome-sandbox cannot run. The sudo guard
  # refuses this while pacman still owns it.
  if [ -L /usr/bin/freetube ] && [ "$(readlink /usr/bin/freetube)" = "$FREETUBE_INSTALL_DIR/freetube" ]; then
    sudo rm -f /usr/bin/freetube || return 1
  fi

  # chrome-sandbox cannot be setuid on a user-owned tree.
  sudo tee /usr/local/bin/freetube >/dev/null <<EOF || return 1
#!/bin/sh
exec "$FREETUBE_INSTALL_DIR/freetube" --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/freetube || return 1

  # Same file name and fields as upstream's entry, so pinned launchers and the
  # freetube:// handler keep working.
  sudo tee /usr/share/applications/freetube.desktop >/dev/null <<EOF || return 1
[Desktop Entry]
Name=FreeTube
Comment=A private YouTube client
Exec=/usr/local/bin/freetube %U
TryExec=/usr/local/bin/freetube
Icon=freetube
Terminal=false
Type=Application
StartupWMClass=FreeTube
StartupNotify=true
MimeType=x-scheme-handler/freetube;
Categories=AudioVideo;Video;Player;Feed;Network;
EOF
  sudo chmod 644 /usr/share/applications/freetube.desktop || return 1

  if extract_freetube_icon "$appdir/resources/app.asar" "$icon"; then
    sudo install -D -m 644 "$icon" /usr/share/icons/hicolor/scalable/apps/freetube.svg || return 1
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
      sudo gtk-update-icon-cache -q /usr/share/icons/hicolor || true
    fi
  else
    log "Could not extract the FreeTube icon; the desktop entry will use the freetube icon name"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi

  rm -rf "$work" "$icon" "$FREETUBE_DOWNLOAD"
}

install_freetube() {
  install_package_group pacman "FreeTube runtime packages" FREETUBE_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download FreeTube zip (missing required command: curl or wget)")
    record_status "FAIL" "download FreeTube zip"
    log "Skipping FreeTube install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract FreeTube zip (missing required command: bsdtar)")
    record_status "FAIL" "extract FreeTube zip"
    log "Skipping FreeTube install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_freetube_url; then
    FAILURES+=("resolve FreeTube linux x64 zip")
    record_status "FAIL" "resolve FreeTube linux x64 zip"
    return 0
  fi

  run_step "download FreeTube zip" download_freetube_zip

  if [ ! -e "$FREETUBE_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_freetube_zip; then
    FAILURES+=("verify FreeTube checksum")
    record_status "FAIL" "verify FreeTube checksum"
    return 0
  fi

  log "Verified FreeTube zip; installing to $FREETUBE_INSTALL_DIR"

  close_running_app --relaunch /usr/local/bin/freetube "FreeTube" "$FREETUBE_INSTALL_DIR" || return 0

  run_step "install FreeTube" install_freetube_files
}

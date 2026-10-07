register_package mayo 330 "Mayo CAD viewer" install_mayo

# Latest GitHub release, linux x86_64 glibc AppImages only.
# Mayo publishes a .sha256 next to each file; that checksum is required.
MAYO_RELEASES_API="https://api.github.com/repos/fougue/mayo/releases/latest"
MAYO_INSTALL_DIR="/opt/mayo"
MAYO_APPIMAGE_NAME="Mayo.AppImage"
MAYO_CONV_NAME="MayoConv.AppImage"
MAYO_DOWNLOAD="$STATE_DIR/mayo-$TIMESTAMP.AppImage"
MAYO_SHA_FILE="$STATE_DIR/mayo-$TIMESTAMP.AppImage.sha256"
MAYO_CONV_DOWNLOAD="$STATE_DIR/mayo-conv-$TIMESTAMP.AppImage"
MAYO_CONV_SHA_FILE="$STATE_DIR/mayo-conv-$TIMESTAMP.AppImage.sha256"
MAYO_ICON_DIR="$STATE_DIR/mayo-icon-$TIMESTAMP"
MAYO_DOWNLOAD_URL=""
MAYO_ASSET_NAME=""
MAYO_CONV_DOWNLOAD_URL=""
MAYO_CONV_ASSET_NAME=""

resolve_mayo_urls() {
  local json="$STATE_DIR/mayo-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/fougue/mayo/releases/latest \
        --jq '.assets[] | select(.name | test("^(Mayo|MayoConv)-[0-9].*-x86_64\\.AppImage$")) | "\(.name)\t\(.browser_download_url)"'
    )"
  else
    download_url_to_file "$json" "$MAYO_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^(Mayo|MayoConv)-[0-9].*-x86_64\.AppImage$")
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

  local name=""
  local url=""
  while IFS=$'\t' read -r name url; do
    [ -n "$name" ] || continue
    case "$name" in
      MayoConv-*-x86_64.AppImage)
        MAYO_CONV_ASSET_NAME="$name"
        MAYO_CONV_DOWNLOAD_URL="$url"
        ;;
      Mayo-*-x86_64.AppImage)
        MAYO_ASSET_NAME="$name"
        MAYO_DOWNLOAD_URL="$url"
        ;;
    esac
  done <<< "$parsed"

  case "$MAYO_DOWNLOAD_URL" in
    https://github.com/fougue/mayo/releases/download/*/Mayo-*-x86_64.AppImage) ;;
    *)
      log "Could not resolve the Mayo x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  case "$MAYO_CONV_DOWNLOAD_URL" in
    https://github.com/fougue/mayo/releases/download/*/MayoConv-*-x86_64.AppImage) ;;
    *)
      log "Could not resolve the MayoConv x86_64 AppImage from GitHub releases"
      return 1
      ;;
  esac

  log "Mayo AppImage: $MAYO_DOWNLOAD_URL"
  log "MayoConv AppImage: $MAYO_CONV_DOWNLOAD_URL"
  return 0
}

download_mayo_appimages() {
  download_url_to_file "$MAYO_DOWNLOAD" "$MAYO_DOWNLOAD_URL"
  download_url_to_file "$MAYO_SHA_FILE" "${MAYO_DOWNLOAD_URL}.sha256"
  download_url_to_file "$MAYO_CONV_DOWNLOAD" "$MAYO_CONV_DOWNLOAD_URL"
  download_url_to_file "$MAYO_CONV_SHA_FILE" "${MAYO_CONV_DOWNLOAD_URL}.sha256"
}

verify_mayo_published_sha256() {
  local file="$1"
  local shafile="$2"
  local expected_name="$3"
  local expected=""
  local listed_name=""
  local actual=""

  if [ ! -s "$file" ]; then
    log "Downloaded Mayo file is empty: $expected_name"
    return 1
  fi

  if [ "$(stat -c%s "$file")" -lt 10000000 ]; then
    log "Downloaded Mayo file looks too small: $expected_name"
    return 1
  fi

  if [ "$(head -c 4 "$file")" != $'\x7fELF' ]; then
    log "Downloaded Mayo file is not an ELF AppImage: $expected_name"
    return 1
  fi

  if [ ! -s "$shafile" ]; then
    log "Missing published SHA-256 next to $expected_name"
    return 1
  fi

  read -r expected listed_name < "$shafile"
  listed_name="${listed_name%$'\r'}"
  expected="${expected,,}"

  if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    log "Published SHA-256 for $expected_name is not a 64-hex digest"
    return 1
  fi

  if [ "$listed_name" != "$expected_name" ]; then
    log "Published SHA-256 names '$listed_name', expected '$expected_name'"
    return 1
  fi

  actual="$(sha256sum "$file" | awk '{ print $1 }')"
  if [ "$actual" != "$expected" ]; then
    log "SHA-256 mismatch for $expected_name (expected $expected, got $actual)"
    return 1
  fi

  return 0
}

extract_mayo_icon() {
  local icon=""

  mkdir -p "$MAYO_ICON_DIR"
  (
    cd "$MAYO_ICON_DIR"
    "$MAYO_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/*/apps/*' >/dev/null 2>&1 || true
    "$MAYO_DOWNLOAD" --appimage-extract 'usr/share/pixmaps/*' >/dev/null 2>&1 || true
    "$MAYO_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
    "$MAYO_DOWNLOAD" --appimage-extract '*.svg' >/dev/null 2>&1 || true
  )

  icon="$(find "$MAYO_ICON_DIR" -type f \( -name '*.png' -o -name '*.svg' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    case "$icon" in
      *.svg)
        sudo install -D -m 644 "$icon" /usr/share/icons/hicolor/scalable/apps/mayo.svg
        ;;
      *)
        sudo install -D -m 644 "$icon" /usr/share/pixmaps/mayo.png
        ;;
    esac
    log "Installed Mayo icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Mayo icon; desktop entry will use the mayo icon name"
  return 0
}

install_mayo_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$MAYO_INSTALL_DIR"
  sudo install -D -m 755 "$MAYO_DOWNLOAD" "$MAYO_INSTALL_DIR/$MAYO_APPIMAGE_NAME"
  sudo install -D -m 755 "$MAYO_CONV_DOWNLOAD" "$MAYO_INSTALL_DIR/$MAYO_CONV_NAME"
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$MAYO_INSTALL_DIR"
  sudo chmod u+rwX "$MAYO_INSTALL_DIR" \
    "$MAYO_INSTALL_DIR/$MAYO_APPIMAGE_NAME" \
    "$MAYO_INSTALL_DIR/$MAYO_CONV_NAME"
  sudo ln -sfn "$MAYO_INSTALL_DIR/$MAYO_APPIMAGE_NAME" /usr/local/bin/mayo
  sudo ln -sfn "$MAYO_INSTALL_DIR/$MAYO_CONV_NAME" /usr/local/bin/mayo-conv

  sudo tee /usr/share/applications/mayo.desktop >/dev/null <<EOF
[Desktop Entry]
Version=1.0
Name=Mayo
Comment=Opensource 3D CAD viewer and converter
Exec=$MAYO_INSTALL_DIR/$MAYO_APPIMAGE_NAME %U
Icon=mayo
Terminal=false
Type=Application
Categories=Graphics;3DGraphics;Viewer;Engineering;Qt;
Keywords=Converter;stl;cad;step;iges;opencascade;
MimeType=model/step;model/iges;model/gltf+json;model/gltf.binary;application/vnd.ms-pki.stl;model/x.stl-ascii;model/x.stl-binary;application/x-wavefront-obj;model/x-brep;model/x-ply;
StartupWMClass=Mayo
EOF
  sudo chmod 644 /usr/share/applications/mayo.desktop
  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  extract_mayo_icon
  rm -rf "$MAYO_ICON_DIR" "$MAYO_DOWNLOAD" "$MAYO_SHA_FILE" "$MAYO_CONV_DOWNLOAD" "$MAYO_CONV_SHA_FILE"
}

install_mayo() {
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Mayo AppImage (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Mayo AppImage"
    log "Skipping Mayo install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! resolve_mayo_urls; then
    FAILURES+=("resolve Mayo x86_64 AppImage")
    record_status "FAIL" "resolve Mayo x86_64 AppImage"
    return 0
  fi

  run_step "download Mayo AppImages" download_mayo_appimages

  if [ ! -e "$MAYO_DOWNLOAD" ] || [ ! -e "$MAYO_CONV_DOWNLOAD" ]; then
    return 0
  fi

  if ! verify_mayo_published_sha256 "$MAYO_DOWNLOAD" "$MAYO_SHA_FILE" "$MAYO_ASSET_NAME"; then
    FAILURES+=("verify Mayo checksum")
    record_status "FAIL" "verify Mayo checksum"
    return 0
  fi

  if ! verify_mayo_published_sha256 "$MAYO_CONV_DOWNLOAD" "$MAYO_CONV_SHA_FILE" "$MAYO_CONV_ASSET_NAME"; then
    FAILURES+=("verify MayoConv checksum")
    record_status "FAIL" "verify MayoConv checksum"
    return 0
  fi

  chmod 700 "$MAYO_DOWNLOAD" "$MAYO_CONV_DOWNLOAD"
  log "Verified Mayo AppImages; installing to $MAYO_INSTALL_DIR"

  run_step "install Mayo AppImages" install_mayo_files
}

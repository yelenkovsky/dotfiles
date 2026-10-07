register_package printcraft 350 "PrintCraft PDF workbench" install_printcraft

# Latest GitHub release, linux x86_64 AppImage only.
# PrintCraft publishes SHA256SUMS.txt next to the assets; that checksum is required.
PRINTCRAFT_RELEASES_API="https://api.github.com/repos/storytold/printcraft/releases/latest"
PRINTCRAFT_INSTALL_DIR="/opt/printcraft"
PRINTCRAFT_APPIMAGE_NAME="PrintCraft.AppImage"
PRINTCRAFT_DOWNLOAD="$STATE_DIR/printcraft-$TIMESTAMP.AppImage"
PRINTCRAFT_SUMS_FILE="$STATE_DIR/printcraft-$TIMESTAMP.SHA256SUMS.txt"
PRINTCRAFT_ICON_DIR="$STATE_DIR/printcraft-icon-$TIMESTAMP"
PRINTCRAFT_MODELS_DIR="$PRINTCRAFT_INSTALL_DIR/models"
PRINTCRAFT_ATTRIBUTION="$STATE_DIR/printcraft-$TIMESTAMP-ATTRIBUTION.toml"
PRINTCRAFT_MODELS_LIST="$STATE_DIR/printcraft-$TIMESTAMP-models.tsv"
PRINTCRAFT_MODELS_STAGE="$STATE_DIR/printcraft-models-$TIMESTAMP"
PRINTCRAFT_DOWNLOAD_URL=""
PRINTCRAFT_SUMS_URL=""
PRINTCRAFT_ATTRIBUTION_URL=""
PRINTCRAFT_ASSET_NAME=""
PRINTCRAFT_TAG=""

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

  PRINTCRAFT_TAG="${PRINTCRAFT_DOWNLOAD_URL#https://github.com/storytold/printcraft/releases/download/}"
  PRINTCRAFT_TAG="${PRINTCRAFT_TAG%%/*}"
  case "$PRINTCRAFT_TAG" in
    v[0-9]*) ;;
    *)
      log "Could not resolve the PrintCraft release tag from $PRINTCRAFT_DOWNLOAD_URL"
      return 1
      ;;
  esac

  PRINTCRAFT_ATTRIBUTION_URL="https://raw.githubusercontent.com/storytold/printcraft/${PRINTCRAFT_TAG}/ATTRIBUTION.toml"
  case "$PRINTCRAFT_ATTRIBUTION_URL" in
    https://raw.githubusercontent.com/storytold/printcraft/v[0-9]*/ATTRIBUTION.toml) ;;
    *)
      log "Could not resolve PrintCraft ATTRIBUTION.toml"
      return 1
      ;;
  esac

  log "PrintCraft AppImage: $PRINTCRAFT_DOWNLOAD_URL"
  log "PrintCraft OCR models: $PRINTCRAFT_ATTRIBUTION_URL"
  return 0
}

download_printcraft_appimage() {
  download_url_to_file "$PRINTCRAFT_DOWNLOAD" "$PRINTCRAFT_DOWNLOAD_URL"
  download_url_to_file "$PRINTCRAFT_SUMS_FILE" "$PRINTCRAFT_SUMS_URL"
}

# The AppImage looks for text-detection.rten and text-recognition.rten via
# PRINTCRAFT_MODELS. Those files are the `kind = "model"` rows in the release's
# ATTRIBUTION.toml, the same ones `cargo xtask models` fetches.
download_printcraft_models() {
  local file=""
  local url=""
  local sha=""
  local licence_url=""
  local licence_sha=""

  download_url_to_file "$PRINTCRAFT_ATTRIBUTION" "$PRINTCRAFT_ATTRIBUTION_URL"
  python3 - "$PRINTCRAFT_ATTRIBUTION" "$PRINTCRAFT_MODELS_LIST" <<'PY'
import sys
import tomllib
from pathlib import Path

source, dest = sys.argv[1:]
data = tomllib.loads(Path(source).read_text(encoding="utf-8"))
rows = []
for item in data.get("fetched", []):
    if item.get("kind") != "model":
        continue
    file = item.get("file", "")
    url = item.get("url", "")
    sha = item.get("sha256", "").lower()
    licence_url = item.get("licence_url", "")
    licence_sha = item.get("licence_sha256", "").lower()
    if "/" in file or file in ("", ".", "..") or not file.endswith(".rten"):
        raise SystemExit(f"refusing model filename {file!r}")
    if not url.startswith("https://") or not licence_url.startswith("https://"):
        raise SystemExit(f"refusing non-https model URL for {file}")
    if len(sha) != 64 or len(licence_sha) != 64 or any(c not in "0123456789abcdef" for c in sha + licence_sha):
        raise SystemExit(f"bad SHA-256 for {file}")
    rows.append("\t".join((file, url, sha, licence_url, licence_sha)))

needed = {"text-detection.rten", "text-recognition.rten"}
got = {row.split("\t", 1)[0] for row in rows}
missing = needed - got
if missing:
    raise SystemExit("ATTRIBUTION.toml is missing OCR models: " + ", ".join(sorted(missing)))
Path(dest).write_text("\n".join(rows) + "\n", encoding="utf-8")
PY

  mkdir -p "$PRINTCRAFT_MODELS_STAGE"
  while IFS=$'\t' read -r file url sha licence_url licence_sha; do
    [ -n "$file" ] || continue
    download_url_to_file "$PRINTCRAFT_MODELS_STAGE/$file" "$url"
    download_url_to_file "$PRINTCRAFT_MODELS_STAGE/${file}.LICENCE.txt" "$licence_url"
  done < "$PRINTCRAFT_MODELS_LIST"
}

verify_printcraft_models() {
  local file=""
  local url=""
  local sha=""
  local licence_url=""
  local licence_sha=""
  local actual=""
  local count=0

  if [ ! -s "$PRINTCRAFT_MODELS_LIST" ]; then
    log "PrintCraft model list is missing"
    return 1
  fi

  while IFS=$'\t' read -r file url sha licence_url licence_sha; do
    [ -n "$file" ] || continue
    count=$((count + 1))
    if [ ! -s "$PRINTCRAFT_MODELS_STAGE/$file" ]; then
      log "Downloaded PrintCraft model is empty: $file"
      return 1
    fi
    actual="$(sha256sum "$PRINTCRAFT_MODELS_STAGE/$file" | awk '{ print $1 }')"
    if [ "$actual" != "$sha" ]; then
      log "SHA-256 mismatch for $file (expected $sha, got $actual)"
      return 1
    fi
    if [ ! -s "$PRINTCRAFT_MODELS_STAGE/${file}.LICENCE.txt" ]; then
      log "Downloaded PrintCraft model licence is empty: $file"
      return 1
    fi
    actual="$(sha256sum "$PRINTCRAFT_MODELS_STAGE/${file}.LICENCE.txt" | awk '{ print $1 }')"
    if [ "$actual" != "$licence_sha" ]; then
      log "SHA-256 mismatch for ${file}.LICENCE.txt (expected $licence_sha, got $actual)"
      return 1
    fi
    log "Verified PrintCraft model $file"
  done < "$PRINTCRAFT_MODELS_LIST"

  if [ "$count" -lt 1 ]; then
    log "PrintCraft ATTRIBUTION.toml listed no OCR models"
    return 1
  fi

  return 0
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

  sudo mkdir -p "$PRINTCRAFT_INSTALL_DIR" "$PRINTCRAFT_MODELS_DIR"
  sudo install -D -m 755 "$PRINTCRAFT_DOWNLOAD" "$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME"
  sudo cp -a "$PRINTCRAFT_MODELS_STAGE"/. "$PRINTCRAFT_MODELS_DIR"/
  # User owns the tree so a later in-app replace does not need root.
  sudo chown -R "$owner:$group" "$PRINTCRAFT_INSTALL_DIR"
  sudo chmod u+rwX "$PRINTCRAFT_INSTALL_DIR" "$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME"
  # The mounted AppImage binary does not see files beside the .AppImage.
  # Remove any previous path first so tee cannot follow a symlink into it.
  sudo rm -f /usr/local/bin/printcraft
  sudo tee /usr/local/bin/printcraft >/dev/null <<EOF
#!/bin/bash
export PRINTCRAFT_MODELS="$PRINTCRAFT_MODELS_DIR"
exec "$PRINTCRAFT_INSTALL_DIR/$PRINTCRAFT_APPIMAGE_NAME" "\$@"
EOF
  sudo chmod 755 /usr/local/bin/printcraft

  sudo tee /usr/share/applications/printcraft.desktop >/dev/null <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=PrintCraft
GenericName=PDF Editor
Comment=Read, organize, combine, split and secure PDFs
Exec=/usr/local/bin/printcraft %F
TryExec=/usr/local/bin/printcraft
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
  rm -rf "$PRINTCRAFT_ICON_DIR" "$PRINTCRAFT_DOWNLOAD" "$PRINTCRAFT_SUMS_FILE" \
    "$PRINTCRAFT_ATTRIBUTION" "$PRINTCRAFT_MODELS_LIST" "$PRINTCRAFT_MODELS_STAGE"
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
  log "Verified PrintCraft AppImage"

  if ! command -v python3 >/dev/null 2>&1; then
    FAILURES+=("download PrintCraft OCR models (missing required command: python3)")
    record_status "FAIL" "download PrintCraft OCR models"
    log "Skipping PrintCraft OCR models because python3 is not installed"
    return 0
  fi

  run_step "download PrintCraft OCR models" download_printcraft_models

  if [ ! -s "$PRINTCRAFT_MODELS_LIST" ]; then
    return 0
  fi

  if ! verify_printcraft_models; then
    FAILURES+=("verify PrintCraft OCR models")
    record_status "FAIL" "verify PrintCraft OCR models"
    return 0
  fi

  log "Verified PrintCraft OCR models; installing to $PRINTCRAFT_INSTALL_DIR"

  run_step "install PrintCraft AppImage" install_printcraft_files
}

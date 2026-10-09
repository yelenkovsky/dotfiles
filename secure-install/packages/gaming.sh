register_package gaming 50 "Gaming packages" install_gaming

# proton-cachyos-slr on the AUR is the baseline x86_64 Steam Linux Runtime build.
# The x86-64-v3 build is a separate GitHub release asset. Steam discovers it
# only from compatibilitytools.d, which is why it does not go under /opt.
PACMAN_GAMING_PACKAGES=(
  steam
  gamemode
  lib32-gamemode
  mangohud
  lib32-mangohud
  nvidia-prime
)

AUR_GAMING_PACKAGES=(
  mangojuice
)

PROTON_CACHYOS_RELEASES_API="https://api.github.com/repos/CachyOS/proton-cachyos/releases?per_page=20"
PROTON_CACHYOS_COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
PROTON_CACHYOS_DOWNLOAD="$STATE_DIR/proton-cachyos-slr-v3-$TIMESTAMP.tar.xz"
PROTON_CACHYOS_SHA512_FILE="$STATE_DIR/proton-cachyos-slr-v3-$TIMESTAMP.sha512sum"
PROTON_CACHYOS_DOWNLOAD_URL=""
PROTON_CACHYOS_SHA512=""
PROTON_CACHYOS_TOOL_NAME=""

cpu_supports_x86_64_v3() {
  local loader="/lib/ld-linux-x86-64.so.2"

  [ -x "$loader" ] || return 1
  "$loader" --help 2>/dev/null | grep -q 'x86-64-v3 (supported'
}

resolve_proton_cachyos_slr_v3() {
  local json="$STATE_DIR/proton-cachyos-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api "repos/CachyOS/proton-cachyos/releases?per_page=20" \
        --jq '[.[] | .assets[] | select(.name | test("^proton-cachyos-.+-slr-x86_64_v3\\.tar\\.xz$")) | select(.name | contains("sunset") | not)] | .[0].browser_download_url // empty'
    )"
  else
    download_url_to_file "$json" "$PROTON_CACHYOS_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

pattern = re.compile(r"^proton-cachyos-.+-slr-x86_64_v3\.tar\.xz$")

with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)

for release in releases:
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if "sunset" in name or not pattern.match(name):
            continue
        print(asset.get("browser_download_url", ""))
        raise SystemExit
PY
      )"
    fi
    rm -f "$json"
  fi

  case "$parsed" in
    https://github.com/CachyOS/proton-cachyos/releases/download/*/proton-cachyos-*-slr-x86_64_v3.tar.xz) ;;
    *)
      log "Could not resolve a Proton-CachyOS SLR x86-64-v3 tarball from GitHub releases"
      return 1
      ;;
  esac

  PROTON_CACHYOS_DOWNLOAD_URL="$parsed"
  PROTON_CACHYOS_TOOL_NAME="${parsed##*/}"
  PROTON_CACHYOS_TOOL_NAME="${PROTON_CACHYOS_TOOL_NAME%.tar.xz}"
  log "Proton-CachyOS SLR v3: $PROTON_CACHYOS_DOWNLOAD_URL"
  return 0
}

download_proton_cachyos_slr_v3_checksum() {
  download_url_to_file "$PROTON_CACHYOS_SHA512_FILE" "${PROTON_CACHYOS_DOWNLOAD_URL%.tar.xz}.sha512sum"
}

read_proton_cachyos_slr_v3_checksum() {
  local filename="${PROTON_CACHYOS_TOOL_NAME}.tar.xz"

  PROTON_CACHYOS_SHA512="$(
    awk -v name="$filename" '
      {
        file = $2
        sub(/^\*/, "", file)
        if (file == name) {
          print $1
          exit
        }
      }
    ' "$PROTON_CACHYOS_SHA512_FILE"
  )"

  if [ -z "$PROTON_CACHYOS_SHA512" ]; then
    log "No SHA-512 for $filename in the Proton-CachyOS checksum file"
    return 1
  fi

  return 0
}

download_proton_cachyos_slr_v3_tarball() {
  download_url_to_file "$PROTON_CACHYOS_DOWNLOAD" "$PROTON_CACHYOS_DOWNLOAD_URL"
}

install_proton_cachyos_slr_v3_files() {
  local work="$STATE_DIR/proton-cachyos-slr-v3-extract-$TIMESTAMP"
  local appdir=""
  local dest="$PROTON_CACHYOS_COMPAT_DIR/$PROTON_CACHYOS_TOOL_NAME"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$PROTON_CACHYOS_DOWNLOAD"

  if [ -f "$work/$PROTON_CACHYOS_TOOL_NAME/proton" ]; then
    appdir="$work/$PROTON_CACHYOS_TOOL_NAME"
  else
    appdir="$(find "$work" -type f -name proton -printf '%h\n' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -f "$appdir/proton" ] || [ ! -f "$appdir/compatibilitytool.vdf" ]; then
    log "Proton-CachyOS tarball does not contain a proton compatibility tool"
    rm -rf "$work"
    return 1
  fi

  mkdir -p "$PROTON_CACHYOS_COMPAT_DIR"
  rm -rf "$dest"
  cp -a "$appdir" "$dest"
  rm -rf "$work" "$PROTON_CACHYOS_DOWNLOAD" "$PROTON_CACHYOS_SHA512_FILE"
  log "Installed Proton-CachyOS SLR v3 to $dest"
}

remove_baseline_proton_cachyos_slr() {
  local -a command

  if ! pacman -Q proton-cachyos-slr >/dev/null 2>&1; then
    log "Baseline proton-cachyos-slr package is not installed"
    return 0
  fi

  command=(sudo pacman -R)
  [ "$ASSUME_YES" = true ] && command+=(--noconfirm)
  command+=(proton-cachyos-slr)
  "${command[@]}"
}

install_proton_cachyos_ntsync() {
  if ! modinfo ntsync >/dev/null 2>&1; then
    log "Kernel has no ntsync module; skipping modules-load.d entry"
    return 0
  fi

  printf 'ntsync\n' | sudo tee /etc/modules-load.d/proton-cachyos-slr.conf >/dev/null
}

install_proton_cachyos_slr_v3() {
  local file_size=0
  local actual_hash=""
  local dest=""

  if ! cpu_supports_x86_64_v3; then
    FAILURES+=("install Proton-CachyOS SLR v3 (CPU does not support x86-64-v3)")
    record_status "FAIL" "install Proton-CachyOS SLR v3"
    log "Skipping Proton-CachyOS SLR v3 because this CPU does not support x86-64-v3"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Proton-CachyOS SLR v3 (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Proton-CachyOS SLR v3"
    log "Skipping Proton-CachyOS SLR v3 because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Proton-CachyOS SLR v3 (missing required command: bsdtar)")
    record_status "FAIL" "extract Proton-CachyOS SLR v3"
    log "Skipping Proton-CachyOS SLR v3 because bsdtar is not installed"
    return 0
  fi

  if ! resolve_proton_cachyos_slr_v3; then
    FAILURES+=("resolve Proton-CachyOS SLR x86-64-v3 tarball")
    record_status "FAIL" "resolve Proton-CachyOS SLR x86-64-v3 tarball"
    return 0
  fi

  dest="$PROTON_CACHYOS_COMPAT_DIR/$PROTON_CACHYOS_TOOL_NAME"
  if [ -f "$dest/proton" ] && [ -f "$dest/compatibilitytool.vdf" ]; then
    log "Proton-CachyOS SLR v3 already installed: $dest"
  else
    run_step "download Proton-CachyOS SLR v3 checksum" download_proton_cachyos_slr_v3_checksum

    if [ ! -s "$PROTON_CACHYOS_SHA512_FILE" ]; then
      if [ "$DRY_RUN" != true ]; then
        FAILURES+=("download Proton-CachyOS SLR v3 checksum")
        record_status "FAIL" "download Proton-CachyOS SLR v3 checksum"
      fi
      return 0
    fi

    if ! read_proton_cachyos_slr_v3_checksum; then
      FAILURES+=("parse Proton-CachyOS SLR v3 SHA-512")
      record_status "FAIL" "parse Proton-CachyOS SLR v3 SHA-512"
      return 0
    fi

    run_step "download Proton-CachyOS SLR v3 tarball" download_proton_cachyos_slr_v3_tarball

    if [ ! -e "$PROTON_CACHYOS_DOWNLOAD" ]; then
      return 0
    fi

    if [ ! -s "$PROTON_CACHYOS_DOWNLOAD" ]; then
      FAILURES+=("download Proton-CachyOS SLR v3 tarball (empty file)")
      record_status "FAIL" "download Proton-CachyOS SLR v3 tarball"
      log "Downloaded Proton-CachyOS file is empty: $PROTON_CACHYOS_DOWNLOAD"
      return 0
    fi

    file_size="$(stat -c%s "$PROTON_CACHYOS_DOWNLOAD")"
    if [ "$file_size" -lt 10000000 ]; then
      FAILURES+=("download Proton-CachyOS SLR v3 tarball (file too small: ${file_size} bytes)")
      record_status "FAIL" "download Proton-CachyOS SLR v3 tarball"
      log "Downloaded Proton-CachyOS file looks too small: $PROTON_CACHYOS_DOWNLOAD ($file_size bytes)"
      return 0
    fi

    if [ "$(head -c 6 "$PROTON_CACHYOS_DOWNLOAD")" != $'\xfd7zXZ\x00' ]; then
      FAILURES+=("download Proton-CachyOS SLR v3 tarball (not an xz archive)")
      record_status "FAIL" "download Proton-CachyOS SLR v3 tarball"
      log "Downloaded Proton-CachyOS file is not an xz archive: $PROTON_CACHYOS_DOWNLOAD"
      return 0
    fi

    actual_hash="$(sha512sum "$PROTON_CACHYOS_DOWNLOAD" | awk '{ print $1 }')"
    if [ "$actual_hash" != "$PROTON_CACHYOS_SHA512" ]; then
      FAILURES+=("verify Proton-CachyOS SLR v3 checksum")
      record_status "FAIL" "verify Proton-CachyOS SLR v3 checksum"
      log "Proton-CachyOS SHA-512 mismatch (expected $PROTON_CACHYOS_SHA512, got $actual_hash)"
      rm -f "$PROTON_CACHYOS_DOWNLOAD"
      return 0
    fi

    log "Verified Proton-CachyOS SLR v3 SHA-512 ($file_size bytes)"
    run_step "install Proton-CachyOS SLR v3" install_proton_cachyos_slr_v3_files

    if [ ! -f "$dest/proton" ]; then
      return 0
    fi
  fi

  run_step "remove baseline proton-cachyos-slr package" remove_baseline_proton_cachyos_slr
  run_step "enable ntsync for Proton-CachyOS" install_proton_cachyos_ntsync
}

install_gaming() {
  install_package_group pacman "Gaming packages" PACMAN_GAMING_PACKAGES
  install_package_group yay "Gaming AUR packages" AUR_GAMING_PACKAGES
  install_proton_cachyos_slr_v3
}

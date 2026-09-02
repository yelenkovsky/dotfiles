register_package debtap 260 "debtap" install_debtap

DEBTAP_RELEASES_API="https://api.github.com/repos/helixarch/debtap/releases/latest"
DEBTAP_TARBALL="$STATE_DIR/debtap-$TIMESTAMP.tar.gz"
DEBTAP_EXTRACT="$STATE_DIR/debtap-extract-$TIMESTAMP"
DEBTAP_BIN="/usr/local/bin/debtap"
DEBTAP_TARBALL_URL=""
DEBTAP_RUNTIME_PACKAGES=(
  binutils
  fakeroot
  file
)

resolve_debtap_url() {
  local json="$STATE_DIR/debtap-releases-$TIMESTAMP.json"

  if command -v gh >/dev/null 2>&1; then
    DEBTAP_TARBALL_URL="$(gh api repos/helixarch/debtap/releases/latest --jq .tarball_url)"
  else
    download_url_to_file "$json" "$DEBTAP_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      DEBTAP_TARBALL_URL="$(
        python3 - "$json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("tarball_url") or "")
PY
      )"
    fi
    rm -f "$json"
  fi

  case "$DEBTAP_TARBALL_URL" in
    https://api.github.com/repos/helixarch/debtap/tarball/*) ;;
    *)
      log "Could not resolve a debtap source tarball from GitHub releases"
      return 1
      ;;
  esac

  log "debtap tarball: $DEBTAP_TARBALL_URL"
  return 0
}

download_debtap_tarball() {
  download_url_to_file "$DEBTAP_TARBALL" "$DEBTAP_TARBALL_URL"
}

install_debtap_files() {
  local script=""

  rm -rf "$DEBTAP_EXTRACT"
  mkdir -p "$DEBTAP_EXTRACT"
  bsdtar -C "$DEBTAP_EXTRACT" -xf "$DEBTAP_TARBALL"
  script="$(find "$DEBTAP_EXTRACT" -type f -name debtap | head -1)"
  if [ -z "$script" ] || [ ! -s "$script" ]; then
    log "debtap tarball does not contain a debtap script"
    return 1
  fi
  if ! grep -q '^#!/usr/bin/bash' "$script"; then
    log "debtap script is missing the expected bash shebang"
    return 1
  fi

  sudo install -D -m 755 "$script" "$DEBTAP_BIN"
  rm -rf "$DEBTAP_EXTRACT" "$DEBTAP_TARBALL"
}

install_debtap() {
  local file_size=0

  install_package_group pacman "debtap runtime packages" DEBTAP_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve debtap tarball (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve debtap tarball"
    log "Skipping debtap install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract debtap tarball (missing required command: bsdtar)")
    record_status "FAIL" "extract debtap tarball"
    log "Skipping debtap install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_debtap_url; then
    FAILURES+=("resolve debtap GitHub tarball")
    record_status "FAIL" "resolve debtap GitHub tarball"
    return 0
  fi

  run_step "download debtap tarball" download_debtap_tarball

  if [ ! -e "$DEBTAP_TARBALL" ]; then
    return 0
  fi

  if [ ! -s "$DEBTAP_TARBALL" ]; then
    FAILURES+=("download debtap tarball (empty file)")
    record_status "FAIL" "download debtap tarball"
    log "Downloaded debtap file is empty: $DEBTAP_TARBALL"
    return 0
  fi

  file_size="$(stat -c%s "$DEBTAP_TARBALL")"
  if [ "$file_size" -lt 10000 ]; then
    FAILURES+=("download debtap tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download debtap tarball"
    log "Downloaded debtap file looks too small: $DEBTAP_TARBALL ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 2 "$DEBTAP_TARBALL")" != $'\x1f\x8b' ]; then
    FAILURES+=("download debtap tarball (not a gzip archive)")
    record_status "FAIL" "download debtap tarball"
    log "Downloaded debtap file is not a gzip archive: $DEBTAP_TARBALL"
    return 0
  fi

  log "Verified debtap tarball ($file_size bytes); installing to $DEBTAP_BIN"

  run_step "install debtap" install_debtap_files
}

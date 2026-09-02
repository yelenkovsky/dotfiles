register_package proton-drive 120 "Proton Drive CLI" install_proton_drive

PROTON_DRIVE_INDEX_URL="https://proton.me/download/drive/cli/index.html"
PROTON_DRIVE_PLATFORM="linux/x64"
PROTON_DRIVE_INDEX="$STATE_DIR/proton-drive-index-$TIMESTAMP.html"
PROTON_DRIVE_DOWNLOAD="$STATE_DIR/proton-drive-$TIMESTAMP"
PROTON_DRIVE_BIN="/usr/local/bin/proton-drive"

download_proton_drive_index() {
  download_url_to_file "$PROTON_DRIVE_INDEX" "$PROTON_DRIVE_INDEX_URL"
}

# The index lists linux/x64, linux/x64-baseline, and linux/x64-musl.
# Match the platform cell exactly so we take the glibc x86_64 build.
parse_proton_drive_linux_x64() {
  local parsed

  parsed="$(awk -v platform="$PROTON_DRIVE_PLATFORM" '
    BEGIN { RS = "<tr>" }
    index($0, "<td>" platform "</td>") {
      if (match($0, /href="[^"]+"/)) {
        url = substr($0, RSTART + 6, RLENGTH - 7)
      }
      if (match($0, /<code>[a-f0-9]+<\/code>/)) {
        hash = substr($0, RSTART + 6, RLENGTH - 13)
      }
      print url "\t" hash
      exit
    }
  ' "$PROTON_DRIVE_INDEX")"

  PROTON_DRIVE_URL="${parsed%%$'\t'*}"
  PROTON_DRIVE_SHA512="${parsed#*$'\t'}"

  if [ -z "$PROTON_DRIVE_URL" ] || [ -z "$PROTON_DRIVE_SHA512" ] || [ "$PROTON_DRIVE_URL" = "$PROTON_DRIVE_SHA512" ]; then
    return 1
  fi

  case "$PROTON_DRIVE_URL" in
    */linux-x64/proton-drive) ;;
    *)
      log "Parsed Proton Drive URL is not the linux-x64 binary: $PROTON_DRIVE_URL"
      return 1
      ;;
  esac

  log "Proton Drive CLI ($PROTON_DRIVE_PLATFORM): $PROTON_DRIVE_URL"
  return 0
}

download_proton_drive_binary() {
  download_url_to_file "$PROTON_DRIVE_DOWNLOAD" "$PROTON_DRIVE_URL"
}

install_proton_drive_files() {
  sudo install -D -m 755 "$PROTON_DRIVE_DOWNLOAD" "$PROTON_DRIVE_BIN"
  rm -f "$PROTON_DRIVE_DOWNLOAD" "$PROTON_DRIVE_INDEX"
}

install_proton_drive() {
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Proton Drive index (missing required command: curl or wget)")
    record_status "FAIL" "download Proton Drive index"
    log "Skipping Proton Drive install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Proton Drive CLI index" download_proton_drive_index

  if [ ! -s "$PROTON_DRIVE_INDEX" ]; then
    if [ "$DRY_RUN" = true ]; then
      return 0
    fi
    return 0
  fi

  if ! parse_proton_drive_linux_x64; then
    FAILURES+=("parse Proton Drive linux/x64 download from index")
    record_status "FAIL" "parse Proton Drive linux/x64 download from index"
    log "Could not find the $PROTON_DRIVE_PLATFORM row in $PROTON_DRIVE_INDEX_URL"
    return 0
  fi

  run_step "download Proton Drive CLI" download_proton_drive_binary

  if [ ! -e "$PROTON_DRIVE_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$PROTON_DRIVE_DOWNLOAD" ]; then
    FAILURES+=("download Proton Drive CLI (empty file)")
    record_status "FAIL" "download Proton Drive CLI"
    log "Downloaded Proton Drive file is empty: $PROTON_DRIVE_DOWNLOAD"
    return 0
  fi

  if [ "$(head -c 4 "$PROTON_DRIVE_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Proton Drive CLI (not an ELF binary)")
    record_status "FAIL" "download Proton Drive CLI"
    log "Downloaded Proton Drive file is not an ELF binary: $PROTON_DRIVE_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha512sum "$PROTON_DRIVE_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$PROTON_DRIVE_SHA512" ]; then
    FAILURES+=("verify Proton Drive CLI checksum")
    record_status "FAIL" "verify Proton Drive CLI checksum"
    log "Proton Drive SHA-512 mismatch (expected $PROTON_DRIVE_SHA512, got $actual_hash)"
    return 0
  fi

  chmod 700 "$PROTON_DRIVE_DOWNLOAD"
  log "Verified Proton Drive CLI SHA-512; installing to $PROTON_DRIVE_BIN"

  run_step "install Proton Drive CLI" install_proton_drive_files
}

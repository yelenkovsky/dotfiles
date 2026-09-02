register_package origin-cli 230 "Cursor Origin CLI" install_origin_cli

# Public Origin CLI: parse linux-x64 + SHA-256 from install.sh (do not pipe it
# to sh). Artifacts stay under the co/ CDN prefix; only the installer is origin/.
ORIGIN_CLI_INSTALL_SH_URL="https://downloads.cursor.com/origin/install.sh"
ORIGIN_CLI_INSTALL_SH="$STATE_DIR/origin-cli-install-$TIMESTAMP.sh"
ORIGIN_CLI_DOWNLOAD="$STATE_DIR/origin-cli-$TIMESTAMP.tar.gz"
ORIGIN_CLI_EXTRACT="$STATE_DIR/origin-cli-extract-$TIMESTAMP"
ORIGIN_CLI_BIN="/usr/local/bin/origin"
ORIGIN_CLI_URL=""
ORIGIN_CLI_SHA256=""

download_origin_cli_install_sh() {
  download_url_to_file "$ORIGIN_CLI_INSTALL_SH" "$ORIGIN_CLI_INSTALL_SH_URL"
}

# install.sh bakes stable and latest. Take the default stable linux-x64 glibc
# tarball (not musl, not arm64, not darwin).
parse_origin_cli_linux_x64() {
  local parsed

  parsed="$(awk '
    /^stable\)/ {
      in_stable = 1
      in_linux_x64 = 0
      next
    }
    in_stable && /^latest\)/ {
      in_stable = 0
      in_linux_x64 = 0
      next
    }
    in_stable && /linux-x64\)/ {
      in_linux_x64 = 1
      next
    }
    in_stable && in_linux_x64 && /darwin-|linux-arm64|^\*\)/ {
      in_linux_x64 = 0
      next
    }
    in_stable && in_linux_x64 && /url="/ {
      if (match($0, /https:[^"]+/)) {
        url = substr($0, RSTART, RLENGTH)
      }
      next
    }
    in_stable && in_linux_x64 && /sha="/ {
      if (match($0, /[a-f0-9]{64}/)) {
        print url "\t" substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$ORIGIN_CLI_INSTALL_SH")"

  ORIGIN_CLI_URL="${parsed%%$'\t'*}"
  ORIGIN_CLI_SHA256="${parsed#*$'\t'}"

  case "$ORIGIN_CLI_URL" in
    https://downloads.cursor.com/co/*/linux-x64/co.tar.gz) ;;
    *)
      log "Could not parse a Origin CLI linux-x64 tarball URL from $ORIGIN_CLI_INSTALL_SH_URL"
      return 1
      ;;
  esac

  if [ -z "$ORIGIN_CLI_SHA256" ] || [ "$ORIGIN_CLI_URL" = "$ORIGIN_CLI_SHA256" ]; then
    log "Could not parse the Origin CLI SHA-256 from $ORIGIN_CLI_INSTALL_SH_URL"
    return 1
  fi

  log "Origin CLI tarball: $ORIGIN_CLI_URL"
  return 0
}

download_origin_cli_tarball() {
  download_url_to_file "$ORIGIN_CLI_DOWNLOAD" "$ORIGIN_CLI_URL"
}

install_origin_cli_files() {
  rm -rf "$ORIGIN_CLI_EXTRACT"
  mkdir -p "$ORIGIN_CLI_EXTRACT"
  tar --no-same-owner -xzf "$ORIGIN_CLI_DOWNLOAD" -C "$ORIGIN_CLI_EXTRACT"

  if [ -L "$ORIGIN_CLI_EXTRACT/origin" ] || [ ! -f "$ORIGIN_CLI_EXTRACT/origin" ]; then
    log "Origin CLI tarball did not contain a regular origin binary"
    rm -rf "$ORIGIN_CLI_EXTRACT"
    return 1
  fi

  if [ "$(head -c 4 "$ORIGIN_CLI_EXTRACT/origin")" != $'\x7fELF' ]; then
    log "Origin CLI tarball origin member is not an ELF binary"
    rm -rf "$ORIGIN_CLI_EXTRACT"
    return 1
  fi

  sudo install -D -m 755 "$ORIGIN_CLI_EXTRACT/origin" "$ORIGIN_CLI_BIN"
  rm -rf "$ORIGIN_CLI_EXTRACT" "$ORIGIN_CLI_DOWNLOAD" "$ORIGIN_CLI_INSTALL_SH"
}

install_origin_cli() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Origin CLI installer (missing required command: curl or wget)")
    record_status "FAIL" "download Origin CLI installer"
    log "Skipping Origin CLI install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v tar >/dev/null 2>&1; then
    FAILURES+=("extract Origin CLI tarball (missing required command: tar)")
    record_status "FAIL" "extract Origin CLI tarball"
    log "Skipping Origin CLI install because tar is not installed"
    return 0
  fi

  if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    FAILURES+=("install Origin CLI (musl libc is not supported)")
    record_status "FAIL" "install Origin CLI"
    log "Skipping Origin CLI install because musl libc is not supported (glibc only)"
    return 0
  fi

  run_step "download Origin CLI installer metadata" download_origin_cli_install_sh

  if [ ! -s "$ORIGIN_CLI_INSTALL_SH" ]; then
    if [ "$DRY_RUN" = true ]; then
      return 0
    fi
    return 0
  fi

  if ! parse_origin_cli_linux_x64; then
    FAILURES+=("parse Origin CLI linux-x64 tarball from installer")
    record_status "FAIL" "parse Origin CLI linux-x64 tarball from installer"
    return 0
  fi

  run_step "download Origin CLI tarball" download_origin_cli_tarball

  if [ ! -e "$ORIGIN_CLI_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$ORIGIN_CLI_DOWNLOAD" ]; then
    FAILURES+=("download Origin CLI tarball (empty file)")
    record_status "FAIL" "download Origin CLI tarball"
    log "Downloaded Origin CLI file is empty: $ORIGIN_CLI_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$ORIGIN_CLI_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Origin CLI tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Origin CLI tarball"
    log "Downloaded Origin CLI file looks too small: $ORIGIN_CLI_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  actual_hash="$(sha256sum "$ORIGIN_CLI_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$ORIGIN_CLI_SHA256" ]; then
    FAILURES+=("verify Origin CLI checksum")
    record_status "FAIL" "verify Origin CLI checksum"
    log "Origin CLI SHA-256 mismatch (expected $ORIGIN_CLI_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Origin CLI SHA-256; installing to $ORIGIN_CLI_BIN"

  run_step "install Origin CLI" install_origin_cli_files
}

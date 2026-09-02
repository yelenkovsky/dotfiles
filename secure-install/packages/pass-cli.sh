register_package pass-cli 130 "Proton Pass CLI" install_pass_cli

PASS_CLI_DOWNLOAD_URL="https://github.com/protonpass/pass-cli/releases/latest/download/pass-cli-linux-x86_64"
PASS_CLI_SHA256_URL="https://github.com/protonpass/pass-cli/releases/latest/download/pass-cli-linux-x86_64.sha256"
PASS_CLI_DOWNLOAD="$STATE_DIR/pass-cli-$TIMESTAMP"
PASS_CLI_SHA256_FILE="$STATE_DIR/pass-cli-$TIMESTAMP.sha256"
PASS_CLI_BIN="/usr/local/bin/pass-cli"

download_pass_cli_files() {
  download_url_to_file "$PASS_CLI_SHA256_FILE" "$PASS_CLI_SHA256_URL"
  download_url_to_file "$PASS_CLI_DOWNLOAD" "$PASS_CLI_DOWNLOAD_URL"
}

install_pass_cli_files() {
  sudo install -D -m 755 "$PASS_CLI_DOWNLOAD" "$PASS_CLI_BIN"
  rm -f "$PASS_CLI_DOWNLOAD" "$PASS_CLI_SHA256_FILE"
}

install_pass_cli() {
  local expected_hash=""
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Proton Pass CLI (missing required command: curl or wget)")
    record_status "FAIL" "download Proton Pass CLI"
    log "Skipping Proton Pass CLI install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Proton Pass CLI" download_pass_cli_files

  if [ ! -e "$PASS_CLI_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$PASS_CLI_DOWNLOAD" ]; then
    FAILURES+=("download Proton Pass CLI (empty file)")
    record_status "FAIL" "download Proton Pass CLI"
    log "Downloaded Proton Pass CLI file is empty: $PASS_CLI_DOWNLOAD"
    return 0
  fi

  if [ "$(head -c 4 "$PASS_CLI_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Proton Pass CLI (not an ELF binary)")
    record_status "FAIL" "download Proton Pass CLI"
    log "Downloaded Proton Pass CLI file is not an ELF binary: $PASS_CLI_DOWNLOAD"
    return 0
  fi

  if [ ! -s "$PASS_CLI_SHA256_FILE" ]; then
    FAILURES+=("download Proton Pass CLI checksum (empty file)")
    record_status "FAIL" "download Proton Pass CLI checksum"
    log "Downloaded Proton Pass CLI checksum file is empty: $PASS_CLI_SHA256_FILE"
    return 0
  fi

  expected_hash="$(awk '{ print $1 }' "$PASS_CLI_SHA256_FILE")"
  actual_hash="$(sha256sum "$PASS_CLI_DOWNLOAD" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    FAILURES+=("verify Proton Pass CLI checksum")
    record_status "FAIL" "verify Proton Pass CLI checksum"
    log "Proton Pass CLI SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 0
  fi

  chmod 700 "$PASS_CLI_DOWNLOAD"
  log "Verified Proton Pass CLI SHA-256; installing to $PASS_CLI_BIN"

  run_step "install Proton Pass CLI" install_pass_cli_files
}

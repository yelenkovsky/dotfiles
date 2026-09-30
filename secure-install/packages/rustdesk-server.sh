register_package rustdesk-server 320 "RustDesk Server OSS" install_rustdesk_server

# Free OSS ID server (hbbs) and relay (hbbr) from GitHub releases/latest.
# linux-amd64 zip only: not arm64v8, armv7, i386, Windows, or the Pro build.
# SHA-256 is the asset digest. The zip is about 6 MB, under the desktop-app
# size floor, so the floor here is 1 MB.
RUSTDESK_SERVER_RELEASES_API="https://api.github.com/repos/rustdesk/rustdesk-server/releases/latest"
RUSTDESK_SERVER_DOWNLOAD="$STATE_DIR/rustdesk-server-$TIMESTAMP.zip"
RUSTDESK_SERVER_DATA_DIR="/var/lib/rustdesk-server"
RUSTDESK_SERVER_LOG_DIR="/var/log/rustdesk-server"
RUSTDESK_SERVER_DOWNLOAD_URL=""
RUSTDESK_SERVER_SHA256=""

resolve_rustdesk_server_url() {
  local json="$STATE_DIR/rustdesk-server-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/rustdesk/rustdesk-server/releases/latest \
        --jq '.assets[] | select(.name == "rustdesk-server-linux-amd64.zip") | "\(.browser_download_url)\t\(.digest)"' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$RUSTDESK_SERVER_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for asset in data.get("assets", []):
    if asset.get("name") == "rustdesk-server-linux-amd64.zip":
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            digest = digest[7:]
        print(asset["browser_download_url"] + "\t" + digest)
        break
PY
      )"
    fi
    rm -f "$json"
  fi

  RUSTDESK_SERVER_DOWNLOAD_URL="${parsed%%$'\t'*}"
  RUSTDESK_SERVER_SHA256="${parsed#*$'\t'}"
  RUSTDESK_SERVER_SHA256="${RUSTDESK_SERVER_SHA256#sha256:}"

  case "$RUSTDESK_SERVER_DOWNLOAD_URL" in
    https://github.com/rustdesk/rustdesk-server/releases/download/*/rustdesk-server-linux-amd64.zip) ;;
    *)
      log "Could not resolve a RustDesk Server linux-amd64 zip from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$RUSTDESK_SERVER_SHA256" ] || [ "$RUSTDESK_SERVER_DOWNLOAD_URL" = "$RUSTDESK_SERVER_SHA256" ]; then
    log "Could not parse the RustDesk Server SHA-256 from GitHub releases"
    return 1
  fi

  log "RustDesk Server OSS: $RUSTDESK_SERVER_DOWNLOAD_URL"
  return 0
}

download_rustdesk_server_zip() {
  download_url_to_file "$RUSTDESK_SERVER_DOWNLOAD" "$RUSTDESK_SERVER_DOWNLOAD_URL"
}

install_rustdesk_server_files() {
  local work="$STATE_DIR/rustdesk-server-extract-$TIMESTAMP"
  local binary=""
  local i=""

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$RUSTDESK_SERVER_DOWNLOAD"

  for binary in hbbs hbbr rustdesk-utils; do
    if [ ! -x "$work/amd64/$binary" ]; then
      log "RustDesk Server zip does not contain amd64/$binary"
      return 1
    fi
    if [ "$(head -c 4 "$work/amd64/$binary")" != $'\x7fELF' ]; then
      log "RustDesk Server $binary is not an ELF binary"
      return 1
    fi
  done

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl stop rustdesk-hbbs.service rustdesk-hbbr.service 2>/dev/null || true
  fi

  sudo install -D -m 755 "$work/amd64/hbbs" /usr/local/bin/hbbs
  sudo install -D -m 755 "$work/amd64/hbbr" /usr/local/bin/hbbr
  sudo install -D -m 755 "$work/amd64/rustdesk-utils" /usr/local/bin/rustdesk-utils

  # Keys are generated in the working directory on first start. Keep the
  # private key root-only. Do not replace an existing key on reinstall.
  sudo mkdir -p "$RUSTDESK_SERVER_DATA_DIR" "$RUSTDESK_SERVER_LOG_DIR"
  sudo chmod 700 "$RUSTDESK_SERVER_DATA_DIR"
  sudo chmod 755 "$RUSTDESK_SERVER_LOG_DIR"

  sudo tee /etc/systemd/system/rustdesk-hbbs.service >/dev/null <<EOF
[Unit]
Description=RustDesk Signal Server

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/local/bin/hbbs
WorkingDirectory=$RUSTDESK_SERVER_DATA_DIR
Restart=always
RestartSec=10
StandardOutput=append:$RUSTDESK_SERVER_LOG_DIR/hbbs.log
StandardError=append:$RUSTDESK_SERVER_LOG_DIR/hbbs.error

[Install]
WantedBy=multi-user.target
EOF
  sudo tee /etc/systemd/system/rustdesk-hbbr.service >/dev/null <<EOF
[Unit]
Description=RustDesk Relay Server

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=/usr/local/bin/hbbr
WorkingDirectory=$RUSTDESK_SERVER_DATA_DIR
Restart=always
RestartSec=10
StandardOutput=append:$RUSTDESK_SERVER_LOG_DIR/hbbr.log
StandardError=append:$RUSTDESK_SERVER_LOG_DIR/hbbr.error

[Install]
WantedBy=multi-user.target
EOF
  sudo chmod 644 /etc/systemd/system/rustdesk-hbbs.service /etc/systemd/system/rustdesk-hbbr.service

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl daemon-reload
    sudo systemctl enable --now rustdesk-hbbs.service rustdesk-hbbr.service
    for i in 1 2 3 4 5 6 7 8 9 10; do
      if sudo test -s "$RUSTDESK_SERVER_DATA_DIR/id_ed25519.pub"; then
        log "RustDesk server public key: $(sudo cat "$RUSTDESK_SERVER_DATA_DIR/id_ed25519.pub")"
        log "In the client, set ID server to this host and paste that key. Open TCP 21115-21117 and UDP 21116."
        break
      fi
      sleep 1
    done
    if ! sudo test -s "$RUSTDESK_SERVER_DATA_DIR/id_ed25519.pub"; then
      log "Public key will be written to $RUSTDESK_SERVER_DATA_DIR/id_ed25519.pub after hbbs starts"
    fi
  else
    log "systemd is not running; hbbs and hbbr are installed but not started"
  fi

  rm -rf "$work" "$RUSTDESK_SERVER_DOWNLOAD"
}

install_rustdesk_server() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve RustDesk Server (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve RustDesk Server"
    log "Skipping RustDesk Server install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract RustDesk Server zip (missing required command: bsdtar)")
    record_status "FAIL" "extract RustDesk Server zip"
    log "Skipping RustDesk Server install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_rustdesk_server_url; then
    FAILURES+=("resolve RustDesk Server linux-amd64 zip")
    record_status "FAIL" "resolve RustDesk Server linux-amd64 zip"
    return 0
  fi

  run_step "download RustDesk Server zip" download_rustdesk_server_zip

  if [ ! -e "$RUSTDESK_SERVER_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$RUSTDESK_SERVER_DOWNLOAD" ]; then
    FAILURES+=("download RustDesk Server zip (empty file)")
    record_status "FAIL" "download RustDesk Server zip"
    log "Downloaded RustDesk Server file is empty: $RUSTDESK_SERVER_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$RUSTDESK_SERVER_DOWNLOAD")"
  if [ "$file_size" -lt 1000000 ]; then
    FAILURES+=("download RustDesk Server zip (file too small: ${file_size} bytes)")
    record_status "FAIL" "download RustDesk Server zip"
    log "Downloaded RustDesk Server file looks too small: $RUSTDESK_SERVER_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 2 "$RUSTDESK_SERVER_DOWNLOAD")" != $'PK' ]; then
    FAILURES+=("download RustDesk Server zip (not a zip archive)")
    record_status "FAIL" "download RustDesk Server zip"
    log "Downloaded RustDesk Server file is not a zip archive: $RUSTDESK_SERVER_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha256sum "$RUSTDESK_SERVER_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$RUSTDESK_SERVER_SHA256" ]; then
    FAILURES+=("verify RustDesk Server checksum")
    record_status "FAIL" "verify RustDesk Server checksum"
    log "RustDesk Server SHA-256 mismatch (expected $RUSTDESK_SERVER_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified RustDesk Server zip SHA-256 ($file_size bytes); installing hbbs and hbbr"

  run_step "install RustDesk Server" install_rustdesk_server_files
}

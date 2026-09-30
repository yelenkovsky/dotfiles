register_package rustdesk 310 "RustDesk" install_rustdesk

# Official Arch x86_64 package from GitHub releases/latest (not the .deb, rpm,
# AppImage, sciter build, or aarch64 package). SHA-256 is the asset digest.
RUSTDESK_RELEASES_API="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"
RUSTDESK_INSTALL_DIR="/opt/rustdesk"
RUSTDESK_DOWNLOAD="$STATE_DIR/rustdesk-$TIMESTAMP.pkg.tar.zst"
RUSTDESK_DOWNLOAD_URL=""
RUSTDESK_SHA256=""
RUSTDESK_RUNTIME_PACKAGES=(
  alsa-lib
  gst-plugin-pipewire
  gst-plugins-base
  gtk3
  libappindicator-gtk3
  libva
  libxcb
  libxfixes
  pam
  xdotool
)

resolve_rustdesk_url() {
  local json="$STATE_DIR/rustdesk-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api repos/rustdesk/rustdesk/releases/latest \
        --jq '.assets[] | select(.name | test("^rustdesk-[0-9.]+-[0-9]+-x86_64\\.pkg\\.tar\\.zst$")) | "\(.browser_download_url)\t\(.digest)"' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$RUSTDESK_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for asset in data.get("assets", []):
    name = asset.get("name", "")
    if re.match(r"^rustdesk-[0-9.]+-[0-9]+-x86_64\.pkg\.tar\.zst$", name):
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

  RUSTDESK_DOWNLOAD_URL="${parsed%%$'\t'*}"
  RUSTDESK_SHA256="${parsed#*$'\t'}"
  RUSTDESK_SHA256="${RUSTDESK_SHA256#sha256:}"

  case "$RUSTDESK_DOWNLOAD_URL" in
    https://github.com/rustdesk/rustdesk/releases/download/*/rustdesk-*-x86_64.pkg.tar.zst) ;;
    *)
      log "Could not resolve a RustDesk x86_64 package from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$RUSTDESK_SHA256" ] || [ "$RUSTDESK_DOWNLOAD_URL" = "$RUSTDESK_SHA256" ]; then
    log "Could not parse the RustDesk SHA-256 from GitHub releases"
    return 1
  fi

  log "RustDesk: $RUSTDESK_DOWNLOAD_URL"
  return 0
}

download_rustdesk_package() {
  download_url_to_file "$RUSTDESK_DOWNLOAD" "$RUSTDESK_DOWNLOAD_URL"
}

install_rustdesk_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/rustdesk-extract-$TIMESTAMP"
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$RUSTDESK_DOWNLOAD"

  appdir="$work/usr/share/rustdesk"
  if [ ! -x "$appdir/rustdesk" ]; then
    log "RustDesk package does not contain usr/share/rustdesk/rustdesk"
    return 1
  fi

  if [ "$(head -c 4 "$appdir/rustdesk")" != $'\x7fELF' ]; then
    log "RustDesk launcher is not an ELF binary"
    return 1
  fi

  sudo mkdir -p "$RUSTDESK_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$RUSTDESK_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$RUSTDESK_INSTALL_DIR"
  sudo chmod u+rwX "$RUSTDESK_INSTALL_DIR"
  sudo chmod 755 "$RUSTDESK_INSTALL_DIR/rustdesk"
  sudo ln -sfn "$RUSTDESK_INSTALL_DIR/rustdesk" /usr/local/bin/rustdesk

  sudo tee /usr/share/applications/rustdesk.desktop >/dev/null <<EOF
[Desktop Entry]
Name=RustDesk
GenericName=Remote Desktop
Comment=Remote Desktop
Exec=/usr/local/bin/rustdesk %u
Icon=rustdesk
Terminal=false
Type=Application
StartupNotify=true
Categories=Network;RemoteAccess;GTK;
Keywords=remote-desktop;
StartupWMClass=rustdesk
EOF
  sudo chmod 644 /usr/share/applications/rustdesk.desktop

  sudo tee /usr/share/applications/rustdesk-link.desktop >/dev/null <<EOF
[Desktop Entry]
Name=RustDesk
NoDisplay=true
MimeType=x-scheme-handler/rustdesk;
TryExec=/usr/local/bin/rustdesk
Exec=/usr/local/bin/rustdesk %u
Icon=rustdesk
Terminal=false
Type=Application
StartupNotify=false
StartupWMClass=rustdesk
EOF
  sudo chmod 644 /usr/share/applications/rustdesk-link.desktop

  icon="$(find "$work/usr/share/icons" -type f -name 'rustdesk.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/icons/hicolor/256x256/apps/rustdesk.png
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/rustdesk.png
  fi
  if [ -f "$work/usr/share/icons/hicolor/scalable/apps/rustdesk.svg" ]; then
    sudo install -D -m 644 "$work/usr/share/icons/hicolor/scalable/apps/rustdesk.svg" /usr/share/icons/hicolor/scalable/apps/rustdesk.svg
  fi

  # Official package starts the incoming-connection service. This machine uses
  # systemd; point the unit at /opt instead of /usr/bin.
  sudo tee /etc/systemd/system/rustdesk.service >/dev/null <<EOF
[Unit]
Description=RustDesk
Requires=network.target
After=systemd-user-sessions.service

[Service]
Type=simple
ExecStart=$RUSTDESK_INSTALL_DIR/rustdesk --service
ExecStop=/usr/bin/pkill -f "rustdesk --"
PIDFile=/run/rustdesk.pid
KillMode=mixed
TimeoutStopSec=30
User=root
LimitNOFILE=100000
Environment="PULSE_LATENCY_MSEC=60" "PIPEWIRE_LATENCY=1024/48000"

[Install]
WantedBy=multi-user.target
EOF
  sudo chmod 644 /etc/systemd/system/rustdesk.service
  sudo systemctl daemon-reload
  sudo systemctl enable --now rustdesk.service

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  fi

  rm -rf "$work" "$RUSTDESK_DOWNLOAD"
}

install_rustdesk() {
  local file_size=0
  local actual_hash=""

  install_package_group pacman "RustDesk runtime packages" RUSTDESK_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve RustDesk package (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve RustDesk package"
    log "Skipping RustDesk install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract RustDesk package (missing required command: bsdtar)")
    record_status "FAIL" "extract RustDesk package"
    log "Skipping RustDesk install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_rustdesk_url; then
    FAILURES+=("resolve RustDesk x86_64 package")
    record_status "FAIL" "resolve RustDesk x86_64 package"
    return 0
  fi

  run_step "download RustDesk package" download_rustdesk_package

  if [ ! -e "$RUSTDESK_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$RUSTDESK_DOWNLOAD" ]; then
    FAILURES+=("download RustDesk package (empty file)")
    record_status "FAIL" "download RustDesk package"
    log "Downloaded RustDesk file is empty: $RUSTDESK_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$RUSTDESK_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download RustDesk package (file too small: ${file_size} bytes)")
    record_status "FAIL" "download RustDesk package"
    log "Downloaded RustDesk file looks too small: $RUSTDESK_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$RUSTDESK_DOWNLOAD")" != $'\x28\xb5\x2f\xfd' ]; then
    FAILURES+=("download RustDesk package (not a zstd archive)")
    record_status "FAIL" "download RustDesk package"
    log "Downloaded RustDesk file is not a zstd archive: $RUSTDESK_DOWNLOAD"
    return 0
  fi

  actual_hash="$(sha256sum "$RUSTDESK_DOWNLOAD" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$RUSTDESK_SHA256" ]; then
    FAILURES+=("verify RustDesk checksum")
    record_status "FAIL" "verify RustDesk checksum"
    log "RustDesk SHA-256 mismatch (expected $RUSTDESK_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified RustDesk package SHA-256 ($file_size bytes); extracting to $RUSTDESK_INSTALL_DIR"

  run_step "install RustDesk" install_rustdesk_files
}

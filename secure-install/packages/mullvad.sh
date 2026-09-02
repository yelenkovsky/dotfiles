register_package mullvad 200 "Mullvad VPN" install_mullvad

# Newest desktop linux amd64 .deb (stable or beta; not arm64, not rpm, not
# android). Website latest-beta returns HTML to non-wget clients.
MULLVAD_RELEASES_API="https://api.github.com/repos/mullvad/mullvadvpn-app/releases?per_page=30"
MULLVAD_GPG_KEY_URL="https://mullvad.net/media/mullvad-code-signing.asc"
# Mullvad (code signing) <admin@mullvad.net>
MULLVAD_GPG_FINGERPRINT="A1198702FC3E0A09A9AE5B75D5A1D4F266DE8DDF"
MULLVAD_INSTALL_DIR="/opt/Mullvad VPN"
MULLVAD_DEB="$STATE_DIR/mullvad-vpn-$TIMESTAMP.deb"
MULLVAD_SIG="$STATE_DIR/mullvad-vpn-$TIMESTAMP.deb.asc"
MULLVAD_GPG_KEY="$STATE_DIR/mullvad-signing-key-$TIMESTAMP.asc"
MULLVAD_GPG_HOME="$STATE_DIR/mullvad-gnupg-$TIMESTAMP"
MULLVAD_DOWNLOAD_URL=""
MULLVAD_SHA256=""
MULLVAD_RUNTIME_PACKAGES=(
  dbus
  iputils
  libayatana-appindicator
  libnotify
  libxss
  nss
)

resolve_mullvad_deb_url() {
  local json="$STATE_DIR/mullvad-releases-$TIMESTAMP.json"
  local parsed=""

  if command -v gh >/dev/null 2>&1; then
    parsed="$(
      gh api 'repos/mullvad/mullvadvpn-app/releases?per_page=30' \
        --jq '
          [.[] | select(.tag_name | test("^[0-9]"))]
          | .[0].assets[]
          | select(.name | test("^MullvadVPN-.*_amd64\\.deb$"))
          | "\(.browser_download_url)\t\(.digest)"
        ' \
        | head -1
    )"
  else
    download_url_to_file "$json" "$MULLVAD_RELEASES_API"
    if command -v python3 >/dev/null 2>&1; then
      parsed="$(
        python3 - "$json" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    releases = json.load(handle)

for release in releases:
    tag = release.get("tag_name") or ""
    if not re.match(r"^[0-9]", tag):
        continue
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if re.match(r"^MullvadVPN-.*_amd64\.deb$", name):
            digest = asset.get("digest") or ""
            if digest.startswith("sha256:"):
                digest = digest[7:]
            print(asset["browser_download_url"] + "\t" + digest)
            raise SystemExit
PY
      )"
    fi
    rm -f "$json"
  fi

  MULLVAD_DOWNLOAD_URL="${parsed%%$'\t'*}"
  MULLVAD_SHA256="${parsed#*$'\t'}"
  MULLVAD_SHA256="${MULLVAD_SHA256#sha256:}"

  case "$MULLVAD_DOWNLOAD_URL" in
    https://github.com/mullvad/mullvadvpn-app/releases/download/*/MullvadVPN-*_amd64.deb) ;;
    *)
      log "Could not resolve a Mullvad VPN amd64 .deb from GitHub releases"
      return 1
      ;;
  esac

  if [ -z "$MULLVAD_SHA256" ] || [ "$MULLVAD_DOWNLOAD_URL" = "$MULLVAD_SHA256" ]; then
    log "Could not parse the Mullvad VPN SHA-256 from GitHub releases"
    return 1
  fi

  log "Mullvad VPN .deb: $MULLVAD_DOWNLOAD_URL"
  return 0
}

download_mullvad_files() {
  download_url_to_file "$MULLVAD_DEB" "$MULLVAD_DOWNLOAD_URL"
  download_url_to_file "$MULLVAD_SIG" "${MULLVAD_DOWNLOAD_URL}.asc"
  download_url_to_file "$MULLVAD_GPG_KEY" "$MULLVAD_GPG_KEY_URL"
}

verify_mullvad_signature() {
  local imported_fingerprint=""
  local status=""

  rm -rf "$MULLVAD_GPG_HOME"
  mkdir -m 700 -p "$MULLVAD_GPG_HOME"

  status="$(
    export GNUPGHOME="$MULLVAD_GPG_HOME"
    gpg --batch --import "$MULLVAD_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$MULLVAD_GPG_FINGERPRINT" ]; then
    log "Mullvad VPN signing key fingerprint mismatch (expected $MULLVAD_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$MULLVAD_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$MULLVAD_SIG" "$MULLVAD_DEB" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | awk -v fpr="$MULLVAD_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Mullvad VPN .deb GPG verification failed"
    return 1
  fi

  log "Verified Mullvad VPN .deb GPG signature (VALIDSIG $MULLVAD_GPG_FINGERPRINT)"
  return 0
}

install_mullvad_files() {
  local work="$STATE_DIR/mullvad-extract-$TIMESTAMP"
  local data=""
  local appdir=""
  local unit=""
  local desktop=""
  local icon=""
  local bin=""

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$MULLVAD_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Mullvad VPN .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/opt/Mullvad VPN/mullvad-vpn" ]; then
    appdir="$work/opt/Mullvad VPN"
  else
    appdir="$(find "$work" -type d -name 'Mullvad VPN' | head -1)"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/mullvad-vpn" ]; then
    log "Mullvad VPN .deb does not contain /opt/Mullvad VPN/mullvad-vpn"
    return 1
  fi

  if [ ! -x "$work/usr/bin/mullvad-daemon" ]; then
    log "Mullvad VPN .deb does not contain usr/bin/mullvad-daemon"
    return 1
  fi

  sudo mkdir -p "$MULLVAD_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$MULLVAD_INSTALL_DIR"/
  sudo chmod 755 "$MULLVAD_INSTALL_DIR/mullvad-vpn"

  for bin in mullvad mullvad-daemon mullvad-exclude mullvad-problem-report; do
    if [ -f "$work/usr/bin/$bin" ]; then
      sudo install -D -m 755 "$work/usr/bin/$bin" "/usr/local/bin/$bin"
    fi
  done
  if [ -f /usr/local/bin/mullvad-exclude ]; then
    sudo chmod u+s /usr/local/bin/mullvad-exclude
  fi

  sudo tee /usr/local/bin/mullvad-vpn >/dev/null <<EOF
#!/bin/bash
exec "$MULLVAD_INSTALL_DIR/mullvad-vpn" --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/mullvad-vpn

  for unit in "$work"/usr/lib/systemd/system/mullvad-*.service; do
    [ -f "$unit" ] || continue
    sudo install -D -m 644 "$unit" "/usr/lib/systemd/system/$(basename "$unit")"
    sudo sed -i 's|/usr/bin/mullvad-daemon|/usr/local/bin/mullvad-daemon|g' \
      "/usr/lib/systemd/system/$(basename "$unit")"
  done

  if [ -d "$work/usr/share/dbus-1" ]; then
    sudo mkdir -p /usr/share/dbus-1
    sudo cp -a "$work/usr/share/dbus-1"/. /usr/share/dbus-1/
  fi
  if [ -d "$work/usr/share/polkit-1" ]; then
    sudo mkdir -p /usr/share/polkit-1
    sudo cp -a "$work/usr/share/polkit-1"/. /usr/share/polkit-1/
  fi

  desktop="$(find "$work" -type f -name 'mullvad-vpn.desktop' | head -1)"
  if [ -n "$desktop" ]; then
    sudo install -D -m 644 "$desktop" /usr/share/applications/mullvad-vpn.desktop
    sudo sed -i 's|^Exec=.*|Exec=/usr/local/bin/mullvad-vpn %U|' /usr/share/applications/mullvad-vpn.desktop
  else
    sudo tee /usr/share/applications/mullvad-vpn.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Mullvad VPN
Comment=Mullvad VPN client
Exec=/usr/local/bin/mullvad-vpn %U
Icon=mullvad-vpn
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
EOF
    sudo chmod 644 /usr/share/applications/mullvad-vpn.desktop
  fi

  icon="$(find "$work" -type f \( -name 'mullvad-vpn.png' -o -name 'mullvad.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/mullvad-vpn.png
  elif [ -d "$work/usr/share/icons" ]; then
    sudo cp -a "$work/usr/share/icons"/. /usr/share/icons/
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl daemon-reload
    sudo systemctl enable mullvad-daemon.service
    sudo systemctl enable mullvad-early-boot-blocking.service
    sudo systemctl restart mullvad-daemon.service || log "Failed to restart mullvad-daemon.service"
  fi

  rm -rf "$work" "$MULLVAD_DEB" "$MULLVAD_SIG" "$MULLVAD_GPG_KEY" "$MULLVAD_GPG_HOME"
}

install_mullvad() {
  local file_size=0
  local actual_hash=""

  install_package_group pacman "Mullvad VPN runtime packages" MULLVAD_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Mullvad VPN .deb (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Mullvad VPN .deb"
    log "Skipping Mullvad VPN install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Mullvad VPN signature (missing required command: gpg)")
    record_status "FAIL" "verify Mullvad VPN signature"
    log "Skipping Mullvad VPN install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Mullvad VPN .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Mullvad VPN .deb"
    log "Skipping Mullvad VPN install because bsdtar is not installed"
    return 0
  fi

  if ! resolve_mullvad_deb_url; then
    FAILURES+=("resolve Mullvad VPN amd64 .deb URL")
    record_status "FAIL" "resolve Mullvad VPN amd64 .deb URL"
    return 0
  fi

  run_step "download Mullvad VPN .deb" download_mullvad_files

  if [ ! -e "$MULLVAD_DEB" ]; then
    return 0
  fi

  if [ ! -s "$MULLVAD_DEB" ]; then
    FAILURES+=("download Mullvad VPN .deb (empty file)")
    record_status "FAIL" "download Mullvad VPN .deb"
    log "Downloaded Mullvad VPN file is empty: $MULLVAD_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$MULLVAD_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Mullvad VPN .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Mullvad VPN .deb"
    log "Downloaded Mullvad VPN file looks too small to be a .deb: $MULLVAD_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$MULLVAD_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Mullvad VPN .deb (not an ar archive)")
    record_status "FAIL" "download Mullvad VPN .deb"
    log "Downloaded Mullvad VPN file is not a .deb ar archive: $MULLVAD_DEB"
    return 0
  fi

  if [ ! -s "$MULLVAD_SIG" ]; then
    FAILURES+=("download Mullvad VPN signature (empty file)")
    record_status "FAIL" "download Mullvad VPN signature"
    log "Downloaded Mullvad VPN signature is empty: $MULLVAD_SIG"
    return 0
  fi

  actual_hash="$(sha256sum "$MULLVAD_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$MULLVAD_SHA256" ]; then
    FAILURES+=("verify Mullvad VPN checksum")
    record_status "FAIL" "verify Mullvad VPN checksum"
    log "Mullvad VPN SHA-256 mismatch (expected $MULLVAD_SHA256, got $actual_hash)"
    return 0
  fi

  if ! verify_mullvad_signature; then
    FAILURES+=("verify Mullvad VPN GPG signature")
    record_status "FAIL" "verify Mullvad VPN GPG signature"
    return 0
  fi

  log "Verified Mullvad VPN .deb ($file_size bytes); extracting to $MULLVAD_INSTALL_DIR"

  run_step "install Mullvad VPN" install_mullvad_files
}

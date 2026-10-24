# shellcheck shell=bash
register_package ivpn 202 "IVPN (daemon, CLI, GUI)" install_ivpn

# Official amd64 ivpn (daemon + CLI) and ivpn-ui (Electron GUI) from IVPN's
# "generic" Ubuntu repo, the same one apt would use. GitHub releases carry no
# Linux assets, and some tags (3.16.x) are macOS-only, so the repo index is
# the source of truth for the newest Linux build.
IVPN_REPO_URL="https://repo.ivpn.net/stable/ubuntu"
IVPN_INRELEASE_URL="$IVPN_REPO_URL/dists/generic/InRelease"
IVPN_PACKAGES_URL="$IVPN_REPO_URL/dists/generic/main/binary-amd64/Packages"
IVPN_GPG_KEY_URL="$IVPN_REPO_URL/generic.gpg"
# IVPN Signing Key <admin@ivpn.net>, as published on ivpn.net/apps-linux.
IVPN_GPG_FINGERPRINT="F52691AB05F2FCDF67CD6516D437F3E150DB096C"
IVPN_INRELEASE="$STATE_DIR/ivpn-$TIMESTAMP.InRelease"
IVPN_RELEASE="$STATE_DIR/ivpn-$TIMESTAMP.Release"
IVPN_PACKAGES="$STATE_DIR/ivpn-$TIMESTAMP.Packages"
IVPN_GPG_KEY="$STATE_DIR/ivpn-signing-key-$TIMESTAMP.asc"
IVPN_GPG_HOME="$STATE_DIR/ivpn-gnupg-$TIMESTAMP"
IVPN_DEB="$STATE_DIR/ivpn-$TIMESTAMP.deb"
IVPN_UI_DEB="$STATE_DIR/ivpn-ui-$TIMESTAMP.deb"
IVPN_INSTALL_DIR="/opt/ivpn"
IVPN_VERSION=""
IVPN_DEB_URL=""
IVPN_SHA256=""
IVPN_UI_DEB_URL=""
IVPN_UI_SHA256=""
# shellcheck disable=SC2034  # passed by name to install_package_group (local -n)
IVPN_RUNTIME_PACKAGES=(
  alsa-lib
  gtk3
  iptables
  libnotify
  libxss
  nss
  openvpn
)
register_update_check ivpn "$IVPN_DEB"
register_changelog ivpn 'https://github.com/ivpn/desktop-app/releases/tag/v{version}' '/pool/ivpn_([0-9.]+)_amd64\.deb' 'https://github.com/ivpn/desktop-app/releases'

download_ivpn_metadata() {
  download_url_to_file "$IVPN_GPG_KEY" "$IVPN_GPG_KEY_URL" || return 1
  download_url_to_file "$IVPN_INRELEASE" "$IVPN_INRELEASE_URL" || return 1
  download_url_to_file "$IVPN_PACKAGES" "$IVPN_PACKAGES_URL"
}

# Verify InRelease and keep only its signed text: gpg --verify still passes
# when unsigned lines are added around the signed block, so hashes are read
# from what gpg --decrypt writes out, never from the downloaded file.
verify_ivpn_packages_signature() {
  local imported_fingerprint=""
  local status=""
  local expected_hash=""
  local actual_hash=""

  rm -rf "$IVPN_GPG_HOME" "$IVPN_RELEASE"
  # shellcheck disable=SC2174  # only the GPG home itself needs 0700
  mkdir -m 700 -p "$IVPN_GPG_HOME"

  status="$(
    export GNUPGHOME="$IVPN_GPG_HOME"
    gpg --batch --import "$IVPN_GPG_KEY" >/dev/null 2>&1
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$IVPN_GPG_FINGERPRINT" ]; then
    log "IVPN signing key fingerprint mismatch (expected $IVPN_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$IVPN_GPG_HOME"
    gpg --batch --status-fd 1 --output "$IVPN_RELEASE" --decrypt "$IVPN_INRELEASE" 2>/dev/null
  )" || true

  if [ ! -s "$IVPN_RELEASE" ] || ! printf '%s\n' "$status" | awk -v fpr="$IVPN_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "IVPN InRelease GPG verification failed"
    return 1
  fi

  expected_hash="$(
    awk '
      $0 == "SHA256:" { in_sha = 1; next }
      in_sha && /^[A-Za-z]/ { in_sha = 0 }
      in_sha && $3 == "main/binary-amd64/Packages" { print $1; exit }
    ' "$IVPN_RELEASE"
  )"
  actual_hash="$(sha256sum "$IVPN_PACKAGES" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    log "IVPN Packages SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 1
  fi

  log "Verified IVPN Packages GPG signature and SHA-256"
  return 0
}

# The index keeps every past release plus pool/*_LATEST_amd64.deb aliases that
# can lag behind. Take the highest ivpn version stored under its own versioned
# filename, and the ivpn-ui build of that same version.
parse_ivpn_debs() {
  local entries=""
  local parsed=""
  local ui_parsed=""

  entries="$(
    awk '
      /^Package:/ { pkg = $2; ver = ""; file = ""; hash = "" }
      /^Version:/ { ver = $2 }
      /^Filename:/ { file = $2 }
      /^SHA256:/ { hash = $2 }
      /^$/ { if (pkg != "") print pkg "\t" ver "\t" file "\t" hash; pkg = "" }
      END { if (pkg != "") print pkg "\t" ver "\t" file "\t" hash }
    ' "$IVPN_PACKAGES"
  )"

  IVPN_VERSION="$(
    printf '%s\n' "$entries" \
      | awk -F '\t' '$1 == "ivpn" && $3 == "pool/ivpn_" $2 "_amd64.deb" { print $2 }' \
      | sort -V | tail -1
  )"
  if ! [[ "$IVPN_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    log "Could not find an IVPN amd64 release in $IVPN_PACKAGES_URL"
    return 1
  fi

  parsed="$(printf '%s\n' "$entries" | awk -F '\t' -v v="$IVPN_VERSION" \
    '$1 == "ivpn" && $3 == "pool/ivpn_" v "_amd64.deb" { print $3 "\t" $4; exit }')"
  ui_parsed="$(printf '%s\n' "$entries" | awk -F '\t' -v v="$IVPN_VERSION" \
    '$1 == "ivpn-ui" && $3 == "pool/ivpn-ui_" v "_amd64.deb" { print $3 "\t" $4; exit }')"

  IVPN_DEB_URL="$IVPN_REPO_URL/${parsed%%$'\t'*}"
  IVPN_SHA256="${parsed#*$'\t'}"
  IVPN_UI_DEB_URL="$IVPN_REPO_URL/${ui_parsed%%$'\t'*}"
  IVPN_UI_SHA256="${ui_parsed#*$'\t'}"

  if [ -z "$ui_parsed" ]; then
    log "IVPN $IVPN_VERSION has no matching ivpn-ui amd64 .deb in $IVPN_PACKAGES_URL"
    return 1
  fi

  if ! [[ "$IVPN_SHA256" =~ ^[0-9a-f]{64}$ ]] || ! [[ "$IVPN_UI_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    log "Could not parse the IVPN SHA-256 values from $IVPN_PACKAGES_URL"
    return 1
  fi

  log "IVPN $IVPN_VERSION: $IVPN_DEB_URL"
  log "IVPN UI $IVPN_VERSION: $IVPN_UI_DEB_URL"
  return 0
}

download_ivpn_debs() {
  download_url_to_file "$IVPN_DEB" "$IVPN_DEB_URL" || return 1
  download_url_to_file "$IVPN_UI_DEB" "$IVPN_UI_DEB_URL"
}

# Size floor, ar magic and the SHA-256 from the signed index. Prints nothing;
# logs and returns 1 on the first problem.
check_ivpn_deb() {
  local label="$1"
  local file="$2"
  local expected="$3"
  local file_size=0
  local actual_hash=""

  if [ ! -s "$file" ]; then
    log "Downloaded $label is empty or missing: $file"
    return 1
  fi

  file_size="$(stat -c%s "$file")"
  if [ "$file_size" -lt 10000000 ]; then
    log "Downloaded $label looks too small to be a .deb: $file ($file_size bytes)"
    return 1
  fi

  if [ "$(head -c 7 "$file")" != '!<arch>' ]; then
    log "Downloaded $label is not a .deb ar archive: $file"
    return 1
  fi

  actual_hash="$(sha256sum "$file" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$expected" ]; then
    log "$label SHA-256 mismatch (expected $expected, got $actual_hash)"
    return 1
  fi

  log "Verified $label ($file_size bytes, SHA-256 $actual_hash)"
}

extract_ivpn_deb_payload() {
  local deb="$1"
  local dest="$2"
  local unpack="$3"
  local data=""

  rm -rf "$unpack"
  mkdir -p "$unpack" "$dest"
  bsdtar -C "$unpack" -xf "$deb" || return 1
  data="$(find "$unpack" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "$(basename "$deb") has no data.tar payload"
    return 1
  fi
  bsdtar -C "$dest" -xf "$data"
}

# What the vendor's preinst does before an upgrade: drop the tunnel and the
# split-tunnel rules while the old daemon and its scripts are still in place.
release_ivpn_connection() {
  if [ -x /usr/local/bin/ivpn ]; then
    timeout 30 /usr/local/bin/ivpn disconnect >/dev/null 2>&1 \
      || log "Could not disconnect IVPN before the upgrade (daemon not running?)"
  fi
  if [ -f "$IVPN_INSTALL_DIR/etc/firewall.sh" ]; then
    sudo "$IVPN_INSTALL_DIR/etc/firewall.sh" -only_dns_off >/dev/null 2>&1 || true
  fi
  if [ -f "$IVPN_INSTALL_DIR/etc/splittun.sh" ]; then
    sudo "$IVPN_INSTALL_DIR/etc/splittun.sh" reset >/dev/null 2>&1 || true
    sudo "$IVPN_INSTALL_DIR/etc/splittun.sh" stop >/dev/null 2>&1 || true
  fi
}

install_ivpn_files() {
  local work="$STATE_DIR/ivpn-extract-$TIMESTAMP"
  local root="$work/root"
  local unit_src="$root/usr/share/pleaserun/ivpn-service/systemd/default/files/etc/systemd/system/ivpn-service.service"
  local bin=""

  rm -rf "$work"
  extract_ivpn_deb_payload "$IVPN_DEB" "$root" "$work/ivpn" || return 1
  extract_ivpn_deb_payload "$IVPN_UI_DEB" "$root" "$work/ivpn-ui" || return 1

  for bin in "$root/usr/bin/ivpn" "$root/usr/bin/ivpn-service" "$root$IVPN_INSTALL_DIR/ui/bin/ivpn-ui"; do
    if [ ! -x "$bin" ]; then
      log "IVPN .debs do not contain ${bin#"$root"}"
      return 1
    fi
  done
  if [ ! -f "$unit_src" ]; then
    log "IVPN .deb does not contain the ivpn-service systemd unit"
    return 1
  fi

  release_ivpn_connection

  # Root-owned, unlike the user-owned Electron trees: the root daemon runs
  # etc/firewall.sh and reads etc/ca.crt and ta.key from this tree.
  replace_install_tree "$root$IVPN_INSTALL_DIR" "$IVPN_INSTALL_DIR" "root:root" || return 1

  # File modes from the vendor's postinst. chrome-sandbox is left non-setuid:
  # unprivileged user namespaces give Chromium its sandbox here.
  sudo find "$IVPN_INSTALL_DIR" -type d -exec chmod 755 {} + || return 1
  sudo find "$IVPN_INSTALL_DIR/etc" -maxdepth 1 -type f -exec chmod 400 {} + || return 1
  sudo chmod 600 "$IVPN_INSTALL_DIR/etc/servers.json" || return 1
  sudo find "$IVPN_INSTALL_DIR/etc" -maxdepth 1 -type f \
    \( -name '*.sh' -o -name '*.up' -o -name '*.down' \) -exec chmod 700 {} + || return 1

  for bin in ivpn ivpn-service; do
    sudo install -D -m 755 "$root/usr/bin/$bin" "/usr/local/bin/$bin" || return 1
  done
  sudo ln -sfn "$IVPN_INSTALL_DIR/ui/bin/ivpn-ui" /usr/local/bin/ivpn-ui || return 1

  sudo install -D -m 644 "$root$IVPN_INSTALL_DIR/etc/ivpn.bash-completion" \
    /usr/share/bash-completion/completions/ivpn || return 1

  sudo mkdir -p /var/log/ivpn /etc/opt/ivpn/mutable || return 1
  # A new daemon may read a new servers.json format; the vendor overwrites the
  # cached copy with the bundled one on every upgrade.
  if sudo test -f /etc/opt/ivpn/mutable/servers.json; then
    sudo cp "$IVPN_INSTALL_DIR/etc/servers.json" /etc/opt/ivpn/mutable/servers.json || return 1
  fi

  sudo install -D -m 644 "$unit_src" /usr/lib/systemd/system/ivpn-service.service || return 1
  sudo sed -i 's|/usr/bin/ivpn-service|/usr/local/bin/ivpn-service|g' \
    /usr/lib/systemd/system/ivpn-service.service || return 1

  sudo tee /usr/share/applications/ivpn.desktop >/dev/null <<EOF || return 1
[Desktop Entry]
Name=IVPN
GenericName=VPN client
Comment=IVPN client
Exec=/usr/local/bin/ivpn-ui
Icon=$IVPN_INSTALL_DIR/ui/ivpnicon.svg
StartupWMClass=IVPN
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/ivpn.desktop || return 1

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl daemon-reload
    sudo systemctl enable ivpn-service.service
    sudo systemctl restart ivpn-service.service || log "Failed to restart ivpn-service.service"
  fi

  rm -rf "$work" "$IVPN_DEB" "$IVPN_UI_DEB" "$IVPN_PACKAGES" "$IVPN_INRELEASE" "$IVPN_RELEASE" "$IVPN_GPG_KEY" "$IVPN_GPG_HOME"
}

install_ivpn() {
  install_package_group pacman "IVPN runtime packages" IVPN_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download IVPN metadata (missing required command: curl or wget)")
    record_status "FAIL" "download IVPN metadata"
    log "Skipping IVPN install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify IVPN Packages signature (missing required command: gpg)")
    record_status "FAIL" "verify IVPN Packages signature"
    log "Skipping IVPN install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract IVPN .debs (missing required command: bsdtar)")
    record_status "FAIL" "extract IVPN .debs"
    log "Skipping IVPN install because bsdtar is not installed"
    return 0
  fi

  run_step "download IVPN metadata" download_ivpn_metadata

  if [ ! -s "$IVPN_PACKAGES" ] || [ ! -s "$IVPN_INRELEASE" ] || [ ! -s "$IVPN_GPG_KEY" ]; then
    return 0
  fi

  if ! verify_ivpn_packages_signature; then
    FAILURES+=("verify IVPN Packages GPG signature")
    record_status "FAIL" "verify IVPN Packages GPG signature"
    return 0
  fi

  if ! parse_ivpn_debs; then
    FAILURES+=("parse IVPN amd64 .deb URLs")
    record_status "FAIL" "parse IVPN amd64 .deb URLs"
    return 0
  fi

  run_step "download IVPN .debs" download_ivpn_debs

  if [ ! -e "$IVPN_DEB" ]; then
    return 0
  fi

  if ! check_ivpn_deb "IVPN .deb" "$IVPN_DEB" "$IVPN_SHA256"; then
    FAILURES+=("verify IVPN .deb")
    record_status "FAIL" "verify IVPN .deb"
    return 0
  fi

  if ! check_ivpn_deb "IVPN UI .deb" "$IVPN_UI_DEB" "$IVPN_UI_SHA256"; then
    FAILURES+=("verify IVPN UI .deb")
    record_status "FAIL" "verify IVPN UI .deb"
    return 0
  fi

  log "Verified IVPN $IVPN_VERSION; extracting to $IVPN_INSTALL_DIR"

  close_running_app "IVPN app" "$IVPN_INSTALL_DIR/ui" || return 0

  run_step "install IVPN" install_ivpn_files
}

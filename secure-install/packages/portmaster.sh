register_package portmaster 205 "Portmaster (daemon and UI)" install_portmaster

# Desktop v2 linux amd64 .deb from the download page (not the v1
# portmaster-installer.deb, not rpm, not Windows). Checksums are the installer
# list linked from that page.
PORTMASTER_DOWNLOAD_PAGE="https://safing.io/download/"
PORTMASTER_CHECKSUMS_URL="https://raw.githubusercontent.com/safing/checksums/master/sha256_installers.txt"
PORTMASTER_PAGE="$STATE_DIR/portmaster-download-$TIMESTAMP.html"
PORTMASTER_CHECKSUMS="$STATE_DIR/portmaster-sha256-$TIMESTAMP.txt"
PORTMASTER_DEB="$STATE_DIR/portmaster-$TIMESTAMP.deb"
PORTMASTER_LIB_DIR="/usr/lib/portmaster"
PORTMASTER_DEB_URL=""
PORTMASTER_SHA256=""
PORTMASTER_RUNTIME_PACKAGES=(
  gtk3
  libayatana-appindicator
  webkit2gtk-4.1
)

download_portmaster_metadata() {
  download_url_to_file "$PORTMASTER_PAGE" "$PORTMASTER_DOWNLOAD_PAGE"
  download_url_to_file "$PORTMASTER_CHECKSUMS" "$PORTMASTER_CHECKSUMS_URL"
}

# First linux_amd64 Portmaster_<version>_amd64.deb on the download page, then
# its SHA-256 from sha256_installers.txt. The v1 installer name does not match.
parse_portmaster_deb() {
  local name=""

  PORTMASTER_DEB_URL="$(
    awk '
      match($0, /https:\/\/updates\.safing\.io\/latest\/linux_amd64\/packages\/Portmaster_[0-9.]+_amd64\.deb/) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    ' "$PORTMASTER_PAGE"
  )"

  case "$PORTMASTER_DEB_URL" in
    https://updates.safing.io/latest/linux_amd64/packages/Portmaster_*_amd64.deb) ;;
    *)
      log "Could not parse a Portmaster amd64 .deb URL from $PORTMASTER_DOWNLOAD_PAGE"
      return 1
      ;;
  esac

  name="${PORTMASTER_DEB_URL##*/}"
  PORTMASTER_SHA256="$(
    awk -v name="$name" '
      {
        file = $2
        sub(/\r$/, "", file)
        if (file == name || file == "./" name) {
          print $1
          exit
        }
      }
    ' "$PORTMASTER_CHECKSUMS"
  )"

  if [ -z "$PORTMASTER_SHA256" ]; then
    log "No SHA-256 for $name in $PORTMASTER_CHECKSUMS_URL"
    return 1
  fi

  if ! printf '%s\n' "$PORTMASTER_SHA256" | grep -Eq '^[0-9a-f]{64}$'; then
    log "Portmaster checksum for $name is not a SHA-256: $PORTMASTER_SHA256"
    return 1
  fi

  log "Portmaster: $PORTMASTER_DEB_URL"
  return 0
}

download_portmaster_deb() {
  download_url_to_file "$PORTMASTER_DEB" "$PORTMASTER_DEB_URL"
}

# Vendor postinst copies v1 config into /var/lib/portmaster and retires the v1 unit.
migrate_portmaster_v1() {
  local old="/opt/safing/portmaster"

  if [ ! -d "$old" ] || [ -e "$old/migrated.txt" ]; then
    return 0
  fi

  log "Migrating Portmaster v1 data from $old"
  sudo rm -f /etc/systemd/system/portmaster.service
  sudo mkdir -p /var/lib/portmaster
  if [ -d "$old/databases" ]; then
    sudo cp -a "$old/databases" /var/lib/portmaster/
  fi
  if [ -f "$old/config.json" ]; then
    sudo cp -a "$old/config.json" /var/lib/portmaster/config.json
  fi
  sudo rm -f /etc/xdg/autostart/portmaster_notifier.desktop \
    /usr/share/applications/portmaster_notifier.desktop \
    /usr/share/applications/portmaster.desktop
  sudo rm -rf "$old/exec" "$old/logs" "$old/updates" \
    "$old/databases/cache" "$old/databases/icons" "$old/databases/history.db"
  sudo touch "$old/migrated.txt"
}

install_portmaster_files() {
  local work="$STATE_DIR/portmaster-extract-$TIMESTAMP"
  local data=""
  local unit=""
  local desktop=""
  local autostart=""
  local icon=""
  local intel=""
  local was_active=0

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$PORTMASTER_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Portmaster .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ "$(head -c 4 "$work/usr/bin/portmaster")" != $'\x7fELF' ]; then
    log "Portmaster .deb does not contain an ELF usr/bin/portmaster"
    return 1
  fi
  if [ "$(head -c 4 "$work/usr/lib/portmaster/portmaster-core")" != $'\x7fELF' ]; then
    log "Portmaster .deb does not contain an ELF portmaster-core"
    return 1
  fi
  for intel in portmaster.zip assets.zip; do
    if [ ! -s "$work/usr/lib/portmaster/$intel" ]; then
      log "Portmaster .deb is missing usr/lib/portmaster/$intel"
      return 1
    fi
  done

  unit="$work/usr/lib/systemd/system/portmaster.service"
  desktop="$work/usr/share/applications/Portmaster.desktop"
  autostart="$work/etc/xdg/autostart/portmaster.desktop"
  icon="$work/usr/share/icons/hicolor/512x512/apps/portmaster.png"
  if [ ! -f "$unit" ] || [ ! -f "$desktop" ] || [ ! -f "$autostart" ] || [ ! -f "$icon" ]; then
    log "Portmaster .deb is missing the service, desktop entry, or icon"
    return 1
  fi
  if ! grep -q '^ExecStart=/usr/lib/portmaster/portmaster-core ' "$unit"; then
    log "Portmaster service ExecStart is not the expected vendor path"
    return 1
  fi
  if ! grep -q '^Exec=portmaster ' "$desktop"; then
    log "Portmaster desktop Exec line was not the expected vendor form"
    return 1
  fi
  if ! grep -q '^Exec=/usr/bin/portmaster ' "$autostart"; then
    log "Portmaster autostart Exec line was not the expected vendor form"
    return 1
  fi

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet portmaster.service; then
    was_active=1
    sudo systemctl stop portmaster.service
  fi
  pkill -x portmaster >/dev/null 2>&1 || true

  # The unit and in-place updater write /usr/lib/portmaster. The UI binary
  # ships at usr/bin/portmaster; the vendor postinst moves it beside the core.
  sudo install -D -m 755 "$work/usr/lib/portmaster/portmaster-core" "$PORTMASTER_LIB_DIR/portmaster-core"
  sudo install -D -m 755 "$work/usr/bin/portmaster" "$PORTMASTER_LIB_DIR/portmaster"
  sudo install -D -m 644 "$work/usr/lib/portmaster/portmaster.zip" "$PORTMASTER_LIB_DIR/portmaster.zip"
  sudo install -D -m 644 "$work/usr/lib/portmaster/assets.zip" "$PORTMASTER_LIB_DIR/assets.zip"
  sudo ln -sfn "$PORTMASTER_LIB_DIR/portmaster" /usr/local/bin/portmaster

  sudo mkdir -p /var/lib/portmaster/intel
  for intel in "$work"/var/lib/portmaster/intel/*; do
    [ -f "$intel" ] || continue
    sudo install -D -m 644 "$intel" "/var/lib/portmaster/intel/$(basename "$intel")"
  done

  migrate_portmaster_v1

  if command -v semanage >/dev/null 2>&1; then
    sudo semanage fcontext -a -t bin_t -s system_u "$(realpath /usr/lib)/portmaster/portmaster-core" || true
    sudo restorecon -R "$PORTMASTER_LIB_DIR/portmaster-core" >/dev/null 2>&1 || true
  fi

  sudo install -D -m 644 "$unit" /usr/lib/systemd/system/portmaster.service
  sudo install -D -m 644 "$desktop" /usr/share/applications/Portmaster.desktop
  sudo sed -i 's|^Exec=portmaster |Exec=/usr/local/bin/portmaster |' /usr/share/applications/Portmaster.desktop
  sudo install -D -m 644 "$autostart" /etc/xdg/autostart/portmaster.desktop
  sudo sed -i 's|^Exec=/usr/bin/portmaster |Exec=/usr/local/bin/portmaster |' /etc/xdg/autostart/portmaster.desktop
  sudo install -D -m 644 "$icon" /usr/share/icons/hicolor/512x512/apps/portmaster.png
  sudo install -D -m 644 "$icon" /usr/share/pixmaps/portmaster.png

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl daemon-reload
    sudo systemctl enable portmaster.service
    if [ "$was_active" -eq 1 ]; then
      sudo systemctl restart portmaster.service || log "Failed to restart portmaster.service"
    else
      log "Portmaster service is enabled. It starts on the next boot."
    fi
  fi

  rm -rf "$work" "$PORTMASTER_DEB" "$PORTMASTER_PAGE" "$PORTMASTER_CHECKSUMS"
}

install_portmaster() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Portmaster metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Portmaster metadata"
    log "Skipping Portmaster install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Portmaster .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Portmaster .deb"
    log "Skipping Portmaster install because bsdtar is not installed"
    return 0
  fi

  run_step "download Portmaster metadata" download_portmaster_metadata

  if [ ! -s "$PORTMASTER_PAGE" ] || [ ! -s "$PORTMASTER_CHECKSUMS" ]; then
    return 0
  fi

  if ! parse_portmaster_deb; then
    FAILURES+=("resolve Portmaster amd64 .deb")
    record_status "FAIL" "resolve Portmaster amd64 .deb"
    return 0
  fi

  run_step "download Portmaster .deb" download_portmaster_deb

  if [ ! -e "$PORTMASTER_DEB" ]; then
    return 0
  fi

  if [ ! -s "$PORTMASTER_DEB" ]; then
    FAILURES+=("download Portmaster .deb (empty file)")
    record_status "FAIL" "download Portmaster .deb"
    log "Downloaded Portmaster file is empty: $PORTMASTER_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$PORTMASTER_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Portmaster .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Portmaster .deb"
    log "Downloaded Portmaster file looks too small to be a .deb: $PORTMASTER_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$PORTMASTER_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Portmaster .deb (not an ar archive)")
    record_status "FAIL" "download Portmaster .deb"
    log "Downloaded Portmaster file is not a .deb ar archive: $PORTMASTER_DEB"
    return 0
  fi

  actual_hash="$(sha256sum "$PORTMASTER_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$PORTMASTER_SHA256" ]; then
    FAILURES+=("verify Portmaster checksum")
    record_status "FAIL" "verify Portmaster checksum"
    log "Portmaster SHA-256 mismatch (expected $PORTMASTER_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Portmaster .deb SHA-256 ($file_size bytes)"

  install_package_group pacman "Portmaster runtime packages" PORTMASTER_RUNTIME_PACKAGES

  run_step "install Portmaster" install_portmaster_files
}

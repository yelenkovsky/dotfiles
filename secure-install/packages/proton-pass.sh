register_package proton-pass 140 "Proton Pass desktop" install_proton_pass

PROTON_PASS_VERSION_URL="https://proton.me/download/pass/linux/version.json"
PROTON_PASS_VERSION_JSON="$STATE_DIR/proton-pass-$TIMESTAMP.json"
PROTON_PASS_DEB="$STATE_DIR/proton-pass-$TIMESTAMP.deb"
PROTON_PASS_INSTALL_DIR="/opt/proton-pass"
PROTON_PASS_DEB_URL=""
PROTON_PASS_SHA512=""

download_proton_pass_version_json() {
  download_url_to_file "$PROTON_PASS_VERSION_JSON" "$PROTON_PASS_VERSION_URL"
}

# Official Linux builds are versioned .deb/.rpm only. Take the first Stable amd64
# .deb from version.json (not RPM, not Beta).
parse_proton_pass_deb() {
  local parsed

  parsed="$(awk '
    /"CategoryName":/ {
      in_stable = ($0 ~ /"Stable"/)
      next
    }
    in_stable && /"Url":/ && /proton-pass_.*_amd64\.deb/ && url == "" {
      if (match($0, /https:[^"]+/)) {
        url = substr($0, RSTART, RLENGTH)
      }
      next
    }
    url != "" && /Sha512CheckSum/ {
      if (match($0, /[a-f0-9]{128}/)) {
        print url "\t" substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$PROTON_PASS_VERSION_JSON")"

  PROTON_PASS_DEB_URL="${parsed%%$'\t'*}"
  PROTON_PASS_SHA512="${parsed#*$'\t'}"

  case "$PROTON_PASS_DEB_URL" in
    https://proton.me/download/pass/linux/proton-pass_*_amd64.deb) ;;
    *)
      log "Could not parse a Proton Pass amd64 .deb URL from $PROTON_PASS_VERSION_URL"
      return 1
      ;;
  esac

  if [ -z "$PROTON_PASS_SHA512" ] || [ "$PROTON_PASS_DEB_URL" = "$PROTON_PASS_SHA512" ]; then
    log "Could not parse the Proton Pass SHA-512 from $PROTON_PASS_VERSION_URL"
    return 1
  fi

  log "Proton Pass desktop: $PROTON_PASS_DEB_URL"
  return 0
}

download_proton_pass_deb() {
  download_url_to_file "$PROTON_PASS_DEB" "$PROTON_PASS_DEB_URL"
}

install_proton_pass_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/proton-pass-extract-$TIMESTAMP"
  local data=""
  local binary=""
  local appdir=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$PROTON_PASS_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Proton Pass .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  binary="$(find "$work" -type f -name 'Proton Pass' | head -1)"
  if [ -z "$binary" ]; then
    log "Proton Pass .deb does not contain a Proton Pass binary"
    return 1
  fi
  appdir="$(dirname "$binary")"

  sudo mkdir -p "$PROTON_PASS_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$PROTON_PASS_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$PROTON_PASS_INSTALL_DIR"
  sudo chmod u+rwX "$PROTON_PASS_INSTALL_DIR"
  sudo chmod 755 "$PROTON_PASS_INSTALL_DIR/Proton Pass"
  sudo ln -sfn "$PROTON_PASS_INSTALL_DIR/Proton Pass" /usr/local/bin/proton-pass

  sudo tee /usr/share/applications/proton-pass.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Proton Pass
Comment=Proton Pass desktop application
GenericName=Password Manager
Exec="/opt/proton-pass/Proton Pass" --no-sandbox %U
Icon=proton-pass
Type=Application
StartupNotify=true
Categories=Utility;
StartupWMClass=Proton Pass
EOF
  sudo chmod 644 /usr/share/applications/proton-pass.desktop

  icon="$(find "$work" -type f -name 'proton-pass.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/proton-pass.png
  fi

  rm -rf "$work" "$PROTON_PASS_DEB" "$PROTON_PASS_VERSION_JSON"
}

install_proton_pass() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Proton Pass version metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Proton Pass version metadata"
    log "Skipping Proton Pass desktop install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Proton Pass .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Proton Pass .deb"
    log "Skipping Proton Pass desktop install because bsdtar is not installed"
    return 0
  fi

  run_step "download Proton Pass version metadata" download_proton_pass_version_json

  if [ ! -s "$PROTON_PASS_VERSION_JSON" ]; then
    return 0
  fi

  if ! parse_proton_pass_deb; then
    FAILURES+=("parse Proton Pass amd64 .deb URL")
    record_status "FAIL" "parse Proton Pass amd64 .deb URL"
    return 0
  fi

  run_step "download Proton Pass desktop .deb" download_proton_pass_deb

  if [ ! -e "$PROTON_PASS_DEB" ]; then
    return 0
  fi

  if [ ! -s "$PROTON_PASS_DEB" ]; then
    FAILURES+=("download Proton Pass desktop .deb (empty file)")
    record_status "FAIL" "download Proton Pass desktop .deb"
    log "Downloaded Proton Pass file is empty: $PROTON_PASS_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$PROTON_PASS_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Proton Pass desktop .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Proton Pass desktop .deb"
    log "Downloaded Proton Pass file looks too small to be a .deb: $PROTON_PASS_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$PROTON_PASS_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Proton Pass desktop .deb (not an ar archive)")
    record_status "FAIL" "download Proton Pass desktop .deb"
    log "Downloaded Proton Pass file is not a .deb ar archive: $PROTON_PASS_DEB"
    return 0
  fi

  actual_hash="$(sha512sum "$PROTON_PASS_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$PROTON_PASS_SHA512" ]; then
    FAILURES+=("verify Proton Pass desktop checksum")
    record_status "FAIL" "verify Proton Pass desktop checksum"
    log "Proton Pass SHA-512 mismatch (expected $PROTON_PASS_SHA512, got $actual_hash)"
    return 0
  fi

  log "Verified Proton Pass .deb SHA-512; extracting to $PROTON_PASS_INSTALL_DIR"

  run_step "install Proton Pass desktop" install_proton_pass_files
}

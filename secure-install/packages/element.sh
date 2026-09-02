register_package element 180 "Element Desktop" install_element

ELEMENT_PACKAGES_URL="https://packages.element.io/debian/dists/default/main/binary-amd64/Packages"
ELEMENT_INRELEASE_URL="https://packages.element.io/debian/dists/default/InRelease"
ELEMENT_GPG_KEY_URL="https://packages.element.io/debian/element-io-archive-keyring.gpg"
# riot.im packages <packages@riot.im>; pin so a swapped keyring cannot pass.
ELEMENT_GPG_FINGERPRINT="12D4CD600C2240A9F4A82071D7B0B66941D01538"
ELEMENT_PACKAGES="$STATE_DIR/element-desktop-$TIMESTAMP.Packages"
ELEMENT_INRELEASE="$STATE_DIR/element-desktop-$TIMESTAMP.InRelease"
ELEMENT_GPG_KEY="$STATE_DIR/element-desktop-signing-key-$TIMESTAMP.gpg"
ELEMENT_GPG_HOME="$STATE_DIR/element-desktop-gnupg-$TIMESTAMP"
ELEMENT_DEB="$STATE_DIR/element-desktop-$TIMESTAMP.deb"
ELEMENT_INSTALL_DIR="/opt/element-desktop"
ELEMENT_DEB_URL=""
ELEMENT_SHA256=""

download_element_metadata() {
  download_url_to_file "$ELEMENT_PACKAGES" "$ELEMENT_PACKAGES_URL"
  download_url_to_file "$ELEMENT_INRELEASE" "$ELEMENT_INRELEASE_URL"
  download_url_to_file "$ELEMENT_GPG_KEY" "$ELEMENT_GPG_KEY_URL"
}

verify_element_packages_signature() {
  local imported_fingerprint=""
  local status=""
  local expected_hash=""
  local actual_hash=""

  rm -rf "$ELEMENT_GPG_HOME"
  mkdir -m 700 -p "$ELEMENT_GPG_HOME"

  status="$(
    export GNUPGHOME="$ELEMENT_GPG_HOME"
    gpg --batch --import "$ELEMENT_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$ELEMENT_GPG_FINGERPRINT" ]; then
    log "Element signing key fingerprint mismatch (expected $ELEMENT_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$ELEMENT_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$ELEMENT_INRELEASE" 2>/dev/null
  )" || true

  # InRelease is signed with the signing subkey. VALIDSIG's first fingerprint is
  # that subkey; the primary fingerprint is the last field.
  if ! printf '%s\n' "$status" | awk -v fpr="$ELEMENT_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Element InRelease GPG verification failed"
    return 1
  fi

  expected_hash="$(
    awk '
      $0 == "SHA256:" { in_sha = 1; next }
      in_sha && /^[A-Z]/ { in_sha = 0 }
      in_sha && $3 == "main/binary-amd64/Packages" { print $1; exit }
    ' "$ELEMENT_INRELEASE"
  )"
  actual_hash="$(sha256sum "$ELEMENT_PACKAGES" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    log "Element Packages SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 1
  fi

  log "Verified Element Packages GPG signature and SHA-256"
  return 0
}

parse_element_deb() {
  local parsed=""

  parsed="$(
    awk '
      $0 == "Package: element-desktop" { inpkg = 1; file = ""; hash = ""; next }
      inpkg && /^Package:/ { inpkg = 0 }
      inpkg && /^Filename:/ { file = $2 }
      inpkg && /^SHA256:/ { hash = $2 }
      END {
        if (file != "" && hash != "") {
          print file "\t" hash
        }
      }
    ' "$ELEMENT_PACKAGES"
  )"

  ELEMENT_DEB_URL="https://packages.element.io/debian/${parsed%%$'\t'*}"
  ELEMENT_SHA256="${parsed#*$'\t'}"

  case "$ELEMENT_DEB_URL" in
    https://packages.element.io/debian/pool/main/e/element-desktop/element-desktop_*_amd64.deb) ;;
    *)
      log "Could not parse an Element Desktop amd64 .deb URL from $ELEMENT_PACKAGES_URL"
      return 1
      ;;
  esac

  if [ -z "$ELEMENT_SHA256" ] || [ "$ELEMENT_DEB_URL" = "$ELEMENT_SHA256" ]; then
    log "Could not parse the Element Desktop SHA-256 from $ELEMENT_PACKAGES_URL"
    return 1
  fi

  log "Element Desktop: $ELEMENT_DEB_URL"
  return 0
}

download_element_deb() {
  download_url_to_file "$ELEMENT_DEB" "$ELEMENT_DEB_URL"
}

install_element_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/element-desktop-extract-$TIMESTAMP"
  local data=""
  local binary=""
  local appdir=""
  local icon=""
  local candidate=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$ELEMENT_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Element Desktop .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/opt/Element/element-desktop" ]; then
    appdir="$work/opt/Element"
  else
    while IFS= read -r candidate; do
      if [ "$(head -c 4 "$candidate")" = $'\x7fELF' ]; then
        binary="$candidate"
        break
      fi
    done < <(find "$work" -type f -name element-desktop)
    if [ -n "$binary" ]; then
      appdir="$(dirname "$binary")"
    fi
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/element-desktop" ]; then
    log "Element Desktop .deb does not contain an element-desktop binary"
    return 1
  fi

  sudo mkdir -p "$ELEMENT_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$ELEMENT_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$ELEMENT_INSTALL_DIR"
  sudo chmod u+rwX "$ELEMENT_INSTALL_DIR"
  sudo chmod 755 "$ELEMENT_INSTALL_DIR/element-desktop"
  # Hyprland is not a desktop Electron auto-detects; pin gnome-libsecret
  # (same as chromium-flags.conf on this machine).
  sudo tee /usr/local/bin/element-desktop >/dev/null <<EOF
#!/bin/bash
exec $ELEMENT_INSTALL_DIR/element-desktop --password-store=gnome-libsecret --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/element-desktop

  sudo tee /usr/share/applications/element-desktop.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Element
Comment=Secure Matrix messenger
GenericName=Matrix Client
Exec=$ELEMENT_INSTALL_DIR/element-desktop --password-store=gnome-libsecret --no-sandbox %U
Icon=element-desktop
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
MimeType=x-scheme-handler/element;x-scheme-handler/io.element.desktop;
StartupWMClass=Element
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/element-desktop.desktop

  icon="$(find "$work" -type f \( -name 'element.png' -o -name 'element-desktop.png' -o -name 'io.element.desktop.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/element-desktop.png
  fi

  rm -rf "$work" "$ELEMENT_DEB" "$ELEMENT_PACKAGES" "$ELEMENT_INRELEASE" "$ELEMENT_GPG_KEY" "$ELEMENT_GPG_HOME"
}

install_element() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Element metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Element metadata"
    log "Skipping Element Desktop install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Element Packages signature (missing required command: gpg)")
    record_status "FAIL" "verify Element Packages signature"
    log "Skipping Element Desktop install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Element Desktop .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Element Desktop .deb"
    log "Skipping Element Desktop install because bsdtar is not installed"
    return 0
  fi

  run_step "download Element metadata" download_element_metadata

  if [ ! -s "$ELEMENT_PACKAGES" ] || [ ! -s "$ELEMENT_INRELEASE" ]; then
    return 0
  fi

  if ! verify_element_packages_signature; then
    FAILURES+=("verify Element Packages GPG signature")
    record_status "FAIL" "verify Element Packages GPG signature"
    return 0
  fi

  if ! parse_element_deb; then
    FAILURES+=("parse Element Desktop amd64 .deb URL")
    record_status "FAIL" "parse Element Desktop amd64 .deb URL"
    return 0
  fi

  run_step "download Element Desktop .deb" download_element_deb

  if [ ! -e "$ELEMENT_DEB" ]; then
    return 0
  fi

  if [ ! -s "$ELEMENT_DEB" ]; then
    FAILURES+=("download Element Desktop .deb (empty file)")
    record_status "FAIL" "download Element Desktop .deb"
    log "Downloaded Element Desktop file is empty: $ELEMENT_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$ELEMENT_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Element Desktop .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Element Desktop .deb"
    log "Downloaded Element Desktop file looks too small to be a .deb: $ELEMENT_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$ELEMENT_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Element Desktop .deb (not an ar archive)")
    record_status "FAIL" "download Element Desktop .deb"
    log "Downloaded Element Desktop file is not a .deb ar archive: $ELEMENT_DEB"
    return 0
  fi

  actual_hash="$(sha256sum "$ELEMENT_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$ELEMENT_SHA256" ]; then
    FAILURES+=("verify Element Desktop checksum")
    record_status "FAIL" "verify Element Desktop checksum"
    log "Element Desktop SHA-256 mismatch (expected $ELEMENT_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Element Desktop .deb SHA-256; extracting to $ELEMENT_INSTALL_DIR"

  run_step "install Element Desktop" install_element_files
}

register_package zoom 340 "Zoom Workplace" install_zoom

# Official linux amd64 .deb from the latest redirect (not rpm, not the Arch
# pkg.tar.xz, not arm64). Zoom signs the .deb with dpkg-sig. The public key
# is published at the URL below; pin the 6.7.5+ fingerprint.
ZOOM_LATEST_DEB_URL="https://zoom.us/client/latest/zoom_amd64.deb"
ZOOM_GPG_KEY_URL="https://zoom.us/linux/download/pubkey"
# Zoom Communications, Inc. <CryptoOpsCodeSignProd@zoom.us>
ZOOM_GPG_FINGERPRINT="84C365D6CC9A4886CA926BCC4F2197399706AC24"
ZOOM_DEB="$STATE_DIR/zoom-$TIMESTAMP.deb"
ZOOM_GPG_KEY="$STATE_DIR/zoom-signing-key-$TIMESTAMP.pub"
ZOOM_GPG_HOME="$STATE_DIR/zoom-gnupg-$TIMESTAMP"
ZOOM_INSTALL_DIR="/opt/zoom"
ZOOM_DEB_URL=""
ZOOM_RUNTIME_PACKAGES=(
  dbus
  desktop-file-utils
  fontconfig
  freetype2
  ibus
  libatomic
  libdrm
  libglvnd
  libpulse
  libsm
  libx11
  libxcb
  libxcomposite
  libxext
  libxfixes
  libxi
  libxkbcommon-x11
  libxrender
  libxslt
  libxtst
  mesa
  sqlite
  xcb-util-cursor
  xcb-util-image
  xcb-util-keysyms
  xcb-util-wm
  xdg-utils
)

resolve_zoom_deb_url() {
  local url=""

  if ! command -v curl >/dev/null 2>&1; then
    log "Could not resolve the Zoom amd64 .deb redirect without curl"
    return 1
  fi

  url="$(curl -fsIL -o /dev/null -w '%{url_effective}' "$ZOOM_LATEST_DEB_URL")" || return 1
  url="${url%$'\r'}"

  case "$url" in
    https://cdn.zoom.us/prod/*/zoom_amd64.deb) ;;
    *)
      log "Could not resolve a Zoom amd64 .deb URL from $ZOOM_LATEST_DEB_URL (got ${url:-empty})"
      return 1
      ;;
  esac

  ZOOM_DEB_URL="$url"
  log "Zoom Workplace: $ZOOM_DEB_URL"
  return 0
}

download_zoom_files() {
  download_url_to_file "$ZOOM_DEB" "$ZOOM_DEB_URL"
  download_url_to_file "$ZOOM_GPG_KEY" "$ZOOM_GPG_KEY_URL"
}

# dpkg-sig stores a clearsigned member list in _gpgbuilder. Trust it only
# after the pinned key produces VALIDSIG, then check each member's size,
# MD5, and SHA-1 from that signed list.
verify_zoom_signature() {
  local work="$1"
  local imported_fingerprint=""
  local status=""
  local md5=""
  local sha1=""
  local size=""
  local name=""
  local actual_md5=""
  local actual_sha1=""
  local actual_size=""
  local count=0
  local saw_data=0

  rm -rf "$ZOOM_GPG_HOME"
  mkdir -m 700 -p "$ZOOM_GPG_HOME"

  status="$(
    export GNUPGHOME="$ZOOM_GPG_HOME"
    gpg --batch --import "$ZOOM_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$ZOOM_GPG_FINGERPRINT" ]; then
    log "Zoom signing key fingerprint mismatch (expected $ZOOM_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$ZOOM_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$work/_gpgbuilder" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | awk -v fpr="$ZOOM_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Zoom .deb GPG verification failed"
    return 1
  fi

  while read -r md5 sha1 size name; do
    case "$name" in
      debian-binary|control.tar.*|data.tar.*) ;;
      *)
        log "Zoom .deb signature lists an unexpected member: $name"
        return 1
        ;;
    esac

    if [ ! -f "$work/$name" ]; then
      log "Zoom .deb is missing signed member $name"
      return 1
    fi

    actual_size="$(stat -c%s "$work/$name")"
    actual_md5="$(md5sum "$work/$name" | awk '{ print $1 }')"
    actual_sha1="$(sha1sum "$work/$name" | awk '{ print $1 }')"
    if [ "$actual_size" != "$size" ] || [ "$actual_md5" != "$md5" ] || [ "$actual_sha1" != "$sha1" ]; then
      log "Zoom .deb member $name digest mismatch"
      return 1
    fi

    case "$name" in
      data.tar.*) saw_data=1 ;;
    esac
    count=$((count + 1))
  done < <(awk '
    /^-----BEGIN PGP SIGNATURE-----/ { exit }
    $1 ~ /^[0-9a-f]{32}$/ && $2 ~ /^[0-9a-f]{40}$/ && $3 ~ /^[0-9]+$/ && $4 != "" {
      print $1, $2, $3, $4
    }
  ' "$work/_gpgbuilder")

  if [ "$count" -lt 3 ] || [ "$saw_data" -ne 1 ]; then
    log "Zoom .deb signature did not cover the archive members"
    return 1
  fi

  log "Verified Zoom .deb GPG signature (VALIDSIG $ZOOM_GPG_FINGERPRINT)"
  return 0
}

install_zoom_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/zoom-extract-$TIMESTAMP"
  local stage="$STATE_DIR/zoom-stage-$TIMESTAMP"
  local data=""
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$stage"
  if [ ! -s "$work/_gpgbuilder" ]; then
    rm -rf "$work"
    mkdir -p "$work"
    bsdtar -C "$work" -xf "$ZOOM_DEB"
  fi

  if [ ! -s "$work/_gpgbuilder" ]; then
    log "Zoom .deb has no dpkg-sig signature"
    return 1
  fi

  verify_zoom_signature "$work" || return 1

  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Zoom .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ ! -x "$work/opt/zoom/ZoomLauncher" ] || [ ! -x "$work/opt/zoom/zoom" ]; then
    log "Zoom .deb does not contain ZoomLauncher and zoom"
    return 1
  fi

  if [ "$(head -c 4 "$work/opt/zoom/ZoomLauncher")" != $'\x7fELF' ] \
    || [ "$(head -c 4 "$work/opt/zoom/zoom")" != $'\x7fELF' ]; then
    log "Zoom launcher is not an ELF binary"
    return 1
  fi

  # cef/chrome_sandbox wants setuid, but this tree is user-owned so the
  # binary can be replaced. Leave it mode 755.
  sudo rm -rf "$stage"
  sudo mkdir -p "$stage"
  sudo cp -a "$work/opt/zoom"/. "$stage"/
  sudo chown -R "$owner:$group" "$stage"
  sudo chmod u+rwX "$stage"
  sudo chmod 755 "$stage/ZoomLauncher" "$stage/zoom"
  sudo rm -rf "$ZOOM_INSTALL_DIR"
  sudo mv "$stage" "$ZOOM_INSTALL_DIR"
  sudo ln -sfn "$ZOOM_INSTALL_DIR/ZoomLauncher" /usr/local/bin/zoom

  sudo tee /usr/share/applications/Zoom.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Zoom Workplace
Comment=Zoom Video Conference
Exec=/usr/local/bin/zoom %U
Icon=Zoom
Terminal=false
Type=Application
Categories=Network;Application;
StartupWMClass=zoom
MimeType=x-scheme-handler/zoommtg;x-scheme-handler/zoomus;x-scheme-handler/tel;x-scheme-handler/callto;x-scheme-handler/zoomphonecall;x-scheme-handler/zoomphonesms;x-scheme-handler/zoomcontactcentercall;application/x-zoom;
X-KDE-Protocols=zoommtg;zoomus;tel;callto;zoomphonecall;zoomphonesms;zoomcontactcentercall;
EOF
  sudo chmod 644 /usr/share/applications/Zoom.desktop

  icon="$work/usr/share/pixmaps/Zoom.png"
  if [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/Zoom.png
  fi
  icon="$work/usr/share/pixmaps/application-x-zoom.png"
  if [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/application-x-zoom.png
  fi
  if [ -f "$work/usr/share/mime/packages/zoom.xml" ]; then
    sudo install -D -m 644 "$work/usr/share/mime/packages/zoom.xml" /usr/share/mime/packages/zoom.xml
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo update-desktop-database /usr/share/applications || true
  fi
  if command -v update-mime-database >/dev/null 2>&1; then
    sudo update-mime-database /usr/share/mime || true
  fi

  rm -rf "$work" "$ZOOM_DEB" "$ZOOM_GPG_KEY" "$ZOOM_GPG_HOME"
}

install_zoom() {
  local file_size=0
  local work="$STATE_DIR/zoom-extract-$TIMESTAMP"

  install_package_group pacman "Zoom runtime packages" ZOOM_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Zoom .deb (missing required command: curl or wget)")
    record_status "FAIL" "download Zoom .deb"
    log "Skipping Zoom install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Zoom .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Zoom .deb"
    log "Skipping Zoom install because bsdtar is not installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Zoom .deb (missing required command: gpg)")
    record_status "FAIL" "verify Zoom .deb"
    log "Skipping Zoom install because gpg is not installed"
    return 0
  fi

  if ! resolve_zoom_deb_url; then
    FAILURES+=("resolve Zoom amd64 .deb URL")
    record_status "FAIL" "resolve Zoom amd64 .deb URL"
    return 0
  fi

  run_step "download Zoom .deb" download_zoom_files

  if [ ! -e "$ZOOM_DEB" ]; then
    return 0
  fi

  if [ ! -s "$ZOOM_DEB" ]; then
    FAILURES+=("download Zoom .deb (empty file)")
    record_status "FAIL" "download Zoom .deb"
    log "Downloaded Zoom file is empty: $ZOOM_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$ZOOM_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Zoom .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Zoom .deb"
    log "Downloaded Zoom file looks too small to be a .deb: $ZOOM_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$ZOOM_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Zoom .deb (not an ar archive)")
    record_status "FAIL" "download Zoom .deb"
    log "Downloaded Zoom file is not a .deb ar archive: $ZOOM_DEB"
    return 0
  fi

  if [ ! -s "$ZOOM_GPG_KEY" ]; then
    FAILURES+=("download Zoom signing key (empty file)")
    record_status "FAIL" "download Zoom signing key"
    log "Downloaded Zoom signing key is empty: $ZOOM_GPG_KEY"
    return 0
  fi

  rm -rf "$work"
  mkdir -p "$work"
  if ! bsdtar -C "$work" -xf "$ZOOM_DEB"; then
    FAILURES+=("extract Zoom .deb")
    record_status "FAIL" "extract Zoom .deb"
    log "Could not unpack the Zoom .deb"
    return 0
  fi

  if ! verify_zoom_signature "$work"; then
    FAILURES+=("verify Zoom .deb signature")
    record_status "FAIL" "verify Zoom .deb signature"
    rm -rf "$work"
    return 0
  fi

  log "Verified Zoom .deb ($file_size bytes); extracting to $ZOOM_INSTALL_DIR"

  run_step "install Zoom" install_zoom_files
}

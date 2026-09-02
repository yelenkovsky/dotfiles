register_package nextcloud 110 "Nextcloud desktop AppImage" install_nextcloud

NEXTCLOUD_LATEST_RELEASE_URL="https://github.com/nextcloud-releases/desktop/releases/latest"
NEXTCLOUD_INSTALL_DIR="/opt/nextcloud"
NEXTCLOUD_APPIMAGE_NAME="Nextcloud.AppImage"
NEXTCLOUD_DOWNLOAD="$STATE_DIR/Nextcloud-$TIMESTAMP.AppImage"
NEXTCLOUD_SIG="$STATE_DIR/Nextcloud-$TIMESTAMP.AppImage.asc"
NEXTCLOUD_GPG_KEY="$STATE_DIR/nextcloud-signing-key-$TIMESTAMP.asc"
NEXTCLOUD_GPG_HOME="$STATE_DIR/nextcloud-gnupg-$TIMESTAMP"
NEXTCLOUD_ICON_DIR="$STATE_DIR/nextcloud-icon-$TIMESTAMP"
NEXTCLOUD_DOWNLOAD_URL=""
NEXTCLOUD_GPG_KEY_URL="https://nextcloud.com/nextcloud.asc"
# Nextcloud Security <security@nextcloud.com>; pin so a swapped key file cannot pass.
NEXTCLOUD_GPG_FINGERPRINT="28806A878AE423A28372792ED75899B9A724937A"

# Asset names include the version (Nextcloud-34.0.2-x86_64.AppImage), so there is
# no stable latest/download URL. Follow /releases/latest to the current tag, or
# use gh when it is available (avoids unauthenticated API rate limits).
resolve_nextcloud_appimage_url() {
  local effective=""
  local tag=""
  local version=""

  if command -v gh >/dev/null 2>&1; then
    NEXTCLOUD_DOWNLOAD_URL="$(
      gh api repos/nextcloud-releases/desktop/releases/latest \
        --jq '.assets[] | select(.name | test("x86_64\\.AppImage$")) | .browser_download_url' \
        | head -1
    )"
  elif command -v curl >/dev/null 2>&1; then
    effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$NEXTCLOUD_LATEST_RELEASE_URL")"
    tag="${effective##*/}"
    version="${tag#v}"
    NEXTCLOUD_DOWNLOAD_URL="https://github.com/nextcloud-releases/desktop/releases/download/${tag}/Nextcloud-${version}-x86_64.AppImage"
  else
    log "Missing required command: gh or curl"
    return 127
  fi

  case "$NEXTCLOUD_DOWNLOAD_URL" in
    https://github.com/nextcloud-releases/desktop/releases/download/*/Nextcloud-*-x86_64.AppImage) ;;
    *)
      log "Could not resolve a Nextcloud x86_64 AppImage URL from $NEXTCLOUD_LATEST_RELEASE_URL"
      return 1
      ;;
  esac

  log "Nextcloud desktop AppImage: $NEXTCLOUD_DOWNLOAD_URL"
  return 0
}

download_nextcloud_appimage() {
  download_url_to_file "$NEXTCLOUD_DOWNLOAD" "$NEXTCLOUD_DOWNLOAD_URL"
  download_url_to_file "$NEXTCLOUD_SIG" "${NEXTCLOUD_DOWNLOAD_URL}.asc"
  download_url_to_file "$NEXTCLOUD_GPG_KEY" "$NEXTCLOUD_GPG_KEY_URL"
}

verify_nextcloud_appimage_signature() {
  local imported_fingerprint=""
  local status=""

  rm -rf "$NEXTCLOUD_GPG_HOME"
  mkdir -m 700 -p "$NEXTCLOUD_GPG_HOME"

  status="$(
    export GNUPGHOME="$NEXTCLOUD_GPG_HOME"
    gpg --batch --import "$NEXTCLOUD_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$NEXTCLOUD_GPG_FINGERPRINT" ]; then
    log "Nextcloud signing key fingerprint mismatch (expected $NEXTCLOUD_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$NEXTCLOUD_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$NEXTCLOUD_SIG" "$NEXTCLOUD_DOWNLOAD" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | grep -q "VALIDSIG $NEXTCLOUD_GPG_FINGERPRINT"; then
    log "Nextcloud AppImage GPG verification failed"
    return 1
  fi

  log "Verified Nextcloud AppImage GPG signature (VALIDSIG $NEXTCLOUD_GPG_FINGERPRINT)"
  return 0
}

extract_nextcloud_icon() {
  local icon=""

  mkdir -p "$NEXTCLOUD_ICON_DIR"
  (
    cd "$NEXTCLOUD_ICON_DIR"
    "$NEXTCLOUD_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/512x512/apps/*' >/dev/null 2>&1 || true
    "$NEXTCLOUD_DOWNLOAD" --appimage-extract 'usr/share/icons/hicolor/256x256/apps/*' >/dev/null 2>&1 || true
    "$NEXTCLOUD_DOWNLOAD" --appimage-extract '*.png' >/dev/null 2>&1 || true
  )

  icon="$(find "$NEXTCLOUD_ICON_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/Nextcloud.png
    log "Installed Nextcloud icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Nextcloud icon; desktop entry will use the Nextcloud icon name"
  return 0
}

install_nextcloud_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$NEXTCLOUD_INSTALL_DIR"
  sudo install -D -m 755 "$NEXTCLOUD_DOWNLOAD" "$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME"
  # The updater replaces this AppImage in place. Root ownership would block
  # self-update, so the installing user owns /opt/nextcloud.
  sudo chown -R "$owner:$group" "$NEXTCLOUD_INSTALL_DIR"
  sudo chmod u+rwX "$NEXTCLOUD_INSTALL_DIR" "$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME"
  sudo ln -sfn "$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME" /usr/local/bin/nextcloud
  sudo tee /usr/share/applications/nextcloud.desktop >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Nextcloud Desktop
GenericName=Folder Sync
Comment=Nextcloud desktop synchronization client
Exec=$NEXTCLOUD_INSTALL_DIR/$NEXTCLOUD_APPIMAGE_NAME %u
Icon=Nextcloud
Terminal=false
Categories=Utility;Network;FileTransfer;
Keywords=Nextcloud;syncing;file;sharing;
MimeType=application/vnd.nextcloud;x-scheme-handler/nc;
StartupWMClass=Nextcloud
SingleMainWindow=true
EOF
  sudo chmod 644 /usr/share/applications/nextcloud.desktop
  extract_nextcloud_icon
  rm -rf "$NEXTCLOUD_ICON_DIR" "$NEXTCLOUD_DOWNLOAD" "$NEXTCLOUD_SIG" "$NEXTCLOUD_GPG_KEY" "$NEXTCLOUD_GPG_HOME"
}

install_nextcloud() {
  local file_size=0

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
    FAILURES+=("resolve Nextcloud AppImage URL (missing required command: curl, wget, or gh)")
    record_status "FAIL" "resolve Nextcloud AppImage URL"
    log "Skipping Nextcloud install because curl, wget, and gh are not installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Nextcloud AppImage signature (missing required command: gpg)")
    record_status "FAIL" "verify Nextcloud AppImage signature"
    log "Skipping Nextcloud install because gpg is not installed"
    return 0
  fi

  if ! resolve_nextcloud_appimage_url; then
    FAILURES+=("resolve Nextcloud x86_64 AppImage URL")
    record_status "FAIL" "resolve Nextcloud x86_64 AppImage URL"
    return 0
  fi

  run_step "download Nextcloud desktop AppImage" download_nextcloud_appimage

  if [ ! -e "$NEXTCLOUD_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$NEXTCLOUD_DOWNLOAD" ]; then
    FAILURES+=("download Nextcloud desktop AppImage (empty file)")
    record_status "FAIL" "download Nextcloud desktop AppImage"
    log "Downloaded Nextcloud file is empty: $NEXTCLOUD_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$NEXTCLOUD_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Nextcloud desktop AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Nextcloud desktop AppImage"
    log "Downloaded Nextcloud file looks too small to be an AppImage: $NEXTCLOUD_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$NEXTCLOUD_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Nextcloud desktop AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Nextcloud desktop AppImage"
    log "Downloaded Nextcloud file is not an ELF AppImage: $NEXTCLOUD_DOWNLOAD"
    return 0
  fi

  if [ ! -s "$NEXTCLOUD_SIG" ]; then
    FAILURES+=("download Nextcloud AppImage signature (empty file)")
    record_status "FAIL" "download Nextcloud AppImage signature"
    log "Downloaded Nextcloud signature is empty: $NEXTCLOUD_SIG"
    return 0
  fi

  if ! verify_nextcloud_appimage_signature; then
    FAILURES+=("verify Nextcloud AppImage GPG signature")
    record_status "FAIL" "verify Nextcloud AppImage GPG signature"
    return 0
  fi

  chmod 700 "$NEXTCLOUD_DOWNLOAD"
  log "Verified Nextcloud AppImage ($file_size bytes); installing to $NEXTCLOUD_INSTALL_DIR"

  run_step "install Nextcloud desktop AppImage" install_nextcloud_files
}

# shellcheck shell=bash
register_package tor-browser 220 "Tor Browser" install_tor_browser

# downloads.json is what Tor Browser's own updater reads; it always names the
# current stable release and its detached signature.
TOR_BROWSER_DOWNLOADS_JSON_URL="https://aus1.torproject.org/torbrowser/update_3/release/downloads.json"
# Tor Browser Developers signing key, served over WKD by torproject.org.
TOR_BROWSER_GPG_KEY_URL="https://openpgpkey.torproject.org/.well-known/openpgpkey/torproject.org/hu/kounek7zrdx745qydx6p59t9mqjpuhdf"
# Primary key of "Tor Browser Developers (signing key) <torbrowser@torproject.org>".
# Releases are signed by a subkey; VALIDSIG ends with this primary fingerprint.
TOR_BROWSER_GPG_FINGERPRINT="EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"
TOR_BROWSER_INSTALL_DIR="/opt/tor-browser"
TOR_BROWSER_DOWNLOAD="$STATE_DIR/tor-browser-$TIMESTAMP.tar.xz"
TOR_BROWSER_SIG="$STATE_DIR/tor-browser-$TIMESTAMP.tar.xz.asc"
TOR_BROWSER_JSON="$STATE_DIR/tor-browser-downloads-$TIMESTAMP.json"
TOR_BROWSER_GPG_KEY="$STATE_DIR/tor-browser-signing-key-$TIMESTAMP.gpg"
TOR_BROWSER_GPG_HOME="$STATE_DIR/tor-browser-gnupg-$TIMESTAMP"
TOR_BROWSER_DOWNLOAD_URL=""
TOR_BROWSER_SIG_URL=""
register_update_check tor-browser "$TOR_BROWSER_DOWNLOAD"
register_changelog tor-browser 'https://blog.torproject.org/new-release-tor-browser-{version_nodots}/' '/torbrowser/([0-9.]+)/' 'https://blog.torproject.org/category/applications/'

resolve_tor_browser_download() {
  download_url_to_file "$TOR_BROWSER_JSON" "$TOR_BROWSER_DOWNLOADS_JSON_URL" || return 1

  TOR_BROWSER_DOWNLOAD_URL="$(jq -r '.downloads["linux-x86_64"].ALL.binary // empty' "$TOR_BROWSER_JSON")"
  TOR_BROWSER_SIG_URL="$(jq -r '.downloads["linux-x86_64"].ALL.sig // empty' "$TOR_BROWSER_JSON")"

  case "$TOR_BROWSER_DOWNLOAD_URL" in
    https://dist.torproject.org/torbrowser/*/tor-browser-linux-x86_64-*.tar.xz) ;;
    *)
      log "Could not resolve a Tor Browser linux-x86_64 tarball from $TOR_BROWSER_DOWNLOADS_JSON_URL"
      return 1
      ;;
  esac

  if [ "$TOR_BROWSER_SIG_URL" != "${TOR_BROWSER_DOWNLOAD_URL}.asc" ]; then
    log "Unexpected Tor Browser signature URL: $TOR_BROWSER_SIG_URL"
    return 1
  fi

  log "Tor Browser tarball: $TOR_BROWSER_DOWNLOAD_URL"
  return 0
}

download_tor_browser_tarball() {
  download_url_to_file "$TOR_BROWSER_DOWNLOAD" "$TOR_BROWSER_DOWNLOAD_URL" || return 1
  download_url_to_file "$TOR_BROWSER_SIG" "$TOR_BROWSER_SIG_URL" || return 1
  download_url_to_file "$TOR_BROWSER_GPG_KEY" "$TOR_BROWSER_GPG_KEY_URL"
}

verify_tor_browser_signature() {
  local imported=""
  local status=""

  rm -rf "$TOR_BROWSER_GPG_HOME"
  # shellcheck disable=SC2174  # only the GPG home itself needs 0700
  mkdir -m 700 -p "$TOR_BROWSER_GPG_HOME"

  imported="$(
    export GNUPGHOME="$TOR_BROWSER_GPG_HOME"
    gpg --batch --import "$TOR_BROWSER_GPG_KEY" >/dev/null 2>&1
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported="$(printf '%s\n' "$imported" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported" != "$TOR_BROWSER_GPG_FINGERPRINT" ]; then
    log "Tor Browser signing key fingerprint mismatch (expected $TOR_BROWSER_GPG_FINGERPRINT, got $imported)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$TOR_BROWSER_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$TOR_BROWSER_SIG" "$TOR_BROWSER_DOWNLOAD" 2>/dev/null
  )" || true

  # The last VALIDSIG field is the primary key fingerprint.
  if ! printf '%s\n' "$status" | awk -v fpr="$TOR_BROWSER_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { ok = 1 }
    END { exit !ok }
  '; then
    log "Tor Browser tarball GPG verification failed"
    return 1
  fi

  log "Verified Tor Browser GPG signature (primary key $TOR_BROWSER_GPG_FINGERPRINT)"
  return 0
}

install_tor_browser_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/tor-browser-extract-$TIMESTAMP"
  local appdir=""
  local data_rel="Browser/TorBrowser/Data"
  local icon=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$TOR_BROWSER_DOWNLOAD" || return 1

  appdir="$work/tor-browser"
  if [ ! -x "$appdir/Browser/start-tor-browser" ]; then
    log "Tor Browser tarball does not contain Browser/start-tor-browser"
    return 1
  fi

  # Tor Browser keeps its profile (bookmarks, settings, tor state) inside the
  # install tree. Carry it into the new tree so a reinstall does not wipe it.
  if [ -d "$TOR_BROWSER_INSTALL_DIR/$data_rel" ]; then
    rm -rf "${appdir:?}/$data_rel"
    cp -a "$TOR_BROWSER_INSTALL_DIR/$data_rel" "$appdir/$data_rel" || return 1
    log "Kept the existing Tor Browser profile"
  fi

  # User-owned so Tor Browser's built-in updater can replace its own files.
  replace_install_tree "$appdir" "$TOR_BROWSER_INSTALL_DIR" "$owner:$group" || return 1

  sudo tee /usr/local/bin/tor-browser >/dev/null <<EOF || return 1
#!/bin/sh
exec $TOR_BROWSER_INSTALL_DIR/Browser/start-tor-browser --detach "\$@"
EOF
  sudo chmod 755 /usr/local/bin/tor-browser || return 1

  icon="$TOR_BROWSER_INSTALL_DIR/Browser/browser/chrome/icons/default/default128.png"
  if [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/tor-browser.png || return 1
  fi

  sudo tee /usr/share/applications/tor-browser.desktop >/dev/null <<EOF || return 1
[Desktop Entry]
Type=Application
Name=Tor Browser
GenericName=Web Browser
Comment=Browse the web privately through the Tor network
Exec=/usr/local/bin/tor-browser %u
Icon=tor-browser
Terminal=false
Categories=Network;WebBrowser;Security;
StartupWMClass=Tor Browser
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/tor-browser.desktop || return 1

  rm -rf "$work" "$TOR_BROWSER_DOWNLOAD" "$TOR_BROWSER_SIG" "$TOR_BROWSER_JSON" "$TOR_BROWSER_GPG_KEY" "$TOR_BROWSER_GPG_HOME"
}

install_tor_browser() {
  local file_size=0
  local cmd=""

  for cmd in curl jq gpg bsdtar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      FAILURES+=("install Tor Browser (missing required command: $cmd)")
      record_status "FAIL" "install Tor Browser"
      log "Skipping Tor Browser install because $cmd is not installed"
      return 0
    fi
  done

  if ! resolve_tor_browser_download; then
    FAILURES+=("resolve Tor Browser linux-x86_64 tarball")
    record_status "FAIL" "resolve Tor Browser linux-x86_64 tarball"
    return 0
  fi

  run_step "download Tor Browser tarball" download_tor_browser_tarball

  if [ ! -e "$TOR_BROWSER_DOWNLOAD" ]; then
    return 0
  fi

  file_size="$(stat -c%s "$TOR_BROWSER_DOWNLOAD")"
  if [ "$file_size" -lt 50000000 ]; then
    FAILURES+=("download Tor Browser tarball (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Tor Browser tarball"
    log "Downloaded Tor Browser file looks too small: $TOR_BROWSER_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 6 "$TOR_BROWSER_DOWNLOAD" | od -An -tx1 | tr -d ' \n')" != "fd377a585a00" ]; then
    FAILURES+=("download Tor Browser tarball (not an xz archive)")
    record_status "FAIL" "download Tor Browser tarball"
    log "Downloaded Tor Browser file is not an xz archive: $TOR_BROWSER_DOWNLOAD"
    return 0
  fi

  if [ ! -s "$TOR_BROWSER_SIG" ] || [ ! -s "$TOR_BROWSER_GPG_KEY" ]; then
    FAILURES+=("download Tor Browser signature or signing key (empty file)")
    record_status "FAIL" "download Tor Browser signature"
    return 0
  fi

  if ! verify_tor_browser_signature; then
    FAILURES+=("verify Tor Browser GPG signature")
    record_status "FAIL" "verify Tor Browser GPG signature"
    return 0
  fi

  log "Verified Tor Browser ($file_size bytes); extracting to $TOR_BROWSER_INSTALL_DIR"

  close_running_app "Tor Browser" "$TOR_BROWSER_INSTALL_DIR" || return 0

  run_step "install Tor Browser" install_tor_browser_files
}

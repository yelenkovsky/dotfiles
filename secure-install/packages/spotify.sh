register_package spotify 240 "Spotify" install_spotify

# Official amd64 spotify-client from the vendor Debian repo (not snap, not i386).
SPOTIFY_PACKAGES_URL="https://repository.spotify.com/dists/stable/non-free/binary-amd64/Packages"
SPOTIFY_INRELEASE_URL="https://repository.spotify.com/dists/stable/InRelease"
SPOTIFY_GPG_KEY_URL="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc"
# Spotify Public Repository Signing Key <tux@spotify.com>; pin so a swapped key cannot pass.
SPOTIFY_GPG_FINGERPRINT="E1096BCBFF6D418796DE78515384CE82BA52C83A"
SPOTIFY_PACKAGES="$STATE_DIR/spotify-$TIMESTAMP.Packages"
SPOTIFY_INRELEASE="$STATE_DIR/spotify-$TIMESTAMP.InRelease"
SPOTIFY_GPG_KEY="$STATE_DIR/spotify-signing-key-$TIMESTAMP.asc"
SPOTIFY_GPG_HOME="$STATE_DIR/spotify-gnupg-$TIMESTAMP"
SPOTIFY_DEB="$STATE_DIR/spotify-$TIMESTAMP.deb"
SPOTIFY_INSTALL_DIR="/opt/spotify"
SPOTIFY_DEB_URL=""
SPOTIFY_SHA256=""
SPOTIFY_RUNTIME_PACKAGES=(
  alsa-lib
  gtk3
  libayatana-appindicator
  libsm
  libxss
  libxtst
  nss
  xdg-utils
)

download_spotify_metadata() {
  download_url_to_file "$SPOTIFY_PACKAGES" "$SPOTIFY_PACKAGES_URL"
  download_url_to_file "$SPOTIFY_INRELEASE" "$SPOTIFY_INRELEASE_URL"
  download_url_to_file "$SPOTIFY_GPG_KEY" "$SPOTIFY_GPG_KEY_URL"
}

verify_spotify_packages_signature() {
  local imported_fingerprint=""
  local status=""
  local expected_hash=""
  local actual_hash=""

  rm -rf "$SPOTIFY_GPG_HOME"
  mkdir -m 700 -p "$SPOTIFY_GPG_HOME"

  status="$(
    export GNUPGHOME="$SPOTIFY_GPG_HOME"
    gpg --batch --import "$SPOTIFY_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$SPOTIFY_GPG_FINGERPRINT" ]; then
    log "Spotify signing key fingerprint mismatch (expected $SPOTIFY_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$SPOTIFY_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$SPOTIFY_INRELEASE" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | awk -v fpr="$SPOTIFY_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Spotify InRelease GPG verification failed"
    return 1
  fi

  expected_hash="$(
    awk '
      $0 == "SHA256:" { in_sha = 1; next }
      in_sha && /^[A-Z]/ { in_sha = 0 }
      in_sha && $3 == "non-free/binary-amd64/Packages" { print $1; exit }
    ' "$SPOTIFY_INRELEASE"
  )"
  actual_hash="$(sha256sum "$SPOTIFY_PACKAGES" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    log "Spotify Packages SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 1
  fi

  log "Verified Spotify Packages GPG signature and SHA-256"
  return 0
}

parse_spotify_deb() {
  local parsed=""

  parsed="$(
    awk '
      $0 == "Package: spotify-client" { inpkg = 1; file = ""; hash = ""; next }
      inpkg && /^Package:/ { inpkg = 0 }
      inpkg && /^Filename:/ { file = $2 }
      inpkg && /^SHA256:/ { hash = $2 }
      END {
        if (file != "" && hash != "") {
          print file "\t" hash
        }
      }
    ' "$SPOTIFY_PACKAGES"
  )"

  SPOTIFY_DEB_URL="https://repository.spotify.com/${parsed%%$'\t'*}"
  SPOTIFY_SHA256="${parsed#*$'\t'}"

  case "$SPOTIFY_DEB_URL" in
    https://repository.spotify.com/pool/non-free/s/spotify-client/spotify-client_*_amd64.deb) ;;
    *)
      log "Could not parse a Spotify amd64 .deb URL from $SPOTIFY_PACKAGES_URL"
      return 1
      ;;
  esac

  if [ -z "$SPOTIFY_SHA256" ] || [ "$SPOTIFY_DEB_URL" = "$SPOTIFY_SHA256" ]; then
    log "Could not parse the Spotify SHA-256 from $SPOTIFY_PACKAGES_URL"
    return 1
  fi

  log "Spotify: $SPOTIFY_DEB_URL"
  return 0
}

download_spotify_deb() {
  download_url_to_file "$SPOTIFY_DEB" "$SPOTIFY_DEB_URL"
}

install_spotify_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/spotify-extract-$TIMESTAMP"
  local data=""
  local appdir=""
  local icon=""
  local candidate=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$SPOTIFY_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Spotify .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/usr/share/spotify/spotify" ]; then
    appdir="$work/usr/share/spotify"
  else
    while IFS= read -r candidate; do
      if [ "$(head -c 4 "$candidate")" = $'\x7fELF' ]; then
        appdir="$(dirname "$candidate")"
        break
      fi
    done < <(find "$work" -type f -name spotify)
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/spotify" ]; then
    log "Spotify .deb does not contain a spotify binary"
    return 1
  fi

  sudo mkdir -p "$SPOTIFY_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$SPOTIFY_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$SPOTIFY_INSTALL_DIR"
  sudo chmod u+rwX "$SPOTIFY_INSTALL_DIR"
  sudo chmod 755 "$SPOTIFY_INSTALL_DIR/spotify"
  sudo tee /usr/local/bin/spotify >/dev/null <<EOF
#!/bin/bash
exec $SPOTIFY_INSTALL_DIR/spotify --no-sandbox "\$@"
EOF
  sudo chmod 755 /usr/local/bin/spotify

  sudo tee /usr/share/applications/spotify.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Spotify
GenericName=Music Player
Comment=Spotify streaming music client
Exec=/usr/local/bin/spotify %U
Icon=spotify-client
Terminal=false
Type=Application
Categories=Audio;Music;Player;AudioVideo;
MimeType=x-scheme-handler/spotify;
StartupWMClass=spotify
EOF
  sudo chmod 644 /usr/share/applications/spotify.desktop

  icon="$(find "$work" -type f \( -name 'spotify-linux-*.png' -o -name 'spotify-client.png' -o -name 'spotify.png' \) -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/spotify-client.png
  fi

  rm -rf "$work" "$SPOTIFY_DEB" "$SPOTIFY_PACKAGES" "$SPOTIFY_INRELEASE" "$SPOTIFY_GPG_KEY" "$SPOTIFY_GPG_HOME"
}

install_spotify() {
  local file_size=0
  local actual_hash=""

  install_package_group pacman "Spotify runtime packages" SPOTIFY_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Spotify metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Spotify metadata"
    log "Skipping Spotify install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Spotify Packages signature (missing required command: gpg)")
    record_status "FAIL" "verify Spotify Packages signature"
    log "Skipping Spotify install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Spotify .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Spotify .deb"
    log "Skipping Spotify install because bsdtar is not installed"
    return 0
  fi

  run_step "download Spotify metadata" download_spotify_metadata

  if [ ! -s "$SPOTIFY_PACKAGES" ] || [ ! -s "$SPOTIFY_INRELEASE" ]; then
    return 0
  fi

  if ! verify_spotify_packages_signature; then
    FAILURES+=("verify Spotify Packages GPG signature")
    record_status "FAIL" "verify Spotify Packages GPG signature"
    return 0
  fi

  if ! parse_spotify_deb; then
    FAILURES+=("parse Spotify amd64 .deb URL")
    record_status "FAIL" "parse Spotify amd64 .deb URL"
    return 0
  fi

  run_step "download Spotify .deb" download_spotify_deb

  if [ ! -e "$SPOTIFY_DEB" ]; then
    return 0
  fi

  if [ ! -s "$SPOTIFY_DEB" ]; then
    FAILURES+=("download Spotify .deb (empty file)")
    record_status "FAIL" "download Spotify .deb"
    log "Downloaded Spotify file is empty: $SPOTIFY_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$SPOTIFY_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Spotify .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Spotify .deb"
    log "Downloaded Spotify file looks too small to be a .deb: $SPOTIFY_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$SPOTIFY_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Spotify .deb (not an ar archive)")
    record_status "FAIL" "download Spotify .deb"
    log "Downloaded Spotify file is not a .deb ar archive: $SPOTIFY_DEB"
    return 0
  fi

  actual_hash="$(sha256sum "$SPOTIFY_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$SPOTIFY_SHA256" ]; then
    FAILURES+=("verify Spotify checksum")
    record_status "FAIL" "verify Spotify checksum"
    log "Spotify SHA-256 mismatch (expected $SPOTIFY_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Spotify .deb ($file_size bytes); extracting to $SPOTIFY_INSTALL_DIR"

  run_step "install Spotify" install_spotify_files
}

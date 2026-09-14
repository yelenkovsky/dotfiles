register_package grok-bot 225 "Grok Bot desktop" install_grok_bot

# Official linux amd64 .deb from Cursor's GPG-signed apt repo (not Windows, not
# unofficial AppImage ports). The CDN 403s non-browser clients.
GROK_BOT_REPO="https://downloads.cursor.com/aptrepo"
GROK_BOT_PACKAGES_URL="$GROK_BOT_REPO/dists/grok-bot/main/binary-amd64/Packages"
GROK_BOT_INRELEASE_URL="$GROK_BOT_REPO/dists/grok-bot/InRelease"
# Anysphere Inc <security@anysphere.co>; same key Debian postinst writes to
# /usr/share/keyrings/grok-bot.gpg. Pin so a swapped key cannot pass.
GROK_BOT_GPG_FINGERPRINT="380FF4BCDC34A4BD92A3565342A1772E62E492D6"
GROK_BOT_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
GROK_BOT_PACKAGES="$STATE_DIR/grok-bot-$TIMESTAMP.Packages"
GROK_BOT_INRELEASE="$STATE_DIR/grok-bot-$TIMESTAMP.InRelease"
GROK_BOT_GPG_KEY="$STATE_DIR/grok-bot-signing-key-$TIMESTAMP.asc"
GROK_BOT_GPG_HOME="$STATE_DIR/grok-bot-gnupg-$TIMESTAMP"
GROK_BOT_DEB="$STATE_DIR/grok-bot-$TIMESTAMP.deb"
GROK_BOT_INSTALL_DIR="/opt/grok-bot"
GROK_BOT_DEB_URL=""
GROK_BOT_SHA256=""
GROK_BOT_RUNTIME_PACKAGES=(
  alsa-lib
  at-spi2-core
  gnome-keyring
  gtk3
  libnotify
  libsecret
  libxss
  libxtst
  mesa
  nss
  xdg-utils
)

write_grok_bot_signing_key() {
  cat >"$GROK_BOT_GPG_KEY" <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGhv/tgBEAC24VCTfKi5NSVaUAuSaIERf2EC5PCyOQz7WOh/UwyuG/1RB2r8
/SYtipV+fD2b+xdu7WGPqrSHrKNNO1A9j6TtqbLVDDweJU2keHOqfIaamxrcyfCw
3LMF9elIsmdkbZBukezWM32YBrG5MOwfCmG782sN79jYIPYckGZehh8Q6uIlZAzM
TR7Qr6mlRR9cRZOF1gY1hRVCXQc1P3SH+ncX1abo/w3idRjxW3l0tqzjLcovWXD1
xQdgt5odrpHlUkXRxxr7ukkPu2yJ2tL0KJydLtRDFf7k6ipYoCQv6hrFziHBHqfA
EAMymr4YH96GhlbeP/zTSeUn8Y9Blz18q8sJJ2AKoAwpxWTYDIk7D3GDxHQYkcWI
uh3MNJd3nulrptCOXgLBPqAF9/N1PW6UyX2XZmcFf0MQYC++IO0FwgcRw968L4Lv
gIGJdSCA5umcadDPoCQNcdobTur0WtzrsZ8letGoZ18FAhfeWfMWfljHDPbG0LSI
mKthaiAwXggi76sQyo374azY/ZfjepxRG3U7iEcesopqeo9p8l/8R7aZEk3zUbVt
45yhp7XN8YtDrFvAPZfcIuoQTkeDZEub9Cch+fbeqdNk+LAyUbVzX/cFWBvRWC4a
jsI/rD4IgeZInV39uG5ngpiwdb755xmZFiZSD1riGUYFYMfFfI1d80EOtQARAQAB
tCVBbnlzcGhlcmUgSW5jIDxzZWN1cml0eUBhbnlzcGhlcmUuY28+iQJRBBMBCAA7
FiEEOA/0vNw0pL2So1ZTQqF3LmLkktYFAmhv/tgCGwMFCwkIBwICIgIGFQoJCAsC
BBYCAwECHgcCF4AACgkQQqF3LmLkktZXUw//fAEm1Vo8uQ1E/4lNToEPM24olQp6
If49+HSwFLCB5HhsGFmed6Zx1L+iNDJ8eW8niuepIqSRTX8G/+0z487hP29moLTE
85g/YNsgWfkptbps3vgxlStotfgXZIKI71/m7FItBiA/tMS2ZkL1UwCSUQWE1YJg
YJ8Gm4IbvoqYNwHv+8i0wJi3/G6lphHMxQp6XuO4HVlIk0dteQPaeszFK7jf74ud
RVTpxu+ffM0x/NFw08qYPsmBQJ9Of4/dhRfAYI9ZQOAFnIhujykOs7QBnq49JlzF
3pYG/ZnvXwpUzRQgga+ro+5bXoQ1DZrNH+zl4EXtiXKpowUoYOZpDSELRVPGUW4v
syi+n34M5jMnxglYQJGB/ZTW95al7c84WZANripx2szeIxKukDcln7y0Qd7jpfGI
C7xAjTzwVK8JzsDPisP9KPfua/zifr972QMK/4xlwjRRS6yRyM7Z2QZVdtzpUdPs
VgbnXJkb6IBQSJDXKN7LQeB5Wi+4Cg9hddAG6sPu5wIcig67qFN/GEaeu6P4SuQq
gBhmtf0x26Y0MDBbJtQ4adHSr90F8Fn8si6/Hb5xjSSOTg9QsPbAbBpmXjblLLRm
dhUt0JCbIrBn2+jPKL+bT7aLkXiyI/k6kNC3AbI+YYwYgIDqSpqNHbdu+t9IOHK0
33IS4qoybKtiKbY=
=s2ww
-----END PGP PUBLIC KEY BLOCK-----
EOF
}

download_grok_bot_metadata() {
  write_grok_bot_signing_key
  download_url_to_file "$GROK_BOT_PACKAGES" "$GROK_BOT_PACKAGES_URL" "$GROK_BOT_USER_AGENT"
  download_url_to_file "$GROK_BOT_INRELEASE" "$GROK_BOT_INRELEASE_URL" "$GROK_BOT_USER_AGENT"
}

verify_grok_bot_packages_signature() {
  local imported_fingerprint=""
  local status=""
  local expected_hash=""
  local actual_hash=""

  rm -rf "$GROK_BOT_GPG_HOME"
  mkdir -m 700 -p "$GROK_BOT_GPG_HOME"

  status="$(
    export GNUPGHOME="$GROK_BOT_GPG_HOME"
    gpg --batch --import "$GROK_BOT_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$GROK_BOT_GPG_FINGERPRINT" ]; then
    log "Grok Bot signing key fingerprint mismatch (expected $GROK_BOT_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$GROK_BOT_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$GROK_BOT_INRELEASE" 2>/dev/null
  )" || true

  if ! printf '%s\n' "$status" | awk -v fpr="$GROK_BOT_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Grok Bot InRelease GPG verification failed"
    return 1
  fi

  expected_hash="$(
    awk '
      $0 == "SHA256:" { in_sha = 1; next }
      in_sha && /^[A-Z]/ { in_sha = 0 }
      in_sha && $3 == "main/binary-amd64/Packages" { print $1; exit }
    ' "$GROK_BOT_INRELEASE"
  )"
  actual_hash="$(sha256sum "$GROK_BOT_PACKAGES" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    log "Grok Bot Packages SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 1
  fi

  log "Verified Grok Bot Packages GPG signature and SHA-256"
  return 0
}

parse_grok_bot_deb() {
  local parsed=""

  parsed="$(
    awk '
      $0 == "Package: grok-bot" { inpkg = 1; file = ""; hash = ""; next }
      inpkg && /^Package:/ { inpkg = 0 }
      inpkg && /^Filename:/ { file = $2 }
      inpkg && /^SHA256:/ { hash = $2 }
      END {
        if (file != "" && hash != "") {
          print file "\t" hash
        }
      }
    ' "$GROK_BOT_PACKAGES"
  )"

  GROK_BOT_DEB_URL="$GROK_BOT_REPO/${parsed%%$'\t'*}"
  GROK_BOT_SHA256="${parsed#*$'\t'}"

  case "$GROK_BOT_DEB_URL" in
    https://downloads.cursor.com/aptrepo/pool/grok-bot/g/gr/grok-bot_*_amd64.deb) ;;
    *)
      log "Could not parse a Grok Bot amd64 .deb URL from $GROK_BOT_PACKAGES_URL"
      return 1
      ;;
  esac

  if [ -z "$GROK_BOT_SHA256" ] || [ "$GROK_BOT_DEB_URL" = "$GROK_BOT_SHA256" ]; then
    log "Could not parse the Grok Bot SHA-256 from $GROK_BOT_PACKAGES_URL"
    return 1
  fi

  log "Grok Bot desktop: $GROK_BOT_DEB_URL"
  return 0
}

download_grok_bot_deb() {
  local basename=""
  local candidate=""
  local hash=""

  basename="$(basename "$GROK_BOT_DEB_URL")"
  candidate="${HOME}/Downloads/${basename}"
  if [ -f "$candidate" ]; then
    hash="$(sha256sum "$candidate" | awk '{ print $1 }')"
    if [ "$hash" = "$GROK_BOT_SHA256" ]; then
      log "Using already-downloaded $candidate"
      cp -a "$candidate" "$GROK_BOT_DEB"
      return 0
    fi
    log "Ignoring $candidate (SHA-256 does not match signed Packages)"
  fi

  download_url_to_file "$GROK_BOT_DEB" "$GROK_BOT_DEB_URL" "$GROK_BOT_USER_AGENT"
}

install_grok_bot_files() {
  local owner="$USER"
  local group
  local work="$STATE_DIR/grok-bot-extract-$TIMESTAMP"
  local data=""
  local appdir=""
  local icon=""
  local candidate=""

  group="$(id -gn "$owner")"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$GROK_BOT_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Grok Bot .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/opt/Grok Bot/grok-bot" ]; then
    appdir="$work/opt/Grok Bot"
  else
    while IFS= read -r candidate; do
      if [ "$(head -c 4 "$candidate")" = $'\x7fELF' ]; then
        appdir="$(dirname "$candidate")"
        break
      fi
    done < <(find "$work" -type f -name grok-bot)
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/grok-bot" ]; then
    log "Grok Bot .deb does not contain a grok-bot binary"
    return 1
  fi

  sudo mkdir -p "$GROK_BOT_INSTALL_DIR"
  sudo cp -a "$appdir"/. "$GROK_BOT_INSTALL_DIR"/
  sudo chown -R "$owner:$group" "$GROK_BOT_INSTALL_DIR"
  sudo chmod u+rwX "$GROK_BOT_INSTALL_DIR"
  sudo chmod 755 "$GROK_BOT_INSTALL_DIR/grok-bot"
  # Hyprland is not a desktop Electron auto-detects; pin gnome-libsecret
  # (same as chromium-flags.conf and Cursor on this machine). chrome-sandbox
  # cannot be setuid on a user-owned tree.
  sudo rm -f /usr/local/bin/grok-bot
  sudo tee /usr/local/bin/grok-bot >/dev/null <<EOF
#!/bin/bash
exec $GROK_BOT_INSTALL_DIR/grok-bot --password-store=gnome-libsecret --no-sandbox --ozone-platform-hint=auto "\$@"
EOF
  sudo chmod 755 /usr/local/bin/grok-bot

  sudo tee /usr/share/applications/grok-bot.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Grok Bot
Comment=Grok Bot desktop agent
Exec=/usr/local/bin/grok-bot %U
Icon=grok-bot
Terminal=false
Type=Application
Categories=Development;Network;
MimeType=x-scheme-handler/grokbot;x-scheme-handler/sand;
StartupWMClass=Grok Bot
StartupNotify=true
EOF
  sudo chmod 644 /usr/share/applications/grok-bot.desktop

  icon="$(find "$work" -type f -name 'grok-bot.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/grok-bot.png
  fi

  rm -rf "$work" "$GROK_BOT_DEB" "$GROK_BOT_PACKAGES" "$GROK_BOT_INRELEASE" "$GROK_BOT_GPG_KEY" "$GROK_BOT_GPG_HOME"
}

install_grok_bot() {
  local file_size=0
  local actual_hash=""

  install_package_group pacman "Grok Bot runtime packages" GROK_BOT_RUNTIME_PACKAGES

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Grok Bot metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Grok Bot metadata"
    log "Skipping Grok Bot install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Grok Bot Packages signature (missing required command: gpg)")
    record_status "FAIL" "verify Grok Bot Packages signature"
    log "Skipping Grok Bot install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Grok Bot .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Grok Bot .deb"
    log "Skipping Grok Bot install because bsdtar is not installed"
    return 0
  fi

  run_step "download Grok Bot metadata" download_grok_bot_metadata

  if [ ! -s "$GROK_BOT_PACKAGES" ] || [ ! -s "$GROK_BOT_INRELEASE" ]; then
    return 0
  fi

  if ! verify_grok_bot_packages_signature; then
    FAILURES+=("verify Grok Bot Packages GPG signature")
    record_status "FAIL" "verify Grok Bot Packages GPG signature"
    return 0
  fi

  if ! parse_grok_bot_deb; then
    FAILURES+=("parse Grok Bot amd64 .deb URL")
    record_status "FAIL" "parse Grok Bot amd64 .deb URL"
    return 0
  fi

  run_step "download Grok Bot .deb" download_grok_bot_deb

  if [ ! -e "$GROK_BOT_DEB" ]; then
    return 0
  fi

  if [ ! -s "$GROK_BOT_DEB" ]; then
    FAILURES+=("download Grok Bot .deb (empty file)")
    record_status "FAIL" "download Grok Bot .deb"
    log "Downloaded Grok Bot file is empty: $GROK_BOT_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$GROK_BOT_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Grok Bot .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Grok Bot .deb"
    log "Downloaded Grok Bot file looks too small to be a .deb: $GROK_BOT_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$GROK_BOT_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Grok Bot .deb (not an ar archive)")
    record_status "FAIL" "download Grok Bot .deb"
    log "Downloaded Grok Bot file is not a .deb ar archive: $GROK_BOT_DEB"
    return 0
  fi

  actual_hash="$(sha256sum "$GROK_BOT_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$GROK_BOT_SHA256" ]; then
    FAILURES+=("verify Grok Bot checksum")
    record_status "FAIL" "verify Grok Bot checksum"
    log "Grok Bot SHA-256 mismatch (expected $GROK_BOT_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Grok Bot .deb SHA-256; extracting to $GROK_BOT_INSTALL_DIR"

  run_step "install Grok Bot" install_grok_bot_files
}

register_package claude-desktop 300 "Claude Desktop" install_claude_desktop

# Official linux/amd64 glibc .deb from Anthropic's stable apt repo (not arm64,
# not the Claude Code CLI). The Packages index is covered by a signed
# InRelease; SHA-256 of the .deb comes from that index.
CLAUDE_DESKTOP_PACKAGES_URL="https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages"
CLAUDE_DESKTOP_INRELEASE_URL="https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/InRelease"
CLAUDE_DESKTOP_GPG_KEY_URL="https://downloads.claude.ai/claude-desktop/key.asc"
# Anthropic Claude Code Release Signing <security@anthropic.com>
CLAUDE_DESKTOP_GPG_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
CLAUDE_DESKTOP_PACKAGES="$STATE_DIR/claude-desktop-$TIMESTAMP.Packages"
CLAUDE_DESKTOP_INRELEASE="$STATE_DIR/claude-desktop-$TIMESTAMP.InRelease"
CLAUDE_DESKTOP_GPG_KEY="$STATE_DIR/claude-desktop-signing-key-$TIMESTAMP.asc"
CLAUDE_DESKTOP_GPG_HOME="$STATE_DIR/claude-desktop-gnupg-$TIMESTAMP"
CLAUDE_DESKTOP_DEB="$STATE_DIR/claude-desktop-$TIMESTAMP.deb"
# User prefix: sudo on this machine asks for a password, and the desktop
# entry has to be installable without one. $HOME is not hardcoded.
CLAUDE_DESKTOP_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-desktop"
CLAUDE_DESKTOP_LAUNCHER="${HOME}/.local/bin/claude-desktop"
CLAUDE_DESKTOP_DESKTOP_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/applications/claude-desktop.desktop"
CLAUDE_DESKTOP_ICON_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
CLAUDE_DESKTOP_DEB_URL=""
CLAUDE_DESKTOP_SHA256=""

download_claude_desktop_metadata() {
  download_url_to_file "$CLAUDE_DESKTOP_PACKAGES" "$CLAUDE_DESKTOP_PACKAGES_URL"
  download_url_to_file "$CLAUDE_DESKTOP_INRELEASE" "$CLAUDE_DESKTOP_INRELEASE_URL"
  download_url_to_file "$CLAUDE_DESKTOP_GPG_KEY" "$CLAUDE_DESKTOP_GPG_KEY_URL"
}

verify_claude_desktop_packages_signature() {
  local imported_fingerprint=""
  local status=""
  local expected_hash=""
  local actual_hash=""

  rm -rf "$CLAUDE_DESKTOP_GPG_HOME"
  mkdir -m 700 -p "$CLAUDE_DESKTOP_GPG_HOME"

  status="$(
    export GNUPGHOME="$CLAUDE_DESKTOP_GPG_HOME"
    gpg --batch --import "$CLAUDE_DESKTOP_GPG_KEY" >/dev/null
    gpg --batch --with-colons --fingerprint
  )" || return 1

  imported_fingerprint="$(printf '%s\n' "$status" | awk -F: '/^fpr:/ { print $10; exit }')"
  if [ "$imported_fingerprint" != "$CLAUDE_DESKTOP_GPG_FINGERPRINT" ]; then
    log "Claude Desktop signing key fingerprint mismatch (expected $CLAUDE_DESKTOP_GPG_FINGERPRINT, got $imported_fingerprint)"
    return 1
  fi

  status="$(
    export GNUPGHOME="$CLAUDE_DESKTOP_GPG_HOME"
    gpg --batch --status-fd 1 --verify "$CLAUDE_DESKTOP_INRELEASE" 2>/dev/null
  )" || true

  # InRelease is signed with the signing key. VALIDSIG's first fingerprint is
  # that key; the primary fingerprint is the last field.
  if ! printf '%s\n' "$status" | awk -v fpr="$CLAUDE_DESKTOP_GPG_FINGERPRINT" '
    $2 == "VALIDSIG" && $NF == fpr { found = 1 }
    END { exit !found }
  '; then
    log "Claude Desktop InRelease GPG verification failed"
    return 1
  fi

  expected_hash="$(
    awk '
      $0 == "SHA256:" { in_sha = 1; next }
      in_sha && /^[A-Z]/ { in_sha = 0 }
      in_sha && $3 == "main/binary-amd64/Packages" { print $1; exit }
    ' "$CLAUDE_DESKTOP_INRELEASE"
  )"
  actual_hash="$(sha256sum "$CLAUDE_DESKTOP_PACKAGES" | awk '{ print $1 }')"
  if [ -z "$expected_hash" ] || [ "$actual_hash" != "$expected_hash" ]; then
    log "Claude Desktop Packages SHA-256 mismatch (expected $expected_hash, got $actual_hash)"
    return 1
  fi

  log "Verified Claude Desktop Packages GPG signature and SHA-256"
  return 0
}

# The index keeps every published amd64 build. Take the newest version only.
parse_claude_desktop_deb() {
  local parsed=""

  parsed="$(
    awk '
      $0 == "Package: claude-desktop" { inpkg = 1; ver = ""; file = ""; hash = ""; next }
      inpkg && /^$/ {
        if (ver != "" && file != "" && hash != "") print ver "\t" file "\t" hash
        inpkg = 0
        next
      }
      inpkg && /^Version:/ { ver = $2 }
      inpkg && /^Filename:/ { file = $2 }
      inpkg && /^SHA256:/ { hash = $2 }
      END {
        if (inpkg && ver != "" && file != "" && hash != "") print ver "\t" file "\t" hash
      }
    ' "$CLAUDE_DESKTOP_PACKAGES" | sort -V | tail -n 1
  )"

  CLAUDE_DESKTOP_DEB_URL="https://downloads.claude.ai/claude-desktop/apt/stable/${parsed#*$'\t'}"
  CLAUDE_DESKTOP_DEB_URL="${CLAUDE_DESKTOP_DEB_URL%%$'\t'*}"
  CLAUDE_DESKTOP_SHA256="${parsed##*$'\t'}"

  case "$CLAUDE_DESKTOP_DEB_URL" in
    https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_*_amd64.deb) ;;
    *)
      log "Could not parse a Claude Desktop amd64 .deb URL from $CLAUDE_DESKTOP_PACKAGES_URL"
      return 1
      ;;
  esac

  if [ -z "$CLAUDE_DESKTOP_SHA256" ] || [ "$CLAUDE_DESKTOP_DEB_URL" = "$CLAUDE_DESKTOP_SHA256" ]; then
    log "Could not parse the Claude Desktop SHA-256 from $CLAUDE_DESKTOP_PACKAGES_URL"
    return 1
  fi

  log "Claude Desktop: $CLAUDE_DESKTOP_DEB_URL"
  return 0
}

download_claude_desktop_deb() {
  download_url_to_file "$CLAUDE_DESKTOP_DEB" "$CLAUDE_DESKTOP_DEB_URL"
}

install_claude_desktop_files() {
  local work="$STATE_DIR/claude-desktop-extract-$TIMESTAMP"
  local data=""
  local appdir=""
  local icon=""
  local size_dir=""
  local icon_path="claude-desktop"

  rm -rf "$work"
  mkdir -p "$work"
  bsdtar -C "$work" -xf "$CLAUDE_DESKTOP_DEB"
  data="$(find "$work" -maxdepth 1 -name 'data.tar.*' | head -1)"
  if [ -z "$data" ]; then
    log "Claude Desktop .deb has no data.tar payload"
    return 1
  fi
  bsdtar -C "$work" -xf "$data"

  if [ -x "$work/usr/lib/claude-desktop/claude-desktop" ]; then
    appdir="$work/usr/lib/claude-desktop"
  fi

  if [ -z "$appdir" ] || [ ! -x "$appdir/claude-desktop" ]; then
    log "Claude Desktop .deb does not contain a claude-desktop binary"
    return 1
  fi

  rm -rf "$CLAUDE_DESKTOP_INSTALL_DIR"
  mkdir -p "$CLAUDE_DESKTOP_INSTALL_DIR" "$(dirname "$CLAUDE_DESKTOP_LAUNCHER")" "$(dirname "$CLAUDE_DESKTOP_DESKTOP_FILE")"
  cp -a "$appdir"/. "$CLAUDE_DESKTOP_INSTALL_DIR"/
  chmod u+rwX "$CLAUDE_DESKTOP_INSTALL_DIR"
  chmod 755 "$CLAUDE_DESKTOP_INSTALL_DIR/claude-desktop"
  # Hyprland is not a desktop Electron auto-detects; pin gnome-libsecret
  # (same as chromium-flags.conf on this machine). chrome-sandbox cannot be
  # setuid on a user-owned tree. Remove any previous path first so the
  # redirect cannot follow a symlink into the app tree.
  rm -f "$CLAUDE_DESKTOP_LAUNCHER"
  cat >"$CLAUDE_DESKTOP_LAUNCHER" <<EOF
#!/bin/bash
exec $CLAUDE_DESKTOP_INSTALL_DIR/claude-desktop --password-store=gnome-libsecret --no-sandbox --ozone-platform-hint=auto "\$@"
EOF
  chmod 755 "$CLAUDE_DESKTOP_LAUNCHER"

  if [ -d "$work/usr/share/icons/hicolor" ]; then
    while IFS= read -r icon; do
      size_dir="$(basename "$(dirname "$(dirname "$icon")")")"
      install -D -m 644 "$icon" "$CLAUDE_DESKTOP_ICON_ROOT/hicolor/${size_dir}/apps/claude-desktop.png"
      if [ "$size_dir" = "256x256" ]; then
        icon_path="$CLAUDE_DESKTOP_ICON_ROOT/hicolor/${size_dir}/apps/claude-desktop.png"
      fi
    done < <(find "$work/usr/share/icons/hicolor" -type f -name 'claude-desktop.png')
  fi

  cat >"$CLAUDE_DESKTOP_DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Claude
Comment=Desktop application for Claude.ai
GenericName=AI Assistant
Keywords=AI;Chat;Assistant;Claude;Code;LLM;
Exec=$CLAUDE_DESKTOP_LAUNCHER %U
Icon=$icon_path
Terminal=false
Type=Application
StartupNotify=true
StartupWMClass=com.anthropic.Claude
SingleMainWindow=true
Categories=Utility;Development;
MimeType=x-scheme-handler/claude;
Actions=NewChat;NewCode;

[Desktop Action NewChat]
Name=New Chat
Exec=$CLAUDE_DESKTOP_LAUNCHER "claude://claude.ai/new?surface=chat&source=desktop_action"

[Desktop Action NewCode]
Name=New Claude Code Session
Exec=$CLAUDE_DESKTOP_LAUNCHER "claude://code/new?source=desktop_action"
EOF
  chmod 644 "$CLAUDE_DESKTOP_DESKTOP_FILE"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$(dirname "$CLAUDE_DESKTOP_DESKTOP_FILE")" >/dev/null 2>&1 || true
  fi

  rm -rf "$work" "$CLAUDE_DESKTOP_DEB" "$CLAUDE_DESKTOP_PACKAGES" "$CLAUDE_DESKTOP_INRELEASE" "$CLAUDE_DESKTOP_GPG_KEY" "$CLAUDE_DESKTOP_GPG_HOME"
}

install_claude_desktop() {
  local file_size=0
  local actual_hash=""

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Claude Desktop metadata (missing required command: curl or wget)")
    record_status "FAIL" "download Claude Desktop metadata"
    log "Skipping Claude Desktop install because neither curl nor wget is installed"
    return 0
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    FAILURES+=("verify Claude Desktop Packages signature (missing required command: gpg)")
    record_status "FAIL" "verify Claude Desktop Packages signature"
    log "Skipping Claude Desktop install because gpg is not installed"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    FAILURES+=("extract Claude Desktop .deb (missing required command: bsdtar)")
    record_status "FAIL" "extract Claude Desktop .deb"
    log "Skipping Claude Desktop install because bsdtar is not installed"
    return 0
  fi

  run_step "download Claude Desktop metadata" download_claude_desktop_metadata

  if [ ! -s "$CLAUDE_DESKTOP_PACKAGES" ] || [ ! -s "$CLAUDE_DESKTOP_INRELEASE" ] || [ ! -s "$CLAUDE_DESKTOP_GPG_KEY" ]; then
    return 0
  fi

  if ! verify_claude_desktop_packages_signature; then
    FAILURES+=("verify Claude Desktop Packages GPG signature")
    record_status "FAIL" "verify Claude Desktop Packages GPG signature"
    return 0
  fi

  if ! parse_claude_desktop_deb; then
    FAILURES+=("parse Claude Desktop amd64 .deb URL")
    record_status "FAIL" "parse Claude Desktop amd64 .deb URL"
    return 0
  fi

  run_step "download Claude Desktop .deb" download_claude_desktop_deb

  if [ ! -e "$CLAUDE_DESKTOP_DEB" ]; then
    return 0
  fi

  if [ ! -s "$CLAUDE_DESKTOP_DEB" ]; then
    FAILURES+=("download Claude Desktop .deb (empty file)")
    record_status "FAIL" "download Claude Desktop .deb"
    log "Downloaded Claude Desktop file is empty: $CLAUDE_DESKTOP_DEB"
    return 0
  fi

  file_size="$(stat -c%s "$CLAUDE_DESKTOP_DEB")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Claude Desktop .deb (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Claude Desktop .deb"
    log "Downloaded Claude Desktop file looks too small to be a .deb: $CLAUDE_DESKTOP_DEB ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 7 "$CLAUDE_DESKTOP_DEB")" != '!<arch>' ]; then
    FAILURES+=("download Claude Desktop .deb (not an ar archive)")
    record_status "FAIL" "download Claude Desktop .deb"
    log "Downloaded Claude Desktop file is not a .deb ar archive: $CLAUDE_DESKTOP_DEB"
    return 0
  fi

  actual_hash="$(sha256sum "$CLAUDE_DESKTOP_DEB" | awk '{ print $1 }')"
  if [ "$actual_hash" != "$CLAUDE_DESKTOP_SHA256" ]; then
    FAILURES+=("verify Claude Desktop checksum")
    record_status "FAIL" "verify Claude Desktop checksum"
    log "Claude Desktop SHA-256 mismatch (expected $CLAUDE_DESKTOP_SHA256, got $actual_hash)"
    return 0
  fi

  log "Verified Claude Desktop .deb SHA-256; extracting to $CLAUDE_DESKTOP_INSTALL_DIR"

  run_step "install Claude Desktop" install_claude_desktop_files
}

register_package cursor 220 "Cursor nightly (dev) AppImage" install_cursor

# Official linux/x64 glibc AppImage from the dev (nightly) track, not arm64
# and not releaseTrack=stable. Cursor does not publish SHA-256 next to the
# file; verify ELF + size instead.
CURSOR_DOWNLOAD_API_URL="https://cursor.com/api/download?platform=linux-x64&releaseTrack=dev"
CURSOR_API_JSON="$STATE_DIR/cursor-download-$TIMESTAMP.json"
CURSOR_INSTALL_DIR="/opt/cursor"
CURSOR_APPIMAGE_NAME="Cursor.AppImage"
CURSOR_CURRENT_DIR="$CURSOR_INSTALL_DIR/current"
CURSOR_LAUNCH="$CURSOR_INSTALL_DIR/launch"
CURSOR_UPDATER="$CURSOR_INSTALL_DIR/appimageupdatetool.AppImage"
CURSOR_DOWNLOAD="$STATE_DIR/Cursor-$TIMESTAMP.AppImage"
CURSOR_DOWNLOAD_URL=""

download_cursor_api_json() {
  download_url_to_file "$CURSOR_API_JSON" "$CURSOR_DOWNLOAD_API_URL" "Mozilla/5.0"
}

# Match linux/x64 AppImage only (not arm64, not .deb/.rpm).
parse_cursor_appimage_url() {
  CURSOR_DOWNLOAD_URL="$(awk '
    /"downloadUrl":/ && /linux\/x64\/Cursor-.*-x86_64\.AppImage/ {
      if (match($0, /https:[^"]+/)) {
        print substr($0, RSTART, RLENGTH)
        exit
      }
    }
  ' "$CURSOR_API_JSON")"

  case "$CURSOR_DOWNLOAD_URL" in
    https://downloads.cursor.com/production/*/linux/x64/Cursor-*-x86_64.AppImage) ;;
    *)
      log "Could not parse a Cursor linux/x64 AppImage URL from $CURSOR_DOWNLOAD_API_URL"
      return 1
      ;;
  esac

  log "Cursor AppImage: $CURSOR_DOWNLOAD_URL"
  return 0
}

download_cursor_appimage() {
  download_url_to_file "$CURSOR_DOWNLOAD" "$CURSOR_DOWNLOAD_URL"
}

# Cursor's in-app updater runs from the "quit" event:
#   $resources/appimageupdatetool.AppImage -u "zsync|..." -O "$APPIMAGE"; $APPIMAGE &
# If Cursor is a live FUSE AppImage, that updater path dies with the mount and
# the trailing command relaunches the unchanged file (reload, same version).
# Launch the extracted ELF with APPIMAGE still pointing at the writable
# AppImage so resourcesPath and appimageupdatetool survive quit.
#
# appimageupdatetool also restores the old file when GPG validation fails.
# Nightly AppImages are often unsigned, then a later build is signed (or
# signed with a key the tool cannot check). zsync succeeds, then:
#   Validation error: Bad signature / Restoring original file
# The shim falls back to a full download of the same official URL.
write_cursor_launch() {
  cat >"$CURSOR_LAUNCH" <<'EOF'
#!/bin/bash
set -euo pipefail

INSTALL=/opt/cursor
APP="$INSTALL/Cursor.AppImage"
ROOT="$INSTALL/current"
STAMP="$INSTALL/.appimage-id"
UPDATER_REAL="$INSTALL/appimageupdatetool.AppImage"
UPDATER_NESTED="$ROOT/usr/share/cursor/resources/appimageupdatetool.AppImage"
LOG_DIR="$INSTALL/logs"

cursor_appimage_id() {
  stat -c '%Y-%s' "$APP"
}

cursor_running_from_extract() {
  local pid exe

  for pid in /proc/[0-9]*; do
    exe="$(readlink "$pid/exe" 2>/dev/null || true)"
    if [ "$exe" = "$ROOT/usr/share/cursor/cursor" ]; then
      return 0
    fi
  done
  return 1
}

install_cursor_updater_shim() {
  mkdir -p "$(dirname "$UPDATER_NESTED")" "$LOG_DIR"
  cat >"$UPDATER_NESTED" <<'SH'
#!/bin/bash
set -euo pipefail
REAL=/opt/cursor/appimageupdatetool.AppImage
APP=/opt/cursor/Cursor.AppImage
LAUNCH=/opt/cursor/launch
LOG=/opt/cursor/logs/appimage-update.log
mkdir -p /opt/cursor/logs

log() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$*" >>"$LOG"
}

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Cursor" "$1" || true
  fi
}

cursor_full_download() {
  local url="$1"
  local dest="$2"
  local tmp size magic

  tmp="$(mktemp "$dest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  log "full download $url -> $dest"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -A "Mozilla/5.0" -o "$tmp" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --tries=3 -U "Mozilla/5.0" -O "$tmp" "$url"
  else
    log "missing curl or wget"
    return 127
  fi

  size="$(stat -c%s "$tmp")"
  magic="$(head -c 4 "$tmp")"
  if [ "$size" -lt 10000000 ] || [ "$magic" != $'\x7fELF' ]; then
    log "full download is not a Cursor AppImage (${size} bytes)"
    return 1
  fi
  chmod 755 "$tmp"
  mv -f "$tmp" "$dest"
  trap - RETURN
  log "full download installed $dest ($size bytes)"
}

extract_after_update() {
  nohup env CURSOR_EXTRACT_ONLY=1 "$LAUNCH" >>/opt/cursor/logs/extract-after-update.log 2>&1 &
  disown || true
}

# Cursor spawns this from the quit event; give the old process a moment to
# release the AppImage before zsync rewrites it.
sleep 2
notify "Installing update…"
log "appimageupdatetool $*"

if [ ! -x "$REAL" ]; then
  log "missing $REAL"
  exit 127
fi

update_info=""
appimage="$APP"
args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    -u|--update-info)
      update_info="${2-}"
      shift 2
      ;;
    -O|--overwrite)
      if [ -n "${2-}" ] && [ "${2#-}" = "$2" ]; then
        appimage="$2"
        shift 2
      else
        shift
      fi
      ;;
    -*)
      shift
      ;;
    *)
      appimage="$1"
      shift
      ;;
  esac
done
set -- "${args[@]}"

export APPIMAGE_EXTRACT_AND_RUN=1
runlog="$(mktemp /opt/cursor/logs/update-run.XXXXXX)"
rc=0
"$REAL" "$@" >"$runlog" 2>&1 || rc=$?
cat "$runlog" >>"$LOG"
if [ "$rc" -eq 0 ] && ! grep -q "Restoring original file" "$runlog"; then
  rm -f "$runlog"
  log "appimageupdatetool succeeded"
  notify "Update installed"
  extract_after_update
  exit 0
fi

log "appimageupdatetool failed (rc=$rc); trying official full download"
notify "Signature check failed; downloading full update…"
url=""
case "$update_info" in
  'zsync|http://'*|'zsync|https://'*)
    url="${update_info#zsync|}"
    url="${url%.zsync}"
    ;;
esac
rm -f "$runlog"
if [ -z "$url" ]; then
  log "no zsync URL in updater args; cannot fall back ($update_info)"
  notify "Cursor update failed"
  exit 1
fi
if ! cursor_full_download "$url" "$appimage"; then
  notify "Cursor update failed"
  exit 1
fi
notify "Update installed"
extract_after_update
exit 0
SH
  chmod 755 "$UPDATER_NESTED"
}

extract_cursor_payload() {
  local tmp id

  if [ ! -x "$APP" ]; then
    echo "Cursor AppImage is missing: $APP" >&2
    exit 1
  fi

  tmp="$(mktemp -d "$INSTALL/extract.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  (
    cd "$tmp"
    "$APP" --appimage-extract >/dev/null
  )
  if [ ! -x "$tmp/squashfs-root/usr/share/cursor/cursor" ] || [ ! -x "$tmp/squashfs-root/AppRun" ]; then
    echo "Cursor AppImage extract did not contain usr/share/cursor/cursor" >&2
    exit 1
  fi
  if [ -f "$tmp/squashfs-root/usr/share/cursor/resources/appimageupdatetool.AppImage" ]; then
    cp -f "$tmp/squashfs-root/usr/share/cursor/resources/appimageupdatetool.AppImage" "$UPDATER_REAL"
    chmod 755 "$UPDATER_REAL"
  fi
  rm -rf "$ROOT"
  mv "$tmp/squashfs-root" "$ROOT"
  trap - EXIT
  rm -rf "$tmp"
  id="$(cursor_appimage_id)"
  printf '%s\n' "$id" >"$STAMP"
  chmod u+rwX "$ROOT" "$APP" || true
}

rewrite_extracted_desktops() {
  local file

  # AppRun reads $ROOT/cursor.desktop and execs that Exec line. Leave it as
  # `cursor` so PATH finds $ROOT/usr/bin/cursor. Rewriting it to this launcher
  # made AppRun call /opt/cursor/launch in a loop, so Cursor never started.
  for file in \
    "$ROOT/usr/share/applications/cursor.desktop" \
    "$ROOT/usr/share/applications/cursor-url-handler.desktop"
  do
    [ -f "$file" ] || continue
    sed -i \
      -e 's|^Exec=/usr/share/cursor/cursor|Exec=/opt/cursor/launch|' \
      -e 's|^Exec=cursor |Exec=/opt/cursor/launch |' \
      -e 's|^Exec=cursor$|Exec=/opt/cursor/launch|' \
      "$file"
  done
  if [ -f "$ROOT/cursor.desktop" ]; then
    sed -i \
      -e 's|^Exec=/opt/cursor/launch --new-window|Exec=cursor --new-window|' \
      -e 's|^Exec=/opt/cursor/launch|Exec=cursor|' \
      "$ROOT/cursor.desktop"
  fi
}

if [ ! -x "$APP" ]; then
  echo "Cursor AppImage is missing: $APP" >&2
  exit 1
fi

if [ "${CURSOR_EXTRACT_ONLY:-0}" = 1 ]; then
  if cursor_running_from_extract; then
    echo "Not replacing $ROOT while Cursor is running from it; restart Cursor to finish installing" >&2
  else
    extract_cursor_payload
  fi
  install_cursor_updater_shim
  rewrite_extracted_desktops
  exit 0
fi

id="$(cursor_appimage_id)"
if [ ! -x "$ROOT/AppRun" ] || [ ! -x "$ROOT/usr/share/cursor/cursor" ] || [ "$(cat "$STAMP" 2>/dev/null || true)" != "$id" ]; then
  if cursor_running_from_extract; then
    echo "Cursor payload is stale but still running; using the current extract" >&2
  else
    extract_cursor_payload
  fi
fi

install_cursor_updater_shim
rewrite_extracted_desktops

if [ "${CURSOR_LAUNCHING:-}" = 1 ]; then
  echo "Cursor launch wrapper called itself; starting the extracted binary" >&2
  exec "$ROOT/usr/share/cursor/cursor" --password-store=gnome-libsecret --no-sandbox "$@"
fi
export CURSOR_LAUNCHING=1
export APPIMAGE="$APP"
export ARGV0="$APP"
cd "$ROOT"
exec "$ROOT/AppRun" --password-store=gnome-libsecret --no-sandbox "$@"
EOF
  chmod 755 "$CURSOR_LAUNCH"
}

extract_cursor_icon() {
  local icon=""

  icon="$(find "$CURSOR_CURRENT_DIR/usr/share/icons/hicolor/512x512" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  if [ -z "$icon" ] || [ ! -f "$icon" ]; then
    icon="$(find "$CURSOR_CURRENT_DIR/usr/share/pixmaps" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  fi
  if [ -z "$icon" ] || [ ! -f "$icon" ]; then
    icon="$(find "$CURSOR_CURRENT_DIR" -type f -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -nr | awk 'NR==1 { $1=""; sub(/^ /, ""); print }')"
  fi

  if [ -n "$icon" ] && [ -f "$icon" ]; then
    sudo install -D -m 644 "$icon" /usr/share/pixmaps/cursor.png
    log "Installed Cursor icon from AppImage: $icon"
    return 0
  fi

  log "Could not extract a Cursor icon; desktop entry will use the cursor icon name"
  return 0
}

# Point Hyprland Cursor shortcuts at the extracted launcher. `launch = "cursor"`
# goes through uwsm PATH and can still hit an old AppImage wrapper.
fix_cursor_hypr_bindings() {
  local file="$HOME/.config/hypr/bindings.lua"
  local before=""

  if [ ! -f "$file" ]; then
    return 0
  fi

  before="$(cat "$file")"
  sed -i \
    -e 's|launch = "cursor"|launch = "/opt/cursor/launch"|g' \
    -e "s|launch = 'cursor'|launch = \"/opt/cursor/launch\"|g" \
    -e 's|/opt/cursor/Cursor\.AppImage|/opt/cursor/launch|g' \
    "$file"
  if [ "$(cat "$file")" = "$before" ]; then
    log "Hyprland Cursor binding already uses $CURSOR_LAUNCH"
    return 0
  fi

  log "Updated Hyprland Cursor launch path in $file"
  if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE-}" ]; then
    hyprctl reload >/dev/null
    hyprctl configerrors
  fi
}

fix_cursor_mimeapps() {
  local file="$HOME/.config/mimeapps.list"

  mkdir -p "$(dirname "$file")"
  if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default cursor.desktop x-scheme-handler/cursor >/dev/null 2>&1 || true
    xdg-mime default cursor.desktop application/x-cursor-workspace >/dev/null 2>&1 || true
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text() if path.exists() else "[Default Applications]\n"
defaults = [
    "x-scheme-handler/cursor=cursor.desktop",
    "application/x-cursor-workspace=cursor.desktop",
]
added = [
    "x-scheme-handler/cursor=cursor.desktop;",
    "application/x-cursor-workspace=cursor.desktop;",
]
if "[Default Applications]" not in text:
    text = "[Default Applications]\n" + text
for line in defaults:
    key = line.split("=", 1)[0]
    if f"{key}=" not in text.split("[Added Associations]", 1)[0]:
        text = text.replace("[Default Applications]\n", "[Default Applications]\n" + line + "\n", 1)
if "[Added Associations]" not in text:
    text = text.rstrip() + "\n\n[Added Associations]\n"
assoc = text.split("[Added Associations]", 1)[-1]
for line in added:
    key = line.split("=", 1)[0]
    if f"{key}=" not in assoc:
        text = text.rstrip() + "\n" + line
path.write_text(text if text.endswith("\n") else text + "\n")
PY
  fi
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
  fi
}

install_cursor_files() {
  local owner="$USER"
  local group

  group="$(id -gn "$owner")"

  sudo mkdir -p "$CURSOR_INSTALL_DIR"
  sudo install -D -m 755 "$CURSOR_DOWNLOAD" "$CURSOR_INSTALL_DIR/$CURSOR_APPIMAGE_NAME"
  # Cursor's updater replaces this AppImage in place. Root ownership would
  # block self-update, so the installing user owns /opt/cursor.
  sudo chown -R "$owner:$group" "$CURSOR_INSTALL_DIR"
  sudo chmod u+rwX "$CURSOR_INSTALL_DIR" "$CURSOR_INSTALL_DIR/$CURSOR_APPIMAGE_NAME"
  mkdir -p "$CURSOR_INSTALL_DIR/logs"
  write_cursor_launch
  CURSOR_EXTRACT_ONLY=1 "$CURSOR_LAUNCH"
  # Hyprland is not a desktop Electron auto-detects; pin gnome-libsecret
  # (same as chromium-flags.conf and Element on this machine).
  # Remove any leftover symlink first: `tee` follows /usr/local/bin/cursor ->
  # /opt/cursor/Cursor.AppImage and would overwrite the AppImage with this
  # wrapper (which is how this install previously bricked Cursor).
  sudo rm -f /usr/local/bin/cursor
  sudo tee /usr/local/bin/cursor >/dev/null <<EOF
#!/bin/bash
exec $CURSOR_LAUNCH "\$@"
EOF
  sudo chmod 755 /usr/local/bin/cursor
  sudo tee /usr/share/applications/cursor.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Cursor
Comment=The AI Code Editor (nightly)
GenericName=Text Editor
Exec=$CURSOR_LAUNCH %F
TryExec=$CURSOR_LAUNCH
Icon=cursor
Terminal=false
Type=Application
StartupNotify=false
StartupWMClass=Cursor
Categories=Development;TextEditor;IDE;
MimeType=application/x-cursor-workspace;x-scheme-handler/cursor;
Actions=new-empty-window;
Keywords=cursor;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=$CURSOR_LAUNCH --new-window %F
Icon=cursor
EOF
  sudo chmod 644 /usr/share/applications/cursor.desktop
  sudo tee /usr/share/applications/cursor-url-handler.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Cursor - URL Handler
Comment=The AI Code Editor (nightly)
Exec=$CURSOR_LAUNCH --open-url %U
TryExec=$CURSOR_LAUNCH
Icon=cursor
Terminal=false
Type=Application
NoDisplay=true
StartupNotify=true
StartupWMClass=Cursor
Categories=Utility;TextEditor;Development;IDE;
MimeType=x-scheme-handler/cursor;
Keywords=cursor;
EOF
  sudo chmod 644 /usr/share/applications/cursor-url-handler.desktop
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  cat >"$HOME/.local/bin/cursor" <<EOF
#!/bin/bash
exec $CURSOR_LAUNCH "\$@"
EOF
  chmod 755 "$HOME/.local/bin/cursor"
  cat >"$HOME/.local/share/applications/cursor.desktop" <<EOF
[Desktop Entry]
Name=Cursor
Comment=The AI Code Editor (nightly)
GenericName=Text Editor
Exec=$CURSOR_LAUNCH %F
TryExec=$CURSOR_LAUNCH
Icon=cursor
Terminal=false
Type=Application
StartupNotify=false
StartupWMClass=Cursor
Categories=Development;TextEditor;IDE;
MimeType=application/x-cursor-workspace;x-scheme-handler/cursor;
Actions=new-empty-window;
Keywords=cursor;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=$CURSOR_LAUNCH --new-window %F
Icon=cursor
EOF
  chmod 644 "$HOME/.local/share/applications/cursor.desktop"
  cat >"$HOME/.local/share/applications/cursor-url-handler.desktop" <<EOF
[Desktop Entry]
Name=Cursor - URL Handler
Comment=The AI Code Editor (nightly)
Exec=$CURSOR_LAUNCH --open-url %U
TryExec=$CURSOR_LAUNCH
Icon=cursor
Terminal=false
Type=Application
NoDisplay=true
StartupNotify=true
StartupWMClass=Cursor
Categories=Utility;TextEditor;Development;IDE;
MimeType=x-scheme-handler/cursor;
Keywords=cursor;
EOF
  chmod 644 "$HOME/.local/share/applications/cursor-url-handler.desktop"
  extract_cursor_icon
  fix_cursor_hypr_bindings
  fix_cursor_mimeapps
  rm -f "$CURSOR_DOWNLOAD" "$CURSOR_API_JSON"
}

install_cursor() {
  local file_size=0

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    FAILURES+=("download Cursor AppImage (missing required command: curl or wget)")
    record_status "FAIL" "download Cursor AppImage"
    log "Skipping Cursor install because neither curl nor wget is installed"
    return 0
  fi

  run_step "download Cursor download API JSON" download_cursor_api_json

  if [ ! -e "$CURSOR_API_JSON" ]; then
    return 0
  fi

  if ! parse_cursor_appimage_url; then
    FAILURES+=("resolve Cursor linux/x64 AppImage URL")
    record_status "FAIL" "resolve Cursor linux/x64 AppImage URL"
    return 0
  fi

  run_step "download Cursor AppImage" download_cursor_appimage

  if [ ! -e "$CURSOR_DOWNLOAD" ]; then
    return 0
  fi

  if [ ! -s "$CURSOR_DOWNLOAD" ]; then
    FAILURES+=("download Cursor AppImage (empty file)")
    record_status "FAIL" "download Cursor AppImage"
    log "Downloaded Cursor file is empty: $CURSOR_DOWNLOAD"
    return 0
  fi

  file_size="$(stat -c%s "$CURSOR_DOWNLOAD")"
  if [ "$file_size" -lt 10000000 ]; then
    FAILURES+=("download Cursor AppImage (file too small: ${file_size} bytes)")
    record_status "FAIL" "download Cursor AppImage"
    log "Downloaded Cursor file looks too small to be an AppImage: $CURSOR_DOWNLOAD ($file_size bytes)"
    return 0
  fi

  if [ "$(head -c 4 "$CURSOR_DOWNLOAD")" != $'\x7fELF' ]; then
    FAILURES+=("download Cursor AppImage (not an ELF/AppImage)")
    record_status "FAIL" "download Cursor AppImage"
    log "Downloaded Cursor file is not an ELF AppImage: $CURSOR_DOWNLOAD"
    return 0
  fi

  chmod 700 "$CURSOR_DOWNLOAD"
  log "Verified Cursor AppImage ($file_size bytes); installing to $CURSOR_INSTALL_DIR"

  run_step "install Cursor AppImage" install_cursor_files
}

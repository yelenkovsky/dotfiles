#!/usr/bin/env bash
# Install the Kokoro read-aloud tool: select text, press a hotkey, hear it.
#
#   ~/.local/share/kokoro-reader/   daemon.py + client.py (symlinks) and a Python 3.12 venv
#   ~/.local/bin/read-aloud         command for the hotkey (symlink)
#
# The Hyprland keybinding is machine-specific and lives in dotfiles-private:
#   o.bind("SUPER + ALT + R", "Read selection aloud", "<home>/.local/bin/read-aloud toggle")
#
# Needs uv, mpv and wl-clipboard. The CUDA build of torch is a ~5 GB download;
# --cpu installs the small CPU-only build (Kokoro still reads faster than real time).
#
# Usage: setup/kokoro-reader.sh [--cpu] [--remove]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$DOTFILES_DIR/kokoro-reader"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/kokoro-reader"
BIN="$HOME/.local/bin/read-aloud"

if [ "${1-}" = "--remove" ]; then
  pkill -f '[k]okoro-reader/daemon\.py' || true
  rm -rf "$APP_DIR"
  rm -f "$BIN"
  echo "Removed $APP_DIR and $BIN (the ~/.cache/huggingface model cache stays)"
  exit 0
fi

for cmd in uv mpv wl-paste notify-send; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done

mkdir -p "$APP_DIR" "$(dirname "$BIN")"
ln -sfn "$SRC/daemon.py" "$APP_DIR/daemon.py"
ln -sfn "$SRC/client.py" "$APP_DIR/client.py"
ln -sfn "$SRC/read-aloud" "$BIN"

# A system Python newer than torch's wheels would fail to resolve, so pin 3.12.
[ -x "$APP_DIR/.venv/bin/python" ] || uv venv --python 3.12 "$APP_DIR/.venv"

extra=()
if [ "${1-}" = "--cpu" ]; then
  extra=(--index-url https://download.pytorch.org/whl/cpu --extra-index-url https://pypi.org/simple --index-strategy unsafe-best-match)
fi
VIRTUAL_ENV="$APP_DIR/.venv" uv pip install "${extra[@]}" -r "$SRC/requirements.txt"

# Stop a running daemon so the next key press loads the new code.
pkill -f '[k]okoro-reader/daemon\.py' || true

echo "Installed. Select text and run: read-aloud   (the first run downloads the ~330 MB model)"

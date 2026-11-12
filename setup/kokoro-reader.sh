#!/usr/bin/env bash
# Install the Kokoro read-aloud tool: select text, press a hotkey, hear it.
#
#   ~/.local/share/kokoro-reader/   daemon.py + client.py (symlinks) and a Python 3.12 venv
#   ~/.local/bin/read-aloud         command for the hotkey (symlink)
#
# Keybindings are machine-specific and live in dotfiles-private; bind
# `read-aloud toggle|pause|prev|next|slower|faster|voice` (see read-aloud).
# While reading, the daemon is also an MPRIS player, so media keys and the
# Omarchy Media bar widget (omarchy bar put omarchy.media) control it.
#
# Needs uv, portaudio and wl-clipboard. The CUDA build of torch is a ~5 GB
# download; --cpu installs the small CPU-only build (Kokoro still reads faster
# than real time).
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

for cmd in uv wl-paste notify-send; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }
done
# Not `grep -q`: it exits at the first match, and under pipefail ldconfig's SIGPIPE fails the test.
ldconfig -p | grep libportaudio >/dev/null || { echo "Missing portaudio (pacman -S portaudio)" >&2; exit 1; }

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

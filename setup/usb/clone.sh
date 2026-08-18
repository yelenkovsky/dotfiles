#!/usr/bin/env bash
# Clone https://github.com/yelenkovsky/usb for local use.
# The public copy of its scripts lives in this directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
USB_DIR="${USB_DIR:-$HOME/.local/src/usb}"
USB_REPO_URL="${USB_REPO_URL:-https://github.com/yelenkovsky/usb.git}"
USB_SSH_URL="${USB_SSH_URL:-git@github.com:yelenkovsky/usb.git}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--ssh]

Clone https://github.com/yelenkovsky/usb into:
  $USB_DIR

Scripts that belong in the public dotfiles stay in:
  $SCRIPT_DIR

Options:
  --ssh   Clone with SSH instead of HTTPS
  -h      Show this help text
EOF
}

case "${1:-}" in
  --ssh)
    USB_REPO_URL="$USB_SSH_URL"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

if [ -d "$USB_DIR/.git" ]; then
  echo "usb repo already present: $USB_DIR"
  git -C "$USB_DIR" remote -v
  git -C "$USB_DIR" pull --ff-only
  exit 0
fi

if [ -e "$USB_DIR" ]; then
  echo "Error: $USB_DIR exists but is not a git clone." >&2
  exit 1
fi

echo "Cloning $USB_REPO_URL -> $USB_DIR"
mkdir -p "$(dirname "$USB_DIR")"
git clone "$USB_REPO_URL" "$USB_DIR"
echo "Done. Run $SCRIPT_DIR/install.sh to apply it."

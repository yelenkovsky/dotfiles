#!/usr/bin/env bash
# Clone the private companion repo into ./usb (gitignored).
# https://github.com/yelenkovsky/usb stays out of the public tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
USB_DIR="${USB_DIR:-$DOTFILES_DIR/usb}"
USB_REPO_URL="${USB_REPO_URL:-https://github.com/yelenkovsky/usb.git}"
USB_SSH_URL="${USB_SSH_URL:-git@github.com:yelenkovsky/usb.git}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--ssh]

Clone https://github.com/yelenkovsky/usb into:
  $USB_DIR

The directory is gitignored so private files are not committed here.

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
git clone "$USB_REPO_URL" "$USB_DIR"
echo "Done. Re-run ./install.sh to apply the usb overlay."

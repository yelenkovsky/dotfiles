#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="$HOME/dotfiles-backup-usb-$(date +%Y%m%d_%H%M%S)"

create_symlink() {
  local source="$1"
  local target="$2"

  mkdir -p "$(dirname "$target")"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "Backing up existing: $target"
    mkdir -p "$BACKUP_DIR/$(dirname "$target")"
    mv "$target" "$BACKUP_DIR/$target"
  fi

  if [ -L "$target" ]; then
    rm "$target"
  fi

  echo "Linking: $target -> $source"
  ln -s "$source" "$target"
}

should_skip_path() {
  local rel="$1"
  case "$rel" in
    .git|.git/*|README.md|LICENSE|LICENSE.md|install.sh|secure-install.sh|.gitignore|.github|.github/*)
      return 0
      ;;
  esac
  return 1
}

usb_dir=""
for candidate in \
  "$HOME/.local/src/usb" \
  "$DOTFILES_DIR/../usb" \
  "$HOME/usb"
do
  if [ -d "$candidate" ]; then
    usb_dir="$(cd "$candidate" && pwd)"
    break
  fi
done

if [ -z "$usb_dir" ]; then
  echo "usb repo not found. Clone it first:"
  echo "  $SCRIPT_DIR/clone.sh"
  exit 1
fi

if [ -x "$usb_dir/install.sh" ]; then
  echo "Running $usb_dir/install.sh"
  "$usb_dir/install.sh"
  exit 0
fi

while IFS= read -r -d '' source; do
  rel="${source#"$usb_dir"/}"
  if should_skip_path "$rel"; then
    continue
  fi
  create_symlink "$source" "$HOME/$rel"
done < <(find "$usb_dir" \( -path "$usb_dir/.git" -o -path "$usb_dir/.github" \) -prune -o \( -type f -o -type l \) -print0)

echo "Done."
if [ -d "$BACKUP_DIR" ]; then
  echo "Backups: $BACKUP_DIR"
fi

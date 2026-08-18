#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    README.md|LICENSE|LICENSE.md|install.sh|clone.sh|.gitignore)
      return 0
      ;;
  esac
  return 1
}

echo "Installing USB setup from $SCRIPT_DIR"

while IFS= read -r -d '' source; do
  rel="${source#"$SCRIPT_DIR"/}"
  if should_skip_path "$rel"; then
    continue
  fi
  create_symlink "$source" "$HOME/$rel"
done < <(find "$SCRIPT_DIR" \( -type f -o -type l \) -print0)

echo "Done."
if [ -d "$BACKUP_DIR" ]; then
  echo "Backups: $BACKUP_DIR"
fi

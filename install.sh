#!/bin/bash
# Link this repository's configs into $HOME.
# Clone anywhere; paths are resolved from this script's directory.

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/dotfiles-backup-$(date +%Y%m%d_%H%M%S)"

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

link_if_present() {
    local rel="$1"
    local target="$2"

    if [ -e "$DOTFILES_DIR/$rel" ]; then
        create_symlink "$DOTFILES_DIR/$rel" "$target"
    fi
}

echo "Installing public dotfiles from $DOTFILES_DIR"

echo ""
echo "Editor and git"
link_if_present ".vimrc" "$HOME/.vimrc"
link_if_present ".gitconfig" "$HOME/.gitconfig"

echo ""
echo "Cursor"
link_if_present ".config/Cursor/settings.json" "$HOME/.config/Cursor/User/settings.json"
link_if_present ".config/Cursor/keybindings.json" "$HOME/.config/Cursor/User/keybindings.json"
link_if_present ".config/Cursor/snippets" "$HOME/.config/Cursor/User/snippets"
link_if_present ".cursor/skills/add-secure-install-app" "$HOME/.cursor/skills/add-secure-install-app"
link_if_present ".cursor/skills/add-secure-install-app" "$HOME/.agents/skills/add-secure-install-app"
if [ -f "$DOTFILES_DIR/.config/Cursor/extensions.txt" ]; then
    echo "Extension list found (install from Cursor marketplace as needed)"
fi

echo ""
echo "Shell, terminal, prompt"
link_if_present ".config/fish" "$HOME/.config/fish"
link_if_present ".config/omf" "$HOME/.config/omf"
link_if_present ".config/starship.toml" "$HOME/.config/starship.toml"
link_if_present ".config/eza" "$HOME/.config/eza"
link_if_present ".config/ghostty" "$HOME/.config/ghostty"

echo ""
echo "GitHub CLI config (hosts.yml is not in this repo)"
if [ -f "$DOTFILES_DIR/.config/gh/config.yml" ]; then
    mkdir -p "$HOME/.config/gh"
    if [ -L "$HOME/.config/gh" ]; then
        rm "$HOME/.config/gh"
        mkdir -p "$HOME/.config/gh"
    fi
    create_symlink "$DOTFILES_DIR/.config/gh/config.yml" "$HOME/.config/gh/config.yml"
fi

echo ""
echo "Done."
if [ -d "$BACKUP_DIR" ]; then
    echo "Backups: $BACKUP_DIR"
fi

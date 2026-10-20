# shellcheck shell=bash
register_package fonts 40 "Fonts and prompt" install_fonts

# shellcheck disable=SC2034  # passed by name to install_package_group (local -n)
PACMAN_FONT_PACKAGES=(
  starship
  ttf-firacode-nerd
  ttf-hack-nerd
  ttf-meslo-nerd
  ttf-nerd-fonts-symbols-mono
)

install_fonts() {
  install_package_group pacman "Fonts and prompt" PACMAN_FONT_PACKAGES
}

register_package fonts 40 "Fonts and prompt" install_fonts

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

register_package core 10 "Core pacman packages" install_core

PACMAN_CORE_PACKAGES=(
  ghostty
  fish
  vim
  pkgfile
  wl-clipboard
)

install_core() {
  install_package_group pacman "Core packages" PACMAN_CORE_PACKAGES
}

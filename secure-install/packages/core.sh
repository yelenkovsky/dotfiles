# shellcheck shell=bash
register_package core 10 "Core pacman packages" install_core

# shellcheck disable=SC2034  # passed by name to install_package_group (local -n)
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

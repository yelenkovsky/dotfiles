# shellcheck shell=bash
register_package util 30 "Utility pacman packages" install_util

# shellcheck disable=SC2034  # passed by name to install_package_group (local -n)
PACMAN_UTIL_PACKAGES=(
  cpupower
  eza
  fuse2
  fzf
  gnupg
  pv
  sshfs
  stow
  tree
  unzip
  viu
  wget
  power-profiles-daemon
)

install_util() {
  install_package_group pacman "Utility packages" PACMAN_UTIL_PACKAGES
}

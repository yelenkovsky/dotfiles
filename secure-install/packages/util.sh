register_package util 30 "Utility pacman packages" install_util

PACMAN_UTIL_PACKAGES=(
  cpupower
  eza
  fuse2
  fzf
  gnupg
  pv
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

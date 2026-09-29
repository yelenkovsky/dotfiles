register_package gaming 50 "Gaming packages" install_gaming

PACMAN_GAMING_PACKAGES=(
  steam
  gamemode
  lib32-gamemode
  mangohud
  lib32-mangohud
  nvidia-prime
)

AUR_GAMING_PACKAGES=(
  mangojuice
  proton-cachyos-slr
)

install_gaming() {
  install_package_group pacman "Gaming packages" PACMAN_GAMING_PACKAGES
  install_package_group yay "Gaming AUR packages" AUR_GAMING_PACKAGES
}

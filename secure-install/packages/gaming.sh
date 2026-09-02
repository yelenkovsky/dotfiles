register_package gaming 50 "Gaming pacman packages" install_gaming

PACMAN_GAMING_PACKAGES=(
  steam
  gamemode
  lib32-gamemode
  mangohud
  lib32-mangohud
)

install_gaming() {
  install_package_group pacman "Gaming packages" PACMAN_GAMING_PACKAGES
}

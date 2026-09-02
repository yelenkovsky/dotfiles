register_package desktop 20 "Desktop pacman packages" install_desktop

PACMAN_DESKTOP_PACKAGES=(
  file-roller
  flameshot
  gparted
  # kdeconnect
  # kleopatra
  kompare
  krename
  krusader
  qbittorrent
  remmina
  unrar
  vlc
  vlc-plugins-all
)

install_desktop() {
  install_package_group pacman "Desktop packages" PACMAN_DESKTOP_PACKAGES
}

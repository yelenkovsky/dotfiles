register_package desktop 20 "Desktop pacman packages" install_desktop

PACMAN_DESKTOP_PACKAGES=(
  file-roller
  flameshot
  gparted
  # kdeconnect
  # kleopatra
  7zip
  arj
  ark
  kde-cli-tools
  kdiff3
  keditbookmarks
  kio-extras
  kompare
  konsole
  krename
  krusader
  lhasa
  qbittorrent
  remmina
  unace
  unarj
  unrar
  vlc
  vlc-plugins-all
)

install_desktop() {
  install_package_group pacman "Desktop packages" PACMAN_DESKTOP_PACKAGES
}

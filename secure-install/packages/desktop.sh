# shellcheck shell=bash
register_package desktop 20 "Desktop pacman packages" install_desktop

# shellcheck disable=SC2034  # passed by name to install_package_group (local -n)
PACMAN_DESKTOP_PACKAGES=(
  file-roller
  flameshot
  gparted
  # kdeconnect
  # kleopatra
  7zip
  arj
  ark
  discord
  dpkg
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
  yazi
  perl-image-exiftool # exiftool, for Yazi's "Show EXIF"
  resvg
  chafa
)

install_desktop() {
  install_package_group pacman "Desktop packages" PACMAN_DESKTOP_PACKAGES
}

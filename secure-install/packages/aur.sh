register_package aur 60 "AUR packages" install_aur

AUR_PACKAGES=(
  masterpdfeditor-free
  mangojuice
  proton-cachyos-slr
  optimus-manager-git
  ttf-ms-fonts
  ttf-vista-fonts
)

install_aur() {
  install_package_group yay "AUR packages" AUR_PACKAGES
}

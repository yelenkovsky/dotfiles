# shellcheck shell=bash
register_package aur 60 "AUR packages" install_aur

# shellcheck disable=SC2034  # passed by name to install_package_group (local -n)
AUR_PACKAGES=(
  pbpctrl
  optimus-manager-git
  ttf-ms-fonts
  ttf-vista-fonts
)

install_aur() {
  install_package_group yay "AUR packages" AUR_PACKAGES
}

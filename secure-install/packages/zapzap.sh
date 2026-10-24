# shellcheck shell=bash
register_package zapzap 410 "ZapZap (WhatsApp, Flathub)" install_zapzap

ZAPZAP_APP_ID="com.rtosta.zapzap"
ZAPZAP_FLATHUB_REPO="https://dl.flathub.org/repo/flathub.flatpakrepo"
ZAPZAP_HYPR_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/autostart.lua"
ZAPZAP_AUTOSTART_LINE="o.launch_on_start(\"flatpak run $ZAPZAP_APP_ID\")"

# The GitHub releases publish no checksums. Flathub builds from the author's
# git source, and flatpak checks every OSTree commit against the GPG key that
# ships inside the .flatpakrepo file, so that is the verified route.
add_flathub_remote() {
  flatpak remote-add --user --if-not-exists flathub "$ZAPZAP_FLATHUB_REPO"
}

install_zapzap_flatpak() {
  flatpak install --user --noninteractive --or-update flathub "$ZAPZAP_APP_ID"
}

# ZapZap's own "Start with system" does nothing in the Flatpak on Hyprland:
# the portal there has no Background interface (rafatosta/zapzap#988). Start
# it from Hyprland's autostart instead. "Start in background" in ZapZap's
# settings still works and keeps the window hidden at login.
add_zapzap_hypr_autostart() {
  if [ ! -f "$ZAPZAP_HYPR_AUTOSTART" ]; then
    log "No $ZAPZAP_HYPR_AUTOSTART; add the ZapZap autostart line by hand"
    return 1
  fi
  if grep -qF "$ZAPZAP_AUTOSTART_LINE" "$ZAPZAP_HYPR_AUTOSTART"; then
    return 0
  fi
  printf '\n-- ZapZap (secure-install); its own autostart toggle fails in the Flatpak.\n%s\n' \
    "$ZAPZAP_AUTOSTART_LINE" >>"$ZAPZAP_HYPR_AUTOSTART"
}

install_zapzap() {
  # Flatseal edits Flatpak permission overrides (e.g. to narrow ZapZap's
  # folders). The Arch package is signed by the Arch keys and needs no
  # GNOME Flatpak runtime.
  local -a flatpak_command=(sudo pacman -S --needed flatpak flatseal)

  [ "$CHECK_MODE" = true ] && return 0
  [ "$ASSUME_YES" = true ] && flatpak_command+=(--noconfirm)

  run_step "install flatpak and Flatseal" "${flatpak_command[@]}"
  run_step "add Flathub remote (user)" add_flathub_remote
  run_step "install ZapZap from Flathub" install_zapzap_flatpak
  run_step "add ZapZap to Hyprland autostart" add_zapzap_hypr_autostart
}

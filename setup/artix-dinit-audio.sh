#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
PIPEWIRE_PULSE_SERVICE="$HOME/.config/dinit.d/pipewire-pulse"
USER_DINIT_SERVICE_DIR="$HOME/.config/dinit.d"

PACKAGES=(
  alsa-utils
  pavucontrol
  pipewire
  pipewire-alsa
  pipewire-audio
  pipewire-jack
  pipewire-pulse
  pipewire-dinit
  sof-firmware
  wireplumber
  wireplumber-dinit
)

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--reinstall]

Set up audio on Artix with dinit using PipeWire, WirePlumber, and pipewire-pulse.

Options:
  --reinstall  Reinstall audio packages instead of only installing missing ones
  -h, --help   Show this help text
EOF
}

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

install_packages() {
  local reinstall="$1"

  if [ "$reinstall" = true ]; then
    echo "Reinstalling audio packages..."
    sudo pacman -S --noconfirm "${PACKAGES[@]}"
  else
    echo "Installing missing audio packages..."
    sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"
  fi
}

write_pipewire_pulse_service() {
  echo "Writing dinit user service: $PIPEWIRE_PULSE_SERVICE"
  mkdir -p "$(dirname "$PIPEWIRE_PULSE_SERVICE")"

  cat >"$PIPEWIRE_PULSE_SERVICE" <<'EOF'
type            = process
command         = /usr/bin/pipewire-pulse
depends-on      = pipewire
log-type        = buffer
EOF
}

user_service_exists() {
  local service_name="$1"
  local service_path

  for service_path in \
    "$USER_DINIT_SERVICE_DIR/$service_name" \
    "/etc/dinit.d/user/$service_name" \
    "/usr/lib/dinit.d/user/$service_name"
  do
    if [ -f "$service_path" ]; then
      return 0
    fi
  done

  return 1
}

require_user_service() {
  local service_name="$1"

  if ! user_service_exists "$service_name"; then
    echo "Missing dinit user service definition: $service_name" >&2
    exit 1
  fi
}

require_user_dinit() {
  if dinitctl --user list >/dev/null 2>&1; then
    return 0
  fi

  echo >&2
  echo "User dinit is not reachable, so audio services were not enabled." >&2
  echo "Log into your desktop session and rerun: $SCRIPT_NAME" >&2
  exit 1
}

start_user_service() {
  local service_name="$1"

  echo "Enabling user service: $service_name"
  dinitctl --user enable "$service_name"

  echo "Starting user service: $service_name"
  dinitctl --user start "$service_name"
}

verify_audio() {
  echo
  echo "Verifying audio stack..."

  if command -v wpctl >/dev/null 2>&1; then
    wpctl status
    echo
  fi

  if command -v pactl >/dev/null 2>&1; then
    pactl info
  fi
}

main() {
  local reinstall=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reinstall)
        reinstall=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  require_command sudo
  require_command pacman
  require_command dinitctl

  install_packages "$reinstall"
  write_pipewire_pulse_service
  require_user_dinit
  require_user_service pipewire
  require_user_service wireplumber
  require_user_service pipewire-pulse

  start_user_service pipewire
  start_user_service wireplumber
  start_user_service pipewire-pulse

  echo
  echo "Audio setup complete."

  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    echo "Run this from your logged-in desktop session if you want immediate verification."
    exit 0
  fi

  verify_audio
}

main "$@"

#!/usr/bin/env bash
# Install a systemd user timer that runs `secure-install.sh --check --notify`
# every day at 18:00 UTC. It only reports which apps have a newer release
# (desktop notification + ~/.local/state/dotfiles-installer/updates-available.txt);
# it never installs anything and needs no sudo.
#
# Usage: setup/update-check-timer.sh [--remove]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
NAME="secure-install-check"

if [ "${1-}" = "--remove" ]; then
  systemctl --user disable --now "$NAME.timer" 2>/dev/null || true
  rm -f "$UNIT_DIR/$NAME.service" "$UNIT_DIR/$NAME.timer"
  systemctl --user daemon-reload
  echo "Removed $NAME.timer"
  exit 0
fi

mkdir -p "$UNIT_DIR"

# Generated rather than linked: ExecStart needs this clone's absolute path.
cat >"$UNIT_DIR/$NAME.service" <<EOF
[Unit]
Description=Check secure-install apps for new releases

[Service]
Type=oneshot
ExecStart=$DOTFILES_DIR/secure-install.sh --check --notify
Nice=10
EOF

# Persistent catches up after boot when the machine was off at 18:00.
cat >"$UNIT_DIR/$NAME.timer" <<EOF
[Unit]
Description=Daily check for secure-install app updates

[Timer]
OnCalendar=*-*-* 18:00:00 UTC
Persistent=true
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "$NAME.timer"
systemctl --user list-timers "$NAME.timer" --no-pager

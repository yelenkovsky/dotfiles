#!/usr/bin/env bash

set -euo pipefail

ORIGINAL_ARGS=("$@")

DRY_RUN=0
TARGET_USER="${SUDO_USER:-${USER:-}}"
DUMPCAP_BIN="/usr/bin/dumpcap"
WIRESHARK_GROUP="wireshark"

usage() {
  cat <<'EOF'
Set up Wireshark packet capture permissions for a local user.

Usage:
  setup-wireshark.sh [options]

Options:
  --user USER   Add USER to the wireshark group.
  --dry-run     Show what would be changed without writing anything.
  --help        Show this help text.

Examples:
  ./setup-wireshark.sh
  ./setup-wireshark.sh --user xbloc
  ./setup-wireshark.sh --dry-run

Notes:
  - This script does not install Wireshark; it configures capture permissions.
  - You must log out and back in after the group change takes effect.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

group_exists() {
  getent group "$WIRESHARK_GROUP" >/dev/null 2>&1
}

user_exists() {
  id "$1" >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      shift
      [[ $# -gt 0 ]] || die "--user requires an argument"
      TARGET_USER="$1"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown option: $1"
      ;;
  esac
  shift
done

need_cmd getent
need_cmd id
need_cmd usermod
need_cmd chgrp
need_cmd chmod
need_cmd setcap
need_cmd getcap

[[ -n "$TARGET_USER" ]] || die "Could not determine target user. Re-run with --user USER."
user_exists "$TARGET_USER" || die "User does not exist: $TARGET_USER"
[[ -x "$DUMPCAP_BIN" ]] || die "dumpcap not found at $DUMPCAP_BIN. Install Wireshark first."

if [[ "${EUID}" -ne 0 && "$DRY_RUN" -ne 1 ]]; then
  exec sudo -- "$0" "${ORIGINAL_ARGS[@]}"
fi

if ! group_exists; then
  run groupadd "$WIRESHARK_GROUP"
  printf 'Created group: %s\n' "$WIRESHARK_GROUP"
else
  printf 'Group already exists: %s\n' "$WIRESHARK_GROUP"
fi

run chgrp "$WIRESHARK_GROUP" "$DUMPCAP_BIN"
run chmod 0750 "$DUMPCAP_BIN"
run setcap cap_net_raw,cap_net_admin=eip "$DUMPCAP_BIN"
run usermod -aG "$WIRESHARK_GROUP" "$TARGET_USER"

printf 'Configured: %s\n' "$DUMPCAP_BIN"
printf 'Capture capabilities: '
if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '[dry-run] getcap %s\n' "$DUMPCAP_BIN"
else
  getcap "$DUMPCAP_BIN"
fi

printf 'Added user to group: %s -> %s\n' "$TARGET_USER" "$WIRESHARK_GROUP"
printf 'Log out and back in before starting Wireshark.\n'

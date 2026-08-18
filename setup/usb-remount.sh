#!/usr/bin/env bash
# Remount a USB drive at /mnt/usb with user write permissions.

set -euo pipefail

ORIGINAL_ARGS=("$@")
DEVICE="/dev/sda"
MOUNT_POINT="/mnt/usb"

usage() {
  cat <<'EOF'
Remount a USB drive at /mnt/usb with your user permissions.

Usage:
  usb-remount [device]
  usb-remount --help

Examples:
  ./setup/usb-remount.sh
  ./setup/usb-remount.sh /dev/sdb

Notes:
  - Default device is /dev/sda (partition 1 is mounted).
  - Does not format or erase data.
  - Use this after a reboot or automount that left the drive unwritable.
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

block_name() {
  local path="$1"
  basename "$path"
}

is_removable() {
  local name="$1"
  local removable_file="/sys/block/${name}/removable"

  [[ -f "$removable_file" ]] || return 1
  [[ "$(cat "$removable_file")" == "1" ]]
}

device_holds_root() {
  local device="$1"
  local root_source

  root_source="$(findmnt -n -o SOURCE / || true)"
  [[ -n "$root_source" ]] || return 1
  [[ "$root_source" == "$device"* ]]
}

unmount_if_mounted() {
  local target="$1"

  if findmnt -n "$target" >/dev/null 2>&1 || findmnt -n -S "$target" >/dev/null 2>&1; then
    umount "$target"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      die "Unknown option: $1"
      ;;
    *)
      DEVICE="$1"
      shift
      break
      ;;
  esac
  shift
done

[[ $# -eq 0 ]] || die "Unexpected extra arguments: $*"

need_cmd sudo
need_cmd findmnt
need_cmd lsblk
need_cmd mount
need_cmd umount
need_cmd mkdir
need_cmd id

[[ "$DEVICE" == /dev/* ]] || die "Device must be a /dev path, got: $DEVICE"
[[ -b "$DEVICE" ]] || die "Block device not found: $DEVICE"
[[ "$DEVICE" != *[[:digit:]] ]] || die "Pass the whole disk (e.g. /dev/sda), not a partition: $DEVICE"

DISK_NAME="$(block_name "$DEVICE")"
is_removable "$DISK_NAME" || die "$DEVICE is not marked removable. Refusing to remount."
device_holds_root "$DEVICE" && die "$DEVICE appears to hold the root filesystem. Refusing to remount."

PARTITION="${DEVICE}1"
[[ -b "$PARTITION" ]] || die "Partition not found: $PARTITION"

TARGET_USER="${SUDO_USER:-${USER:-}}"
[[ -n "$TARGET_USER" ]] || die "Could not determine the user that should own the mount."
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -- "$0" "${ORIGINAL_ARGS[@]}"
fi

printf 'Remounting %s at %s with user permissions...\n' "$PARTITION" "$MOUNT_POINT"

unmount_if_mounted "$MOUNT_POINT"
unmount_if_mounted "$PARTITION"

mkdir -p "$MOUNT_POINT"
mount -t vfat "$PARTITION" "$MOUNT_POINT" -o "uid=${TARGET_UID},gid=${TARGET_GID},umask=0000"

printf 'Done. You can now write to %s\n' "$MOUNT_POINT"
ls -la "$MOUNT_POINT"

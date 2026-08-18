#!/usr/bin/env bash
# Format a USB pendrive as a single FAT32 partition and mount it at /mnt/usb.

set -euo pipefail

ORIGINAL_ARGS=("$@")
DEVICE="/dev/sda"
MOUNT_POINT="/mnt/usb"
LABEL="USB"

usage() {
  cat <<'EOF'
Format a USB drive as a single FAT32 partition and mount it at /mnt/usb.

Usage:
  usb [device]
  usb --help

Examples:
  ./setup/usb.sh
  ./setup/usb.sh /dev/sdb

Notes:
  - Default device is /dev/sda.
  - The target must be a removable disk and must not hold the root filesystem.
  - This erases all data on the target device.
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
need_cmd parted
need_cmd mkfs.vfat
need_cmd mount
need_cmd umount
need_cmd mkdir

[[ "$DEVICE" == /dev/* ]] || die "Device must be a /dev path, got: $DEVICE"
[[ -b "$DEVICE" ]] || die "Block device not found: $DEVICE"
[[ "$DEVICE" != *[[:digit:]] ]] || die "Pass the whole disk (e.g. /dev/sda), not a partition: $DEVICE"

DISK_NAME="$(block_name "$DEVICE")"
is_removable "$DISK_NAME" || die "$DEVICE is not marked removable. Refusing to format."
device_holds_root "$DEVICE" && die "$DEVICE appears to hold the root filesystem. Refusing to format."

TARGET_USER="${SUDO_USER:-${USER:-}}"
[[ -n "$TARGET_USER" ]] || die "Could not determine the user that should own the mount."
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -- "$0" "${ORIGINAL_ARGS[@]}"
fi

printf '=== Formatting %s USB pendrive ===\n' "$DEVICE"
printf 'WARNING: This will erase all data on %s!\n' "$DEVICE"
printf '\n'
lsblk -o NAME,SIZE,TYPE,TRAN,RM,MOUNTPOINT "$DEVICE"
printf '\n'
read -r -p "Press ENTER to continue or Ctrl+C to cancel..."

printf 'Step 1: Unmounting partitions...\n'
mapfile -t MOUNTED_PARTS < <(lsblk -ln -o NAME,MOUNTPOINT "$DEVICE" | awk '$2 != "" { print "/dev/" $1 }')
for part in "${MOUNTED_PARTS[@]+"${MOUNTED_PARTS[@]}"}"; do
  umount "$part" || true
done

printf 'Step 2: Creating new partition table...\n'
parted "$DEVICE" --script mklabel msdos
parted "$DEVICE" --script mkpart primary fat32 1MiB 100%
parted "$DEVICE" --script set 1 boot on

sleep 2

PARTITION="${DEVICE}1"
[[ -b "$PARTITION" ]] || die "Partition did not appear: $PARTITION"

printf 'Step 3: Formatting as FAT32...\n'
mkfs.vfat -F 32 -n "$LABEL" "$PARTITION"

printf 'Step 4: Mounting the drive...\n'
mkdir -p "$MOUNT_POINT"
mount -t vfat "$PARTITION" "$MOUNT_POINT" -o "uid=${TARGET_UID},gid=${TARGET_GID},umask=0000"

printf '\n'
printf '=== Setup Complete! ===\n'
printf 'USB pendrive is now formatted and ready to use\n'
printf 'Mount point: %s\n' "$MOUNT_POINT"
printf '\n'
printf 'To safely eject the drive later, run:\n'
printf '  sudo umount %s\n' "$MOUNT_POINT"
printf '\n'

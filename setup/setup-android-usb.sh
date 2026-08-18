#!/usr/bin/env bash
# Install Android USB udev rules from M0Rf30/android-udev-rules so adb,
# fastboot, and scrcpy work without root. Works on Artix/dinit (no systemd).

set -euo pipefail

ORIGINAL_ARGS=("$@")

DRY_RUN=0
PREFER_PACKAGE=1
TARGET_USER="${SUDO_USER:-${USER:-}}"
ADBUSERS_GROUP="adbusers"
UDEV_RULES_DEST="/etc/udev/rules.d/51-android.rules"
UPSTREAM_REPO_URL="https://github.com/M0Rf30/android-udev-rules.git"

usage() {
  cat <<'EOF'
Set up Android USB access (adb / fastboot / scrcpy) for a local user.

Uses the Arch/Artix android-udev package when available, otherwise clones
https://github.com/M0Rf30/android-udev-rules and installs 51-android.rules.

Usage:
  setup-android-usb.sh [options]

Options:
  --user USER     Add USER to the adbusers group (default: current user).
  --from-repo     Skip the distro package and always use the upstream git repo.
  --dry-run       Show what would be changed without writing anything.
  --help          Show this help text.

Examples:
  ./setup-android-usb.sh
  ./setup-android-usb.sh --user xbloc
  ./setup-android-usb.sh --from-repo --dry-run

Notes:
  - Log out (or reboot) after the group change so adbusers takes effect.
  - Enable USB debugging on the phone, then replug the cable.
  - This script does not install scrcpy or android-tools; add those via
    ./secure-install.sh or pacman.
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
  getent group "$ADBUSERS_GROUP" >/dev/null 2>&1
}

user_exists() {
  id "$1" >/dev/null 2>&1
}

user_home() {
  getent passwd "$1" | cut -d: -f6
}

package_available() {
  pacman -Si android-udev >/dev/null 2>&1
}

package_installed() {
  pacman -Q android-udev >/dev/null 2>&1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      shift
      [[ $# -gt 0 ]] || die "--user requires an argument"
      TARGET_USER="$1"
      ;;
    --from-repo)
      PREFER_PACKAGE=0
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

[[ -n "$TARGET_USER" ]] || die "Could not determine target user. Re-run with --user USER."
user_exists "$TARGET_USER" || die "User does not exist: $TARGET_USER"

TARGET_HOME="$(user_home "$TARGET_USER")"
[[ -n "$TARGET_HOME" ]] || die "Could not resolve home directory for $TARGET_USER"
STATE_DIR="${TARGET_HOME}/.local/state/dotfiles-installer"
CLONE_DIR="$STATE_DIR/android-udev-rules"

if [[ "$DRY_RUN" -ne 1 ]]; then
  need_cmd usermod
  need_cmd udevadm
fi

if [[ "${EUID}" -ne 0 && "$DRY_RUN" -ne 1 ]]; then
  exec sudo -- "$0" "${ORIGINAL_ARGS[@]}"
fi

ensure_adbusers_group() {
  if group_exists; then
    printf 'Group already exists: %s\n' "$ADBUSERS_GROUP"
    return 0
  fi
  run groupadd -f "$ADBUSERS_GROUP"
  printf 'Created group: %s\n' "$ADBUSERS_GROUP"
}

install_from_package() {
  printf 'Installing distro package: android-udev\n'
  run pacman -S --needed --noconfirm android-udev
}

install_from_repo() {
  need_cmd git
  printf 'Using upstream USB udev repo: %s\n' "$UPSTREAM_REPO_URL"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] git clone --depth=1 %s %s\n' "$UPSTREAM_REPO_URL" "$CLONE_DIR"
    printf '[dry-run] ln -sf %s/51-android.rules %s\n' "$CLONE_DIR" "$UDEV_RULES_DEST"
    printf '[dry-run] chmod a+r %s\n' "$UDEV_RULES_DEST"
    return 0
  fi

  mkdir -p "$STATE_DIR"
  if [[ -d "$CLONE_DIR/.git" ]]; then
    git -C "$CLONE_DIR" pull --ff-only
  else
    rm -rf "$CLONE_DIR"
    git clone --depth=1 "$UPSTREAM_REPO_URL" "$CLONE_DIR"
  fi

  if [[ "${EUID}" -eq 0 && "$TARGET_USER" != "root" ]]; then
    chown -R "$TARGET_USER:$TARGET_USER" "$CLONE_DIR"
  fi

  [[ -f "$CLONE_DIR/51-android.rules" ]] || die "Clone is missing 51-android.rules"

  mkdir -p /etc/udev/rules.d
  ln -sfn "$CLONE_DIR/51-android.rules" "$UDEV_RULES_DEST"
  chmod a+r "$CLONE_DIR/51-android.rules"
  printf 'Linked: %s -> %s\n' "$UDEV_RULES_DEST" "$CLONE_DIR/51-android.rules"
}

ensure_adbusers_group

if [[ "$PREFER_PACKAGE" -eq 1 ]] && command -v pacman >/dev/null 2>&1 && package_available; then
  if package_installed; then
    printf 'Package already installed: android-udev\n'
  else
    install_from_package
  fi
else
  if [[ "$PREFER_PACKAGE" -eq 1 ]]; then
    printf 'android-udev package not available; cloning upstream repo\n'
  fi
  install_from_repo
fi

run usermod -aG "$ADBUSERS_GROUP" "$TARGET_USER"
printf 'Added user to group: %s -> %s\n' "$TARGET_USER" "$ADBUSERS_GROUP"

run udevadm control --reload-rules
run udevadm trigger
printf 'Reloaded udev rules (no systemd udevd restart; Artix/dinit safe)\n'

if command -v adb >/dev/null 2>&1; then
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run] adb kill-server\n'
  else
    adb kill-server >/dev/null 2>&1 || true
  fi
fi

printf '\nReplug the Android device, then run: adb devices\n'
printf 'Log out and back in so the adbusers group applies.\n'

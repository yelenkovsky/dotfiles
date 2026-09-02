#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-installer"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$STATE_DIR/install-$TIMESTAMP.log"
STATUS_FILE="$STATE_DIR/install-$TIMESTAMP.status"

DRY_RUN=false
STOP_ON_ERROR=false
ASSUME_YES=false
SKIP_PACKAGES=()

# shellcheck source=secure-install/lib.sh
source "$SCRIPT_DIR/secure-install/lib.sh"
load_secure_install_packages "$SCRIPT_DIR/secure-install/packages"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options] [package ...]

Install bootstrap packages one at a time with logs.
With no package names, install everything (in bootstrap order).

Options:
  --dry-run        Print what would be installed without making changes
  --stop-on-error  Exit on the first failed step
  --only NAME ...  Install only these packages
  --skip NAME ...  Skip these packages
  --list           List package names
  --yes            Pass --noconfirm to pacman/yay and --yes to OMF
  -h, --help       Show this help text

Examples:
  $SCRIPT_NAME --yes
  $SCRIPT_NAME remnote
  $SCRIPT_NAME desktop aur
  $SCRIPT_NAME --only remnote cursor
  $SCRIPT_NAME --skip remnote slack

Logs:
  Detailed log:  $LOG_FILE
  Step summary:  $STATUS_FILE
EOF
}

unknown_package() {
  echo "Unknown package: $1" >&2
  echo "See $SCRIPT_NAME --list" >&2
  exit 1
}

validate_package_names() {
  local name

  for name in "$@"; do
    if ! package_exists "$name"; then
      unknown_package "$name"
    fi
  done
}

selected_packages() {
  local -a allow=("$@")
  local -A skip_set=()
  local -A allow_set=()
  local name id

  for name in "${SKIP_PACKAGES[@]}"; do
    skip_set["$name"]=1
  done

  if [ "${#allow[@]}" -eq 0 ]; then
    while IFS= read -r id; do
      [ -n "${skip_set[$id]+x}" ] && continue
      printf '%s\n' "$id"
    done < <(sorted_package_ids)
    return 0
  fi

  for name in "${allow[@]}"; do
    allow_set["$name"]=1
  done

  while IFS= read -r id; do
    [ -n "${allow_set[$id]+x}" ] || continue
    [ -n "${skip_set[$id]+x}" ] && continue
    printf '%s\n' "$id"
  done < <(sorted_package_ids)
}

main() {
  local used_only_flag=false
  local -a only_packages=()
  local -a positional_packages=()
  local -a allow_packages=()
  local -a selected=()
  local id

  SKIP_PACKAGES=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --stop-on-error)
        STOP_ON_ERROR=true
        shift
        ;;
      --yes)
        ASSUME_YES=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --list)
        list_packages
        exit 0
        ;;
      --only)
        used_only_flag=true
        shift
        if [ "$#" -eq 0 ] || [[ "$1" == --* ]]; then
          echo "--only requires at least one package name" >&2
          echo "See $SCRIPT_NAME --list" >&2
          exit 1
        fi
        while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do
          only_packages+=("$1")
          shift
        done
        ;;
      --skip)
        shift
        if [ "$#" -eq 0 ] || [[ "$1" == --* ]]; then
          echo "--skip requires at least one package name" >&2
          echo "See $SCRIPT_NAME --list" >&2
          exit 1
        fi
        while [ "$#" -gt 0 ] && [[ "$1" != --* ]]; do
          SKIP_PACKAGES+=("$1")
          shift
        done
        ;;
      --*)
        echo "Unknown option: $1" >&2
        echo "Use --skip NAME or see --list / --help." >&2
        echo >&2
        usage >&2
        exit 1
        ;;
      *)
        positional_packages+=("$1")
        shift
        ;;
    esac
  done

  if [ "$used_only_flag" = true ] && [ "${#positional_packages[@]}" -gt 0 ]; then
    echo "Use either --only or positional package names, not both." >&2
    exit 1
  fi

  if [ "${#only_packages[@]}" -gt 0 ]; then
    allow_packages=("${only_packages[@]}")
  elif [ "${#positional_packages[@]}" -gt 0 ]; then
    allow_packages=("${positional_packages[@]}")
  fi

  if [ "${#allow_packages[@]}" -gt 0 ]; then
    validate_package_names "${allow_packages[@]}"
  fi
  if [ "${#SKIP_PACKAGES[@]}" -gt 0 ]; then
    validate_package_names "${SKIP_PACKAGES[@]}"
  fi

  if [ "${#allow_packages[@]}" -gt 0 ]; then
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      selected+=("$id")
    done < <(selected_packages "${allow_packages[@]}")
  else
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      selected+=("$id")
    done < <(selected_packages)
  fi

  if [ "${#selected[@]}" -eq 0 ]; then
    echo "No packages selected." >&2
    echo "See $SCRIPT_NAME --list" >&2
    exit 1
  fi

  mkdir -p "$STATE_DIR"
  : >"$LOG_FILE"
  : >"$STATUS_FILE"

  require_command sudo
  require_command pacman

  log "Starting secure package installation"
  log "State directory: $STATE_DIR"
  log "Packages: ${selected[*]}"

  if [ "$DRY_RUN" = false ]; then
    log "Refreshing sudo credentials"
    sudo -v
  fi

  for id in "${selected[@]}"; do
    "${PACKAGE_INSTALLER[$id]}"
  done

  print_summary

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    exit 1
  fi
}

main "$@"

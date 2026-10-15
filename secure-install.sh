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
NOTIFY=false
MARK_CURRENT=false

# Package scripts build their download paths from STATE_DIR when they load,
# so check mode has to pick its scratch directory before they are sourced.
RECORD_DIR="$STATE_DIR"
CHECK_MODE=false
for arg in "$@"; do
  [ "$arg" = --check ] && CHECK_MODE=true
done
if [ "$CHECK_MODE" = true ]; then
  mkdir -p "$RECORD_DIR"
  STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/secure-install-check.XXXXXX")"
  trap 'rm -rf "$STATE_DIR"' EXIT
  LOG_FILE="$RECORD_DIR/check.log"
  STATUS_FILE="$STATE_DIR/check.status"
fi

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
  --check          Only report which apps have a newer release (no sudo,
                   nothing downloaded or installed)
  --notify         With --check, also send a desktop notification
  --mark-current   With --check, record the latest release as installed
                   (use once for apps installed before update tracking)
  -h, --help       Show this help text

Examples:
  $SCRIPT_NAME --yes
  $SCRIPT_NAME remnote
  $SCRIPT_NAME desktop aur
  $SCRIPT_NAME --only remnote slack
  $SCRIPT_NAME --skip remnote slack
  $SCRIPT_NAME --check

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

# Desktop notification for found updates. With changelog links it offers an
# "Open changelogs" button (notify-send waits for the click or the timeout)
# that opens each release-notes page in the default browser.
notify_updates() {
  local title="$1"
  local body="$2"
  shift 2
  local action="" link

  if [ "$#" -eq 0 ]; then
    notify-send -a "secure-install" -i system-software-update "$title" "$body" || true
    return 0
  fi

  action="$(notify-send -a "secure-install" -i system-software-update \
    -A open="Open changelogs" "$title" "$body" 2>/dev/null || true)"
  if [ "$action" = open ]; then
    for link in "$@"; do
      xdg-open "$link" >/dev/null 2>&1 &
    done
    wait
  fi
}

# Run the selected installers in check mode and compare what each would
# download now with what was recorded at its last successful install.
check_for_updates() {
  local id current installed link
  local -a updates=() unknown=() failed=() links=()
  local -A link_for=()

  # Nothing in check mode may change the system. run_step already skips
  # install steps; this catches any sudo an installer calls directly.
  sudo() {
    log "check mode: refused sudo $*"
    return 1
  }

  printf '%-24s %s\n' "PACKAGE" "STATUS"
  for id in "$@"; do
    [ -n "${PACKAGE_ARTIFACT[$id]+x}" ] || continue

    CURRENT_PACKAGE="$id"
    # Installers print progress, curl meters and gpg chatter; keep that in the
    # log so the terminal (and the timer's journal) only shows the table.
    "${PACKAGE_INSTALLER[$id]}" >>"$LOG_FILE" 2>&1 || true
    CURRENT_PACKAGE=""

    current="$(cat "$FINGERPRINT_DIR/$id" 2>/dev/null || true)"
    installed="$(installed_fingerprint "$id")"

    if [ -z "$current" ]; then
      failed+=("$id")
      printf '%-24s %s\n' "$id" "check failed (see $LOG_FILE)"
      continue
    fi

    if [ "$MARK_CURRENT" = true ]; then
      record_installed_release "$id" "$current"
      printf '%-24s %s\n' "$id" "marked as up to date"
    elif [ -z "$installed" ]; then
      unknown+=("$id")
      printf '%-24s %s\n' "$id" "not tracked yet"
    elif [ "$current" != "$installed" ]; then
      updates+=("$id")
      link="$(changelog_link "$id")"
      link_for[$id]="$link"
      [ -z "$link" ] || links+=("$link")
      printf '%-24s %-17s %s\n' "$id" "UPDATE AVAILABLE" "${link:-(no changelog published)}"
    else
      printf '%-24s %s\n' "$id" "up to date"
    fi
  done

  # One "id<TAB>changelog" line per pending update. Merge: a check of some
  # packages (--only) must not forget pending updates of the others, so drop
  # the checked ids from the list, then add what is new.
  local list="$RECORD_DIR/updates-available.txt"
  {
    [ -f "$list" ] && awk -F '\t' 'NR == FNR { checked[$1] = 1; next } !($1 in checked)' \
      <(printf '%s\n' "$@") "$list"
    for id in "${updates[@]}"; do
      printf '%s\t%s\n' "$id" "${link_for[$id]}"
    done
  } | sed '/^$/d' | sort -u -t $'\t' -k1,1 >"$list.tmp"
  mv "$list.tmp" "$list"

  echo
  if [ "${#updates[@]}" -gt 0 ]; then
    echo "Update with: $SCRIPT_DIR/$SCRIPT_NAME --only ${updates[*]}"
  else
    echo "No updates found."
  fi
  [ "${#unknown[@]}" -eq 0 ] || echo "Not tracked yet (install once, or run --check --mark-current): ${unknown[*]}"

  if [ "$NOTIFY" = true ] && [ "${#updates[@]}" -gt 0 ] && command -v notify-send >/dev/null 2>&1; then
    notify_updates "${#updates[@]} app update(s) available" "${updates[*]}" "${links[@]}"
  fi
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
      --check)
        shift
        ;;
      --notify)
        NOTIFY=true
        shift
        ;;
      --mark-current)
        MARK_CURRENT=true
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
  INSTALLED_FILE="$RECORD_DIR/installed.tsv"
  FINGERPRINT_DIR="$STATE_DIR/fingerprints-$TIMESTAMP"
  mkdir -p "$FINGERPRINT_DIR"

  if [ "$CHECK_MODE" = true ]; then
    check_for_updates "${selected[@]}"
    return
  fi

  require_command sudo
  require_command pacman

  log "Starting secure package installation"
  log "State directory: $STATE_DIR"
  log "Packages: ${selected[*]}"

  if [ "$DRY_RUN" = false ]; then
    log "Refreshing sudo credentials"
    sudo -v
  fi

  local failures_before fingerprint
  for id in "${selected[@]}"; do
    failures_before=${#FAILURES[@]}
    CURRENT_PACKAGE="$id"
    "${PACKAGE_INSTALLER[$id]}"
    CURRENT_PACKAGE=""
    reopen_closed_apps

    fingerprint="$(cat "$FINGERPRINT_DIR/$id" 2>/dev/null || true)"
    if [ "$DRY_RUN" = false ] && [ "${#FAILURES[@]}" -eq "$failures_before" ] && [ -n "$fingerprint" ]; then
      record_installed_release "$id" "$fingerprint"
    fi
  done
  rm -rf "$FINGERPRINT_DIR"

  print_summary

  if [ "${#FAILURES[@]}" -gt 0 ]; then
    exit 1
  fi
}

main "$@"

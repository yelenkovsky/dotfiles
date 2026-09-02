FAILURES=()

declare -a PACKAGE_IDS=()
declare -A PACKAGE_ORDER=()
declare -A PACKAGE_DESCRIPTION=()
declare -A PACKAGE_INSTALLER=()

register_package() {
  local id="$1"
  local order="$2"
  local description="$3"
  local installer="$4"

  if [ -n "${PACKAGE_INSTALLER[$id]+x}" ]; then
    echo "Duplicate package id: $id" >&2
    exit 1
  fi

  PACKAGE_IDS+=("$id")
  PACKAGE_ORDER["$id"]="$order"
  PACKAGE_DESCRIPTION["$id"]="$description"
  PACKAGE_INSTALLER["$id"]="$installer"
}

package_exists() {
  [ -n "${PACKAGE_INSTALLER[$1]+x}" ]
}

sorted_package_ids() {
  local id

  for id in "${PACKAGE_IDS[@]}"; do
    printf '%s\t%s\n' "${PACKAGE_ORDER[$id]}" "$id"
  done | sort -n -k1,1 -k2,2 | cut -f2
}

list_packages() {
  local id

  while IFS= read -r id; do
    printf '%-24s %s\n' "$id" "${PACKAGE_DESCRIPTION[$id]}"
  done < <(sorted_package_ids)
}

load_secure_install_packages() {
  local package_dir="$1"
  local file
  local found=0

  for file in "$package_dir"/*.sh; do
    [ -e "$file" ] || continue
    # shellcheck disable=SC1090
    source "$file"
    found=1
  done

  if [ "$found" -eq 0 ]; then
    echo "No package scripts found in $package_dir" >&2
    exit 1
  fi
}

log() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$*" | tee -a "$LOG_FILE"
}

command_to_string() {
  local rendered=""
  local arg

  for arg in "$@"; do
    printf -v rendered '%s%q ' "$rendered" "$arg"
  done

  printf '%s' "${rendered% }"
}

record_status() {
  printf '%s\t%s\n' "$1" "$2" >>"$STATUS_FILE"
}

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log "Missing required command: $command_name"
    exit 1
  fi
}

run_step() {
  local step_name="$1"
  shift
  local -a command=("$@")
  local exit_code=0

  log ""
  log "STEP: $step_name"
  log "COMMAND: $(command_to_string "${command[@]}")"

  if [ "$DRY_RUN" = true ]; then
    record_status "DRY_RUN" "$step_name"
    return 0
  fi

  if "${command[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    record_status "OK" "$step_name"
    log "STEP OK: $step_name"
    return 0
  fi

  exit_code=${PIPESTATUS[0]}
  FAILURES+=("$step_name (exit $exit_code)")
  record_status "FAIL($exit_code)" "$step_name"
  log "STEP FAILED: $step_name (exit $exit_code)"

  if [ "$STOP_ON_ERROR" = true ]; then
    print_summary
    exit "$exit_code"
  fi

  return 0
}

install_package_group() {
  local manager="$1"
  local group_name="$2"
  local array_name="$3"
  local -n packages_ref="$array_name"
  local package_name
  local -a base_command

  log ""
  log "GROUP: $group_name"

  case "$manager" in
    pacman)
      base_command=(sudo pacman -S --needed)
      [ "$ASSUME_YES" = true ] && base_command+=(--noconfirm)
      ;;
    yay)
      if ! command -v yay >/dev/null 2>&1; then
        FAILURES+=("AUR packages (missing required command: yay)")
        record_status "FAIL" "AUR packages"
        log "Skipping AUR packages because yay is not installed"
        return 0
      fi
      base_command=(yay -S --needed)
      [ "$ASSUME_YES" = true ] && base_command+=(--noconfirm)
      ;;
    *)
      log "Unsupported package manager: $manager"
      exit 1
      ;;
  esac

  for package_name in "${packages_ref[@]}"; do
    run_step "$manager package: $package_name" "${base_command[@]}" "$package_name"
  done
}

download_url_to_file() {
  local dest="$1"
  local url="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget --tries=3 -O "$dest" "$url"
    return
  fi

  log "Missing required command: curl or wget"
  return 127
}

print_summary() {
  log ""
  log "Install log: $LOG_FILE"
  log "Step summary: $STATUS_FILE"

  if [ "${#FAILURES[@]}" -eq 0 ]; then
    log "All steps completed successfully."
    return 0
  fi

  log "Failures detected:"
  local failure
  for failure in "${FAILURES[@]}"; do
    log "  - $failure"
  done
}

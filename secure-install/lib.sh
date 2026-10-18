FAILURES=()

declare -a PACKAGE_IDS=()
declare -A PACKAGE_ORDER=()
declare -A PACKAGE_DESCRIPTION=()
declare -A PACKAGE_INSTALLER=()
declare -A PACKAGE_ARTIFACT=()
declare -A PACKAGE_CHANGELOG=()
declare -A PACKAGE_CHANGELOG_MATCH=()
declare -A PACKAGE_CHANGELOG_FALLBACK=()

# --check mode: run each installer up to the point where it would download the
# app, record what it would download, and stop. Set by secure-install.sh.
CHECK_MODE="${CHECK_MODE:-false}"
CURRENT_PACKAGE=""
FINGERPRINT_DIR=""
INSTALLED_FILE=""

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

# Name the download that is the app itself (not metadata, checksums or keys),
# so --check can tell when a newer one is published.
register_update_check() {
  PACKAGE_ARTIFACT["$1"]="$2"
}

# Where to read what changed when --check finds a newer release.
#   register_changelog ID TEMPLATE [PATTERN [FALLBACK]]
# PATTERN is a bash regex matched against the release's download URL (the one
# the installer asked for, then the final one after redirects); its first
# group is the version or tag. TEMPLATE may use {version}, {version_dashes}
# (dots as dashes) and {version_nodots}. Without PATTERN the TEMPLATE is a
# fixed page. When PATTERN does not match, FALLBACK (a fixed page) is used.
register_changelog() {
  PACKAGE_CHANGELOG["$1"]="$2"
  PACKAGE_CHANGELOG_MATCH["$1"]="${3-}"
  PACKAGE_CHANGELOG_FALLBACK["$1"]="${4-}"
}

# Print the changelog link for the release --check just found, if any.
changelog_link() {
  local id="$1"
  local template="${PACKAGE_CHANGELOG[$id]-}"
  local pattern="${PACKAGE_CHANGELOG_MATCH[$id]-}"
  local urls version

  [ -n "$template" ] || return 0
  if [ -z "$pattern" ]; then
    printf '%s\n' "$template"
    return 0
  fi

  urls="$(tr '\n' ' ' <"$FINGERPRINT_DIR/$id.url" 2>/dev/null)"
  if [[ "$urls" =~ $pattern ]]; then
    version="${BASH_REMATCH[1]}"
    template="${template//\{version\}/$version}"
    template="${template//\{version_dashes\}/${version//./-}}"
    template="${template//\{version_nodots\}/${version//./}}"
    printf '%s\n' "$template"
  elif [ -n "${PACKAGE_CHANGELOG_FALLBACK[$id]-}" ]; then
    printf '%s\n' "${PACKAGE_CHANGELOG_FALLBACK[$id]}"
  fi
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
  if [ "$CHECK_MODE" = true ]; then
    printf '[%s] %s\n' "$(date +'%F %T')" "$*" >>"$LOG_FILE"
    return 0
  fi

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

  # Check mode only fetches and reads release metadata. Anything that installs,
  # extracts or changes the system is skipped, and failures are not reported.
  if [ "$CHECK_MODE" = true ]; then
    case "${command[0]}" in
      download_* | resolve_* | parse_* | verify_* | fetch_*)
        "${command[@]}" >>"$LOG_FILE" 2>&1 || true
        ;;
    esac
    return 0
  fi

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

  [ "$CHECK_MODE" = true ] && return 0

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

# Print the PIDs of our own processes started from any of the given install
# paths (a directory or a single file). A process matches on its executable,
# its argv[0], or the APPIMAGE variable that AppImages export to every child,
# because a running AppImage executes from /tmp/.mount_*, not from /opt.
# The installer's own ancestors (e.g. the terminal app it runs in) are skipped.
app_process_pids() {
  local -A ancestors=()
  local proc pid exe argv0 entry appimage path value
  local -a values

  pid=$$
  while [ "$pid" -gt 1 ] 2>/dev/null; do
    ancestors[$pid]=1
    read -r _ _ _ pid _ <"/proc/$pid/stat" 2>/dev/null || break
  done

  for proc in /proc/[0-9]*; do
    pid="${proc#/proc/}"
    [ -O "$proc" ] || continue
    [ -z "${ancestors[$pid]+x}" ] || continue

    exe="$(readlink "$proc/exe" 2>/dev/null)" || exe=""
    exe="${exe% (deleted)}"
    argv0=""
    IFS= read -r -d '' argv0 <"$proc/cmdline" 2>/dev/null || true
    appimage=""
    case "$exe" in
      "${TMPDIR:-/tmp}"/.mount_* | "${TMPDIR:-/tmp}"/appimage_extracted_* | /tmp/.mount_* | /tmp/appimage_extracted_*)
        {
          while IFS= read -r -d '' entry; do
            case "$entry" in APPIMAGE=*) appimage="${entry#APPIMAGE=}"; break ;; esac
          done <"$proc/environ"
        } 2>/dev/null || true
        ;;
    esac

    values=("$exe" "$argv0" "$appimage")
    for path in "$@"; do
      for value in "${values[@]}"; do
        case "$value" in
          "$path" | "$path"/* | "$path "*)
            printf '%s\n' "$pid"
            continue 3
            ;;
        esac
      done
    done
  done

  return 0
}

# True when the installer itself runs inside the app (e.g. installing Claude
# Desktop from its own terminal pane); closing it would kill the installer.
app_hosts_installer() {
  local pid=$$ exe path

  while [ "$pid" -gt 1 ] 2>/dev/null; do
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null)" || exe=""
    exe="${exe% (deleted)}"
    for path in "$@"; do
      case "$exe" in "$path" | "$path"/*) return 0 ;; esac
    done
    read -r _ _ _ pid _ <"/proc/$pid/stat" 2>/dev/null || break
  done

  return 1
}

# Close an app before its files are replaced: overwriting a running binary
# fails with "Text file busy" and leaves a mixed old/new install. Asks politely
# first (SIGTERM, lets Electron apps save state), then forces anything still
# alive after APP_CLOSE_TIMEOUT seconds.
stop_app_processes() {
  local label="$1"
  shift
  local timeout="${APP_CLOSE_TIMEOUT:-10}"
  local waited=0
  local -a pids

  if app_hosts_installer "$@"; then
    log "The installer is running inside $label; close $label and run it from another terminal"
    return 1
  fi

  mapfile -t pids < <(app_process_pids "$@")
  [ "${#pids[@]}" -gt 0 ] || return 0

  log "Closing running $label (${#pids[@]} processes)"
  kill -TERM "${pids[@]}" 2>/dev/null || true

  while [ -n "$(app_process_pids "$@")" ] && [ "$waited" -lt "$timeout" ]; do
    sleep 1
    waited=$((waited + 1))
  done

  mapfile -t pids < <(app_process_pids "$@")
  if [ "${#pids[@]}" -gt 0 ]; then
    log "$label did not exit after ${timeout}s; killing it"
    kill -KILL "${pids[@]}" 2>/dev/null || true
    sleep 1
  fi

  if [ -n "$(app_process_pids "$@")" ]; then
    log "Could not close $label"
    return 1
  fi
}

# Apps closed for the current package, reopened by reopen_closed_apps once it
# is installed: systemd units to start again, and commands to run again.
REOPEN_LABELS=()
REOPEN_UNITS=()
REOPEN_COMMANDS=()

# Note how each running app was started, before it is closed. A process whose
# parent is not part of the app is a launch point. If it belongs to a
# persistent systemd service (e.g. an XDG autostart unit) that service is
# restarted. Otherwise (keybinding, launcher, terminal, or a one-off
# systemd-run unit that is gone once the app exits) the app is run again:
# through relaunch when the installer names its launcher, so the launcher's
# flags and working directory apply, else with the original command line.
remember_app_launches() {
  local label="$1"
  local relaunch="$2"
  shift 2
  local -A app=()
  local -a units=() commands=() argv=()
  local pid ppid unit cmd arg cwd exe rest
  local need_command=false

  for pid in $(app_process_pids "$@"); do
    app[$pid]=1
  done

  for pid in "${!app[@]}"; do
    read -r _ _ _ ppid _ <"/proc/$pid/stat" 2>/dev/null || continue
    [ -z "${app[$ppid]+x}" ] || continue

    unit="$(sed -n 's|^0::.*/||p' "/proc/$pid/cgroup" 2>/dev/null)"
    if [[ "$unit" == *.service ]] \
      && [ "$(systemctl --user show -p Transient --value "$unit" 2>/dev/null)" = no ]; then
      [[ " ${units[*]} " == *" $unit "* ]] || units+=("$unit")
      continue
    fi

    if [ -n "$relaunch" ]; then
      need_command=true
      continue
    fi

    argv=()
    while IFS= read -r -d '' arg; do
      argv+=("$arg")
    done <"/proc/$pid/cmdline" 2>/dev/null
    [ "${#argv[@]}" -gt 0 ] || continue

    # Electron/Chromium rewrite their command line into one space-joined
    # string ("/path/app --flag"). Take the program from /proc/PID/exe and
    # split the rest; a lone argument that is a real file (a path with a
    # space, "/opt/proton-pass/Proton Pass") is left alone.
    if [ "${#argv[@]}" -eq 1 ] && [[ "${argv[0]}" == *" "* ]] && [ ! -e "${argv[0]}" ]; then
      exe="$(readlink "/proc/$pid/exe" 2>/dev/null)"
      exe="${exe% (deleted)}"
      if [ -n "$exe" ] && [[ "${argv[0]}" == "$exe "* ]]; then
        rest="${argv[0]#"$exe "}"
        read -r -a argv <<<"$rest"
        argv=("$exe" "${argv[@]}")
      fi
    fi

    # Relative program paths (e.g. ./Grayjay after the launcher's cd) are
    # resolved against the process's working directory.
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)"
    if [[ "${argv[0]}" != /* && "${argv[0]}" == */* ]] && [ -n "$cwd" ]; then
      argv[0]="$cwd/${argv[0]#./}"
    fi

    cmd=""
    for arg in "${argv[@]}"; do
      printf -v cmd '%s%q ' "$cmd" "$arg"
    done
    commands+=("$cmd")
  done

  if [ "$need_command" = true ]; then
    printf -v cmd '%q' "$relaunch"
    commands+=("$cmd")
  fi

  # One reopen per app: restarting its persistent service brings it back, so
  # extra launch points (a second instance started from a shortcut) are not
  # run again as well.
  if [ "${#units[@]}" -gt 0 ]; then
    for unit in "${units[@]}"; do
      [[ " ${REOPEN_UNITS[*]} " == *" $unit "* ]] || REOPEN_UNITS+=("$unit")
    done
  else
    REOPEN_COMMANDS+=("${commands[@]}")
  fi

  if [ "${#units[@]}" -gt 0 ] || [ "${#commands[@]}" -gt 0 ]; then
    REOPEN_LABELS+=("$label")
  fi
}

# Start again what close_running_app closed for this package, whether its
# install succeeded or not (a failed replace keeps the old version runnable).
reopen_closed_apps() {
  local unit cmd
  local -a argv

  if [ "${#REOPEN_LABELS[@]}" -eq 0 ]; then
    return 0
  fi

  log "Reopening ${REOPEN_LABELS[*]}"
  for unit in "${REOPEN_UNITS[@]}"; do
    systemctl --user start "$unit" || log "Could not restart $unit"
  done
  for cmd in "${REOPEN_COMMANDS[@]}"; do
    eval "argv=($cmd)"
    if command -v uwsm-app >/dev/null 2>&1; then
      systemd-run --user --quiet --collect \
        --property=StandardOutput=null --property=StandardError=null \
        uwsm-app -- "${argv[@]}" || log "Could not reopen: $cmd"
    else
      setsid -f "${argv[@]}" </dev/null >/dev/null 2>&1 || log "Could not reopen: $cmd"
    fi
  done

  REOPEN_LABELS=()
  REOPEN_UNITS=()
  REOPEN_COMMANDS=()
}

# Make an installed app the default opener for MIME types in the user's
# ~/.config/mimeapps.list. Never fails the install.
#
# Usage: set_default_app DESKTOP_ID LABEL MIME_TYPE...
set_default_app() {
  local desktop_id="$1"
  local label="$2"
  shift 2

  if ! command -v xdg-mime >/dev/null 2>&1; then
    log "xdg-mime is not installed; $label was not made a default app"
    return 0
  fi

  xdg-mime default "$desktop_id" "$@" || return 0
  log "$label is the default app for $# file types"
}

# Installers call this right before their install step, after the download has
# been verified, so a failed download never closes anything. Whatever it
# closes is reopened after the package finishes (see reopen_closed_apps).
#
# Usage: close_running_app [--relaunch LAUNCHER] LABEL PATH...
close_running_app() {
  local relaunch=""
  if [ "${1-}" = --relaunch ]; then
    relaunch="$2"
    shift 2
  fi
  local label="$1"
  shift

  [ "$CHECK_MODE" = true ] && return 0

  if [ -z "$(app_process_pids "$@")" ] && ! app_hosts_installer "$@"; then
    return 0
  fi

  if [ "$DRY_RUN" != true ] && ! app_hosts_installer "$@"; then
    remember_app_launches "$label" "$relaunch" "$@"
  fi

  run_step "close running $label" stop_app_processes "$label" "$@"
}

restore_executable_bits() {
  local dir="$1"
  local file
  local -a programs=()

  if ! command -v file >/dev/null 2>&1; then
    log "file(1) is missing; not checking $dir for programs without execute permission"
    return 0
  fi

  mapfile -t programs < <(
    sudo find "$dir" -type f ! -perm -u+x ! -name '*.so' ! -name '*.so.*' -print0 \
      | xargs -0 -r file -N -F $'\t' \
      | awk -F '\t' '$2 ~ /ELF .*executable/ { print $1 }'
  )

  for file in "${programs[@]}"; do
    sudo chmod 755 "$file" || return 1
    log "Marked ${file#"$dir"/} executable (the archive stored it without permissions)"
  done
}

# ---- pacman ownership guard -------------------------------------------------
# secure-install replaces apps that were once installed from pacman/AUR. If
# such a package is still installed it keeps owning the paths we write, and
# its next upgrade silently puts its own build back (Brave's launcher and the
# Portmaster firewall both went that way). So refuse to overwrite or remove
# anything pacman owns, and say how to hand the files over.

pacman_owners() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  command -v pacman >/dev/null 2>&1 || return 0
  pacman -Qqo -- "$1" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'
}

report_pacman_conflict() {
  log "Refusing to change $1: it belongs to the pacman package(s) $2."
  log "  A pacman/yay upgrade of $2 would put its own version back over ours."
  log "  Hand the files over without deleting them, then run this install again:"
  log "    sudo pacman -Rdd --dbonly $2"
}

# Files only: shared directories (/usr/share/applications, icon theme dirs)
# are owned by many packages and are fine to write into.
refuse_if_pacman_owned() {
  local path owners

  for path in "$@"; do
    [ -d "$path" ] && [ ! -L "$path" ] && continue
    owners="$(pacman_owners "$path")"
    if [ -n "$owners" ]; then
      report_pacman_conflict "$path" "$owners"
      return 1
    fi
  done
}

# An app's own install root (/opt/x, /usr/lib/portmaster) must not belong to a
# package either; checked before replace_install_tree touches anything.
refuse_if_pacman_owned_dir() {
  local owners
  local -a list

  owners="$(pacman_owners "$1")"
  [ -n "$owners" ] || return 0

  read -r -a list <<<"$owners"
  if [ "${#list[@]}" -gt 1 ]; then
    # An app's own folder belongs to one package at most; many owners means a
    # shared system directory, which must never be replaced wholesale.
    log "Refusing to replace $1: it is a shared system directory (owned by ${#list[@]} pacman packages), not an app's own folder."
    return 1
  fi
  report_pacman_conflict "$1" "$owners"
  return 1
}

# Every installer writes system files through sudo; check the targets of the
# commands that create, replace or delete files before running them.
# SECURE_INSTALL_PACMAN_GUARD=false turns the check off.
sudo() {
  local -a targets=()
  local arg

  if [ "${SECURE_INSTALL_PACMAN_GUARD:-true}" = true ] && [ "$CHECK_MODE" != true ]; then
    case "${1-}" in
      tee)
        for arg in "${@:2}"; do
          [[ "$arg" == -* ]] || { targets+=("$arg"); break; }
        done
        ;;
      install | ln)
        targets+=("${@: -1}")
        ;;
      rm)
        for arg in "${@:2}"; do
          [[ "$arg" == -* ]] || targets+=("$arg")
        done
        ;;
    esac
    if [ "${#targets[@]}" -gt 0 ]; then
      refuse_if_pacman_owned "${targets[@]}" || return 1
    fi
  fi

  command sudo "$@"
}

# Install an extracted app tree into dest without ever leaving it half-copied:
# copy into dest.new, swap it in with two renames on the same filesystem, and
# only then delete the old tree. Any failure before the swap leaves the old
# install untouched. Pass owner as user:group to hand the tree to the user (so
# later updates need no sudo), or "" to keep it root-owned.
replace_install_tree() {
  local src="$1"
  local dest="$2"
  local owner="${3-}"
  local stage="$dest.new"
  local old="$dest.old"

  refuse_if_pacman_owned_dir "$dest" || return 1

  sudo rm -rf "$stage" "$old" || return 1

  if ! sudo mkdir -p "$stage" || ! sudo cp -a "$src"/. "$stage"/; then
    log "Could not copy the new files into $stage; keeping the current install"
    sudo rm -rf "$stage"
    return 1
  fi

  if [ -n "$owner" ]; then
    if ! sudo chown -R "$owner" "$stage" || ! sudo chmod u+rwX "$stage"; then
      log "Could not set ownership on $stage; keeping the current install"
      sudo rm -rf "$stage"
      return 1
    fi
  fi

  # Zip entries stored without Unix permissions extract as 0644, programs
  # included (Grayjay's cef/justcefnative did, and Grayjay could not start).
  # Mark every ELF executable as one; shared libraries do not need it.
  if ! restore_executable_bits "$stage"; then
    log "Could not mark the programs in $stage executable; keeping the current install"
    sudo rm -rf "$stage"
    return 1
  fi

  if [ -e "$dest" ] && ! sudo mv "$dest" "$old"; then
    log "Could not move the current install aside; keeping it"
    sudo rm -rf "$stage"
    return 1
  fi

  if ! sudo mv "$stage" "$dest"; then
    log "Could not move the new files into $dest; restoring the previous install"
    [ -e "$old" ] && sudo mv "$old" "$dest"
    sudo rm -rf "$stage"
    return 1
  fi

  sudo rm -rf "$old" || log "Could not remove the previous install at $old"
}

# Identify a release without downloading it: the final URL after redirects
# (query string dropped, since CDNs sign it per request) and the size in bytes.
# Tries HEAD first and falls back to a one-byte range GET for servers that
# refuse HEAD. Prints "url|size".
release_fingerprint() {
  local url="$1"
  local user_agent="${2-}"
  local final_url_file="${3-}"
  local -a agent=()
  local headers=""
  local final=""
  local size=""

  [ -n "$user_agent" ] && agent=(-A "$user_agent")

  headers="$(curl -fsSIL --retry 2 --max-time 60 "${agent[@]}" -w '\n%{url_effective}' "$url" 2>/dev/null)" \
    || headers="$(curl -fsSL --retry 2 --max-time 60 -r 0-0 -D - -o /dev/null "${agent[@]}" -w '\n%{url_effective}' "$url" 2>/dev/null)" \
    || return 1

  # Only the last response counts: redirects carry their own (often zero)
  # Content-Length. Generated downloads (e.g. GitHub source tarballs) send no
  # size at all; fall back to the ETag, and then to the URL alone, which for
  # those already names the release.
  final="$(printf '%s\n' "$headers" | tail -n 1)"
  size="$(printf '%s\n' "$headers" | tr -d '\r' | awk '
    /^HTTP\// { range = ""; length_ = ""; etag = "" }
    tolower($1) == "content-range:" { n = split($2 $3, part, "/"); if (part[n] ~ /^[0-9]+$/) range = part[n] }
    tolower($1) == "content-length:" && $2 > 0 { length_ = $2 }
    tolower($1) == "etag:" { etag = $2 }
    END { print (range != "" ? range : length_ != "" ? length_ : etag != "" ? "etag:" etag : "-") }
  ')"

  [ -n "$final" ] || return 1
  # The full final URL (query included) can name the release even when the
  # path does not (DBeaver: ...?filename=dbeaver-ce-26.2.2-...); keep it for
  # changelog links, never for the fingerprint.
  [ -z "$final_url_file" ] || printf '%s\n' "$final" >>"$final_url_file"
  printf '%s|%s\n' "${final%%\?*}" "$size"
}

# Called by download_url_to_file. In check mode, the app download is replaced
# by a fingerprint and everything the installer downloads after it is skipped.
# Returns 0 when the real download should go ahead.
intercept_package_download() {
  local dest="$1"
  local url="$2"
  local user_agent="$3"
  local artifact=""
  local file=""

  [ "$CHECK_MODE" = true ] && [ -n "$CURRENT_PACKAGE" ] || return 0
  artifact="${PACKAGE_ARTIFACT[$CURRENT_PACKAGE]-}"
  file="$FINGERPRINT_DIR/$CURRENT_PACKAGE"

  [ ! -e "$file" ] || return 1
  if [ -n "$artifact" ] && [ "$dest" = "$artifact" ]; then
    printf '%s\n' "$url" >"$file.url"
    release_fingerprint "$url" "$user_agent" "$file.url" >"$file.tmp" && mv "$file.tmp" "$file"
    rm -f "$file.tmp"
    return 1
  fi

  return 0
}

# After a real download of the app, remember its fingerprint so the main loop
# can record it once the whole package installed without failures.
note_package_download() {
  local dest="$1"
  local url="$2"
  local user_agent="$3"

  [ "$CHECK_MODE" != true ] && [ -n "$CURRENT_PACKAGE" ] && [ -n "$FINGERPRINT_DIR" ] || return 0
  [ "$dest" = "${PACKAGE_ARTIFACT[$CURRENT_PACKAGE]-}" ] || return 0

  release_fingerprint "$url" "$user_agent" >"$FINGERPRINT_DIR/$CURRENT_PACKAGE" \
    || rm -f "$FINGERPRINT_DIR/$CURRENT_PACKAGE"
  return 0
}

# For installers that see on their own that the latest release is already
# installed and skip the download: report that release anyway, so --check and
# the installed record still know about it.
note_release_already_installed() {
  [ -n "$CURRENT_PACKAGE" ] && [ -n "$FINGERPRINT_DIR" ] || return 0
  printf '%s\n' "$1" >"$FINGERPRINT_DIR/$CURRENT_PACKAGE.url"
  release_fingerprint "$1" "${2-}" "$FINGERPRINT_DIR/$CURRENT_PACKAGE.url" >"$FINGERPRINT_DIR/$CURRENT_PACKAGE" \
    || rm -f "$FINGERPRINT_DIR/$CURRENT_PACKAGE"
  return 0
}

installed_fingerprint() {
  [ -f "$INSTALLED_FILE" ] || return 0
  awk -F '\t' -v id="$1" '$1 == id { print $2 }' "$INSTALLED_FILE"
}

record_installed_release() {
  local id="$1"
  local fingerprint="$2"
  local tmp="$INSTALLED_FILE.tmp"

  mkdir -p "$(dirname "$INSTALLED_FILE")"
  touch "$INSTALLED_FILE"
  awk -F '\t' -v id="$id" '$1 != id' "$INSTALLED_FILE" >"$tmp"
  printf '%s\t%s\t%s\n' "$id" "$fingerprint" "$(date +%F)" >>"$tmp"
  sort -o "$tmp" "$tmp"
  mv "$tmp" "$INSTALLED_FILE"
}

download_url_to_file() {
  local dest="$1"
  local url="$2"
  local user_agent="${3-}"

  intercept_package_download "$dest" "$url" "$user_agent" || return 1
  _download_url_to_file "$dest" "$url" "$user_agent" || return
  note_package_download "$dest" "$url" "$user_agent"
}

_download_url_to_file() {
  local dest="$1"
  local url="$2"
  local user_agent="${3-}"

  if command -v curl >/dev/null 2>&1; then
    if [ -n "$user_agent" ]; then
      curl -fL --retry 3 --retry-delay 2 -A "$user_agent" -o "$dest" "$url"
    else
      curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
    fi
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    if [ -n "$user_agent" ]; then
      wget --tries=3 -U "$user_agent" -O "$dest" "$url"
    else
      wget --tries=3 -O "$dest" "$url"
    fi
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

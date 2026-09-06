register_package waydroid 290 "Waydroid Android container and ARM translation" install_waydroid

# Lineage 20 (Android 13) prebuilts used by casualsnek/waydroid_script.
# Pins are the GitHub commit plus the MD5 that script publishes next to the URL.
WAYDROID_NDK_COMMIT="68734c52556d3d7a6db34c603dd9276915c29f2f"
WAYDROID_NDK_MD5="0b2207c490fcb400aa5c87fcf0d52d38"
WAYDROID_NDK_URL="https://github.com/supremegamers/vendor_google_proprietary_ndk_translation-prebuilt/archive/${WAYDROID_NDK_COMMIT}.zip"
WAYDROID_HOUDINI_COMMIT="9e77896350caccd228b36b2e1b4a994aa4bd48da"
WAYDROID_HOUDINI_MD5="3807fe029559db3037efe245d9e74270"
WAYDROID_HOUDINI_URL="https://github.com/supremegamers/vendor_intel_proprietary_houdini/archive/${WAYDROID_HOUDINI_COMMIT}.zip"
WAYDROID_OVERLAY="/var/lib/waydroid/overlay/system"
WAYDROID_CFG="/var/lib/waydroid/waydroid.cfg"

WAYDROID_PACKAGES=(
  waydroid
  python-pyclip
  android-tools
)

waydroid_cpu_layer() {
  local vendor=""

  vendor="$(awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo)"
  case "$vendor" in
    GenuineIntel) printf '%s\n' houdini ;;
    *) printf '%s\n' ndk ;;
  esac
}

waydroid_render_node() {
  local node=""
  local vendor=""
  local fallback=""

  for node in /sys/class/drm/renderD*; do
    [ -e "$node/device/vendor" ] || continue
    vendor="$(tr '[:upper:]' '[:lower:]' <"$node/device/vendor")"
    vendor="${vendor%"${vendor##*[![:space:]]}"}"
    if [ "$vendor" = "0x10de" ]; then
      [ -z "$fallback" ] && fallback="/dev/dri/$(basename "$node")"
      continue
    fi
    printf '%s\n' "/dev/dri/$(basename "$node")"
    return 0
  done

  if [ -n "$fallback" ]; then
    log "Only NVIDIA render nodes found; Waydroid GPU may not work"
    printf '%s\n' "$fallback"
    return 0
  fi

  return 1
}

waydroid_cfg_set() {
  local section="$1"
  local key="$2"
  local value="$3"

  sudo python3 - "$WAYDROID_CFG" "$section" "$key" "$value" <<'PY'
import configparser
import sys

path, section, key, value = sys.argv[1:5]
cfg = configparser.ConfigParser()
cfg.optionxform = str
cfg.read(path)
if not cfg.has_section(section):
    cfg.add_section(section)
cfg.set(section, key, value)
with open(path, "w", encoding="utf-8") as handle:
    cfg.write(handle)
PY
}

waydroid_cfg_get() {
  local section="$1"
  local key="$2"

  python3 - "$WAYDROID_CFG" "$section" "$key" <<'PY'
import configparser
import sys

path, section, key = sys.argv[1:4]
cfg = configparser.ConfigParser()
cfg.optionxform = str
cfg.read(path)
if cfg.has_option(section, key):
    print(cfg.get(section, key))
PY
}

waydroid_init_images() {
  if [ -s /var/lib/waydroid/images/system.img ]; then
    log "Waydroid system image already present"
    return 0
  fi

  sudo waydroid init
}

waydroid_configure_gpu() {
  local node=""
  local current=""

  if [ ! -f "$WAYDROID_CFG" ]; then
    log "Waydroid config missing; skip GPU pin"
    return 1
  fi

  current="$(waydroid_cfg_get waydroid drm_device || true)"
  if [ -n "$current" ]; then
    log "Waydroid drm_device already set: $current"
    return 0
  fi

  node="$(waydroid_render_node)" || {
    log "No DRM render node found"
    return 1
  }

  log "Pinning Waydroid drm_device to $node"
  waydroid_cfg_set waydroid drm_device "$node"
  sudo waydroid upgrade --offline
}

waydroid_apply_translation_props() {
  local bridge="$1"

  waydroid_cfg_set properties ro.product.cpu.abilist "x86_64,x86,arm64-v8a,armeabi-v7a,armeabi"
  waydroid_cfg_set properties ro.product.cpu.abilist32 "x86,armeabi-v7a,armeabi"
  waydroid_cfg_set properties ro.product.cpu.abilist64 "x86_64,arm64-v8a"
  waydroid_cfg_set properties ro.dalvik.vm.native.bridge "$bridge"
  waydroid_cfg_set properties ro.enable.native.bridge.exec "1"
  waydroid_cfg_set properties ro.dalvik.vm.isa.arm "x86"
  waydroid_cfg_set properties ro.dalvik.vm.isa.arm64 "x86_64"

  if [ "$bridge" = "libndk_translation.so" ]; then
    waydroid_cfg_set properties ro.vendor.enable.native.bridge.exec "1"
    waydroid_cfg_set properties ro.vendor.enable.native.bridge.exec64 "1"
    waydroid_cfg_set properties ro.ndk_translation.version "0.2.3"
  fi
}

waydroid_extract_verified_zip() {
  local dest="$1"
  local url="$2"
  local expected_md5="$3"
  local min_bytes="$4"
  local actual_md5=""
  local file_size=0

  download_url_to_file "$dest" "$url"

  if [ ! -s "$dest" ]; then
    log "Downloaded translation zip is empty: $dest"
    return 1
  fi

  file_size="$(stat -c%s "$dest")"
  if [ "$file_size" -lt "$min_bytes" ]; then
    log "Downloaded translation zip looks too small: $dest ($file_size bytes)"
    return 1
  fi

  if [ "$(head -c 2 "$dest")" != 'PK' ]; then
    log "Downloaded translation file is not a zip: $dest"
    return 1
  fi

  actual_md5="$(md5sum "$dest" | awk '{ print $1 }')"
  if [ "$actual_md5" != "$expected_md5" ]; then
    log "Translation zip MD5 mismatch (expected $expected_md5, got $actual_md5)"
    return 1
  fi

  return 0
}

waydroid_install_ndk_overlay() {
  local zip="$STATE_DIR/libndk-$TIMESTAMP.zip"
  local work="$STATE_DIR/libndk-$TIMESTAMP"
  local prebuilts=""

  rm -rf "$work"
  mkdir -p "$work"

  waydroid_extract_verified_zip "$zip" "$WAYDROID_NDK_URL" "$WAYDROID_NDK_MD5" 10000000 || return 1
  bsdtar -C "$work" -xf "$zip"

  prebuilts="$(find "$work" -type d -path '*/prebuilts' | head -1)"
  if [ -z "$prebuilts" ] || [ ! -f "$prebuilts/lib64/libndk_translation.so" ]; then
    log "libndk zip does not contain prebuilts/lib64/libndk_translation.so"
    return 1
  fi

  sudo mkdir -p "$WAYDROID_OVERLAY"
  sudo cp -a "$prebuilts"/. "$WAYDROID_OVERLAY"/
  waydroid_apply_translation_props libndk_translation.so
  rm -rf "$work" "$zip"
}

waydroid_install_houdini_overlay() {
  local zip="$STATE_DIR/libhoudini-$TIMESTAMP.zip"
  local work="$STATE_DIR/libhoudini-$TIMESTAMP"
  local prebuilts=""
  local init_rc="$WAYDROID_OVERLAY/etc/init/houdini.rc"

  rm -rf "$work"
  mkdir -p "$work"

  waydroid_extract_verified_zip "$zip" "$WAYDROID_HOUDINI_URL" "$WAYDROID_HOUDINI_MD5" 10000000 || return 1
  bsdtar -C "$work" -xf "$zip"

  prebuilts="$(find "$work" -type d -path '*/prebuilts' | head -1)"
  if [ -z "$prebuilts" ] || [ ! -f "$prebuilts/lib64/libhoudini.so" ]; then
    log "libhoudini zip does not contain prebuilts/lib64/libhoudini.so"
    return 1
  fi

  sudo mkdir -p "$WAYDROID_OVERLAY"
  sudo cp -a "$prebuilts"/. "$WAYDROID_OVERLAY"/
  if [ ! -f "$init_rc" ]; then
    sudo mkdir -p "$(dirname "$init_rc")"
    sudo tee "$init_rc" >/dev/null <<'EOF'
on early-init
    mount binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc

on property:ro.enable.native.bridge.exec=1
    exec -- /system/bin/sh -c "echo ':arm_exe:M::\\x7f\\x45\\x4c\\x46\\x01\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\x28::/system/bin/houdini:P' > /proc/sys/fs/binfmt_misc/register"
    exec -- /system/bin/sh -c "echo ':arm_dyn:M::\\x7f\\x45\\x4c\\x46\\x01\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\x28::/system/bin/houdini:P' >> /proc/sys/fs/binfmt_misc/register"
    exec -- /system/bin/sh -c "echo ':arm64_exe:M::\\x7f\\x45\\x4c\\x46\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x02\\x00\\xb7::/system/bin/houdini64:P' >> /proc/sys/fs/binfmt_misc/register"
    exec -- /system/bin/sh -c "echo ':arm64_dyn:M::\\x7f\\x45\\x4c\\x46\\x02\\x01\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x03\\x00\\xb7::/system/bin/houdini64:P' >> /proc/sys/fs/binfmt_misc/register"
EOF
  fi
  waydroid_apply_translation_props libhoudini.so
  rm -rf "$work" "$zip"
}

waydroid_install_translation() {
  local layer=""

  if [ ! -f "$WAYDROID_CFG" ]; then
    log "Waydroid config missing; skip ARM translation"
    return 1
  fi

  layer="$(waydroid_cpu_layer)"
  if [ "$layer" = houdini ] && [ -f "$WAYDROID_OVERLAY/lib64/libhoudini.so" ]; then
    log "libhoudini overlay already present"
    return 0
  fi
  if [ "$layer" = ndk ] && [ -f "$WAYDROID_OVERLAY/lib64/libndk_translation.so" ]; then
    log "libndk overlay already present"
    return 0
  fi

  if ! command -v bsdtar >/dev/null 2>&1; then
    log "Missing required command: bsdtar"
    return 1
  fi

  sudo waydroid container stop >/dev/null 2>&1 || true

  if [ "$layer" = houdini ]; then
    log "Installing libhoudini ARM translation (Intel CPU)"
    waydroid_install_houdini_overlay
  else
    log "Installing libndk ARM translation (AMD or other CPU)"
    waydroid_install_ndk_overlay
  fi

  sudo waydroid upgrade --offline
}

waydroid_enable_container() {
  if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
    log "systemd not available; start waydroid-container.service yourself"
    return 0
  fi

  sudo systemctl enable --now waydroid-container.service
}

waydroid_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  if ! sudo ufw status | grep -q '^Status: active'; then
    log "UFW not active; skip Waydroid firewall rules"
    return 0
  fi

  sudo ufw allow in on waydroid0 comment 'waydroid'
  sudo ufw route allow in on waydroid0 comment 'waydroid-fwd'
  sudo ufw route allow out on waydroid0 comment 'waydroid-fwd'
}

waydroid_docker_forward() {
  local docker_json="/etc/docker/daemon.json"

  if [ ! -f "$docker_json" ]; then
    log "Docker daemon.json not present; skip ip-forward-no-drop"
    return 0
  fi

  if grep -q 'ip-forward-no-drop' "$docker_json"; then
    log "Docker ip-forward-no-drop already set"
    return 0
  fi

  sudo python3 - "$docker_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["ip-forward-no-drop"] = True
path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")
PY

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    sudo systemctl restart docker.service
  fi
}

install_waydroid() {
  install_package_group pacman "Waydroid packages" WAYDROID_PACKAGES
  run_step "initialize Waydroid images" waydroid_init_images
  run_step "configure Waydroid GPU" waydroid_configure_gpu
  run_step "install Waydroid ARM translation" waydroid_install_translation
  run_step "enable Waydroid container" waydroid_enable_container
  run_step "allow Waydroid DHCP through UFW" waydroid_ufw
  run_step "allow Waydroid through Docker forwarding" waydroid_docker_forward
}

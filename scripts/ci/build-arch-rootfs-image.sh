#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/system-payload-policy.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Build an Arch Linux ARM rootfs image for Lenovo Y700 / TB321FU.

Environment inputs:
  OUTPUT_DIR                  default: out/ci-rootfs
  OUTPUT_PREFIX               default: y700-archlinuxarm
  ARCH_ROOTFS_URL             default: official ArchLinuxARM aarch64 tarball
  ARCH_MIRROR                 pacman Server line, default: mirror.archlinuxarm.org
  ROOTFS_IMAGE_SIZE           default: 20G
  ROOTFS_LABEL                default: ArchLinux
  ROOTFS_PARTLABEL            default: userdata, informational for build metadata
  HOSTNAME_NAME               default: y700
  DEFAULT_USER_NAME           default: y700
  DEFAULT_USER_PASSWORD_HASH  crypt(3) hash supplied via secret; default: locked
  ROOT_PASSWORD_MODE          locked|set|empty, default: locked
  ROOT_PASSWORD_HASH          crypt(3) hash used when ROOT_PASSWORD_MODE=set
  USER_SUDO_MODE              password|nopasswd|none, default: password
  SDDM_AUTOLOGIN              1/0, default: 0
  SDDM_AUTOLOGIN_SESSION      default: plasma
  TZ_REGION                   default: Asia/Shanghai
  LANG_NAME                   default: zh_CN.UTF-8
  LOCALES                     whitespace list, default: en_US.UTF-8 zh_CN.UTF-8
  DESKTOP_PROFILE             minimal|standard|full, default: standard
  PACKAGE_LIST                additional pacman packages
  INSTALL_FCITX5_CHINESE      default: 1
  INSTALL_FIREFOX             default: 1
  INSTALL_CAMERA_APPS         install camera test apps, default: 1
  DEVICE_DEB_ARCHIVE          Y700 device payload archive containing .deb files and overlays
  DEVICE_DEB_DIR              optional local directory containing device .deb files/overlays
  SENSOR_DEB_ARCHIVE          TB321FU qcom-sns sensor package archive
  SENSOR_DEB_DIR              optional local directory containing TB321FU sensor packages
  HAPTICS_DEB_ARCHIVE         TB321FU haptics package archive
  HAPTICS_DEB_DIR             optional local directory containing TB321FU haptics packages
  CAMERA_STACK_ARCHIVE        verified TB321FU camera stack source/archive
  CAMERA_STACK_DIR            optional verified TB321FU camera stack directory
  BUILD_TB321FU_GPU_SENSOR    build/install TB321FU KSystemStats GPU plugin, default: 1
  TB321FU_GPU_SENSOR_SOURCE_ARCHIVE source archive containing source/tb321fu-ksystemstats-adreno-freq
  TB321FU_GPU_SENSOR_SOURCE_DIR     source directory containing the GPU plugin CMake project
  OVERLAY_ARCHIVE             optional rootfs overlay archive
  OVERLAY_DIR                 optional rootfs overlay directory
  KERNEL_VERSION              default: 7.1.1-g5df8e852ea72
  APPLY_Y700_FIRMWARE_FIXES   default: 1
  APPLY_Y700_AUDIO_POLICY_FIXES default: 1
  COMPRESS                    none|zstd|xz|7z, default: 7z
  CHUNK_SIZE                  optional 7z volume size, empty disables volumes
  KEEP_RAW_IMAGE              keep uncompressed rootfs image, default: 0
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

ci_require_cmd curl
ci_require_cmd tar
ci_require_cmd mount
ci_require_cmd umount
ci_require_cmd findmnt
ci_require_cmd realpath
ci_require_cmd truncate
ci_require_cmd mkfs.ext4
ci_require_cmd e2fsck
ci_require_cmd sha256sum
ci_require_cmd chroot
ci_require_cmd dpkg-deb
ci_require_cmd depmod
ci_require_cmd rsync

REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)

OUTPUT_DIR=${OUTPUT_DIR:-out/ci-rootfs}
OUTPUT_PREFIX=${OUTPUT_PREFIX:-y700-archlinuxarm}
ci_validate_output_prefix "$OUTPUT_PREFIX"
ARCH_ROOTFS_URL=${ARCH_ROOTFS_URL:-https://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
ARCH_ROOTFS_SHA256=${ARCH_ROOTFS_SHA256:-}
ARCH_MIRROR=${ARCH_MIRROR:-'http://os.archlinuxarm.org/$arch/$repo'}
ROOTFS_IMAGE_SIZE=${ROOTFS_IMAGE_SIZE:-20G}
ROOTFS_LABEL=${ROOTFS_LABEL:-ArchLinux}
ROOTFS_PARTLABEL=${ROOTFS_PARTLABEL:-userdata}
HOSTNAME_NAME=${HOSTNAME_NAME:-y700}
DEFAULT_USER_NAME=${DEFAULT_USER_NAME:-y700}
DEFAULT_USER_PASSWORD_HASH=${DEFAULT_USER_PASSWORD_HASH:-!}
ROOT_PASSWORD_MODE=${ROOT_PASSWORD_MODE:-locked}
ROOT_PASSWORD_HASH=${ROOT_PASSWORD_HASH:-}
USER_SUDO_MODE=${USER_SUDO_MODE:-password}
SDDM_AUTOLOGIN=${SDDM_AUTOLOGIN:-0}
SDDM_AUTOLOGIN_SESSION=${SDDM_AUTOLOGIN_SESSION:-plasma}
TZ_REGION=${TZ_REGION:-Asia/Shanghai}
LANG_NAME=${LANG_NAME:-zh_CN.UTF-8}
LOCALES=${LOCALES:-"en_US.UTF-8 zh_CN.UTF-8"}
DESKTOP_PROFILE=${DESKTOP_PROFILE:-standard}
PACKAGE_LIST=${PACKAGE_LIST:-}
PACKAGE_LIST=$(ci_normalize_package_list "$PACKAGE_LIST")
INSTALL_FCITX5_CHINESE=${INSTALL_FCITX5_CHINESE:-1}
INSTALL_FIREFOX=${INSTALL_FIREFOX:-1}
INSTALL_CAMERA_APPS=${INSTALL_CAMERA_APPS:-1}
DEVICE_DEB_ARCHIVE=${DEVICE_DEB_ARCHIVE:-}
DEVICE_DEB_ARCHIVE_SHA256=${DEVICE_DEB_ARCHIVE_SHA256:-}
DEVICE_DEB_DIR=${DEVICE_DEB_DIR:-}
SENSOR_DEB_ARCHIVE=${SENSOR_DEB_ARCHIVE:-}
SENSOR_DEB_ARCHIVE_SHA256=${SENSOR_DEB_ARCHIVE_SHA256:-}
SENSOR_DEB_DIR=${SENSOR_DEB_DIR:-}
HAPTICS_DEB_ARCHIVE=${HAPTICS_DEB_ARCHIVE:-}
HAPTICS_DEB_ARCHIVE_SHA256=${HAPTICS_DEB_ARCHIVE_SHA256:-}
HAPTICS_DEB_DIR=${HAPTICS_DEB_DIR:-}
CAMERA_STACK_ARCHIVE=${CAMERA_STACK_ARCHIVE:-}
CAMERA_STACK_ARCHIVE_SHA256=${CAMERA_STACK_ARCHIVE_SHA256:-}
CAMERA_STACK_DIR=${CAMERA_STACK_DIR:-}
BUILD_TB321FU_GPU_SENSOR=${BUILD_TB321FU_GPU_SENSOR:-1}
TB321FU_GPU_SENSOR_SOURCE_ARCHIVE=${TB321FU_GPU_SENSOR_SOURCE_ARCHIVE:-}
TB321FU_GPU_SENSOR_SOURCE_ARCHIVE_SHA256=${TB321FU_GPU_SENSOR_SOURCE_ARCHIVE_SHA256:-}
TB321FU_GPU_SENSOR_SOURCE_DIR=${TB321FU_GPU_SENSOR_SOURCE_DIR:-}
OVERLAY_ARCHIVE=${OVERLAY_ARCHIVE:-}
OVERLAY_ARCHIVE_SHA256=${OVERLAY_ARCHIVE_SHA256:-}
SOURCE_DATE_EPOCH=$(ci_source_date_epoch)
export SOURCE_DATE_EPOCH
OVERLAY_DIR=${OVERLAY_DIR:-}
KERNEL_VERSION=${KERNEL_VERSION:-7.1.1-g5df8e852ea72}
APPLY_Y700_FIRMWARE_FIXES=${APPLY_Y700_FIRMWARE_FIXES:-1}
APPLY_Y700_AUDIO_POLICY_FIXES=${APPLY_Y700_AUDIO_POLICY_FIXES:-1}
COMPRESS=${COMPRESS:-7z}
CHUNK_SIZE=${CHUNK_SIZE:-}
KEEP_RAW_IMAGE=${KEEP_RAW_IMAGE:-0}

mkdir -p "$OUTPUT_DIR"
work_dir=$(mktemp -d "$OUTPUT_DIR/.arch-rootfs-build.XXXXXX")
rootfs_dir="$work_dir/rootfs"
arch_import_stage="$work_dir/arch-import-stage"
arch_import_sources="$work_dir/arch-import-sources.tsv"
arch_camera_supplement_stage="$work_dir/arch-camera-supplement-stage"
rootfs_img="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.img"
build_info="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.BUILD-INFO.txt"
manifest="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.manifest"
mounted_rootfs=0
bind_mounts=()

cleanup() {
  set +e
  if [ "$mounted_rootfs" = 1 ]; then
    ci_unmount_tree "$rootfs_dir" ||
      ci_log "cleanup preserved mounted work tree for manual recovery: $work_dir"
  fi
  if ! ci_safe_rmtree "$work_dir" "$OUTPUT_DIR" .arch-rootfs-build.; then
    ci_log "cleanup refused to remove work tree: $work_dir"
  fi
}
trap cleanup EXIT

mount_bind() {
  local source=$1
  local target=$2
  install -d -m 0755 "$target"
  mount --bind "$source" "$target"
  bind_mounts+=("$target")
}

mount_chroot_runtime() {
  mount_bind /dev "$rootfs_dir/dev"
  install -d -m 0755 "$rootfs_dir/dev/pts"
  mount --bind /dev/pts "$rootfs_dir/dev/pts"
  bind_mounts+=("$rootfs_dir/dev/pts")
  install -d -m 0555 "$rootfs_dir/proc" "$rootfs_dir/sys"
  mount -t proc proc "$rootfs_dir/proc"
  bind_mounts+=("$rootfs_dir/proc")
  mount -t sysfs sysfs "$rootfs_dir/sys"
  bind_mounts+=("$rootfs_dir/sys")
  install -d -m 0755 "$rootfs_dir/run"
  mount -t tmpfs tmpfs "$rootfs_dir/run"
  bind_mounts+=("$rootfs_dir/run")
}

unmount_chroot_runtime() {
  local i target
  for ((i=${#bind_mounts[@]} - 1; i >= 0; i--)); do
    target=${bind_mounts[$i]}
    if mountpoint -q "$target"; then
      umount -- "$target" || ci_die "failed to unmount chroot runtime path: $target"
    fi
  done
  bind_mounts=()
}

rootfs_pids() {
  local root=$1
  local root_real pid procdir link target
  root_real=$(readlink -f "$root")

  for procdir in /proc/[0-9]*; do
    [ -d "$procdir" ] || continue
    pid=${procdir##*/}
    [ "$pid" = "$$" ] && continue
    [ "$pid" = "${BASHPID:-}" ] && continue

    for link in "$procdir/root" "$procdir/cwd" "$procdir/exe" "$procdir/fd"/*; do
      [ -e "$link" ] || [ -L "$link" ] || continue
      target=$(readlink "$link" 2>/dev/null || true)
      target=${target% (deleted)}
      case "$target" in
        "$root_real"|"$root_real"/*)
          printf '%s\n' "$pid"
          break
          ;;
      esac
    done
  done | sort -un
}

log_rootfs_pids() {
  local root=$1
  local pid comm cmdline
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    comm=$(cat "/proc/$pid/comm" 2>/dev/null || true)
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    ci_log "rootfs busy pid=$pid comm=${comm:-unknown} cmdline=${cmdline:-unknown}"
  done < <(rootfs_pids "$root")
}

terminate_rootfs_processes() {
  local root=$1
  local -a pids=()
  mapfile -t pids < <(rootfs_pids "$root")
  [ "${#pids[@]}" -gt 0 ] || return 0

  ci_log "terminating processes still using rootfs: ${pids[*]}"
  kill -TERM "${pids[@]}" 2>/dev/null || true
  sleep 2

  mapfile -t pids < <(rootfs_pids "$root")
  [ "${#pids[@]}" -gt 0 ] || return 0

  ci_log "force killing processes still using rootfs: ${pids[*]}"
  kill -KILL "${pids[@]}" 2>/dev/null || true
  sleep 1
}

stop_chroot_background_services() {
  [ -x "$rootfs_dir/usr/bin/gpgconf" ] || return 0
  arch_chroot /usr/bin/gpgconf --kill all || true
  arch_chroot /usr/bin/env GNUPGHOME=/etc/pacman.d/gnupg /usr/bin/gpgconf --kill all || true
}

finalize_rootfs_mount() {
  stop_chroot_background_services
  unmount_chroot_runtime
  terminate_rootfs_processes "$rootfs_dir"
  sync

  if ! ci_unmount_tree "$rootfs_dir"; then
    ci_log "rootfs unmount failed; remaining mounts:"
    findmnt -R "$rootfs_dir" || true
    log_rootfs_pids "$rootfs_dir"
    terminate_rootfs_processes "$rootfs_dir"
    ci_unmount_tree "$rootfs_dir" || ci_die "rootfs remains mounted: $rootfs_dir"
  fi
  mounted_rootfs=0
}

arch_chroot() {
  chroot "$rootfs_dir" /usr/bin/env -i \
    HOME=/root \
    TERM=xterm \
    http_proxy="${http_proxy:-}" \
    https_proxy="${https_proxy:-}" \
    HTTP_PROXY="${HTTP_PROXY:-}" \
    HTTPS_PROXY="${HTTPS_PROXY:-}" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin \
    "$@"
}

assert_pacman_remote_policy_tokens() {
  local context=$1
  local policy=$2

  grep -Fxq PackageRequired <<< "$policy" ||
    ci_die "$context does not require remote package signatures"
  grep -Fxq PackageTrustedOnly <<< "$policy" ||
    ci_die "$context accepts remote package signatures from untrusted keys"
  if grep -Eqx 'Package(Optional|Never|TrustAll)' <<< "$policy"; then
    ci_die "$context weakens remote package signature verification"
  fi
}

assert_pacman_local_policy_tokens() {
  local context=$1
  local policy=$2

  grep -Eqx 'Package(Optional|Required)' <<< "$policy" ||
    ci_die "$context has an unsupported local package signature policy"
  grep -Fxq PackageTrustedOnly <<< "$policy" ||
    ci_die "$context accepts local package signatures from untrusted keys"
  if grep -Eqx 'Package(Never|TrustAll)' <<< "$policy"; then
    ci_die "$context disables trusted local package signature handling"
  fi
}

assert_arch_remote_signature_policy() {
  local policy repo
  local -a repos=()

  policy=$(arch_chroot /usr/bin/pacman-conf SigLevel) ||
    ci_die "failed to resolve global pacman signature policy"
  assert_pacman_remote_policy_tokens "global pacman policy" "$policy"

  mapfile -t repos < <(arch_chroot /usr/bin/pacman-conf --repo-list)
  [ "${#repos[@]}" -gt 0 ] || ci_die "pacman has no configured repositories"
  for repo in "${repos[@]}"; do
    [ -n "$repo" ] || ci_die "pacman returned an empty repository name"
    policy=$(arch_chroot /usr/bin/pacman-conf -r "$repo" SigLevel) ||
      ci_die "failed to resolve pacman signature policy for repository: $repo"
    assert_pacman_remote_policy_tokens "pacman repository $repo" "$policy"
  done
}

assert_arch_local_signature_policy() {
  local policy

  policy=$(arch_chroot /usr/bin/pacman-conf LocalFileSigLevel) ||
    ci_die "failed to resolve local pacman signature policy"
  assert_pacman_local_policy_tokens "local pacman policy" "$policy"
}

apply_y700_firmware_fixes() {
  local root=$1

  ci_log "applying Y700 firmware path fixes"
  install -d -m 0755 "$root/lib/firmware/qcom" "$root/lib/firmware/qcom/sm8650" "$root/lib/firmware/qcom/vpu"

  copy_firmware_if_missing() {
    local source_rel=$1
    local dest_rel=$2
    [ -f "$root/$source_rel" ] || return 1
    if [ -e "$root/$dest_rel" ]; then
      return 0
    fi
    install -d -m 0755 "$(dirname "$root/$dest_rel")"
    install -m 0644 "$root/$source_rel" "$root/$dest_rel"
  }

  local src dst
  for src in \
    usr/lib/firmware/qcom/sm8650/lenovo/tb321fu/gen70900_zap.mbn \
    lib/firmware/qcom/sm8650/lenovo/tb321fu/gen70900_zap.mbn; do
    if copy_firmware_if_missing "$src" lib/firmware/qcom/gen70900_zap.mbn; then
      break
    fi
  done
  for src in \
    usr/lib/firmware/qcom-tb321fu/Lenovo-Y700-TB321FU-tplg.bin \
    lib/firmware/qcom-tb321fu/Lenovo-Y700-TB321FU-tplg.bin; do
    if copy_firmware_if_missing "$src" lib/firmware/qcom/sm8650/Lenovo-Y700-TB321FU-tplg.bin; then
      break
    fi
  done

  for src in \
    usr/lib/firmware/qcom/gen70900_aqe.fw \
    usr/lib/firmware/qcom/gen70900_sqe.fw \
    usr/lib/firmware/qcom/gmu_gen70900.bin \
    usr/lib/firmware/qcom/vpu/vpu33_p4.mbn; do
    dst=${src#usr/}
    copy_firmware_if_missing "$src" "$dst" || true
  done
}

verify_required_y700_payload() {
  local root=$1
  local required=(
    lib/firmware/qcom/gen70900_aqe.fw
    lib/firmware/qcom/gen70900_sqe.fw
    lib/firmware/qcom/gen70900_zap.mbn
    lib/firmware/qcom/gmu_gen70900.bin
    lib/firmware/qcom/sm8650/Lenovo-Y700-TB321FU-tplg.bin
    lib/firmware/qcom/vpu/vpu33_p4.mbn
    usr/lib/modules/$KERNEL_VERSION
    usr/lib/modules/$KERNEL_VERSION/modules.dep
    etc/systemd/system/y700-audio-card-guard.service
    usr/lib/systemd/system/qcom-sns-init.service
    etc/systemd/system/multi-user.target.wants/qcom-sns-init.service
    usr/libexec/qcom-sns/qcom-sns-init
    usr/share/qcom/sm8650/Lenovo/tb321fu/sensors/registry
    usr/share/qcom/sm8650/Lenovo/tb321fu/sensors/config
    usr/share/qcom/conf.d/tb321fu.yaml
    etc/systemd/system/multi-user.target.wants/iio-sensor-proxy.service
    etc/systemd/system/iio-sensor-proxy.service.d/99-qcom-sns.conf
    usr/lib/udev/rules.d/80-tb321fu-qcom-sns.rules
    usr/lib/systemd/system/tb321fu-haptics.service
    etc/systemd/system/multi-user.target.wants/tb321fu-haptics.service
    usr/libexec/tb321fu-haptics/bind-aw86937
    usr/lib/udev/rules.d/90-tb321fu-haptics.rules
    usr/lib/modules/$KERNEL_VERSION/extra/aw86937-haptics.ko
    usr/lib/firmware/haptic_ram.bin
    usr/lib/firmware/haptic_click.bin
    etc/ld.so.conf.d/y700-device.conf
    etc/ld.so.conf.d/y700-libcamera.conf
    opt/libcamera-y700/bin/cam
    opt/libcamera-y700/lib/aarch64-linux-gnu/libcamera.so.0.7.1
    opt/libcamera-y700/lib/aarch64-linux-gnu/libcamera-base.so.0.7.1
    opt/libcamera-y700/lib/aarch64-linux-gnu/libcamera/ipa/ipa_soft_simple.so
    opt/libcamera-y700/libexec/libcamera/soft_ipa_proxy
    opt/libcamera-y700/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so
    usr/lib/spa-0.2/libcamera/libspa-libcamera.so
    usr/lib/gstreamer-1.0/libgstlibcamera.so
    usr/lib/libaperture-0.so.0
    usr/lib/libaperture-0.so
    usr/lib/tb321fu/refresh-camera-compat-paths
    usr/share/libalpm/hooks/98-tb321fu-camera-compat.hook
    etc/systemd/user/pipewire.service.d/50-y700-libcamera-ipa.conf
    etc/systemd/user/pipewire.service.d/60-y700-libcamera-paths.conf
    etc/systemd/user/wireplumber.service.d/60-y700-libcamera-paths.conf
    etc/udev/rules.d/70-y700-camera-dma-heap.rules
    usr/share/applications/org.kde.plasma.keyboard.desktop
    etc/xdg/kwinrc
    home/$DEFAULT_USER_NAME/.config/kwinrc
    home/$DEFAULT_USER_NAME/.config/plasmakeyboardrc
  )
  if ci_bool "$INSTALL_FCITX5_CHINESE"; then
    required+=(home/$DEFAULT_USER_NAME/.config/fcitx5/profile)
  fi
  if ci_bool "$BUILD_TB321FU_GPU_SENSOR"; then
    required+=(usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_tb321fu_gpu.so)
    required+=(usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256)
    required+=(usr/lib/tb321fu/disable-stock-ksystemstats-gpu)
    required+=(usr/share/libalpm/hooks/99-tb321fu-disable-stock-ksystemstats-gpu.hook)
  fi

  local rel
  for rel in "${required[@]}"; do
    [ -e "$root/$rel" ] || [ -L "$root/$rel" ] || ci_die "missing required Y700/desktop payload: /$rel"
  done

  for rel in \
    opt/libcamera-y700/bin/cam \
    opt/libcamera-y700/bin/libcamera-bug-report \
    opt/libcamera-y700/libexec/libcamera/soft_ipa_proxy \
    usr/local/bin/y700-camera-env \
    usr/local/bin/y700-camera-cam \
    usr/local/bin/y700-camera-preview \
    usr/lib/tb321fu/refresh-camera-compat-paths; do
    [ "$(stat -c '%a' "$root/$rel")" = 755 ] || ci_die "camera executable has wrong mode: /$rel"
  done
  [ "$(readlink "$root/usr/lib/libaperture-0.so")" = libaperture-0.so.0 ] || ci_die "Arch libaperture compatibility symlink has wrong target"
  [ "$(readlink "$root/usr/lib/libaperture-0.so.0")" = /usr/lib/aarch64-linux-gnu/libaperture-0.so.0 ] || \
    ci_die "Arch libaperture ABI symlink has wrong target"
  [ "$(readlink "$root/usr/lib/gstreamer-1.0/libgstlibcamera.so")" = /opt/libcamera-y700/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so ] || ci_die "Arch GStreamer camera symlink has wrong target"
  grep -Fxq 'RestrictNamespaces=user net' "$root/etc/systemd/user/pipewire.service.d/50-y700-libcamera-ipa.conf" || ci_die "PipeWire camera namespace allowlist is missing"

  [ -n "$(find "$root/usr/lib/modules/$KERNEL_VERSION" -type f -name '*.ko*' -print -quit)" ] || \
    ci_die "no kernel modules found for $KERNEL_VERSION"

  local forbidden=(
    etc/systemd/system/iio-sensor-proxy.service.d/10-y700-ssc.conf
    etc/systemd/system/y700-sns-init.service
    etc/systemd/system/y700-aw86937-haptics.service
    etc/systemd/system/sddm.service.d/10-y700-audio-card-guard.conf
    usr/lib/systemd/system/y700-sns-init.service
    usr/lib/systemd/system/y700-aw86937-haptics.service
    etc/systemd/system/multi-user.target.wants/y700-sns-init.service
    etc/systemd/system/multi-user.target.wants/y700-aw86937-haptics.service
    etc/udev/rules.d/80-y700-iio-sensor-proxy.rules
    etc/udev/rules.d/90-y700-haptics.rules
    usr/lib/udev/rules.d/80-y700-iio-sensor-proxy.rules
    usr/lib/udev/rules.d/90-y700-haptics.rules
    usr/local/sbin/y700-sns-init.sh
    usr/local/sbin/y700-aw86937-bind
    usr/local/libexec/y700-iio-sensor-proxy
    usr/local/lib/y700-sns
    usr/local/share/y700-sns
    etc/udev/rules.d/70-y700-dma-heap.rules
    usr/local/libexec/y700-display-rotation-update
    usr/local/libexec/y700-display-rotation-dbus
    usr/local/bin/y700-display-rotation-sync
  )
  for rel in "${forbidden[@]}"; do
    [ ! -e "$root/$rel" ] && [ ! -L "$root/$rel" ] || ci_die "legacy Y700 payload must not be present: /$rel"
  done
}

apply_y700_audio_policy_fixes() {
  local root=$1
  local conf_dir="$root/etc/wireplumber/wireplumber.conf.d"
  local conf="$conf_dir/51-y700-alsa-auto.conf"
  local old_conf="$conf_dir/52-y700-headset-cleanup.conf"
  local old_script="$root/usr/share/wireplumber/scripts/y700/headset-cleanup.lua"
  local route_conf="$conf_dir/52-tb321fu-headset-route-reconcile.conf"
  local route_script="$root/usr/share/wireplumber/scripts/tb321fu/headset-route-reconcile.lua"
  local old_conf_sha old_script_sha

  ci_log "installing Y700 WirePlumber ALSA policy fix"
  install -d -m 0755 "$conf_dir"
  cat > "$conf" <<'CONF'
monitor.alsa.rules = [
  {
    matches = [
      {
        device.name = "alsa_card.platform-sound"
      }
    ]
    actions = {
      update-props = {
        api.alsa.use-acp = true
        api.alsa.use-ucm = true
        api.acp.auto-profile = true
        api.acp.auto-port = true
        api.alsa.split-enable = false
      }
    }
  }
]
CONF
  chmod 0644 "$conf"

  if [ -e "$old_conf" ] || [ -L "$old_conf" ] ||
     [ -e "$old_script" ] || [ -L "$old_script" ]; then
    [ -f "$old_conf" ] && [ ! -L "$old_conf" ] ||
      ci_die "tested WirePlumber headset cleanup config is missing or unsafe"
    [ -f "$old_script" ] && [ ! -L "$old_script" ] ||
      ci_die "tested WirePlumber headset cleanup script is missing or unsafe"
    old_conf_sha=$(sha256sum "$old_conf" | awk '{print $1}')
    [ "$old_conf_sha" = 5ea413266962a5bec45b6e287dc7e5bd6ab45112f4c2fd23810004e32b6328b2 ] ||
      ci_die "unrecognized tested WirePlumber headset cleanup config: $old_conf_sha"
    old_script_sha=$(sha256sum "$old_script" | awk '{print $1}')
    [ "$old_script_sha" = 6da046508f8965e05d9ec2d2b9e8b7bb7d556924f21f671b41b2451714f988c9 ] ||
      ci_die "unrecognized tested WirePlumber headset cleanup script: $old_script_sha"
    rm -f -- "$old_conf" "$old_script"
    rmdir --ignore-fail-on-non-empty "$(dirname "$old_script")" 2>/dev/null || true
  fi

  [ ! -L "$route_conf" ] || ci_die "TB321FU route reconcile config must not be a symlink"
  [ ! -L "$route_script" ] || ci_die "TB321FU route reconcile script must not be a symlink"
  install -D -m 0644 "$SCRIPT_DIR/payloads/52-tb321fu-headset-route-reconcile.conf" \
    "$route_conf"
  install -D -m 0644 "$SCRIPT_DIR/payloads/tb321fu-headset-route-reconcile.lua" \
    "$route_script"

  [ ! -e "$old_conf" ] && [ ! -L "$old_conf" ] ||
    ci_die "legacy node-presence WirePlumber cleanup config remains in the rootfs"
  [ ! -e "$old_script" ] && [ ! -L "$old_script" ] ||
    ci_die "legacy node-presence WirePlumber cleanup script remains in the rootfs"
  cmp -s "$SCRIPT_DIR/payloads/52-tb321fu-headset-route-reconcile.conf" "$route_conf" ||
    ci_die "TB321FU WirePlumber route reconcile config is missing or changed"
  cmp -s "$SCRIPT_DIR/payloads/tb321fu-headset-route-reconcile.lua" "$route_script" ||
    ci_die "TB321FU WirePlumber route reconcile script is missing or changed"
}

remove_legacy_y700_payload() {
  local root=$1

  rm -f \
    "$root/etc/systemd/system/iio-sensor-proxy.service.d/10-y700-ssc.conf" \
    "$root/etc/systemd/system/y700-sns-init.service" \
    "$root/etc/systemd/system/y700-aw86937-haptics.service" \
    "$root/etc/systemd/system/smartmontools.service" \
    "$root/etc/systemd/system/sddm.service.d/10-y700-audio-card-guard.conf" \
    "$root/usr/lib/systemd/system/y700-sns-init.service" \
    "$root/usr/lib/systemd/system/y700-aw86937-haptics.service" \
    "$root/etc/udev/rules.d/80-y700-iio-sensor-proxy.rules" \
    "$root/etc/udev/rules.d/90-y700-haptics.rules" \
    "$root/usr/lib/udev/rules.d/80-y700-iio-sensor-proxy.rules" \
    "$root/usr/lib/udev/rules.d/90-y700-haptics.rules" \
    "$root/usr/local/sbin/y700-sns-init.sh" \
    "$root/usr/local/libexec/y700-iio-sensor-proxy" \
    "$root/usr/local/sbin/y700-aw86937-bind"
  rm -rf \
    "$root/usr/local/lib/y700-sns" \
    "$root/usr/local/share/y700-sns"

  if [ -d "$root/etc/systemd/system/multi-user.target.wants" ]; then
    rm -f \
      "$root/etc/systemd/system/multi-user.target.wants/y700-sns-init.service" \
      "$root/etc/systemd/system/multi-user.target.wants/y700-aw86937-haptics.service"
  fi
}

validate_tb321fu_compat_firmware_stage() {
  local archive=$1
  local stage=$2
  local expected="$work_dir/tb321fu-compat-firmware.sha256"
  local archive_sha actual_files expected_files member mode leftover target

  [ "$(basename "$archive")" = y700-compat1-extra-rootfs-overlay.tar.gz ] || \
    ci_die "unexpected nested device overlay: $(basename "$archive")"
  archive_sha=$(sha256sum "$archive" | awk '{print $1}')
  [ "$archive_sha" = a3f55ddee04aac465465c2ff8fcddebc1b65b7e7d3af82e5e5c8ce0a4766c414 ] || \
    ci_die "TB321FU compat overlay checksum mismatch: $archive_sha"
  cat > "$expected" <<'COMPAT_SHA256'
25237c161d727b8ea92b4beb837a31651b44ea78bfc34d95672af8f346a45825  ./usr/lib/firmware/qcom/gen70900_aqe.fw
a739a1ef14e4418c5a1f1e1da444deb71aeeb4a31370ab41a4dddf378ab5683d  ./usr/lib/firmware/qcom/gen70900_sqe.fw
9685f62c42543befcaee68d25355e16bf55cdb0d573bddcc9f6633f59eec3f72  ./usr/lib/firmware/qcom/gmu_gen70900.bin
8166b1fde9725547bd07eba4add22f442dc938f17274fbf358dbdcfc88ec5f31  ./usr/lib/firmware/qcom/vpu/vpu33_p4.mbn
COMPAT_SHA256
  leftover=$(find "$stage" -mindepth 1 ! -type d ! -type f -print -quit)
  [ -z "$leftover" ] || ci_die "unsupported special member in TB321FU compat overlay: $leftover"
  actual_files=$(cd "$stage" && find . -type f -print | LC_ALL=C sort)
  expected_files=$(awk '{print $2}' "$expected" | LC_ALL=C sort)
  [ "$actual_files" = "$expected_files" ] || ci_die "TB321FU compat overlay member list mismatch"
  (cd "$stage" && sha256sum -c "$expected") || ci_die "TB321FU compat firmware content mismatch"
  while IFS= read -r member; do
    mode=$(stat -c '%a' "$stage/${member#./}")
    [ "$mode" = 644 ] || ci_die "unsafe TB321FU compat firmware mode $mode: $member"
    target="$rootfs_dir/${member#./}"
    if [ -e "$target" ] && ! cmp -s "$stage/${member#./}" "$target"; then
      ci_die "TB321FU compat firmware collides with different existing content: $member"
    fi
  done <<< "$expected_files"

  install -D -m 0644 "$expected" "$stage/usr/share/tb321fu/imported-compat-firmware.sha256"
  cat > "$stage/usr/share/tb321fu/imported-compat-firmware.provenance" <<PROVENANCE
source_archive=$(basename "$archive")
source_archive_sha256=$archive_sha
ownership=staged-for-native-pacman-package
PROVENANCE
  chmod 0644 "$stage/usr/share/tb321fu/imported-compat-firmware.provenance"
  rm -f -- "$expected"
}

remove_legacy_camera_payload() {
  local root=$1

  rm -f \
    "$root/etc/udev/rules.d/70-y700-dma-heap.rules" \
    "$root/etc/y700-camera-display-transform-mode" \
    "$root/etc/y700-camera-display-rotation-base" \
    "$root/etc/systemd/user/y700-display-rotation-update.path" \
    "$root/etc/systemd/user/y700-display-rotation-update.service" \
    "$root/etc/systemd/user/y700-display-rotation-dbus.service" \
    "$root/etc/systemd/user/y700-display-rotation-sync.service" \
    "$root/usr/local/libexec/y700-display-rotation-update" \
    "$root/usr/local/libexec/y700-display-rotation-dbus" \
    "$root/usr/local/bin/y700-display-rotation-sync"
  rm -rf "$root/run/y700-camera-display-rotation"
}

stage_arch_camera_supplement() {
  local root=$1
  local source_library="$root/usr/lib/aarch64-linux-gnu/libaperture-0.so.0"
  local source_link="$root/usr/lib/aarch64-linux-gnu/libaperture-0.so"
  local destination_library="$arch_camera_supplement_stage/usr/lib/aarch64-linux-gnu/libaperture-0.so.0"
  local destination_link="$arch_camera_supplement_stage/usr/lib/aarch64-linux-gnu/libaperture-0.so"

  if [ -e "$source_library" ] || [ -L "$source_library" ]; then
    [ -f "$source_library" ] && [ ! -L "$source_library" ] || \
      ci_die "imported libaperture ABI member is not a regular file"
    install -d -m 0755 "$(dirname "$destination_library")"
    if [ -e "$destination_library" ] || [ -L "$destination_library" ]; then
      [ -f "$destination_library" ] && [ ! -L "$destination_library" ] && \
        cmp -s "$source_library" "$destination_library" || \
        ci_die "conflicting imported libaperture ABI payloads"
    else
      install -m 0644 "$source_library" "$destination_library"
    fi
    rm -f "$source_library"
  fi
  if [ -e "$source_link" ] || [ -L "$source_link" ]; then
    [ -L "$source_link" ] || ci_die "imported libaperture development member is not a symlink"
    [ "$(readlink "$source_link")" = libaperture-0.so.0 ] || \
      ci_die "imported libaperture symlink has an unsafe target"
    install -d -m 0755 "$(dirname "$destination_link")"
    if [ -e "$destination_link" ] || [ -L "$destination_link" ]; then
      [ -L "$destination_link" ] && \
        [ "$(readlink "$destination_link")" = libaperture-0.so.0 ] || \
        ci_die "conflicting imported libaperture development symlinks"
    else
      ln -s libaperture-0.so.0 "$destination_link"
    fi
    rm -f "$source_link"
  fi
}

remove_arch_native_camera_package_paths() {
  local root=$1

  rm -rf \
    "$root/opt/libcamera-y700" \
    "$root/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera" \
    "$root/usr/lib/spa-0.2/libcamera"
  rm -f \
    "$root/etc/ld.so.conf.d/y700-device.conf" \
    "$root/etc/ld.so.conf.d/y700-libcamera.conf" \
    "$root/etc/systemd/user/pipewire.service.d/50-y700-libcamera-ipa.conf" \
    "$root/etc/systemd/user/pipewire.service.d/60-y700-libcamera-paths.conf" \
    "$root/etc/systemd/user/wireplumber.service.d/60-y700-libcamera-paths.conf" \
    "$root/etc/udev/rules.d/70-y700-camera-dma-heap.rules" \
    "$root/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so" \
    "$root/usr/lib/aarch64-linux-gnu/libaperture-0.so" \
    "$root/usr/lib/aarch64-linux-gnu/libaperture-0.so.0" \
    "$root/usr/lib/gstreamer-1.0/libgstlibcamera.so" \
    "$root/usr/lib/libaperture-0.so" \
    "$root/usr/lib/libaperture-0.so.0" \
    "$root/usr/lib/tb321fu/refresh-camera-compat-paths" \
    "$root/usr/share/libalpm/hooks/98-tb321fu-camera-compat.hook" \
    "$root/usr/local/bin/y700-camera-env" \
    "$root/usr/local/bin/y700-camera-cam" \
    "$root/usr/local/bin/y700-camera-preview"
}

sanitize_arch_import_stage() {
  local stage=$1

  rm -f \
    "$stage/BUILD-INFO.txt" \
    "$stage/SHA256SUMS" \
    "$stage/SHA256SUMS.txt" \
    "$stage/Y700-ROOTFS-OVERLAY-MANIFEST.tsv"
  if [ -d "$stage/usr/lib/modules" ]; then
    find "$stage/usr/lib/modules" -mindepth 2 -maxdepth 2 -type l \
      \( -name build -o -name source \) -delete
  fi
  ci_normalize_system_payload_modes "$stage"
  ci_assert_normalized_system_payload_modes "$stage"
}

discard_arch_import_source_stage() {
  local stage=$1
  local stage_real work_real
  stage_real=$(realpath -m "$stage")
  work_real=$(realpath -m "$work_dir")
  case "$stage_real" in
    "$work_real"/*-stage-*.d|"$work_real"/device-overlay-stage-*.d) ;;
    *) ci_die "refusing to remove unbounded Arch import staging path: $stage_real" ;;
  esac
  mountpoint -q "$stage_real" && \
    ci_die "refusing to remove mounted Arch import staging path: $stage_real"
  rm -rf --one-file-system -- "$stage_real"
}

merge_stage_to_arch_import() {
  local stage=$1
  local source_id=$2
  local special unreadable path relative target source_meta target_meta

  [[ $source_id =~ ^[A-Za-z0-9._:+-]+$ ]] || ci_die "unsafe Arch import source id: $source_id"
  stage_arch_camera_supplement "$stage"
  remove_arch_native_camera_package_paths "$stage"
  sanitize_arch_import_stage "$stage"
  special=$(find "$stage" -mindepth 1 ! -type d ! -type f ! -type l -print -quit)
  [ -z "$special" ] || ci_die "unsupported special member in Arch import: $special"
  unreadable=$(find "$stage" -type f ! -perm -0004 -print -quit)
  [ -z "$unreadable" ] || ci_die "Arch import is not readable by the package builder: $unreadable"
  unreadable=$(find "$stage" -type d ! -perm -0001 -print -quit)
  [ -z "$unreadable" ] || ci_die "Arch import directory is not traversable by the package builder: $unreadable"

  install -d -m 0755 "$arch_import_stage"
  while IFS= read -r -d '' path; do
    relative=${path#"$stage"/}
    target="$arch_import_stage/$relative"
    if [ -e "$target" ] || [ -L "$target" ]; then
      if [ -L "$path" ] && [ -L "$target" ]; then
        [ "$(readlink "$path")" = "$(readlink "$target")" ] || \
          ci_die "conflicting Arch import symlink: $relative"
      elif [ -f "$path" ] && [ -f "$target" ] && [ ! -L "$target" ]; then
        cmp -s "$path" "$target" || ci_die "conflicting Arch import file: $relative"
        source_meta=$(stat -c '%u:%g:%a' "$path")
        target_meta=$(stat -c '%u:%g:%a' "$target")
        [ "$source_meta" = "$target_meta" ] || \
          ci_die "conflicting Arch import file metadata: $relative"
      elif [ -d "$path" ] && [ -d "$target" ] && [ ! -L "$target" ]; then
        source_meta=$(stat -c '%u:%g:%a' "$path")
        target_meta=$(stat -c '%u:%g:%a' "$target")
        [ "$source_meta" = "$target_meta" ] || \
          ci_die "conflicting Arch import directory metadata: $relative"
      else
        ci_die "conflicting Arch import member type: $relative"
      fi
    fi
  done < <(find "$stage" -mindepth 1 -print0 | sort -z)

  rsync -aH --numeric-ids "$stage"/ "$arch_import_stage"/
  if [ ! -f "$arch_import_sources" ]; then
    printf 'source_id\n' > "$arch_import_sources"
  fi
  printf '%s\n' "$source_id" >> "$arch_import_sources"
  discard_arch_import_source_stage "$stage"
}

install_arch_import_package() {
  local package_name=tb321fu-imported-release-payload
  local package_hash package_version package_file build_user=tb321fu-pkgbuild
  local build_dir=/run/tb321fu-import-package-build
  local bind_path=/run/tb321fu-import-stage
  local host_build_dir="$work_dir/arch-import-package-build"
  local host_build_bind="$rootfs_dir$build_dir"
  local host_bind_path="$rootfs_dir$bind_path"
  local payload_manifest="$work_dir/arch-import-payload.sha256"
  local target
  local -a built_packages=() remaining_binds=()

  [ -d "$arch_import_stage" ] || return 0
  [ -n "$(find "$arch_import_stage" -mindepth 1 -print -quit)" ] || return 0

  if [ -d "$arch_import_stage/usr/lib/modules/$KERNEL_VERSION" ]; then
    depmod -b "$arch_import_stage" "$KERNEL_VERSION"
  fi

  (cd "$arch_import_stage" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) > "$payload_manifest"
  package_hash=$(
    {
      (cd "$arch_import_stage" && find . -xdev -printf '%y\t%U\t%G\t%m\t%s\t%p\t%l\0' | sort -z)
      sha256sum "$payload_manifest" "$arch_import_sources"
    } | sha256sum | awk '{print $1}'
  )
  package_version="1.${package_hash:0:16}"
  install -D -m 0644 "$payload_manifest" \
    "$arch_import_stage/usr/share/tb321fu/imported-release-payload.sha256"
  install -D -m 0644 "$arch_import_sources" \
    "$arch_import_stage/usr/share/tb321fu/imported-release-sources.tsv"

  [ -z "$(find "$arch_import_stage" -type f ! -perm -0004 -print -quit)" ] || \
    ci_die "final Arch import is not readable by the package builder"
  [ -z "$(find "$arch_import_stage" -type d ! -perm -0001 -print -quit)" ] || \
    ci_die "final Arch import directory is not traversable by the package builder"
  if arch_chroot /usr/bin/id -u "$build_user" >/dev/null 2>&1; then
    ci_die "reserved Arch package-build account already exists: $build_user"
  fi

  install -d -m 0755 "$host_build_dir" "$host_build_bind" "$host_bind_path"
  mount_bind "$host_build_dir" "$host_build_bind"
  mount_bind "$arch_import_stage" "$host_bind_path"
  arch_chroot /usr/bin/useradd --system --no-create-home --home-dir "$build_dir" \
    --shell /usr/bin/nologin "$build_user"
  chown -R "$(arch_chroot /usr/bin/id -u "$build_user")":"$(arch_chroot /usr/bin/id -g "$build_user")" \
    "$host_build_dir"
  cat > "$host_build_dir/PKGBUILD" <<PKGBUILD
pkgname=$package_name
pkgver=$package_version
pkgrel=1
pkgdesc='Content-locked TB321FU payload imported from the tested Ubuntu release packages'
arch=('aarch64')
url='https://github.com/GUF296/tb321fu-linux'
license=('custom')
options=('!strip' 'docs' 'libtool' 'emptydirs' '!zipman' '!purge' '!debug' '!lto')
source=()

package() {
  cp -a $bind_path/. "\$pkgdir/"
}
PKGBUILD
  chown "$(arch_chroot /usr/bin/id -u "$build_user")":"$(arch_chroot /usr/bin/id -g "$build_user")" \
    "$host_build_dir/PKGBUILD"

  arch_chroot /usr/bin/runuser -u "$build_user" -- /usr/bin/env \
    HOME="$build_dir" \
    PKGDEST="$build_dir" \
    SRCDEST="$build_dir/srcdest" \
    BUILDDIR="$build_dir/build" \
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}" \
    /usr/bin/makepkg --noconfirm --nodeps --cleanbuild --clean --force

  while IFS= read -r -d '' package_file; do
    built_packages+=("$package_file")
  done < <(find "$host_build_dir" -maxdepth 1 -type f -name "$package_name-*.pkg.tar.*" -print0 | sort -z)
  [ "${#built_packages[@]}" -eq 1 ] || \
    ci_die "expected one native Arch import package, found ${#built_packages[@]}"
  package_file=${built_packages[0]}
  assert_arch_local_signature_policy
  arch_chroot /usr/bin/pacman -U --noconfirm "$build_dir/$(basename "$package_file")"
  arch_chroot /usr/bin/pacman -Q "$package_name" | \
    grep -Fx "$package_name $package_version-1" >/dev/null || \
    ci_die "native Arch import package identity mismatch"
  arch_chroot /usr/bin/pacman -Qkk "$package_name" >/dev/null || \
    ci_die "native Arch import package failed its immediate file check"
  printf '%s=%s-1\n' "$package_name" "$package_version" >> \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.packages"

  arch_chroot /usr/bin/userdel "$build_user"
  umount -- "$host_bind_path" || ci_die "failed to unmount Arch import staging bind"
  umount -- "$host_build_bind" || ci_die "failed to unmount Arch import build bind"
  for target in "${bind_mounts[@]}"; do
    case "$target" in
      "$host_bind_path"|"$host_build_bind") ;;
      *) remaining_binds+=("$target") ;;
    esac
  done
  bind_mounts=("${remaining_binds[@]}")
  rmdir "$host_bind_path" "$host_build_bind"
  rm -rf --one-file-system -- "$host_build_dir"
  rm -rf --one-file-system -- "$arch_import_stage"
  rm -f -- "$payload_manifest" "$arch_import_sources"
  ci_log "installed pacman-owned TB321FU release payload: $package_name $package_version-1"
}

install_arch_native_stage_package() {
  local package_name=$1
  local package_description=$2
  local stage=$3
  local dependencies_name=$4
  local provides_name=$5
  local conflicts_name=$6
  local replaces_name=$7
  local install_script=${8:-}
  local package_hash package_version package_file build_user=tb321fu-pkgbuild
  local build_dir="/run/${package_name}-build"
  local bind_path="/run/${package_name}-stage"
  local host_build_dir="$work_dir/${package_name}-build"
  local host_build_bind="$rootfs_dir$build_dir"
  local host_bind_path="$rootfs_dir$bind_path"
  local relation target
  local -a built_packages=() remaining_binds=()
  local -n dependencies=$dependencies_name
  local -n provides=$provides_name
  local -n conflicts=$conflicts_name
  local -n replaces=$replaces_name

  [[ $package_name =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || ci_die "unsafe native Arch package name: $package_name"
  [[ $package_description != *$'\n'* && $package_description != *$'\r'* && $package_description != *\'* ]] || \
    ci_die "native Arch package description contains unsafe control or quoting characters: $package_name"
  [ -d "$stage" ] || ci_die "native Arch package stage is missing: $stage"
  case "$(realpath -m "$stage")" in
    "$(realpath -m "$work_dir")"/*) ;;
    *) ci_die "native Arch package stage is outside the build workspace: $stage" ;;
  esac
  [ -n "$(find "$stage" -mindepth 1 -print -quit)" ] || ci_die "native Arch package stage is empty: $package_name"
  for relation in "${dependencies[@]}" "${provides[@]}" "${conflicts[@]}" "${replaces[@]}"; do
    [[ $relation =~ ^[A-Za-z0-9@._+:-]+([\<\>\=]+[A-Za-z0-9@._+~:-]+)?$ ]] || \
      ci_die "unsafe native Arch package relation for $package_name: $relation"
  done
  if [ -n "$install_script" ]; then
    [ -f "$install_script" ] || ci_die "native Arch install script is missing: $install_script"
  fi

  ci_normalize_system_payload_modes "$stage"
  ci_assert_normalized_system_payload_modes "$stage"
  package_hash=$(
    {
      (cd "$stage" && find . -xdev -printf '%y\t%U\t%G\t%m\t%s\t%p\t%l\0' | sort -z)
      (cd "$stage" && find . -xdev -type f -print0 | sort -z | xargs -0 -r sha256sum)
      printf '\0name=%s\ndescription=%s\n' "$package_name" "$package_description"
      printf 'depends=%s\n' "${dependencies[*]}"
      printf 'provides=%s\n' "${provides[*]}"
      printf 'conflicts=%s\n' "${conflicts[*]}"
      printf 'replaces=%s\n' "${replaces[*]}"
      if [ -n "$install_script" ]; then
        sha256sum "$install_script" | awk '{print "install=" $1}'
      fi
    } | sha256sum | awk '{print $1}'
  )
  package_version="1.${package_hash:0:16}"

  if arch_chroot /usr/bin/id -u "$build_user" >/dev/null 2>&1; then
    ci_die "reserved Arch package-build account already exists: $build_user"
  fi
  install -d -m 0755 "$host_build_dir" "$host_build_bind" "$host_bind_path"
  mount_bind "$host_build_dir" "$host_build_bind"
  mount_bind "$stage" "$host_bind_path"
  arch_chroot /usr/bin/useradd --system --no-create-home --home-dir "$build_dir" \
    --shell /usr/bin/nologin "$build_user"
  chown -R "$(arch_chroot /usr/bin/id -u "$build_user")":"$(arch_chroot /usr/bin/id -g "$build_user")" \
    "$host_build_dir"

  {
    printf 'pkgname=%s\n' "$package_name"
    printf 'pkgver=%s\n' "$package_version"
    printf 'pkgrel=1\n'
    printf "pkgdesc='%s'\n" "$package_description"
    printf "arch=('aarch64')\n"
    printf "url='https://github.com/GUF296/tb321fu-linux'\n"
    printf "license=('custom')\n"
    printf "options=('!strip' 'docs' 'libtool' 'emptydirs' '!zipman' '!purge' '!debug' '!lto')\n"
    printf 'depends=('; for relation in "${dependencies[@]}"; do printf " '%s'" "$relation"; done; printf ' )\n'
    printf 'provides=('; for relation in "${provides[@]}"; do printf " '%s'" "$relation"; done; printf ' )\n'
    printf 'conflicts=('; for relation in "${conflicts[@]}"; do printf " '%s'" "$relation"; done; printf ' )\n'
    printf 'replaces=('; for relation in "${replaces[@]}"; do printf " '%s'" "$relation"; done; printf ' )\n'
    if [ -n "$install_script" ]; then
      printf 'install=%s.install\n' "$package_name"
    fi
    printf 'source=()\n\n'
    printf 'package() {\n  cp -a %s/. "$pkgdir/"\n}\n' "$bind_path"
  } > "$host_build_dir/PKGBUILD"
  if [ -n "$install_script" ]; then
    install -m 0644 "$install_script" "$host_build_dir/$package_name.install"
  fi
  chown -R "$(arch_chroot /usr/bin/id -u "$build_user")":"$(arch_chroot /usr/bin/id -g "$build_user")" \
    "$host_build_dir"

  arch_chroot /usr/bin/runuser -u "$build_user" -- /usr/bin/env \
    HOME="$build_dir" \
    PKGDEST="$build_dir" \
    SRCDEST="$build_dir/srcdest" \
    BUILDDIR="$build_dir/build" \
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}" \
    /usr/bin/makepkg --noconfirm --nodeps --cleanbuild --clean --force

  while IFS= read -r -d '' package_file; do
    built_packages+=("$package_file")
  done < <(find "$host_build_dir" -maxdepth 1 -type f -name "$package_name-*.pkg.tar.*" -print0 | sort -z)
  [ "${#built_packages[@]}" -eq 1 ] || \
    ci_die "expected one native Arch package for $package_name, found ${#built_packages[@]}"
  package_file=${built_packages[0]}
  assert_arch_local_signature_policy
  arch_chroot /usr/bin/pacman -U --noconfirm "$build_dir/$(basename "$package_file")"
  arch_chroot /usr/bin/pacman -Q "$package_name" | \
    grep -Fx "$package_name $package_version-1" >/dev/null || \
    ci_die "native Arch package identity mismatch: $package_name"
  arch_chroot /usr/bin/pacman -Qkk "$package_name" >/dev/null || \
    ci_die "native Arch package failed its immediate file check: $package_name"
  find "$OUTPUT_DIR" -maxdepth 1 -type f \
    -name "${OUTPUT_PREFIX}-${package_name}-*.pkg.tar.*" -delete
  install -m 0644 "$package_file" \
    "$OUTPUT_DIR/${OUTPUT_PREFIX}-$(basename "$package_file")"

  arch_chroot /usr/bin/userdel "$build_user"
  umount -- "$host_bind_path" || ci_die "failed to unmount native Arch package staging bind: $package_name"
  umount -- "$host_build_bind" || ci_die "failed to unmount native Arch package build bind: $package_name"
  for target in "${bind_mounts[@]}"; do
    case "$target" in
      "$host_bind_path"|"$host_build_bind") ;;
      *) remaining_binds+=("$target") ;;
    esac
  done
  bind_mounts=("${remaining_binds[@]}")
  rmdir "$host_bind_path" "$host_build_bind"
  rm -rf --one-file-system -- "$host_build_dir" "$stage"
  ci_log "installed native Arch package: $package_name $package_version-1"
}

enable_y700_device_services() {
  local root=$1

  install -d -m 0755 "$root/etc/systemd/system/multi-user.target.wants"
  for service in y700-audio-card-guard.service; do
    if [ -f "$root/etc/systemd/system/$service" ]; then
      grep -q '^Restart=on-failure$' "$root/etc/systemd/system/$service" || \
        ci_die "audio card guard does not retry asynchronously"
      ln -sfn "/etc/systemd/system/$service" \
        "$root/etc/systemd/system/multi-user.target.wants/$service"
    fi
  done

  if [ -f "$root/usr/lib/systemd/system/qcom-sns-init.service" ]; then
    ln -sfn /usr/lib/systemd/system/qcom-sns-init.service \
      "$root/etc/systemd/system/multi-user.target.wants/qcom-sns-init.service"
  fi
  if [ -f "$root/usr/lib/systemd/system/tb321fu-haptics.service" ]; then
    ln -sfn /usr/lib/systemd/system/tb321fu-haptics.service \
      "$root/etc/systemd/system/multi-user.target.wants/tb321fu-haptics.service"
  fi
  if [ -f "$root/usr/lib/systemd/system/iio-sensor-proxy.service" ]; then
    ln -sfn /usr/lib/systemd/system/iio-sensor-proxy.service \
      "$root/etc/systemd/system/multi-user.target.wants/iio-sensor-proxy.service"
  fi
}

extract_device_payload_dir() {
  local payload_dir=$1
  local deb overlay stage

  if [ -z "$(find "$payload_dir" -type f \( -name '*.deb' -o -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.tar.xz' -o -name '*.tar.zst' \) -print -quit)" ]; then
    ci_die "device payload directory has no supported payload files: $payload_dir"
  fi

  while IFS= read -r -d '' deb; do
    ci_log "extracting device deb data: $(basename "$deb")"
    stage="$work_dir/device-stage-$(basename "$deb").d"
    rm -rf "$stage"
    mkdir -p "$stage"
    dpkg-deb -x "$deb" "$stage"
    remove_legacy_y700_payload "$stage"
    remove_legacy_camera_payload "$stage"
    merge_stage_to_arch_import "$stage" "deb:$(basename "$deb"):$(sha256sum "$deb" | awk '{print $1}')"
  done < <(find "$payload_dir" -type f -name '*.deb' -print0 | sort -z)

  while IFS= read -r -d '' overlay; do
    case "$overlay" in
      *.tar|*.tar.gz|*.tgz|*.tar.xz|*.tar.zst)
        ci_log "extracting device overlay: $(basename "$overlay")"
        stage="$work_dir/device-overlay-stage-$(basename "$overlay").d"
        rm -rf "$stage"
        mkdir -p "$stage"
        ci_extract_archive "$overlay" "$stage"
        validate_tb321fu_compat_firmware_stage "$overlay" "$stage"
        remove_legacy_y700_payload "$stage"
        remove_legacy_camera_payload "$stage"
        merge_stage_to_arch_import "$stage" "overlay:$(basename "$overlay"):$(sha256sum "$overlay" | awk '{print $1}')"
        ;;
    esac
  done < <(find "$payload_dir" -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.tar.xz' -o -name '*.tar.zst' \) -print0 | sort -z)
}

apply_device_payloads() {
  if [ -n "$DEVICE_DEB_ARCHIVE" ]; then
    local archive="$work_dir/device-payload.archive"
    local extract="$work_dir/device-payload"
    ci_log "downloading device payload archive: $DEVICE_DEB_ARCHIVE"
    ci_download "$DEVICE_DEB_ARCHIVE" "$archive" "$DEVICE_DEB_ARCHIVE_SHA256"
    ci_extract_archive "$archive" "$extract"
    extract_device_payload_dir "$extract"
  fi

  if [ -n "$DEVICE_DEB_DIR" ]; then
    ci_log "applying device payload directory: $DEVICE_DEB_DIR"
    extract_device_payload_dir "$DEVICE_DEB_DIR"
  fi
}

extract_tb321fu_deb_payload_dir() {
  local payload_dir=$1
  local label=$2
  local deb stage found=0

  while IFS= read -r -d '' deb; do
    found=1
    ci_log "extracting $label deb data: $(basename "$deb")"
    stage="$work_dir/${label}-stage-$(basename "$deb").d"
    rm -rf "$stage"
    mkdir -p "$stage"
    dpkg-deb -x "$deb" "$stage"
    remove_legacy_y700_payload "$stage"
    remove_legacy_camera_payload "$stage"
    merge_stage_to_arch_import "$stage" "deb:$(basename "$deb"):$(sha256sum "$deb" | awk '{print $1}')"
  done < <(find "$payload_dir" -type f -name '*.deb' -print0 | sort -z)

  [ "$found" = 1 ] || ci_die "$label payload directory has no .deb files: $payload_dir"
}

apply_tb321fu_deb_payloads() {
  local archive extract

  if [ -n "$SENSOR_DEB_ARCHIVE" ]; then
    archive="$work_dir/sensor-payload.archive"
    extract="$work_dir/sensor-payload"
    ci_log "downloading TB321FU sensor package archive: $SENSOR_DEB_ARCHIVE"
    ci_download "$SENSOR_DEB_ARCHIVE" "$archive" "$SENSOR_DEB_ARCHIVE_SHA256"
    ci_extract_archive "$archive" "$extract"
    extract_tb321fu_deb_payload_dir "$extract" sensor
  fi
  if [ -n "$SENSOR_DEB_DIR" ]; then
    extract_tb321fu_deb_payload_dir "$SENSOR_DEB_DIR" sensor
  fi

  if [ -n "$HAPTICS_DEB_ARCHIVE" ]; then
    archive="$work_dir/haptics-payload.archive"
    extract="$work_dir/haptics-payload"
    ci_log "downloading TB321FU haptics package archive: $HAPTICS_DEB_ARCHIVE"
    ci_download "$HAPTICS_DEB_ARCHIVE" "$archive" "$HAPTICS_DEB_ARCHIVE_SHA256"
    ci_extract_archive "$archive" "$extract"
    extract_tb321fu_deb_payload_dir "$extract" haptics
  fi
  if [ -n "$HAPTICS_DEB_DIR" ]; then
    extract_tb321fu_deb_payload_dir "$HAPTICS_DEB_DIR" haptics
  fi
}

find_camera_source_root() {
  local root=$1 found candidate
  local -a markers=() candidates=()
  local -A seen=()

  if [ -d "$root/rootfs-overlay/opt/libcamera-y700" ] && \
     [ -f "$root/rootfs-overlay/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera/libspa-libcamera.so" ]; then
    printf '%s\n' "$root/rootfs-overlay"
    return 0
  fi
  if [ -d "$root/opt/libcamera-y700" ] && \
     [ -f "$root/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera/libspa-libcamera.so" ]; then
    printf '%s\n' "$root"
    return 0
  fi

  mapfile -d '' -t markers < <(find "$root" -type f \
    -path '*/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera/libspa-libcamera.so' -print0 | sort -z)
  for found in "${markers[@]}"; do
    candidate=${found%/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera/libspa-libcamera.so}
    [ -d "$candidate/opt/libcamera-y700" ] || continue
    if [ -z "${seen[$candidate]+set}" ]; then
      seen[$candidate]=1
      candidates+=("$candidate")
    fi
  done
  case ${#candidates[@]} in
    0) return 1 ;;
    1) printf '%s\n' "${candidates[0]}" ;;
    *)
      printf 'ambiguous camera source roots:\n' >&2
      printf '  %s\n' "${candidates[@]}" >&2
      return 2
      ;;
  esac
}

apply_tb321fu_camera_stack() {
  local source_root archive extract stage
  local -a camera_dependencies=(
    glibc gcc-libs libdrm libyaml gnutls libunwind libcamera
    gstreamer gst-plugins-base-libs pipewire
  )
  local -a camera_provides=(gst-plugin-libcamera y700-camera-stack)
  local -a camera_conflicts=(gst-plugin-libcamera y700-camera-stack)
  local -a camera_replaces=(gst-plugin-libcamera y700-camera-stack)

  if [ -n "$CAMERA_STACK_ARCHIVE" ]; then
    archive="$work_dir/camera-stack.archive"
    extract="$work_dir/camera-stack"
    ci_log "downloading TB321FU camera stack archive: $CAMERA_STACK_ARCHIVE"
    ci_download "$CAMERA_STACK_ARCHIVE" "$archive" "$CAMERA_STACK_ARCHIVE_SHA256"
    ci_extract_archive "$archive" "$extract"
    source_root=$(find_camera_source_root "$extract") || ci_die "CAMERA_STACK_ARCHIVE does not contain verified camera stack"
  elif [ -n "$CAMERA_STACK_DIR" ]; then
    source_root=$(find_camera_source_root "$CAMERA_STACK_DIR") || ci_die "CAMERA_STACK_DIR does not contain verified camera stack"
  elif [ -d "$REPO_ROOT/source/tb321fu-camera-rootfs-overlay" ]; then
    source_root=$(find_camera_source_root "$REPO_ROOT/source/tb321fu-camera-rootfs-overlay") || ci_die "repository camera stack overlay is incomplete"
  else
    ci_die "set CAMERA_STACK_ARCHIVE/CAMERA_STACK_DIR or add source/tb321fu-camera-rootfs-overlay"
  fi

  ci_log "applying TB321FU camera stack: $source_root"
  stage="$work_dir/camera-stack-stage"
  rm -rf "$stage"
  mkdir -p "$stage"
  rsync -aH --numeric-ids "$source_root"/ "$stage"/
  if [ -d "$arch_camera_supplement_stage" ]; then
    local supplement_relative supplement_source supplement_target
    for supplement_relative in \
      usr/lib/aarch64-linux-gnu/libaperture-0.so.0 \
      usr/lib/aarch64-linux-gnu/libaperture-0.so; do
      supplement_source="$arch_camera_supplement_stage/$supplement_relative"
      supplement_target="$stage/$supplement_relative"
      [ -e "$supplement_source" ] || [ -L "$supplement_source" ] || continue
      if [ -e "$supplement_target" ] || [ -L "$supplement_target" ]; then
        if [ -L "$supplement_source" ] && [ -L "$supplement_target" ]; then
          [ "$(readlink "$supplement_source")" = "$(readlink "$supplement_target")" ] || \
            ci_die "camera source conflicts with imported supplement: $supplement_relative"
        elif [ -f "$supplement_source" ] && [ ! -L "$supplement_source" ] && \
             [ -f "$supplement_target" ] && [ ! -L "$supplement_target" ]; then
          cmp -s "$supplement_source" "$supplement_target" || \
            ci_die "camera source conflicts with imported supplement: $supplement_relative"
        else
          ci_die "camera source supplement type conflict: $supplement_relative"
        fi
      fi
    done
    rsync -aH --numeric-ids "$arch_camera_supplement_stage"/ "$stage"/
  fi
  remove_legacy_camera_payload "$stage"
  install -d -m 0755 "$stage/etc/ld.so.conf.d"
  cat > "$stage/etc/ld.so.conf.d/y700-device.conf" <<'LDSO'
/opt/libcamera-y700/lib/aarch64-linux-gnu
/usr/lib/aarch64-linux-gnu
LDSO
  adapt_ubuntu_multilib_paths_for_arch "$stage"
  install_arch_native_stage_package \
    tb321fu-camera-stack \
    'TB321FU libcamera, PipeWire and GStreamer compatibility stack' \
    "$stage" \
    camera_dependencies camera_provides camera_conflicts camera_replaces
  rm -rf --one-file-system -- "$arch_camera_supplement_stage"
}

adapt_ubuntu_multilib_paths_for_arch() {
  local root=$1
  local compat_source_root=${TB321FU_CAMERA_COMPAT_SOURCE_ROOT:-$root}
  local executable

  install -d -m 0755 "$root/usr/lib/tb321fu" "$root/usr/share/libalpm/hooks"
  cat > "$root/usr/lib/tb321fu/refresh-camera-compat-paths" <<'CAMERA_COMPAT'
#!/bin/sh
set -eu
root=${TB321FU_ROOT:-}
case "$root" in
  ""|/*) ;;
  *) echo "TB321FU_ROOT must be empty or absolute" >&2; exit 2 ;;
esac
source_root=${TB321FU_CAMERA_COMPAT_SOURCE_ROOT:-$root}
case "$source_root" in
  ""|/*) ;;
  *) echo "TB321FU_CAMERA_COMPAT_SOURCE_ROOT must be empty or absolute" >&2; exit 2 ;;
esac
multiarch=$root/usr/lib/aarch64-linux-gnu
source_multiarch=$source_root/usr/lib/aarch64-linux-gnu

if [ -f "$source_multiarch/libaperture-0.so.0" ]; then
  ln -sfn /usr/lib/aarch64-linux-gnu/libaperture-0.so.0 "$root/usr/lib/libaperture-0.so.0"
fi
if [ -L "$source_multiarch/libaperture-0.so" ]; then
  target=$(readlink "$source_multiarch/libaperture-0.so")
  [ "$target" = libaperture-0.so.0 ] || { echo "unsafe libaperture symlink target: $target" >&2; exit 1; }
  ln -sfn "$target" "$root/usr/lib/libaperture-0.so"
fi

spa=$multiarch/spa-0.2/libcamera/libspa-libcamera.so
[ -f "$spa" ] || { echo "missing TB321FU camera SPA source: $spa" >&2; exit 1; }
install -d -m 0755 "$root/usr/lib/spa-0.2/libcamera" "$root/usr/lib/gstreamer-1.0"
install -m 0644 "$spa" "$root/usr/lib/spa-0.2/libcamera/libspa-libcamera.so"
ln -sfn /opt/libcamera-y700/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so \
  "$root/usr/lib/gstreamer-1.0/libgstlibcamera.so"
CAMERA_COMPAT
  chmod 0755 "$root/usr/lib/tb321fu/refresh-camera-compat-paths"
  cat > "$root/usr/share/libalpm/hooks/98-tb321fu-camera-compat.hook" <<'CAMERA_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Path
Target = usr/lib/spa-0.2/libcamera/libspa-libcamera.so
Target = usr/lib/gstreamer-1.0/libgstlibcamera.so

[Action]
Description = Restore TB321FU camera compatibility paths after package upgrades
When = PostTransaction
Exec = /usr/lib/tb321fu/refresh-camera-compat-paths
CAMERA_HOOK
  chmod 0644 "$root/usr/share/libalpm/hooks/98-tb321fu-camera-compat.hook"
  TB321FU_ROOT="$root" TB321FU_CAMERA_COMPAT_SOURCE_ROOT="$compat_source_root" \
    "$root/usr/lib/tb321fu/refresh-camera-compat-paths"

  for executable in \
    "$root/opt/libcamera-y700/bin/cam" \
    "$root/opt/libcamera-y700/bin/libcamera-bug-report" \
    "$root/opt/libcamera-y700/libexec/libcamera/soft_ipa_proxy" \
    "$root/usr/local/bin/y700-camera-env" \
    "$root/usr/local/bin/y700-camera-cam" \
    "$root/usr/local/bin/y700-camera-preview"; do
    [ -f "$executable" ] || ci_die "missing camera executable: ${executable#"$root"}"
    chmod 0755 "$executable"
  done
  find "$root/opt/libcamera-y700" "$root/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera" \
    -type f -name '*.so*' -exec chmod 0644 {} +
}

find_gpu_sensor_source_root() {
  local root=$1 found
  local -a candidates=()

  if [ -f "$root/CMakeLists.txt" ] && [ -f "$root/tb321fu_gpu.cpp" ] && [ -f "$root/metadata.json" ]; then
    printf '%s\n' "$root"
    return 0
  fi
  if [ -d "$root/source/tb321fu-ksystemstats-adreno-freq" ]; then
    find_gpu_sensor_source_root "$root/source/tb321fu-ksystemstats-adreno-freq"
    return $?
  fi
  mapfile -d '' -t candidates < <(find "$root" -type f -path '*/tb321fu-ksystemstats-adreno-freq/CMakeLists.txt' -print0 | sort -z)
  case ${#candidates[@]} in
    0) return 1 ;;
    1) found=${candidates[0]} ;;
    *)
      printf 'ambiguous GPU sensor source roots:\n' >&2
      printf '  %s\n' "${candidates[@]}" >&2
      return 2
      ;;
  esac
  found=${found%/CMakeLists.txt}
  [ -f "$found/tb321fu_gpu.cpp" ] || return 1
  [ -f "$found/metadata.json" ] || return 1
  printf '%s\n' "$found"
}

apply_tb321fu_gpu_sensor() {
  local root=$1 source_root archive extract rootfs_src rootfs_build rootfs_stage plugin_rel stock_plugin_rel disabled_stock_plugin_rel
  local had_stock_plugin=0
  local -a gpu_dependencies=(glibc gcc-libs ksystemstats libksysguard qt6-base kcoreaddons ki18n lm_sensors)
  local -a gpu_provides=(tb321fu-adreno-frequency-provider)
  local -a gpu_conflicts=(y700-ksystemstats-gpu)
  local -a gpu_replaces=(y700-ksystemstats-gpu)

  if [ -n "$TB321FU_GPU_SENSOR_SOURCE_ARCHIVE" ]; then
    archive="$work_dir/gpu-sensor-source.archive"
    extract="$work_dir/gpu-sensor-source"
    ci_log "downloading TB321FU GPU sensor source archive: $TB321FU_GPU_SENSOR_SOURCE_ARCHIVE"
    ci_download "$TB321FU_GPU_SENSOR_SOURCE_ARCHIVE" "$archive" "$TB321FU_GPU_SENSOR_SOURCE_ARCHIVE_SHA256"
    ci_extract_archive "$archive" "$extract"
    source_root=$(find_gpu_sensor_source_root "$extract") || ci_die "GPU sensor source archive is missing or ambiguously contains the expected project"
  elif [ -n "$TB321FU_GPU_SENSOR_SOURCE_DIR" ]; then
    source_root=$(find_gpu_sensor_source_root "$TB321FU_GPU_SENSOR_SOURCE_DIR") || ci_die "GPU sensor source dir is missing or ambiguously contains the expected project"
  else
    source_root=$(find_gpu_sensor_source_root "$REPO_ROOT/source/tb321fu-ksystemstats-adreno-freq") || ci_die "repository GPU sensor source is missing"
  fi

  ci_log "building TB321FU KSystemStats Adreno GPU frequency plugin"
  rootfs_src=/tmp/tb321fu-ksystemstats-adreno-freq-src
  rootfs_build=/tmp/tb321fu-ksystemstats-adreno-freq-build
  rootfs_stage=/tmp/tb321fu-ksystemstats-gpu-package
  plugin_rel=usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_tb321fu_gpu.so
  stock_plugin_rel=usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_gpu.so
  disabled_stock_plugin_rel=$stock_plugin_rel.disabled-tb321fu-adreno

  rm -rf "$root$rootfs_src" "$root$rootfs_build" "$root$rootfs_stage"
  install -d -m 0755 "$root$rootfs_src" "$root$rootfs_stage"
  rsync -a --delete "$source_root"/ "$root$rootfs_src"/

  arch_chroot /usr/bin/cmake -S "$rootfs_src" -B "$rootfs_build" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr
  arch_chroot /usr/bin/cmake --build "$rootfs_build" -j"${TB321FU_GPU_SENSOR_BUILD_JOBS:-2}"
  arch_chroot /usr/bin/env DESTDIR="$rootfs_stage" /usr/bin/cmake --install "$rootfs_build"

  rm -rf "$root$rootfs_src" "$root$rootfs_build"
  install -D -m 0755 "$SCRIPT_DIR/payloads/tb321fu-disable-stock-ksystemstats-gpu" \
    "$root$rootfs_stage/usr/lib/tb321fu/disable-stock-ksystemstats-gpu"
  install -d -m 0755 "$root$rootfs_stage/usr/share/libalpm/hooks"
  cat > "$root$rootfs_stage/usr/share/libalpm/hooks/99-tb321fu-disable-stock-ksystemstats-gpu.hook" <<'GPU_HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Path
Target = usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_gpu.so

[Action]
Description = Keep the stock KSystemStats GPU provider disabled on TB321FU
When = PostTransaction
Exec = /usr/lib/tb321fu/disable-stock-ksystemstats-gpu
GPU_HOOK
  chmod 0644 "$root$rootfs_stage/usr/share/libalpm/hooks/99-tb321fu-disable-stock-ksystemstats-gpu.hook"
  if [ -f "$root/$stock_plugin_rel" ]; then
    had_stock_plugin=1
  fi
  install -d -m 0755 "$root$rootfs_stage/usr/share/tb321fu-ksystemstats-gpu"
  (
    cd "$root$rootfs_stage"
    sha256sum "./$plugin_rel" > \
      ./usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256
  )

  install_arch_native_stage_package \
    tb321fu-ksystemstats-gpu \
    'TB321FU Adreno frequency provider for KSystemStats' \
    "$root$rootfs_stage" \
    gpu_dependencies gpu_provides gpu_conflicts gpu_replaces \
    "$SCRIPT_DIR/payloads/tb321fu-ksystemstats-gpu.install"

  [ -f "$root/$plugin_rel" ] || ci_die "TB321FU GPU sensor plugin missing after build: /$plugin_rel"
  [ ! -e "$root/$stock_plugin_rel" ] || ci_die "stock KSystemStats GPU plugin still enabled: /$stock_plugin_rel"
  if [ "$had_stock_plugin" = 1 ]; then
    [ -f "$root/$disabled_stock_plugin_rel" ] || ci_die "disabled stock KSystemStats GPU plugin missing: /$disabled_stock_plugin_rel"
  fi
  [ -x "$root/usr/lib/tb321fu/disable-stock-ksystemstats-gpu" ] || ci_die "GPU stock-plugin disable helper missing"
  [ -f "$root/usr/share/libalpm/hooks/99-tb321fu-disable-stock-ksystemstats-gpu.hook" ] || ci_die "GPU stock-plugin pacman hook missing"
  [ "$(arch_chroot /usr/bin/pacman -Qoq "/$plugin_rel")" = tb321fu-ksystemstats-gpu ] || \
    ci_die "TB321FU GPU plugin is not owned by its native Arch package"
  (
    cd "$root"
    sha256sum -c ./usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256
  ) || ci_die "TB321FU GPU package checksum mismatch"
}

verify_tb321fu_native_package_integrity() {
  local package path owner
  local -a packages=(tb321fu-camera-stack)
  local -a camera_paths=(
    /etc/ld.so.conf.d/y700-device.conf
    /opt/libcamera-y700/bin/cam
    /usr/lib/spa-0.2/libcamera/libspa-libcamera.so
    /usr/lib/gstreamer-1.0/libgstlibcamera.so
    /usr/lib/aarch64-linux-gnu/libaperture-0.so.0
    /usr/lib/aarch64-linux-gnu/libaperture-0.so
    /usr/lib/libaperture-0.so.0
    /usr/lib/libaperture-0.so
    /usr/lib/tb321fu/refresh-camera-compat-paths
    /usr/share/libalpm/hooks/98-tb321fu-camera-compat.hook
  )
  local -a gpu_paths=(
    /usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_tb321fu_gpu.so
    /usr/lib/tb321fu/disable-stock-ksystemstats-gpu
    /usr/share/libalpm/hooks/99-tb321fu-disable-stock-ksystemstats-gpu.hook
    /usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256
  )

  if arch_chroot /usr/bin/pacman -Q tb321fu-imported-release-payload >/dev/null 2>&1; then
    packages+=(tb321fu-imported-release-payload)
  fi
  if ci_bool "$BUILD_TB321FU_GPU_SENSOR"; then
    packages+=(tb321fu-ksystemstats-gpu)
  fi

  for package in "${packages[@]}"; do
    arch_chroot /usr/bin/pacman -Qkk "$package" >/dev/null || \
      ci_die "native TB321FU package was mutated after installation: $package"
  done
  for path in "${camera_paths[@]}"; do
    owner=$(arch_chroot /usr/bin/pacman -Qoq "$path") || \
      ci_die "camera payload is not pacman-owned: $path"
    [ "$owner" = tb321fu-camera-stack ] || \
      ci_die "camera payload has wrong pacman owner $owner: $path"
  done
  if ci_bool "$BUILD_TB321FU_GPU_SENSOR"; then
    for path in "${gpu_paths[@]}"; do
      owner=$(arch_chroot /usr/bin/pacman -Qoq "$path") || \
        ci_die "GPU payload is not pacman-owned: $path"
      [ "$owner" = tb321fu-ksystemstats-gpu ] || \
        ci_die "GPU payload has wrong pacman owner $owner: $path"
    done
    (
      cd "$rootfs_dir"
      sha256sum -c ./usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256
    ) || ci_die "final TB321FU GPU package checksum mismatch"
  fi
}

write_fcitx5_config() {
  local root=$1

  install -d -m 0755 \
    "$root/etc/environment.d" \
    "$root/etc/skel/.config/environment.d" \
    "$root/etc/skel/.config/autostart" \
    "$root/etc/skel/.config/fcitx5" \
    "$root/etc/skel/.config/plasma-workspace/env"

  cat > "$root/etc/environment.d/90-fcitx5.conf" <<'FCITX5_ENV'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
INPUT_METHOD=fcitx
FCITX5_ENV
  chmod 0644 "$root/etc/environment.d/90-fcitx5.conf"
  cp -a "$root/etc/environment.d/90-fcitx5.conf" "$root/etc/skel/.config/environment.d/90-fcitx5.conf"

  cat > "$root/etc/skel/.config/plasma-workspace/env/fcitx5.sh" <<'FCITX5_PLASMA_ENV'
#!/bin/sh
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
export INPUT_METHOD=fcitx
FCITX5_PLASMA_ENV
  chmod 0755 "$root/etc/skel/.config/plasma-workspace/env/fcitx5.sh"

  cat > "$root/etc/skel/.config/autostart/org.fcitx.Fcitx5.desktop" <<'FCITX5_AUTOSTART'
[Desktop Entry]
Name=Fcitx 5
GenericName=Input Method
Comment=Start Fcitx 5 input method
Exec=fcitx5 -d --replace
Icon=org.fcitx.Fcitx5
Terminal=false
Type=Application
Categories=System;Utility;
X-GNOME-Autostart-enabled=true
X-KDE-autostart-after=panel
FCITX5_AUTOSTART
  chmod 0644 "$root/etc/skel/.config/autostart/org.fcitx.Fcitx5.desktop"

  cat > "$root/etc/skel/.config/fcitx5/profile" <<'FCITX5_PROFILE'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=pinyin

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=pinyin
# Layout
Layout=

[GroupOrder]
0=Default
FCITX5_PROFILE
  chmod 0644 "$root/etc/skel/.config/fcitx5/profile"
}

write_plasma_tablet_config() {
  local root=$1

  install -d -m 0755 "$root/etc/xdg" "$root/etc/skel/.config"
  cat > "$root/etc/skel/.config/plasmakeyboardrc" <<'PLASMAKEYBOARDRC'
[General]
enabledLocales=en_US
soundEnabled=true
vibrationEnabled=true
vibrationMs=20
PLASMAKEYBOARDRC
  chmod 0644 "$root/etc/skel/.config/plasmakeyboardrc"

  cat > "$root/etc/xdg/kwinrc" <<'KWINRC'
[Wayland]
InputMethod=/usr/share/applications/org.kde.plasma.keyboard.desktop
VirtualKeyboardEnabled=true
KWINRC
  chmod 0644 "$root/etc/xdg/kwinrc"
  cp -a "$root/etc/xdg/kwinrc" "$root/etc/skel/.config/kwinrc"

  cat > "$root/etc/skel/.config/kwinoutputconfig.json" <<'KWINOUTPUTCONFIG'
[
    {
        "data": [
            {
                "allowDdcCi": true,
                "allowSdrSoftwareBrightness": false,
                "autoRotation": "InTabletMode",
                "automaticBrightness": true,
                "brightness": 0.35,
                "colorProfileSource": "sRGB",
                "connectorName": "DSI-1",
                "mode": {
                    "height": 2560,
                    "refreshRate": 120000,
                    "width": 1600
                },
                "scale": 2.3,
                "transform": "Rotated180",
                "vrrPolicy": "Never"
            }
        ],
        "name": "outputs"
    }
]
KWINOUTPUTCONFIG
  chmod 0644 "$root/etc/skel/.config/kwinoutputconfig.json"
}

copy_skel_to_user() {
  local root=$1
  local user_home="$root/home/$DEFAULT_USER_NAME"
  local group_name

  [ -d "$user_home" ] || return 0
  group_name=$(arch_chroot id -gn "$DEFAULT_USER_NAME")
  install -d -m 0755 "$user_home/.config"

  local skel_config
  for skel_config in kwinrc plasmakeyboardrc kwinoutputconfig.json; do
    cp -a "$root/etc/skel/.config/$skel_config" "$user_home/.config/$skel_config"
  done

  if ci_bool "$INSTALL_FCITX5_CHINESE"; then
    install -d -m 0755 \
      "$user_home/.config/environment.d" \
      "$user_home/.config/autostart" \
      "$user_home/.config/fcitx5" \
      "$user_home/.config/plasma-workspace/env"
    cp -a "$root/etc/skel/.config/environment.d/90-fcitx5.conf" "$user_home/.config/environment.d/90-fcitx5.conf"
    cp -a "$root/etc/skel/.config/autostart/org.fcitx.Fcitx5.desktop" "$user_home/.config/autostart/org.fcitx.Fcitx5.desktop"
    cp -a "$root/etc/skel/.config/fcitx5/profile" "$user_home/.config/fcitx5/profile"
    cp -a "$root/etc/skel/.config/plasma-workspace/env/fcitx5.sh" "$user_home/.config/plasma-workspace/env/fcitx5.sh"
  fi

  chroot "$root" chown -R "$DEFAULT_USER_NAME:$group_name" "/home/$DEFAULT_USER_NAME/.config"
}

build_package_list() {
  local base_packages=(
    base bash-completion sudo openssh rsync curl wget ca-certificates gnupg fakeroot
    nano vim less which file htop usbutils pciutils iproute2 inetutils
    networkmanager bluez bluez-utils power-profiles-daemon udisks2 upower
    linux-firmware
    alsa-ucm-conf alsa-utils iio-sensor-proxy feedbackd
    glib2 libgudev polkit protobuf-c libqmi libqrtr-glib
    libevent libyaml gstreamer gst-plugins-base gst-plugins-base-libs gst-plugins-good gst-plugin-libcamera gtk3 gdk-pixbuf2 libunwind elfutils gnutls libglvnd
    mesa vulkan-freedreno vulkan-tools
    pipewire pipewire-alsa pipewire-pulse wireplumber
  )
  local desktop_standard=(
    plasma-meta sddm sddm-kcm plasma-keyboard xdg-desktop-portal-kde
    dolphin konsole kate ark gwenview okular spectacle discover packagekit-qt6 bluedevil
    packagekit
    noto-fonts noto-fonts-cjk ttf-dejavu ttf-liberation
  )
  local desktop_full=(kde-applications-meta)
  local fcitx_packages=(
    fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-qt fcitx5-gtk fcitx5-material-color
  )
  local browser_packages=(firefox)
  local camera_app_packages=(snapshot kamoso)
  local gpu_sensor_build_packages=(cmake extra-cmake-modules gcc make libksysguard ksystemstats qt6-base kcoreaddons ki18n)
  local packages=("${base_packages[@]}")

  case "$DESKTOP_PROFILE" in
    minimal)
      packages+=(plasma-desktop plasma-workspace sddm plasma-keyboard konsole dolphin noto-fonts-cjk)
      ;;
    standard)
      packages+=("${desktop_standard[@]}")
      ;;
    full)
      packages+=("${desktop_standard[@]}" "${desktop_full[@]}")
      ;;
    *) ci_die "unsupported DESKTOP_PROFILE=$DESKTOP_PROFILE" ;;
  esac

  if ci_bool "$INSTALL_FCITX5_CHINESE"; then
    packages+=("${fcitx_packages[@]}")
  fi
  if ci_bool "$INSTALL_FIREFOX"; then
    packages+=("${browser_packages[@]}")
  fi
  if ci_bool "$INSTALL_CAMERA_APPS"; then
    packages+=("${camera_app_packages[@]}")
  fi
  if ci_bool "$BUILD_TB321FU_GPU_SENSOR"; then
    packages+=("${gpu_sensor_build_packages[@]}")
  fi
  if [ -n "$PACKAGE_LIST" ]; then
    while IFS= read -r package; do
      [ -n "$package" ] && packages+=("$package")
    done <<< "$PACKAGE_LIST"
  fi

  printf '%s\n' "${packages[@]}" | awk 'NF && !seen[$0]++'
}

ci_log "creating rootfs image: $rootfs_img ($ROOTFS_IMAGE_SIZE)"
rm -f "$rootfs_img"
truncate -s "$ROOTFS_IMAGE_SIZE" "$rootfs_img"
mkfs.ext4 -F -L "$ROOTFS_LABEL" "$rootfs_img"
mkdir -p "$rootfs_dir"
mount -o loop "$rootfs_img" "$rootfs_dir"
mounted_rootfs=1

rootfs_archive="$work_dir/arch-rootfs.tar.gz"
ci_log "downloading Arch Linux ARM rootfs: $ARCH_ROOTFS_URL"
ci_download "$ARCH_ROOTFS_URL" "$rootfs_archive" "$ARCH_ROOTFS_SHA256"
ci_log "extracting Arch Linux ARM rootfs"
tar -C "$rootfs_dir" -xpf "$rootfs_archive" --numeric-owner

install -d -m 0755 "$rootfs_dir/etc/pacman.d" "$rootfs_dir/etc/systemd/system"
printf 'Server = %s\n' "$ARCH_MIRROR" > "$rootfs_dir/etc/pacman.d/mirrorlist"
rm -f "$rootfs_dir/etc/resolv.conf"
cp -L /etc/resolv.conf "$rootfs_dir/etc/resolv.conf"
if ! awk '
  /^[[:space:]]*nameserver[[:space:]]+/ {
    ns=$2
    if (ns !~ /^(127\.|::1$|0\.0\.0\.0$)/) good=1
  }
  END { exit good ? 0 : 1 }
' "$rootfs_dir/etc/resolv.conf"; then
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$rootfs_dir/etc/resolv.conf"
fi

mount_chroot_runtime

ci_log "initializing pacman keyring"
arch_chroot /usr/bin/pacman-key --init
arch_chroot /usr/bin/pacman-key --populate archlinuxarm
assert_arch_remote_signature_policy
arch_chroot /usr/bin/getent hosts os.archlinuxarm.org >/dev/null
arch_chroot /usr/bin/pacman -Sy --noconfirm --needed archlinuxarm-keyring

mapfile -t packages < <(build_package_list)
printf '%s\n' "${packages[@]}" > "$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.packages"
ci_log "installing Arch packages: ${#packages[@]} packages"
assert_arch_remote_signature_policy
arch_chroot /usr/bin/pacman -Syu --noconfirm --needed --disable-download-timeout -- "${packages[@]}"

ci_log "configuring base system"
printf '%s\n' "$HOSTNAME_NAME" > "$rootfs_dir/etc/hostname"
cat > "$rootfs_dir/etc/hosts" <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 $HOSTNAME_NAME.localdomain $HOSTNAME_NAME
HOSTS

for locale in $LOCALES; do
  if grep -q "^#${locale} UTF-8" "$rootfs_dir/etc/locale.gen"; then
    sed -i "s/^#${locale} UTF-8/${locale} UTF-8/" "$rootfs_dir/etc/locale.gen"
  elif ! grep -q "^${locale} UTF-8" "$rootfs_dir/etc/locale.gen"; then
    printf '%s UTF-8\n' "$locale" >> "$rootfs_dir/etc/locale.gen"
  fi
done
arch_chroot /usr/bin/locale-gen
printf 'LANG=%s\n' "$LANG_NAME" > "$rootfs_dir/etc/locale.conf"
ln -sfn "/usr/share/zoneinfo/$TZ_REGION" "$rootfs_dir/etc/localtime"

cat > "$rootfs_dir/etc/fstab" <<FSTAB
LABEL=$ROOTFS_LABEL / ext4 rw,relatime 0 1
FSTAB

if [ "$DEFAULT_USER_NAME" != alarm ] && arch_chroot /usr/bin/id -u alarm >/dev/null 2>&1; then
  ci_log "removing inherited alarm account before creating $DEFAULT_USER_NAME"
  arch_chroot /usr/bin/userdel -r alarm
fi

if ! arch_chroot /usr/bin/id -u "$DEFAULT_USER_NAME" >/dev/null 2>&1; then
  arch_chroot /usr/bin/useradd -m -s /bin/bash -G users,video,audio,input,storage,power "$DEFAULT_USER_NAME"
fi
if [ -n "$DEFAULT_USER_PASSWORD_HASH" ] && [ "$DEFAULT_USER_PASSWORD_HASH" != '!' ]; then
  printf '%s:%s\n' "$DEFAULT_USER_NAME" "$DEFAULT_USER_PASSWORD_HASH" | arch_chroot /usr/bin/chpasswd -e
else
  arch_chroot /usr/bin/passwd -l "$DEFAULT_USER_NAME" || true
fi

case "$ROOT_PASSWORD_MODE" in
  locked)
    arch_chroot /usr/bin/passwd -l root || true
    ;;
  set)
    [ -n "$ROOT_PASSWORD_HASH" ] || ci_die "ROOT_PASSWORD_MODE=set requires ROOT_PASSWORD_HASH"
    printf 'root:%s\n' "$ROOT_PASSWORD_HASH" | arch_chroot /usr/bin/chpasswd -e
    ;;
  empty)
    arch_chroot /usr/bin/passwd -d root || true
    ;;
  *) ci_die "unsupported ROOT_PASSWORD_MODE=$ROOT_PASSWORD_MODE" ;;
esac

install -d -m 0750 "$rootfs_dir/etc/sudoers.d"
case "$USER_SUDO_MODE" in
  password)
    arch_chroot /usr/bin/usermod -aG wheel "$DEFAULT_USER_NAME"
    printf '%s ALL=(ALL:ALL) ALL\n' "$DEFAULT_USER_NAME" > "$rootfs_dir/etc/sudoers.d/010_${DEFAULT_USER_NAME}"
    chmod 0440 "$rootfs_dir/etc/sudoers.d/010_${DEFAULT_USER_NAME}"
    ;;
  nopasswd)
    arch_chroot /usr/bin/usermod -aG wheel "$DEFAULT_USER_NAME"
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$DEFAULT_USER_NAME" > "$rootfs_dir/etc/sudoers.d/010_${DEFAULT_USER_NAME}"
    chmod 0440 "$rootfs_dir/etc/sudoers.d/010_${DEFAULT_USER_NAME}"
    ;;
  none)
    rm -f "$rootfs_dir/etc/sudoers.d/010_${DEFAULT_USER_NAME}"
    ;;
  *) ci_die "unsupported USER_SUDO_MODE=$USER_SUDO_MODE" ;;
esac

write_plasma_tablet_config "$rootfs_dir"
if ci_bool "$INSTALL_FCITX5_CHINESE"; then
  write_fcitx5_config "$rootfs_dir"
fi
copy_skel_to_user "$rootfs_dir"

ci_log "enabling system services"
required_system_units=(NetworkManager.service sshd.service sddm.service bluetooth.service)
required_user_units=(pipewire.socket pipewire-pulse.socket wireplumber.service)
systemctl --root="$rootfs_dir" enable "${required_system_units[@]}"
systemctl --root="$rootfs_dir" --global enable "${required_user_units[@]}"
for required_unit in "${required_system_units[@]}"; do
  systemctl --root="$rootfs_dir" is-enabled --quiet "$required_unit" ||
    ci_die "required system service was not enabled: $required_unit"
done
for required_unit in "${required_user_units[@]}"; do
  systemctl --root="$rootfs_dir" --global is-enabled --quiet "$required_unit" ||
    ci_die "required global user service was not enabled: $required_unit"
done

if ci_bool "$SDDM_AUTOLOGIN"; then
  install -d -m 0755 "$rootfs_dir/etc/sddm.conf.d"
  cat > "$rootfs_dir/etc/sddm.conf.d/zz-tb321fu-autologin.conf" <<CONF
[Autologin]
User=$DEFAULT_USER_NAME
Session=${SDDM_AUTOLOGIN_SESSION%.desktop}
Relogin=false
CONF
  chmod 0644 "$rootfs_dir/etc/sddm.conf.d/zz-tb321fu-autologin.conf"
fi

apply_device_payloads
apply_tb321fu_deb_payloads
install_arch_import_package
apply_tb321fu_camera_stack

overlay_stage=
if [ -n "$OVERLAY_ARCHIVE" ]; then
  tmp_overlay="$work_dir/overlay.archive"
  overlay_stage="$work_dir/final-overlay"
  mkdir -p "$overlay_stage"
  ci_log "staging overlay archive: $OVERLAY_ARCHIVE"
  ci_download "$OVERLAY_ARCHIVE" "$tmp_overlay" "$OVERLAY_ARCHIVE_SHA256"
  ci_extract_archive "$tmp_overlay" "$overlay_stage"
  ci_validate_rootfs_overlay_tree "$overlay_stage"
fi
if [ -n "$OVERLAY_DIR" ]; then
  ci_validate_rootfs_overlay_tree "$OVERLAY_DIR"
fi

unmount_chroot_runtime

if [ -n "$overlay_stage" ]; then
  ci_log "applying staged overlay archive: $OVERLAY_ARCHIVE"
  rsync -aHAX --numeric-ids "$overlay_stage"/ "$rootfs_dir"/
fi
if [ -n "$OVERLAY_DIR" ]; then
  ci_log "applying validated overlay directory: $OVERLAY_DIR"
  rsync -aHAX --numeric-ids "$OVERLAY_DIR"/ "$rootfs_dir"/
fi

mount_chroot_runtime

remove_legacy_y700_payload "$rootfs_dir"
remove_legacy_camera_payload "$rootfs_dir"

enable_y700_device_services "$rootfs_dir"
if ci_bool "$APPLY_Y700_FIRMWARE_FIXES"; then
  apply_y700_firmware_fixes "$rootfs_dir"
fi
if ci_bool "$APPLY_Y700_AUDIO_POLICY_FIXES"; then
  apply_y700_audio_policy_fixes "$rootfs_dir"
fi
if ci_bool "$BUILD_TB321FU_GPU_SENSOR"; then
  apply_tb321fu_gpu_sensor "$rootfs_dir"
fi

ci_log "generating module dependency files for $KERNEL_VERSION"
depmod -b "$rootfs_dir" "$KERNEL_VERSION"
arch_chroot /usr/bin/ldconfig

rm -rf "$rootfs_dir/var/cache/pacman/pkg"/* "$rootfs_dir/tmp"/* "$rootfs_dir/var/tmp"/*
rm -f \
  "$rootfs_dir/BUILD-INFO.txt" \
  "$rootfs_dir/SHA256SUMS" \
  "$rootfs_dir/SHA256SUMS.txt" \
  "$rootfs_dir/Y700-ROOTFS-OVERLAY-MANIFEST.tsv"

verify_required_y700_payload "$rootfs_dir"
ci_assert_privileged_payload_security "$rootfs_dir" \
  usr/libexec/tb321fu-haptics/bind-aw86937 \
  opt/libcamera-y700/bin/cam \
  opt/libcamera-y700/bin/libcamera-bug-report \
  opt/libcamera-y700/libexec/libcamera/soft_ipa_proxy \
  usr/local/bin/y700-camera-env \
  usr/local/bin/y700-camera-cam \
  usr/local/bin/y700-camera-preview
verify_tb321fu_native_package_integrity
arch_chroot /usr/bin/pacman -Q | LC_ALL=C sort > \
  "$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.packages"

cat > "$build_info" <<INFO
generated=$(ci_iso8601_timestamp)
distribution=Arch Linux ARM
arch=aarch64
arch_rootfs_url=$ARCH_ROOTFS_URL
arch_mirror=$ARCH_MIRROR
desktop_profile=$DESKTOP_PROFILE
rootfs_image_size=$ROOTFS_IMAGE_SIZE
rootfs_label=$ROOTFS_LABEL
rootfs_partlabel=$ROOTFS_PARTLABEL
hostname=$HOSTNAME_NAME
default_user=$DEFAULT_USER_NAME
root_password_mode=$ROOT_PASSWORD_MODE
user_sudo_mode=$USER_SUDO_MODE
sddm_autologin=$SDDM_AUTOLOGIN
sddm_autologin_session=$SDDM_AUTOLOGIN_SESSION
lang=$LANG_NAME
locales=$LOCALES
install_fcitx5_chinese=$INSTALL_FCITX5_CHINESE
install_firefox=$INSTALL_FIREFOX
install_camera_apps=$INSTALL_CAMERA_APPS
device_deb_archive=${DEVICE_DEB_ARCHIVE:-}
device_deb_dir=${DEVICE_DEB_DIR:-}
sensor_deb_archive=${SENSOR_DEB_ARCHIVE:-}
sensor_deb_dir=${SENSOR_DEB_DIR:-}
haptics_deb_archive=${HAPTICS_DEB_ARCHIVE:-}
haptics_deb_dir=${HAPTICS_DEB_DIR:-}
camera_stack_archive=${CAMERA_STACK_ARCHIVE:-}
camera_stack_dir=${CAMERA_STACK_DIR:-}
build_tb321fu_gpu_sensor=$BUILD_TB321FU_GPU_SENSOR
tb321fu_gpu_sensor_source_archive=${TB321FU_GPU_SENSOR_SOURCE_ARCHIVE:-}
tb321fu_gpu_sensor_source_dir=${TB321FU_GPU_SENSOR_SOURCE_DIR:-repo-default}
overlay_archive=${OVERLAY_ARCHIVE:-}
overlay_dir=${OVERLAY_DIR:-}
kernel_version=$KERNEL_VERSION
apply_y700_firmware_fixes=$APPLY_Y700_FIRMWARE_FIXES
apply_y700_audio_policy_fixes=$APPLY_Y700_AUDIO_POLICY_FIXES
INFO

ci_log "writing rootfs manifest"
(cd "$rootfs_dir" && find . -xdev -printf '%y\t%u\t%g\t%m\t%s\t%p\n' | sort) > "$manifest"

finalize_rootfs_mount
ci_e2fsck_repair "$rootfs_img"

ci_log "checksumming rootfs image"
raw_sha_file="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.raw.sha256"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img")" > "$(basename "$raw_sha_file")")

checksum_file="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.SHA256SUMS"
rm -f "$checksum_file"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$build_info")" "$(basename "$manifest")" "$(basename "$raw_sha_file")" "$(basename "$OUTPUT_PREFIX")-rootfs.packages" > "$(basename "$checksum_file")")

case "$COMPRESS" in
  none)
    (cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img")" >> "$(basename "$checksum_file")")
    ;;
  zstd)
    ci_require_cmd zstd
    zstd -T0 -19 -f "$rootfs_img" -o "$rootfs_img.zst"
    (cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img").zst" >> "$(basename "$checksum_file")")
    ;;
  xz)
    xz -T0 -k -f "$rootfs_img"
    (cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img").xz" >> "$(basename "$checksum_file")")
    ;;
  7z)
    ci_require_cmd 7z
    sevenz_out="$rootfs_img.7z"
    rm -f "$sevenz_out" "$sevenz_out".*
    if [ -n "$CHUNK_SIZE" ]; then
      7z a "$sevenz_out" "$rootfs_img" -t7z -m0=lzma2 -mx=9 -mmt=on -mtm=off -mta=off -mtc=off "-v$CHUNK_SIZE" >/dev/null
      (cd "$OUTPUT_DIR" && sha256sum "$(basename "$sevenz_out")".* >> "$(basename "$checksum_file")")
    else
      7z a "$sevenz_out" "$rootfs_img" -t7z -m0=lzma2 -mx=9 -mmt=on -mtm=off -mta=off -mtc=off >/dev/null
      (cd "$OUTPUT_DIR" && sha256sum "$(basename "$sevenz_out")" >> "$(basename "$checksum_file")")
    fi
    ;;
  *) ci_die "unsupported COMPRESS=$COMPRESS" ;;
esac

if [ "$COMPRESS" != none ] && [ "$KEEP_RAW_IMAGE" != 1 ]; then
  rm -f "$rootfs_img"
fi

ci_log "rootfs build complete: $OUTPUT_DIR"

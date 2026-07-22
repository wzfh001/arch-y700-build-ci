#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/system-payload-policy.sh"
. "$SCRIPT_DIR/package-list.sh"

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
  DEFAULT_USER_AUTHORIZED_KEYS public SSH keys supplied via secret; default: empty
  ROOT_PASSWORD_MODE          locked|set|empty, default: locked
  ROOT_PASSWORD_HASH          crypt(3) hash used when ROOT_PASSWORD_MODE=set
  USER_SUDO_MODE              password|nopasswd|none, default: password
  SDDM_AUTOLOGIN              1/0, default: 0
  SDDM_AUTOLOGIN_SESSION      default: plasma
  TZ_REGION                   default: Asia/Shanghai
  LANG_NAME                   default: zh_CN.UTF-8
  LOCALES                     whitespace list, default: en_US.UTF-8 zh_CN.UTF-8
  DESKTOP_PROFILE             minimal|standard|full|tablet-niri, default: standard
  PACKAGE_LIST                additional pacman packages
  INSTALL_FCITX5_CHINESE      default: 1
  INSTALL_FIREFOX             default: 1
  INSTALL_CAMERA_APPS         install camera test apps, default: 1
  DEVICE_DEB_ARCHIVE          Y700 device payload archive containing .deb files and overlays
  DEVICE_DEB_DIR              optional local directory containing device .deb files/overlays
  PACMAN_PACKAGE_LOCK_DIR     verified offline pacman repository lock for tablet-niri
  PACMAN_PACKAGE_LOCK_MANIFEST_SHA256 pinned SHA-256 of the lock manifest
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
ci_require_cmd readelf
ci_require_cmd unshare

REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
TB321FU_DEVICE_ARCHIVE_URL='https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-device-debs-20260624-201420-compat1.tar.gz'
TB321FU_DEVICE_ARCHIVE_SHA256='047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04'
TB321FU_WIFI_OVERLAY_DEB='y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb'
TB321FU_WIFI_OVERLAY_DEB_SHA256='9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc'
TB321FU_WIFI_FIRMWARE_MANIFEST="$REPO_ROOT/profiles/tablet-niri/wifi-firmware.sha256"

OUTPUT_DIR=${OUTPUT_DIR:-out/ci-rootfs}
OUTPUT_PREFIX=${OUTPUT_PREFIX:-y700-archlinuxarm}
ci_validate_output_prefix "$OUTPUT_PREFIX"
ARCH_ROOTFS_URL=${ARCH_ROOTFS_URL:-https://de3.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
ARCH_ROOTFS_SHA256=${ARCH_ROOTFS_SHA256:-}
ARCH_MIRROR=${ARCH_MIRROR:-'https://de3.mirror.archlinuxarm.org/$arch/$repo'}
ROOTFS_IMAGE_SIZE=${ROOTFS_IMAGE_SIZE:-20G}
ROOTFS_LABEL=${ROOTFS_LABEL:-ArchLinux}
ROOTFS_PARTLABEL=${ROOTFS_PARTLABEL:-userdata}
HOSTNAME_NAME=${HOSTNAME_NAME:-y700}
DEFAULT_USER_NAME=${DEFAULT_USER_NAME:-y700}
DEFAULT_USER_PASSWORD_HASH=${DEFAULT_USER_PASSWORD_HASH:-!}
DEFAULT_USER_AUTHORIZED_KEYS=${DEFAULT_USER_AUTHORIZED_KEYS:-}
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
PACMAN_PACKAGE_LOCK_DIR=${PACMAN_PACKAGE_LOCK_DIR:-}
PACMAN_PACKAGE_LOCK_MANIFEST_SHA256=${PACMAN_PACKAGE_LOCK_MANIFEST_SHA256:-}
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

if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  [ "$HOSTNAME_NAME" = fuhao ] || ci_die "tablet-niri requires HOSTNAME_NAME=fuhao"
  [ "$DEFAULT_USER_NAME" = fuhao ] || ci_die "tablet-niri requires DEFAULT_USER_NAME=fuhao"
  [ "$ROOTFS_PARTLABEL" = userdata ] || ci_die "tablet-niri requires ROOTFS_PARTLABEL=userdata"
  [[ $DEFAULT_USER_PASSWORD_HASH == \$6\$* ]] || \
    ci_die "tablet-niri requires a SHA-512 user password hash from a repository secret"
  [ -n "$DEFAULT_USER_AUTHORIZED_KEYS" ] || \
    ci_die "tablet-niri requires authorized SSH keys from a repository secret"
  [ "$ROOT_PASSWORD_MODE" = locked ] || ci_die "tablet-niri requires a locked root password"
  [ "$USER_SUDO_MODE" = password ] || ci_die "tablet-niri requires password-based sudo"
  [ "$DEVICE_DEB_ARCHIVE" = "$TB321FU_DEVICE_ARCHIVE_URL" ] || \
    ci_die "tablet-niri requires the fixed TB321FU device archive URL"
  [ "$DEVICE_DEB_ARCHIVE_SHA256" = "$TB321FU_DEVICE_ARCHIVE_SHA256" ] || \
    ci_die "tablet-niri requires the fixed TB321FU device archive SHA-256"
  [ -z "$DEVICE_DEB_DIR" ] || ci_die "tablet-niri forbids an unpinned device payload directory"
  [ -f "$TB321FU_WIFI_FIRMWARE_MANIFEST" ] || \
    ci_die "tablet-niri Wi-Fi firmware manifest is missing"
  [ -n "$PACMAN_PACKAGE_LOCK_DIR" ] || \
    ci_die "tablet-niri requires a verified pacman package lock directory"
  [[ $PACMAN_PACKAGE_LOCK_MANIFEST_SHA256 =~ ^[0-9a-f]{64}$ ]] || \
    ci_die "tablet-niri requires a pinned pacman package lock manifest SHA-256"
  INSTALL_FCITX5_CHINESE=1
  INSTALL_FIREFOX=1
  INSTALL_CAMERA_APPS=0
  BUILD_TB321FU_GPU_SENSOR=0
fi

OUTPUT_DIR=$(ci_prepare_output_dir "$OUTPUT_DIR")
work_dir=$(mktemp -d "$OUTPUT_DIR/.arch-rootfs-build.XXXXXX")
rootfs_dir="$work_dir/rootfs"
arch_import_stage="$work_dir/arch-import-stage"
arch_import_sources="$work_dir/arch-import-sources.tsv"
arch_camera_supplement_stage="$work_dir/arch-camera-supplement-stage"
rootfs_img="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.img"
build_info="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.BUILD-INFO.txt"
manifest="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.manifest"
third_party_manifest="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.third-party-assets.manifest"
requested_packages_file="$work_dir/requested-packages.txt"
mounted_rootfs=0
bind_mounts=()

cleanup() {
  set +e
  if [ "$mounted_rootfs" = 1 ]; then
    stop_chroot_background_services
    terminate_rootfs_processes "$rootfs_dir"
    ci_unmount_tree "$rootfs_dir" ||
      ci_log "cleanup preserved mounted work tree for manual recovery: $work_dir"
  fi
  if ! ci_safe_rmtree "$work_dir" "$OUTPUT_DIR" .arch-rootfs-build.; then
    ci_log "cleanup refused to remove work tree: $work_dir"
  fi
}
trap cleanup EXIT

if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  build_package_list > "$requested_packages_file"
  [ -s "$requested_packages_file" ] || ci_die "tablet-niri package request list is empty"
  bash "$SCRIPT_DIR/verify-pacman-package-lock.sh" \
    "$PACMAN_PACKAGE_LOCK_DIR" \
    "$PACMAN_PACKAGE_LOCK_MANIFEST_SHA256" \
    "$ARCH_ROOTFS_SHA256" \
    "$requested_packages_file"
  PACMAN_PACKAGE_LOCK_DIR=$(realpath -e -- "$PACMAN_PACKAGE_LOCK_DIR")
fi

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

suspend_chroot_runtime() {
  stop_chroot_background_services
  terminate_rootfs_processes "$rootfs_dir"
  unmount_chroot_runtime
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

arch_chroot_offline() {
  unshare --net -- chroot "$rootfs_dir" /usr/bin/env -i \
    HOME=/root TERM=xterm PATH=/usr/local/sbin:/usr/local/bin:/usr/bin "$@"
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
  local global_policy policy repo repo_policy
  local -a repos=()

  global_policy=$(arch_chroot /usr/bin/pacman-conf SigLevel) ||
    ci_die "failed to resolve global pacman signature policy"
  assert_pacman_remote_policy_tokens "global pacman policy" "$global_policy"

  mapfile -t repos < <(arch_chroot /usr/bin/pacman-conf --repo-list)
  [ "${#repos[@]}" -gt 0 ] || ci_die "pacman has no configured repositories"
  for repo in "${repos[@]}"; do
    [ -n "$repo" ] || ci_die "pacman returned an empty repository name"
    repo_policy=$(arch_chroot /usr/bin/pacman-conf -r "$repo" SigLevel) ||
      ci_die "failed to resolve pacman signature policy for repository: $repo"
    policy=${repo_policy:-$global_policy}
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
  )
  if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
    required+=(
      usr/bin/niri
      usr/bin/noctalia
      etc/greetd/config.toml
      etc/nftables.conf
      etc/systemd/user/noctalia.service
      etc/systemd/user/fcitx5-tablet.service
      etc/systemd/system/tb321fu-grow-rootfs.service
      etc/systemd/system/tb321fu-usb-rescue.service
      etc/systemd/system/tb321fu-bt-nap.service
      etc/modules-load.d/60-tb321fu-rescue.conf
      etc/NetworkManager/system-connections/tb321fu-rescue-usb.nmconnection
      etc/NetworkManager/system-connections/tb321fu-rescue-bt.nmconnection
      usr/local/libexec/tb321fu-usb-rescue
      usr/local/libexec/tb321fu-bt-nap
      usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin
      usr/share/tb321fu-wifi-firmware/SHA256SUMS
      usr/share/tb321fu-wifi-firmware/SOURCE.txt
      usr/lib/modules/$KERNEL_VERSION/kernel/drivers/net/wireless/ath/ath12k/wifi7/ath12k_wifi7.ko
      usr/lib/modules/$KERNEL_VERSION/kernel/drivers/soc/qcom/pmic_glink.ko
      usr/lib/modules/$KERNEL_VERSION/kernel/drivers/usb/typec/ucsi/ucsi_glink.ko
      usr/lib/modules/$KERNEL_VERSION/kernel/drivers/usb/gadget/libcomposite.ko
      usr/lib/modules/$KERNEL_VERSION/kernel/drivers/usb/gadget/function/usb_f_acm.ko
      usr/lib/modules/$KERNEL_VERSION/kernel/drivers/usb/gadget/function/usb_f_ncm.ko
      usr/lib/modules/$KERNEL_VERSION/kernel/net/bluetooth/bnep/bnep.ko
      home/$DEFAULT_USER_NAME/.config/niri/config.kdl
      home/$DEFAULT_USER_NAME/.config/noctalia/config.toml
    )
  else
    required+=(
      usr/share/applications/org.kde.plasma.keyboard.desktop
      etc/xdg/kwinrc
      home/$DEFAULT_USER_NAME/.config/kwinrc
      home/$DEFAULT_USER_NAME/.config/plasmakeyboardrc
    )
  fi
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
  if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
    forbidden+=(
      usr/share/applications/org.kde.plasma.keyboard.desktop
      etc/xdg/kwinrc
      etc/skel/.config/kwinrc
      etc/skel/.config/plasmakeyboardrc
      etc/skel/.config/kwinoutputconfig.json
      home/$DEFAULT_USER_NAME/.config/kwinrc
      home/$DEFAULT_USER_NAME/.config/plasmakeyboardrc
      home/$DEFAULT_USER_NAME/.config/kwinoutputconfig.json
    )
  fi
  for rel in "${forbidden[@]}"; do
    [ ! -e "$root/$rel" ] && [ ! -L "$root/$rel" ] || ci_die "legacy Y700 payload must not be present: /$rel"
  done
}

remove_legacy_y700_audio_policy() {
  local root=$1
  local old_conf="$root/etc/wireplumber/wireplumber.conf.d/52-y700-headset-cleanup.conf"
  local old_script="$root/usr/share/wireplumber/scripts/y700/headset-cleanup.lua"
  local old_conf_sha old_script_sha

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
}

apply_y700_audio_policy_fixes() {
  local root=$1
  local conf_dir="$root/etc/wireplumber/wireplumber.conf.d"
  local conf="$conf_dir/51-y700-alsa-auto.conf"
  local old_conf="$conf_dir/52-y700-headset-cleanup.conf"
  local old_script="$root/usr/share/wireplumber/scripts/y700/headset-cleanup.lua"
  local route_conf="$conf_dir/52-tb321fu-headset-route-reconcile.conf"
  local route_script="$root/usr/share/wireplumber/scripts/tb321fu/headset-route-reconcile.lua"

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

  remove_legacy_y700_audio_policy "$root"

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

remove_tablet_niri_desktop_payload() {
  local root=$1

  [ "$DESKTOP_PROFILE" = tablet-niri ] || return 0
  rm -f \
    "$root/usr/share/applications/org.kde.plasma.keyboard.desktop" \
    "$root/etc/xdg/kwinrc" \
    "$root/etc/skel/.config/kwinrc" \
    "$root/etc/skel/.config/plasmakeyboardrc" \
    "$root/etc/skel/.config/kwinoutputconfig.json" \
    "$root/home/$DEFAULT_USER_NAME/.config/kwinrc" \
    "$root/home/$DEFAULT_USER_NAME/.config/plasmakeyboardrc" \
    "$root/home/$DEFAULT_USER_NAME/.config/kwinoutputconfig.json"
  rmdir --ignore-fail-on-non-empty \
    "$root/home/$DEFAULT_USER_NAME/.config" \
    "$root/home/$DEFAULT_USER_NAME" \
    "$root/home" 2>/dev/null || true
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

remove_generated_module_dependency_files() {
  local stage=$1
  local kernel_version=$2
  local module_dir="$stage/usr/lib/modules/$kernel_version"

  [ -d "$module_dir" ] || return 0
  rm -f -- \
    "$module_dir/modules.alias" \
    "$module_dir/modules.alias.bin" \
    "$module_dir/modules.builtin.alias.bin" \
    "$module_dir/modules.builtin.bin" \
    "$module_dir/modules.dep" \
    "$module_dir/modules.dep.bin" \
    "$module_dir/modules.devname" \
    "$module_dir/modules.softdep" \
    "$module_dir/modules.symbols" \
    "$module_dir/modules.symbols.bin" \
    "$module_dir/modules.weakdep"
}

remove_existing_identical_arch_import_members() {
  local stage=$1
  local root=$2
  local path relative target source_meta target_meta owner

  while IFS= read -r -d '' path; do
    relative=${path#"$stage"/}
    target="$root/$relative"
    [ -e "$target" ] || [ -L "$target" ] || continue
    owner=$(arch_chroot /usr/bin/pacman -Qoq "/$relative" 2>/dev/null || true)
    if [ -n "$owner" ]; then
      ci_log "verifying imported path already owned by native Arch package $owner: /$relative"
    fi
    if [ -L "$path" ] && [ -L "$target" ]; then
      [ "$(readlink "$path")" = "$(readlink "$target")" ] || \
        ci_die "Arch import differs from existing symlink: /$relative"
    elif [ -f "$path" ] && [ -f "$target" ] && [ ! -L "$target" ]; then
      cmp -s "$path" "$target" || ci_die "Arch import differs from existing file: /$relative"
      source_meta=$(stat -c '%u:%g:%a' "$path")
      target_meta=$(stat -c '%u:%g:%a' "$target")
      [ "$source_meta" = "$target_meta" ] || \
        ci_die "Arch import metadata differs from existing file: /$relative"
    else
      ci_die "Arch import type differs from existing member: /$relative"
    fi
    if [ -n "$owner" ]; then
      ci_log "excluding byte-identical imported path owned by native Arch package $owner: /$relative"
    fi
    rm -f -- "$path"
  done < <(find "$stage" -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)
  find "$stage" -depth -mindepth 1 -type d -empty -delete
}

run_arch_makepkg() {
  local build_user=$1
  local build_dir=$2

  arch_chroot /usr/bin/runuser -u "$build_user" -- /usr/bin/env \
    HOME="$build_dir" \
    PKGDEST="$build_dir" \
    SRCDEST="$build_dir/srcdest" \
    BUILDDIR="$build_dir/build" \
    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}" \
    /usr/bin/bash -c 'cd -- "$1" && shift && exec "$@"' bash "$build_dir" \
    /usr/bin/makepkg --noconfirm --nodeps --cleanbuild --clean --force
}

install_arch_local_package() {
  local package_path=$1
  local replace_conflicts=${2:-0}
  local -a pacman_args=(-U --noconfirm)

  if [ "$replace_conflicts" = 1 ]; then
    pacman_args+=(--ask=4)
  else
    [ "$replace_conflicts" = 0 ] || ci_die "invalid local package conflict policy: $replace_conflicts"
  fi
  arch_chroot /usr/bin/pacman "${pacman_args[@]}" "$package_path"
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
  remove_legacy_y700_payload "$stage"
  remove_tablet_niri_desktop_payload "$stage"
  remove_legacy_y700_audio_policy "$stage"
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

  remove_generated_module_dependency_files "$arch_import_stage" "$KERNEL_VERSION"
  remove_existing_identical_arch_import_members "$arch_import_stage" "$rootfs_dir"

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

  run_arch_makepkg "$build_user" "$build_dir"

  while IFS= read -r -d '' package_file; do
    built_packages+=("$package_file")
  done < <(find "$host_build_dir" -maxdepth 1 -type f -name "$package_name-*.pkg.tar.*" -print0 | sort -z)
  [ "${#built_packages[@]}" -eq 1 ] || \
    ci_die "expected one native Arch import package, found ${#built_packages[@]}"
  package_file=${built_packages[0]}
  assert_arch_local_signature_policy
  install_arch_local_package "$build_dir/$(basename "$package_file")"
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
  local mode_policy=${9:-normalize}
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

  case "$mode_policy" in
    normalize)
      ci_normalize_system_payload_modes "$stage"
      ci_assert_normalized_system_payload_modes "$stage"
      ;;
    preserve)
      ci_secure_preserved_payload_modes "$stage"
      ;;
    *) ci_die "unsupported native Arch package mode policy for $package_name: $mode_policy" ;;
  esac
  chown -R 0:0 "$stage"
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

  run_arch_makepkg "$build_user" "$build_dir"

  while IFS= read -r -d '' package_file; do
    built_packages+=("$package_file")
  done < <(find "$host_build_dir" -maxdepth 1 -type f -name "$package_name-*.pkg.tar.*" -print0 | sort -z)
  [ "${#built_packages[@]}" -eq 1 ] || \
    ci_die "expected one native Arch package for $package_name, found ${#built_packages[@]}"
  package_file=${built_packages[0]}
  assert_arch_local_signature_policy
  if [ "${#conflicts[@]}" -gt 0 ]; then
    install_arch_local_package "$build_dir/$(basename "$package_file")" 1
  else
    install_arch_local_package "$build_dir/$(basename "$package_file")"
  fi
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

install_tb321fu_wifi_firmware_package() {
  [ "$DESKTOP_PROFILE" = tablet-niri ] || return 0

  local source_root="$arch_import_stage/usr/lib/firmware/ath12k/WCN7850/hw2.0"
  local stage="$work_dir/tb321fu-wifi-firmware-stage"
  local package_manifest="$stage/usr/share/tb321fu-wifi-firmware/SHA256SUMS"
  local actual_files expected_files source_line hash relative custom_relative mode
  local -a wifi_dependencies=()
  local -a wifi_provides=(tb321fu-wifi-firmware)
  local -a wifi_conflicts=()
  local -a wifi_replaces=()

  [ -d "$source_root" ] || ci_die "TB321FU WCN7850 source directory is missing from the fixed device archive"
  [ -f "$TB321FU_WIFI_FIRMWARE_MANIFEST" ] || ci_die "TB321FU Wi-Fi firmware manifest is missing"
  [ "$(wc -l < "$TB321FU_WIFI_FIRMWARE_MANIFEST")" -eq 6 ] || \
    ci_die "TB321FU Wi-Fi firmware manifest must contain exactly six files"
  while read -r hash relative; do
    [[ $hash =~ ^[0-9a-f]{64}$ ]] || ci_die "invalid TB321FU Wi-Fi firmware hash: $hash"
    [[ $relative =~ ^usr/lib/firmware/ath12k/WCN7850/hw2\.0/[A-Za-z0-9._-]+$ ]] || \
      ci_die "unsafe TB321FU Wi-Fi firmware manifest path: $relative"
    [ -f "$arch_import_stage/$relative" ] && [ ! -L "$arch_import_stage/$relative" ] || \
      ci_die "TB321FU Wi-Fi firmware source is missing or unsafe: $relative"
    mode=$(stat -c '%a' "$arch_import_stage/$relative")
    [ "$mode" = 644 ] || ci_die "TB321FU Wi-Fi firmware has unsafe mode $mode: $relative"
  done < "$TB321FU_WIFI_FIRMWARE_MANIFEST"

  actual_files=$(cd "$arch_import_stage" && \
    find usr/lib/firmware/ath12k/WCN7850/hw2.0 -mindepth 1 -maxdepth 1 -type f -printf '%p\n' | LC_ALL=C sort)
  expected_files=$(awk '{print $2}' "$TB321FU_WIFI_FIRMWARE_MANIFEST" | LC_ALL=C sort)
  [ "$actual_files" = "$expected_files" ] || \
    ci_die "fixed device archive WCN7850 member list differs from the pinned manifest"
  [ -z "$(find "$source_root" -mindepth 1 -maxdepth 1 ! -type f -print -quit)" ] || \
    ci_die "fixed device archive WCN7850 directory contains a non-regular member"
  (cd "$arch_import_stage" && sha256sum -c "$TB321FU_WIFI_FIRMWARE_MANIFEST") || \
    ci_die "fixed device archive WCN7850 content differs from the pinned manifest"

  source_line="deb:$TB321FU_WIFI_OVERLAY_DEB:$TB321FU_WIFI_OVERLAY_DEB_SHA256"
  grep -Fxq "$source_line" "$arch_import_sources" || \
    ci_die "TB321FU Wi-Fi firmware did not originate from the pinned overlay package"

  install -d -m 0755 "$stage"
  while read -r hash relative; do
    custom_relative=${relative#usr/lib/firmware/}
    install -D -m 0644 "$arch_import_stage/$relative" \
      "$stage/usr/lib/firmware/tb321fu/$custom_relative"
    rm -f -- "$arch_import_stage/$relative"
  done < "$TB321FU_WIFI_FIRMWARE_MANIFEST"
  find "$arch_import_stage/usr/lib/firmware/ath12k/WCN7850" -depth -type d -empty -delete

  install -d -m 0755 "$(dirname "$package_manifest")"
  (
    cd "$stage"
    find ./usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0 -type f -print0 | \
      LC_ALL=C sort -z | xargs -0 sha256sum
  ) > "$package_manifest"
  cat > "$stage/usr/share/tb321fu-wifi-firmware/SOURCE.txt" <<SOURCE
device=Lenovo Y700 2025 TB321FU
source_archive=$TB321FU_DEVICE_ARCHIVE_URL
source_archive_sha256=$TB321FU_DEVICE_ARCHIVE_SHA256
source_package=$TB321FU_WIFI_OVERLAY_DEB
source_package_sha256=$TB321FU_WIFI_OVERLAY_DEB_SHA256
firmware_search_path=/usr/lib/firmware/tb321fu
board_2_bin_sha256=c896bc7782e252aa915849d5c9c47d109ecfe9f0fc5650fe771f7ba8f8eb77fb
SOURCE

  install_arch_native_stage_package \
    tb321fu-wifi-firmware \
    'Pinned WCN7850 firmware from the TB321FU-verified Kubuntu payload' \
    "$stage" \
    wifi_dependencies wifi_provides wifi_conflicts wifi_replaces
}

build_and_install_tablet_niri_source_package() {
  local package_name=$1
  local recipe_dir="$REPO_ROOT/packages/tablet-niri/$package_name"
  local build_user=tb321fu-pkgbuild
  local build_dir="/run/tablet-niri-${package_name}-build"
  local host_build_dir="$work_dir/tablet-niri-${package_name}-build"
  local host_build_bind="$rootfs_dir$build_dir"
  local package_file target
  local -a built_packages=() remaining_binds=()

  [[ $package_name =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || \
    ci_die "unsafe tablet-niri source package name: $package_name"
  [ -f "$recipe_dir/PKGBUILD" ] || \
    ci_die "tablet-niri source package recipe is missing: $package_name"
  if arch_chroot /usr/bin/id -u "$build_user" >/dev/null 2>&1; then
    ci_die "reserved Arch package-build account already exists: $build_user"
  fi

  install -d -m 0755 "$host_build_dir" "$host_build_bind"
  mount_bind "$host_build_dir" "$host_build_bind"
  rsync -aH --delete "$recipe_dir"/ "$host_build_dir"/
  arch_chroot /usr/bin/useradd --system --no-create-home --home-dir "$build_dir" \
    --shell /usr/bin/nologin "$build_user"
  chown -R "$(arch_chroot /usr/bin/id -u "$build_user")":"$(arch_chroot /usr/bin/id -g "$build_user")" \
    "$host_build_dir"

  run_arch_makepkg "$build_user" "$build_dir"
  while IFS= read -r -d '' package_file; do
    built_packages+=("$package_file")
  done < <(find "$host_build_dir" -maxdepth 1 -type f \
    -name "$package_name-*.pkg.tar.*" ! -name '*.sig' -print0 | sort -z)
  [ "${#built_packages[@]}" -eq 1 ] || \
    ci_die "expected one tablet-niri source package for $package_name, found ${#built_packages[@]}"
  package_file=${built_packages[0]}

  assert_arch_local_signature_policy
  install_arch_local_package "$build_dir/$(basename "$package_file")"
  arch_chroot /usr/bin/pacman -Q "$package_name" >/dev/null || \
    ci_die "tablet-niri source package identity is missing: $package_name"
  arch_chroot /usr/bin/pacman -Qkk "$package_name" >/dev/null || \
    ci_die "tablet-niri source package failed its file check: $package_name"

  arch_chroot /usr/bin/userdel "$build_user"
  umount -- "$host_build_bind" || \
    ci_die "failed to unmount tablet-niri source package build bind: $package_name"
  for target in "${bind_mounts[@]}"; do
    case "$target" in
      "$host_build_bind") ;;
      *) remaining_binds+=("$target") ;;
    esac
  done
  bind_mounts=("${remaining_binds[@]}")
  rmdir "$host_build_bind"
  rm -rf --one-file-system -- "$host_build_dir"
  ci_log "installed tablet-niri source package: $package_name"
}

assert_aarch64_elf() {
  local path=$1

  [ -f "$path" ] || ci_die "expected AArch64 ELF is missing: $path"
  readelf -h "$path" 2>/dev/null | grep -Eq 'Machine:[[:space:]]+AArch64$' || \
    ci_die "file is not an AArch64 ELF: $path"
}

record_tablet_niri_asset() {
  local package_name=$1
  local version=$2
  local url=$3
  local sha256=$4

  [[ $package_name != *$'\t'* && $version != *$'\t'* && $url != *$'\t'* ]] || \
    ci_die "invalid tablet-niri asset metadata"
  printf '%s\t%s\t%s\t%s\n' "$package_name" "$version" "$sha256" "$url" >> \
    "$third_party_manifest"
}

discard_exported_native_package() {
  local package_name=$1

  find "$OUTPUT_DIR" -maxdepth 1 -type f \
    -name "${OUTPUT_PREFIX}-${package_name}-*.pkg.tar.*" -delete
}

install_tablet_niri_binary_packages() {
  local asset_root="$REPO_ROOT/packages/tablet-niri/assets"
  local archive extract stage source_dir source_icon size special
  local zen_url='https://github.com/zen-browser/desktop/releases/download/1.21.8b/zen.linux-aarch64.tar.xz'
  local zen_sha256='0586ff279d7a1f93207fdb195c5586ef0d6813bd4f4318badcd0984adc39db39'
  local cc_url='https://github.com/farion1231/cc-switch/releases/download/v3.17.0/CC-Switch-v3.17.0-Linux-arm64.deb'
  local cc_sha256='8b1b2ba9cca007d0b5070670b7d8904d45789402f5ab915ba9d619cad3621052'
  local mihomo_url='https://github.com/mihomo-party-org/clash-party/releases/download/v2.0.0/mihomo-party-linux-2.0.0-arm64.deb'
  local mihomo_sha256='bfa25f96e27982d87232e017e6ee0f3f9ab7aa8d2d69a8f06e418b38ac3ab690'
  local codex_url='https://github.com/openai/codex/releases/download/rust-v0.144.6/codex-aarch64-unknown-linux-musl.tar.gz'
  local codex_sha256='8eddae5e6c009dff9ba51ae1bfe3bdd9ff4c1ccc93a48cc6860db1cd9fdf11be'
  local -a zen_dependencies=(gtk3 libxt mailcap shared-mime-info dbus-glib nss ffmpeg4.4)
  local -a zen_provides=('zen-browser=1.21.8b')
  local -a zen_conflicts=(zen-browser zen-browser-bin)
  local -a zen_replaces=()
  local -a cc_dependencies=(gtk3 libayatana-appindicator webkit2gtk-4.1)
  local -a cc_provides=('cc-switch=3.17.0')
  local -a cc_conflicts=(cc-switch cc-switch-bin)
  local -a cc_replaces=()
  local -a mihomo_dependencies=(
    gtk3 libnotify nss libxss libxtst xdg-utils at-spi2-core util-linux-libs
    libsecret libayatana-appindicator
  )
  local -a mihomo_provides=('mihomo-party=2.0.0')
  local -a mihomo_conflicts=(mihomo-party mihomo-party-bin)
  local -a mihomo_replaces=()
  local -a codex_dependencies=(ca-certificates git)
  local -a codex_provides=('codex-cli=0.144.6')
  local -a codex_conflicts=(codex-cli)
  local -a codex_replaces=()

  printf 'package\tupstream_version\tsha256\turl\n' > "$third_party_manifest"

  archive="$work_dir/zen-browser-aarch64.tar.xz"
  extract="$work_dir/zen-browser-extract"
  stage="$work_dir/tb321fu-zen-browser-stage"
  install -d -m 0755 "$extract" "$stage/opt"
  ci_download "$zen_url" "$archive" "$zen_sha256"
  ci_extract_archive "$archive" "$extract"
  source_dir="$extract/zen"
  [ -f "$source_dir/zen" ] || ci_die "Zen ARM64 archive has an unexpected layout"
  cp -a "$source_dir" "$stage/opt/zen-browser"
  install -D -m 0755 "$asset_root/zen-browser/zen-browser" "$stage/usr/bin/zen-browser"
  install -D -m 0644 "$asset_root/zen-browser/zen-browser.desktop" \
    "$stage/usr/share/applications/zen-browser.desktop"
  install -D -m 0644 "$asset_root/zen-browser/policies.json" \
    "$stage/opt/zen-browser/distribution/policies.json"
  for size in 16 32 48 64 128; do
    source_icon="$source_dir/browser/chrome/icons/default/default${size}.png"
    [ -f "$source_icon" ] || ci_die "Zen icon is missing: $size"
    install -D -m 0644 "$source_icon" \
      "$stage/usr/share/icons/hicolor/${size}x${size}/apps/zen-browser.png"
  done
  install -D -m 0644 /dev/stdin \
    "$stage/usr/share/tb321fu-third-party/zen-browser.source" <<EOF
version=1.21.8b
url=$zen_url
sha256=$zen_sha256
EOF
  assert_aarch64_elf "$stage/opt/zen-browser/zen"
  ci_validate_rootfs_overlay_tree "$stage"
  install_arch_native_stage_package \
    tb321fu-zen-browser 'Pinned ARM64 Zen Browser for TB321FU' "$stage" \
    zen_dependencies zen_provides zen_conflicts zen_replaces '' preserve
  discard_exported_native_package tb321fu-zen-browser
  record_tablet_niri_asset tb321fu-zen-browser 1.21.8b "$zen_url" "$zen_sha256"

  archive="$work_dir/cc-switch-arm64.deb"
  stage="$work_dir/tb321fu-cc-switch-stage"
  install -d -m 0755 "$stage"
  ci_download "$cc_url" "$archive" "$cc_sha256"
  dpkg-deb -x "$archive" "$stage"
  assert_aarch64_elf "$stage/usr/bin/cc-switch"
  install -D -m 0644 /dev/stdin \
    "$stage/usr/share/tb321fu-third-party/cc-switch.source" <<EOF
version=3.17.0
url=$cc_url
sha256=$cc_sha256
EOF
  ci_validate_rootfs_overlay_tree "$stage"
  install_arch_native_stage_package \
    tb321fu-cc-switch 'Pinned ARM64 CC Switch for TB321FU' "$stage" \
    cc_dependencies cc_provides cc_conflicts cc_replaces '' preserve
  discard_exported_native_package tb321fu-cc-switch
  record_tablet_niri_asset tb321fu-cc-switch 3.17.0 "$cc_url" "$cc_sha256"

  archive="$work_dir/mihomo-party-arm64.deb"
  stage="$work_dir/tb321fu-mihomo-party-stage"
  install -d -m 0755 "$stage"
  ci_download "$mihomo_url" "$archive" "$mihomo_sha256"
  dpkg-deb -x "$archive" "$stage"
  install -D -m 0755 "$asset_root/mihomo-party/mihomo-party" \
    "$stage/usr/bin/mihomo-party"
  special=$(find "$stage" -xdev -type f -perm /6000 -print -quit)
  [ -z "$special" ] || ci_die "Mihomo Party archive contains a privilege bit: $special"
  assert_aarch64_elf "$stage/opt/clash-party/mihomo-party"
  assert_aarch64_elf "$stage/opt/clash-party/resources/sidecar/mihomo"
  assert_aarch64_elf "$stage/opt/clash-party/resources/sidecar/mihomo-alpha"
  assert_aarch64_elf "$stage/opt/clash-party/resources/sidecar/mihomo-smart"
  install -D -m 0644 /dev/stdin \
    "$stage/usr/share/tb321fu-third-party/mihomo-party.source" <<EOF
version=2.0.0
url=$mihomo_url
sha256=$mihomo_sha256
privilege_mode=unprivileged
EOF
  ci_validate_rootfs_overlay_tree "$stage"
  install_arch_native_stage_package \
    tb321fu-mihomo-party 'Pinned unprivileged ARM64 Mihomo Party for TB321FU' "$stage" \
    mihomo_dependencies mihomo_provides mihomo_conflicts mihomo_replaces '' preserve
  discard_exported_native_package tb321fu-mihomo-party
  record_tablet_niri_asset tb321fu-mihomo-party 2.0.0 "$mihomo_url" "$mihomo_sha256"

  archive="$work_dir/codex-aarch64.tar.gz"
  extract="$work_dir/codex-aarch64-extract"
  stage="$work_dir/tb321fu-codex-cli-stage"
  install -d -m 0755 "$extract" "$stage"
  ci_download "$codex_url" "$archive" "$codex_sha256"
  ci_extract_archive "$archive" "$extract"
  source_dir="$extract/codex-aarch64-unknown-linux-musl"
  assert_aarch64_elf "$source_dir"
  install -D -m 0755 "$source_dir" "$stage/usr/bin/codex"
  install -D -m 0644 /dev/stdin \
    "$stage/usr/share/tb321fu-third-party/codex-cli.source" <<EOF
version=0.144.6
url=$codex_url
sha256=$codex_sha256
EOF
  ci_validate_rootfs_overlay_tree "$stage"
  install_arch_native_stage_package \
    tb321fu-codex-cli 'Pinned official ARM64 Codex CLI for TB321FU' "$stage" \
    codex_dependencies codex_provides codex_conflicts codex_replaces '' preserve
  discard_exported_native_package tb321fu-codex-cli
  record_tablet_niri_asset tb321fu-codex-cli 0.144.6 "$codex_url" "$codex_sha256"
}

apply_tablet_niri_profile() {
  local root=$1
  local overlay="$REPO_ROOT/profiles/tablet-niri/rootfs-overlay"

  [ -d "$overlay" ] || ci_die "tablet-niri rootfs overlay is missing"
  ci_validate_rootfs_overlay_tree "$overlay"
  rsync -aH --chown=0:0 "$overlay"/ "$root"/

  chmod 0755 \
    "$root/usr/local/bin/tb321fu-osk-toggle" \
    "$root/usr/local/bin/tb321fu-suspend" \
    "$root/usr/local/libexec/tb321fu-grow-rootfs" \
    "$root/usr/local/libexec/tb321fu-bt-nap" \
    "$root/usr/local/libexec/tb321fu-usb-rescue" \
    "$root/usr/local/libexec/tb321fu-pre-upgrade-snapshot" \
    "$root/usr/lib/systemd/system-sleep/tb321fu-suspend-log"
  chmod 0644 \
    "$root/etc/systemd/user/noctalia.service" \
    "$root/etc/systemd/user/fcitx5-tablet.service" \
    "$root/etc/systemd/system/tb321fu-grow-rootfs.service" \
    "$root/etc/systemd/system/tb321fu-bt-nap.service" \
    "$root/etc/systemd/system/tb321fu-usb-rescue.service" \
    "$root/etc/modules-load.d/60-tb321fu-rescue.conf"
  chmod 0600 \
    "$root/etc/NetworkManager/system-connections/tb321fu-rescue-usb.nmconnection" \
    "$root/etc/NetworkManager/system-connections/tb321fu-rescue-bt.nmconnection"

  rm -f "$root"/etc/ssh/ssh_host_*
  : > "$root/etc/machine-id"
  rm -f "$root/var/lib/dbus/machine-id"
  install -d -m 0755 "$root/var/lib/dbus"
  ln -s /etc/machine-id "$root/var/lib/dbus/machine-id"
  install -d -m 2755 "$root/var/log/journal"
  arch_chroot /usr/bin/chown root:systemd-journal /var/log/journal

  arch_chroot /usr/bin/niri validate -c /etc/skel/.config/niri/config.kdl
  arch_chroot /usr/bin/noctalia config validate /etc/skel/.config/noctalia/config.toml
}

freeze_tablet_niri_custom_packages() {
  local root=$1
  local ignore_packages='noctalia wvkbd paru tb321fu-imported-release-payload tb321fu-camera-stack tb321fu-wifi-firmware tb321fu-zen-browser tb321fu-cc-switch tb321fu-mihomo-party tb321fu-codex-cli'

  if grep -Eq '^[[:space:]]*IgnorePkg[[:space:]]*=' "$root/etc/pacman.conf"; then
    ci_die "tablet-niri refuses to merge an existing IgnorePkg policy"
  fi
  sed -i "/^\[options\]$/a IgnorePkg = $ignore_packages" "$root/etc/pacman.conf"
  grep -Fx "IgnorePkg = $ignore_packages" "$root/etc/pacman.conf" >/dev/null || \
    ci_die "tablet-niri custom package freeze policy was not installed"
}

install_tablet_niri_authorized_keys() {
  local root=$1
  local user_home="$root/home/$DEFAULT_USER_NAME"
  local group_name line

  [ -n "$DEFAULT_USER_AUTHORIZED_KEYS" ] || \
    ci_die "tablet-niri requires DEFAULT_USER_AUTHORIZED_KEYS from a repository secret"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [ -n "$line" ] || continue
    [[ $line =~ ^(ssh-ed25519|sk-ssh-ed25519@openssh.com|ecdsa-sha2-nistp256|sk-ecdsa-sha2-nistp256@openssh.com|ssh-rsa)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] || \
      ci_die "DEFAULT_USER_AUTHORIZED_KEYS contains an unsupported public-key line"
  done <<< "$DEFAULT_USER_AUTHORIZED_KEYS"

  group_name=$(arch_chroot id -gn "$DEFAULT_USER_NAME")
  install -d -m 0700 "$user_home/.ssh"
  printf '%s\n' "$DEFAULT_USER_AUTHORIZED_KEYS" | sed '/^[[:space:]]*$/d' > \
    "$user_home/.ssh/authorized_keys"
  chmod 0600 "$user_home/.ssh/authorized_keys"
  chroot "$root" chown -R "$DEFAULT_USER_NAME:$group_name" "/home/$DEFAULT_USER_NAME/.ssh"
}

verify_tablet_niri_profile() {
  local root=$1
  local package path mode hash_field target
  local -a required_packages=(
    noctalia wvkbd paru dnsmasq
    tb321fu-wifi-firmware
    tb321fu-zen-browser tb321fu-cc-switch tb321fu-mihomo-party tb321fu-codex-cli
  )
  local -a forbidden_packages=(
    plasma-meta plasma-desktop plasma-workspace sddm plasma-keyboard
  )
  local -a custom_executables=(
    /opt/zen-browser/zen
    /usr/bin/cc-switch
    /opt/clash-party/mihomo-party
    /opt/clash-party/resources/sidecar/mihomo
    /opt/clash-party/resources/sidecar/mihomo-alpha
    /opt/clash-party/resources/sidecar/mihomo-smart
    /usr/bin/codex
  )

  for package in "${required_packages[@]}"; do
    arch_chroot /usr/bin/pacman -Q "$package" >/dev/null || \
      ci_die "required tablet-niri package is missing: $package"
    arch_chroot /usr/bin/pacman -Qkk "$package" >/dev/null || \
      ci_die "required tablet-niri package failed its file check: $package"
  done
  for package in "${forbidden_packages[@]}"; do
    if arch_chroot /usr/bin/pacman -Q "$package" >/dev/null 2>&1; then
      ci_die "forbidden Plasma package is installed in tablet-niri: $package"
    fi
  done

  for path in "${custom_executables[@]}"; do
    [ -x "$root$path" ] || ci_die "required tablet-niri executable is missing: $path"
    mode=$(stat -c '%a' "$root$path")
    case "$mode" in
      4???|2???|6???|7???) ci_die "tablet-niri executable has a privilege bit: $path ($mode)" ;;
    esac
  done

  hash_field=$(arch_chroot /usr/bin/awk -F: -v user="$DEFAULT_USER_NAME" \
    '$1 == user { print substr($2, 1, 3); exit }' /etc/shadow)
  [ "$hash_field" = '$6$' ] || ci_die "tablet-niri user password is not a SHA-512 hash"
  target=$(arch_chroot /usr/bin/awk -F: '$1 == "root" { print $2; exit }' /etc/shadow)
  [[ $target == '!'* ]] || ci_die "tablet-niri root account is not locked"

  path="$root/home/$DEFAULT_USER_NAME/.ssh/authorized_keys"
  [ -s "$path" ] || ci_die "tablet-niri authorized_keys is missing"
  [ "$(stat -c '%a' "$path")" = 600 ] || ci_die "tablet-niri authorized_keys mode is not 0600"
  [ -z "$(find "$root/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*_key' -print -quit)" ] || \
    ci_die "private SSH host key leaked into tablet-niri image"

  for path in \
    "$root/home/$DEFAULT_USER_NAME/.codex" \
    "$root/home/$DEFAULT_USER_NAME/.cc-switch" \
    "$root/home/$DEFAULT_USER_NAME/.config/mihomo-party" \
    "$root/home/$DEFAULT_USER_NAME/.config/clash"; do
    [ ! -e "$path" ] || ci_die "credential-bearing user config leaked into tablet-niri image: $path"
  done
  local connection_dir="$root/etc/NetworkManager/system-connections"
  local unexpected_connection
  unexpected_connection=$(find "$connection_dir" -maxdepth 1 -type f \
    ! -name tb321fu-rescue-usb.nmconnection \
    ! -name tb321fu-rescue-bt.nmconnection -print -quit 2>/dev/null)
  [ -z "$unexpected_connection" ] || \
    ci_die "unexpected NetworkManager profile leaked into tablet-niri image: $unexpected_connection"
  for path in \
    "$connection_dir/tb321fu-rescue-usb.nmconnection" \
    "$connection_dir/tb321fu-rescue-bt.nmconnection"; do
    [ -f "$path" ] || ci_die "required rescue connection is missing: $path"
    [ "$(stat -c '%a' "$path")" = 600 ] || \
      ci_die "rescue connection mode is not 0600: $path"
  done
  grep -Fxq 'address1=10.77.0.1/24' \
    "$connection_dir/tb321fu-rescue-usb.nmconnection" || \
    ci_die "USB rescue address is missing"
  grep -Fxq 'address1=10.78.0.1/24' \
    "$connection_dir/tb321fu-rescue-bt.nmconnection" || \
    ci_die "Bluetooth rescue address is missing"
  grep -Fxq 'type=nap' "$connection_dir/tb321fu-rescue-bt.nmconnection" || \
    ci_die "Bluetooth rescue profile is not a NAP"

  for target in sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target; do
    path="$root/etc/systemd/system/$target"
    if [ -L "$path" ] && [ "$(readlink "$path")" = /dev/null ]; then
      ci_die "tablet-niri must not mask manual sleep target: $target"
    fi
  done

  arch_chroot /usr/bin/niri validate -c /home/$DEFAULT_USER_NAME/.config/niri/config.kdl
  arch_chroot /usr/bin/noctalia config validate /home/$DEFAULT_USER_NAME/.config/noctalia/config.toml
  unshare --net -- chroot "$root" /usr/bin/nft --check --file /etc/nftables.conf
}

enable_y700_device_services() {
  local root=$1

  install -d -m 0755 "$root/etc/systemd/system/multi-user.target.wants"
  for service in y700-audio-card-guard.service; do
    if [ -f "$root/etc/systemd/system/$service" ]; then
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
  if [ ! -L "$root/usr/lib/libaperture-0.so.0" ] ||
     [ "$(readlink "$root/usr/lib/libaperture-0.so.0")" != /usr/lib/aarch64-linux-gnu/libaperture-0.so.0 ]; then
    ln -sfn /usr/lib/aarch64-linux-gnu/libaperture-0.so.0 "$root/usr/lib/libaperture-0.so.0"
  fi
fi
if [ -L "$source_multiarch/libaperture-0.so" ]; then
  target=$(readlink "$source_multiarch/libaperture-0.so")
  [ "$target" = libaperture-0.so.0 ] || { echo "unsafe libaperture symlink target: $target" >&2; exit 1; }
  if [ ! -L "$root/usr/lib/libaperture-0.so" ] ||
     [ "$(readlink "$root/usr/lib/libaperture-0.so")" != "$target" ]; then
    ln -sfn "$target" "$root/usr/lib/libaperture-0.so"
  fi
fi

spa=$multiarch/spa-0.2/libcamera/libspa-libcamera.so
[ -f "$spa" ] || { echo "missing TB321FU camera SPA source: $spa" >&2; exit 1; }
install -d -m 0755 "$root/usr/lib/spa-0.2/libcamera" "$root/usr/lib/gstreamer-1.0"
spa_target=$root/usr/lib/spa-0.2/libcamera/libspa-libcamera.so
if [ ! -f "$spa_target" ] || ! cmp -s "$spa" "$spa_target"; then
  install -m 0644 "$spa" "$spa_target"
fi
gst_target=$root/usr/lib/gstreamer-1.0/libgstlibcamera.so
gst_source=/opt/libcamera-y700/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so
if [ ! -L "$gst_target" ] || [ "$(readlink "$gst_target")" != "$gst_source" ]; then
  ln -sfn "$gst_source" "$gst_target"
fi
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
  local -a packages=(tb321fu-camera-stack tb321fu-wifi-firmware)
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
  local -a wifi_paths=(
    /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/Notice.txt.zst
    /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/amss.bin.zst
    /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin
    /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin.zst
    /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/m3.bin.zst
    /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/regdb.bin
    /usr/share/tb321fu-wifi-firmware/SHA256SUMS
    /usr/share/tb321fu-wifi-firmware/SOURCE.txt
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
  for path in "${wifi_paths[@]}"; do
    owner=$(arch_chroot /usr/bin/pacman -Qoq "$path") || \
      ci_die "TB321FU Wi-Fi payload is not pacman-owned: $path"
    [ "$owner" = tb321fu-wifi-firmware ] || \
      ci_die "TB321FU Wi-Fi payload has wrong pacman owner $owner: $path"
  done
  owner=$(arch_chroot /usr/bin/pacman -Qoq \
    /usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin) || \
    ci_die "generic WCN7850 board file is not pacman-owned"
  [ "$owner" = linux-firmware-atheros ] || \
    ci_die "generic WCN7850 board file has unexpected owner: $owner"
  [ "$(sha256sum "$rootfs_dir/usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin" | awk '{print $1}')" = \
    c896bc7782e252aa915849d5c9c47d109ecfe9f0fc5650fe771f7ba8f8eb77fb ] || \
    ci_die "TB321FU WCN7850 board file hash mismatch"
  (
    cd "$rootfs_dir"
    sha256sum -c ./usr/share/tb321fu-wifi-firmware/SHA256SUMS
  ) || ci_die "TB321FU Wi-Fi firmware package checksum mismatch"
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
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  printf 'Server = file:///run/tb321fu-pacman-lock/repo/$arch/$repo\n' > \
    "$rootfs_dir/etc/pacman.d/mirrorlist"
else
  printf 'Server = %s\n' "$ARCH_MIRROR" > "$rootfs_dir/etc/pacman.d/mirrorlist"
fi
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
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  install -d -m 0755 "$rootfs_dir/run/tb321fu-pacman-lock"
  mount_bind "$PACMAN_PACKAGE_LOCK_DIR" "$rootfs_dir/run/tb321fu-pacman-lock"
fi

ci_log "initializing pacman keyring"
arch_chroot /usr/bin/pacman-key --init
arch_chroot /usr/bin/pacman-key --populate archlinuxarm
assert_arch_remote_signature_policy
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  arch_chroot_offline /usr/bin/pacman -Sy --noconfirm --needed archlinuxarm-keyring
  arch_chroot_offline /usr/bin/pacman-key --populate archlinuxarm
  mapfile -t packages < "$requested_packages_file"
else
  arch_chroot /usr/bin/getent hosts os.archlinuxarm.org >/dev/null
  arch_chroot /usr/bin/pacman -Sy --noconfirm --needed archlinuxarm-keyring
  mapfile -t packages < <(build_package_list)
fi
printf '%s\n' "${packages[@]}" > "$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.packages"
ci_log "installing Arch packages: ${#packages[@]} packages"
assert_arch_remote_signature_policy
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  arch_chroot_offline /usr/bin/pacman -Syu --noconfirm --needed --disable-download-timeout -- "${packages[@]}"
  arch_chroot_offline /usr/bin/pacman -Q | LC_ALL=C sort > "$work_dir/locked-installed-packages.txt"
  cmp -s "$PACMAN_PACKAGE_LOCK_DIR/expected-installed-packages.txt" \
    "$work_dir/locked-installed-packages.txt" || \
    ci_die "locked pacman transaction produced a different installed package set"
else
  arch_chroot /usr/bin/pacman -Syu --noconfirm --needed --disable-download-timeout -- "${packages[@]}"
fi

if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  ci_log "building pinned tablet-niri source packages"
  build_and_install_tablet_niri_source_package noctalia
  build_and_install_tablet_niri_source_package wvkbd
  build_and_install_tablet_niri_source_package paru
  ci_log "packaging pinned tablet-niri ARM64 applications"
  install_tablet_niri_binary_packages
  apply_tablet_niri_profile "$rootfs_dir"
fi

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
  arch_chroot /usr/bin/useradd -m -s /bin/bash -G users,video,audio,input,storage,power,render "$DEFAULT_USER_NAME"
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

if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  install_tablet_niri_authorized_keys "$rootfs_dir"
  install -d -m 0755 \
    "$rootfs_dir/home/$DEFAULT_USER_NAME/Pictures" \
    "$rootfs_dir/home/$DEFAULT_USER_NAME/Pictures/Screenshots"
  default_user_group=$(arch_chroot id -gn "$DEFAULT_USER_NAME")
  chroot "$rootfs_dir" chown -R "$DEFAULT_USER_NAME:$default_user_group" \
    "/home/$DEFAULT_USER_NAME/Pictures"
else
  write_plasma_tablet_config "$rootfs_dir"
  if ci_bool "$INSTALL_FCITX5_CHINESE"; then
    write_fcitx5_config "$rootfs_dir"
  fi
  copy_skel_to_user "$rootfs_dir"
fi

ci_log "enabling system services"
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  required_system_units=(
    NetworkManager.service sshd.service greetd.service bluetooth.service
    nftables.service tb321fu-grow-rootfs.service tb321fu-usb-rescue.service
    tb321fu-bt-nap.service
    serial-getty@ttyGS0.service systemd-timesyncd.service
  )
  required_user_units=(
    pipewire.socket pipewire-pulse.socket wireplumber.service
    noctalia.service fcitx5-tablet.service
  )
else
  required_system_units=(NetworkManager.service sshd.service sddm.service bluetooth.service)
  required_user_units=(pipewire.socket pipewire-pulse.socket wireplumber.service)
fi
systemctl --root="$rootfs_dir" enable "${required_system_units[@]}"
systemctl --root="$rootfs_dir" --global enable "${required_user_units[@]}"
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  systemctl --root="$rootfs_dir" set-default graphical.target
  [ "$(systemctl --root="$rootfs_dir" get-default)" = graphical.target ] || \
    ci_die "tablet-niri default target is not graphical.target"
fi
for required_unit in "${required_system_units[@]}"; do
  systemctl --root="$rootfs_dir" is-enabled --quiet "$required_unit" ||
    ci_die "required system service was not enabled: $required_unit"
done
for required_unit in "${required_user_units[@]}"; do
  systemctl --root="$rootfs_dir" --global is-enabled --quiet "$required_unit" ||
    ci_die "required global user service was not enabled: $required_unit"
done

if [ "$DESKTOP_PROFILE" != tablet-niri ] && ci_bool "$SDDM_AUTOLOGIN"; then
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
install_tb321fu_wifi_firmware_package
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

suspend_chroot_runtime

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
remove_tablet_niri_desktop_payload "$rootfs_dir"
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
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  freeze_tablet_niri_custom_packages "$rootfs_dir"
fi

ci_log "generating module dependency files for $KERNEL_VERSION"
depmod -b "$rootfs_dir" "$KERNEL_VERSION"
arch_chroot /usr/bin/ldconfig
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  arch_chroot /usr/bin/update-desktop-database /usr/share/applications
  arch_chroot /usr/bin/gtk-update-icon-cache --force /usr/share/icons/hicolor
fi

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
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  verify_tablet_niri_profile "$rootfs_dir"
fi
arch_chroot /usr/bin/pacman -Q | LC_ALL=C sort > \
  "$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.packages"

cat > "$build_info" <<INFO
generated=$(ci_iso8601_timestamp)
distribution=Arch Linux ARM
arch=aarch64
arch_rootfs_url=$ARCH_ROOTFS_URL
arch_rootfs_sha256=$ARCH_ROOTFS_SHA256
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
third_party_asset_manifest=$([ -f "$third_party_manifest" ] && basename "$third_party_manifest" || true)
device_deb_archive=${DEVICE_DEB_ARCHIVE:-}
device_deb_archive_sha256=${DEVICE_DEB_ARCHIVE_SHA256:-}
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
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  cat >> "$build_info" <<INFO
pacman_package_lock_manifest_sha256=$PACMAN_PACKAGE_LOCK_MANIFEST_SHA256
pacman_package_lock_seed_run_id=$(awk -F= '$1 == "seed_run_id" { print $2; exit }' "$PACMAN_PACKAGE_LOCK_DIR/LOCK-INFO.env")
pacman_package_lock_seed_commit=$(awk -F= '$1 == "seed_commit" { print $2; exit }' "$PACMAN_PACKAGE_LOCK_DIR/LOCK-INFO.env")
INFO
  cat >> "$build_info" <<'INFO'
rescue_usb_network=cdc-ncm:10.77.0.1/24:networkmanager-shared
rescue_usb_console=cdc-acm:ttyGS0:password-login
rescue_bluetooth_network=nap:10.78.0.1/24:networkmanager-shared
rescue_module_policy=pmic_glink,ucsi_glink,ath12k_wifi7,bnep,libcomposite,usb_f_acm,usb_f_ncm
wifi_firmware_package=tb321fu-wifi-firmware
wifi_firmware_search_path=/usr/lib/firmware/tb321fu
wifi_board_2_bin_sha256=c896bc7782e252aa915849d5c9c47d109ecfe9f0fc5650fe771f7ba8f8eb77fb
INFO
fi

if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  for lock_member in LOCK-INFO.env SHA256SUMS PACKAGE-FILES.tsv requested-packages.txt expected-installed-packages.txt; do
    install -m 0644 "$PACMAN_PACKAGE_LOCK_DIR/$lock_member" \
      "$OUTPUT_DIR/${OUTPUT_PREFIX}-pacman-lock.$lock_member"
  done
fi

ci_log "writing rootfs manifest"
(cd "$rootfs_dir" && find . -xdev -printf '%y\t%u\t%g\t%m\t%s\t%p\n' | sort) > "$manifest"

finalize_rootfs_mount
ci_e2fsck_repair "$rootfs_img"

ci_log "checksumming rootfs image"
raw_sha_file="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.raw.sha256"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img")" > "$(basename "$raw_sha_file")")

checksum_file="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.SHA256SUMS"
rm -f "$checksum_file"
checksum_inputs=(
  "$(basename "$build_info")"
  "$(basename "$manifest")"
  "$(basename "$raw_sha_file")"
  "$(basename "$OUTPUT_PREFIX")-rootfs.packages"
)
if [ -f "$third_party_manifest" ]; then
  checksum_inputs+=("$(basename "$third_party_manifest")")
fi
if [ "$DESKTOP_PROFILE" = tablet-niri ]; then
  checksum_inputs+=(
    "$(basename "$OUTPUT_PREFIX")-pacman-lock.LOCK-INFO.env"
    "$(basename "$OUTPUT_PREFIX")-pacman-lock.SHA256SUMS"
    "$(basename "$OUTPUT_PREFIX")-pacman-lock.PACKAGE-FILES.tsv"
    "$(basename "$OUTPUT_PREFIX")-pacman-lock.requested-packages.txt"
    "$(basename "$OUTPUT_PREFIX")-pacman-lock.expected-installed-packages.txt"
  )
fi
(cd "$OUTPUT_DIR" && sha256sum "${checksum_inputs[@]}" > "$(basename "$checksum_file")")

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

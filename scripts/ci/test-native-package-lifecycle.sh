#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"
GPU_SOURCE="$SCRIPT_DIR/../../source/tb321fu-ksystemstats-adreno-freq/tb321fu_gpu.cpp"

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
root="$tmp/root"
helper="$SCRIPT_DIR/payloads/tb321fu-disable-stock-ksystemstats-gpu"
install_script="$SCRIPT_DIR/payloads/tb321fu-ksystemstats-gpu.install"
stock=/usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_gpu.so
disabled=$stock.disabled-tb321fu-adreno

install -D -m 0755 "$helper" "$root/usr/lib/tb321fu/disable-stock-ksystemstats-gpu"
install -D -m 0644 /dev/stdin "$root$stock" <<'STOCK_V1'
stock-provider-v1
STOCK_V1

run_helper() {
  "$root/usr/lib/tb321fu/disable-stock-ksystemstats-gpu" --test-root "$root" "$1"
}

# Install and package-upgrade callbacks keep the generic provider inactive.
run_helper disable
[ ! -e "$root$stock" ] || fail "stock provider remained active after install"
cmp -s "$root$disabled" <(printf 'stock-provider-v1\n') || fail "install did not preserve the stock provider"
run_helper disable

# A ksystemstats upgrade writes a fresh stock plugin. The pacman hook helper
# atomically replaces the disabled backup with those new bytes.
printf 'stock-provider-v2\n' > "$root$stock"
run_helper disable
[ ! -e "$root$stock" ] || fail "stock provider remained active after dependency upgrade"
cmp -s "$root$disabled" <(printf 'stock-provider-v2\n') || fail "dependency upgrade did not refresh disabled bytes"

# Removal restores the current stock bytes. An aborted removal can run the
# install callback again and return to the installed state without data loss.
run_helper restore
cmp -s "$root$stock" <(printf 'stock-provider-v2\n') || fail "remove did not restore stock provider"
[ ! -e "$root$disabled" ] || fail "disabled provider remained after restore"
run_helper disable
[ ! -e "$root$stock" ] || fail "rollback did not disable the restored provider"
run_helper restore
cmp -s "$root$stock" <(printf 'stock-provider-v2\n') || fail "post-remove changed restored bytes"

# Never overwrite an active provider if both names unexpectedly exist.
printf 'unexpected-disabled\n' > "$root$disabled"
if run_helper restore >/dev/null 2>&1; then
  fail "ambiguous restore was accepted"
fi
cmp -s "$root$stock" <(printf 'stock-provider-v2\n') || fail "ambiguous restore damaged active provider"
cmp -s "$root$disabled" <(printf 'unexpected-disabled\n') || fail "ambiguous restore damaged disabled provider"

bash -n "$install_script"
grep -Fq '/usr/lib/tb321fu/disable-stock-ksystemstats-gpu disable' "$install_script" || \
  fail "package install/upgrade callback does not disable the stock provider"
grep -Fq '/usr/lib/tb321fu/disable-stock-ksystemstats-gpu restore' "$install_script" || \
  fail "package remove callback does not restore the stock provider"
if grep -Fq TB321FU_ROOT "$install_script"; then
  fail "production pacman callbacks accept ambient root redirection"
fi
grep -Fq "/usr/bin/bash -c 'cd -- \"\$1\" && shift && exec \"\$@\"' bash \"\$build_dir\"" \
  "$BUILD_SCRIPT" || fail "native package build does not enter its PKGBUILD directory"

# Execute the camera staging helpers directly from the build script. Imported
# Ubuntu camera files are excluded from the generic package, while libaperture
# is transferred byte-for-byte into the native camera package.
extract_shell_function() {
  local name=$1
  awk -v signature="$name() {" '
    $0 == signature { copying = 1 }
    copying { print }
    copying && $0 == "}" { exit }
  ' "$BUILD_SCRIPT"
}
ci_die() { fail "$*"; }
eval "$(extract_shell_function stage_arch_camera_supplement)"
eval "$(extract_shell_function remove_arch_native_camera_package_paths)"
eval "$(extract_shell_function adapt_ubuntu_multilib_paths_for_arch)"
eval "$(extract_shell_function prepare_arch_import_module_dependencies)"
eval "$(extract_shell_function remove_generated_module_dependency_files)"
eval "$(extract_shell_function remove_existing_identical_arch_import_members)"

module_stage="$tmp/module-stage"
kernel_version=7.1.1-test
mkdir -p "$module_stage/usr/lib/modules/$kernel_version"
depmod_args=
depmod() { printf -v depmod_args '%q ' "$@"; }
prepare_arch_import_module_dependencies "$module_stage" "$kernel_version"
[ "$depmod_args" = "-b $module_stage $kernel_version " ] || \
  fail "Arch import depmod arguments are wrong: $depmod_args"
[ ! -e "$module_stage/lib" ] && [ ! -L "$module_stage/lib" ] || \
  fail "temporary Arch import /lib compatibility link remained"
touch \
  "$module_stage/usr/lib/modules/$kernel_version/modules.dep" \
  "$module_stage/usr/lib/modules/$kernel_version/modules.dep.bin" \
  "$module_stage/usr/lib/modules/$kernel_version/modules.builtin" \
  "$module_stage/usr/lib/modules/$kernel_version/modules.order"
remove_generated_module_dependency_files "$module_stage" "$kernel_version"
[ ! -e "$module_stage/usr/lib/modules/$kernel_version/modules.dep" ] || \
  fail "generated modules.dep remained in imported package"
[ ! -e "$module_stage/usr/lib/modules/$kernel_version/modules.dep.bin" ] || \
  fail "generated modules.dep.bin remained in imported package"
[ -e "$module_stage/usr/lib/modules/$kernel_version/modules.builtin" ] || \
  fail "static modules.builtin was removed from imported package"
[ -e "$module_stage/usr/lib/modules/$kernel_version/modules.order" ] || \
  fail "static modules.order was removed from imported package"

dedupe_stage="$tmp/dedupe-stage"
dedupe_root="$tmp/dedupe-root"
arch_owner=
arch_chroot() {
  [ "$1 $2" = '/usr/bin/pacman -Qoq' ] || return 1
  [ -n "$arch_owner" ] || return 1
  printf '%s\n' "$arch_owner"
}
ci_log() { :; }
install -D -m 0644 /dev/stdin "$dedupe_stage/usr/share/test/identical" <<'IDENTICAL'
same bytes
IDENTICAL
install -D -m 0644 "$dedupe_stage/usr/share/test/identical" \
  "$dedupe_root/usr/share/test/identical"
remove_existing_identical_arch_import_members "$dedupe_stage" "$dedupe_root"
[ ! -e "$dedupe_stage/usr/share/test/identical" ] || \
  fail "identical rootfs file remained in imported package"
arch_owner=iio-sensor-proxy
printf 'Ubuntu monitor-sensor\n' > "$dedupe_stage/owned"
printf 'Arch monitor-sensor\n' > "$dedupe_root/owned"
remove_existing_identical_arch_import_members "$dedupe_stage" "$dedupe_root"
[ ! -e "$dedupe_stage/owned" ] || fail "Arch-owned collision remained in imported package"
arch_owner=
printf 'different bytes\n' > "$dedupe_stage/different"
printf 'existing bytes\n' > "$dedupe_root/different"
if (remove_existing_identical_arch_import_members "$dedupe_stage" "$dedupe_root") >/dev/null 2>&1; then
  fail "differing rootfs collision was silently removed"
fi

import_stage="$tmp/import-stage"
arch_camera_supplement_stage="$tmp/camera-supplement-stage"
install -D -m 0644 /dev/stdin \
  "$import_stage/opt/libcamera-y700/bin/cam" <<'OLD_CAMERA'
old-camera
OLD_CAMERA
install -D -m 0644 /dev/stdin \
  "$import_stage/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera/libspa-libcamera.so" <<'OLD_SPA'
old-spa
OLD_SPA
install -D -m 0644 /dev/stdin \
  "$import_stage/usr/lib/aarch64-linux-gnu/libaperture-0.so.0" <<'APERTURE'
aperture
APERTURE
ln -s libaperture-0.so.0 "$import_stage/usr/lib/aarch64-linux-gnu/libaperture-0.so"
stage_arch_camera_supplement "$import_stage"
remove_arch_native_camera_package_paths "$import_stage"
[ ! -e "$import_stage/opt/libcamera-y700" ] || fail "camera payload remained in generic import stage"
[ ! -e "$import_stage/usr/lib/aarch64-linux-gnu/spa-0.2/libcamera" ] || \
  fail "camera SPA payload remained in generic import stage"
[ ! -e "$import_stage/usr/lib/aarch64-linux-gnu/libaperture-0.so.0" ] || \
  fail "libaperture remained in the generic import package"
[ -f "$arch_camera_supplement_stage/usr/lib/aarch64-linux-gnu/libaperture-0.so.0" ] || \
  fail "canonical imported libaperture was not staged for the camera package"

camera_stage="$tmp/camera-stage"
camera_source="$SCRIPT_DIR/../../source/tb321fu-camera-rootfs-overlay/rootfs-overlay"
cp -a "$camera_source" "$camera_stage"
cp -a "$arch_camera_supplement_stage"/. "$camera_stage"/
adapt_ubuntu_multilib_paths_for_arch "$camera_stage"
[ "$(readlink "$camera_stage/usr/lib/libaperture-0.so.0")" = \
  /usr/lib/aarch64-linux-gnu/libaperture-0.so.0 ] || fail "camera package ABI symlink is wrong"
[ "$(readlink "$camera_stage/usr/lib/libaperture-0.so")" = libaperture-0.so.0 ] || \
  fail "camera package development symlink is wrong"
[ "$(readlink "$camera_stage/usr/lib/gstreamer-1.0/libgstlibcamera.so")" = \
  /opt/libcamera-y700/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so ] || \
  fail "camera package GStreamer symlink is wrong"
[ -x "$camera_stage/usr/lib/tb321fu/refresh-camera-compat-paths" ] || \
  fail "camera compatibility helper is not executable"

# Checksums are rooted at the package payload, never at a host build path.
stage="$tmp/package-stage"
plugin_rel=usr/lib/qt6/plugins/ksystemstats/ksystemstats_plugin_tb321fu_gpu.so
install -D -m 0644 /dev/stdin "$stage/$plugin_rel" <<'PLUGIN'
tb321fu-provider
PLUGIN
install -d -m 0755 "$stage/usr/share/tb321fu-ksystemstats-gpu"
(
  cd "$stage"
  sha256sum "./$plugin_rel" > \
    ./usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256
)
checksum_line=$(cat "$stage/usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256")
[[ $checksum_line == *"  ./$plugin_rel" ]] || fail "GPU checksum is not package-relative"
[[ $checksum_line != *"$tmp"* ]] || fail "GPU checksum leaked its host build path"
(
  cd "$stage"
  sha256sum -c ./usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256
) >/dev/null

# Native package graph and final gates are executable policy, not comments.
grep -Fq 'tb321fu-camera-stack' "$BUILD_SCRIPT" || fail "camera native package is missing"
grep -Fq 'camera_conflicts=(gst-plugin-libcamera y700-camera-stack)' "$BUILD_SCRIPT" || \
  fail "camera conflicts are missing"
grep -Fq 'camera_replaces=(gst-plugin-libcamera y700-camera-stack)' "$BUILD_SCRIPT" || \
  fail "camera replacements are missing"
grep -Fq 'tb321fu-ksystemstats-gpu' "$BUILD_SCRIPT" || fail "GPU native package is missing"
grep -Fq 'verify_tb321fu_native_package_integrity' "$BUILD_SCRIPT" || fail "final native package gate is missing"
grep -Fq 'pacman -Qoq' "$BUILD_SCRIPT" || fail "final ownership gate is missing"
grep -Fq 'pacman -Qkk' "$BUILD_SCRIPT" || fail "final integrity gate is missing"

# Runtime telemetry discovers the devfreq class and publishes an invalid value
# while unavailable instead of reporting a misleading zero.
grep -Fq '/sys/class/devfreq' "$GPU_SOURCE" || fail "GPU devfreq discovery is missing"
grep -Fq 'm_frequency->setValue(QVariant())' "$GPU_SOURCE" || fail "GPU unavailable state is not explicit"
if grep -Fq '/sys/devices/platform/soc@0/3d00000.gpu' "$GPU_SOURCE"; then
  fail "GPU telemetry still hardcodes one platform path"
fi

printf 'ARCH_NATIVE_PACKAGE_LIFECYCLE=PASS\n'

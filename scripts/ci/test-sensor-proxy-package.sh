#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

extract_shell_function() {
  local name=$1
  awk -v signature="$name() {" '
    $0 == signature { copying = 1 }
    copying { print }
    copying && $0 == "}" { exit }
  ' "$BUILD_SCRIPT"
}

bash -n "$BUILD_SCRIPT"
grep -Fq "TB321FU_SENSOR_PROXY_DEB='qcom-sns-iio-sensor-proxy_20260627.1_arm64.deb'" \
  "$BUILD_SCRIPT" || fail 'sensor proxy source package filename is not pinned'
grep -Fq "TB321FU_SENSOR_PROXY_DEB_SHA256='b010a9a783629c4e0fd4c404b1a34e14258fab8a674d0499d553d361cb59a843'" \
  "$BUILD_SCRIPT" || fail 'sensor proxy source package checksum is not pinned'
grep -Fq 'package=$(dpkg-deb -f "$deb" Package)' "$BUILD_SCRIPT" || \
  fail 'sensor Debian packages are not selected by package identity'
grep -Fq 'stage_tb321fu_sensor_proxy_deb "$deb"' "$BUILD_SCRIPT" || \
  fail 'Qualcomm sensor proxy is not removed from the generic import path'
grep -Fq 'install_tb321fu_sensor_proxy_package' "$BUILD_SCRIPT" || \
  fail 'native Qualcomm sensor proxy package is never installed'
grep -Fq 'local -a sensor_proxy_provides=(iio-sensor-proxy)' "$BUILD_SCRIPT" || \
  fail 'Qualcomm sensor proxy does not provide iio-sensor-proxy'
grep -Fq 'local -a sensor_proxy_conflicts=(iio-sensor-proxy)' "$BUILD_SCRIPT" || \
  fail 'Qualcomm sensor proxy does not conflict with the stock package'
grep -Fq 'local -a sensor_proxy_replaces=(iio-sensor-proxy)' "$BUILD_SCRIPT" || \
  fail 'Qualcomm sensor proxy does not replace the stock package'
grep -Fq 'tb321fu-imported-release-payload' \
  <(extract_shell_function install_tb321fu_sensor_proxy_package) || \
  fail 'Qualcomm sensor proxy does not depend on the imported SSC libraries'
grep -Fq 'stock iio-sensor-proxy package remains after Qualcomm replacement' \
  "$BUILD_SCRIPT" || fail 'stock package removal is not verified'
grep -Fq 'qcom-sns-iio-sensor-proxy' \
  <(extract_shell_function freeze_tablet_niri_custom_packages) || \
  fail 'custom sensor proxy is not frozen against rolling replacement'
grep -Fq 'cmp -s "$path" "$target" || ci_die "Arch import differs from existing file: /$relative"' \
  "$BUILD_SCRIPT" || fail 'generic differing-file collision guard was weakened'

generic_line=$(grep -n '^install_arch_import_package$' "$BUILD_SCRIPT" | tail -1 | cut -d: -f1)
sensor_line=$(grep -n '^install_tb321fu_sensor_proxy_package$' "$BUILD_SCRIPT" | tail -1 | cut -d: -f1)
[ -n "$generic_line" ] && [ -n "$sensor_line" ] && [ "$sensor_line" -gt "$generic_line" ] || \
  fail 'sensor proxy replacement does not run after the generic SSC dependency package'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stage="$tmp/stage"
install -D -m 0755 /dev/stdin "$stage/usr/bin/monitor-sensor" <<'MONITOR'
fixture monitor
MONITOR
install -D -m 0755 /dev/stdin "$stage/usr/libexec/iio-sensor-proxy" <<'PROXY'
fixture proxy
PROXY
install -D -m 0644 /dev/stdin \
  "$stage/usr/lib/systemd/system/iio-sensor-proxy.service" <<'SERVICE'
ExecStart=/usr/libexec/iio-sensor-proxy
SERVICE
install -D -m 0644 /dev/stdin \
  "$stage/usr/lib/udev/rules.d/80-iio-sensor-proxy.rules" <<'UDEV'
fixture udev rules
UDEV
install -D -m 0644 /dev/stdin \
  "$stage/usr/share/dbus-1/system-services/net.hadess.SensorProxy.service" <<'DBUS_SERVICE'
Exec=/usr/libexec/iio-sensor-proxy
DBUS_SERVICE
install -D -m 0644 /dev/stdin \
  "$stage/usr/share/dbus-1/system.d/net.hadess.SensorProxy.conf" <<'DBUS_POLICY'
fixture dbus policy
DBUS_POLICY
install -D -m 0644 /dev/stdin \
  "$stage/usr/share/polkit-1/actions/net.hadess.SensorProxy.policy" <<'POLKIT'
fixture polkit policy
POLKIT

ci_die() { fail "$*"; }
assert_aarch64_elf() { :; }
sha256sum() {
  if [ "${1:-}" = -c ]; then
    cat >/dev/null
    return 0
  fi
  command sha256sum "$@"
}
eval "$(extract_shell_function validate_tb321fu_sensor_proxy_payload)"
eval "$(extract_shell_function write_tb321fu_sensor_proxy_checksums)"

validate_tb321fu_sensor_proxy_payload "$stage"
printf 'unexpected\n' > "$stage/usr/share/unexpected"
if (validate_tb321fu_sensor_proxy_payload "$stage") >/dev/null 2>&1; then
  fail 'unexpected sensor proxy payload member was accepted'
fi
rm -f "$stage/usr/share/unexpected"
chmod 0644 "$stage/usr/bin/monitor-sensor"
if (validate_tb321fu_sensor_proxy_payload "$stage") >/dev/null 2>&1; then
  fail 'non-executable monitor-sensor was accepted'
fi
chmod 0755 "$stage/usr/bin/monitor-sensor"
ln -s monitor-sensor "$stage/usr/bin/monitor-sensor-link"
if (validate_tb321fu_sensor_proxy_payload "$stage") >/dev/null 2>&1; then
  fail 'sensor proxy symlink member was accepted'
fi

printf 'SENSOR_PROXY_PACKAGE=PASS\n'

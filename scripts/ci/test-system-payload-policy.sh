#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/system-payload-policy.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-arch-payload-policy-test.XXXXXX")
cleanup() {
  rm -rf -- "$tmp"
}
trap cleanup EXIT

root="$tmp/root"
outside="$tmp/outside"
install -d -m 0755 "$outside"
printf 'outside\n' > "$outside/world-writable"
chmod 0777 "$outside/world-writable"
install -d -m 0777 \
  "$root/etc/systemd/system" \
  "$root/usr/lib/firmware" \
  "$root/usr/lib/aarch64-linux-gnu" \
  "$root/usr/lib/tb321fu" \
  "$root/usr/libexec/tb321fu-haptics" \
  "$root/usr/local/bin" \
  "$root/opt/libcamera-y700/bin" \
  "$root/opt/libcamera-y700/libexec/libcamera"
ln -s "$outside" "$root/lib"
printf 'unit\n' > "$root/etc/systemd/system/fixture.service"
printf 'firmware\n' > "$root/usr/lib/firmware/fixture.bin"
printf 'library\n' > "$root/usr/lib/aarch64-linux-gnu/libfixture.so"
printf '#!/bin/sh\nexit 0\n' > "$root/usr/libexec/tb321fu-haptics/bind-aw86937"
printf '#!/bin/sh\nexit 0\n' > "$root/usr/lib/tb321fu/refresh-camera-compat-paths"
printf '#!/bin/sh\nexit 0\n' > "$root/usr/lib/tb321fu/disable-stock-ksystemstats-gpu"
for executable in \
  "$root/opt/libcamera-y700/bin/cam" \
  "$root/opt/libcamera-y700/bin/libcamera-bug-report" \
  "$root/opt/libcamera-y700/libexec/libcamera/soft_ipa_proxy" \
  "$root/usr/local/bin/y700-camera-env" \
  "$root/usr/local/bin/y700-camera-cam" \
  "$root/usr/local/bin/y700-camera-preview"; do
  printf '#!/bin/sh\nexit 0\n' > "$executable"
done
chmod 0777 "$root/etc/systemd/system/fixture.service" \
  "$root/usr/lib/firmware/fixture.bin" \
  "$root/usr/lib/aarch64-linux-gnu/libfixture.so"
chmod 0644 "$root/usr/libexec/tb321fu-haptics/bind-aw86937" \
  "$root/usr/lib/tb321fu/refresh-camera-compat-paths" \
  "$root/usr/lib/tb321fu/disable-stock-ksystemstats-gpu" \
  "$root/opt/libcamera-y700/bin/cam" \
  "$root/opt/libcamera-y700/bin/libcamera-bug-report" \
  "$root/opt/libcamera-y700/libexec/libcamera/soft_ipa_proxy" \
  "$root/usr/local/bin/y700-camera-env" \
  "$root/usr/local/bin/y700-camera-cam" \
  "$root/usr/local/bin/y700-camera-preview"

ci_normalize_system_payload_modes "$root"
ci_assert_normalized_system_payload_modes "$root"
ci_assert_privileged_payload_security "$root" \
  usr/libexec/tb321fu-haptics/bind-aw86937 \
  opt/libcamera-y700/bin/cam \
  opt/libcamera-y700/bin/libcamera-bug-report \
  opt/libcamera-y700/libexec/libcamera/soft_ipa_proxy \
  usr/local/bin/y700-camera-env \
  usr/local/bin/y700-camera-cam \
  usr/local/bin/y700-camera-preview
[ "$(stat -c '%a' "$root/etc/systemd/system/fixture.service")" = 644 ]
[ "$(stat -c '%a' "$root/usr/lib/firmware/fixture.bin")" = 644 ]
[ "$(stat -c '%a' "$root/usr/lib/aarch64-linux-gnu/libfixture.so")" = 644 ]
[ "$(stat -c '%a' "$root/usr/libexec/tb321fu-haptics/bind-aw86937")" = 755 ]
[ "$(stat -c '%a' "$root/usr/lib/tb321fu/refresh-camera-compat-paths")" = 755 ]
[ "$(stat -c '%a' "$root/usr/lib/tb321fu/disable-stock-ksystemstats-gpu")" = 755 ]
[ "$(stat -c '%a' "$root/opt/libcamera-y700/bin/cam")" = 755 ]
[ "$(stat -c '%a' "$outside/world-writable")" = 777 ]

chmod 0777 "$root/usr/lib/firmware/fixture.bin"
if (ci_assert_privileged_payload_security "$root" >/dev/null 2>&1); then
  echo '0777 imported payload was accepted' >&2
  exit 1
fi
chmod 0644 "$root/usr/lib/firmware/fixture.bin"
if (ci_assert_privileged_payload_security "$root" etc/systemd/system/fixture.service >/dev/null 2>&1); then
  echo 'non-executable required payload was accepted' >&2
  exit 1
fi

preserved="$tmp/preserved"
install -D -m 6755 /dev/stdin "$preserved/opt/application/bin/app" <<'PRESERVED_APP'
#!/bin/sh
exit 0
PRESERVED_APP
install -D -m 0666 /dev/stdin "$preserved/opt/application/config.json" <<'PRESERVED_CONFIG'
{}
PRESERVED_CONFIG
ci_secure_preserved_payload_modes "$preserved"
[ "$(stat -c '%a' "$preserved/opt/application/bin/app")" = 755 ]
[ "$(stat -c '%a' "$preserved/opt/application/config.json")" = 644 ]
[ -z "$(find "$preserved" -type f -perm /6000 -print -quit)" ]

grep -F 'ci_normalize_system_payload_modes "$stage"' \
  "$SCRIPT_DIR/build-arch-rootfs-image.sh" >/dev/null
grep -F 'ci_assert_privileged_payload_security "$rootfs_dir"' \
  "$SCRIPT_DIR/build-arch-rootfs-image.sh" >/dev/null

echo 'SYSTEM_PAYLOAD_POLICY=PASS'

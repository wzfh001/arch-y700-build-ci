#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"
PROFILE="$REPO_ROOT/profiles/tablet-niri/rootfs-overlay"

fail() {
  printf 'tablet-niri profile test failure: %s\n' "$*" >&2
  exit 1
}

[ -d "$PROFILE" ] || fail "profile overlay is missing"

for script in \
  "$PROFILE/usr/local/bin/tb321fu-osk-toggle" \
  "$PROFILE/usr/local/bin/tb321fu-suspend" \
  "$PROFILE/usr/local/libexec/tb321fu-grow-rootfs" \
  "$PROFILE/usr/local/libexec/tb321fu-pre-upgrade-snapshot" \
  "$PROFILE/usr/lib/systemd/system-sleep/tb321fu-suspend-log"; do
  [ -x "$script" ] || fail "profile script is not executable: $script"
  bash -n "$script"
done

python3 - "$PROFILE" <<'PY'
import pathlib
import sys
import tomllib

profile = pathlib.Path(sys.argv[1])
with (profile / "etc/skel/.config/noctalia/config.toml").open("rb") as stream:
    noctalia = tomllib.load(stream)
with (profile / "etc/greetd/config.toml").open("rb") as stream:
    greetd = tomllib.load(stream)

assert greetd["initial_session"] == {"command": "niri-session", "user": "fuhao"}
assert noctalia["lockscreen"]["enabled"] is False
assert noctalia["idle"]["behavior"]["lock"]["enabled"] is False
screen_off = noctalia["idle"]["behavior"]["screen-off"]
assert screen_off == {"timeout": 600, "action": "screen_off", "enabled": True}
assert noctalia["bar"]["default"]["start"] == [
    "launcher", "workspaces", "active_window"
]
end = noctalia["bar"]["default"]["end"]
for required in (
    "network", "bluetooth", "proxy", "brightness", "volume", "battery", "osk", "session"
):
    assert required in end
actions = noctalia["shell"]["session"]["actions"]
assert "lock" not in {item["action"] for item in actions}
assert "lock_and_suspend" not in {item["action"] for item in actions}
assert noctalia["shell"]["session"]["power"]["suspend"] == "/usr/local/bin/tb321fu-suspend"
PY

niri_config="$PROFILE/etc/skel/.config/niri/config.kdl"
grep -Fq 'output "DSI-1"' "$niri_config" || fail "DSI-1 output is not configured"
grep -Fq 'mode "1600x2560@120.000"' "$niri_config" || fail "120 Hz mode is not configured"
grep -Fq 'scale 2.3' "$niri_config" || fail "display scale is not 2.3"
grep -Fq 'transform "270"' "$niri_config" || fail "landscape transform is not 270"
grep -Fq 'map-to-output "DSI-1"' "$niri_config" || fail "touch is not mapped to DSI-1"
grep -Fq 'XF86PowerOff { power-off-monitors; }' "$niri_config" || \
  fail "power key is not a display-off action"
if grep -Eqi 'swaylock|noctalia msg session lock' "$niri_config"; then
  fail "niri config exposes a lock-screen shortcut"
fi

package_block=$(sed -n '/local tablet_niri=(/,/^  )/p' "$BUILD_SCRIPT")
for package in niri greetd foot nftables zram-generator dolphin mpv vlc nodejs rust; do
  grep -Eq "(^|[[:space:]])${package}([[:space:]]|$)" <<< "$package_block" || \
    fail "tablet package list is missing $package"
done
grep -Fq 'INSTALL_FIREFOX=1' "$BUILD_SCRIPT" || fail "tablet profile does not require Firefox"
for package in plasma-meta plasma-desktop plasma-workspace sddm plasma-keyboard konsole; do
  if grep -Eq "(^|[[:space:]])${package}([[:space:]]|$)" <<< "$package_block"; then
    fail "tablet package list contains forbidden package $package"
  fi
done

grep -Fq 'DESKTOP_PROFILE" = tablet-niri' "$BUILD_SCRIPT" || fail "tablet profile branch is missing"
grep -Fq 'DEFAULT_USER_AUTHORIZED_KEYS' "$BUILD_SCRIPT" || fail "SSH key secret path is missing"
grep -Fq 'unshare --net -- chroot' "$BUILD_SCRIPT" || fail "isolated nftables validation is missing"
grep -Fq 'tb321fu-mihomo-party' "$BUILD_SCRIPT" || fail "Mihomo native package is missing"
grep -Fq "privilege_mode=unprivileged" "$BUILD_SCRIPT" || fail "Mihomo privilege policy is missing"

if find "$PROFILE" -type f -perm /6000 -print -quit | grep -q .; then
  fail "profile overlay contains a setuid/setgid file"
fi
if find "$PROFILE" \( -type f -o -type d \) -perm /0022 -print -quit | grep -q .; then
  fail "profile overlay contains a group/world-writable member"
fi

grep -Fq 'PermitRootLogin no' "$PROFILE/etc/ssh/sshd_config.d/60-tablet-niri.conf"
grep -Fq 'PasswordAuthentication yes' "$PROFILE/etc/ssh/sshd_config.d/60-tablet-niri.conf"
grep -Fq 'HandlePowerKey=ignore' "$PROFILE/etc/systemd/logind.conf.d/60-tablet-niri.conf"
grep -Fq 'IdleAction=ignore' "$PROFILE/etc/systemd/logind.conf.d/60-tablet-niri.conf"

printf 'TABLET_NIRI_PROFILE=PASS\n'

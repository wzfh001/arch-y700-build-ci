#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"
PROFILE="$REPO_ROOT/profiles/tablet-niri/rootfs-overlay"
PARU_PKGBUILD="$REPO_ROOT/packages/tablet-niri/paru/PKGBUILD"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-tablet-niri-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'tablet-niri profile test failure: %s\n' "$*" >&2
  exit 1
}

[ -d "$PROFILE" ] || fail "profile overlay is missing"

for script in \
  "$PROFILE/usr/local/bin/tb321fu-osk-toggle" \
  "$PROFILE/usr/local/bin/tb321fu-suspend" \
  "$PROFILE/usr/local/bin/tb321fu-support-bundle" \
  "$PROFILE/usr/local/libexec/tb321fu-grow-rootfs" \
  "$PROFILE/usr/local/libexec/tb321fu-bt-nap" \
  "$PROFILE/usr/local/libexec/tb321fu-usb-rescue" \
  "$PROFILE/usr/local/libexec/tb321fu-pre-upgrade-snapshot" \
  "$PROFILE/usr/lib/systemd/system-sleep/tb321fu-suspend-log"; do
  [ -x "$script" ] || fail "profile script is not executable: $script"
  bash -n "$script"
done

redactor="$PROFILE/usr/local/libexec/tb321fu-redact-support-bundle"
[ -x "$redactor" ] || fail "profile script is not executable: $redactor"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m py_compile "$redactor"

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
assert "logout" not in {item["action"] for item in actions}
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

extract_shell_function() {
  local name=$1
  awk -v signature="$name() {" '
    $0 == signature { copying = 1 }
    copying { print }
    copying && $0 == "}" { exit }
  ' "$BUILD_SCRIPT"
}
eval "$(extract_shell_function remove_tablet_niri_desktop_payload)"
eval "$(extract_shell_function freeze_tablet_niri_custom_packages)"

payload_root="$tmp/payload"
for path in \
  usr/share/applications/org.kde.plasma.keyboard.desktop \
  etc/xdg/kwinrc \
  etc/skel/.config/kwinrc \
  etc/skel/.config/plasmakeyboardrc \
  etc/skel/.config/kwinoutputconfig.json \
  home/fuhao/.config/kwinrc \
  home/fuhao/.config/plasmakeyboardrc \
  home/fuhao/.config/kwinoutputconfig.json; do
  install -D -m 0644 /dev/null "$payload_root/$path"
done
DESKTOP_PROFILE=tablet-niri
DEFAULT_USER_NAME=fuhao
remove_tablet_niri_desktop_payload "$payload_root"
if find "$payload_root" -type f -print -quit | grep -q .; then
  fail "tablet profile retained a Plasma/KWin payload"
fi

standard_root="$tmp/standard"
install -D -m 0644 /dev/null "$standard_root/etc/xdg/kwinrc"
DESKTOP_PROFILE=standard
remove_tablet_niri_desktop_payload "$standard_root"
[ -f "$standard_root/etc/xdg/kwinrc" ] || fail "legacy Plasma profile lost its KWin payload"
DESKTOP_PROFILE=tablet-niri

freeze_root="$tmp/freeze"
install -D -m 0644 /dev/stdin "$freeze_root/etc/pacman.conf" <<'PACMAN_CONF'
[options]
PACMAN_CONF
freeze_tablet_niri_custom_packages "$freeze_root"
expected_ignore='IgnorePkg = noctalia wvkbd paru tb321fu-imported-release-payload qcom-sns-iio-sensor-proxy tb321fu-camera-stack tb321fu-wifi-firmware tb321fu-zen-browser tb321fu-cc-switch tb321fu-mihomo-party tb321fu-codex-cli'
grep -Fxq "$expected_ignore" "$freeze_root/etc/pacman.conf" || \
  fail "custom package freeze policy is incomplete"

package_block=$(sed -n '/local tablet_niri=(/,/^  )/p' "$SCRIPT_DIR/package-list.sh")
for package in niri greetd foot nftables zram-generator dnsmasq dolphin mpv vlc nodejs rust; do
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
for update in \
  'cargo update -p alpm-sys --precise 4.0.5' \
  'cargo update -p alpm --precise 4.0.4' \
  'cargo update -p pacmanconf --precise 3.1.0' \
  'cargo update -p alpm-utils --precise 4.0.3'; do
  grep -Fqx "  $update" "$PARU_PKGBUILD" || \
    fail "Paru compatibility update is missing or unpinned: $update"
done
if grep -E '^[[:space:]]*cargo update' "$PARU_PKGBUILD" | grep -Evq -- '--precise [0-9]+(\.[0-9]+)+$'; then
  fail "Paru recipe contains an unpinned cargo update"
fi
camera_install_line=$(grep -n '^apply_tb321fu_camera_stack$' "$BUILD_SCRIPT" | cut -d: -f1)
freeze_line=$(grep -n '^  freeze_tablet_niri_custom_packages ' "$BUILD_SCRIPT" | cut -d: -f1)
[[ $camera_install_line =~ ^[0-9]+$ && $freeze_line =~ ^[0-9]+$ ]] || \
  fail "custom package freeze ordering markers are missing"
((freeze_line > camera_install_line)) || \
  fail "custom packages are frozen before the final device packages are installed"

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

usb_script="$PROFILE/usr/local/libexec/tb321fu-usb-rescue"
usb_service="$PROFILE/etc/systemd/system/tb321fu-usb-rescue.service"
module_list="$PROFILE/etc/modules-load.d/60-tb321fu-rescue.conf"
usb_connection="$PROFILE/etc/NetworkManager/system-connections/tb321fu-rescue-usb.nmconnection"
bt_connection="$PROFILE/etc/NetworkManager/system-connections/tb321fu-rescue-bt.nmconnection"
bt_script="$PROFILE/usr/local/libexec/tb321fu-bt-nap"
bt_service="$PROFILE/etc/systemd/system/tb321fu-bt-nap.service"
for module in pmic_glink ucsi_glink ath12k_wifi7 bnep; do
  grep -Fxq "$module" "$module_list" || fail "rescue module list is missing $module"
done
grep -Fq 'for module in pmic_glink ucsi_glink libcomposite usb_f_acm usb_f_ncm; do' \
  "$usb_script" || fail "USB rescue module load sequence is incomplete"
grep -Fq 'ensure_function_link "$gadget/functions/acm.usb0"' "$usb_script" || \
  fail "USB ACM ConfigFS link is not reconciled"
grep -Fq 'ensure_function_link "$gadget/functions/ncm.usb0"' "$usb_script" || \
  fail "USB NCM ConfigFS link is not reconciled"
grep -Fq '10.77.0.1/24' "$usb_connection" || fail "USB rescue address is missing"
grep -Fq 'method=shared' "$usb_connection" || fail "USB rescue DHCP sharing is missing"
grep -Fq '10.78.0.1/24' "$bt_connection" || fail "Bluetooth rescue address is missing"
grep -Fq 'type=nap' "$bt_connection" || fail "Bluetooth rescue NAP is missing"
grep -Fq 'autoconnect=false' "$bt_connection" || \
  fail "Bluetooth rescue NAP is not controlled by its coordinator"
grep -Fq 'serial-getty@ttyGS0.service' "$BUILD_SCRIPT" || fail "USB serial getty is not enabled"
grep -Fxq 'Type=simple' "$usb_service" || fail "USB rescue is not a simple persistent service"
grep -Fxq 'Restart=always' "$usb_service" || fail "USB rescue does not restart persistently"
if grep -Fq 'TimeoutStartSec=infinity' "$usb_service"; then
  fail "USB rescue still blocks startup while waiting for UDC"
fi
grep -Fxq 'Type=simple' "$bt_service" || fail "Bluetooth NAP is not a simple persistent service"
grep -Fxq 'Restart=always' "$bt_service" || fail "Bluetooth NAP does not restart persistently"
grep -Fq 'connection up "$connection"' "$bt_script" || \
  fail "Bluetooth NAP coordinator does not activate its profile"
grep -Fq 'tb321fu-bt-nap.service' "$BUILD_SCRIPT" || \
  fail "Bluetooth NAP coordinator is not enabled in the image"
grep -Fq 'rescue_usb_network=cdc-ncm:10.77.0.1/24:networkmanager-shared' \
  "$BUILD_SCRIPT" || fail "USB rescue build metadata is missing"
grep -Fq 'rescue_bluetooth_network=nap:10.78.0.1/24:networkmanager-shared' \
  "$BUILD_SCRIPT" || fail "Bluetooth rescue build metadata is missing"
grep -Fq 'iifname { "usb0", "bnep0" } udp sport 68 udp dport 67 accept' \
  "$PROFILE/etc/nftables.conf" || fail "rescue DHCP firewall rule is missing"

python3 - "$usb_connection" "$bt_connection" <<'PY'
import configparser
import pathlib
import sys

for path_value in sys.argv[1:]:
    path = pathlib.Path(path_value)
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(path)
    assert parser["ipv4"]["method"] == "shared"
    assert parser["ipv6"]["method"] == "disabled"
usb = configparser.ConfigParser(interpolation=None)
usb.read(sys.argv[1])
assert usb["connection"]["interface-name"] == "usb0"
bt = configparser.ConfigParser(interpolation=None)
bt.read(sys.argv[2])
assert bt["connection"]["interface-name"] == "bnep0"
assert bt["connection"]["autoconnect"] == "false"
assert bt["bluetooth"]["type"] == "nap"
PY

printf 'TABLET_NIRI_PROFILE=PASS\n'

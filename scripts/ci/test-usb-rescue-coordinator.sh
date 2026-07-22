#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
PROFILE="$REPO_ROOT/profiles/tablet-niri/rootfs-overlay"
coordinator="$PROFILE/usr/local/libexec/tb321fu-usb-rescue"
service="$PROFILE/etc/systemd/system/tb321fu-usb-rescue.service"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-usb-coordinator-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'USB rescue coordinator test failure: %s\n' "$*" >&2
  exit 1
}

make_fake_command() {
  local path=$1
  cat > "$path" <<'EOF'
#!/usr/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TB321FU_FAKE_COMMAND_LOG"
exit 0
EOF
  chmod 0755 "$path"
}

[ -x "$coordinator" ] || fail 'coordinator is not executable'
bash -n "$coordinator"
grep -Fxq 'Type=simple' "$service" || fail 'USB service is not Type=simple'
grep -Fxq 'Restart=always' "$service" || fail 'USB service is not persistent'
if grep -Fq 'TimeoutStartSec=infinity' "$service"; then
  fail 'USB service still blocks startup indefinitely'
fi

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
for command in modprobe nmcli ip systemctl; do
  make_fake_command "$fake_bin/$command"
done
command_log="$tmp/commands.log"
: > "$command_log"

sys_root="$tmp/sys"
config_root="$tmp/config"
dev_root="$tmp/dev"
mkdir -p \
  "$sys_root/class/typec/port0-partner" \
  "$sys_root/class/typec/port0" \
  "$sys_root/class/udc/a600000.usb" \
  "$sys_root/class/net/usb0" \
  "$dev_root"
printf 'host\n' > "$sys_root/class/typec/port0/data_role"
printf 'source [sink]\n' > "$sys_root/class/typec/port0/power_role"
: > "$dev_root/ttyGS0"

output=$(TB321FU_SYS_ROOT="$sys_root" \
  TB321FU_CONFIG_ROOT="$config_root" \
  TB321FU_DEV_ROOT="$dev_root" \
  TB321FU_MODPROBE="$fake_bin/modprobe" \
  TB321FU_NMCLI="$fake_bin/nmcli" \
  TB321FU_IP="$fake_bin/ip" \
  TB321FU_SYSTEMCTL="$fake_bin/systemctl" \
  TB321FU_FAKE_COMMAND_LOG="$command_log" \
  TB321FU_ONCE=1 \
  "$coordinator")

[ "$(cat "$sys_root/class/typec/port0/data_role")" = device ] || \
  fail 'coordinator did not request the device data role'
gadget="$config_root/usb_gadget/tb321fu-rescue"
[ -L "$gadget/configs/c.1/acm.usb0" ] || fail 'ACM function link is missing'
[ -L "$gadget/configs/c.1/ncm.usb0" ] || fail 'NCM function link is missing'
[ "$(readlink "$gadget/configs/c.1/acm.usb0")" = "$gadget/functions/acm.usb0" ] || \
  fail 'ACM function link target is wrong'
grep -Fq 'bound gadget to a600000.usb' <<< "$output" || \
  fail 'coordinator did not bind the discovered UDC'
grep -Fq 'gadget unbound during service stop' <<< "$output" || \
  fail 'coordinator did not cleanly unbind'
grep -Fq 'nmcli connection up tb321fu-rescue-usb ifname usb0' "$command_log" || \
  fail 'coordinator did not activate the NCM profile'
grep -Fq 'systemctl start serial-getty@ttyGS0.service' "$command_log" || \
  fail 'coordinator did not activate the ACM getty'
grep -Fq 'power_role=source [sink]' <<< "$output" || \
  fail 'coordinator did not report the Type-C power role'

no_udc_sys="$tmp/no-udc-sys"
no_udc_config="$tmp/no-udc-config"
mkdir -p \
  "$no_udc_sys/class/typec/port0-partner" \
  "$no_udc_sys/class/typec/port0" \
  "$no_udc_sys/class/udc" \
  "$no_udc_sys/class/net"
printf 'host\n' > "$no_udc_sys/class/typec/port0/data_role"
TB321FU_SYS_ROOT="$no_udc_sys" \
  TB321FU_CONFIG_ROOT="$no_udc_config" \
  TB321FU_DEV_ROOT="$tmp/no-dev" \
  TB321FU_MODPROBE="$fake_bin/modprobe" \
  TB321FU_NMCLI="$fake_bin/nmcli" \
  TB321FU_IP="$fake_bin/ip" \
  TB321FU_SYSTEMCTL="$fake_bin/systemctl" \
  TB321FU_FAKE_COMMAND_LOG="$command_log" \
  TB321FU_ONCE=1 \
  timeout 5s "$coordinator" >/dev/null || fail 'missing UDC caused coordinator failure or blocking'
[ "$(cat "$no_udc_sys/class/typec/port0/data_role")" = device ] || \
  fail 'missing UDC path did not retain device-role request'

hotplug_sys="$tmp/hotplug-sys"
hotplug_config="$tmp/hotplug-config"
hotplug_dev="$tmp/hotplug-dev"
mkdir -p \
  "$hotplug_sys/class/typec/port0-partner" \
  "$hotplug_sys/class/typec/port0" \
  "$hotplug_sys/class/udc" \
  "$hotplug_sys/class/net" \
  "$hotplug_dev"
printf 'host\n' > "$hotplug_sys/class/typec/port0/data_role"
printf '[source] sink\n' > "$hotplug_sys/class/typec/port0/power_role"
hotplug_sleep="$fake_bin/hotplug-sleep"
apply_count="$tmp/hotplug-count"
printf '0\n' > "$apply_count"
cat > "$hotplug_sleep" <<'EOF'
#!/usr/bin/bash
count=$(cat "$TB321FU_HOTPLUG_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$TB321FU_HOTPLUG_COUNT"
case $count in
  1)
    mkdir -p "$TB321FU_SYS_ROOT/class/udc/a600000.usb" \
      "$TB321FU_SYS_ROOT/class/net/usb0"
    : > "$TB321FU_DEV_ROOT/ttyGS0"
    ;;
  2)
    rm -rf -- "$TB321FU_SYS_ROOT/class/udc/a600000.usb" \
      "$TB321FU_SYS_ROOT/class/net/usb0"
    rm -f -- "$TB321FU_DEV_ROOT/ttyGS0"
    ;;
  3)
    mkdir -p "$TB321FU_SYS_ROOT/class/udc/a600000.usb" \
      "$TB321FU_SYS_ROOT/class/net/usb0"
    : > "$TB321FU_DEV_ROOT/ttyGS0"
    ;;
esac
EOF
chmod 0755 "$hotplug_sleep"
hotplug_output=$(TB321FU_SYS_ROOT="$hotplug_sys" \
  TB321FU_CONFIG_ROOT="$hotplug_config" \
  TB321FU_DEV_ROOT="$hotplug_dev" \
  TB321FU_MODPROBE="$fake_bin/modprobe" \
  TB321FU_NMCLI="$fake_bin/nmcli" \
  TB321FU_IP="$fake_bin/ip" \
  TB321FU_SYSTEMCTL="$fake_bin/systemctl" \
  TB321FU_SLEEP="$hotplug_sleep" \
  TB321FU_HOTPLUG_COUNT="$apply_count" \
  TB321FU_FAKE_COMMAND_LOG="$command_log" \
  TB321FU_MAX_ITERATIONS=4 \
  "$coordinator")
[ "$(grep -Fc 'bound gadget to a600000.usb' <<< "$hotplug_output")" -eq 2 ] || \
  fail 'coordinator did not rebind the gadget after UDC hotplug'
grep -Fq 'unbound missing UDC a600000.usb' <<< "$hotplug_output" || \
  fail 'coordinator did not notice UDC removal'
[ "$(grep -Fc 'USB NCM ready at 10.77.0.1' <<< "$hotplug_output")" -eq 2 ] || \
  fail 'coordinator did not restore NCM after hotplug'
[ "$(grep -Fc 'USB ACM console ready at ttyGS0' <<< "$hotplug_output")" -eq 2 ] || \
  fail 'coordinator did not restore ACM after hotplug'

fail_bin="$tmp/fail-bin"
mkdir -p "$fail_bin"
cat > "$fail_bin/nmcli" <<'EOF'
#!/usr/bin/bash
printf 'nmcli-fail %s\n' "$*" >> "$TB321FU_FAKE_COMMAND_LOG"
exit 10
EOF
cat > "$fail_bin/systemctl" <<'EOF'
#!/usr/bin/bash
printf 'systemctl-fail %s\n' "$*" >> "$TB321FU_FAKE_COMMAND_LOG"
exit 1
EOF
chmod 0755 "$fail_bin"/*
failure_sys="$tmp/failure-sys"
failure_config="$tmp/failure-config"
failure_dev="$tmp/failure-dev"
mkdir -p \
  "$failure_sys/class/typec/port0-partner" \
  "$failure_sys/class/typec/port0" \
  "$failure_sys/class/udc/a600000.usb" \
  "$failure_sys/class/net/usb0" \
  "$failure_dev"
printf 'device\n' > "$failure_sys/class/typec/port0/data_role"
: > "$failure_dev/ttyGS0"
failure_output=$(TB321FU_SYS_ROOT="$failure_sys" \
  TB321FU_CONFIG_ROOT="$failure_config" \
  TB321FU_DEV_ROOT="$failure_dev" \
  TB321FU_MODPROBE="$fake_bin/modprobe" \
  TB321FU_NMCLI="$fail_bin/nmcli" \
  TB321FU_IP="$fake_bin/ip" \
  TB321FU_SYSTEMCTL="$fail_bin/systemctl" \
  TB321FU_FAKE_COMMAND_LOG="$command_log" \
  TB321FU_ONCE=1 \
  timeout 5s "$coordinator")
grep -Fq 'NetworkManager failed; USB NCM has static fallback 10.77.0.1' \
  <<< "$failure_output" || fail 'NetworkManager failure did not use static fallback'
grep -Fq 'ttyGS0 exists but serial getty failed' <<< "$failure_output" || \
  fail 'serial getty failure was not recorded without blocking'

printf 'USB_RESCUE_COORDINATOR=PASS\n'

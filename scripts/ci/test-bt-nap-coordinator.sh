#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
PROFILE="$REPO_ROOT/profiles/tablet-niri/rootfs-overlay"
coordinator="$PROFILE/usr/local/libexec/tb321fu-bt-nap"
service="$PROFILE/etc/systemd/system/tb321fu-bt-nap.service"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-bt-nap-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'Bluetooth NAP coordinator test failure: %s\n' "$*" >&2
  exit 1
}

[ -x "$coordinator" ] || fail 'coordinator is not executable'
bash -n "$coordinator"
grep -Fxq 'Type=simple' "$service" || fail 'service is not Type=simple'
grep -Fxq 'Restart=always' "$service" || fail 'service is not persistent'
if grep -Fq 'TimeoutStartSec=infinity' "$service"; then
  fail 'service blocks startup indefinitely'
fi

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
command_log="$tmp/commands.log"
active_state="$tmp/active"
attempt_state="$tmp/attempts"
: > "$command_log"
: > "$active_state"
printf '0\n' > "$attempt_state"

cat > "$fake_bin/modprobe" <<'EOF'
#!/usr/bin/bash
printf 'modprobe %s\n' "$*" >> "$TB321FU_FAKE_COMMAND_LOG"
exit 0
EOF
cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/bash
printf 'systemctl %s\n' "$*" >> "$TB321FU_FAKE_COMMAND_LOG"
if [ "$1" = is-active ] && [ "$2" = --quiet ]; then
  exit 0
fi
exit 1
EOF
cat > "$fake_bin/bluetoothctl" <<'EOF'
#!/usr/bin/bash
printf 'bluetoothctl %s\n' "$*" >> "$TB321FU_FAKE_COMMAND_LOG"
case ${1:-} in
  show)
    printf 'Controller 00:11:22:33:44:55\n\tPowered: yes\n\tUUID: Network Access Point (00001116-0000-1000-8000-00805f9b34fb)\n'
    ;;
  power) exit 0 ;;
esac
EOF
cat > "$fake_bin/nmcli" <<'EOF'
#!/usr/bin/bash
printf 'nmcli %s\n' "$*" >> "$TB321FU_FAKE_COMMAND_LOG"
if [ "$1" = -t ]; then
  [ -s "$TB321FU_FAKE_ACTIVE_STATE" ] && printf 'tb321fu-rescue-bt\n'
  exit 0
fi
if [ "$1" = connection ] && [ "$2" = show ]; then
  exit 0
fi
if [ "$1" = connection ] && [ "$2" = up ]; then
  count=$(cat "$TB321FU_FAKE_ATTEMPT_STATE")
  count=$((count + 1))
  printf '%s\n' "$count" > "$TB321FU_FAKE_ATTEMPT_STATE"
  if [ "$count" -eq 1 ]; then
    exit 10
  fi
  printf 'active\n' > "$TB321FU_FAKE_ACTIVE_STATE"
  exit 0
fi
if [ "$1" = connection ] && [ "$2" = down ]; then
  : > "$TB321FU_FAKE_ACTIVE_STATE"
  exit 0
fi
exit 1
EOF
cat > "$fake_bin/sleep" <<'EOF'
#!/usr/bin/bash
exit 0
EOF
chmod 0755 "$fake_bin"/*

sys_root="$tmp/sys"
mkdir -p "$sys_root/class/bluetooth/hci0" "$sys_root/class/net"
output=$(TB321FU_SYS_ROOT="$sys_root" \
  TB321FU_MODPROBE="$fake_bin/modprobe" \
  TB321FU_SYSTEMCTL="$fake_bin/systemctl" \
  TB321FU_BLUETOOTHCTL="$fake_bin/bluetoothctl" \
  TB321FU_NMCLI="$fake_bin/nmcli" \
  TB321FU_SLEEP="$fake_bin/sleep" \
  TB321FU_FAKE_COMMAND_LOG="$command_log" \
  TB321FU_FAKE_ACTIVE_STATE="$active_state" \
  TB321FU_FAKE_ATTEMPT_STATE="$attempt_state" \
  TB321FU_MAX_ITERATIONS=3 \
  "$coordinator")
grep -Fq 'Bluetooth NAP activation failed (attempt 1); will retry' <<< "$output" || \
  fail 'coordinator did not report the failed activation'
grep -Fq 'activated Bluetooth NAP profile tb321fu-rescue-bt' <<< "$output" || \
  fail 'coordinator did not retry and activate the NAP profile'
grep -Fq 'nap_uuid=yes' <<< "$output" || fail 'coordinator did not report the NAP UUID'
[ "$(cat "$attempt_state")" -eq 2 ] || fail 'coordinator repeated activation without new state'
grep -Fq 'nmcli connection down tb321fu-rescue-bt' "$command_log" || \
  fail 'coordinator did not clean up the NAP profile'

missing_sys="$tmp/missing-sys"
mkdir -p "$missing_sys/class/bluetooth" "$missing_sys/class/net"
TB321FU_SYS_ROOT="$missing_sys" \
  TB321FU_MODPROBE="$fake_bin/modprobe" \
  TB321FU_SYSTEMCTL="$fake_bin/systemctl" \
  TB321FU_BLUETOOTHCTL="$fake_bin/bluetoothctl" \
  TB321FU_NMCLI="$fake_bin/nmcli" \
  TB321FU_SLEEP="$fake_bin/sleep" \
  TB321FU_FAKE_COMMAND_LOG="$command_log" \
  TB321FU_FAKE_ACTIVE_STATE="$active_state" \
  TB321FU_FAKE_ATTEMPT_STATE="$attempt_state" \
  TB321FU_ONCE=1 \
  timeout 5s "$coordinator" >/dev/null || \
  fail 'missing adapter caused coordinator failure or blocking'

cat > "$fake_bin/hang" <<'EOF'
#!/usr/bin/bash
sleep 10
EOF
chmod 0755 "$fake_bin/hang"
TB321FU_SYS_ROOT="$sys_root" \
  TB321FU_MODPROBE="$fake_bin/modprobe" \
  TB321FU_SYSTEMCTL="$fake_bin/systemctl" \
  TB321FU_BLUETOOTHCTL="$fake_bin/hang" \
  TB321FU_NMCLI="$fake_bin/nmcli" \
  TB321FU_SLEEP="$fake_bin/sleep" \
  TB321FU_COMMAND_TIMEOUT=0.1 \
  TB321FU_FAKE_COMMAND_LOG="$command_log" \
  TB321FU_FAKE_ACTIVE_STATE="$active_state" \
  TB321FU_FAKE_ATTEMPT_STATE="$attempt_state" \
  TB321FU_ONCE=1 \
  timeout 3s "$coordinator" >/dev/null || \
  fail 'hung bluetoothctl command blocked the coordinator'

printf 'BT_NAP_COORDINATOR=PASS\n'

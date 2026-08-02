#!/usr/bin/env bash
# Offline checks of a tablet-kde rootfs raw image for KDE/user/firmware facts.
# Usage: audit-tablet-kde-rootfs.sh <rootfs-raw>
# Uses debugfs (no root, no mount) to read the ext4 image read-only and verify:
#   fuhao account, skel/user KDE configs, kwinoutputconfig Rotated270,
#   environment.d/mimeapps presence, firmware packages, service enablement.
#
# debugfs caveats handled here:
#   - command exit status is 0 even when a path lookup fails, so existence is
#     tested by scanning stdout for "Inode:" instead of relying on rc.
#   - `cat` on binary files stops at the first NUL byte, so binary facts use
#     `dump` + sha256sum (via a host temp file) instead of `cat`.
#   - there is no `readlink` subcommand; symlink targets are read from
#     `stat`'s "Fast link dest" line.
set -euo pipefail

raw="$1"
[ -f "$raw" ] || { echo "missing raw: $raw" >&2; exit 2; }
command -v debugfs >/dev/null || { echo "debugfs not found" >&2; exit 2; }

# exists <path> -> 0 if the path resolves in the image (regular/dir/symlink)
exists() {
  debugfs -R "stat $1" "$raw" 2>/dev/null | grep -q 'Inode:'
}

# type_of <path> -> "regular"/"directory"/"symlink"/"" (empty if missing)
type_of() {
  debugfs -R "stat $1" "$raw" 2>/dev/null | sed -n 's/.*Type: \([a-z]*\).*/\1/p' | head -1
}

# cat_ok <path> -> prints file content for text files; fails if missing or not regular
cat_ok() {
  debugfs -R "cat $1" "$raw" 2>/dev/null | grep -q '^' || return 1
  debugfs -R "cat $1" "$raw" 2>/dev/null
}

# dump_sha <path> -> sha256 of the exact file bytes (binary safe)
dump_sha() {
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/audit-tablet-kde.XXXXXX")
  debugfs -R "dump $1 $tmp" "$raw" >/dev/null 2>&1
  sha256sum "$tmp" | cut -d' ' -f1
  rm -f "$tmp"
}

echo "== fuhao account =="
cat_ok /etc/passwd | grep -E '^fuhao:' || echo "MISSING fuhao in passwd"
shadow=$(cat_ok /etc/shadow || true)
printf '%s\n' "$shadow" | grep -E '^fuhao:' | cut -d: -f1-2 | sed 's/:[^:]*$/:***/' || echo "no fuhao shadow line"
printf '%s\n' "$shadow" | grep -E '^root:' | cut -d: -f1-2 | sed 's/:[^:]*$/:***/' || true

echo "== KDE user config =="
for f in \
  /home/fuhao/.config/kwinoutputconfig.json \
  /home/fuhao/.config/kwinrc \
  /home/fuhao/.config/plasmakeyboardrc \
  /home/fuhao/.config/environment.d/90-tablet-kde.conf \
  /home/fuhao/.config/mimeapps.list \
  /home/fuhao/.config/fcitx5/profile; do
  if exists "$f"; then echo "OK   $f"; else echo "MISS $f"; fi
done

echo "== kwinoutputconfig =="
if exists /home/fuhao/.config/kwinoutputconfig.json; then
  koc=$(cat_ok /home/fuhao/.config/kwinoutputconfig.json || true)
  printf '%s\n' "$koc" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    out=d[0]["data"][0]
    print("connectorName=", out.get("connectorName"))
    print("transform=", out.get("transform"))
    print("mode=", out.get("mode"))
    print("scale=", out.get("scale"))
except Exception as e:
    print("PARSE FAIL:", e)' || true
else
  echo "MISSING kwinoutputconfig"
fi

echo "== kwinrc =="
kwinrc=$(cat_ok /home/fuhao/.config/kwinrc 2>/dev/null || true)
printf '%s\n' "$kwinrc" | grep -A2 '\[Wayland\]' || true

echo "== mimeapps references =="
ma=$(cat_ok /home/fuhao/.config/mimeapps.list 2>/dev/null || true)
printf '%s\n' "$ma" | grep -oE '[A-Za-z0-9._-]+\.desktop' | sort -u || true

echo "== firmware =="
debugfs -R 'ls -l /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0' "$raw" 2>/dev/null | awk 'NR>2 && $9 !~ /^\./ {print $9}' || echo "MISSING wifi firmware dir"
board=$(dump_sha /usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin 2>/dev/null || echo MISSING)
echo "board-2.bin sha256: $board"
qca_count=$(debugfs -R 'ls -l /usr/lib/firmware/tb321fu/qca' "$raw" 2>/dev/null | awk 'NR>2 && $9!="." && $9!=".." {n++} END{print n+0}')
echo "qca entries: $qca_count"

echo "== native package dirs =="
for d in tb321fu-wifi-firmware tb321fu-bluetooth-firmware tb321fu-alsa-ucm tb321fu-libssc tb321fu-sensor-proxy; do
  if exists "/usr/share/$d"; then echo "OK  $d"; else echo "MISS $d"; fi
done

echo "== key binaries =="
for p in /usr/bin/ssccli /usr/libexec/iio-sensor-proxy /usr/lib/systemd/system/iio-sensor-proxy.service; do
  if exists "$p"; then echo "OK  $p"; else echo "MISS $p"; fi
done

echo "== services (multi-user.wants) =="
for s in sddm.service NetworkManager.service sshd.service bluetooth.service nftables.service tb321fu-grow-rootfs.service tb321fu-usb-rescue.service tb321fu-bt-nap.service systemd-timesyncd.service serial-getty@ttyGS0.service; do
  if exists "/etc/systemd/system/multi-user.target.wants/$s"; then
    echo "OK  $s"
  else
    echo "MISS $s"
  fi
done
dt=$(debugfs -R 'stat /etc/systemd/system/default.target' "$raw" 2>/dev/null | sed -n 's/.*Fast link dest: "\(.*\)"/\1/p' || true)
echo "default target: ${dt:-MISSING}"

echo "== AUTH COMPLETE =="

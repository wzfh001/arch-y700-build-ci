#!/usr/bin/env bash
# Offline checks of a tablet-kde rootfs raw image for KDE/user/firmware facts.
# Usage: audit-tablet-kde-rootfs.sh <rootfs-raw>
# Mounts the ext4 image read-only (loop) and verifies:
#   fuhao user, skel/user KDE configs, kwinoutputconfig Rotated270,
#   environment.d/mimeapps presence, firmware packages, service enablement.
# Requires root. Emits evidence to stdout.
set -euo pipefail

raw="$1"
[ -f "$raw" ] || { echo "missing raw: $raw" >&2; exit 2; }
[ "$(id -u)" = 0 ] || { echo "must run as root" >&2; exit 2; }

mnt=$(mktemp -d)
cleanup() { umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; }
trap cleanup EXIT

mount -o ro,loop "$raw" "$mnt"

echo "== fuhao account =="
grep -E '^fuhao:' "$mnt/etc/passwd" || echo "MISSING fuhao in passwd"
grep -E '^fuhao:' "$mnt/etc/shadow" 2>/dev/null | cut -d: -f1-2 | sed 's/:[^:]*$/:***/'
grep -E '^root:' "$mnt/etc/shadow" 2>/dev/null | cut -d: -f1-2 | sed 's/:[^:]*$/:***/'
grep -E '^fuhao' "$mnt/etc/sudoers.d/"* 2>/dev/null | head

echo "== KDE user config =="
for f in \
  .config/kwinoutputconfig.json \
  .config/kwinrc \
  .config/plasmakeyboardrc \
  .config/environment.d/90-tablet-kde.conf \
  .config/mimeapps.list \
  .config/fcitx5/profile; do
  p="$mnt/home/fuhao/$f"
  [ -f "$p" ] && echo "OK   $f" || echo "MISS $f"
done

echo "== kwinoutputconfig =="
python3 - "$mnt/home/fuhao/.config/kwinoutputconfig.json" <<'PY' || true
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    out=d[0]["data"][0]
    print("connectorName=", out.get("connectorName"))
    print("transform=", out.get("transform"))
    print("mode=", out.get("mode"))
    print("scale=", out.get("scale"))
except Exception as e:
    print("PARSE FAIL:", e)
PY

echo "== kwinrc =="
grep -A2 '\[Wayland\]' "$mnt/home/fuhao/.config/kwinrc" || true

echo "== mimeapps references (should be firefox/dolphin/okular/elisa only) =="
grep -oE '[A-Za-z0-9._-]+\.desktop' "$mnt/home/fuhao/.config/mimeapps.list" | sort -u || true

echo "== firmware packages =="
ls "$mnt/usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/" 2>/dev/null || echo "MISSING wifi firmware dir"
sha256sum "$mnt/usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin" 2>/dev/null | cut -d' ' -f1
ls "$mnt/usr/lib/firmware/tb321fu/qca/" 2>/dev/null | wc -l

echo "== native package dirs =="
for d in tb321fu-wifi-firmware tb321fu-bluetooth-firmware tb321fu-alsa-ucm tb321fu-libssc tb321fu-sensor-proxy; do
  [ -d "$mnt/usr/share/$d" ] && echo "OK  $d" || echo "MISS $d"
done
ls "$mnt/usr/bin/ssccli" "$mnt/usr/libexec/iio-sensor-proxy" 2>/dev/null || true

echo "== services =="
for s in sddm.service NetworkManager.service sshd.service bluetooth.service nftables.service tb321fu-grow-rootfs.service tb321fu-usb-rescue.service tb321fu-bt-nap.service serial-getty@ttyGS0.service systemd-timesyncd.service; do
  if [ -e "$mnt/etc/systemd/system/multi-user.target.wants/$s" ] || [ -e "$mnt/etc/systemd/system/$s" ]; then
    echo "OK  $s"
  else
    echo "MISS $s"
  fi
done
echo "default target: $(readlink "$mnt/etc/systemd/system/default.target" 2>/dev/null || echo MISSING)"

echo "== AUTH COMPLETE =="

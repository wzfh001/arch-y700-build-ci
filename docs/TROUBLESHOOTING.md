# Troubleshooting

Status words: `VERIFIED` / `PARTIAL` / `BROKEN` / `UNTESTED` / `BLOCKED`.

## Wi-Fi (WCN7850) — high-confidence root cause

- Device uses `17cb:1107 -> ath12k_wifi7_pci`, interface `wlp1s0`.
- The only hardware-verified working firmware is the Kubuntu WCN7850
  `hw2.0/board-2.bin` (202148 bytes).
- Fix (source-level, P2): pinned device archive + native
  `tb321fu-wifi-firmware` package + independent firmware path
  `/usr/lib/firmware/tb321fu` + bootargs `firmware_class.path` + package
  ownership collision stop-line.
- `SRC-20260722-004` (FAIL, forbidden to repeat): old raw's 33090-byte
  `board-2.bin.zst` unpacked to 1,897,968 bytes / SHA `7ce00dc0…` — not the
  target; only a hash-matched main ZIP may be used.
- **Hardware status: UNTESTED** — never flashed post-fix.

## USB (two separate issues)

1. ConfigFS link bug — fixed in source (`d480039`); not flashed.
2. Hardware: `/sys/class/udc` was empty and `port0` stayed host on the old run.
   A non-blocking coordinator now handles role/UDC/ConfigFS/ACM/NCM with
   hotplug, retry, timeout and cleanup. **Hardware status: UNTESTED.**

## Bluetooth NAP — removed (2026-08-02, user decision)

- Wi-Fi is the primary network; BT NAP coordinator/service/NM connection were
  dropped from the overlay and kernel BNEP disabled (`50-tablet-bt-nap-off`).
  Bluetooth itself stays enabled (keyboard/audio via HIDP/RFCOMM).

## General verification sequence (post-flash)

1. Boot chain and local TTY
2. Automatic support bundle
3. USB ACM → USB NCM (at least one rescue channel PASS)
4. Wi-Fi: PCI enum, module, firmware request, `wlp1s0`, scan, connect, DHCP,
   reconnect, screen-off recovery
5. `/dev/dri/renderD128`, `vulkaninfo`
6. PipeWire audio devices, Fcitx5, Plasma Keyboard, sensor rotation, haptics,
   SSH

## How to report a hardware bug

Open an issue with:

- run ID / commit / artifact SHA
- `systemctl --failed` output
- kernel log (`journalctl -b`) sections for the failing subsystem
- the automatic support bundle
- whether it reproduces on the Kubuntu baseline (hardware vs software)

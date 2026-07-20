# TB321FU Arch Linux ARM status

Last reviewed: 2026-07-21

This file records current implementation and runtime truth. A source file,
installed package, enabled service, or green CI job does not prove hardware
functionality.

## Identity

- Device: Lenovo Y700 2025, TB321FU, SM8650, 16 GiB + 512 GiB
- Current branch: `codex/tablet-rescue-20260720`
- Last flashed build: workflow run `29709555909`, commit `4edf3a4`
- First post-handoff source fix: commit `d480039`
- Release state: artifact-only; no approved Arch hardware release

## Evidence states

- `VERIFIED`: reproducible device or complete offline-audit evidence exists.
- `PARTIAL`: only part of the path has evidence.
- `BROKEN`: evidence shows the feature is not working.
- `UNTESTED`: no sufficient evidence exists.
- `OUT-OF-SCOPE`: deliberately excluded from the current release gate.

## Current device state

| Area | State | Current evidence |
|---|---|---|
| Boot to Arch | PARTIAL | User reported the rescue image booted; full automated boot evidence is missing. |
| Wi-Fi | BROKEN | No usable interface; final raw contains generic WCN7850 firmware instead of the Kubuntu-proven device file. |
| Bluetooth base | PARTIAL | Basic Bluetooth was observed by the user; detailed logs are missing. |
| Bluetooth NAP | UNTESTED | Profile exists, but activation, SDP UUID, `bnep0`, DHCP, and SSH are unproved. |
| USB ACM | BROKEN | Host did not enumerate ACM; device `/sys/class/udc` was empty. |
| USB NCM | BROKEN | Host did not enumerate NCM; device `/sys/class/udc` was empty. |
| Display/touch/120 Hz | UNTESTED | Configuration exists but the flashed Arch runtime has no complete acceptance record. |
| Audio/microphone/haptics | UNTESTED | Payload exists; no complete Arch runtime acceptance record. |
| Brightness/battery/charging | UNTESTED | No complete Arch runtime acceptance record. |
| Camera | OUT-OF-SCOPE | Not a first release gate. |
| Suspend resume | OUT-OF-SCOPE | Automatic suspend is forbidden; diagnostic testing requires rescue/logging first. |

## Confirmed engineering findings

1. Fastboot must never write the 20 GiB `userdata` image. It returned `OKAY`
   while omitting tail data. The verified historical recovery used the matching
   Windows Firehose programmer and a ten-point `10/10` readback.
2. The build discarded the device WCN7850 file when the same path was owned by
   `linux-firmware-atheros`, without comparing content.
3. USB gadget work has two independent layers: ConfigFS function linking and
   the missing UDC/device-role transition. Commit `d480039` addresses only the
   first layer.
4. The current USB unit is `Type=oneshot` with an infinite start timeout. It
   can block startup ordering and does not coordinate hotplug or role changes.
5. The Bluetooth NAP profile has no dedicated activation/retry coordinator.
6. The current image lacks an automatic, redacted support bundle, so runtime
   failures cannot yet be investigated reliably.

## Immediate release blockers

- Persistent non-blocking USB role/UDC/gadget coordinator
- Bluetooth NAP activation coordinator
- Redacted offline support bundle
- Device-specific WCN7850 package, exact hashes, firmware path, and bootarg
- Deterministic CI gates for the final raw filesystem
- Complete rootfs/GRUB/boot/DTB offline audit
- Device-specific GPT verification and Firehose bundle
- At least two independent rescue paths verified on hardware

## Safety boundary

Do not flash a new device image from this repository until all relevant gates
in `ROADMAP.md` and the external project plan are complete. Never reuse a flash
bundle, GPT range, or checksum identity from another run.

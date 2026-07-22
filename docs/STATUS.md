# TB321FU Arch Linux ARM status

Last reviewed: 2026-07-22

This file records current implementation and runtime truth. A source file,
installed package, enabled service, or green CI job does not prove hardware
functionality.

## Identity

- Device: Lenovo Y700 2025, TB321FU, SM8650, 16 GiB + 512 GiB
- Current branch: `codex/tablet-rescue-20260720`
- Current device OS: recovered Kubuntu 26.04 ARM64 baseline
- Last attempted Arch build: workflow run `29709555909`, commit `4edf3a4`
- First post-handoff source fix: commit `d480039`
- Evidence-governance baseline: commit `34de491`
- Offline support-bundle implementation: commit `3a095ed`
- P0 recovery/governance completion: commit `c45ad2a`
- Extended support-bundle redaction: commit `dc36f47`
- Persistent USB coordinator: commits `5f50ade` and `649d032`
- Bluetooth NAP coordinator: commit `406e0c1`
- Rescue CI integration: commit `eaf0650`
- P2 WCN7850 exact-hash/native-package source gate: `SRC-20260722-005`
- P3 two-stage pacman lock mechanism: `SRC-20260722-007`; lock artifact unset
- Release state: artifact-only; no approved Arch hardware release

## Evidence states

- `VERIFIED`: reproducible device or complete offline-audit evidence exists.
- `PARTIAL`: only part of the path has evidence.
- `BROKEN`: evidence shows the feature is not working.
- `UNTESTED`: no sufficient evidence exists.
- `OUT-OF-SCOPE`: deliberately excluded from the current release gate.

## Current device state

The physical tablet was restored to Kubuntu on 2026-07-21. The Arch results
below are retained as historical evidence for the last attempted Arch rescue
image; they do not describe the currently running filesystem.

| Area | State | Current evidence |
|---|---|---|
| Current Kubuntu recovery | VERIFIED | Kubuntu 26.04 ARM64, Wi-Fi, SSH, SDDM, and NetworkManager were observed after recovery. |
| Last Arch boot | PARTIAL | User reported the rescue image booted; full automated boot evidence is missing. |
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
4. The last flashed USB unit was `Type=oneshot` with an infinite start timeout.
   Commits `5f50ade`, `649d032`, and `eaf0650` replace it with a persistent,
   command-bounded coordinator and source tests, but no TB321FU runtime
   acceptance exists yet.
5. The last flashed Bluetooth NAP profile had no activation/retry coordinator;
   commits `406e0c1` and `eaf0650` add one, still hardware `UNTESTED`.
6. Commit `3a095ed` adds an automatic offline support bundle, redaction, file
   checksums, and an end-to-end archive test. It is not present in the flashed
   image and remains `UNTESTED` on TB321FU hardware.
7. `SRC-20260722-005` pins the verified device archive and all six WCN7850
   hashes, builds `tb321fu-wifi-firmware` on an independent search path, and
   rejects differing Arch-owned imports. A new final raw and hardware test are
   still required before Wi-Fi can leave `BROKEN` for the historical image or
   become `VERIFIED` for a new candidate.

## Immediate release blockers

- Install and verify the redacted support bundle on TB321FU hardware
- Verify USB role/UDC/ACM/NCM and Bluetooth NAP on TB321FU hardware
- Final-raw proof for the device-specific WCN7850 package, hashes, ownership,
  firmware path, and bootarg
- Run and pin the immutable pacman lock seed, then prove the locked offline
  transaction in a complete final raw build
- Complete rootfs/GRUB/boot/DTB offline audit
- Device-specific GPT verification and Firehose bundle
- At least two independent rescue paths verified on hardware

The fixed device archive is now locally verified and gated by
`SRC-20260722-005`. Experiment `SRC-20260722-004` still permanently forbids the
old raw's 33090-byte compressed member, which expands to a different
1,897,968-byte file, as a substitute.

## Safety boundary

Do not flash a new device image from this repository until all relevant gates
in `ROADMAP.md` and the external project plan are complete. Never reuse a flash
bundle, GPT range, or checksum identity from another run.

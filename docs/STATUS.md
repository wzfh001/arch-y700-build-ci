# TB321FU Arch Linux ARM status

Last reviewed: 2026-07-22

This file records current implementation and runtime truth. A source file,
installed package, enabled service, or green CI job does not prove hardware
functionality.

## Identity

- Device: Lenovo Y700 2025, TB321FU, SM8650, 16 GiB + 512 GiB
- Current branch: `codex/tablet-rescue-20260720`
- Current device OS: recovered Kubuntu 26.04 ARM64 baseline
- Last flashed Arch build: workflow run `29709555909`, commit `4edf3a4`
- Last artifact-only build attempt: workflow run `29940159992`, commit
  `3c46e74`; the corrected rootfs SHA and all six explicit collision policies
  passed far enough to build/install the Wi-Fi, QCA Bluetooth, ALSA UCM, and
  generic payload packages, then a provider-sensitive stock-package check
  falsely reported that `libssc` remained after its logged removal
- First post-handoff source fix: commit `d480039`
- Evidence-governance baseline: commit `34de491`
- Offline support-bundle implementation: commit `3a095ed`
- P0 recovery/governance completion: commit `c45ad2a`
- Extended support-bundle redaction: commit `dc36f47`
- Persistent USB coordinator: commits `5f50ade` and `649d032`
- Bluetooth NAP coordinator: commit `406e0c1`
- Rescue CI integration: commit `eaf0650`
- P2 WCN7850 exact-hash/native-package source gate: `SRC-20260722-005`
- P3 pacman lock: seed run `29921200387`, immutable transaction audit
  `AUDIT-20260722-002`, committed pin `e87d90c`
- Qualcomm SSC sensor proxy native replacement source gate:
  `SRC-20260722-009`, commit `68898ad`; the follow-up `libssc` replacement
  source gate is `SRC-20260722-010`, commit `04aa394`
- Elevated rootfs SHA transport source gate: `SRC-20260722-011`, commit
  `f3b4bb4`
- Rootfs SHA byte-diagnostic gate: `SRC-20260722-012`, commit `72c6bd5`
- QCA Bluetooth firmware native-package source gate: `SRC-20260722-013`,
  commit `782dd08`
- ALSA UCM independent-path native-package source gate: `SRC-20260722-014`,
  commit `395175c`
- Exact installed-package name source gate: `SRC-20260722-015`, commit
  `e31977c`
- Latest artifact-only attempt: `CI-20260722-012`, run `29940159992`, failed
  after the replacement transaction logged removal of stock `libssc` and
  installation of `qcom-sns-libssc`; `pacman -Q libssc` then resolved the
  replacement's `provides=libssc` and caused a false-positive stop. Zero
  artifacts were created, and no post-fix artifact exists yet
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
8. `CI-20260722-005` proved that the fixed Qualcomm SSC sensor proxy differs
   from the locked stock `iio-sensor-proxy`; silently dropping either payload
   is forbidden. `SRC-20260722-009` stages the Qualcomm proxy as an independent
   native Arch package with explicit transactional replacement and ownership
   checks. `CI-20260722-007` then found the same ownership problem for
   `/usr/bin/ssccli`; `SRC-20260722-010` packages Qualcomm `libssc` natively
   with explicit replacement semantics. A new artifact-only build is required
   to prove the final rootfs.
9. `CI-20260722-008` passed the immutable lock download and complete pre-build
   verification, then rejected the workflow-selected rootfs SHA inside
   `build-arch-rootfs-image.sh`. The earlier conclusion that the same value had
   passed before `sudo` was incorrect: the pre-build step validated the
   profile's 64-character lock value, while the dispatch input was 63
   characters.
10. `SRC-20260722-011` removes the rootfs SHA from the `sudo --preserve-env`
    dependency and binds it explicitly through the post-`sudo` `env` command.
    The workflow and lock regression gates reject restoration of the fragile
    transport path. `CI-20260722-009` showed that change did not address the
    failure because the dispatched value itself was already truncated.
11. `SRC-20260722-012` makes malformed lock-verifier input report its byte
    length and shell-escaped form. `CI-20260722-010` used it to prove all three
    failed dispatches supplied the 63-character prefix
    `3cf5764f...0404c56`, missing the final `a` from the pinned 64-character
    SHA. This is an operator-input failure, not lock corruption.
12. `CI-20260722-011` reached the device payload merge with the corrected
    64-character rootfs SHA and stopped on a real content mismatch at
    `/usr/lib/firmware/qca/hmtbtfw20.tlv`: the Kubuntu overlay is 265,528
    bytes with SHA-256
    `b4e7f61e7dd090e56811860a7781ff3b0ce8e87cc0480feaab34bf4f614308c5`,
    while locked `linux-firmware-atheros-20260622-1` is 270,120 bytes with
    SHA-256
    `f1c00f4640a5c4e5dc36a2574d3d1d0afcfd1ab58a84f217dce4b1bb73cba981`.
    This is a genuine device-versus-generic firmware collision, not a hash
    transport error; the generic collision guard remains fail-closed.
13. `SRC-20260722-013` packages all 62 fixed device QCA files as
    `tb321fu-bluetooth-firmware` under the existing independent firmware search
    path and retains generic `linux-firmware-atheros` ownership unchanged.
    `AUDIT-20260722-003` then compared all 2,335 device members with all 723
    locked packages: 16 paths intersect, ten are identical, and six differ.
    Wi-Fi plus four QCA differences now have explicit package policies; the
    remaining mismatch is the TB321FU headphone UCM sequence versus
    `alsa-ucm-conf`, so a build containing only the Bluetooth fix is forbidden.
14. `SRC-20260722-014` packages the complete 13-file TB321FU UCM source set as
    `tb321fu-alsa-ucm`, rewrites seven device-profile includes to
    `/usr/share/alsa/ucm2/codecs/tb321fu-wcd939x`, and retains the generic
    `alsa-ucm-conf` WCD939x tree unchanged. The fixed archive fixture, locked
    generic-package combination, `alsaucm` parser, full archive-overlap audit,
    and complete local P3 test matrix pass. Final raw and hardware audio remain
    `UNTESTED`.
15. `CI-20260722-012` accepted the exact committed rootfs SHA and passed the
    immutable lock. It built and installed the new QCA Bluetooth and ALSA UCM
    packages, then proved the stock-package removal validator is
    provider-sensitive: pacman logged `removing libssc...` and
    `installing qcom-sns-libssc...`, but `pacman -Q libssc` still succeeded
    because the replacement declares `provides=libssc`. The same defect can
    misclassify `iio-sensor-proxy`. Exact installed package names must be used
    before another artifact-only build.
16. `SRC-20260722-015` replaces every stock `libssc` and
    `iio-sensor-proxy` pre/post/final query with an exact match against the
    complete `pacman -Qq` installed-name list. The profile forbidden-package
    gate uses the same helper. Regressions prove the installed Qualcomm
    providers and a `libssc-tools` near-match do not imply either exact stock
    package. The complete local P3 matrix and both offline collision audits
    pass; final raw and hardware remain `UNTESTED`.

## Immediate release blockers

- Install and verify the redacted support bundle on TB321FU hardware
- Verify USB role/UDC/ACM/NCM and Bluetooth NAP on TB321FU hardware
- Final-raw proof for the device-specific WCN7850 package, hashes, ownership,
  firmware path, and bootarg
- Final-raw proof for the device-specific QCA Bluetooth package, hashes,
  ownership, firmware path, and bootarg
- Final-raw proof for `tb321fu-alsa-ucm`, all 13 transformed hashes, seven
  includes, package ownership, parser result, and unchanged generic UCM path
- Push `SRC-20260722-015`, record a separate authorization, and complete
  exactly one new artifact-only build; the rootfs SHA must be read and
  validated from `profiles/tablet-niri/pacman-lock.env`
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

# TB321FU roadmap and gates

Last reviewed: 2026-07-22

The long-term target is a deterministic, recoverable, auditable Arch Linux ARM
tablet that is suitable for daily use. Work proceeds in dependency order.

## P0 — Baseline and evidence governance

- Preserve and review the existing source state.
- Maintain `STATUS.md`, `EXPERIMENT-LOG.md`, and `RISK-REGISTER.md`.
- Store release evidence in `validation/<release>/hardware.yaml`.

Exit gate: source, build, artifact, and device identities are unambiguous; no
current-state document contradicts the authoritative status.

## P1 — Rescue and observability

- Replace the blocking USB oneshot with a persistent coordinator.
- Coordinate Type-C role, UDC discovery, ConfigFS, bind/unbind, and hotplug.
- Activate and retry Bluetooth NAP without blocking graphical boot.
- `SOURCE PASS` Produce a one-command redacted support bundle without network
  access (`3a095ed`); hardware acceptance remains pending.
- `SOURCE PASS` Persistent USB coordinator, missing-UDC/hotplug/fallback tests,
  and bounded external commands (`5f50ade`, `649d032`).
- `SOURCE PASS` Bluetooth NAP activation/retry/cleanup coordinator with bounded
  external commands (`406e0c1`).
- `SOURCE PASS` Both coordinators are enabled and gated in CI (`eaf0650`).

Exit gate: rescue failures never block `graphical.target`; tests cover absent
UDC, hotplug, retries, cleanup, command timeouts, and redaction. The P1 source
gate is complete; P7 still requires physical ACM/NCM/NAP acceptance.

## P2 — WCN7850 Wi-Fi

`SOURCE PASS`: `SRC-20260722-005` pins and verifies the fixed device archive,
the exact overlay package, and all six WCN7850 hashes. It packages the
Kubuntu-proven firmware as `tb321fu-wifi-firmware`, uses
`/usr/lib/firmware/tb321fu`, adds the kernel firmware search-path bootarg, and
turns differing Arch-owned import collisions into hard failures.

The old rootfs compressed member remains permanently rejected by
`SRC-20260722-004`. The next stop is P3 followed by a complete build: source
tests do not yet prove the final raw or physical Wi-Fi behavior.

Exit gate: raw-image content, hashes, package ownership, path, and bootarg all

## P3 — Deterministic build candidate

- `SOURCE PASS`: `SRC-20260722-007` implements a two-stage pacman lock because
  `SRC-20260722-006` proved the historical ALARM archive is unavailable. The
  seed freezes repository databases, exact packages/signatures and expected
  package state; the build consumes the pinned artifact under `unshare --net`.
- `AUDIT PASS`: seed run `29921200387` and all 723 locked package/signature/
  database bindings passed `AUDIT-20260722-002`; the immutable pin is committed
  in `profiles/tablet-niri/pacman-lock.env` at `e87d90c`.
- `CI FAIL`: artifact-only run `29924934432` stopped before producing an image
  because the Qualcomm SSC sensor proxy differs from stock
  `iio-sensor-proxy`. `SRC-20260722-009` adds a dedicated native package with
  explicit `provides/conflicts/replaces`, exact payload hashes, ownership and
  stock-removal gates while preserving the generic collision stop line; source
  commit `68898ad`.
- `CI FAIL`: the authorized follow-up run `29928261179` then stopped at the
  remaining Qualcomm `libssc` collision (`/usr/bin/ssccli`). `SRC-20260722-010`
  packages the complete fixed payload as native `qcom-sns-libssc` with
  `provides/conflicts/replaces=libssc`, exact member hashes, and transactional
  ordering before the sensor proxy; source commit `04aa394`.
- `CI FAIL`: run `29931623980` passed verification of the lock profile but the
  rootfs script rejected the separately dispatched rootfs SHA. Later diagnostic
  evidence proved that dispatch value was only 63 characters. No artifact was
  created.
- `SOURCE PASS`: `SRC-20260722-011` explicitly passes the non-secret rootfs
  SHA through the post-`sudo` `env` command and adds a regression gate that
  rejects returning it to `sudo --preserve-env`; source commit `f3b4bb4`.
- `CI FAIL`: run `29932470727` still reported an invalid rootfs SHA after that
  explicit binding because the source value was already truncated. It also
  produced zero artifacts.
- `SOURCE PASS`: `SRC-20260722-012` adds fail-closed byte-level diagnostics for
  malformed rootfs-SHA input and a trailing-newline regression fixture; source
  commit `72c6bd5`.
- `CI FAIL / ROOT CAUSE`: diagnostic run `29933069005` reported
  `length=63` and exposed a value missing the final `a` from the pinned
  64-character rootfs SHA. All three recent dispatches repeated that same
  malformed input and produced zero artifacts.
- `CI FAIL`: corrected artifact-only run `29933523257` accepted the lock SHA
  and reached device payload merging, then rejected the genuine content
  collision at `/usr/lib/firmware/qca/hmtbtfw20.tlv`; no artifact was created.
  The fixed overlay member is 265,528 bytes / SHA-256
  `b4e7f61e7dd090e56811860a7781ff3b0ce8e87cc0480feaab34bf4f614308c5`, while
  locked `linux-firmware-atheros-20260622-1` is 270,120 bytes /
  `f1c00f4640a5c4e5dc36a2574d3d1d0afcfd1ab58a84f217dce4b1bb73cba981`.
- `SOURCE PASS`: `SRC-20260722-013` / commit `782dd08` packages all 62 device
  QCA members under `/usr/lib/firmware/tb321fu/qca`, retains generic Arch
  ownership, and gates the four differing overlaps by content/type/mode.
- `OFFLINE AUDIT`: `AUDIT-20260722-003` compared 2,335 device members against
  723 locked packages: 16 paths intersect, ten are identical, and six differ.
  The remaining unhandled mismatch is
  `/usr/share/alsa/ucm2/codecs/wcd939x/HeadphoneEnableSeq.conf` from
  `alsa-ucm-conf-1.2.16.1-1`.
- `SOURCE PASS`: `SRC-20260722-014` / commit `395175c` locks the complete
  13-file device UCM source, moves all eleven device codec sequences to
  `/usr/share/alsa/ucm2/codecs/tb321fu-wcd939x`, rewrites exactly seven
  includes, retains the generic Arch path, and passes offline `alsaucm`
  parsing with the locked package.
- `LOCAL GATE PASS`: all current P3 workflow, boundary, governance, rescue,
  firmware, UCM, sensor, payload, profile, audio, native-package, signature,
  overlay, publication, and pacman-lock tests pass. The full archive collision
  audit remains 2,335 device members / 723 packages / 16 intersections / ten
  identical / six explicitly handled mismatches.
- `CI FAIL / VALIDATOR ROOT CAUSE`: run `29940159992` at commit `3c46e74`
  accepted the exact committed rootfs SHA and built/installed the Wi-Fi, QCA
  Bluetooth, ALSA UCM, and generic payload packages. Pacman then logged
  removal of stock `libssc` and installation of `qcom-sns-libssc`, but the
  provider-sensitive `pacman -Q libssc` check falsely treated
  `provides=libssc` as the stock package remaining. Zero artifacts and no
  Release were created. The same query defect exists for
  `iio-sensor-proxy`.
- `SOURCE PASS`: `SRC-20260722-015` / commit `e31977c` queries the complete
  `pacman -Qq` installed-name list and matches exact package names for all
  stock `libssc` and `iio-sensor-proxy` pre/post/final checks and the tablet
  profile forbidden-package pass. Regressions reject provider-only and
  near-match false positives. The complete local P3 matrix and both offline
  collision audits pass again; final raw remains `UNTESTED`.
- `AUTHORIZED/PENDING`: `CI-20260723-001` binds the next candidate to source
  evidence head `621df8f`, output prefix
  `TB321FU-archlinuxarm-tablet-niri-ci13-20260723`, `tablet-niri`, `20G`,
  empty advanced configs, no Release, and the rootfs SHA read from the lock
  profile.
- Current stop: dispatch that authorization exactly once, then perform the P4
  offline audit. Do not publish a Release, flash a device, or retry commit
  `3c46e74` unchanged.
- Pin every remaining controllable input.
- Validate niri, service behavior, credentials policy, final configuration
  paths, package ownership, and secret absence.
- Build artifact-only; do not publish a release.

Exit gate: local tests and CI pass without hidden failures, and metadata is
free of credentials.

## P4 — Complete offline audit

- Verify all archive and raw-image hashes.
- Run read-only ext4 and FAT checks.
- Audit accounts, boot chain, DTB, cmdline, firmware, services, permissions,
  rescue paths, and actual user configuration.

Exit gate: every required audit item is PASS before a flash bundle is made.

## P5/P6 — Device-specific flash preparation and controlled write

- Re-read and validate the device GPT.
- Bind one bundle to one run, commit, image set, GPT, and programmer hash.
- Use only the verified Windows Firehose path for `userdata`.
- Require ten-point `MATCHED=10/10` readback before reset.

Exit gate: complete write/readback logs are saved and all identities match.

## P7 — Rescue and networking acceptance

Test in this order: support bundle, ACM, NCM, Bluetooth NAP, then Wi-Fi.

Exit gate: at least two independent rescue channels pass on hardware; every
failure produces automatic evidence; Wi-Fi passes scan, association, DHCP,
reconnect, and screen-off recovery.

## P8/P9 — Daily hardware and release maturity

- Verify landscape touch, OSK, 120 Hz, audio, microphone, haptics, brightness,
  battery, charging, screen-off wake, networking, and required applications.
- Record camera and suspend honestly without making them first-release gates.
- Progress through Rescue alpha, Networking alpha, Daily Tablet beta, Stable.

Exit gate: first-release hardware requirements are `VERIFIED`, no P0/P1 issue
remains, and stability/recovery exercises are recorded.

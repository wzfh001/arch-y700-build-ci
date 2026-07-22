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

- Pin every controllable input.
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

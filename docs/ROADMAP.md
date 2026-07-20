# TB321FU roadmap and gates

Last reviewed: 2026-07-21

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
- Produce a one-command redacted support bundle without network access.

Exit gate: rescue failures never block `graphical.target`; tests cover absent
UDC, hotplug, retries, cleanup, and redaction.

## P2 — WCN7850 Wi-Fi

- Pin and verify the device archive.
- Package the Kubuntu-proven device firmware with exact file hashes.
- Use an independent firmware search path and verify the kernel bootarg.
- Reject final images where the generic firmware replaces device firmware.

Exit gate: raw-image content, hashes, package ownership, path, and bootarg all
pass deterministic checks.

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

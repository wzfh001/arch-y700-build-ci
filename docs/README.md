# Documentation Index

This repository is the **Arch Linux ARM + kernel build pipeline** for the Lenovo
Y700 2025 (TB321FU / SM8650). Start here if you are new.

| Document | Purpose |
|---|---|
| [`STATUS.md`](STATUS.md) | **Start here.** Current project status: P0–P9 phases, kernel K0–K9 phases, firmware reality, and what is blocked. |
| [`ROADMAP.md`](ROADMAP.md) | Milestones, releases and the dependency-ordered execution path. |
| [`BUILD.md`](BUILD.md) | How the two GitHub Actions workflows build the kernel and the rootfs/GRUB images, plus inputs and pins. |
| [`FLASHING.md`](FLASHING.md) | Flash discipline and safety red lines. Read before touching a device. |
| [`RECOVERY.md`](RECOVERY.md) | Rescue channels and rollback paths (Kubuntu baseline, Fastboot, Firehose). |
| [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) | Known root causes: Wi-Fi, USB/UDC, Bluetooth NAP, and how to verify each. |
| [`UPSTREAM.md`](UPSTREAM.md) | Repository topology: this fork, GUF296 upstream, kernel source, and artifact sources. |
| [`AUDIT-LOG.md`](AUDIT-LOG.md) | Append-only record of offline audits and device experiments (EXP-/AUDIT-/CI- IDs). |

Status words used everywhere: `VERIFIED`, `PARTIAL`, `BROKEN`, `UNTESTED`,
`BLOCKED`, `OUT-OF-SCOPE`, `UNKNOWN`, `PASS`, `FAIL`.

> The canonical long-form handoff document lives outside this repository
> (`TB321FU-HANDOFF-CURRENT.md` in the workspace). This `docs/` tree is the
> GitHub-facing, human-readable view of the same facts.

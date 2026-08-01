# Audit & Experiment Log (append-only)

Every offline audit and device experiment gets a stable ID and an entry here.
The canonical full records live in the workspace kernel `experiments/`,
`reports/` and main-project handoff; this file is the GitHub-facing index.

## IDs

- `AUDIT-YYYYMMDD-NNN` — offline audit
- `EXP-YYYYMMDD-NNN` — kernel experiment (build/assembly/device)
- `CI-YYYYMMDD-NNN` — CI acceptance record
- `SRC-YYYYMMDD-NNN` — source-gate record

## 2026-08

| ID | Kind | Scope | Result |
|---|---|---|---|
| `EXP-20260801-001` | kernel experiment | K4 reproducible build (run 30704468188) | PASS (REPRO-CLOSE basis) |
| `EXP-20260801-002` | kernel experiment | K7 boot/GRUB assembly dry-run vs official template | PASS (candidate `dade9ac5b2…`) |
| `EXP-20260729-001` | kernel experiment | source worktree HEAD verification | VERIFIED |

## 2026-07

| ID | Kind | Scope | Result |
|---|---|---|---|
| `CI-20260723-001` | CI record | artifact-only build run 29966711103 | PASS (no release, no write) |
| `AUDIT-20260723-001` | offline audit | full candidate ZIP audit (rootfs/GRUB/boot) | **PARTIAL/BLOCKED** (main ZIP not fully downloaded) |
| `SRC-20260722-005` | source gate | pinned device archive + WCN7850 real SHAs + firmware package | PASS |
| `SRC-20260722-004` | source gate | old raw board-2.bin.zst 33090-byte member | **FAIL — forbidden to repeat** |
| `DEV-20260722-002/003` | dev failure | earlier WCN7850 extraction failures | FAIL (recorded) |

## How to add an entry

1. Assign the next ID in the right sequence.
2. Write the canonical record in the workspace.
3. Append one row here.
4. Run `scripts/ci/update-project-status.sh` to refresh `docs/STATUS.md`.

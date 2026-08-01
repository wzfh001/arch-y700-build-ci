# Repository Topology & Upstreams

## This repository

`wzfh001/arch-y700-build-ci` — fork of `GUF296/arch-y700-build-ci` (the author
of the vendor Y700/TB321FU kernel and build). It builds the **Arch Linux ARM**
route with the same kernel/DTB/device archive as upstream.

```text
origin  = https://github.com/GUF296/arch-y700-build-ci.git   (upstream)
fork    = https://github.com/wzfh001/arch-y700-build-ci.git   (this repo)
```

Local `main` = fork/main = `4e9e6e1`; upstream origin/main is behind by 23
commits (not yet pushed upstream).

## Kernel source

```text
repo:   https://github.com/GUF296/linux
branch: TB321FU-7.1.1
head:   5df8e852ea722929f5359a5ef28ebcec0c4443fd
describe: v7.1-19-g5df8e852ea72
base_commit: 66edb901bf874d9e0787326ba12d3548b2da8700
```

Local shallow worktree: `kernel/worktrees/TB321FU-7.1.1` (in the workspace).

## Artifact / device payload sources

| Source | Purpose | Pinned SHA |
|---|---|---|
| `bootstrap-y700-20260625` release `y700-kernel-artifacts-7.1.1-g5df8e852ea72.tar.gz` | prebuilt kernel Image/DTB/config | `86ea0190e3a073a8ce94e1d6f74dcc3482457a0b9161c2ff968aaeb0f1147188` |
| same release device debs (compat1) | kernel modules + firmware + udev + services | `047c1bac…` |
| `source/boot-image/boot.img.7z` (committed) | Android bootimg (not GRUB FAT); informational | `a9c2e176…` |
| official GRUB template | verified boot template for GRUB path | `7136020f5c736e13772980af5d22652e71281f34ce3da7b22add928a62ebd194` |

## Other repos in scope (workspace)

- `ubuntu-y700-build-ci` — Ubuntu/Kubuntu route (separate repository).
- `TB321FU-7.1.1` kernel worktree — source of the reproducible build.

## Key documents elsewhere

- Kernel project plan + handoff: `kernel/KERNEL-PROJECT-PLAN.md`,
  `kernel/KERNEL-HANDOFF-CURRENT.md`
- Main project handoff: `TB321FU-HANDOFF-CURRENT.md`

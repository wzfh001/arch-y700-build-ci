# Deterministic build policy

No build is a release candidate unless every controllable input is pinned and
the resulting identity can be explained without consulting mutable state.

## Required input identity

- TB321FU device and `tablet-niri` profile
- Git commit and workflow run
- Arch rootfs URL, size, SHA-256, and signing fingerprint
- kernel, device archive, boot template, DTB, and third-party asset identities
- workflow inputs and source-config hash, excluding all secret values

Secrets are accepted only as step-scoped environment data. They must never be
written to workflow inputs, metadata, logs, manifests, or release notes.

## Build gate

1. Worktree state and commit identity are recorded in the experiment log.
2. Every local CI script and workflow semantic check passes without hidden
   `|| true` success paths.
3. `niri validate` and final installed configuration-path checks pass.
4. The run is artifact-only. A successful build does not authorize flashing.
5. Rootfs, GRUB, boot, DTB, input manifest, and package ownership evidence are
   preserved together under one candidate identity.

The authoritative commands are the CI steps in
`.github/workflows/build-rootfs-and-grub.yml`. Do not copy isolated commands
from old runs as evidence for a new candidate.

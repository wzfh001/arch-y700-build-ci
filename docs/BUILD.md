# Build

Two GitHub Actions workflows build everything in this repository. Both are
`workflow_dispatch`-only and artifact-only by default (no Release, no device
write).

## 1. Kernel repro build — `build-kernel.yml`

Builds `GUF296/linux` at a pinned ref with the baseline config, on
`ubuntu-24.04` x86_64 with `gcc-aarch64-linux-gnu` 13.3.0 + binutils 2.42
(aligned with the vendor banner).

| Input | Default | Meaning |
|---|---|---|
| `kernel_ref` | `TB321FU-7.1.1` | GUF296/linux ref (branch or commit) |
| `build_config` | `baseline` | `baseline` (pinned kernel.config), `defconfig`, or `fragment` (baseline + one or more fragments) |
| `fragments` | empty | Comma-separated fragment names from `source/kernel/fragments/*.config`, used only with `build_config=fragment` (e.g. `10-tablet-perf,20-tablet-memory`) |

Pinned ref: `5df8e852ea722929f5359a5ef28ebcec0c4443fd` (K1/K4 verified).
Artifacts: `Image`, `sm8650-lenovo-tb321fu.dtb`, `kernel.config`,
`modules.tar.gz`, `BUILD-INFO.txt`, `SHA256SUMS`, uploaded as
`tb321fu-kernel-repro-<kernel_ref>-<build_config>-<run_id>`.

Last successful run: `30704468188` (2026-08-01). See `docs/STATUS.md` for hashes.

## 2. RootFS + GRUB build — `build-rootfs-and-grub.yml`

Builds the Arch Linux ARM rootfs (Plasma profiles), packages kernel modules and
firmware, and assembles the GRUB FAT boot image.

| Input | Default | Meaning |
|---|---|---|
| `release_tag` | empty | Empty = artifact-only. Non-empty + `prerelease=true` = prerelease |
| `prerelease` | false | Must be true when publishing a remediation release |
| `output_prefix` | `TB321FU-archlinuxarm-plasma-aarch64` | Filename prefix |
| `arch_rootfs_url` | `de3.mirror.archlinuxarm.org` rolling URL | Pinned rootfs tarball |
| `arch_rootfs_sha256` | pinned | Required; fails closed if changed |
| `desktop_profile` | `standard` | `minimal` / `standard` / `full` |
| `rootfs_image_size` | `20G` | ext4 image size |
| `rootfs_config` / `boot_config` / `source_config` | empty | Advanced `KEY=value` overrides |

### Pinned inputs

```text
KERNEL_ARTIFACT_ARCHIVE = bootstrap-y700-20260625/y700-kernel-artifacts-7.1.1-g5df8e852ea72.tar.gz
KERNEL_ARTIFACT_ARCHIVE_SHA256 = 86ea0190e3a073a8ce94e1d6f74dcc3482457a0b9161c2ff968aaeb0f1147188
Arch rootfs (de3, 2026-06-06) SHA256 = 3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
```

All URLs, versions, commits, package snapshots and SHA-256s must be pinned; a
changed rolling archive fails closed until the pin is deliberately updated.

### Secrets

Passwords are never workflow inputs. Use repository secrets:

- `DEFAULT_USER_PASSWORD_HASH` (SHA-512 encrypted hash for the default user)
- `ROOT_PASSWORD_HASH` (only when `ROOT_PASSWORD_MODE=set`)

Hashes are exposed only to the rootfs build step and are not written to
metadata artifacts or release notes.

### Outputs

```text
boot.img.7z, grub.img.7z, rootfs.img.7z.000, rootfs.img.7z.001, SHA256SUMS.txt
```

Recombine split rootfs: `cat rootfs.img.7z.* > rootfs.img.7z`.

## Local checks

```bash
bash scripts/ci/run-actionlint.sh .github/workflows/build-kernel.yml
python3 scripts/ci/check-action-pins.py .github/workflows/build-kernel.yml
python3 scripts/ci/check-workflow-input-boundaries.py .github/workflows/build-rootfs-and-grub.yml
bash scripts/ci/test-input-and-path-boundaries.sh
```

The rootfs workflow runs the full local gate suite before building.

### Kernel fragments (customization)

`build_config=fragment` starts from the pinned baseline `kernel.config`, then
merges named fragments from `source/kernel/fragments/` using the kernel's own
`scripts/kconfig/merge_config.sh`, then runs `make olddefconfig`.

Current candidate fragments (all **candidate**, not yet on device; each is a
single-variable group, K9 discipline, independent EXP, rollback to baseline
unit):

| Fragment | Symbols | Rationale | Source |
|---|---|---|---|
| `10-tablet-perf` | `HZ=1000`, `PREEMPT_DYNAMIC=y` | KDE touch/scroll responsiveness; slight power cost | ALARM linux-aarch64 |
| `20-tablet-memory` | `ZRAM=m`, `ZSWAP=y`, `PSI=y` | 16 GiB RAM swap backstop; earlyoom/systemd-oomd pressure signals | ALARM linux-aarch64 |
| `30-tablet-network` | `WIREGUARD=m`, `NF_TABLES=m`, `CFS_BANDWIDTH=y` | VPN/nftables support; clears nftables service failed state | ALARM linux-aarch64 |
| `40-arch-compat` | `SECURITY_LANDLOCK=y`, `BINFMT_MISC=y` | pacman filesystem sandbox (Landlock) + binfmt_misc; fixes `DisableSandboxFilesystem` workaround | ALARM linux-aarch64 |

Fragments only set explicit symbols; everything else stays byte-identical to
the baseline. The merged `.config` is uploaded as `kernel.config` and recorded
in `BUILD-INFO.txt` (`fragments=` field). Adding a new fragment is a normal
commit; running it on the device requires an EXP ID and an explicit user go.

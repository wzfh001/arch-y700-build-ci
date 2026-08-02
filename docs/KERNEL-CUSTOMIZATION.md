# Kernel customization (config fragments)

> Updated: 2026-08-02
> Companion to `BUILD.md` § Kernel fragments. Detailed three-way config
> comparison lives in the workspace kernel notes
> (`kernel/notes/CONFIG-THREEWAY-COMPARISON.md`,
> `kernel/notes/ALARM-BUILD-COMPARISON.md`).

## Why fragments, not a new defconfig

The device baseline is the pinned vendor `kernel.config` (4912 symbols,
K3-verified, zero functional diff in the repro build). Both the in-tree arm64
`defconfig` (1974 symbols) and the ALARM `linux-aarch64` config (6986 symbols,
multi-platform) are **not** device baselines:

- `defconfig` lacks the panel/touch/haptics drivers
  (`DRM_PANEL_NOVATEK_NT36523`, `TOUCHSCREEN_NT36523_SPI`,
  `INPUT_AW86937_Y700`) and would demote `DRM_MSM`/`SCSI_UFS_QCOM` to modules.
- ALARM's config targets every ARM board (RPi/Rockchip/Apple/…) and is a
  different kernel version lineage (7.1.3 config header, 7.1.5 pkg).

So customization = **baseline + explicit fragments**, each a small
single-variable group, validated one at a time on the device.

## How it works

```text
cp source/kernel/kernel.config .config
scripts/kconfig/merge_config.sh -m -O . .config source/kernel/fragments/<name>.config ...
make ARCH=arm64 olddefconfig
```

The merged `.config` is uploaded as `kernel.config`; `BUILD-INFO.txt` records
`config_source=fragment` and `fragments=<names>`. Only explicit symbols change;
everything else stays byte-identical to baseline.

## Candidate fragments

| Fragment | Changes | Notes |
|---|---|---|
| `10-tablet-perf` | `HZ=1000` (+ `HZ_1000=y`, `HZ_250` unset), `PREEMPT_DYNAMIC=y` | KDE touch/scroll latency; slight power cost |
| `20-tablet-memory` | `ZRAM=m`, `ZSWAP=y`, `PSI=y` | 16 GiB RAM swap backstop; systemd/earlyoom pressure signals |
| `30-tablet-network` | `WIREGUARD=m`, `NF_TABLES=m`, `CFS_BANDWIDTH=y` | VPN/nftables; clears the `nftables` service failed state on the device |
| `40-arch-compat` | `SECURITY_LANDLOCK=y` (auto-selects `SECURITY_NETWORK`/`SECURITY_PATH`), `BINFMT_MISC=y` | **pacman 7.1.x filesystem sandbox 依赖 Landlock**（作者内核未开 → 设备曾用 `DisableSandboxFilesystem` 绕过）；ALARM 官方 config 已开此两项 |

All candidates are **off-device** until an EXP ID + explicit user go. Device
kernel today: `7.1.1-g5df8e852ea72` (vendor). Version bump (e.g. 7.1.1 → 7.1.5)
is a separate change-control topic, not a fragment.

## What we deliberately do NOT adopt from ALARM

- Multi-platform config / defconfig swap (would lose device drivers).
- ALARM 7.1.x versioning/localversion (`7.1.5-2-aarch64`) — ours stays
  `7.1.1-g5df8e852ea72` to match the verified device baseline.
- `DTC_FLAGS="-@"` dtbs (GRUB path needs no overlay symbols).
- RPi/Rockchip/Apple platform patches and config.

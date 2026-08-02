# tablet-kde CI run 身份（2026-08-02）

| 项 | 值 |
|---|---|
| fork | `wzfh001/arch-y700-build-ci`（只推此 fork，origin=GUF296 永不推） |
| branch | `codex/tablet-kde-20260802` |
| head | `5e5017f`（CI 实际构建 head；仓库 HEAD 已到 `dd07535`，审计脚本修复已推 fork，不影响产物） |
| run id | `30730513005` |
| workflow | `build-rootfs-and-grub.yml` |
| desktop_profile | `tablet-kde` |
| output_prefix | `TB321FU-archlinuxarm-plasma-aarch64` |
| 旧 run（作废） | `30730288776`（b57147f，缺用户级 KDE 配置，已取消） |
| 更早旧 run（作废） | `29966711103`（tablet-niri，不刷） |

## 关键输入

- ARCH_ROOTFS: `ArchLinuxARM-aarch64-latest.tar.gz` SHA `3cf5764f…`
- device archive: `y700-device-debs-20260624-201420-compat1.tar.gz` SHA `047c1bac…e04`
- sensor debs: `tb321fu-sensor-debs_20260627.1` SHA `62ebf6fb…ab10`
- haptics: `tb321fu-haptics-debs_20260627.2` SHA `5a87f510…20a37`
- kernel: `7.1.1-g5df8e852ea72`（K4 复现验证）
- secrets（fork）: `DEFAULT_USER_AUTHORIZED_KEYS`、`DEFAULT_USER_PASSWORD_HASH`
- root: locked（无需 secret）；fuhao sudo password

## CI 状态（2026-08-02）

- run `30730513005` **SUCCESS**（head `5e5017f`，全部 13 步绿）
- artifact 已取回：`/mnt/game/.TB321FU-tablet-kde-run-30730513005-audit/downloads/`
- rootfs raw SHA `c4efa7ce…e98a8`；grub-fat `7378dc11…41cc`；boot `45f923bc…2d58f`
- **P4 审计 VERIFIED（2026-08-02）**：外层 SHA 全 OK、e2fsck 0 错误、KDE 配置 6/6、固件 board-2.bin=c896bc77…7fb、系统服务 10/10 + 用户单元 4/4、账号/SSH 安全项全过。证据：`/mnt/game/.TB321FU-tablet-kde-run-30730513005-audit/evidence/P4-AUDIT-20260802-CONCLUSION.txt`

## 期望产物（CI 完成后核对）

- rootfs.img.7z / grub-fat.img.7z / boot.img.7z
- 主 ZIP SHA/size 以 Actions run 页面为准（下载后 `sha256sum` 比对）
- grub.cfg 含 `firmware_class.path=/usr/lib/firmware/tb321fu`、`root=PARTLABEL=userdata`
- `/home/fuhao/.config/` 含 kwinoutputconfig.json(Rotated270)/kwinrc/environment.d/mimeapps.list

## 后续

P4 审计 → P5 bundle（模板 `P5-BUNDLE-BUILD.md`）→ 用户放行 → Windows QFIL → P7/P8（模板 `HARDWARE-ACCEPTANCE-CHECKLIST.md`）

---

# Wi-Fi 修复后 run（2026-08-02）

## run `30736975180`（最终候选）

| 项 | 值 |
|---|---|
| head | `d1d3c1d`（build-arch-rootfs-image.sh：从已安装 rootfs 的 tb321fu 路径回填标准 ath12k 路径；修复 39cdfc8 stage 删除 bug） |
| 前置修复 | `39cdfc8`（标准路径安装板级固件，CI 失败）、`a3ca23d`（audit 脚本标准路径断言） |
| CI 结果 | **SUCCESS**（24m45s，全部步骤绿） |
| 下载 | `/mnt/game/.TB321FU-tablet-kde-run-30736975180-download/` |
| rootfs raw SHA | `3a472fbca5ac591794ea238d27225029836919f9c23215db16ba562956d78ae2` |
| grub-fat raw SHA | `f54035fd298b6f81ad7a26893b6007e3e7b62a03372899f8b49573be2ba09945` |
| boot raw SHA | `a9c2e176b34d3205f8f71b5819c58d215dcb993395191d8d44f37d922f592b02` |
| **标准路径 board-2.bin** | `c896bc7782e252aa915849d5c9c47d109ecfe9f0fc5650fe771f7ba8f8eb77fb`（202148B，debugfs 实测） |
| e2fsck | 0 errors（232575 files） |
| FAT fsck | PASS（269 files） |

## P4 审计（2026-08-02，run 30736975180）

- audit-tablet-kde-rootfs.sh 全项 PASS（fuhao/root locked、KDE 配置 6/6、固件标准路径板级、原生包、服务 10/10 + 用户 4/4）
- grub.cfg 含 firmware_class.path=/usr/lib/firmware/tb321fu + root=PARTLABEL=userdata
- 证据：`/mnt/game/.TB321FU-tablet-kde-run-30736975180-audit/evidence/P4-AUDIT-20260802-CONCLUSION-30736975180.txt`

## P5 bundle（2026-08-02，run 30736975180）

- `builds/flash-bundles/TB321FU-tablet-kde-run-30736975180/` 19 成员齐备
- `BUNDLE-SHA256SUMS.txt` 本地 `sha256sum -c` 19/19 PASS
- readback 期望 10/10 MATCH（从新 raw `3a472fbc…` 重算）
- known-gpt/firehose XML 与已验证 niri bundle 逐字节一致
- **这是最终待刷 bundle**（Wi-Fi 固件布局已修复）

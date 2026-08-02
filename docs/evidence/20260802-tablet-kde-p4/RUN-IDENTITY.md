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

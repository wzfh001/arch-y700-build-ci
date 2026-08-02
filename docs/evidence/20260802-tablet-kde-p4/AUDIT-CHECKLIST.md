# tablet-kde P4 离线审计检查单（2026-08-02）

> 适用于 `codex/tablet-kde-20260802` @ `5e5017f` 的 CI run
> （`30730513005`，desktop_profile=tablet-kde，output_prefix=TB321FU-archlinuxarm-plasma-aarch64）。
> 仅在主 artifact ZIP 完整取回、外层 digest/size 匹配后执行。状态词只许 VERIFIED/PARTIAL/BROKEN/UNTESTED/BLOCKED/UNKNOWN。

## 0. 外层完整性

- [ ] 主 ZIP SHA-256 与 Actions 声明一致（`gh run download` 后 `sha256sum`）
- [ ] 主 ZIP 大小一致
- [ ] `unzip -t` PASS
- [ ] 内部 `SHA256SUMS` 全过
- [ ] rootfs.img.7z / grub.img.7z / boot.img.7z 哈希各自匹配，`7z t` 通过

## 1. rootfs 镜像

- [ ] rootfs.img raw SHA-256 与 7z 解压后一致
- [ ] `e2fsck -fn` 0 错误
- [ ] `root=PARTLABEL=userdata`、`firmware_class.path=/usr/lib/firmware/tb321fu`（grub.cfg / STABLEARGS）
- [ ] `BOOT_FAT_LABEL=Y700GRUB`、FAT fsck PASS

## 2. 账号与安全

- [ ] 主机名 `fuhao`、用户 `fuhao`（非 alarm）
- [ ] root locked；`fuhao` 在 wheel 且 sudo 需要密码
- [ ] `fuhao/.ssh/authorized_keys` 已注入（来自 fork secret `DEFAULT_USER_AUTHORIZED_KEYS`）
- [ ] 用户密码为 SHA-512 哈希（来自 secret，不在镜像明文）
- [ ] SSH host keys 已清空（构建时删除，首启生成）

## 3. KDE / Plasma 会话（tablet-kde 特有）

- [ ] SDDM 已启用，默认 target = graphical.target
- [ ] `kwinoutputconfig.json` 位于 `/home/fuhao/.config/`：connectorName=DSI-1、mode 1600x2560@120Hz、scale 2.3、**transform=Rotated270**
- [ ] `/home/fuhao/.config/kwinrc`：`[Wayland] InputMethod=org.kde.plasma.keyboard.desktop`、`VirtualKeyboardEnabled=true`
- [ ] `/home/fuhao/.config/plasmakeyboardrc` 存在
- [ ] **`/home/fuhao/.config/environment.d/90-tablet-kde.conf` 存在**（XMODIFIERS/SDL/ELECTRON/MOZ 环境）——这是 `5e5017f` 修复项
- [ ] **`/home/fuhao/.config/mimeapps.list` 存在且只引用 firefox/dolphin/okular/elisa**——`5e5017f` 修复项
- [ ] `/home/fuhao/.config/fcitx5/profile` 存在，DefaultIM=pinyin

## 4. 固件 / 原生包

- [ ] `/usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin` 202148B、SHA=`c896bc77…7fb`
- [ ] QCA Bluetooth 62 文件、ALSA UCM 13 文件 manifest 校验通过
- [ ] `tb321fu-wifi-firmware`、`tb321fu-bluetooth-firmware`、`tb321fu-alsa-ucm`、`qcom-sns-libssc`、`qcom-sns-iio-sensor-proxy` 均为 pacman 原生包（`pacman -Qoq` 归属正确）
- [ ] stock `libssc` / `iio-sensor-proxy` 已被替换（不存在）
- [ ] `/usr/lib/firmware/tb321fu` 通过 `firmware_class.path` 生效

## 5. 服务

- [ ] `sddm.service`、`NetworkManager.service`、`sshd.service`、`bluetooth.service` enabled
- [ ] tablet-kde 额外：`nftables.service`、`tb321fu-grow-rootfs.service`、`tb321fu-usb-rescue.service`、`tb321fu-bt-nap.service`、`serial-getty@ttyGS0.service`、`systemd-timesyncd.service` enabled
- [ ] user units：`pipewire.socket`、`pipewire-pulse.socket`、`wireplumber.service`、`fcitx5-tablet.service` enabled

## 6. 结论

- 记录每项 PASS/FAIL + 证据行；全部 PASS → P4 VERIFIED → 出 P5 bundle
- 任何 FAIL → PARTIAL/BROKEN，禁止进入 P5

## 证据落盘

- 复制检查单到 `/mnt/game/.TB321FU-tablet-kde-run-<runid>-audit/evidence/`
- 实际命令输出追加到 `P4-AUDIT-2026XXX-EVIDENCE.txt`

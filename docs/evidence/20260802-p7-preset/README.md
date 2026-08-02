# P7 预置离线核查（run 29966711103 候选镜像, 2026-08-02）

status: VERIFIED（离线只读核查，未上机）
对象: TB321FU-tablet-niri-run-29966711103 候选
  rootfs raw SHA = 6d1af258405cb1edefe5d43b2a94d3568c6e098c573aaddef867b914d8e9f2d7
  grub raw SHA   = 13747e8638e8932de2a392358ffa5cfd4844ddb2f9309ac8dde9dbc2249898fd
方法: debugfs 只读遍历 ext4 rootfs；mtools 只读遍历 FAT grub；对照 BUILD-INFO.txt

## 结果

| 预置项 | 位置 | 状态 |
|---|---|---|
| support bundle 采集 | `/usr/local/bin/tb321fu-support-bundle`（5550B, 0755） | VERIFIED |
| 脱敏器 | `/usr/local/libexec/tb321fu-redact-support-bundle`（4508B, 0755） | VERIFIED |
| USB 救援 | `/usr/local/libexec/tb321fu-usb-rescue`（7443B）| VERIFIED |
| BT NAP 救援 | `/usr/local/libexec/tb321fu-bt-nap`（3120B）| VERIFIED |
| WCN7850 板级固件 | `/usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin` **202148B** | VERIFIED |
| bootargs 固件路径 | grub BOOT-INFO `stableargs=... firmware_class.path=/usr/lib/firmware/tb321fu` | VERIFIED |

BUILD-INFO 关键字段（来自 CI 构建事实）:
- rescue_usb_network=cdc-ncm:10.77.0.1/24:networkmanager-shared
- rescue_usb_console=cdc-acm:ttyGS0:password-login
- rescue_bluetooth_network=nap:10.78.0.1/24:networkmanager-shared
- rescue_module_policy=pmic_glink,ucsi_glink,ath12k_wifi7,bnep,libcomposite,usb_f_acm,usb_f_ncm
- wifi_firmware_package=tb321fu-wifi-firmware
- wifi_firmware_search_path=/usr/lib/firmware/tb321fu
- wifi_board_2_bin_sha256=c896bc7782e252aa915849d5c9c47d109ecfe9f0fc5650fe771f7ba8f8eb77fb

## 说明

- 202148B board-2.bin 与 2026-07-19 已验证基线尺寸一致（Kubuntu 上 Wi-Fi VERIFIED 使用的同尺寸板级固件）。
- 默认 ath12k 目录另有一份 2253964B board-2.bin（官方 WCN7850 全量）；候选通过 `firmware_class.path=/usr/lib/firmware/tb321fu` 让内核先查 tb321fu 专属目录。
- 本核查只证明"候选镜像内固件/脚本已就绪"；实机 PASS 仍须 P6 完成后上机执行（support bundle 落盘）。

证据原图: 本目录 `gpt-*` 见 `docs/evidence/20260802-gpt-reacquire/`（同一候选 bundle）。

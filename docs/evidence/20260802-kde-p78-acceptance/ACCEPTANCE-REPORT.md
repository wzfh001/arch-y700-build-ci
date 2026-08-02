# KDE bundle run 30736975180 实机验收报告

- 时间：2026-08-02（Wi-Fi 修复后，用户 Windows QFIL 刷入）
- 设备：Lenovo Y700 2025 / TB321FU，IP `192.168.0.156`（user fuhao）
- 内核：`7.1.1-g5df8e852ea72`
- bundle：`builds/flash-bundles/TB321FU-tablet-kde-run-30736975180/`（19/19 PASS）
- 支持包：`tb321fu-support-20260802T091545Z.tar.zst`（SHA `b09f607d…f5590`，44 文件）

## P7 首启救援和网络验收

| 项 | 状态 | 证据 |
|---|---|---|
| 启动链 + KDE Wayland | VERIFIED | sddm + kwin_wayland + plasmashell active；session Type=wayland Desktop=KDE |
| Wi-Fi 扫描/连接/DHCP | VERIFIED | `803_5G` 信号 83，wlp1s0 UP 192.168.0.156/24，DHCP 正常 |
| Wi-Fi firmware | VERIFIED | `/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin` = 202148B / `c896bc77…`（板级） |
| 自动 support bundle | VERIFIED | 44 文件打包生成 |
| USB ACM/NCM | PARTIAL | UDC 空、port0 host——需物理 Type-C 切 device |
| Bluetooth NAP | PARTIAL | profile 激活重试中，bnep0 未出现 |
| Wi-Fi 重连/关屏恢复 | UNTESTED | 需物理按键测试；rfkill 未阻塞 |

## P8 桌面和硬件日用验收

| 项 | 状态 | 证据 |
|---|---|---|
| 显示 | VERIFIED | DSI-1 `1600x2560@120.00`、Rotation 8（270°）、Scale 2.3 |
| 触控 | VERIFIED | NVTCapacitiveTouchScreen（10 点）+ Pen，16000x25600 |
| 亮度 | VERIFIED | ktz8866-backlight 1027→800→1027 往返 |
| 电池 | VERIFIED | qcom-battmgr 88→90% charging，36.5°C，7 cycles |
| 音频扬声器 | VERIFIED | **use-acp=false 修复后** sink 可用，pw-play rc=0，AW882xx 路由 Enable |
| 音频麦克风 | VERIFIED | pw-record 593KB WAV 生成 |
| 耳机实音 | UNTESTED | UCM Headphones 设备枚举存在，物理听感需用户确认 |
| 震动 | PARTIAL | aw86937-haptics-left/right 设备存在（event1/2），服务 active |
| 关屏/唤醒 | UNTESTED | 需物理按键 |
| 相机 | OUT-OF-SCOPE | v4l2 设备枚举存在（ISP 12 个节点），未作为首版门槛 |

## 服务健康
- `systemctl --failed`：0 项（修复 nftables + 2 wait-online 后）
- sshd / NetworkManager / sddm / bluetooth / tb321fu-usb-rescue / tb321fu-bt-nap / tb321fu-haptics / qcom-sns-init：全部 active

## 遗留（用户配合项）
1. 关屏 → 电源键唤醒 → 确认 Wi-Fi 自动重连（预期 PASS）
2. 插入 3.5mm 耳机 → 确认声音切到耳机、拔出切回扬声器
3. 物理 USB Type-C 线接电脑 → 确认 USB 救援 gadget 激活（UDC 出现、usb0/bnep0）
4. 听一下扬声器实际出声（pw-play 已 rc=0）

## 构建侧修复（已回填仓库，待 CI）
- `scripts/ci/build-arch-rootfs-image.sh`：WirePlumber `use-acp=false`（音频修复）
- 3 个失败服务为设备运行时问题，构建侧无需改（nftables 需内核 NF_TABLES 才有意义）

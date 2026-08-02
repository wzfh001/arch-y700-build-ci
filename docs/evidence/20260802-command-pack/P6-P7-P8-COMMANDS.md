# P6→P7→P8 放行后执行命令包（2026-08-02）

status: READY（命令包已固化；未上机）
适用: 用户放行后，Windows 端 Codex + 平板端按本页逐条执行。每步都有成功标志；失败即停并记录。

## P6：受控刷写（Windows 端）

```powershell
# 0) 前置：解压 bundle 到 C 盘（≥26 GiB 空闲），设备保持关机
# 1) bundle 完整性（应输出 BUNDLE_VERIFY=PASS FILES=19）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Bundle.ps1
# 2) 解压镜像到工作目录（应输出 PREPARE_IMAGES=PASS）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Prepare-Images.ps1
# 3) 设备进 9008/Sahara：QFIL 加载 firehose\read-gpts-prearch.xml
#    -> 产出 session\prearch-lun0..5-gpt-primary.bin
# 4) GPT 比对（应逐行输出 GPT_BASELINE_MATCH LUN=0..5；末尾 CRC 8584A79D/224FD5BF）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-TB321FUGpt.ps1
# 5) QFIL 加载 firehose\program-userdata-raw-20g-arch.xml（单条 program）
#    LUN0/4096B/start=3613096/count=5242880/end=8855975/sparse=false
# 6) QFIL 加载 firehose\read-userdata-10point.xml（10 点）
# 7) 回读校验（应输出 MATCHED=10/10 + USERDATA_READBACK_VERIFY=PASS）
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Readback.ps1
# 8) Fastboot 处理 GRUB/boot/槽位（boot 不重刷，SHA 45f923bc…；禁 fastboot 写 userdata）
```

成功标志：`BUNDLE_VERIFY=PASS FILES=19` → `PREPARE_IMAGES=PASS` → `GPT_BASELINE_MATCH LUN=0..5` → 写入 OK → `MATCHED=10/10`。

## P7：首启救援/网络（平板端 SSH/串口/蓝牙）

```bash
# 0) 首启立即收集证据（任一终端可用即执行）
tb321fu-support-bundle                                   # -> ~/Downloads/tb321fu-support-<ts>.tar.zst
uname -a; cat /etc/os-release; systemctl --failed; systemd-analyze
findmnt /; lsblk -f; cat /proc/cmdline
ip -br link; ip -br address; lsmod

# 1) USB NCM：电脑出现 usb0 网卡，ping 10.77.0.1 && ssh fuhao@10.77.0.1
# 2) USB ACM：串口 ttyGS0 登录（普通用户；root 拒绝）
# 3) BT NAP：配对后 PAN 连接，ping 10.78.0.1 && ssh fuhao@10.78.0.1
#    至少两条 PASS；分别记录，不得以一条掩盖其他失败
systemctl status tb321fu-usb-rescue.service tb321fu-bt-nap.service
systemctl status NetworkManager bluetooth nftables sshd
ls /sys/class/udc; ip -details link show usb0 bnep0

# 4) Wi-Fi：扫描/连接/DHCP/重连/关屏恢复
nmcli device wifi list
nmcli device wifi connect "<SSID>" password "<PASS>"
ip -br address show wlp1s0
nmcli connection up "<CONN>"          # 重连测试
# 固件证据：/usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin（202148B）
```

成功标志：support bundle 落盘 + 至少两条救援通道 PASS + Wi-Fi 连接/DHCP/重连 OK。

## P8：桌面与硬件验收（平板端）

```bash
# 显示/输入
niri msg outputs            # DSI-1 1600x2560@120、transform 270
niri msg input-devices      # 触控映射
# 音频（PipeWire）
wpctl status; pactl list short sinks
aplay -l; arecord -l        # 内置扬声器/耳机/麦克风
# 电源/亮度/震动
upower -d; brightnessctl info
ls /sys/class/leds          # 震动/haptics
# 存储扩容（首启应自动扩容，勿手动格式化）
systemctl status tb321fu-grow-rootfs.service
df -h /                      # 期望接近物理 userdata 456.8G
# 稳定项（suspend 不做）
systemctl --failed; journalctl -b -p warning
```

成功标志：显示 120Hz + 触控正确 + 音频三态 + 亮度/电量遥测 + 扩容到 ~456G + `systemctl --failed` 为空。

## 验收记录

每项写 `PASS`/`FAIL`/`NOT TESTED` + 命令/日志路径。把 support bundle、journal、niri outputs 落盘到
`y700-linux/live/EXP-20260802-001/`，再回填 EXP-20260802-001 的"实测"段。失败即回基线（Kubuntu 26.04 +
原版 GRUB `6C1C06A6…` + boot_a），不掩盖。

## 红线（每步都有效）

- 禁 `fastboot flash/format userdata`；禁 stock XML；仅 programmer `8CFC8C43…`
- 禁写 persist/modemst/fsg/proinfo/lenovolock/xbl；不再次解锁；首刷不测 suspend
- 9008 侧 GPT 与 known-gpt 六份基线比对，任何不一致立即停止
- 只推 fork，绝不推 origin

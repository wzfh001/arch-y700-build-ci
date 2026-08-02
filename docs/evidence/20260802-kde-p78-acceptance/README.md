# 2026-08-02 KDE bundle P7/P8 实机验收证据

- Bundle：`TB321FU-tablet-kde-run-30736975180`（用户 Windows QFIL 刷入 2026-08-02）
- 设备：`192.168.0.156`（fuhao@fuhao，kernel `7.1.1-g5df8e852ea72`）
- 核心结论：Wi-Fi / KDE Wayland / 显示 1600x2560@120 Rotated270 / 触控 / 亮度 / 电池 / 音频 VERIFIED；
  USB ACM/NCM + BT NAP PARTIAL；关屏重连 + 耳机实音 UNTESTED（用户物理步骤）。
- 重要修复：WirePlumber `use-acp=false`（否则 UCM 设备不暴露 profile，音频无声），
  已回填 `scripts/ci/build-arch-rootfs-image.sh`；3 个失败服务（nftables/两个 wait-online）已 disable。

## 文件
- `ACCEPTANCE-REPORT.md` — P7/P8 逐项结论
- `AUDIO-FIX-EVIDENCE.md` — 音频根因与修复证据
- `SERVICE-FIX-EVIDENCE.md` — 3 个失败服务处置
- `acceptance-snapshot.txt` — 实机快照（system/services/display/audio/battery/input/wifi/ucm）
- `tb321fu-support-20260802T091545Z.tar.zst` — 设备 support bundle（44 文件，SHA b09f607d…f5590）

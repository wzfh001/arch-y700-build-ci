# 2026-08-02 KDE bundle P7/P8 实机验收证据

- Bundle：`TB321FU-tablet-kde-run-30736975180`（用户 Windows QFIL 刷入 2026-08-02）
- 设备：`192.168.0.156`（fuhao@fuhao，kernel `7.1.1-g5df8e852ea72`）
- 核心结论：Wi-Fi / KDE Wayland / 显示 1600x2560@120 Rotated270 / 触控 / 亮度 / 电池 / 音频 VERIFIED；
  **BT NAP 协调器已实机 VERIFIED（bnep0 up `10.78.0.1/24`，NM connection activated，2026-08-02 18:57，根因=缺 `dnsmasq`）**；
  USB ACM/NCM PARTIAL（需物理 Type-C partner）；关屏重连 + 耳机实音 UNTESTED（用户物理步骤）。
- 重要修复：
  - WirePlumber `use-acp=false`（否则 UCM 设备不暴露 profile，音频无声），已回填 `scripts/ci/build-arch-rootfs-image.sh`；
  - 3 个失败服务（nftables/两个 wait-online）已 disable；
  - **BT NAP 修复**：`dnsmasq` 加入 base 包（NetworkManager `shared` 依赖它做 DHCP/DNS）；
  - **USB 协调器噪音修复**：`write_if_changed` 读 sysfs 去 NUL（消除每 2s 的 journal null-byte 警告）。
  以上均已在实机应用并回填仓库（commit 见 git log）。

## 文件
- `ACCEPTANCE-REPORT.md` — P7/P8 逐项结论
- `AUDIO-FIX-EVIDENCE.md` — 音频根因与修复证据
- `SERVICE-FIX-EVIDENCE.md` — 3 个失败服务处置
- `acceptance-snapshot.txt` — 实机快照（system/services/display/audio/battery/input/wifi/ucm）
- `tb321fu-support-20260802T091545Z.tar.zst` — 设备 support bundle（44 文件，SHA 11c29ff5…e495ec）

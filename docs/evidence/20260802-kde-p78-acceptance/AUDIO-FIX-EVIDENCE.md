# 音频修复证据（2026-08-02）

## 问题
WirePlumber 默认 ACP 后端（`api.alsa.use-acp=true`）无法把 UCM 设备映射成 profile，
只枚举出 `off` / `pro-audio` 两个 profile，且默认停在 `off` → 无任何 sink 可用（仅 auto_null 虚拟输出）。

## 根因
`scripts/ci/build-arch-rootfs-image.sh` 写死 `api.alsa.use-acp = true`。
ACP 是 generic 枚举器，不识别本卡 UCM 的 Speaker/Headphones 设备路由。

## 修复
`/etc/wireplumber/wireplumber.conf.d/51-y700-alsa-auto.conf`：
- `api.alsa.use-acp = false`
- `api.alsa.use-ucm = true`（保持）
- 移除 `api.acp.auto-profile` / `api.acp.auto-port`

重启 wireplumber 后：sink `内置音频`（alsa_output.platform-sound.playback.0.0）出现。

## 验证
- `wpctl status`：Sinks: * 55. 内置音频 [vol: 1.00]；Sources: * 54. 内置音频 (MultiMedia3 Capture)
- `pw-play /usr/share/sounds/alsa/Front_Center.wav` → rc=0
- UCM Speaker 路由激活：`aw882xx_rx_switch=Enable`、`aw_dev_0_switch=Enable`、`SEC_TDM_RX_0 ... Front Left on`
- `pw-record /tmp/mic-test.wav` → 593,964 字节（麦克风数据流正常）
- 音量 0.8↔1.0 往返验证

## 已知 trade-off
use-acp=false 下 sink 命名为 raw-PCM 风格（`playback.0.0`），
`tb321fu-headset-route-reconcile.lua` 匹配的 `HiFi__Speaker__sink` 名字不再出现 → reconcile 为 no-op。
耳机热插拔仍靠 UCM jack 事件自动切换（Headphones 与 Speaker 为 ConflictingDevice）。
后续如需恢复 reconcile，可给 UCM node 加别名或改脚本兼容两种命名。

## 回滚
恢复 `51-y700-alsa-auto.conf` 为 use-acp=true（设备上备份：`51-y700-alsa-auto.conf.bak-20260802`），
或从仓库历史恢复 build 脚本。

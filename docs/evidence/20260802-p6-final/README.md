# P6 执行链最终就绪核查 + bundle 修复（2026-08-02）

status: VERIFIED（离线静态核验；尚未执行破坏性刷写）
对象: run 29966711103 Firehose bundle
位置: builds/flash-bundles/TB321FU-tablet-niri-run-29966711103/

## 本次发现并修复的真实缺陷

1. **BUNDLE-SHA256SUMS.txt 自引用行永远不匹配**
   - 原文件含自身行（`BUNDLE-SHA256SUMS.txt d84521e2…`），而文件内容包含自身哈希 → 不存在不动点，任何内容都无法让该行成立。
   - Windows 端 `Verify-Bundle.ps1` 会校验每一行（含自引用行）→ 原包第 2 步**必然失败**。
   - 修复：从 BUMS 移除自引用行；`Verify-Bundle.ps1` 增加防御性跳过自身行（SKIP_SELF）。
2. **README 恢复边界陈旧**
   - 原写"当前设备运行 Kubuntu 26.04 @ 192.168.0.146"，与 2026-08-02 实机（作者原版 Arch @ 192.168.0.220）不符。
   - 已改为当前真实状态（作者原版 Arch，刷写覆盖其 userdata 前 20 GiB，Kubuntu 为历史回退基线 2026-07-21）。

## 修复后最终核验（19 成员）

| 项 | 值 | 结果 |
|---|---|---|
| BUNDLE-SHA256SUMS 全量 | 19 成员（含脚本），无自引用 | **19/19 PASS（OK=19 BAD=0）** |
| rootfs.img.7z | `0d6c7f29…` | PASS |
| grub-fat.img.7z | `5d6b58c1…` | PASS |
| boot.img.7z | `a9c2e176…` | PASS |
| program XML | LUN0/4096B/start=3613096/count=5242880/end=8855975/sparse=false/单条 | PASS |
| read-gpts-prearch | 6 LUN 只读重读（prearch-lun0..5） | PASS |
| read-userdata-10point | 10 点（00/02/04/06/08/10/12/14/16/18 GiB，每点 64 扇区） | PASS |
| EXPECTED-READBACK tsv | header + 10 行 | PASS |
| Verify-TB321FUGpt | 6 LUN SHA 基线比对 + LUN0 CRC 8584A79D/224FD5BF + userdata 边界 3613096..123365370 + 写入范围不超界 | PASS（静态审阅） |
| Prepare-Images | 3 镜像 7z 解压 + size/SHA 校验 + 复制 session/known-gpt/scripts | PASS（静态审阅） |
| Verify-Readback | Import-Csv + 10 行 + 262144B/行 + MATCHED=10/10 | PASS（静态审阅） |

## P6 单命令执行链（放行后按此顺序）

```text
1. powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Bundle.ps1
   -> BUNDLE_VERIFY=PASS FILES=19
2. powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Prepare-Images.ps1
   -> PREPARE_IMAGES=PASS（C:\Users\Admin\Documents\001\Y700_Arch_tablet_niri_run_29966711103）
3. 设备进入 9008/Sahara；QFIL 加载 firehose\read-gpts-prearch.xml
   -> 产出 prearch-lun0..5-gpt-primary.bin
4. powershell .\scripts\Verify-TB321FUGpt.ps1
   -> GPT_BASELINE_MATCH LUN=0..5 + LUN0 CRC 8584A79D/224FD5BF + userdata 3613096..123365370
5. QFIL 加载 firehose\program-userdata-raw-20g-arch.xml（LUN0/4096/start=3613096/count=5242880/sparse=false）
   -> 写入成功
6. QFIL 加载 firehose\read-userdata-10point.xml（10 点）
   -> 产出 readback-*.bin（每点 262144B）
7. powershell .\scripts\Verify-Readback.ps1
   -> MATCHED=10/10
8. fastboot（如 QFIL 未自动）：处理 GRUB/boot/槽位（boot 不重刷，45f923bc…）
9. 首启：support bundle（tb321fu-support-bundle）落盘 + 救援通道验收（ACM/NCM/NAP）
```

## 红线（放行后仍须遵守）

- 绝不 fastboot 写 20G userdata；绝不复用旧 run 29690572889 身份/XML/哈希
- 仅 Windows 官方 programmer SHA `8CFC8C43…`；绝不写 persist/modemst/fsg/proinfo/lenovolock/xbl
- 刷写前必须 9008 侧重读 GPT（步骤 3-4）并与 known-gpt 六份基线比对；任何不一致立即停止
- 只推 fork；origin 永不 push

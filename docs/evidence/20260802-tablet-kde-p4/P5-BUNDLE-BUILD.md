# tablet-kde P5 bundle 制作（2026-08-02 预置模板）

> CI run `30730513005`（`codex/tablet-kde-20260802` @ `f083e42`）P4 VERIFIED 后执行。
> 复用已验证 GPT 数值：userdata LBA 3613096..123365370，
> program XML start=3613096/count=5242880/LUN0/4096/sparse=false。
> 所有哈希/尺寸在 CI 产物下载后填入，禁止猜值。

## 输入

| 项 | 来源 |
|---|---|
| 主 ZIP | `gh run download 30730513005`（预期 ~3.8 GiB） |
| rootfs.img.7z / grub.img.7z / boot.img.7z | 主 ZIP 内（`SHA256SUMS` 交叉校验） |
| known-gpt LUN0-5 | 旧 bundle `TB321FU-tablet-niri-run-29966711103/known-gpt/`（复用，实机 GPT 已验证） |
| firehose XML（program/read-gpts/read-userdata） | 旧 bundle 复用（program-userdata-raw-20g-arch.xml 已验证） |

## 步骤

1. `mkdir -p builds/flash-bundles/TB321FU-tablet-kde-run-30730513005/{images,firehose,known-gpt,scripts,readback-expect}`
2. 复制主 ZIP 内 3 个 7z 到 `images/`，`7z t` 验证
3. 解压 rootfs.img.7z → raw，`e2fsck -fn` + `sha256sum`（记录 raw SHA）
4. 复制旧 bundle 的 `known-gpt/*.bin`、`firehose/*.xml`、`EXPECTED-READBACK-SHA256.tsv`
5. 按新 raw SHA 重新生成 10 点回读期望（offset=3613096+，每点 4096 块）
6. 写 `ARTIFACT-IDENTITY.txt`（run id、commit、output_prefix、raw SHA）
7. 从旧 `scripts/` 复制 PS 脚本，替换 3 处 run 前缀：
   - `Prepare-Images.ps1` 的 `$WorkRoot`（`Y700_Arch_tablet_kde_run_30730513005`）
   - `archives` 数组的 rootfs/grub 7z 文件名
   - `imageSpecs` 的 `Path`/`Size`/`Sha256`
8. 生成 `BUNDLE-SHA256SUMS.txt`（自引用行按旧 bundle 修复方式排除；PS 脚本防御性跳过自身）
9. `sha256sum -c BUNDLE-SHA256SUMS.txt` 19/19（或实际成员数）PASS

## 回读验证（Windows QFIL）

- `Verify-Bundle.ps1` → `Prepare-Images.ps1` → QFIL 刷写 → `Verify-Readback.ps1` 10/10
- `Verify-TB321FUGpt.ps1` 确认 6 LUN GPT 与 known-gpt 一致（只读重读，不写）

## 关键红线

- **绝不 fastboot 写 20G userdata**（Fastboot sparse 漏尾 bug 已确认）
- 刷前必须 9008 只读重读 GPT 与 known-gpt 比对
- bundle 成员哈希与 ARTIFACT-IDENTITY 完全一致才可交付

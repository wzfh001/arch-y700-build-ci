# 40-arch-compat fragment：pacman sandbox 根因与修复（2026-08-02）

## 结论

作者（GUF296）内核 **缺少 `CONFIG_SECURITY_LANDLOCK`**，而 pacman 7.1.x
的 filesystem sandbox **直接依赖 Landlock syscall**（`landlock_create_ruleset` /
`add_rule` / `restrict_self`）。设备上之前用 `DisableSandboxFilesystem` 绕过，
这不是干净的长期方案。修复 = 新 fragment `40-arch-compat.config`。

## 证据链

1. **pacman 源码**（gitlab.archlinux.org/pacman/pacman，2026-08-02 拉取）：
   - `lib/libalpm/sandbox_fs.c` 调 `landlock_create_ruleset()` 等三个 syscall，
     失败即 `_alpm_log(ERROR, "restricting filesystem access failed ...")`；
   - `lib/libalpm/sandbox.c` 的 `alpm_sandbox_setup_child()` 在
     `disable_sandbox_filesystem == 0` 时执行 Landlock 限制。
2. **设备（192.168.0.156，KDE bundle run 30736975180）**：
   - `zcat /proc/config.gz | grep LANDLOCK` → `# CONFIG_SECURITY_LANDLOCK is not set`
   - `/sys/kernel/security/lsm` → `capability`（Landlock 未注册）
   - `/etc/pacman.conf` 第 39 行 = `DisableSandboxFilesystem`（绕过痕迹，
     journal 2026-08-02 18:57 有 `sed -i s/^#DisableSandboxFilesystem/...` 的 sudo 记录）
3. **ALARM 官方 `linux-aarch64` config**（7.1.5）：`CONFIG_SECURITY_LANDLOCK=y`、
   `CONFIG_BINFMT_MISC=y` —— Arch 官方内核两者都开。

## fragment 内容

```
CONFIG_SECURITY_LANDLOCK=y
CONFIG_BINFMT_MISC=y
```

- Landlock Kconfig：`depends on SECURITY`，`select SECURITY_NETWORK` + `select SECURITY_PATH`。
- 设备基线 `CONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,ipe,bpf"` **已含 landlock
  且排第一**，开开关后随 boot 自动注册，无需改 LSM 串。
- binfmt_misc：ALARM 官方开启；qemu-user/fakeroot 等 Arch 用户态工具链受益。

## 本地验证（merge_config + olddefconfig，2026-08-02）

- `scripts/kconfig/merge_config.sh -m`：两个目标符号正确翻转（`# not set` → `=y`）。
- `make ARCH=arm64 olddefconfig` 通过；最终生效：
  `CONFIG_SECURITY_LANDLOCK=y`、`CONFIG_SECURITY_NETWORK=y`、
  `CONFIG_SECURITY_PATH=y`、`CONFIG_BINFMT_MISC=y`。
- 除工具链探测噪声（本地 GCC 16.1 vs CI 13.3 的 CC_VERSION_TEXT 等）外，目标符号共 4 个，
  其余与基线一致。

## 上机验证计划（等用户放行）

1. 触发 CI `build-kernel.yml`（`build_config=fragment`，`fragments=40-arch-compat`）。
2. 检查产物 `kernel.config`：目标 4 符号在、其余与基线一致。
3. 设备（或下个 bundle）替换 Image/DTB/modules 后重启：
   - `/sys/kernel/security/lsm` 应含 `landlock`；
   - 把 `/etc/pacman.conf` 的 `DisableSandboxFilesystem` 恢复注释，`pacman -Sy` 应正常；
   - 无回归（Wi-Fi / 显示 / 触摸 / 音频）。

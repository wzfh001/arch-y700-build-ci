# tablet-kde P7/P8 硬件验收检查单（2026-08-02 预置）

> 在 P6 Windows QFIL 刷写完成后执行。每项必须实测并留 journal / 命令输出证据；
> 状态词只许 VERIFIED/PARTIAL/BROKEN/UNTESTED/BLOCKED/UNKNOWN。
> 不要在证据缺失时把「配置存在」当成「硬件成功」。

## P7 首启 / 救援 / 网络

- [ ] 首启进入 SDDM（KDE Plasma 登录界面），不是黑屏/回退 console
- [ ] 自动登录 fuhao（SDDM_AUTOLOGIN=1），进入 Plasma Wayland 会话
- [ ] `systemctl --failed` 为 0（允许已处理的已知单元）
- [ ] USB 救援：`tb321fu-usb-rescue.service` 激活，`cdc-ncm` 出现 `usb0`/`10.77.0.1/24`，`cdc-acm` 出现 `ttyGS0`
- [ ] USB 主机侧可 `ssh fuhao@10.77.0.2`（或配置的地址）进入设备
- [ ] BT NAP：`tb321fu-bt-nap.service` 激活，`bnep0`/`10.78.0.1/24`，SSH 可用
- [ ] Wi-Fi：`wlp1s0` 出现，`ath12k` 加载 `board-2.bin`（202148B），可连 AP 并拿到 DHCP
- [ ] `firmware_class.path=/usr/lib/firmware/tb321fu` 生效（journal 无 firmware 加载失败）

## P8 桌面 / 日用硬件

- [ ] KDE 桌面正常渲染，无 GPU 崩溃（`kwin_wayland` 稳定，journal 无 compositor crash）
- [ ] **触控旋转**：平板竖放/横放时 `kwinoutputconfig.json` transform=Rotated270 生效，屏幕方向正确
- [ ] 触控输入与显示方向一致（触摸点映射正确）
- [ ] **虚拟键盘**：输入框聚焦时 Plasma 键盘自动弹出（kwinrc VirtualKeyboardEnabled）
- [ ] fcitx5 中文输入（pinyin）可用
- [ ] 音频：内置扬声器/耳机出声（wireplumber 路由），`aplay -l` 设备正常
- [ ] 蓝牙：可配对耳机/键鼠，A2DP 音频可用
- [ ] 摄像头（libcamera）`cam` 可列设备并出图（如适用）
- [ ] 电池/充电状态显示正常（upower）
- [ ] 亮度控制（KDE OSD）生效
- [ ] `sshd.service` 稳定，SSH 公钥登录可用
- [ ] 休眠/唤醒：`tb321fu-suspend-log` 记录正常，唤醒后 KDE 恢复

## 稳定观察（P9 前置）

- [ ] 连续使用 ≥ 24h 无 panic / 无 compositor 重启 / 无固件加载风暴
- [ ] `journalctl -b -1` 无 fatal 错误
- [ ] `tb321fu-support-bundle` 采集包可生成并脱敏

## 结论

- 全部 PASS → P7/P8 VERIFIED → P9 稳定观察 → 更新 `validation/<release>/hardware.yaml`
- 任一 FAIL → 记录复现步骤/日志/回滚路径，禁止标记完成

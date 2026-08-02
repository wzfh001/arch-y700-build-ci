# 失败服务修复证据（2026-08-02）

## 修复前（3 failed）
```
UNIT                                 LOAD   ACTIVE SUB    DESCRIPTION
● NetworkManager-wait-online.service   loaded failed failed Network Manager Wait Online
● nftables.service                     loaded failed failed Netfilter Tables
● systemd-networkd-wait-online.service loaded failed failed Wait for Network to be Online
```

## 根因与处置

| 服务 | 根因 | 处置 |
|---|---|---|
| nftables | 内核 `CONFIG_NF_TABLES is not set`（作者基线内核未编 nf_tables），`nft -f` netlink 不可用 → 必然失败 | `systemctl disable --now nftables`（无防火墙规则实际生效，禁用不引入风险；如需防火墙须内核启用 NF_TABLES） |
| NetworkManager-wait-online | `nm-online -s -q` 超时（Wi-Fi 场景典型良性失败） | `systemctl disable --now NetworkManager-wait-online` |
| systemd-networkd-wait-online | 平板无有线口，`en.network`/`eth.network` 只匹配有线，等待不存在的链路 | `systemctl disable --now systemd-networkd-wait-online` |

## 修复后
```
$ systemctl --failed --no-pager
  UNIT LOAD ACTIVE SUB DESCRIPTION
0 loaded units listed.
$ systemctl is-enabled nftables NetworkManager-wait-online systemd-networkd-wait-online
disabled / disabled / disabled
```

## 回滚
`systemctl enable --now nftables NetworkManager-wait-online systemd-networkd-wait-online`
（nftables 需内核支持 nf_tables 才有意义；无支持时保持禁用）

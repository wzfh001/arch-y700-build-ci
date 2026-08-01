# Recovery

The device currently runs the **verified Kubuntu 26.04 ARM64 rollback baseline**
(kernel `7.1.1-g5df8e852ea72`). Treat it as the recovery target.

## Verified recovery facts

- Fastboot can query device state, and can write the verified **96 MiB
  `boot.img`** and **256 MiB `super`**.
- Fastboot must **not** write the 20 GiB `userdata` (silent tail-drop bug).
- The final verified raw write used the official TB321FU/SM8650 Windows
  Firehose programmer, LUN 0, 4096-byte sectors, `start=3613096`,
  `count=5242880`, `end=8855975`, `sparse=false`.
- Those GPT numbers belong to the device at that time; re-read the GPT
  read-only before any future write.
- WCN7850 firmware baseline (the only hardware-verified working Wi-Fi firmware):
  `hw2.0/board-2.bin`, 202148 bytes, on the Kubuntu system.

## Rescue channels (target, not yet proven on Arch)

The Arch candidates intend to provide three independent rescue channels.
Only the Kubuntu baseline is currently verified on hardware:

1. **USB ACM** — serial console over USB gadget
2. **USB NCM** — network over USB gadget
3. **Bluetooth NAP** — network over Bluetooth

Historical Arch run (`29709555909`) showed `/sys/class/udc` empty and `port0`
host; the coordinators were added afterward and remain unflashed/UNTESTED.

## Rollback

- Kubuntu rollback baseline is intact on the device; do not disturb it.
- Kernel rollback: `git checkout <commit>` / restore `baseline-*` compatible
  unit (Image/DTB/modules) / official boot template.
- Full device rollback follows the main project's recovery discipline
  (recovery image / Fastboot / 9008) and is executed by the main-project
  engineer, never unilaterally by the kernel role.

## On-device quick checks (Kubuntu baseline)

```bash
uname -r                              # expect 7.1.1-g5df8e852ea72
nmcli device                          # wlp1s0 connected
systemctl --failed                    # expect empty
ls -l /lib/firmware/qcom/sm8650/lenovo-Y700-TB321FU/   # board-2.bin 202148 bytes
```

# TB321FU risk register

Last reviewed: 2026-07-21

| ID | Severity | Trigger | Impact | Prevention gate | Recovery/evidence | State |
|---|---|---|---|---|---|---|
| R-001 | P0 | Fastboot writes 20 GiB userdata | Silent incomplete rootfs | Permanent command prohibition | Windows Firehose + ten-point readback | OPEN CONTROL |
| R-002 | P0 | Wrong GPT/LUN/range reused | Destructive write outside target | Re-read GPT; bind bundle to device/run | Stop before write; preserve raw logs | OPEN CONTROL |
| R-003 | P0 | No rescue path after flash | No diagnosis or safe iteration | P1 and P7 rescue gates | Local support bundle; ACM/NCM/NAP | OPEN |
| R-004 | P0 | Generic WCN7850 firmware wins | Wi-Fi unavailable | Exact hashes, native package, independent path | Final-raw ownership/content audit | OPEN |
| R-005 | P1 | USB service waits forever | Delayed/blocked boot | Persistent non-blocking coordinator | Journal + service timeout tests | OPEN |
| R-006 | P1 | UDC/device role never appears | ACM/NCM unavailable | Type-C role and UDC state machine | Support bundle Type-C/UDC snapshot | OPEN |
| R-007 | P1 | NAP profile never activates | Bluetooth rescue unavailable | Dedicated activation/retry service | SDP, `bnep0`, DHCP, SSH evidence | OPEN |
| R-008 | P1 | Support bundle leaks secrets | Credential/privacy exposure | Redaction fixtures and secret scan | Delete unsafe bundle; rotate exposed secret | OPEN |
| R-009 | P1 | Rolling update breaks payload ABI | Boot/hardware regression | Freeze compatibility unit; test before thaw | Roll back known image/config snapshot | OPEN |
| R-010 | P1 | Suspend resumes to lit black screen | Loss of local UI | No automatic suspend; rescue first | Pre/post logs and forced-reboot plan | DEFERRED |

Risk updates must cite an experiment ID or evidence path. Closing a risk means
the prevention and recovery controls were tested, not merely implemented.

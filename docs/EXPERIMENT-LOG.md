# TB321FU experiment and failure log

This is an append-only evidence index. Do not rewrite a failed result into a
pass. A retry must reference the earlier experiment ID and identify the new
evidence or changed variable.

## Required record

```text
ID:
Time and timezone:
Operator:
Question or hypothesis:
Single primary variable:
Device identity (non-sensitive suffix only):
Branch / commit / workflow run / profile:
rootfs / GRUB / boot / DTB SHA-256:
GPT summary / active slot:
Exact procedure:
Expected result:
Observed result:
Raw evidence paths:
Result: PASS | FAIL | NOT TESTED
Recovery action:
Next hypothesis:
References to earlier experiment IDs:
```

## Historical failures

### EXP-HIST-001 — Fastboot raw userdata tail omission

- Result: `FAIL`
- Primary variable: Fastboot writing the 20 GiB raw ext4 userdata image.
- Observed: Fastboot returned complete `OKAY`, but readback windows in the image
  tail were zero or mismatched.
- Recovery: matching Windows TB321FU/SM8650 Firehose raw write followed by
  0–18 GiB ten-point `10/10` readback.
- Permanent decision: never use Fastboot for the 20 GiB userdata image.
- Evidence: external handoff and archived 2026-07-19 evidence bundle.

### EXP-HIST-002 — First Arch image lost its only practical network path

- Result: `FAIL`
- Primary variable: first `tablet-niri` image on hardware.
- Observed: Wi-Fi did not work and no repeatable USB/Bluetooth SSH rescue path
  existed; complete post-flash logs were not captured.
- Permanent decision: rescue and automatic evidence are release gates, not
  optional follow-up features.

### EXP-HIST-003 — Rescue image configuration did not create runtime rescue

- Result: `FAIL`
- Build identity: run `29709555909`, commit `4edf3a4`.
- Observed: Wi-Fi remained broken; host enumerated no ACM/NCM; device UDC class
  was empty; Bluetooth NAP was not proved.
- New evidence: final raw retained generic WCN7850 firmware; ConfigFS link and
  USB role/UDC are separate issues; NAP lacked an activation coordinator.
- Next work: P1 rescue/observability, then P2 device firmware packaging.

## Development validation incidents

### DEV-20260721-001 — Governance test assumed Markdown stayed on one line

- Result: `FAIL`, then corrected and rerun to `PASS`.
- Primary variable: new `test-project-governance.sh` assertion.
- Observed: the first assertion searched for a phrase split across two Markdown
  lines and reported a false failure.
- Correction: assert the commit identity and fix boundary independently.
- Permanent decision: repository validation commands run with fail-fast shell
  behavior so a failed check cannot be hidden by later successful commands.

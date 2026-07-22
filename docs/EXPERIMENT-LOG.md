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

### DEV-20260721-002 — Profile test assumed every executable was Bash

- Result: `FAIL`, corrected before commit.
- Primary variable: adding the Python support-bundle redactor to the profile.
- Observed: the generic executable loop passed the Python file to `bash -n`.
- Correction: Bash files remain in the shell loop; the redactor is checked with
  `python3 -m py_compile` and an isolated bytecode cache.
- Permanent decision: validate overlay programs with their declared
  interpreter instead of inferring one interpreter from executable mode.

### DEV-20260722-001 — USB coordinator lost its executable mode

- Result: `FAIL`; the immediate retry passed but is not treated as an isolated
  mode-only experiment.
- Primary variable: the uncommitted USB coordinator file mode.
- Observed: `test-usb-rescue-coordinator.sh` stopped immediately with
  `coordinator is not executable`; Git reported mode `0644`.
- Evidence: local source test run on 2026-07-22 before any corrective retry.
- Correction: mode `0755` was restored. Additional coordinator behavior had
  already changed before the retry, so the retry cannot prove a single
  mode-only variable and is not used as release evidence by itself.
- Permanent decision: check executable modes before behavior edits and record
  the complete coordinator candidate under a new source experiment.

## Source validation results

### SRC-20260721-001 — Offline support bundle and redaction

- Result: `PASS` at source-test scope; TB321FU hardware remains `UNTESTED`.
- Commit: `3a095ed`.
- Primary variable: new support collector and Python redactor.
- Evidence: fixture credentials were removed; useful ath12k evidence remained;
  an actual local archive was created at mode `0600`, extracted, and every file
  passed its included SHA-256 manifest.
- Tests: `SUPPORT_BUNDLE=PASS`, `TABLET_NIRI_PROFILE=PASS`, actionlint and
  workflow semantics PASS.
- Boundary: this does not prove privileged journal access, niri session access,
  or redaction coverage on the tablet's real logs.

### SRC-20260722-001 — Persistent USB rescue coordinator

- Result: `PASS` at source-test scope; TB321FU ACM/NCM remain `UNTESTED` for
  this candidate.
- Primary variable: replace the blocking USB oneshot with one persistent
  role/UDC/ConfigFS/network/serial state coordinator. Role selection, binding,
  hotplug recovery, and cleanup are coupled parts of that state transition and
  cannot be tested as independent deployed services.
- Evidence: `USB_RESCUE_COORDINATOR=PASS` after tests for missing UDC,
  role request, correct ConfigFS links, UDC removal/reappearance, ACM/NCM
  restoration, NetworkManager fallback, serial-getty failure, and clean stop.
- Boundary: fake sysfs/configfs and commands do not prove that TB321FU `port0`
  can enter device role or that a real UDC will appear.

### SRC-20260722-002 — Bluetooth NAP activation coordinator

- Result: `PASS` at source-test scope; TB321FU NAP remains `UNTESTED` for this
  candidate.
- Commit: `406e0c1`; CI integration: `eaf0650`.
- Primary variable: add a non-blocking owner for the existing NetworkManager
  NAP profile, including adapter readiness, power-on, bounded activation retry,
  status evidence, and cleanup.
- Evidence: `BT_NAP_COORDINATOR=PASS` covers one failed activation followed by
  a successful retry, NAP UUID reporting, missing adapter, cleanup, and a hung
  `bluetoothctl` command.
- Boundary: simulated BlueZ/NetworkManager output does not prove SDP
  advertisement, `bnep0`, DHCP, or SSH on TB321FU.

### SRC-20260722-003 — P0/P1 complete offline source gate

- Result: `PASS` at source-test scope on commit `eaf0650` plus the documented
  P0 governance files from `c45ad2a`.
- Primary question: does the complete offline CI validation sequence accept the
  governance, redaction, USB, Bluetooth, payload, profile, package, signature,
  extraction, workflow, and release-safety controls together?
- Evidence: actionlint; workflow semantics/input/action/service checks; safe
  extraction; path boundaries; project governance; support bundle; USB rescue;
  Bluetooth NAP; payload policy; tablet profile; audio reconciliation; native
  package lifecycle; OpenPGP; pacman signatures; overlay boundary; publication
  regressions; and Issue-template YAML all returned PASS.
- Boundary: no network build, artifact audit, device access, write, or hardware
  acceptance was performed.

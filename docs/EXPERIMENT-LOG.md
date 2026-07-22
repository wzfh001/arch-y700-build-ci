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

### SRC-20260722-004 — Old rootfs compressed board file is not the Kubuntu board

- Result: `FAIL` for the hypothesis that the retained 33090-byte
  `board-2.bin.zst` can recover the Kubuntu-proven 202148-byte board file.
- Primary variable: read-only extraction and decompression of
  `/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin.zst` from the verified old
  run `29709555909` rootfs raw.
- Source raw identity: 20 GiB image with recorded SHA-256
  `3540513595fce48afcbabcca4ead3c8f5697496df215b5b592455c3f9762eef8`.
- Observed: the compressed member SHA-256 is
  `0713e03f82a343d01b009ec78ce926869555e1ebd9ebb0d47f31a19ffd52b22d`;
  decompression produced 1,897,968 bytes with SHA-256
  `7ce00dc04735053c12c8268c3e82004175f0f108abd93c76bab95544e9e48bf8`,
  not 202148 bytes.
- Evidence: the imported-payload manifest hash matched the extracted member and
  `zstd -t` passed, so corruption is not the explanation.
- Permanent decision: do not retry this compressed member or infer device
  firmware identity from its 33090-byte compressed size.
- Next hypothesis: obtain and verify the fixed device archive itself, or
  read-only copy/hash the 202148-byte file from the currently working Kubuntu
  installation with explicit network/device authorization.

### DEV-20260722-002 — Local archive audit assumed `dpkg-deb` was installed

- Result: `FAIL`, then corrected with a different read-only parser and rerun to
  `PASS`.
- Primary variable: the local command used to inspect the already downloaded,
  hash-verified device archive.
- Observed: the first audit stopped because this CachyOS host does not provide
  `dpkg-deb`; no archive member had been accepted and no package was installed.
- New evidence and correction: the `.deb` ar container was inspected with
  `ar`, its `data.tar.xz` member was streamed to `tar`, and the overlay package,
  six WCN7850 members, file sizes, and SHA-256 values were then verified.
- Permanent decision: local evidence scripts must not silently assume Debian
  package tools; use a declared parser and fail before interpreting content.

### DEV-20260722-003 — Wi-Fi staging fixture skipped production mode normalization

- Result: `FAIL`, then corrected and rerun to `PASS`.
- Primary variable: the source-test fixture used to call
  `install_tb321fu_wifi_firmware_package()` outside the complete build.
- Observed: Debian preserved the six firmware files as mode `0755`, so the
  package function correctly rejected the fixture as unsafe.
- New evidence and correction: production already normalizes imported system
  payload modes to `0644` before the package function. Only the isolated
  fixture was changed to reproduce that stage; the production permission gate
  was not relaxed.
- Permanent decision: isolated function tests must reproduce required upstream
  normalization rather than weakening the function under test.

### SRC-20260722-005 — P2 pinned WCN7850 native package source gate

- Result: `PASS` at source and fixed-archive fixture scope; TB321FU Wi-Fi and
  the final raw image remain `UNTESTED` until a new artifact is built.
- Primary variable: replace path-owner-based firmware discard with an exact,
  device-specific WCN7850 package and independent firmware search path.
- Fixed archive: `y700-device-debs-20260624-201420-compat1.tar.gz`, size
  `71142341`, SHA-256
  `047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04`.
- Fixed overlay package:
  `y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb`, SHA-256
  `9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc`.
- Evidence: all six WCN7850 files match
  `profiles/tablet-niri/wifi-firmware.sha256`; the Kubuntu-proven
  `board-2.bin` is 202148 bytes with SHA-256
  `c896bc7782e252aa915849d5c9c47d109ecfe9f0fc5650fe771f7ba8f8eb77fb`.
- Implementation: build pacman-owned `tb321fu-wifi-firmware`, install under
  `/usr/lib/firmware/tb321fu`, retain the generic Arch firmware under its
  original `linux-firmware-atheros` ownership, and add
  `firmware_class.path=/usr/lib/firmware/tb321fu` to the GRUB command line.
- Collision policy: an imported path already owned by Arch is now discarded
  only when type, content, and relevant metadata are identical; differing
  content is a hard failure and the source evidence is retained.
- Tests: `WIFI_FIRMWARE_ARCHIVE=PASS`, `WIFI_FIRMWARE_PACKAGE=PASS`,
  `ARCH_NATIVE_PACKAGE_LIFECYCLE=PASS`, `TABLET_NIRI_PROFILE=PASS`, and
  `WORKFLOW_SEMANTICS=PASS`.
- Boundary: only the next complete build can prove final-raw ownership,
  contents, package manifest, and bootargs; only P7 hardware testing can mark
  Wi-Fi `VERIFIED`.
- Commit identity: the commit containing this record and the P2 implementation
  is the authoritative source identity; its exact SHA is recorded in the
  external current handoff after commit creation.
- References: `SRC-20260722-004`, `DEV-20260722-002`,
  `DEV-20260722-003`.

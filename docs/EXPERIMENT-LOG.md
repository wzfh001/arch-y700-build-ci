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

### SRC-20260722-006 — Historical Arch Linux ARM snapshot endpoints are unavailable

- Result: `FAIL` for the hypothesis that an existing dated ALARM archive can
  replace the rolling pacman mirror.
- Primary variable: read-only availability checks for previously documented
  Arch Linux ARM archive endpoints.
- Observed: `archive.archlinuxarm.org` did not resolve. The historical Tardis
  archive returned a page stating that the archive was disabled on
  2026-06-02 and would be removed. The alternative archive hostname checked in
  the same probe also did not resolve.
- New evidence: the live `de3` mirror still serves current signed `core.db`,
  `extra.db`, packages, and detached package signatures, but it is rolling and
  cannot be treated as a dated snapshot.
- Permanent decision: do not repeat availability probes against the retired
  Tardis archive or claim that a fixed rootfs SHA also fixes later `pacman
  -Syu` inputs.
- Next hypothesis: create an immutable seed artifact containing the frozen
  repository databases, complete package transaction, signatures, hashes, and
  expected installed package set; consume it offline in a second run.

### DEV-20260722-004 — Read-only repository probe cleanup was rejected before execution

- Result: `FAIL` before command execution; no download or filesystem change
  occurred.
- Primary variable: an automatic recursive cleanup trap attached to a new
  `/tmp/tb321fu-p3-probe.*` directory.
- Observed: the local command safety layer rejected the command because it
  contained recursive removal syntax.
- Correction: create a new mode-0700 temporary probe directory without an
  automatic delete step. The repository database probe then completed.
- Permanent decision: evidence probes must not weaken cleanup safety checks;
  retained temporary evidence is preferable to broad deletion syntax.

### DEV-20260722-005 — Package-lock manifest mixed newline records with NUL sorting

- Result: `FAIL`, then corrected and rerun to `PASS`.
- Primary variable: the source fixture that creates canonical `SHA256SUMS` for
  a package-lock directory.
- Observed: `find -printf '%P\\n'` was piped to `sort -z`, so all pathnames were
  passed to `sha256sum` as one invalid argument.
- Correction: emit NUL-delimited paths with `-printf '%P\\0'` throughout the
  seed and fixture before `sort -z | xargs -0`.
- Permanent decision: every pathname pipeline must use one delimiter end to
  end; newline/NUL mixing is a hard test failure.

### DEV-20260722-006 — Unsafe-path glob rejected every valid lock member

- Result: `FAIL`, then corrected and rerun to `PASS`.
- Primary variable: the verifier's hostile-path rejection expression.
- Observed: a shell `case` pattern intended to reject dollar signs interacted
  with shell expansion and matched ordinary paths such as `LOCK-INFO.env`.
- Correction: iterate NUL-delimited absolute members, derive their relative
  names, and use explicit `[[ ... ]]` checks for empty, absolute, traversal,
  dollar, CR, and LF content.
- Permanent decision: hostile path checks use explicit predicates and a
  positive fixture; no compact glob is accepted without a valid-path test.

### SRC-20260722-007 — Two-stage pacman package-lock source mechanism

- Result: `PASS` at source/hostile-fixture scope; the package lock is still
  `UNSET`, so the P3 exit Gate is not complete.
- Primary variable: replace live `pacman -Syu` for `tablet-niri` with a seed
  artifact and a locked offline transaction.
- Implementation: one shared package request function feeds both workflows;
  the seed freezes `core.db`/`extra.db`, exact package files, detached
  signatures, package SHA-256 values, expected final `pacman -Q`, seed run, and
  seed commit. The build pins the manifest SHA and immutable run/artifact
  identity, verifies every member, mounts a `file://` repository, and runs both
  pacman transactions under `unshare --net`.
- Fail-closed behavior: `tablet-niri` refuses to build without
  `profiles/tablet-niri/pacman-lock.env`, a 64-hex manifest pin, matching fixed
  rootfs SHA, matching request list, valid package signatures, and an exact
  post-transaction installed package set.
- Tests: `PACMAN_PACKAGE_LOCK_SOURCE=PASS`, hostile lock tampering rejected,
  the existing dispatch workflow passes actionlint and immutable-action checks, workflow
  semantics pass, and the complete existing offline validation sequence passes.
- Boundary: no seed workflow has run, no lock artifact has been pinned, and no
  rootfs/GRUB build has consumed the mechanism. The next action is a lock-only
  seed run; it is not a firmware candidate or Release.
- References: `SRC-20260722-006`, `DEV-20260722-004`,
  `DEV-20260722-005`, `DEV-20260722-006`.

### DEV-20260722-007 — New lock-only workflow path could not be dispatched

- Result: `FAIL` before any runner started; no artifact, rootfs, release, or
  device operation occurred.
- Primary variable: dispatching the newly added
  `seed-pacman-package-lock.yml` on the feature branch.
- Observed: GitHub returned HTTP 404 because a `workflow_dispatch` workflow
  file must already exist on the repository default branch, even when the
  requested ref contains that new file.
- Correction: move the lock-only job behind a boolean input in the existing
  `build-rootfs-and-grub.yml` path, which already exists on the default branch;
  the regular build job is explicitly skipped in seed-only mode.
- Permanent decision: do not retry dispatching a new workflow path that is
  absent from the default branch. Branch-only experiments must use an existing
  dispatch workflow identity or wait for an intentional default-branch merge.

### DEV-20260722-008 — Workflow input limit rejected a new seed boolean

- Result: `FAIL`, then corrected and rerun to `PASS`.
- Primary variable: adding `pacman_lock_seed_only` as an eleventh
  `workflow_dispatch` input.
- Observed: actionlint rejected the workflow because GitHub permits at most ten
  inputs and the pre-existing build workflow already used all ten.
- Correction: reserve the exact `release_tag=__PACMAN_LOCK_SEED__` sentinel for
  the lock-only job; the normal build job is mutually exclusive with that
  value, and release publication remains impossible in seed mode.
- Permanent decision: preserve the platform input limit and use an explicit,
  validated mode sentinel rather than silently dropping an existing input.

### CI-20260722-001 — First lock seed stopped at remote shell validation

- Result: `FAIL`; seed/download/upload steps did not run.
- Workflow run: `29918348833`, commit `9d6e8a5`, reserved lock-only mode.
- Primary variable: the workflow shell spelling for an empty `PACKAGE_LIST`
  environment assignment.
- Observed: the remote actionlint shellcheck integration reported SC1007 for
  `PACKAGE_LIST= \\` and stopped in `Validate lock source`. The normal build job
  was skipped as intended; no rootfs, GRUB, Release, or firmware artifact was
  created.
- Correction: spell the empty value as `PACKAGE_LIST=''` in both lock-related
  workflow blocks and add a source regression that rejects the ambiguous form.
- Retry authorization: a new commit changes the one failed variable; the next
  seed run must reference this experiment and is not an unchanged retry.

### CI-20260722-002 — Seed chroot root was not a mount point

- Result: `FAIL`; no lock artifact was uploaded and the normal build job stayed
  skipped.
- Workflow run: `29918507952`, commit `3a0b0a8`, retry of
  `CI-20260722-001` with the SC1007 variable fixed.
- Primary variable: the seed extracted the fixed rootfs into an ordinary
  directory instead of a filesystem mount point.
- Observed: after downloading and verifying the 780 MiB fixed rootfs and
  freezing the repository databases, pacman stopped before reinstalling
  `archlinuxarm-keyring` with `could not determine root mount point /` and
  `not enough free disk space`. A remaining GPG agent also kept the `/dev`
  bind busy during best-effort cleanup; the safety guard correctly refused to
  delete the mounted work tree.
- Correction: self-bind the rootfs directory before entering the chroot so it
  has an explicit mountinfo entry; stop both GPG contexts before unmounting,
  then unmount child trees and the root mount in order.
- Retry authorization: the next seed changes the root mount and cleanup state;
  do not repeat run `29918507952` unchanged.

### CI-20260722-003 — Seed allowlist omitted the ALARM-specific repositories

- Result: `FAIL`; no lock artifact was uploaded and the normal build job stayed
  skipped.
- Workflow run: `29918760462`, commit `36a7ea1`, retry of
  `CI-20260722-002` with an explicit root mount.
- Primary variable: the seed allowed only `core` and `extra` package URLs and
  databases.
- Observed: rootfs verification, keyring initialization, repository sync and
  offline keyring installation passed. The resolved full transaction then
  required `alarm/libpisp-1.5.0-1-aarch64.pkg.tar.xz`; the URL allowlist
  correctly stopped because `alarm` was unmodeled. The fixed rootfs pacman
  configuration also synchronizes `aur`.
- Correction: freeze and verify all four configured signed repositories:
  `core`, `extra`, `alarm`, and `aur`; accept package URLs only from those four
  pinned paths. Cleanup now uses the common deepest-first mount traversal.
- Retry authorization: the next seed changes the repository model and cleanup
  traversal; do not repeat run `29918760462` unchanged.

### CI-20260722-004 — GitHub artifact upload rejects epoch package filenames

- Result: `FAIL`; the seed transaction and lock verification completed, but no
  artifact was published.
- Workflow run: `29919009433`, commit `5124ba6`, reserved lock-only mode.
- Primary variable: upload the verified lock directory as individual artifact
  members using `actions/upload-artifact`.
- Observed: the action rejected
  `repo/aarch64/core/fakeroot-1:1.37.2-2-aarch64.pkg.tar.xz` because GitHub
  artifact paths cannot contain `:`. The package filename is valid and must be
  preserved because the epoch is part of pacman identity; renaming it would
  invalidate the repository transaction. The normal build job was skipped and
  no rootfs, GRUB, release, or device operation occurred.
- Raw evidence: GitHub job log for
  `https://github.com/wzfh001/arch-y700-build-ci/actions/runs/29919009433`.
- Correction: publish one deterministic tar archive of the verified lock
  directory (preserving package filenames), then safely extract and verify it
  in the consuming build job. Keep the manifest SHA and artifact/run identity
  bound to the extracted lock.
- Retry authorization: a new commit will change only the lock transport and
  consumer extraction path; do not repeat run `29919009433` unchanged.
- References: `CI-20260722-003`, `SRC-20260722-007`.

### DEV-20260722-009 — Bulk lock-test patch used stale context

- Result: `FAIL` before any file change, then corrected with a smaller patch.
- Primary variable: one bulk `apply_patch` operation against
  `test-pacman-package-lock.sh`.
- Observed: the patch expected wording that was not present in the current
  profile-validation block, so the patch engine rejected the complete edit;
  no partial hunk was applied.
- Correction: re-read the exact file, split the edit at stable surrounding
  lines, and run the complete lock test afterward.
- Permanent decision: after a long handoff or concurrent edit history, refresh
  the exact target context before applying a multi-hunk patch.

### SRC-20260722-008 — Deterministic epoch-safe package-lock transport

- Result: `PASS` at source and hostile-fixture scope; no replacement seed run
  has been dispatched yet.
- Primary variable: replace direct artifact upload of repository members with
  one deterministic GNU tar plus a SHA-256 sidecar, then safely extract and
  verify it before the normal build consumes the lock.
- Evidence: a fixture package named
  `fake-1:1.0-1-aarch64.pkg.tar.xz` retained its exact epoch filename through
  pack, SHA verification, bounded extraction, and complete lock verification.
  Two archives made from identical input at `SOURCE_DATE_EPOCH=0` were byte
  identical. The consumer also pins the archive SHA-256 in addition to the
  existing manifest, run, artifact, repository, and rootfs identities.
- Full local Gate: actionlint, immutable action pins, workflow semantics and
  input boundaries, safe extraction, governance, support bundle, USB rescue,
  Bluetooth NAP, Wi-Fi package, payload policy, tablet profile, audio, native
  packages, OpenPGP, pacman signatures, overlay boundaries, publication
  safety, shell syntax, and pacman lock tests all passed.
- Boundary: this only authorizes one new seed run that references
  `CI-20260722-004`; it does not authorize a firmware build, Release, or device
  write until the uploaded lock is downloaded and independently audited.

### DEV-20260722-010 — Historical Kubuntu DHCP address is not reachable

- Result: `FAIL` for a read-only SSH reachability check; no device command ran.
- Primary variable: TCP/SSH connection to the last recorded Kubuntu address
  `192.168.0.146` with batch authentication and strict host-key checking.
- Observed: the local kernel returned `No route to host` before SSH host-key or
  authentication negotiation. The address is DHCP-assigned and was already
  documented as non-stable.
- Recovery action: none required; no remote or local configuration changed.
- Next hypothesis: obtain a current address from local neighbor/mDNS evidence
  before any further SSH attempt. Do not retry `192.168.0.146` without new
  reachability evidence.

### DEV-20260722-011 — Ephemeral known-host process substitution was not read

- Result: `FAIL` before remote authentication; no device command ran.
- Primary variable: supply the newly verified host key to OpenSSH through a
  process-substitution `UserKnownHostsFile` while keeping strict checking.
- New evidence: mDNS resolved `GUF296.local` to `192.168.0.128`, and an
  independent ED25519 scan matched the recorded device fingerprint
  `SHA256:6X/qsZqT4F2DwGvhM9z13P31DwSrg9SaQiB8FImZ3T4`.
- Observed: OpenSSH did not recognize the process-substitution entry and
  stopped with `No ED25519 host key is known`; it did not attempt public-key
  authentication.
- Correction: retain the explicit fingerprint equality gate, then use an
  isolated `/dev/null` known-host database for this one connection. Do not
  repeat the failed process-substitution form unchanged.

### DEV-20260722-012 — Kubuntu does not authorize the dedicated Codex key

- Result: `FAIL` at SSH authentication; the verified device ran no command.
- Primary variable: authenticate `GUF296@192.168.0.128` with the dedicated
  local `id_ed25519_y700_codex` key after an explicit equality check against
  the recorded ED25519 host fingerprint.
- Observed: the server returned `Permission denied (publickey,password)`.
  This agrees with the current handoff stating that the restored Kubuntu image
  did not retain the earlier dedicated public key.
- Recovery action: none required; the connection was read-only and no host-key
  or remote configuration was persisted.
- Permanent decision: do not guess passwords or cycle unrelated keys. Resume
  SSH only with an explicitly known credential or after a separately
  authorized key-injection path becomes available.

### DEV-20260722-013 — gh api rejects binary artifact Accept header

- Result: `FAIL` before any artifact bytes were accepted.
- Primary variable: use `gh api` with `Accept: application/zip` to save the
  Actions artifact ZIP directly.
- Observed: GitHub returned HTTP 415 (`Unsupported 'Accept' header`) and the
  shell, without fail-fast around that one command, left a 163-byte JSON error
  body at the target path. No lock content was interpreted.
- Recovery action: identify the file by its size/content as an error response
  and remove only that explicit path before retrying with an authenticated
  HTTP client; preserve the API-reported artifact digest as the authority.
- Permanent decision: binary artifact downloads must fail closed on HTTP status
  and verify both the declared size and GitHub digest before extraction.

### DEV-20260722-014 — Safety layer rejected deleting the invalid download

- Result: `FAIL` before execution; the 163-byte HTTP 415 response was not
  removed.
- Primary variable: use `rm -f` to discard the explicitly identified invalid
  artifact path.
- Observed: the local command guard rejected recursive/destructive-style
  removal syntax even though the path was narrow.
- Correction: move the response to the explicit quarantine file
  `tb321fu-pacman-lock-29921200387.http-415.json`, preserving it as evidence
  and freeing the intended ZIP pathname without deletion.
- Permanent decision: quarantine failed downloads with a narrowly scoped move
  before considering any cleanup; do not weaken the safety guard.

### DEV-20260722-015 — Authenticated curl ZIP request still returns 415

- Result: `FAIL` before artifact bytes were accepted.
- Primary variable: use authenticated `curl --location` with
  `Accept: application/zip` against the GitHub artifact archive endpoint.
- Observed: GitHub returned HTTP 415 after 177 bytes; the expected 1,568,573,902
  byte artifact ZIP was not created and no lock member was interpreted.
- Correction: quarantine the partial response and use the GitHub CLI's
  supported `gh run download` extraction path; retain the API-provided artifact
  digest and verify all extracted members plus the deterministic inner tar.
- Permanent decision: do not repeat the raw ZIP endpoint/Accept combination
  until the API's current media-type behavior is independently established.

### DEV-20260722-016 — Artifact endpoint requires its default media type

- Result: `NOT TESTED` at the time of this record; a new download variable is
  authorized based on header-only evidence.
- Primary variable: omit a custom `Accept` header while retaining the
  authenticated artifact endpoint request.
- New evidence: header probes showed HTTP 302 and a signed blob `Location`
  only when no custom `Accept` was sent; explicit `application/zip` and
  `application/octet-stream` returned HTTP 415.
- Expected result: a raw ZIP whose byte size equals the API declaration and
  whose SHA-256 equals the recorded GitHub artifact digest.
- References: `DEV-20260722-013`, `DEV-20260722-015`.

### DEV-20260722-017 — Host GnuPG keyboxd polluted the first offline audit

- Result: `FAIL` in the audit harness before any package signature was
  accepted or rejected.
- Primary variable: invoke `gpg`/`gpgv` with the extracted ARM keyring while
  leaving the host's default GnuPG keyboxd configuration active.
- Observed: `gpg` ignored the supplied keyring and listed unrelated host keys;
  the trusted fingerprint comparison stopped the audit. No package result was
  recorded from that run.
- Correction: create an isolated temporary `GNUPGHOME`, disable inherited
  keybox state, dearmor the lock's armored keyring explicitly, and require its
  primary fingerprint to match `archlinuxarm-trusted` before running `gpgv`.
- Permanent decision: offline signature audits must never consult the host
  user's or system keybox; keyring provenance is a tested input.

### DEV-20260722-018 — Repository desc parser rejected NUL padding

- Result: `FAIL` in an independent audit harness; the authoritative lock
  verifier and 723-package `gpgv` pass remain unchanged.
- Primary variable: parse every frozen repository `desc` member as UTF-8
  section blocks after stripping only text whitespace.
- Observed: at least one member exposed a trailing NUL-padded block, which the
  parser treated as a section header and rejected. No database/package binding
  conclusion was emitted.
- Correction: first identify every member containing NUL bytes and require all
  NUL content to be trailing padding; strip only that verified suffix before
  parsing sections. Do not weaken filename, SHA, signature, or metadata checks.

### AUDIT-20260722-001 — Frozen extra.db has one unrelated NUL-only desc

- Result: `FAIL` for the stronger hypothesis that every upstream database
  `desc` member contains complete textual metadata; transaction audit remains
  in progress.
- Primary variable: inspect all four frozen repository databases independently
  of the lock manifest.
- Observed: `extra/findnewest-0.3-4/desc` is exactly 1,271 NUL bytes. GNU tar
  and Python agree. `pacman -Sl extra` still parses 12,848 entries and reports
  `findnewest 0.3-4`, but `pacman -Si` shows missing optional metadata. The
  package is absent from `PACKAGE-FILES.tsv`, `requested-packages.txt`, and
  `expected-installed-packages.txt`.
- Decision boundary: do not claim that every unrelated upstream DB entry is
  semantically complete. Continue only with a fail-closed audit requiring all
  723 packages in the actual frozen transaction to have complete DB filename,
  SHA-256, PGPSIG, architecture, name/version, matching detached signatures,
  and matching package metadata. Any NUL-only entry in that locked set is a
  release blocker.
- References: `DEV-20260722-018`, `SRC-20260722-007`.

### AUDIT-20260722-002 — Immutable pacman lock artifact and transaction

- Result: `PASS` for the 723-package transaction represented by the seed
  artifact; this is not a rootfs, GRUB, firmware candidate, Release, or device
  test.
- Workflow identity: run `29921200387`, commit
  `bae626a0e9f19fcdc1be4d0522cc6aebc2eaff9f`, artifact ID `8530543371`, name
  `tb321fu-pacman-lock-29921200387`.
- GitHub artifact: declared size `1568573902`; server digest and independently
  downloaded ZIP SHA-256 both
  `aa922a284f9356c76d8746b79db466c53a27b711b10d2d9612468e775863384e`.
- Inner transport: deterministic tar size `1568573440`, SHA-256
  `8c9328b682f13e9c518e28a6bcb7b3f0b620273ed94859dec7e4d9f4798c3fb0`;
  ZIP integrity passed, the CLI-extracted tar had the same digest, and bounded
  extraction accepted exactly 1,462 members with no symlinks.
- Lock identity: manifest SHA-256
  `a2e554de57011255bc25dc86b7c388982fe4ccadfa5cd2131d0bc817eb996bfd`;
  fixed rootfs SHA-256
  `3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a`;
  request-list SHA-256
  `4ae00eac38b8e4991947873b432afd93abb7205c559c5a44427026efd7052b20`;
  expected-installed SHA-256
  `2ae31bbab24c3c416e26999c2ff7055331c3d7d16eb7dd5c5f62aeaf38540c35`.
- Transaction evidence: 166 requested packages, 830 expected installed
  packages, 723 locked package files (`core=93`, `extra=629`, `alarm=1`,
  `aur=0`) and 52 epoch-bearing filenames. All member SHA256SUMS passed. All
  723 detached signatures passed `gpgv` using only the artifact's dearmored
  ARM primary key `68B3537F39A313B3E574D06777193F152BDBE6A6`.
- Database/package binding: all 723 locked entries have matching repository
  filename, SHA-256, PGPSIG, name, version, architecture, detached-signature
  bytes, and package `.PKGINFO`; all locked versions exactly match the expected
  installed set.
- Known boundary: `AUDIT-20260722-001` remains an explicit upstream database
  warning for the unrelated, unlocked `findnewest` entry; no locked entry has
  NUL or missing metadata, and pacman parses all four databases successfully.
- Evidence directory:
  `/home/fuhao/002/y700-linux/builds/artifacts/TB321FU-pacman-lock-run-29921200387/`.

### CI-20260722-005 — Locked build rejects Ubuntu sensor proxy collision

- Result: `FAIL` in artifact-only workflow run `29924934432`; no rootfs, GRUB,
  Release, or device write was produced.
- Workflow identity: commit `e87d90ca61213a425e12edb17cf968333ea6c53d`, branch
  `codex/tablet-rescue-20260720`, repository `wzfh001/arch-y700-build-ci`.
- Primary variable: first full rootfs build using the audited pacman lock
  (`run_id=29921200387`) while importing the fixed sensor archive and its
  Debian payloads through the generic Arch import package.
- New evidence: the locked transaction installed native Arch
  `iio-sensor-proxy 3.9-1`; the imported `qcom-sns-iio-sensor-proxy` Debian
  payload contains a different `/usr/bin/monitor-sensor`. The collision guard
  stopped at that path before packaging or overwriting it:
  `Arch import differs from existing file: /usr/bin/monitor-sensor`.
- Scope: the failure is deterministic and occurs after the rootfs package
  transaction, Wi-Fi native package, and niri validation all passed. No retry
  is authorized without changing the ownership model for the Qualcomm sensor
  proxy; do not weaken the generic collision guard or discard the differing
  file silently.
- Next hypothesis: stage the source-built Qualcomm sensor proxy as its own
  native Arch package with explicit `provides/conflicts/replaces` for
  `iio-sensor-proxy`, install it transactionally after the locked base set,
  and keep unrelated imported files under the generic package. Add ownership,
  package-integrity, and regression tests before one new CI run.
- Raw evidence: GitHub run logs at
  `https://github.com/wzfh001/arch-y700-build-ci/actions/runs/29924934432`;
  failed step `Build rootfs image`, final diagnostic line
  `error: Arch import differs from existing file: /usr/bin/monitor-sensor`.

### DEV-20260722-019 — Repeated the known unavailable `dpkg-deb` parser

- Result: `FAIL` in a local read-only inspection after the sensor archive and
  all four inner Debian package hashes had already passed.
- Primary variable: inspect Debian control fields and members with
  `dpkg-deb` on the CachyOS host.
- Observed: the command returned `dpkg-deb: command not found`, exactly the
  host limitation already recorded in `DEV-20260722-002`. No package member
  was interpreted and no repository or system state changed.
- Process correction: this was an unauthorized no-new-evidence repeat. Do not
  invoke `dpkg-deb` locally again. Continue with the already validated
  `ar` plus `tar`/`bsdtar` parser path and retain this entry so the repetition
  remains visible in the failure ledger.

### SRC-20260722-009 — Native Qualcomm SSC sensor proxy replacement gate

- Result: `PASS` for the source and fixed-payload gate; no firmware artifact,
  Release, or device write was produced.
- Source commit: `68898adc3e502c6adac2b8191a52bfed7aad70c7`.
- Primary variable: replace only the ownership model that failed in
  `CI-20260722-005`. The fixed Qualcomm SSC sensor proxy is now staged outside
  the generic import package and converted into native Arch package
  `qcom-sns-iio-sensor-proxy` after the locked base transaction.
- Source identity: archive
  `tb321fu-sensor-debs_20260627.1_arm64.tar.gz` passed SHA-256
  `62ebf6fb41730b9f52da2efc99ac5807fd41dd39d7f97dea070ba5f5ce34ab10`;
  all four inner Debian packages passed the archive's checksum manifest. The
  selected package
  `qcom-sns-iio-sensor-proxy_20260627.1_arm64.deb` passed SHA-256
  `b010a9a783629c4e0fd4c404b1a34e14258fab8a674d0499d553d361cb59a843`.
- Payload evidence: exactly seven regular files were accepted. Both binaries
  are AArch64; all seven fixed file hashes, executable/data modes, service
  `ExecStart`, and D-Bus activation path passed against the real extracted
  payload. Evidence directory:
  `/home/fuhao/002/y700-linux/builds/inputs/tb321fu-sensor-debs-20260627.1/`.
- Ownership policy: the audited stock `iio-sensor-proxy` remains part of the
  initial locked transaction, then the custom package explicitly
  `provides/conflicts/replaces` it through one pacman transaction. The generic
  import collision guard remains fail-closed and the stock executable/package
  must be absent after replacement. Final sensor proxy files, provenance, and
  checksums must be owned by the custom package.
- Regression coverage: new `SENSOR_PROXY_PACKAGE=PASS` gate checks source
  pins, exact member policy, rejection of extra/wrong-mode/symlink members,
  replacement relationships, ordering, stock-removal verification, rolling
  freeze policy, and preservation of the generic collision stop line.
- Full local workflow-equivalent gate passed, including actionlint/workflow
  semantics, governance, rescue, Wi-Fi, sensor proxy, payload policy,
  tablet-niri, audio, native package lifecycle, signatures, overlay,
  publication, and `PACMAN_PACKAGE_LOCK_PIN=PASS`.
- Next authorized experiment: one new artifact-only CI build from a committed
  clean tree. It must reference `CI-20260722-005` and this source gate; a
  Release or device write remains forbidden.

### CI-20260722-006 — Native sensor proxy artifact-only rebuild

- Result: `FAIL` as an isolated experiment; the authorized run was terminated
  by the next deterministic collision recorded as `CI-20260722-007` in
  workflow run `29928261179` before any artifact was created.
- Parent failure: `CI-20260722-005`, workflow run `29924934432`.
- Source evidence: `SRC-20260722-009`, implementation commit
  `68898adc3e502c6adac2b8191a52bfed7aad70c7`, source-record commit
  `acb594f`.
- Primary and only functional variable: remove the fixed Qualcomm SSC sensor
  proxy from the generic imported package and install it transactionally as
  native Arch package `qcom-sns-iio-sensor-proxy` after the same audited
  pacman transaction. All URLs, hashes, package lock, profile, image size,
  credentials policy, boot inputs, output prefix, and artifact-only release
  mode remain unchanged from the failed run.
- Expected result: the locked base set still matches all 830 expected packages;
  stock `iio-sensor-proxy` is then replaced, the custom package owns all nine
  payload/provenance paths, rootfs and GRUB complete, and two Actions artifacts
  upload. `release_tag` must remain empty and no Release may be created.
- Stop line: any different collision, package transaction drift, ownership
  mismatch, checksum failure, hidden test failure, or metadata leak is a new
  failure. Record it before considering another run; never rerun this commit
  unchanged without new evidence.

### CI-20260722-007 — Qualcomm libssc collision remains in generic import

- Result: `FAIL` in artifact-only workflow run `29928261179`; no rootfs, GRUB,
  Release, or device write was produced.
- Workflow identity: commit `6e6f6c6e2892d83e21e63dc588b900a52e2fedb7`, branch
  `codex/tablet-rescue-20260720`, repository `wzfh001/arch-y700-build-ci`.
- Primary variable: the `CI-20260722-006` ownership fix for
  `qcom-sns-iio-sensor-proxy`; all other inputs and the audited pacman lock
  were unchanged.
- New evidence: the fixed sensor payload reached the new staging and exact
  seven-file/hash gate successfully, but the remaining
  `qcom-sns-libssc_20260627.1_arm64.deb` was still merged into the generic
  imported package. The locked Arch `libssc` package owns a different
  `/usr/bin/ssccli`, and the fail-closed guard stopped at:
  `Arch import differs from existing file: /usr/bin/ssccli`.
- Decision boundary: do not discard `ssccli`, overwrite the stock package, or
  retry unchanged. Stage the complete Qualcomm `libssc` payload as a second
  native Arch package with explicit `provides/conflicts/replaces` for
  `libssc`; install it before the Qualcomm sensor proxy and make the proxy
  depend on that package. Preserve the generic collision guard for all other
  imports.
- Raw evidence: GitHub run logs at
  `https://github.com/wzfh001/arch-y700-build-ci/actions/runs/29928261179`;
  failed step `Build rootfs image`, final diagnostic line
  `error: Arch import differs from existing file: /usr/bin/ssccli`.
- Next hypothesis: one new source change only—split and verify the fixed
  Qualcomm `libssc` payload, then run a new artifact-only build after local
  gates pass. No Release or device write is authorized.

### DEV-20260722-020 — Two malformed no-op patch attempts used a wrong path

- Result: `FAIL` twice before any file edit was applied.
- Primary variable: update the tablet package required/forbidden arrays for
  the new Qualcomm `libssc` ownership model.
- Observed: both patch attempts contained the duplicated, nonexistent path
  segment `arch-y700-linux/repositories` and an empty hunk, so `apply_patch`
  rejected them during verification. The second attempt repeated the same
  malformed input without new evidence.
- Recovery action: verify the exact repository path, then apply one bounded
  hunk to the existing file. The corrected patch succeeded; no invalid path
  was created and no prior change was overwritten.
- Process correction: treat an `apply_patch` verification error as a failed
  experiment and inspect the literal target/hunk before retrying; never resend
  an unchanged rejected patch.

### DEV-20260722-021 — Third malformed no-op patch used the same wrong path

- Result: `FAIL` before execution; no file edit was applied.
- Primary variable: add Qualcomm `libssc` ownership checks to the native
  package integrity function.
- Observed: the patch target again contained the duplicated nonexistent path
  segment `arch-y700-linux/repositories`, and `apply_patch` rejected the empty
  hunk. This was another process error, not new build evidence.
- Correction: stop using the malformed absolute path form and apply the next
  edit only after checking the repository root. Do not repeat this rejected
  target string.

### DEV-20260722-022 — libssc validator had a duplicate here-document terminator

- Result: `FAIL` at the local shell syntax gate; no CI run or package action
  occurred from this source tree.
- Primary variable: add the fixed-member mode loop to the Qualcomm `libssc`
  validator.
- Observed: the generated function contained both the here-document's
  terminating `done <<...` and a second indented `done` after the delimiter;
  `bash -n` stopped at line 1923 with `syntax error near unexpected token done`.
- Correction: remove only the duplicate terminator, rerun `bash -n` and the
  focused payload test before any commit or dispatch. This is a source-test
  failure, not a reason to retry CI run `29928261179`.

### DEV-20260722-023 — libssc validator delimiter was indented

- Result: `FAIL` at the immediate syntax rerun after `DEV-20260722-022`;
  no package action occurred.
- Primary variable: remove the duplicate `done` while retaining the
  here-document member list.
- Observed: the delimiter line still had two leading spaces, so Bash treated
  the here-document as unterminated and reported `unexpected end of file`.
- Correction: place `LIBSSC_DATA_FILES` at column zero, then rerun syntax and
  focused tests. This is recorded as a separate source-test failure; no CI
  retry is authorized from an unvalidated tree.

### DEV-20260722-024 — libssc symlink was counted as a regular file

- Result: `FAIL` in the focused sensor-payload fixture after shell syntax
  passed; no CI run occurred.
- Primary variable: execute the exact-member validator with one safe
  `libssc.so -> libssc.so.2` symlink.
- Observed: the validator correctly enumerated the symlink separately but its
  regular-file/checksum/mode manifests also listed `libssc.so`, causing a file
  list mismatch. The earlier streamed hash for a symlink member represented no
  file bytes and was not a valid installed-tree checksum.
- Correction: validate the symlink only by exact path and target; remove it
  from regular-file, checksum, and mode manifests. Keep `libssc.so.2` as the
  hashed AArch64 ABI file.

### DEV-20260722-025 — libssc shared-object mode was treated as executable

- Result: `FAIL` in the focused validator fixture after the symlink fix; no CI
  run occurred.
- Primary variable: validate the fixed `ssccli` and `libssc.so.2` ELF members.
- Observed: the validator required mode `0755` for both, but the real fixed
  package intentionally ships the shared object as mode `0644`; only
  `/usr/bin/ssccli` is executable.
- Correction: split the mode checks, retaining AArch64 ELF checks for both and
  requiring `0644` for the ABI library. Do not relax data-file mode policy.

### DEV-20260722-026 — libssc fixture omitted the unexpected-member directory

- Result: `FAIL` in the focused regression test after the validator passed the
  valid fixture; no CI run occurred.
- Primary variable: exercise rejection of an extra `/usr/share/unexpected`
  member.
- Observed: the test wrote that path before creating its parent directory, so
  it stopped with a local `No such file or directory` unrelated to production
  validation.
- Correction: create the fixture directory explicitly, then rerun the same
  negative test. Production code was unchanged by this correction.

### DEV-20260722-027 — Documentation patch used stale roadmap context

- Result: `FAIL` before any file edit was applied.
- Primary variable: update the status, roadmap, and experiment records after
  commit `04aa394`.
- Observed: one combined patch used text from an older `ROADMAP.md` revision;
  `apply_patch` rejected the roadmap hunk during verification, so no part of
  that patch was applied. No repository or external state changed.
- Correction: inspect the literal current context and apply three bounded
  patches separately. Do not resend the rejected combined hunk.

### SRC-20260722-010 — Native Qualcomm libssc replacement gate

- Result: `PASS` for the source and fixed-payload gate; no firmware artifact,
  Release, or device write was produced.
- Source commit: `04aa3949ae6ac5ab45b1d3bc9ef3398ef8865b67`.
- Primary variable: address only the `/usr/bin/ssccli` collision observed in
  `CI-20260722-007` by removing the fixed Qualcomm `libssc` payload from the
  generic import and packaging it as native Arch `qcom-sns-libssc`.
- Source identity: selected package
  `qcom-sns-libssc_20260627.1_arm64.deb` passed SHA-256
  `4c6f84c266a2c6d588289b5a9700a59711f0a7824744c8a788c8adf7c5786f86`.
  The fixed payload contains 19 exact regular files and one explicitly checked
  ABI symlink; all member hashes, modes, and AArch64 ELF checks passed.
- Ownership policy: the native package explicitly
  `provides/conflicts/replaces=libssc`, is installed before
  `qcom-sns-iio-sensor-proxy`, and leaves the generic collision guard
  fail-closed for every unrelated imported path. Stock `libssc` must be absent
  after the transaction and all fixed files must be pacman-owned.
- Regression coverage: focused payload, package lifecycle, ownership,
  ordering, checksum, symlink, mode, and full workflow-equivalent gates all
  passed locally, including the audited pacman lock and publication guards.
- Next authorized experiment: exactly one artifact-only CI build from this
  clean commit. `release_tag` remains empty; no Release or device write is
  authorized.

### CI-20260722-008 — Qualcomm libssc artifact-only rebuild authorization

- Result: `FAIL` in artifact-only workflow run `29931623980`; no rootfs, GRUB,
  artifact, Release, or device write was produced.
- Parent failure: `CI-20260722-007`, workflow run `29928261179`.
- Commit: `04aa3949ae6ac5ab45b1d3bc9ef3398ef8865b67`, branch
  `codex/tablet-rescue-20260720`, repository `wzfh001/arch-y700-build-ci`.
- Primary and only functional variable: split the fixed Qualcomm `libssc`
  payload into native `qcom-sns-libssc`, replace the locked stock `libssc`
  transactionally, and install it before `qcom-sns-iio-sensor-proxy`.
- Held constant: pacman lock seed `29921200387`, rootfs/boot/kernel/sensor/
  haptics inputs, `tablet-niri` profile, image size, output identity, and all
  credential policy. `release_tag` is empty and `prerelease=false`.
- Expected result: the locked base transaction remains unchanged, both custom
  Qualcomm packages pass exact payload/ownership checks, rootfs and GRUB finish,
  and the two Actions artifacts upload without a Release.
- New evidence: checkout, all source gates, release-mode validation, dependency
  installation, lock resolution/download, and immutable lock verification
  passed. The rootfs script then rejected the separately dispatched
  `ARCH_ROOTFS_SHA256` with `invalid rootfs SHA-256`.
- Boundary correction: the pre-build verification used the 64-character value
  from `profiles/tablet-niri/pacman-lock.env`; it did not validate the
  workflow-dispatch input. The run created zero artifacts and the repository
  still has zero Releases.
- Raw evidence: GitHub run
  `https://github.com/wzfh001/arch-y700-build-ci/actions/runs/29931623980`,
  failed job `88962544549`, step `Build rootfs image`.
- Next hypothesis at the time: remove reliance on `sudo --preserve-env` for the
  non-secret rootfs SHA. This hypothesis was later falsified by `CI-20260722-010`.
- Stop line: any new collision, transaction drift, hash/ownership mismatch,
  hidden test failure, metadata leak, or missing log is a new failure. Do not
  rerun this commit unchanged after a failure.

### SRC-20260722-011 — Explicit rootfs SHA transport across sudo

- Result: `PASS` for the source gate; no firmware artifact, Release, or device
  write was produced.
- Source commit: `f3b4bb44be9e87f91c9421963fe46513c11ee05e`.
- Parent failure: `CI-20260722-008`, workflow run `29931623980`.
- Primary and only functional variable: stop relying on
  `sudo --preserve-env` for the non-secret `ARCH_ROOTFS_SHA256`; bind its
  already validated workflow value explicitly in the post-`sudo` `env`
  command that starts `build-arch-rootfs-image.sh`.
- Security boundary: password hashes and authorized keys remain step-scoped
  secrets transported through the existing restricted path. No secret is
  added to workflow inputs, command-line literals, metadata, or logs.
- Regression coverage: actionlint, workflow semantics, input-boundary checks,
  and `test-pacman-package-lock.sh` pass. The lock test now requires the
  explicit SHA binding and rejects restoring it to the `sudo --preserve-env`
  list.
- Next authorized experiment: exactly one artifact-only CI build with all
  package, rootfs, boot, kernel, payload, credential, and release-mode inputs
  unchanged. No Release or device write is authorized.

### CI-20260722-009 — Elevated rootfs SHA artifact-only rebuild authorization

- Result: `FAIL` in artifact-only workflow run `29932470727`; no rootfs, GRUB,
  artifact, Release, or device write was produced.
- Parent failure: `CI-20260722-008`, workflow run `29931623980`.
- Source evidence: `SRC-20260722-011`, implementation commit
  `f3b4bb44be9e87f91c9421963fe46513c11ee05e`.
- Primary and only functional variable: explicitly transport the selected
  rootfs SHA across the elevated command boundary. Qualcomm package handling,
  pacman transaction content, and all fixed payload bytes are unchanged.
- Held constant: pacman lock seed `29921200387`, pinned rootfs/boot/kernel/
  device/sensor/haptics inputs, `tablet-niri`, `20G`, credentials policy,
  artifact naming policy, `release_tag` empty, and `prerelease=false`.
- Expected result: both pre- and post-`sudo` lock verification accept the same
  rootfs SHA, the build reaches the Qualcomm package gates, rootfs and GRUB
  complete, and two artifacts upload without a Release.
- Observed: the workflow source showed the new explicit
  `env ARCH_ROOTFS_SHA256="$ARCH_ROOTFS_SHA256"` binding, but the dispatched
  value was still malformed and the rootfs verifier stopped before image
  creation.
- Conclusion: `SRC-20260722-011` did not address the failure; the actual input
  bytes were unknown at this point, so another transport change was forbidden
  until byte-level diagnostic evidence existed.
- Raw evidence: GitHub run
  `https://github.com/wzfh001/arch-y700-build-ci/actions/runs/29932470727`,
  failed job `88965492451`, zero artifacts.
- Next authorized variable: improve the fail-closed verifier error to report
  the non-secret argument length and shell-escaped representation, with a
  regression test, then execute one diagnostic artifact-only run.
- Stop line: any new failure must be logged before another run; never rerun the
  same commit unchanged.

### DEV-20260722-028 — Source record guessed an incorrect full commit hash

- Result: `FAIL` in an uncommitted documentation check; no CI run or external
  state change occurred.
- Primary variable: record the full implementation identity for
  `SRC-20260722-011` and `CI-20260722-009`.
- Observed: the first draft expanded the known short hash `f3b4bb4` into an
  unverified 40-character value. `git rev-parse f3b4bb4` returned the actual
  identity `f3b4bb44be9e87f91c9421963fe46513c11ee05e` before commit.
- Correction: replace both draft values with the Git-resolved identity and
  require `git rev-parse` evidence before writing any future full commit hash.

### DEV-20260722-029 — Diagnostic regression assertion overescaped the newline

- Result: `FAIL` in a local focused test; no CI run or external state change
  occurred.
- Primary variable: assert that the malformed rootfs-SHA diagnostic exposes a
  shell-escaped trailing newline.
- Observed: the first test fixture searched for two literal backslashes, while
  Bash `%q` correctly emits one backslash before `n`; the production verifier
  was already correct.
- Correction: reduce the fixed-string assertion to one backslash, rerun the
  focused lock test, and require a direct `%q` probe before writing future
  shell-escape assertions.

### DEV-20260722-030 — Combined diagnostic documentation patch used stale wrapping

- Result: `FAIL` before any file edit was applied.
- Primary variable: record the diagnostic source gate and authorization.
- Observed: the combined patch expected a line break in `STATUS.md` that did
  not exist in the current file, so `apply_patch` rejected the whole patch.
- Correction: inspect the literal current lines and apply bounded status,
  roadmap, and experiment-log patches separately. Do not resend the rejected
  combined context.

### SRC-20260722-012 — Fail-closed rootfs SHA byte diagnostics

- Result: `PASS` for the source and regression gate; no firmware artifact,
  Release, or device write was produced.
- Source commit: `72c6bd539bc955fd436ec9bd532455fedfa73641`.
- Parent failure: `CI-20260722-009`, workflow run `29932470727`.
- Primary and only functional variable: when the verifier receives a malformed
  rootfs SHA, report its non-secret byte length and Bash shell-escaped form
  before failing. A valid 64-hex SHA remains the only accepted input.
- Regression coverage: `test-pacman-package-lock.sh` now rejects a
  trailing-newline SHA and checks both diagnostics; syntax and the complete
  local lock policy pass.
- Next authorized experiment: one diagnostic artifact-only CI build to expose
  the exact post-boundary bytes. No Release or device write is authorized.

### CI-20260722-010 — Rootfs SHA diagnostic artifact-only authorization

- Result: `FAIL` in diagnostic artifact-only workflow run `29933069005`; no
  rootfs, GRUB, artifact, Release, or device write was produced.
- Parent failure: `CI-20260722-009`, workflow run `29932470727`.
- Source evidence: `SRC-20260722-012`, implementation commit
  `72c6bd539bc955fd436ec9bd532455fedfa73641`.
- Primary and only functional variable: add fail-closed byte-level diagnostics
  to the lock verifier. Build inputs, package ownership changes, lock seed,
  credentials policy, output prefix, and release mode remain unchanged.
- Expected result: if the hidden-byte hypothesis is correct, the failed step
  will identify the exact length and escaped form; otherwise it will show that
  the invalid value originates elsewhere. The run remains artifact-only.
- Observed: the verifier reported
  `invalid rootfs SHA-256 (length=63, shell=3cf5764f...0404c56)`. The value is
  an exact prefix of the pinned 64-character SHA and is missing its final `a`;
  there is no hidden newline or `sudo` mutation.
- Root cause: the dispatch command manually transcribed a 63-character SHA.
  The pre-build lock step validated the profile's independent 64-character
  value, so it did not catch the malformed workflow input. This is an operator
  input error, not a repository or package-lock defect.
- Raw evidence: GitHub run
  `https://github.com/wzfh001/arch-y700-build-ci/actions/runs/29933069005`,
  failed job `88967512094`, zero artifacts.
- Stop line: record the new evidence before any transport or input fix; never
  rerun this commit unchanged after failure.

### DEV-20260722-031 — Hand-dispatched rootfs SHA omitted the final character

- Result: `FAIL` across three artifact-only dispatches (`29931623980`,
  `29932470727`, and `29933069005`); no artifact or device state changed.
- Primary variable: manually supply the pinned `arch_rootfs_sha256` workflow
  input.
- Observed: each command used the 63-character prefix ending in `c56`; the
  committed lock profile ends in `c56a` and is 64 characters. The new verifier
  diagnostic proved the omission.
- Correction: derive the dispatch value from
  `profiles/tablet-niri/pacman-lock.env`, assert exactly 64 lowercase
  hexadecimal characters, and print the length before dispatch. Do not hand
  type this value again.

### CI-20260722-011 — Corrected pinned rootfs SHA artifact-only authorization

- Result: `AUTHORIZED/PENDING` at record creation.
- Parent failures: `CI-20260722-008`, `CI-20260722-009`, and
  `CI-20260722-010`; the common root cause is `DEV-20260722-031`.
- Source tree: branch `codex/tablet-rescue-20260720`, with the diagnostic and
  package fixes already committed; no source functional change is introduced
  by this authorization.
- Primary and only functional variable: send the exact 64-character
  `rootfs_sha256` read from `profiles/tablet-niri/pacman-lock.env` instead of
  the previously truncated hand-written value.
- Held constant: rootfs/boot/kernel/device/sensor/haptics inputs, pacman lock
  seed `29921200387`, `tablet-niri`, `20G`, credentials policy, output prefix,
  `release_tag` empty, and `prerelease=false`.
- Expected result: the rootfs verifier accepts the selected SHA and the build
  proceeds to the Qualcomm package/ownership gates; success still creates only
  Actions artifacts and never a Release.
- Stop line: any new failure is a distinct experiment; never rerun a malformed
  dispatch or this corrected input unchanged after failure.

### CI-20260722-011 — Corrected pinned rootfs SHA artifact-only build result

- Result: `FAIL`; artifact-only workflow run `29933523257`; zero artifacts,
  zero Release objects, and no device write.
- Commit: `a14ef759f4ab4105f9903101fbc3930a9af74683`, branch
  `codex/tablet-rescue-20260720`, repository `wzfh001/arch-y700-build-ci`.
- Parent authorization: the corrected dispatch described immediately above;
  malformed rootfs-SHA attempts `29931623980`, `29932470727`, and
  `29933069005` are not being repeated.
- Primary and only functional variable: use the exact 64-character rootfs
  SHA read from the committed lock profile. All package, kernel, device
  archive, sensor, haptics, profile, credential and release-mode inputs were
  held constant.
- Expected result: the rootfs build would pass the corrected hash gate and
  either complete or expose a new payload-specific failure with its raw log.
- Observed: the build passed the lock and Qualcomm package preparation far
  enough to hit the generic Arch import guard, which reported:
  `Arch import differs from existing file: /usr/lib/firmware/qca/hmtbtfw20.tlv`.
  The device overlay member is 265,528 bytes, SHA-256
  `b4e7f61e7dd090e56811860a7781ff3b0ce8e87cc0480feaab34bf4f614308c5`, and
  mode `0777` in the Debian archive before the production mode normalizer.
  The locked `linux-firmware-atheros-20260622-1-any.pkg.tar.xz` member is
  270,120 bytes, SHA-256
  `f1c00f4640a5c4e5dc36a2574d3d1d0afcfd1ab58a84f217dce4b1bb73cba981`, mode
  `0644`; the bytes differ. The `sort: write failed: Broken pipe` line is a
  secondary failure after the shell exited and is not a separate cause.
- Offline follow-up evidence: the device overlay contains 62 regular QCA
  files. Across all subdirectories, the locked `linux-firmware-atheros`
  package contains 95 regular QCA members and 48 symlinks (143 non-directory
  members; the direct-root view has 136 entries). Four direct-root paths
  overlap; all four contents differ, and the `b112` types differ. No other
  locked firmware split package contains a QCA path.
- Stop line: this is a real content collision. Do not overwrite either
  payload, drop the device file, or relax the generic collision guard. First
  complete the offline path/owner/content/mode audit and implement a separate
  firmware-search-path package as a new source experiment.

### DEV-20260722-032 — Dispatch shell JavaScript string syntax error

- Result: `FAIL` before dispatch; no file, repository, CI, or device state
  changed.
- Primary variable: compose the shell command used to dispatch the corrected
  artifact-only workflow.
- Observed: a JavaScript string literal containing `source_config=""` was
  malformed, so the orchestration tool rejected the script before executing
  any shell command.
- Correction: use a safely quoted argument representation and verify the
  generated command text before execution. Do not resend the malformed JS
  literal.

### DEV-20260722-033 — Bash parameter expansion parsed as JavaScript

- Result: `FAIL` before dispatch; no external state changed.
- Primary variable: validate the rootfs SHA length inside the dispatch shell
  command.
- Observed: a JavaScript template literal interpreted Bash `${#rootfs_sha}`
  as a JavaScript private-field expression and failed before the shell ran.
- Correction: avoid JavaScript template interpolation for Bash parameter
  expansions; pass the command as a plain string or concatenate only validated
  fragments.

### DEV-20260722-034 — Safety-layer rejection of a read-only check command

- Result: `FAIL` before execution; no filesystem or external state changed.
- Primary variable: inspect temporary dispatch state with a command that
  included the literal text `rm -rf` in a read-only conditional check.
- Observed: the safety layer rejected the command text without running it;
  there was no deletion and no new evidence.
- Correction: use non-destructive inspection without deletion tokens (or let
  temporary directories expire) and do not treat this rejected command as an
  executed experiment.

### DEV-20260722-035 — Bluetooth fixture asserted the wrong build token

- Result: `FAIL` in the local source fixture; no CI, artifact, Release, or
  device state changed.
- Primary variable: add a static assertion for the independent Bluetooth
  firmware destination.
- Observed: the first assertion searched for a target string that the build
  function does not emit because the destination is assembled from
  `custom_relative`; the implementation was not the failing component.
- Correction: assert the actual production expression and then execute the
  extracted production function against the fixed archive fixture. Do not
  restore the rejected string-only assertion.

### DEV-20260722-036 — Bluetooth fixture omitted the package-name variable

- Result: `FAIL` in the local source fixture; no external state changed.
- Primary variable: execute `install_tb321fu_bluetooth_firmware_package()`
  outside the complete rootfs build.
- Observed: the fixture did not set
  `TB321FU_BLUETOOTH_FIRMWARE_PACKAGE`, so strict undefined-variable handling
  stopped before the package-call assertion.
- Correction: set the same fixed package name used by production before
  invoking the extracted function. Do not weaken `set -u`.

### DEV-20260722-037 — QCA inventory mixed direct and recursive counts

- Result: `FAIL` in interpretation only; immutable inputs were not changed.
- Primary variable: count locked QCA members.
- Observed: the first interpretation treated 136 direct directory entries as
  136 regular files plus one symlink. The recursive package inventory is 95
  regular files and 48 symlinks, or 143 non-directory members; only four
  direct-root paths overlap the device payload.
- Correction: count member types recursively and record direct-root overlap
  separately. Do not reuse the rejected 136+1 claim.

### DEV-20260722-038 — First overlap-table patch used literal backslash-t context

- Result: `FAIL` before edit; the patch was rejected and no file changed.
- Primary variable: add the four QCA overlap evidence rows.
- Observed: the patch context contained the two literal characters `\\t`
  while the file contained real tab separators.
- Correction: patch against real TSV context or replace the exact complete
  block. The rejected patch was not retried unchanged.

### DEV-20260722-039 — Second overlap-table patch repeated invalid TSV context

- Result: `FAIL` before edit; no repository or external state changed.
- Primary variable: correct the same overlap evidence block after
  `DEV-20260722-038`.
- Observed: a second patch still matched literal `\\t` text and was rejected.
- Correction: inspect the real file bytes first and apply a tab-correct patch;
  no third attempt used the invalid context.

### DEV-20260722-040 — ALSA lock lookup assumed the wrong repository

- Result: `FAIL` in a read-only package lookup; no state changed.
- Primary variable: identify the locked owner of the remaining UCM collision.
- Observed: the first lookup assumed `alsa-ucm-conf` was in `core`; the fixed
  lock stores `alsa-ucm-conf-1.2.16.1-1-any.pkg.tar.xz` in `extra`.
- Correction: derive package paths from the lock archive inventory instead of
  guessing the repository.

### DEV-20260722-041 — First deferred-output wait targeted no resumable cell

- Result: `FAIL` at the orchestration layer; no shell command or state change
  occurred.
- Primary variable: wait for output from an earlier inspection command.
- Observed: the wait helper was called without a valid yielded cell identity.
- Correction: call the wait helper only after an execution result explicitly
  returns a resumable cell ID.

### DEV-20260722-042 — Second deferred-output call mixed cell and shell sessions

- Result: `FAIL` at the orchestration layer; no filesystem, GitHub, CI, or
  device state changed.
- Primary variable: retrieve the same pending inspection output.
- Observed: the second call used the cell-wait mechanism where a shell session
  poll was required.
- Correction: distinguish yielded execution cells from PTY shell session IDs;
  this invalid call is not evidence and must not be repeated.

### DEV-20260722-043 — Expected zero old UCM references tripped pipefail

- Result: `FAIL` at the end of a read-only temporary transformation check; no
  repository, CI, or device state changed.
- Primary variable: prove the transformed Lenovo UCM files contain zero
  `/codecs/wcd939x/` references.
- Observed: `rg` correctly found zero old references and returned status 1,
  which `set -euo pipefail` treated as command failure before the remaining
  display-only checks ran. The transformed hashes had already been printed.
- Correction: use an explicit negative assertion for expected absence, then
  count the seven required `/codecs/tb321fu-wcd939x/` references separately.

### DEV-20260722-044 — Bluetooth source record guessed the full commit hash

- Result: `FAIL` in documentation review; no source, CI, artifact, Release, or
  device state changed.
- Primary variable: record the full object identity for short commit
  `782dd08`.
- Observed: the first documentation patch expanded the short hash without
  querying Git and wrote a nonexistent full object ID.
- Correction: use `git rev-parse 782dd08` and record
  `782dd08b94c111168294085a1c770c299fdad109`. Never infer the remainder of a
  Git object ID from its short form.

### AUDIT-20260722-003 — Full fixed-device archive versus pacman-lock overlap

- Result: `PASS`; read-only offline audit, no CI, artifact, Release, or device
  write.
- Inputs: fixed device archive SHA-256
  `047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04`
  and pacman-lock archive SHA-256
  `8c9328b682f13e9c518e28a6bcb7b3f0b620273ed94859dec7e4d9f4798c3fb0`.
- Scope: enumerate all 2,335 regular files/symlinks from the three fixed device
  payloads and every member of all 723 locked Arch packages; compare path,
  owner package, owner-package SHA-256, member type, mode, size/target, and
  content hash.
- Observed: exactly 16 paths intersect. Ten WCD939x UCM members are identical;
  six differ: WCN7850 `board-2.bin`, four direct-root QCA Bluetooth files, and
  `/usr/share/alsa/ucm2/codecs/wcd939x/HeadphoneEnableSeq.conf`.
- ALSA evidence: device file is 276 bytes / mode `0644` / SHA-256
  `333c56a133d260f696fbc817dfb7760e7c75619d0540bf62128527dd9a7438f5`;
  locked `alsa-ucm-conf-1.2.16.1-1` is 282 bytes / mode `0644` / SHA-256
  `f8b856216adf46b1b6a7e9e3cbd85fd50a6446c77a9ac7bb0a60dfd189adbbc0`.
  The device route uses `CLSH Switch=0` and `RX HPH Mode=CLS_AB`; the generic
  route uses `CLSH Switch=1` and `RX HPH Mode=CLS_H_LOHIFI`.
- Stop line: all six mismatches require explicit independent ownership or an
  already approved transformation. Do not trigger a build that only fixes
  QCA; it would deterministically stop at the UCM mismatch.

### SRC-20260722-013 — Independent TB321FU QCA Bluetooth firmware source gate

- Result: `SOURCE PASS`; source commit
  `782dd08` (`782dd08b94c111168294085a1c770c299fdad109`); no new CI run,
  artifact, Release, or device write.
- Parent failure: `CI-20260722-011`, run `29933523257`.
- Primary variable: carve all 62 fixed device QCA files out of the generic
  imported payload and package them as `tb321fu-bluetooth-firmware` under
  `/usr/lib/firmware/tb321fu/qca`, while retaining locked
  `linux-firmware-atheros` at `/usr/lib/firmware/qca`.
- Runtime evidence: the Kubuntu kernel log requests
  `qca/hmtbtfw20.tlv` and `qca/hmtnv20_Kirby_prc.bin`; the existing fixed
  `firmware_class.path=/usr/lib/firmware/tb321fu` bootarg resolves those names
  against the device package first.
- Offline audit: device QCA inventory is 62 regular files; locked generic QCA
  inventory is 95 regular files plus 48 symlinks; four paths overlap and all
  differ. `hmtnv20.b112` is deliberately a device regular file while the Arch
  member is a symlink to `hmtnv20.b10f`.
- Verification: Bluetooth archive fixture, native-package staging, manifest,
  provenance, package ownership policy, workflow/profile gates, and the
  independent QCA collision audit all pass. Final raw content and TB321FU
  Bluetooth behavior remain `UNTESTED`.
- Next hypothesis: isolate the device UCM profile and codec sequence under a
  non-conflicting path before one combined artifact-only build. Do not rerun
  `CI-20260722-011` with only this QCA change.

### DEV-20260722-045 — ALSA package matrix used the wrong route token

- Result: `FAIL` in documentation review before commit; no source behavior,
  CI, artifact, Release, or device state changed.
- Primary variable: describe the fixed TB321FU headphone route.
- Observed: the first package-matrix edit wrote `CLSH_AB`, which is not the
  value in the device UCM file. The fixed route is `RX HPH Mode=CLS_AB` with
  `CLSH Switch=0`.
- Correction: compare the prose with the pinned source file and use
  `CLS_AB`. Do not reuse the rejected token.

### SRC-20260722-014 — Independent TB321FU ALSA UCM source gate

- Result: `SOURCE PASS`; source commit `395175c`
  (`395175c9ca9f1cd8d36afcb9b595c02e13e6bf2f`); no new CI run, artifact,
  Release, or device write.
- Parent evidence: `AUDIT-20260722-003` identified the one remaining unhandled
  fixed-device versus locked-Arch mismatch at
  `/usr/share/alsa/ucm2/codecs/wcd939x/HeadphoneEnableSeq.conf`.
- Primary variable: package the two `LenovoY700TB321` UCM profile files and all
  eleven fixed device WCD939x sequence files as `tb321fu-alsa-ucm`. Device
  codec files move to `/usr/share/alsa/ucm2/codecs/tb321fu-wcd939x`; exactly
  seven profile includes are deterministically rewritten to that path.
- Held constant: fixed device archive, pacman lock, generic
  `alsa-ucm-conf-1.2.16.1-1`, QCA/WCN7850 policy, kernel, rootfs, sensor,
  haptics, profile, credentials, and artifact-only release mode.
- Content evidence: source and transformed manifests each pin 13 files. The
  device headphone sequence remains 276 bytes / SHA-256
  `333c56a133d260f696fbc817dfb7760e7c75619d0540bf62128527dd9a7438f5`
  with `CLSH Switch=0` and `RX HPH Mode=CLS_AB`; the generic 282-byte / SHA-256
  `f8b856216adf46b1b6a7e9e3cbd85fd50a6446c77a9ac7bb0a60dfd189adbbc0`
  file remains unchanged and owned by `alsa-ucm-conf`.
- Verification: the production staging function passes the fixed archive
  fixture; the transformed tree combines with the locked generic UCM package
  and passes `alsaucm` offline parsing; the complete 2,335-member versus
  723-package collision audit passes at 16 intersections / 10 identical / 6
  explicitly handled mismatches. All workflow, boundary, governance, rescue,
  Wi-Fi, Bluetooth, ALSA, sensor, payload, profile, audio, native-package,
  OpenPGP, pacman-signature, overlay, publication, and pacman-lock local gates
  pass without hidden failures.
- Remaining state: final raw ownership/content and all TB321FU audio behavior
  are `UNTESTED`. The next build may contain both independently source-gated
  QCA and ALSA fixes because either fix alone is already known to stop at the
  other collision.
- Stop line: trigger exactly one artifact-only build with the rootfs SHA read
  and validated from `profiles/tablet-niri/pacman-lock.env`; do not publish a
  Release or treat CI success as hardware verification.

### DEV-20260722-046 — Handoff update again inferred a full Git object ID

- Result: `FAIL` in local handoff/plan review; no source behavior, GitHub, CI,
  artifact, Release, or device state changed.
- Primary variable: update the current source identity after evidence commit
  `f094bbb`.
- Observed: the first handoff patch again guessed the unprinted suffix and
  wrote a nonexistent full object ID.
- Correction: `git rev-parse f094bbb` returns
  `f094bbb75e61f21b9d8f19e149b79bf697dac658`. Query every full Git identity;
  never expand a short hash by inference.

### CI-20260722-012 — QCA plus ALSA artifact-only build authorization

- Result: `AUTHORIZED/PENDING` at record creation; no dispatch has occurred in
  this experiment yet.
- Parent failure: `CI-20260722-011`, run `29933523257`, which created zero
  artifacts and stopped at the first of the known archive/Arch mismatches.
- Source gates: `SRC-20260722-013` / `782dd08` for all 62 QCA files and
  `SRC-20260722-014` / `395175c` for the complete 13-file UCM source and
  transformed package; current source/evidence HEAD before this authorization
  is `b08b0051b466ee2065b254ed96d03ad99c0a5b23`.
- Primary experiment: build the first candidate in which all six mismatches
  from `AUDIT-20260722-003` have explicit package policies. QCA and ALSA are
  combined only because each was independently source-gated and a build with
  either one alone is already proven to stop at the other known mismatch.
- Dispatch policy: branch `codex/tablet-rescue-20260720`, output prefix
  `TB321FU-archlinuxarm-tablet-niri-ci12-20260722`, `tablet-niri`, `20G`, empty
  advanced configs, empty `release_tag`, and `prerelease=false`.
- Rootfs policy: read `rootfs_sha256` directly from the committed
  `profiles/tablet-niri/pacman-lock.env`, require exactly 64 lowercase
  hexadecimal characters, and pass that variable to the workflow without
  manual transcription. Pacman seed run remains `29921200387`.
- Held constant: rootfs URL, kernel/boot/device/sensor/haptics inputs, complete
  pacman lock, credential policy, rootfs size, and all release protections.
- Expected result: either one complete Actions artifact set for P4 offline
  audit or one new deterministic failure with raw logs. Success is not hardware
  verification and must not create a Release.
- Stop line: dispatch exactly once. Any failure becomes a new experiment and
  may only be retried after a documented evidence or source change.

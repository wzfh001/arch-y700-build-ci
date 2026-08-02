# Flashing & Safety Red Lines

> **Nothing in this repository may be flashed to a device until P4 offline audit
> PASS, P5 flash prep is complete, and the user explicitly confirms
> target/scope/image SHA/recovery boundary. (P4 PASS + P5 READY as of
> 2026-08-02; live GPT re-read VERIFIED. Awaiting user go for P6.)**

## Red lines (never)

- Never use Fastboot to write the 20 GiB `userdata` (it previously reported
  `OKAY` while silently dropping tail data).
- Never reuse an old run's Windows bundle identity for a new run.
- Before every write: re-read the device GPT read-only; verify model, LUN,
  sector size, start sector, count, image size and SHA-256.
- Only the verified official Windows Firehose programmer may be used; Linux
  `qdl`/`edl.py` has no verified write path on this device.
- Never write `persist`, `modemst`, `fsg`, `proinfo`, `lenovolock`, `xbl`; never
  re-unlock the bootloader.
- Never format/factory-reset `userdata` in Android recovery (it is the Linux
  root filesystem).
- Without a complete Android recovery package, slot-switching is not a recovery
  plan; `super` and `userdata` are shared state.
- Kernel candidates never go to P5/P6 without passing the kernel-side gate and
  without the main project's recovery discipline.

## Controlled flash procedure (P6, after P5 prep)

1. Only the verified Windows official Firehose route writes `userdata`.
2. Send exactly one `sparse=false` precise program operation.
3. Do not reset immediately after writing; run the 10-point readback first.
4. After readback `10/10`, enter Fastboot and handle GRUB/boot/slot per audit
   conclusions.

## Current P5 bundle (run 30730513005, READY 2026-08-02)

Windows-side bundle at `builds/flash-bundles/TB321FU-tablet-kde-run-30730513005/`:

- `images/` — `rootfs.img.7z`, `grub-fat.img.7z`, `boot.img.7z` (raw SHAs
  `c4efa7ce…` / `7378dc11…` / `45f923bc…` match ARTIFACT-IDENTITY)
- `firehose/` — `program-userdata-raw-20g-arch.xml` (LUN0/4096B/start
  `3613096`/count `5242880`/end `8855975`/sparse=false), `read-gpts-prearch.xml`
  (LUN0-5), `read-userdata-10point.xml` (10×64 sectors, 0–18 GiB)
- `known-gpt/` — LUN0-5 primary GPT baselines (2026-07-19 verified)
- `EXPECTED-READBACK-SHA256.tsv` — 10-point expected hashes, **header
  `offset<TAB>filename<TAB>sha256` required by Verify-Readback.ps1**
- `scripts/` — Verify-Bundle / Prepare-Images / Verify-TB321FUGpt /
  Verify-Readback
- `BUNDLE-SHA256SUMS.txt` — SHA-256 of every bundle member (Verify-Bundle
  consumes it); local verification 19/19 PASS

Verified on 2026-08-02: 10-point readback expected hashes recomputed from the
source rootfs raw = 10/10 MATCH; boot/grub 7z extract to the expected raw SHAs;
live read-only GPT re-acquire matches known-gpt baselines.

## Recovery boundaries (see `RECOVERY.md`)

- Fastboot may query device state and write the verified 96 MiB `boot.img` and
  256 MiB `super`.
- Fastboot must NOT write the 20 GiB rootfs.
- Kubuntu 26.04 remains the verified rollback baseline (historical 2026-07-21); the device currently runs author Arch Linux ARM (2026-08-02).

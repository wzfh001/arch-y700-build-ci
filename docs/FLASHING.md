# Flashing gate

This repository does not authorize a device write merely because an artifact
exists. Flash preparation starts only after P0-P4 are complete.

## Stop before any write unless all are true

- model is TB321FU and the device identity belongs to this experiment
- rootfs, GRUB, boot, and DTB belong to the same commit and workflow run
- archive, raw-image, and offline-audit checks are all PASS
- GPT was re-read from this device and CRC, LUN, sector size, start, count, and
  image size match the candidate-specific plan
- the matching official TB321FU/SM8650 programmer hash is verified
- recovery computer, cable, power, logs, and support-bundle plan are ready
- the user has reviewed the exact destructive target and explicitly confirmed

## Permanent prohibitions

- Never use Fastboot to write the 20 GiB `userdata` raw image.
- Never format/factory-reset Linux `userdata` from Android recovery.
- Never reuse old GPT numbers, XML, programmer identity, or artifact hashes.
- Never write protected calibration or boot-chain partitions named in the
  project stop lines.

The only historically verified large-image route is the matching Windows
Firehose workflow with `sparse=false`, followed before reset by the defined
ten-point readback. Candidate XML and commands are generated only in P5 after
all identities are known; generic write commands intentionally do not live in
this document.

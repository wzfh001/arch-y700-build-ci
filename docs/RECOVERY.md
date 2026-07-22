# Recovery boundary

Recovery capability is a prerequisite for hardware experiments.

## Verified historical recovery

- Matching TB321FU/SM8650 official Windows Firehose tooling restored a 20 GiB
  raw ext4 image to `userdata`.
- Ten readback windows from 0 through 18 GiB matched the source before reset.
- The original GRUB image then booted the recovered Kubuntu filesystem.

These facts apply only to the device/GPT/programmer identity recorded in the
archived 2026-07-19 evidence. They are not reusable write parameters.

## Current limits

- No complete Android restore set is recorded for all shared partitions.
- Slot switching is not an Android recovery plan because `super` and
  `userdata` are shared.
- Linux Firehose tools have not replaced the verified Windows route.
- Camera and suspend testing cannot proceed without working rescue and logs.

## Before a future candidate

Re-read GPT, verify the official service package/programmer, create one
candidate-specific recovery bundle, prepare the ten-point readback table, and
record how to reach Fastboot/9008 and where every raw log will be saved.

#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)

fail() {
  printf 'project governance test failure: %s\n' "$*" >&2
  exit 1
}

for path in \
  docs/STATUS.md \
  docs/ROADMAP.md \
  docs/BUILD.md \
  docs/FLASHING.md \
  docs/RECOVERY.md \
  docs/TROUBLESHOOTING.md \
  docs/EXPERIMENT-LOG.md \
  docs/RISK-REGISTER.md \
  .github/ISSUE_TEMPLATE/hardware-bug.yml \
  .github/ISSUE_TEMPLATE/build-task.yml \
  .github/ISSUE_TEMPLATE/feature.yml \
  validation/_template/hardware.yaml; do
  [ -s "$REPO_ROOT/$path" ] || fail "missing or empty governance file: $path"
done

grep -Fq 'Current device OS: recovered Kubuntu 26.04 ARM64 baseline' \
  "$REPO_ROOT/docs/STATUS.md" || \
  fail 'STATUS.md does not identify the current recovered Kubuntu baseline'
grep -Fq 'Never use Fastboot to write the 20 GiB `userdata` raw image.' \
  "$REPO_ROOT/docs/FLASHING.md" || \
  fail 'FLASHING.md does not preserve the Fastboot userdata stop line'
grep -Fq 'A retry must cite the old experiment' \
  "$REPO_ROOT/docs/TROUBLESHOOTING.md" || \
  fail 'TROUBLESHOOTING.md permits evidence-free retries'

for state in VERIFIED PARTIAL BROKEN UNTESTED OUT-OF-SCOPE; do
  grep -Fq "\`$state\`" "$REPO_ROOT/docs/STATUS.md" || \
    fail "STATUS.md does not define $state"
done

grep -Fq 'Commit `d480039` addresses only' "$REPO_ROOT/docs/STATUS.md" || \
  fail 'STATUS.md does not identify the ConfigFS-only fix commit'
grep -Fq 'first layer.' "$REPO_ROOT/docs/STATUS.md" || \
  fail 'STATUS.md does not preserve the ConfigFS fix boundary'
grep -Fq 'never use Fastboot for the 20 GiB userdata image' \
  "$REPO_ROOT/docs/EXPERIMENT-LOG.md" || \
  fail 'historical Fastboot failure is not recorded'
grep -Fq '| R-001 | P0 |' "$REPO_ROOT/docs/RISK-REGISTER.md" || \
  fail 'destructive-write risk is not registered'
grep -Fq '| R-008 | P1 |' "$REPO_ROOT/docs/RISK-REGISTER.md" || \
  fail 'support-bundle credential risk is not registered'

template="$REPO_ROOT/validation/_template/hardware.yaml"
for field in \
  'rootfs_sha256:' \
  'grub_sha256:' \
  'boot_sha256:' \
  'dtb_sha256:' \
  'gpt_evidence:' \
  'readback:' \
  'support_bundle:' \
  'usb_acm:' \
  'usb_ncm:' \
  'bluetooth_nap:' \
  'wifi:' \
  'landscape_touch:' \
  'display_120hz:' \
  'microphone:' \
  'charging:'; do
  grep -Fq "$field" "$template" || fail "hardware template is missing $field"
done

if grep -RIEq --include='*.sh' --include='*.py' \
  'fastboot[[:space:]]+flash[[:space:]]+userdata' \
  "$REPO_ROOT/scripts" "$REPO_ROOT/profiles"; then
  fail 'executable source contains a forbidden Fastboot userdata command'
fi

printf 'PROJECT_GOVERNANCE=PASS\n'

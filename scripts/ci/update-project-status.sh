#!/usr/bin/env bash
# Regenerate the human-readable project status documents from committed facts.
#
# Usage:
#   scripts/ci/update-project-status.sh            # refresh docs/STATUS.md + docs/ROADMAP.md
#   scripts/ci/update-project-status.sh --check    # verify docs are up to date (exit 1 if stale)
#
# Facts come from committed docs/templates/*.template.md plus the pinned values
# below. After any status change (P/K phase flip, new artifact run, new audit
# ID), edit the values below and run this script, then commit the regenerated
# docs.

set -euo pipefail

cd "$(dirname "$0")/../.."

check_mode=0
if [[ "${1:-}" == "--check" ]]; then
  check_mode=1
fi

now=$(TZ=Asia/Shanghai date +%Y-%m-%d)
head_short=$(git rev-parse --short HEAD)

# --- Pinned facts (single source of truth for generated docs) ---------------
# Keep in sync with .github/workflows/build-kernel.yml and
# build-rootfs-and-grub.yml and the kernel project plan.
export P4_STATUS="${P4_STATUS:-BLOCKED}"
export K8_STATUS="${K8_STATUS:-BLOCKED}"
export KERNEL_RUN="${KERNEL_RUN:-30704468188}"
export KERNEL_IMAGE_SHA="${KERNEL_IMAGE_SHA:-6e6d939eb25eb497c705d9779cfedbb165f708507741407e4b2bf8b86e5dc819}"
export KERNEL_DTB_SHA="${KERNEL_DTB_SHA:-6f0707cde854db33bb3d092f4d57765a5108717ad65ad97182e603c2cc808f54}"
export KERNEL_CONFIG_SHA="${KERNEL_CONFIG_SHA:-36997050c94bd8bfd91cd8d850cc602a24c59f561b55010a6eccfcf43817f40f}"
export KERNEL_MODULES_SHA="${KERNEL_MODULES_SHA:-a3e5c0ce420997a873b42810d0ed932a48be113671ba98cccfbf4c1e92b89542}"
export BOOT_CANDIDATE_SHA="${BOOT_CANDIDATE_SHA:-dade9ac5b2de4673cbe7eb248c918efd534de8f8a2281fdbb24cfdca3610a7a5}"
export ROOTFS_RAW_SHA="${ROOTFS_RAW_SHA:-6d1af258405cb1edefe5d43b2a94d3568c6e098c573aaddef867b914d8e9f2d7}"
export GRUB_RAW_SHA="${GRUB_RAW_SHA:-13747e8638e8932de2a392358ffa5cfd4844ddb2f9309ac8dde9dbc2249898fd}"
export DATE="$now"
export HEAD="$head_short"

render() {
  local template="$1" out="$2"
  python3 - "$template" "$out" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding='utf-8').read()
for key in ('DATE','HEAD','P4_STATUS','K8_STATUS','KERNEL_RUN',
            'KERNEL_IMAGE_SHA','KERNEL_DTB_SHA','KERNEL_CONFIG_SHA',
            'KERNEL_MODULES_SHA','BOOT_CANDIDATE_SHA','ROOTFS_RAW_SHA','GRUB_RAW_SHA'):
    text = text.replace('@' + key + '@', os.environ[key])
open(dst, 'w', encoding='utf-8').write(text)
PY
}

render docs/templates/STATUS.template.md docs/STATUS.md
render docs/templates/ROADMAP.template.md docs/ROADMAP.md

if [[ $check_mode -eq 1 ]]; then
  if ! git diff --quiet -- docs/STATUS.md docs/ROADMAP.md; then
    echo "docs/STATUS.md or docs/ROADMAP.md are out of date; run scripts/ci/update-project-status.sh" >&2
    exit 1
  fi
  echo "project status docs are up to date"
else
  echo "regenerated docs/STATUS.md and docs/ROADMAP.md (HEAD=$head_short)"
fi

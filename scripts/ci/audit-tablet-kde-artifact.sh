#!/usr/bin/env bash
# Offline P4 audit for a tablet-kde CI artifact ZIP.
# Usage:
#   audit-tablet-kde-artifact.sh <main-zip> <workdir> [expected-prefix]
# Example:
#   audit-tablet-kde-artifact.sh \
#     /mnt/game/TB321FU-tablet-kde-run-30730513005.zip \
#     /mnt/game/.TB321FU-tablet-kde-run-30730513005-audit \
#     TB321FU-archlinuxarm-plasma-aarch64
#
# Checks (subset of docs/evidence/20260802-tablet-kde-p4/AUDIT-CHECKLIST.md):
#   ZIP size/hash (from gh run metadata when passed), unzip -t, inner SHA256SUMS,
#   7z t, raw rootfs SHA, e2fsck, grub FAT fsck, boot 7z t.
# Emits evidence lines to stdout and writes an EVIDENCE file in workdir.
set -euo pipefail

zip="$1"; work="$2"; prefix="${3:-TB321FU-archlinuxarm-plasma-aarch64}"
# Accept either the artifact ZIP itself or a directory already extracted by
# `gh run download` (which unzips artifacts automatically).
if [ -f "$zip" ]; then
  zip_mode=1
elif [ -d "$zip" ]; then
  zip_mode=0
else
  echo "missing main zip/dir: $zip" >&2; exit 2
fi
mkdir -p "$work"/{downloads,extract,evidence}

evidence="$work/evidence/P4-AUDIT-$(date +%Y%m%d)-EVIDENCE.txt"
exec > >(tee "$evidence")

echo "=== AUDIT $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "input: $zip"
if [ "$zip_mode" = 1 ]; then
  echo "size: $(stat -c%s "$zip")"
  sha256sum "$zip" | tee /dev/stderr
  echo "-- unzip -t --"
  unzip -t "$zip" | tail -2
  archive_root="$work/extract"
  rm -rf "$archive_root"; mkdir -p "$archive_root"
  unzip -q "$zip" -d "$archive_root"
else
  echo "mode: already-extracted artifact dir (gh run download unzips)"
  echo "size(on disk): $(du -sb "$zip" | cut -f1)"
  archive_root="$zip"
fi

echo "-- inner SHA256SUMS (find all) --"
find "$archive_root" -name SHA256SUMS.txt -o -name '*.SHA256SUMS' | while read -r f; do
  echo "## $f"
  # release-level SHA256SUMS.txt references paths relative to the artifact root
  if [ "$(basename "$f")" = "SHA256SUMS.txt" ]; then
    ( cd "$archive_root" && sha256sum -c "$(realpath --relative-to="$archive_root" "$f")" 2>&1 | tail -4 )
  else
    ( cd "$(dirname "$f")" && sha256sum -c "$(basename "$f")" 2>&1 | tail -3 )
  fi
done
rootfs_7z=$(find "$archive_root" -name '*-rootfs.img.7z' | head -1)
grub_7z=$(find "$archive_root" -name '*-grub*.7z' -o -name '*-grub-fat.img.7z' | head -1)
boot_7z=$(find "$archive_root" -name 'boot.img.7z' | head -1)

for a in "$rootfs_7z" "$grub_7z" "$boot_7z"; do
  echo "-- 7z t $(basename "$a") --"
  7z t "$a" | tail -2
done

echo "-- rootfs raw sha --"
7z x -y -o"$work/extract/ci-rootfs" "$rootfs_7z" >/dev/null
rootfs_raw=$(find "$work/extract/ci-rootfs" -name '*.img' -type f | head -1)
echo "rootfs_raw=$rootfs_raw"
sha256sum "$rootfs_raw"
echo "-- e2fsck --"
e2fsck -fn "$rootfs_raw" | tail -3 || true

echo "-- grub --"
7z x -y -o"$work/extract/ci-grub" "$grub_7z" >/dev/null
grub_raw=$(find "$work/extract/ci-grub" -name '*.img' -type f | head -1)
sha256sum "$grub_raw"
fsck.fat -n "$grub_raw" 2>&1 | tail -3 || true

echo "-- boot --"
7z x -y -o"$work/extract/ci-boot" "$boot_7z" >/dev/null
boot_raw=$(find "$work/extract/ci-boot" -name '*.img' -type f | head -1)
sha256sum "$boot_raw"

echo "=== AUDIT CHECKLIST: outer ZIP / rootfs / grub / boot — run verbatim checks above ==="
echo "evidence=$evidence"

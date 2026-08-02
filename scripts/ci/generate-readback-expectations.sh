#!/usr/bin/env bash
# Generate 10-point readback SHA expectations for a rootfs raw image.
# Usage: generate-readback-expectations.sh <rootfs-raw> <out.tsv>
# Matches the old P5 bundle layout: offsets 0..18 GiB every 2 GiB,
# 64 sectors per point (each 4096 B).
set -euo pipefail

raw="$1"; out="$2"
[ -f "$raw" ] || { echo "missing raw image: $raw" >&2; exit 2; }
size=$(stat -c%s "$raw")
[ "$size" -eq 21474836480 ] || { echo "unexpected raw size: $size (expect 21474836480)" >&2; exit 2; }

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf 'offset\tfilename\tsha256\n' > "$tmp"
for gi in 0 2 4 6 8 10 12 14 16 18; do
  offset=$((gi * 1024 * 1024 * 1024))
  # 64 sectors * 4096 bytes
  dd if="$raw" bs=4096 skip=$((offset / 4096)) count=64 status=none 2>/dev/null \
    | sha256sum | awk -v g="$gi" '{ printf "%02dGiB\treadback-%02dGiB.bin\t%s\n", g, g, $1 }' >> "$tmp"
done
cp "$tmp" "$out"
echo "readback expectations: $out"
cat "$out"

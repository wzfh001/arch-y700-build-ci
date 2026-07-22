#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
OVERLAP="$REPO_ROOT/profiles/tablet-niri/bluetooth-firmware-arch-overlap.tsv"
DEVICE_ARCHIVE=${1:-${TB321FU_DEVICE_ARCHIVE_FIXTURE:-}}
LOCK_ARCHIVE=${2:-${TB321FU_PACMAN_LOCK_ARCHIVE_FIXTURE:-}}

die() {
  printf 'TB321FU firmware collision audit failure: %s\n' "$*" >&2
  exit 1
}

[ -n "$DEVICE_ARCHIVE" ] || die 'device archive fixture is required'
[ -n "$LOCK_ARCHIVE" ] || die 'pacman lock archive fixture is required'
[ -f "$DEVICE_ARCHIVE" ] || die "device archive fixture does not exist: $DEVICE_ARCHIVE"
[ -f "$LOCK_ARCHIVE" ] || die "pacman lock archive fixture does not exist: $LOCK_ARCHIVE"
[ -s "$OVERLAP" ] || die 'static overlap evidence is missing'

device_sha=$(sha256sum "$DEVICE_ARCHIVE" | awk '{print $1}')
[ "$device_sha" = 047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04 ] || \
  die "device archive SHA-256 differs: $device_sha"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-firmware-audit.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/device-archive" "$tmp/device" "$tmp/lock"

bsdtar -xpf "$DEVICE_ARCHIVE" -C "$tmp/device-archive"
device_deb="$tmp/device-archive/y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb"
[ -f "$device_deb" ] || die 'fixed device overlay package is missing'
device_deb_sha=$(sha256sum "$device_deb" | awk '{print $1}')
[ "$device_deb_sha" = 9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc ] || \
  die "device overlay package SHA-256 differs: $device_deb_sha"
ar p "$device_deb" data.tar.xz | bsdtar -xpf - -C "$tmp/device" ./usr/lib/firmware/qca

mapfile -t locked_firmware_paths < <(
  bsdtar -tf "$LOCK_ARCHIVE" | \
    rg '/linux-firmware[^/]*\.pkg\.tar\.xz$' | LC_ALL=C sort
)
[ "${#locked_firmware_paths[@]}" -gt 0 ] || die 'lock archive contains no linux-firmware package'
for path in "${locked_firmware_paths[@]}"; do
  bsdtar -xpf "$LOCK_ARCHIVE" -C "$tmp/lock" "$path"
done

python3 - "$tmp/device/usr/lib/firmware/qca" "$tmp/lock" "$OVERLAP" <<'PY'
from __future__ import annotations

import hashlib
import pathlib
import stat
import sys

source = pathlib.Path(sys.argv[1])
lock_root = pathlib.Path(sys.argv[2])
overlap_file = pathlib.Path(sys.argv[3])

def member(path: pathlib.Path) -> dict[str, str | int]:
    st = path.lstat()
    mode = format(stat.S_IMODE(st.st_mode), "04o")
    if stat.S_ISLNK(st.st_mode):
        target = path.readlink().as_posix()
        return {"type": "symlink", "mode": mode, "size": len(target), "value": target}
    if not stat.S_ISREG(st.st_mode):
        raise SystemExit(f"unsupported firmware member type: {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return {"type": "regular", "mode": mode, "size": st.st_size, "value": digest}

source_members = {p.name: member(p) for p in source.iterdir() if p.is_file() or p.is_symlink()}
if len(source_members) != 62:
    raise SystemExit(f"device QCA member count is {len(source_members)}, expected 62")
if any(v["type"] != "regular" for v in source_members.values()):
    raise SystemExit("device QCA overlay contains a non-regular member")
if {v["mode"] for v in source_members.values()} != {"0777"}:
    raise SystemExit("device QCA source mode set changed; review the normalizer boundary")

generic_members: dict[str, list[tuple[str, dict[str, str | int]]]] = {}
for package_root in lock_root.rglob("*.pkg.tar.xz"):
    package_name = package_root.name
    qca = package_root.parent / (package_name + ".qca-stage")
    # The package archive is immutable; extraction is confined to this audit tree.
    import subprocess
    listing = subprocess.run(
        ["bsdtar", "-tf", str(package_root)], text=True,
        stdout=subprocess.PIPE, check=True,
    ).stdout.splitlines()
    qca_entries = [x for x in listing if x.startswith("usr/lib/firmware/qca/")]
    if not qca_entries:
        continue
    qca.mkdir()
    subprocess.run(
        ["bsdtar", "-xpf", str(package_root), "-C", str(qca), "usr/lib/firmware/qca"],
        check=True,
    )
    qca_root = qca / "usr/lib/firmware/qca"
    for path in qca_root.rglob("*"):
        if path.is_dir() and not path.is_symlink():
            continue
        rel = path.relative_to(qca_root).as_posix()
        generic_members.setdefault(rel, []).append((package_name, member(path)))

owners = {name for values in generic_members.values() for name, _ in values}
if owners != {"linux-firmware-atheros-20260622-1-any.pkg.tar.xz"}:
    raise SystemExit(f"unexpected locked QCA owners: {sorted(owners)}")
regular_count = sum(1 for values in generic_members.values() for _, data in values if data["type"] == "regular")
symlink_count = sum(1 for values in generic_members.values() for _, data in values if data["type"] == "symlink")
if (regular_count, symlink_count) != (95, 48):
    raise SystemExit(f"locked QCA member counts changed: regular={regular_count} symlink={symlink_count}")

overlap_names = sorted(set(source_members) & set(generic_members))
if overlap_names != ["hmtbtfw20.tlv", "hmtnv20.b10f", "hmtnv20.b112", "hmtnv20.bin"]:
    raise SystemExit(f"unexpected QCA overlap set: {overlap_names}")

rows = []
for line in overlap_file.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#") or line.startswith("generic_") or line.startswith("relative_path"):
        continue
    fields = line.split("\t")
    if len(fields) != 9:
        raise SystemExit(f"malformed static overlap row: {line}")
    rows.append(fields)
if len(rows) != 4:
    raise SystemExit(f"static overlap evidence has {len(rows)} rows, expected 4")

for row in rows:
    rel, d_type, d_mode, d_size, d_value, a_type, a_mode, a_size, a_value = row
    name = rel.rsplit("/", 1)[-1]
    if name not in overlap_names:
        raise SystemExit(f"static overlap names an unexpected member: {rel}")
    actual_device = source_members[name]
    actual_arch = generic_members[name][0][1]
    expected_device = {"type": d_type, "mode": d_mode, "size": int(d_size), "value": d_value}
    expected_arch = {"type": a_type, "mode": a_mode, "size": int(a_size.split("->", 1)[0]), "value": a_value}
    if actual_device != expected_device:
        raise SystemExit(f"device evidence differs for {rel}: {actual_device} != {expected_device}")
    if actual_arch["type"] == "symlink":
        expected_arch["value"] = a_size.split("->", 1)[1]
    if actual_arch != expected_arch:
        raise SystemExit(f"Arch evidence differs for {rel}: {actual_arch} != {expected_arch}")
    if actual_device["type"] == actual_arch["type"] == "regular" and actual_device["value"] == actual_arch["value"]:
        raise SystemExit(f"device and generic bytes unexpectedly match: {rel}")

print("device_archive_sha256=" + "047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04")
print("device_overlay_package_sha256=" + "9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc")
print("device_qca_regular_members=62")
print("locked_qca_regular_members=95")
print("locked_qca_symlink_members=48")
print("qca_overlap_members=4")
print("generic_owner=linux-firmware-atheros")
print("BT_FIRMWARE_COLLISION_AUDIT=PASS")
PY

#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
OVERLAP="$REPO_ROOT/profiles/tablet-niri/device-archive-arch-overlap.tsv"
DEVICE_ARCHIVE=${1:-${TB321FU_DEVICE_ARCHIVE_FIXTURE:-}}
LOCK_ARCHIVE=${2:-${TB321FU_PACMAN_LOCK_ARCHIVE_FIXTURE:-}}

die() {
  printf 'TB321FU device archive collision audit failure: %s\n' "$*" >&2
  exit 1
}

[ -n "$DEVICE_ARCHIVE" ] || die 'device archive fixture is required'
[ -n "$LOCK_ARCHIVE" ] || die 'pacman lock archive fixture is required'
[ -f "$DEVICE_ARCHIVE" ] || die "device archive fixture does not exist: $DEVICE_ARCHIVE"
[ -f "$LOCK_ARCHIVE" ] || die "pacman lock archive fixture does not exist: $LOCK_ARCHIVE"
[ -s "$OVERLAP" ] || die 'static full-overlap evidence is missing'

device_sha=$(sha256sum "$DEVICE_ARCHIVE" | awk '{print $1}')
[ "$device_sha" = 047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04 ] || \
  die "device archive SHA-256 differs: $device_sha"
lock_sha=$(sha256sum "$LOCK_ARCHIVE" | awk '{print $1}')
[ "$lock_sha" = 8c9328b682f13e9c518e28a6bcb7b3f0b620273ed94859dec7e4d9f4798c3fb0 ] || \
  die "pacman lock archive SHA-256 differs: $lock_sha"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-device-overlap.XXXXXX")
trap 'find "$tmp" -depth -delete' EXIT
mkdir -p "$tmp/outer" "$tmp/device"
bsdtar -xpf "$DEVICE_ARCHIVE" -C "$tmp/outer"

actual_outer=$(find "$tmp/outer" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
expected_outer=$'y700-compat1-extra-rootfs-overlay.tar.gz\ny700-daily-kernel-modules_0.1+20260624-201420_arm64.deb\ny700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb'
[ "$actual_outer" = "$expected_outer" ] || die 'fixed device archive top-level member list changed'

for deb in "$tmp/outer"/*.deb; do
  ar p "$deb" data.tar.xz | bsdtar -xpf - -C "$tmp/device"
done
bsdtar -xpf "$tmp/outer/y700-compat1-extra-rootfs-overlay.tar.gz" -C "$tmp/device"

python3 - "$tmp/device" "$LOCK_ARCHIVE" "$OVERLAP" <<'PY'
from __future__ import annotations

import hashlib
import io
import pathlib
import stat
import sys
import tarfile

device_root = pathlib.Path(sys.argv[1])
lock_archive = pathlib.Path(sys.argv[2])
overlap_file = pathlib.Path(sys.argv[3])


def fs_member(path: pathlib.Path) -> tuple[str, str, int, str] | None:
    st = path.lstat()
    mode = format(stat.S_IMODE(st.st_mode), "04o")
    if stat.S_ISLNK(st.st_mode):
        target = path.readlink().as_posix()
        return ("symlink", mode, len(target), target)
    if stat.S_ISREG(st.st_mode):
        return ("regular", mode, st.st_size, hashlib.sha256(path.read_bytes()).hexdigest())
    return None


metadata: dict[str, str] = {}
expected_rows: dict[str, tuple[str, ...]] = {}
for line in overlap_file.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    fields = tuple(line.split("\t"))
    if fields[0] == "status":
        if len(fields) != 12:
            raise SystemExit("static overlap header has the wrong field count")
        continue
    if len(fields) == 2:
        key, value = fields
        if key in metadata:
            raise SystemExit(f"duplicate static overlap metadata: {key}")
        metadata[key] = value
        continue
    if len(fields) != 12:
        raise SystemExit(f"malformed static overlap row: {line}")
    status, path = fields[:2]
    if status not in {"identical", "MISMATCH"}:
        raise SystemExit(f"invalid static overlap status: {status}")
    if path in expected_rows:
        raise SystemExit(f"duplicate static overlap path: {path}")
    expected_rows[path] = fields

required_metadata = {
    "device_archive_sha256": "047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04",
    "device_member_count": "2335",
    "lock_archive_sha256": "8c9328b682f13e9c518e28a6bcb7b3f0b620273ed94859dec7e4d9f4798c3fb0",
    "lock_manifest_sha256": "a2e554de57011255bc25dc86b7c388982fe4ccadfa5cd2131d0bc817eb996bfd",
    "locked_package_count": "723",
    "intersect_path_count": "16",
    "identical_count": "10",
    "mismatch_count": "6",
}
if metadata != required_metadata:
    raise SystemExit(f"static overlap metadata differs: {metadata}")

device: dict[str, tuple[str, str, int, str]] = {}
for path in device_root.rglob("*"):
    data = fs_member(path)
    if data is not None:
        device[path.relative_to(device_root).as_posix()] = data
if len(device) != 2335:
    raise SystemExit(f"device member count changed: {len(device)}")

hits: dict[str, list[tuple[str, str, tuple[str, str, int, str]]]] = {}
package_count = 0
lock_manifest = None
with tarfile.open(lock_archive, mode="r:") as outer:
    for outer_member in outer:
        if outer_member.name.endswith("/SHA256SUMS") and outer_member.isfile():
            stream = outer.extractfile(outer_member)
            if stream is None:
                raise SystemExit("cannot read lock SHA256SUMS")
            lock_manifest = hashlib.sha256(stream.read()).hexdigest()
        if not outer_member.isfile() or not outer_member.name.endswith(".pkg.tar.xz"):
            continue
        package_count += 1
        package_name = pathlib.PurePosixPath(outer_member.name).name
        stream = outer.extractfile(outer_member)
        if stream is None:
            raise SystemExit(f"cannot read locked package: {outer_member.name}")
        package_bytes = stream.read()
        package_sha = hashlib.sha256(package_bytes).hexdigest()
        with tarfile.open(fileobj=io.BytesIO(package_bytes), mode="r:xz") as package:
            for member in package:
                name = member.name.removeprefix("./").lstrip("/")
                if name not in device:
                    continue
                mode = format(member.mode & 0o7777, "04o")
                if member.isreg():
                    member_stream = package.extractfile(member)
                    if member_stream is None:
                        raise SystemExit(f"cannot read {package_name}:{name}")
                    value = hashlib.sha256(member_stream.read()).hexdigest()
                    data = ("regular", mode, member.size, value)
                elif member.issym():
                    data = ("symlink", mode, len(member.linkname), member.linkname)
                else:
                    raise SystemExit(f"unsupported locked overlap type: {package_name}:{name}")
                hits.setdefault(name, []).append((package_name, package_sha, data))

if package_count != 723:
    raise SystemExit(f"locked package count changed: {package_count}")
if lock_manifest != required_metadata["lock_manifest_sha256"]:
    raise SystemExit(f"lock manifest SHA-256 changed: {lock_manifest}")
if len(hits) != 16:
    raise SystemExit(f"intersect path count changed: {len(hits)}")
if any(len(owners) != 1 for owners in hits.values()):
    raise SystemExit("an intersecting path has zero or multiple locked package owners")

actual_rows: dict[str, tuple[str, ...]] = {}
identical = mismatch = 0
for path, owners in hits.items():
    package_name, package_sha, arch = owners[0]
    source = device[path]
    status = "identical" if source == arch else "MISMATCH"
    if status == "identical":
        identical += 1
    else:
        mismatch += 1
    actual_rows[path] = (
        status,
        path,
        source[0],
        source[1],
        str(source[2]),
        source[3],
        package_name,
        package_sha,
        arch[0],
        arch[1],
        str(arch[2]),
        arch[3],
    )

if (identical, mismatch) != (10, 6):
    raise SystemExit(f"overlap result counts changed: identical={identical} mismatch={mismatch}")
if actual_rows != expected_rows:
    missing = sorted(set(expected_rows) - set(actual_rows))
    extra = sorted(set(actual_rows) - set(expected_rows))
    changed = sorted(path for path in set(actual_rows) & set(expected_rows) if actual_rows[path] != expected_rows[path])
    raise SystemExit(f"static full-overlap evidence differs: missing={missing} extra={extra} changed={changed}")

print("device_members=2335")
print("locked_packages=723")
print("intersect_paths=16")
print("identical=10")
print("mismatch=6")
print("DEVICE_ARCHIVE_COLLISION_AUDIT=PASS")
PY

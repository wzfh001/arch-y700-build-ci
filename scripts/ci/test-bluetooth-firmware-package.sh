#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"
GRUB_SCRIPT="$SCRIPT_DIR/build-grub-image.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/build-rootfs-and-grub.yml"
MANIFEST="$REPO_ROOT/profiles/tablet-niri/bluetooth-firmware.sha256"
OVERLAP="$REPO_ROOT/profiles/tablet-niri/bluetooth-firmware-arch-overlap.tsv"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-bluetooth-firmware-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'Bluetooth firmware package test failure: %s\n' "$*" >&2
  exit 1
}

[ -s "$MANIFEST" ] || fail 'Bluetooth firmware manifest is missing'
[ "$(wc -l < "$MANIFEST")" -eq 62 ] || fail 'Bluetooth firmware manifest does not contain 62 files'
[ -s "$OVERLAP" ] || fail 'offline Arch overlap evidence is missing'

python3 - "$MANIFEST" "$OVERLAP" <<'PY'
import pathlib
import re
import sys

manifest = pathlib.Path(sys.argv[1])
rows = []
for line in manifest.read_text(encoding="utf-8").splitlines():
    digest, path = line.split(maxsplit=1)
    assert re.fullmatch(r"[0-9a-f]{64}", digest)
    assert re.fullmatch(r"usr/lib/firmware/qca/[A-Za-z0-9._-]+", path)
    rows.append((digest, path))
assert len(rows) == len({path for _, path in rows}) == 62
names = {path.rsplit("/", 1)[-1]: digest for digest, path in rows}
assert names["hmtbtfw20.tlv"] == "b4e7f61e7dd090e56811860a7781ff3b0ce8e87cc0480feaab34bf4f614308c5"
assert names["hmtnv20_Kirby_prc.bin"] == "513bef77998f239be1ec5e853f1a85f96f52b6d024073685f929a37011e55d4b"
assert names["hmtnv20_Kirby_row.bin"] == "528927549e154f50e90c3986d0bf24d404d204ac0e701d3d2a4449a66a5915b1"
overlap = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
for name in ("hmtbtfw20.tlv", "hmtnv20.b10f", "hmtnv20.b112", "hmtnv20.bin"):
    assert f"usr/lib/firmware/qca/{name}\t" in overlap
assert "generic_package_owner\tlinux-firmware-atheros" in overlap
assert "generic_package_sha256\td000b5fe8765ccd757bee17d8537aaeb065eda9f58870ec40be9534c5c5745c2" in overlap
PY

for required in \
  "TB321FU_BLUETOOTH_FIRMWARE_MANIFEST=\"\$REPO_ROOT/profiles/tablet-niri/bluetooth-firmware.sha256\"" \
  "TB321FU_BLUETOOTH_FIRMWARE_PACKAGE='tb321fu-bluetooth-firmware'" \
  "TB321FU_BLUETOOTH_FIRMWARE_SOURCE_PACKAGE='y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb'" \
  "TB321FU_BLUETOOTH_FIRMWARE_SOURCE_PACKAGE_SHA256='9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc'" \
  'firmware_search_path=/usr/lib/firmware/tb321fu' \
  '"$stage/usr/lib/firmware/tb321fu/$custom_relative"' \
  'runtime_requests=qca/hmtbtfw20.tlv,qca/hmtnv20_Kirby_prc.bin' \
  'generic_arch_package=linux-firmware-atheros-20260622-1-any' \
  'install_tb321fu_bluetooth_firmware_package'; do
  grep -Fq "$required" "$BUILD_SCRIPT" || fail "build policy is missing: $required"
done
grep -Fq 'firmware_class.path=/usr/lib/firmware/tb321fu' "$GRUB_SCRIPT" || \
  fail 'GRUB default lacks the TB321FU firmware search path'
grep -Fq 'STABLEARGS=drm_client_lib.active=none firmware_class.path=/usr/lib/firmware/tb321fu' \
  "$WORKFLOW" || fail 'workflow boot config lacks the TB321FU firmware search path'

extract_shell_function() {
  local name=$1
  awk -v signature="$name() {" '
    $0 == signature { copying = 1 }
    copying { print }
    copying && $0 == "}" { exit }
  ' "$BUILD_SCRIPT"
}

archive=${TB321FU_DEVICE_ARCHIVE_FIXTURE:-}
if [ -n "$archive" ]; then
  [ -f "$archive" ] || fail "archive fixture does not exist: $archive"
  [ "$(sha256sum "$archive" | awk '{print $1}')" = \
    047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04 ] || \
    fail 'archive fixture hash differs from the fixed input'
  mkdir -p "$tmp/archive" "$tmp/payload" "$tmp/work"
  tar -xzf "$archive" --no-same-owner --no-same-permissions -C "$tmp/archive"
  deb="$tmp/archive/y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb"
  [ "$(sha256sum "$deb" | awk '{print $1}')" = \
    9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc ] || \
    fail 'overlay package hash differs from the fixed input'
  ar p "$deb" data.tar.xz | tar -xJf - -C "$tmp/payload" ./usr/lib/firmware/qca
  (cd "$tmp/payload" && sha256sum -c "$MANIFEST") >/dev/null || \
    fail 'fixed archive QCA firmware bytes differ from the repository manifest'
  find "$tmp/payload/usr/lib/firmware/qca" -type f -exec chmod 0644 {} +

  ci_die() { fail "$*"; }
  installed_package=
  install_arch_native_stage_package() { installed_package=$1; }
  eval "$(extract_shell_function install_tb321fu_bluetooth_firmware_package)"
  DESKTOP_PROFILE=tablet-niri
  arch_import_stage="$tmp/payload"
  arch_bluetooth_firmware_stage="$tmp/work/tb321fu-bluetooth-firmware-stage"
  arch_import_sources="$tmp/work/import-sources.tsv"
  TB321FU_BLUETOOTH_FIRMWARE_PACKAGE='tb321fu-bluetooth-firmware'
  TB321FU_DEVICE_ARCHIVE_URL='https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-device-debs-20260624-201420-compat1.tar.gz'
  TB321FU_DEVICE_ARCHIVE_SHA256='047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04'
  TB321FU_BLUETOOTH_FIRMWARE_SOURCE_PACKAGE='y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb'
  TB321FU_BLUETOOTH_FIRMWARE_SOURCE_PACKAGE_SHA256='9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc'
  TB321FU_BLUETOOTH_FIRMWARE_MANIFEST="$MANIFEST"
  printf 'deb:%s:%s\n' "$TB321FU_BLUETOOTH_FIRMWARE_SOURCE_PACKAGE" \
    "$TB321FU_BLUETOOTH_FIRMWARE_SOURCE_PACKAGE_SHA256" > "$arch_import_sources"
  install_tb321fu_bluetooth_firmware_package
  [ "$installed_package" = tb321fu-bluetooth-firmware ] || \
    fail 'staging did not invoke the dedicated native Bluetooth package path'
  [ ! -e "$arch_import_stage/usr/lib/firmware/qca/hmtbtfw20.tlv" ] || \
    fail 'device QCA firmware remained in the generic import stage'
  package_stage="$arch_bluetooth_firmware_stage"
  [ -f "$package_stage/usr/lib/firmware/tb321fu/qca/hmtbtfw20.tlv" ] || \
    fail 'device QCA controller image was not staged on the independent path'
  [ -f "$package_stage/usr/lib/firmware/tb321fu/qca/hmtnv20_Kirby_prc.bin" ] || \
    fail 'device QCA NVM variant was not staged on the independent path'
  [ "$(stat -c '%a' "$package_stage/usr/lib/firmware/tb321fu/qca/hmtbtfw20.tlv")" = 644 ] || \
    fail 'staged QCA controller image mode is not 0644'
  (
    cd "$package_stage"
    sha256sum -c ./usr/share/tb321fu-bluetooth-firmware/SHA256SUMS
  ) >/dev/null || fail 'staged native Bluetooth package manifest did not verify'
  [ "$(wc -l < "$package_stage/usr/share/tb321fu-bluetooth-firmware/SHA256SUMS")" -eq 62 ] || \
    fail 'staged native Bluetooth package manifest does not contain 62 files'
  grep -Fxq 'collision_policy=independent-search-path;generic-qca-paths-retained' \
    "$package_stage/usr/share/tb321fu-bluetooth-firmware/SOURCE.txt" || \
    fail 'Bluetooth package provenance does not record collision policy'
  printf 'BLUETOOTH_FIRMWARE_ARCHIVE=PASS\n'
fi

printf 'BLUETOOTH_FIRMWARE_PACKAGE=PASS\n'

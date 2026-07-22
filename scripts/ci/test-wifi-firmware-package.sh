#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"
GRUB_SCRIPT="$SCRIPT_DIR/build-grub-image.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/build-rootfs-and-grub.yml"
MANIFEST="$REPO_ROOT/profiles/tablet-niri/wifi-firmware.sha256"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-wifi-firmware-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'Wi-Fi firmware package test failure: %s\n' "$*" >&2
  exit 1
}

[ -s "$MANIFEST" ] || fail 'firmware manifest is missing'
[ "$(wc -l < "$MANIFEST")" -eq 6 ] || fail 'firmware manifest does not contain six files'
python3 - "$MANIFEST" <<'PY'
import pathlib
import re
import sys

manifest = pathlib.Path(sys.argv[1])
rows = []
for line in manifest.read_text(encoding="utf-8").splitlines():
    digest, path = line.split(maxsplit=1)
    assert re.fullmatch(r"[0-9a-f]{64}", digest)
    assert re.fullmatch(
        r"usr/lib/firmware/ath12k/WCN7850/hw2\.0/[A-Za-z0-9._-]+", path
    )
    rows.append((digest, path))
assert len(rows) == len({path for _, path in rows}) == 6
expected = {
    "Notice.txt.zst": "56d67526832a0a5901cd3a42062b9cfbd402c21c410f030ec207597e43fb40eb",
    "amss.bin.zst": "8ee4da36cc820396a29f68d38632f47af7a2f6db142fa509a0091d542cb40e1f",
    "board-2.bin": "c896bc7782e252aa915849d5c9c47d109ecfe9f0fc5650fe771f7ba8f8eb77fb",
    "board-2.bin.zst": "0713e03f82a343d01b009ec78ce926869555e1ebd9ebb0d47f31a19ffd52b22d",
    "m3.bin.zst": "603cb5f7a6d70ed23d6511038dfa9144c7992065d7c6c50d530985f4bacc5d10",
    "regdb.bin": "84b55a5691d02b78b96face90b2ba69718a2e617434ffb888a4943b9d2ada5a5",
}
for name, digest in expected.items():
    assert (digest, f"usr/lib/firmware/ath12k/WCN7850/hw2.0/{name}") in rows
assert {path.rsplit("/", 1)[-1] for _, path in rows} == set(expected)
PY

for required in \
  "TB321FU_DEVICE_ARCHIVE_SHA256='047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04'" \
  "TB321FU_WIFI_OVERLAY_DEB_SHA256='9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc'" \
  'sha256sum -c "$TB321FU_WIFI_FIRMWARE_MANIFEST"' \
  'tb321fu-wifi-firmware' \
  'usr/lib/firmware/tb321fu/$custom_relative' \
  'rm -f -- "$arch_import_stage/$relative"' \
  'linux-firmware-atheros'; do
  grep -Fq "$required" "$BUILD_SCRIPT" || fail "build policy is missing: $required"
done
grep -Fq 'firmware_class.path=/usr/lib/firmware/tb321fu' "$GRUB_SCRIPT" || \
  fail 'GRUB default lacks the TB321FU firmware search path'
grep -Fq 'STABLEARGS=drm_client_lib.active=none firmware_class.path=/usr/lib/firmware/tb321fu' \
  "$WORKFLOW" || fail 'workflow boot config lacks the TB321FU firmware search path'
grep -Fq 'verifying imported path already owned by native Arch package' "$BUILD_SCRIPT" || \
  fail 'Arch-owned import collisions are still discarded without comparison'

archive=${TB321FU_DEVICE_ARCHIVE_FIXTURE:-}
if [ -n "$archive" ]; then
  [ -f "$archive" ] || fail "archive fixture does not exist: $archive"
  [ "$(sha256sum "$archive" | awk '{print $1}')" = \
    047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04 ] || \
    fail 'archive fixture hash differs from the fixed input'
  mkdir -p "$tmp/archive" "$tmp/payload"
  tar -xzf "$archive" --no-same-owner --no-same-permissions -C "$tmp/archive"
  deb="$tmp/archive/y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb"
  [ "$(sha256sum "$deb" | awk '{print $1}')" = \
    9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc ] || \
    fail 'overlay package hash differs from the fixed input'
  ar p "$deb" data.tar.xz | tar -xJf - -C "$tmp/payload" ./usr/lib/firmware/ath12k/WCN7850/hw2.0
  (cd "$tmp/payload" && sha256sum -c "$MANIFEST") >/dev/null || \
    fail 'fixed archive firmware bytes differ from the repository manifest'
  [ "$(stat -c '%s' "$tmp/payload/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin")" = 202148 ] || \
    fail 'fixed archive board-2.bin size is not the Kubuntu-proven size'

  extract_shell_function() {
    local name=$1
    awk -v signature="$name() {" '
      $0 == signature { copying = 1 }
      copying { print }
      copying && $0 == "}" { exit }
    ' "$BUILD_SCRIPT"
  }
  ci_die() { fail "$*"; }
  installed_package=
  install_arch_native_stage_package() {
    installed_package=$1
  }
  eval "$(extract_shell_function install_tb321fu_wifi_firmware_package)"
  DESKTOP_PROFILE=tablet-niri
  arch_import_stage="$tmp/payload"
  work_dir="$tmp/work"
  arch_import_sources="$tmp/import-sources.tsv"
  TB321FU_DEVICE_ARCHIVE_URL='https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-device-debs-20260624-201420-compat1.tar.gz'
  TB321FU_DEVICE_ARCHIVE_SHA256='047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04'
  TB321FU_WIFI_OVERLAY_DEB='y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb'
  TB321FU_WIFI_OVERLAY_DEB_SHA256='9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc'
  TB321FU_WIFI_FIRMWARE_MANIFEST="$MANIFEST"
  find "$arch_import_stage/usr/lib/firmware/ath12k/WCN7850/hw2.0" -type f \
    -exec chmod 0644 {} +
  printf 'deb:%s:%s\n' "$TB321FU_WIFI_OVERLAY_DEB" \
    "$TB321FU_WIFI_OVERLAY_DEB_SHA256" > "$arch_import_sources"
  install_tb321fu_wifi_firmware_package
  [ "$installed_package" = tb321fu-wifi-firmware ] || \
    fail 'staging did not invoke the dedicated native package path'
  [ ! -e "$arch_import_stage/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin" ] || \
    fail 'device board file remained in the generic import stage'
  package_stage="$work_dir/tb321fu-wifi-firmware-stage"
  [ -f "$package_stage/usr/lib/firmware/tb321fu/ath12k/WCN7850/hw2.0/board-2.bin" ] || \
    fail 'device board file was not staged on the independent firmware path'
  (
    cd "$package_stage"
    sha256sum -c ./usr/share/tb321fu-wifi-firmware/SHA256SUMS
  ) >/dev/null || fail 'staged native package manifest did not verify'
  printf 'WIFI_FIRMWARE_ARCHIVE=PASS\n'
fi

printf 'WIFI_FIRMWARE_PACKAGE=PASS\n'

#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/build-rootfs-and-grub.yml"
SOURCE_MANIFEST="$REPO_ROOT/profiles/tablet-niri/alsa-ucm-source.sha256"
PACKAGE_MANIFEST="$REPO_ROOT/profiles/tablet-niri/alsa-ucm-package.sha256"
OVERLAP="$REPO_ROOT/profiles/tablet-niri/device-archive-arch-overlap.tsv"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-alsa-ucm-test.XXXXXX")
trap 'find "$tmp" -depth -delete' EXIT

fail() {
  printf 'ALSA UCM package test failure: %s\n' "$*" >&2
  exit 1
}

[ -s "$SOURCE_MANIFEST" ] || fail 'ALSA UCM source manifest is missing'
[ -s "$PACKAGE_MANIFEST" ] || fail 'ALSA UCM package manifest is missing'
[ -s "$OVERLAP" ] || fail 'full device/archive overlap evidence is missing'
[ "$(wc -l < "$SOURCE_MANIFEST")" -eq 13 ] || fail 'source manifest does not contain 13 files'
[ "$(wc -l < "$PACKAGE_MANIFEST")" -eq 13 ] || fail 'package manifest does not contain 13 files'

python3 - "$SOURCE_MANIFEST" "$PACKAGE_MANIFEST" "$OVERLAP" <<'PY'
import pathlib
import re
import sys

source_path, package_path, overlap_path = map(pathlib.Path, sys.argv[1:])

def read_manifest(path: pathlib.Path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        digest, relative = line.split(maxsplit=1)
        assert re.fullmatch(r"[0-9a-f]{64}", digest)
        assert relative.startswith("usr/share/alsa/ucm2/")
        rows.append((digest, relative))
    assert len(rows) == len({relative for _, relative in rows}) == 13
    return rows

source = read_manifest(source_path)
package = read_manifest(package_path)
source_by_path = {relative: digest for digest, relative in source}
package_by_path = {relative: digest for digest, relative in package}
assert source_by_path["usr/share/alsa/ucm2/codecs/wcd939x/HeadphoneEnableSeq.conf"] == \
    "333c56a133d260f696fbc817dfb7760e7c75619d0540bf62128527dd9a7438f5"
assert package_by_path["usr/share/alsa/ucm2/codecs/tb321fu-wcd939x/HeadphoneEnableSeq.conf"] == \
    "333c56a133d260f696fbc817dfb7760e7c75619d0540bf62128527dd9a7438f5"
assert package_by_path["usr/share/alsa/ucm2/LenovoY700TB321/HiFi.conf"] == \
    "532fc575b07dccda542087e0637fa8a57cf54a4e9377cdfeff13505acb736e68"
assert package_by_path["usr/share/alsa/ucm2/LenovoY700TB321/LenovoY700TB321.conf"] == \
    "9250b8fe2987da1d084c32d3d262f108cfdc7ddfbd66844e4f3f630fdd4d38d5"
assert sum("/LenovoY700TB321/" in relative for relative in source_by_path) == 2
assert sum("/codecs/wcd939x/" in relative for relative in source_by_path) == 11
assert sum("/LenovoY700TB321/" in relative for relative in package_by_path) == 2
assert sum("/codecs/tb321fu-wcd939x/" in relative for relative in package_by_path) == 11

rows = []
metadata = {}
for line in overlap_path.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    fields = line.split("\t")
    if fields[0] == "status":
        continue
    if len(fields) == 2:
        metadata[fields[0]] = fields[1]
    else:
        assert len(fields) == 12
        rows.append(fields)
assert metadata["device_member_count"] == "2335"
assert metadata["locked_package_count"] == "723"
assert metadata["intersect_path_count"] == "16"
assert metadata["identical_count"] == "10"
assert metadata["mismatch_count"] == "6"
assert len(rows) == 16
ucm = next(row for row in rows if row[1].endswith("/HeadphoneEnableSeq.conf"))
assert ucm == [
    "MISMATCH",
    "usr/share/alsa/ucm2/codecs/wcd939x/HeadphoneEnableSeq.conf",
    "regular",
    "0644",
    "276",
    "333c56a133d260f696fbc817dfb7760e7c75619d0540bf62128527dd9a7438f5",
    "alsa-ucm-conf-1.2.16.1-1-any.pkg.tar.xz",
    "7c8748eb29e8bdd1632071410aab1ed19edc0f48ffbe47375a51b5a4bdef8db8",
    "regular",
    "0644",
    "282",
    "f8b856216adf46b1b6a7e9e3cbd85fd50a6446c77a9ac7bb0a60dfd189adbbc0",
]
PY

for required in \
  'TB321FU_ALSA_UCM_SOURCE_MANIFEST="$REPO_ROOT/profiles/tablet-niri/alsa-ucm-source.sha256"' \
  'TB321FU_ALSA_UCM_PACKAGE_MANIFEST="$REPO_ROOT/profiles/tablet-niri/alsa-ucm-package.sha256"' \
  "TB321FU_ALSA_UCM_PACKAGE='tb321fu-alsa-ucm'" \
  "TB321FU_ALSA_UCM_GENERIC_PACKAGE='alsa-ucm-conf-1.2.16.1-1-any'" \
  "TB321FU_ALSA_UCM_GENERIC_PACKAGE_SHA256='7c8748eb29e8bdd1632071410aab1ed19edc0f48ffbe47375a51b5a4bdef8db8'" \
  'destination=${relative/usr\/share\/alsa\/ucm2\/codecs\/wcd939x/usr\/share\/alsa\/ucm2\/codecs\/tb321fu-wcd939x}' \
  "sed -i 's#/codecs/wcd939x/#/codecs/tb321fu-wcd939x/#g'" \
  'transformed_include_count=7' \
  'install_tb321fu_alsa_ucm_package'; do
  grep -Fq "$required" "$BUILD_SCRIPT" || fail "build policy is missing: $required"
done
grep -Fq 'bash scripts/ci/test-alsa-ucm-package.sh' "$WORKFLOW" || \
  fail 'workflow does not run the ALSA UCM source gate'
grep -Fq 'bash -n scripts/ci/audit-tb321fu-device-archive-collisions.sh' "$WORKFLOW" || \
  fail 'workflow does not syntax-gate the full device archive collision audit'

extract_shell_function() {
  local name=$1
  awk -v signature="$name() {" '
    $0 == signature { copying = 1 }
    copying { print }
    copying && $0 == "}" { exit }
  ' "$BUILD_SCRIPT"
}

archive=${TB321FU_DEVICE_ARCHIVE_FIXTURE:-}
lock=${TB321FU_PACMAN_LOCK_ARCHIVE_FIXTURE:-}
if [ -n "$archive" ]; then
  [ -f "$archive" ] || fail "device archive fixture does not exist: $archive"
  [ "$(sha256sum "$archive" | awk '{print $1}')" = \
    047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04 ] || \
    fail 'device archive fixture hash differs from the fixed input'
  mkdir -p "$tmp/archive" "$tmp/payload" "$tmp/work"
  bsdtar -xpf "$archive" -C "$tmp/archive"
  deb="$tmp/archive/y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb"
  [ "$(sha256sum "$deb" | awk '{print $1}')" = \
    9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc ] || \
    fail 'overlay package hash differs from the fixed input'
  ar p "$deb" data.tar.xz | bsdtar -xpf - -C "$tmp/payload" \
    ./usr/share/alsa/ucm2/LenovoY700TB321 ./usr/share/alsa/ucm2/codecs/wcd939x
  (cd "$tmp/payload" && sha256sum -c "$SOURCE_MANIFEST") >/dev/null || \
    fail 'fixed archive ALSA UCM bytes differ from the repository source manifest'

  ci_die() { fail "$*"; }
  installed_package=
  install_arch_native_stage_package() { installed_package=$1; }
  arch_chroot() { cat >/dev/null; }
  eval "$(extract_shell_function install_tb321fu_alsa_ucm_package)"
  DESKTOP_PROFILE=tablet-niri
  arch_import_stage="$tmp/payload"
  arch_alsa_ucm_stage="$tmp/work/tb321fu-alsa-ucm-stage"
  arch_import_sources="$tmp/work/import-sources.tsv"
  TB321FU_ALSA_UCM_SOURCE_MANIFEST="$SOURCE_MANIFEST"
  TB321FU_ALSA_UCM_PACKAGE_MANIFEST="$PACKAGE_MANIFEST"
  TB321FU_ALSA_UCM_PACKAGE='tb321fu-alsa-ucm'
  TB321FU_ALSA_UCM_SOURCE_PACKAGE='y700-daily-rootfs-overlay_0.1+20260624-201420_arm64.deb'
  TB321FU_ALSA_UCM_SOURCE_PACKAGE_SHA256='9b45ab04d455cfcc24ed40779e9522930543330151c254e87a2aee7f381db5bc'
  TB321FU_ALSA_UCM_GENERIC_PACKAGE='alsa-ucm-conf-1.2.16.1-1-any'
  TB321FU_ALSA_UCM_GENERIC_PACKAGE_SHA256='7c8748eb29e8bdd1632071410aab1ed19edc0f48ffbe47375a51b5a4bdef8db8'
  TB321FU_DEVICE_ARCHIVE_URL='https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-device-debs-20260624-201420-compat1.tar.gz'
  TB321FU_DEVICE_ARCHIVE_SHA256='047c1baccc420f1c28bf6d761cfc811dd7aeccfcbab6d03746ca01daf6cdfe04'
  printf 'deb:%s:%s\n' "$TB321FU_ALSA_UCM_SOURCE_PACKAGE" \
    "$TB321FU_ALSA_UCM_SOURCE_PACKAGE_SHA256" > "$arch_import_sources"
  install_tb321fu_alsa_ucm_package

  [ "$installed_package" = tb321fu-alsa-ucm ] || \
    fail 'staging did not invoke the dedicated native package path'
  [ ! -e "$arch_import_stage/usr/share/alsa/ucm2/LenovoY700TB321/HiFi.conf" ] || \
    fail 'device UCM profile remained in the generic import stage'
  [ ! -e "$arch_import_stage/usr/share/alsa/ucm2/codecs/wcd939x/HeadphoneEnableSeq.conf" ] || \
    fail 'device WCD939x sequence remained in the generic import stage'
  package_stage="$arch_alsa_ucm_stage"
  (cd "$package_stage" && sha256sum -c ./usr/share/tb321fu-alsa-ucm/SHA256SUMS) >/dev/null || \
    fail 'staged ALSA UCM package manifest did not verify'
  cmp -s "$SOURCE_MANIFEST" "$package_stage/usr/share/tb321fu-alsa-ucm/SOURCE-SHA256SUMS" || \
    fail 'staged ALSA UCM source manifest differs'
  if grep -R -F -q '/codecs/wcd939x/' \
    "$package_stage/usr/share/alsa/ucm2/LenovoY700TB321"; then
    fail 'staged ALSA UCM profile retains a generic codec include'
  fi
  new_count=$(awk '
    { count += gsub("/codecs/tb321fu-wcd939x/", "") }
    END { print count + 0 }
  ' "$package_stage/usr/share/alsa/ucm2/LenovoY700TB321/HiFi.conf" \
    "$package_stage/usr/share/alsa/ucm2/LenovoY700TB321/LenovoY700TB321.conf")
  [ "$new_count" -eq 7 ] || fail "staged ALSA UCM include count is $new_count"

  if [ -n "$lock" ]; then
    [ -f "$lock" ] || fail "pacman lock fixture does not exist: $lock"
    [ "$(sha256sum "$lock" | awk '{print $1}')" = \
      8c9328b682f13e9c518e28a6bcb7b3f0b620273ed94859dec7e4d9f4798c3fb0 ] || \
      fail 'pacman lock fixture hash differs from the committed lock'
    mkdir -p "$tmp/lock" "$tmp/ucm-root"
    pkgpath=TB321FU-tablet-niri-pacman-lock/repo/aarch64/extra/alsa-ucm-conf-1.2.16.1-1-any.pkg.tar.xz
    bsdtar -xpf "$lock" -C "$tmp/lock" "$pkgpath"
    pkg="$tmp/lock/$pkgpath"
    [ "$(sha256sum "$pkg" | awk '{print $1}')" = \
      7c8748eb29e8bdd1632071410aab1ed19edc0f48ffbe47375a51b5a4bdef8db8 ] || \
      fail 'locked alsa-ucm-conf package hash differs'
    bsdtar -xpf "$pkg" -C "$tmp/ucm-root" usr/share/alsa/ucm2
    generic="$tmp/ucm-root/usr/share/alsa/ucm2/codecs/wcd939x/HeadphoneEnableSeq.conf"
    [ "$(sha256sum "$generic" | awk '{print $1}')" = \
      f8b856216adf46b1b6a7e9e3cbd85fd50a6446c77a9ac7bb0a60dfd189adbbc0 ] || \
      fail 'locked generic WCD939x headphone sequence differs'
    cp -a "$package_stage/usr/share/alsa/ucm2/LenovoY700TB321" \
      "$tmp/ucm-root/usr/share/alsa/ucm2/"
    cp -a "$package_stage/usr/share/alsa/ucm2/codecs/tb321fu-wcd939x" \
      "$tmp/ucm-root/usr/share/alsa/ucm2/codecs/"
    printf 'open LenovoY700TB321\ndump text\n' | \
      ALSA_CONFIG_UCM2="$tmp/ucm-root/usr/share/alsa/ucm2" \
      alsaucm -n -b - >/dev/null || fail 'combined locked/custom UCM tree does not parse'
    [ "$(sha256sum "$generic" | awk '{print $1}')" = \
      f8b856216adf46b1b6a7e9e3cbd85fd50a6446c77a9ac7bb0a60dfd189adbbc0 ] || \
      fail 'custom package parsing overwrote the generic WCD939x sequence'
    printf 'ALSA_UCM_LOCKED_PARSE=PASS\n'
  fi
  printf 'ALSA_UCM_ARCHIVE=PASS\n'
fi

printf 'ALSA_UCM_PACKAGE=PASS\n'

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
SEED_SCRIPT="$SCRIPT_DIR/build-pacman-package-lock.sh"
VERIFY_SCRIPT="$SCRIPT_DIR/verify-pacman-package-lock.sh"
BUILD_SCRIPT="$SCRIPT_DIR/build-arch-rootfs-image.sh"
BUILD_WORKFLOW="$REPO_ROOT/.github/workflows/build-rootfs-and-grub.yml"
LOCK_PROFILE="$REPO_ROOT/profiles/tablet-niri/pacman-lock.env"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-pacman-lock-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'pacman lock test failure: %s\n' "$*" >&2
  exit 1
}

. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/package-list.sh"
DESKTOP_PROFILE=tablet-niri
INSTALL_FCITX5_CHINESE=1
INSTALL_FIREFOX=1
INSTALL_CAMERA_APPS=0
BUILD_TB321FU_GPU_SENSOR=0
PACKAGE_LIST=
build_package_list > "$tmp/requested.txt"
[ -s "$tmp/requested.txt" ] || fail 'shared package request list is empty'
[ "$(sort "$tmp/requested.txt" | uniq -d | wc -l)" -eq 0 ] || fail 'shared package request list contains duplicates'
for package in niri linux-firmware networkmanager firefox fcitx5; do
  grep -Fxq "$package" "$tmp/requested.txt" || fail "shared package request is missing: $package"
done

lock="$tmp/lock"
mkdir -p "$lock/repo/aarch64/core" "$lock/repo/aarch64/extra"
printf 'fixture core db\n' > "$lock/repo/aarch64/core/core.db"
printf 'fixture extra db\n' > "$lock/repo/aarch64/extra/extra.db"
package_name=fake-1-1-aarch64.pkg.tar.xz
printf 'fixture package\n' > "$lock/repo/aarch64/core/$package_name"
printf 'fixture signature\n' > "$lock/repo/aarch64/core/$package_name.sig"
cp "$tmp/requested.txt" "$lock/requested-packages.txt"
printf 'base 1-1\n' > "$lock/expected-installed-packages.txt"
package_sha=$(sha256sum "$lock/repo/aarch64/core/$package_name" | awk '{print $1}')
printf 'repo\tfilename\tsha256\ncore\t%s\t%s\n' "$package_name" "$package_sha" > "$lock/PACKAGE-FILES.tsv"
requested_sha=$(sha256sum "$lock/requested-packages.txt" | awk '{print $1}')
installed_sha=$(sha256sum "$lock/expected-installed-packages.txt" | awk '{print $1}')
cat > "$lock/LOCK-INFO.env" <<INFO
lock_schema=1
arch=aarch64
rootfs_sha256=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
requested_packages_sha256=$requested_sha
expected_installed_packages_sha256=$installed_sha
seed_run_id=123456789
seed_commit=0123456789abcdef0123456789abcdef01234567
INFO
(cd "$lock" && find . -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 sha256sum) > "$lock/SHA256SUMS"
manifest_sha=$(sha256sum "$lock/SHA256SUMS" | awk '{print $1}')
bash "$VERIFY_SCRIPT" "$lock" "$manifest_sha" \
  3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a \
  "$tmp/requested.txt" >/dev/null || fail 'valid package lock fixture was rejected'
printf 'tamper\n' >> "$lock/repo/aarch64/core/$package_name"
if bash "$VERIFY_SCRIPT" "$lock" "$manifest_sha" \
  3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a \
  "$tmp/requested.txt" >/dev/null 2>&1; then
  fail 'tampered package lock fixture was accepted'
fi

for token in \
  'pacman -Syu --print' \
  'url.sig' \
  'file:///run/tb321fu-pacman-lock/repo/$arch/$repo' \
  'arch_chroot_offline' \
  'expected-installed-packages.txt'; do
  grep -Fq "$token" "$SEED_SCRIPT" || fail "seed policy is missing: $token"
done
for token in \
  'PACMAN_PACKAGE_LOCK_MANIFEST_SHA256' \
  'verify-pacman-package-lock.sh' \
  'arch_chroot_offline /usr/bin/pacman -Syu' \
  'locked pacman transaction produced a different installed package set'; do
  grep -Fq "$token" "$BUILD_SCRIPT" || fail "locked build policy is missing: $token"
done
grep -Fq 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093' "$BUILD_WORKFLOW" ||
  fail 'build workflow does not use the pinned cross-run artifact downloader'
grep -Fq "release_tag == '__PACMAN_LOCK_SEED__'" "$BUILD_WORKFLOW" ||
  fail 'existing dispatch workflow lacks the reserved lock-only mode'
grep -Fq 'name: tb321fu-pacman-lock-${{ github.run_id }}' "$BUILD_WORKFLOW" ||
  fail 'seed workflow artifact identity is not tied to the seed run'
python3 "$SCRIPT_DIR/check-action-pins.py" "$BUILD_WORKFLOW" >/dev/null

if [ -f "$LOCK_PROFILE" ]; then
  for field in repository run_id artifact_name manifest_sha256 rootfs_sha256; do
    grep -Eq "^${field}=.+$" "$LOCK_PROFILE" || fail "pinned lock profile is missing: $field"
  done
  grep -Eq '^run_id=[0-9]+$' "$LOCK_PROFILE" || fail 'pinned lock run id is invalid'
  grep -Eq '^artifact_name=[A-Za-z0-9_.-]+$' "$LOCK_PROFILE" || fail 'pinned lock artifact name is invalid'
  grep -Eq '^manifest_sha256=[0-9a-f]{64}$' "$LOCK_PROFILE" || fail 'pinned lock manifest SHA-256 is invalid'
  printf 'PACMAN_PACKAGE_LOCK_PIN=PASS\n'
else
  printf 'PACMAN_PACKAGE_LOCK_PIN=UNSET\n'
fi

printf 'PACMAN_PACKAGE_LOCK_SOURCE=PASS\n'

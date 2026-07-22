#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'pacman package lock verification failure: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 4 ] || fail "usage: $0 LOCK_DIR MANIFEST_SHA256 ROOTFS_SHA256 REQUESTED_PACKAGES_FILE"
lock_dir=$(realpath -e -- "$1") || fail "lock directory does not exist"
expected_manifest_sha=$2
expected_rootfs_sha=$3
requested_file=$(realpath -e -- "$4") || fail "requested package file does not exist"

[[ $expected_manifest_sha =~ ^[0-9a-f]{64}$ ]] || fail 'invalid lock manifest SHA-256'
if [[ ! $expected_rootfs_sha =~ ^[0-9a-f]{64}$ ]]; then
  printf -v expected_rootfs_sha_quoted '%q' "$expected_rootfs_sha"
  fail "invalid rootfs SHA-256 (length=${#expected_rootfs_sha}, shell=$expected_rootfs_sha_quoted)"
fi
[ -f "$lock_dir/SHA256SUMS" ] || fail 'lock SHA256SUMS is missing'
[ "$(sha256sum "$lock_dir/SHA256SUMS" | awk '{print $1}')" = "$expected_manifest_sha" ] ||
  fail 'lock manifest SHA-256 differs from the pinned value'

if find "$lock_dir" -type l -print -quit | grep -q .; then
  fail 'lock artifact contains a symlink'
fi
unsafe_path=0
while IFS= read -r -d '' relative; do
  relative=${relative#"$lock_dir"/}
  [[ -n "$relative" && "$relative" != /* && "$relative" != *..* &&
    "$relative" != *'$'* && "$relative" != *$'\n'* && "$relative" != *$'\r'* ]] ||
    unsafe_path=1
done < <(find "$lock_dir" -type f -print0)
[ "$unsafe_path" = 0 ] || fail 'lock artifact contains an unsafe relative path'

(cd "$lock_dir" && sha256sum -c SHA256SUMS) >/dev/null || fail 'lock member checksum mismatch'

info="$lock_dir/LOCK-INFO.env"
[ -f "$info" ] || fail 'LOCK-INFO.env is missing'
get_info() {
  local key=$1 value
  value=$(awk -F= -v wanted="$key" '$1 == wanted { print substr($0, length(wanted) + 2); found=1 } END { if (!found) exit 1 }' "$info") ||
    fail "lock metadata key is missing: $key"
  [[ $value != *$'\n'* && $value != *$'\r'* ]] || fail "lock metadata contains a newline: $key"
  printf '%s\n' "$value"
}

[ "$(get_info lock_schema)" = 1 ] || fail 'unsupported lock schema'
[ "$(get_info arch)" = aarch64 ] || fail 'lock architecture is not aarch64'
[ "$(get_info rootfs_sha256)" = "$expected_rootfs_sha" ] || fail 'lock rootfs SHA-256 does not match the selected rootfs'
[[ $(get_info seed_run_id) =~ ^[0-9]+$ ]] || fail 'lock seed run id is invalid'
[[ $(get_info seed_commit) =~ ^[0-9a-f]{40}$ ]] || fail 'lock seed commit is invalid'

[ -f "$lock_dir/requested-packages.txt" ] || fail 'requested package list is missing'
[ -f "$lock_dir/expected-installed-packages.txt" ] || fail 'expected installed package list is missing'
[ -s "$lock_dir/expected-installed-packages.txt" ] || fail 'expected installed package list is empty'
requested_sha=$(sha256sum "$lock_dir/requested-packages.txt" | awk '{print $1}')
[ "$requested_sha" = "$(sha256sum "$requested_file" | awk '{print $1}')" ] ||
  fail 'requested package list differs from the current profile'
[ "$(get_info requested_packages_sha256)" = "$requested_sha" ] ||
  fail 'requested package list metadata hash mismatch'
installed_sha=$(sha256sum "$lock_dir/expected-installed-packages.txt" | awk '{print $1}')
[ "$(get_info expected_installed_packages_sha256)" = "$installed_sha" ] ||
  fail 'expected installed package list metadata hash mismatch'

[ -d "$lock_dir/repo/aarch64/core" ] || fail 'locked core repository is missing'
[ -d "$lock_dir/repo/aarch64/extra" ] || fail 'locked extra repository is missing'
[ -d "$lock_dir/repo/aarch64/alarm" ] || fail 'locked alarm repository is missing'
[ -d "$lock_dir/repo/aarch64/aur" ] || fail 'locked aur repository is missing'
for db in core extra alarm aur; do
  [ -f "$lock_dir/repo/aarch64/$db/$db.db" ] || fail "locked $db database is missing"
done

package_rows=0
header=1
 [ -f "$lock_dir/PACKAGE-FILES.tsv" ] || fail 'PACKAGE-FILES.tsv is missing'
while IFS=$'\t' read -r repo filename digest; do
  if [ "$header" = 1 ]; then
    [ "$repo" = repo ] && [ "$filename" = filename ] && [ "$digest" = sha256 ] ||
      fail 'PACKAGE-FILES.tsv header is invalid'
    header=0
    continue
  fi
  [ -n "$repo" ] || fail 'empty package repository in PACKAGE-FILES.tsv'
  [[ $repo == core || $repo == extra || $repo == alarm || $repo == aur ]] ||
    fail "unsupported package repository: $repo"
  [[ $filename =~ ^[A-Za-z0-9][A-Za-z0-9+._@:-]*\.pkg\.tar\.(xz|zst|gz|bz2|lz4|lrz|lzo|Z)$ ]] ||
    fail "unsafe package filename: $filename"
  [[ $digest =~ ^[0-9a-f]{64}$ ]] || fail "invalid package digest: $filename"
  package="$lock_dir/repo/aarch64/$repo/$filename"
  [ -f "$package" ] || fail "package listed in lock is missing: $filename"
  [ "$(sha256sum "$package" | awk '{print $1}')" = "$digest" ] ||
    fail "package digest mismatch: $filename"
  [ -f "$package.sig" ] || fail "detached package signature is missing: $filename.sig"
  package_rows=$((package_rows + 1))
done < "$lock_dir/PACKAGE-FILES.tsv"
[ "$header" = 0 ] || fail 'PACKAGE-FILES.tsv contains no header'
[ "$package_rows" -gt 0 ] || fail 'PACKAGE-FILES.tsv is empty'

printf 'PACMAN_PACKAGE_LOCK=PASS\n'

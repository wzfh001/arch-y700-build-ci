#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"

ci_require_cmd realpath
ci_require_cmd find
ci_require_cmd tar
ci_require_cmd sha256sum

fail() {
  printf 'pacman lock archive failure: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 2 ] || fail "usage: $0 LOCK_DIR ARCHIVE_TAR"
lock_dir=$(realpath -e -- "$1") || fail "lock directory does not exist: $1"
[ -d "$lock_dir" ] || fail "lock path is not a directory: $lock_dir"

archive_parent=$(realpath -m -- "$(dirname -- "$2")") || fail "invalid archive parent: $2"
archive_name=$(basename -- "$2")
[[ $archive_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.tar$ ]] ||
  fail "invalid archive filename: $archive_name"
mkdir -p -- "$archive_parent"
archive="$archive_parent/$archive_name"
archive_sha="$archive.sha256"
case "$archive" in
  "$lock_dir"/*) fail 'archive output must be outside the lock directory' ;;
esac

lock_parent=$(dirname -- "$lock_dir")
lock_name=$(basename -- "$lock_dir")
[[ $lock_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
  fail "invalid lock directory name: $lock_name"

if find "$lock_dir" -type l -print -quit | grep -q .; then
  fail 'lock directory contains a symlink'
fi

epoch=$(ci_source_date_epoch)
tmp_archive="$archive.part.$$"
tmp_sha="$archive_sha.part.$$"
cleanup() {
  rm -f -- "$tmp_archive" "$tmp_sha"
}
trap cleanup EXIT

# Package filenames may contain a pacman epoch colon (for example 1:1.37.2-2).
# A single deterministic tar member preserves those names without asking the
# GitHub artifact service to treat them as host filesystem paths.
tar \
  --sort=name \
  --format=gnu \
  --mtime="@$epoch" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --mode='u+rwX,go+rX,go-w' \
  -C "$lock_parent" \
  -cf "$tmp_archive" "$lock_name"
mv -f -- "$tmp_archive" "$archive"

(cd -- "$archive_parent" && sha256sum -- "$archive_name") > "$tmp_sha"
mv -f -- "$tmp_sha" "$archive_sha"
printf 'PACMAN_PACKAGE_LOCK_ARCHIVE=%s\n' "$archive"

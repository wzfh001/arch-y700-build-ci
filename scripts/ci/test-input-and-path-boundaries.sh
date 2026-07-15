#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

expected=$'base\nlibfoo\npkg=1.2-3'
actual=$(ci_normalize_package_list $'base libfoo\npkg=1.2-3')
[ "$actual" = "$expected" ]
for hostile in '--config' 'lib*' '$(touch /tmp/not-run)' 'bad/token'; do
  if (ci_normalize_package_list "$hostile") >/dev/null 2>&1; then
    printf 'accepted hostile package token: %s\n' "$hostile" >&2
    exit 1
  fi
done

touch "$scratch/boot.img" "$scratch/rootfs.img"
ci_require_distinct_paths BOOT "$scratch/boot.img" ROOTFS "$scratch/rootfs.img" OUTPUT "$scratch/disk.img"
if (ci_require_distinct_paths BOOT "$scratch/boot.img" OUTPUT "$scratch/./boot.img") >/dev/null 2>&1; then
  echo 'accepted canonically identical paths' >&2
  exit 1
fi
ln "$scratch/boot.img" "$scratch/boot-hardlink.img"
if (ci_require_distinct_paths BOOT "$scratch/boot.img" OUTPUT "$scratch/boot-hardlink.img") >/dev/null 2>&1; then
  echo 'accepted hard-linked paths' >&2
  exit 1
fi

mkdir -p "$scratch/cleanup/.arch-rootfs-build.target/child"
cleanup_target=$(realpath -e "$scratch/cleanup/.arch-rootfs-build.target")
FAKE_MOUNTS=$cleanup_target
findmnt() { printf '%s\n' "$FAKE_MOUNTS"; }
if ci_safe_rmtree "$cleanup_target" "$scratch/cleanup" .arch-rootfs-build. >/dev/null 2>&1; then
  echo 'deleted a target that is itself a mount root' >&2
  exit 1
fi
test -d "$cleanup_target"
FAKE_MOUNTS=$cleanup_target/child
if ci_safe_rmtree "$cleanup_target" "$scratch/cleanup" .arch-rootfs-build. >/dev/null 2>&1; then
  echo 'deleted a target containing a descendant mount' >&2
  exit 1
fi
FAKE_MOUNTS=
ci_safe_rmtree "$cleanup_target" "$scratch/cleanup" .arch-rootfs-build.
test ! -e "$cleanup_target"

echo 'PASS input and filesystem path boundaries'

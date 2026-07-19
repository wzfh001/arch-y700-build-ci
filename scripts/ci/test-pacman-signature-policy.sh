#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
BUILD_SCRIPT=$SCRIPT_DIR/build-arch-rootfs-image.sh

ci_die() {
  printf '%s\n' "$*" >&2
  exit 1
}

arch_chroot() {
  case "$*" in
    '/usr/bin/pacman-conf SigLevel')
      if [ "${SCENARIO:-valid}" = weak-global ]; then
        printf '%s\n' PackageOptional PackageTrustAll DatabaseOptional DatabaseTrustedOnly
      else
        printf '%s\n' PackageRequired PackageTrustedOnly DatabaseOptional DatabaseTrustedOnly
      fi
      ;;
    '/usr/bin/pacman-conf --repo-list')
      printf '%s\n' core extra
      ;;
    '/usr/bin/pacman-conf -r core SigLevel')
      ;;
    '/usr/bin/pacman-conf -r extra SigLevel')
      if [ "${SCENARIO:-valid}" = weak-repo ]; then
        printf '%s\n' PackageOptional PackageTrustAll DatabaseOptional DatabaseTrustedOnly
      else
        printf '%s\n' PackageRequired PackageTrustedOnly DatabaseOptional DatabaseTrustedOnly
      fi
      ;;
    *)
      printf 'unexpected arch_chroot call: %s\n' "$*" >&2
      return 2
      ;;
  esac
}

source <(
  sed -n \
    '/^assert_pacman_remote_policy_tokens()/,/^apply_y700_firmware_fixes()/p' \
    "$BUILD_SCRIPT" | sed '$d'
)

SCENARIO=valid assert_arch_remote_signature_policy

if (SCENARIO=weak-global assert_arch_remote_signature_policy) >/dev/null 2>&1; then
  printf 'weak inherited global pacman policy was accepted\n' >&2
  exit 1
fi

if (SCENARIO=weak-repo assert_arch_remote_signature_policy) >/dev/null 2>&1; then
  printf 'weak repository pacman policy was accepted\n' >&2
  exit 1
fi

printf 'PACMAN_SIGNATURE_POLICY=PASS\n'

#!/usr/bin/env bash
set -euo pipefail

ci_log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

ci_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

ci_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || ci_die "required command not found: $1"
}

ci_bool() {
  case "${1:-}" in
    1|yes|true|on) return 0 ;;
    *) return 1 ;;
  esac
}

ci_abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$(pwd -P)" "$1" ;;
  esac
}

ci_validate_output_prefix() {
  local value=$1
  [[ ${#value} -le 64 && $value =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
    ci_die "invalid OUTPUT_PREFIX (1-64 characters; letters, digits, dot, underscore and hyphen only): $value"
}

ci_normalize_package_list() {
  local raw=${1-} line token
  local -a line_tokens=()
  while IFS= read -r line || [ -n "$line" ]; do
    line_tokens=()
    read -r -a line_tokens <<< "$line"
    for token in "${line_tokens[@]}"; do
      [[ ${#token} -le 128 && $token =~ ^[A-Za-z0-9][A-Za-z0-9+.:_@=-]*$ ]] ||
        ci_die "invalid package token: $token"
      printf '%s\n' "$token"
    done
  done <<< "$raw"
}

ci_resolve_path_for_comparison() {
  local path=$1 parent
  if [ -e "$path" ] || [ -L "$path" ]; then
    realpath -e -- "$path"
    return
  fi
  parent=$(realpath -e -- "$(dirname -- "$path")")
  printf '%s/%s\n' "$parent" "$(basename -- "$path")"
}

ci_require_distinct_paths() {
  local -a labels=() paths=() resolved=()
  local label path i j
  [ "$#" -ge 4 ] && [ $(( $# % 2 )) -eq 0 ] ||
    ci_die "ci_require_distinct_paths expects LABEL PATH pairs"
  while [ "$#" -gt 0 ]; do
    label=$1
    path=$2
    labels+=("$label")
    paths+=("$path")
    resolved+=("$(ci_resolve_path_for_comparison "$path")")
    shift 2
  done
  for ((i = 0; i < ${#paths[@]}; i++)); do
    for ((j = i + 1; j < ${#paths[@]}; j++)); do
      if [ "${resolved[i]}" = "${resolved[j]}" ] ||
         { [ -e "${paths[i]}" ] && [ -e "${paths[j]}" ] && [ "${paths[i]}" -ef "${paths[j]}" ]; }; then
        ci_die "${labels[i]} and ${labels[j]} must refer to distinct paths"
      fi
    done
  done
}

ci_source_date_epoch() {
  local epoch=${SOURCE_DATE_EPOCH:-0}
  [[ $epoch =~ ^[0-9]{1,10}$ ]] ||
    ci_die "SOURCE_DATE_EPOCH must be a decimal Unix timestamp: $epoch"
  printf '%s\n' "$epoch"
}

ci_iso8601_timestamp() {
  local epoch
  epoch=$(ci_source_date_epoch)
  date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
}

ci_normalize_fat_tree() {
  local root=$1
  local epoch
  [ -d "$root" ] || ci_die "FAT payload tree not found: $root"
  epoch=$(ci_source_date_epoch)
  if [ "$epoch" -lt 315532800 ]; then
    epoch=315532800
  fi
  find "$root" -xdev -exec touch -h -d "@$epoch" {} +
}

ci_e2fsck_repair() {
  local target=$1 rc
  if e2fsck -f -y -- "$target"; then
    rc=0
  else
    rc=$?
  fi
  case $rc in
    0|1) return 0 ;;
    *) ci_die "e2fsck failed for $target with status $rc" ;;
  esac
}

ci_mount_targets_below() {
  local root=$1
  ci_require_cmd findmnt
  findmnt -rn --raw -o TARGET | awk -v root="$root" \
    '$0 == root || index($0, root "/") == 1 { print length($0) "\t" $0 }' |
    sort -rn | cut -f2-
}

ci_unmount_tree() {
  local root=$1 target failed=0
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    if ! umount -- "$target"; then
      printf 'error: failed to unmount %s\n' "$target" >&2
      failed=1
    fi
  done < <(ci_mount_targets_below "$root")
  [ "$failed" -eq 0 ] || return 1
  [ -z "$(ci_mount_targets_below "$root")" ] || {
    printf 'error: mounts remain below %s\n' "$root" >&2
    return 1
  }
}

ci_validate_rootfs_overlay_tree() {
  local root=$1 relative
  [ -d "$root" ] || ci_die "rootfs overlay is not a directory: $root"
  for relative in dev proc sys run; do
    if [ -e "$root/$relative" ] || [ -L "$root/$relative" ]; then
      ci_die "rootfs overlay must not contain runtime path: $relative"
    fi
  done
}

ci_safe_rmtree() {
  local candidate=$1 parent=$2 prefix=$3 resolved resolved_parent
  [ -e "$candidate" ] || return 0
  resolved=$(realpath -e -- "$candidate")
  resolved_parent=$(realpath -e -- "$parent")
  [ "$(dirname -- "$resolved")" = "$resolved_parent" ] || {
    printf 'error: refusing cleanup outside expected parent: %s\n' "$resolved" >&2
    return 1
  }
  case $(basename -- "$resolved") in
    "$prefix"*) ;;
    *)
      printf 'error: refusing cleanup with unexpected basename: %s\n' "$resolved" >&2
      return 1
      ;;
  esac
  [ -z "$(ci_mount_targets_below "$resolved")" ] || {
    printf 'error: refusing to delete a tree containing active mounts: %s\n' "$resolved" >&2
    return 1
  }
  rm -rf -- "$resolved"
}

ci_verify_download() {
  local file=$1 verifier=$2 expected actual
  local -a primary_fingerprints=()
  case $verifier in
    sha256:*) expected=${verifier#sha256:} ;;
    [[:xdigit:]][[:xdigit:]][[:xdigit:]][[:xdigit:]]*) expected=$verifier ;;
    openpgp-fpr:*)
      expected=${verifier#openpgp-fpr:}
      [[ $expected =~ ^[A-Fa-f0-9]{40}$ ]] || ci_die "invalid OpenPGP fingerprint: $expected"
      ci_require_cmd gpg
      mapfile -t primary_fingerprints < <(
        gpg --batch --quiet --show-keys --with-colons "$file" 2>/dev/null |
          awk -F: '
            $1 == "pub" { want_primary_fpr=1; next }
            $1 == "sub" { want_primary_fpr=0; next }
            $1 == "fpr" && want_primary_fpr { print toupper($10); want_primary_fpr=0 }
          '
      )
      [ "${#primary_fingerprints[@]}" -eq 1 ] ||
        ci_die "OpenPGP input must contain exactly one primary key: $file"
      [ "${primary_fingerprints[0]}" = "${expected^^}" ] ||
        ci_die "OpenPGP fingerprint mismatch for $file"
      return
      ;;
    *) ci_die "unsupported or missing download verifier for $file" ;;
  esac
  [[ $expected =~ ^[A-Fa-f0-9]{64}$ ]] || ci_die "invalid SHA-256 verifier: $expected"
  actual=$(sha256sum "$file" | awk '{print $1}')
  [ "$actual" = "${expected,,}" ] || ci_die "SHA-256 mismatch for $file: expected ${expected,,}, got $actual"
}

ci_download() {
  local src=$1
  local dst=$2
  local verifier=${3:-}
  local tmp="${dst}.part.$$"
  rm -f -- "$tmp"
  case "$src" in
    https://*)
      [ -n "$verifier" ] || ci_die "remote download requires an explicit SHA-256 or OpenPGP fingerprint: $src"
      ci_require_cmd curl
      if ! curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 2 -o "$tmp" "$src"; then
        rm -f -- "$tmp"
        ci_die "download failed: $src"
      fi
      ;;
    http://*)
      ci_die "refusing insecure HTTP download: $src"
      ;;
    '')
      ci_die "empty download source for $dst"
      ;;
    *)
      [ -f "$src" ] || ci_die "local download source is not a regular file: $src"
      cp -- "$src" "$tmp"
      ;;
  esac
  if [ -n "$verifier" ]; then
    if ! (ci_verify_download "$tmp" "$verifier"); then
      rm -f -- "$tmp"
      ci_die "download verification failed: $src"
    fi
  fi
  mv -f -- "$tmp" "$dst"
}

ci_extract_archive() {
  local archive=$1
  local dest=$2
  local helper
  helper=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/safe-extract-archive.py
  ci_require_cmd python3
  [ -f "$archive" ] || ci_die "archive not found: $archive"
  python3 "$helper" "$archive" "$dest" || ci_die "safe archive extraction failed: $archive"
}

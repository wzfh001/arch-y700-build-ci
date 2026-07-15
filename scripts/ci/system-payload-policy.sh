#!/usr/bin/env bash

# This file is sourced by CI build scripts after common.sh.

ci_payload_file_mode() {
  local relative=${1#/}

  case "/$relative" in
    /DEBIAN/preinst|/DEBIAN/postinst|/DEBIAN/prerm|/DEBIAN/postrm|/DEBIAN/config|\
    /bin/*|/sbin/*|/usr/bin/*|/usr/sbin/*|/usr/libexec/*|\
    /usr/local/bin/*|/usr/local/sbin/*|/usr/local/libexec/*|\
    /opt/libcamera-y700/bin/*|/opt/libcamera-y700/libexec/*)
      printf '0755\n'
      ;;
    *)
      printf '0644\n'
      ;;
  esac
}

ci_normalize_system_payload_modes() {
  local root=$1 path relative expected

  [ -d "$root" ] || ci_die "system payload tree not found: $root"
  find "$root" -xdev -type d -exec chmod 0755 {} +
  while IFS= read -r -d '' path; do
    relative=${path#"$root"/}
    expected=$(ci_payload_file_mode "$relative")
    chmod "$expected" "$path"
  done < <(find "$root" -xdev -type f -print0)
}

ci_assert_normalized_system_payload_modes() {
  local root=$1 path relative expected actual

  [ -d "$root" ] || ci_die "system payload tree not found: $root"
  while IFS= read -r -d '' path; do
    actual=$(stat -c '%a' "$path")
    [ "$actual" = 755 ] || ci_die "system payload directory has mode $actual, expected 755: $path"
  done < <(find "$root" -xdev -type d -print0)
  while IFS= read -r -d '' path; do
    relative=${path#"$root"/}
    expected=$(ci_payload_file_mode "$relative")
    actual=$(stat -c '%a' "$path")
    [ "$actual" = "${expected#0}" ] || \
      ci_die "system payload file has mode $actual, expected ${expected#0}: $path"
  done < <(find "$root" -xdev -type f -print0)
}

ci_assert_privileged_payload_security() {
  local root=$1 required path writable
  shift

  [ -d "$root" ] || ci_die "rootfs tree not found: $root"
  for path in "$root/etc" "$root/usr" "$root/opt" "$root/bin" "$root/sbin" "$root/lib"; do
    [ -e "$path" ] || continue
    writable=$(find "$path" -xdev \( -type f -o -type d \) -perm /0022 -print -quit)
    [ -z "$writable" ] || ci_die "group/world-writable privileged payload member: $writable"
  done

  for required in "$@"; do
    required=${required#/}
    [ -f "$root/$required" ] || ci_die "required payload executable is missing: /$required"
    [ -x "$root/$required" ] || ci_die "required payload file is not executable: /$required"
  done
}

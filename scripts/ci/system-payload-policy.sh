#!/usr/bin/env bash

# This file is sourced by CI build scripts after common.sh.

ci_payload_file_mode() {
  local relative=${1#/}

  case "/$relative" in
    /DEBIAN/preinst|/DEBIAN/postinst|/DEBIAN/prerm|/DEBIAN/postrm|/DEBIAN/config|\
    /bin/*|/sbin/*|/usr/bin/*|/usr/sbin/*|/usr/libexec/*|\
    /usr/local/bin/*|/usr/local/sbin/*|/usr/local/libexec/*|\
    /usr/lib/tb321fu/refresh-camera-compat-paths|\
    /usr/lib/tb321fu/disable-stock-ksystemstats-gpu|\
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

ci_secure_preserved_payload_modes() {
  local root=$1 special writable

  [ -d "$root" ] || ci_die "system payload tree not found: $root"
  find "$root" -xdev -type d -exec chmod u=rwx,go=rx {} +
  find "$root" -xdev -type f -exec chmod u-s,g-s,go-w {} +

  special=$(find "$root" -xdev -type f -perm /6000 -print -quit)
  [ -z "$special" ] || ci_die "special privilege bit remained in preserved payload: $special"
  writable=$(find "$root" -xdev \( -type f -o -type d \) -perm /0022 -print -quit)
  [ -z "$writable" ] || ci_die "group/world-writable preserved payload member: $writable"
}

ci_assert_privileged_payload_security() {
  local root=$1 required path writable trusted_uid trusted_gid
  shift

  [ -d "$root" ] || ci_die "rootfs tree not found: $root"
  trusted_uid=$(stat -c '%u' "$root")
  trusted_gid=$(stat -c '%g' "$root")
  [ "$trusted_uid" = "$(id -u)" ] && [ "$trusted_gid" = "$(id -g)" ] || \
    ci_die "rootfs trust anchor is not owned by the build identity: $root"
  for path in "$root/etc" "$root/usr" "$root/opt" "$root/bin" "$root/sbin" "$root/lib"; do
    [ -e "$path" ] || continue
    writable=$(find "$path" -xdev \( -type f -o -type d \) \
      \( -perm /0002 -o \
        \( -perm /0020 \( ! -uid "$trusted_uid" -o ! -gid "$trusted_gid" \) \) \
      \) -print -quit)
    [ -z "$writable" ] || \
      ci_die "unprivileged group/world-writable privileged payload member: $writable"
  done

  for required in "$@"; do
    required=${required#/}
    [ -f "$root/$required" ] || ci_die "required payload executable is missing: /$required"
    [ -x "$root/$required" ] || ci_die "required payload file is not executable: /$required"
  done
}

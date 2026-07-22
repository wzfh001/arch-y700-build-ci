#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/package-list.sh"

ci_require_cmd curl
ci_require_cmd tar
ci_require_cmd mount
ci_require_cmd umount
ci_require_cmd findmnt
ci_require_cmd realpath
ci_require_cmd chroot
ci_require_cmd sha256sum
ci_require_cmd unshare

REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
OUTPUT_DIR=${OUTPUT_DIR:-out/pacman-lock}
OUTPUT_PREFIX=${OUTPUT_PREFIX:-TB321FU-tablet-niri}
ci_validate_output_prefix "$OUTPUT_PREFIX"
ARCH_ROOTFS_URL=${ARCH_ROOTFS_URL:-https://de3.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}
ARCH_ROOTFS_SHA256=${ARCH_ROOTFS_SHA256:-3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a}
ARCH_MIRROR=${ARCH_MIRROR:-https://de3.mirror.archlinuxarm.org/\$arch/\$repo}
DESKTOP_PROFILE=${DESKTOP_PROFILE:-tablet-niri}
INSTALL_FCITX5_CHINESE=${INSTALL_FCITX5_CHINESE:-1}
INSTALL_FIREFOX=${INSTALL_FIREFOX:-1}
INSTALL_CAMERA_APPS=${INSTALL_CAMERA_APPS:-0}
BUILD_TB321FU_GPU_SENSOR=${BUILD_TB321FU_GPU_SENSOR:-0}
PACKAGE_LIST=${PACKAGE_LIST:-}
SOURCE_DATE_EPOCH=$(ci_source_date_epoch)
export SOURCE_DATE_EPOCH

[ "$DESKTOP_PROFILE" = tablet-niri ] || ci_die 'the pacman lock seed is only for tablet-niri'
[ "$ARCH_ROOTFS_SHA256" = 3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a ] ||
  ci_die 'tablet-niri pacman lock requires the pinned Arch rootfs SHA-256'

OUTPUT_DIR=$(ci_prepare_output_dir "$OUTPUT_DIR")
work_dir=$(mktemp -d "$OUTPUT_DIR/.pacman-lock-build.XXXXXX")
rootfs_dir="$work_dir/rootfs"
lock_dir="$OUTPUT_DIR/${OUTPUT_PREFIX}-pacman-lock"
rootfs_archive="$work_dir/arch-rootfs.tar.gz"
mounted=0

cleanup() {
  set +e
  if [ "$mounted" = 1 ]; then
    if [ -x "$rootfs_dir/usr/bin/gpgconf" ]; then
      arch_chroot /usr/bin/gpgconf --kill all >/dev/null 2>&1 || true
      arch_chroot /usr/bin/env GNUPGHOME=/etc/pacman.d/gnupg /usr/bin/gpgconf --kill all >/dev/null 2>&1 || true
    fi
    sync
    ci_unmount_tree "$rootfs_dir" || ci_log "pacman lock cleanup left mounted paths below: $rootfs_dir"
    mounted=0
  fi
  ci_safe_rmtree "$work_dir" "$OUTPUT_DIR" .pacman-lock-build. ||
    ci_log "cleanup preserved pacman lock work tree: $work_dir"
}
trap cleanup EXIT

arch_chroot() {
  chroot "$rootfs_dir" /usr/bin/env -i \
    HOME=/root TERM=xterm \
    http_proxy="${http_proxy:-}" https_proxy="${https_proxy:-}" \
    HTTP_PROXY="${HTTP_PROXY:-}" HTTPS_PROXY="${HTTPS_PROXY:-}" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/bin "$@"
}

arch_chroot_offline() {
  unshare --net -- chroot "$rootfs_dir" /usr/bin/env -i \
    HOME=/root TERM=xterm PATH=/usr/local/sbin:/usr/local/bin:/usr/bin "$@"
}

mkdir -p "$rootfs_dir"
ci_safe_rmtree "$lock_dir" "$OUTPUT_DIR" "$OUTPUT_PREFIX-pacman-lock"
mkdir -p \
  "$lock_dir/repo/aarch64/core" \
  "$lock_dir/repo/aarch64/extra" \
  "$lock_dir/repo/aarch64/alarm" \
  "$lock_dir/repo/aarch64/aur"
ci_log "downloading fixed Arch rootfs for package lock: $ARCH_ROOTFS_URL"
ci_download "$ARCH_ROOTFS_URL" "$rootfs_archive" "$ARCH_ROOTFS_SHA256"
tar -C "$rootfs_dir" -xpf "$rootfs_archive" --numeric-owner

install -d -m 0755 "$rootfs_dir/etc/pacman.d" "$rootfs_dir/run"
printf 'Server = %s\n' "$ARCH_MIRROR" > "$rootfs_dir/etc/pacman.d/mirrorlist"
rm -f -- "$rootfs_dir/etc/resolv.conf"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$rootfs_dir/etc/resolv.conf"
rm -f -- "$rootfs_dir/var/lib/pacman/sync"/*.db "$rootfs_dir/var/lib/pacman/sync"/*.db.sig
find "$rootfs_dir/var/cache/pacman/pkg" -mindepth 1 -maxdepth 1 -type f -delete

mounted=1
mount --bind "$rootfs_dir" "$rootfs_dir"
mount --rbind /dev "$rootfs_dir/dev"
mount --make-rslave "$rootfs_dir/dev"
mount -t proc proc "$rootfs_dir/proc"
mount -t sysfs sysfs "$rootfs_dir/sys"
mount -t tmpfs tmpfs "$rootfs_dir/run"
mkdir -p "$rootfs_dir/run/tb321fu-pacman-lock"
mount --bind "$lock_dir" "$rootfs_dir/run/tb321fu-pacman-lock"

ci_log 'initializing the seed keyring and freezing repository databases'
arch_chroot /usr/bin/pacman-key --init
arch_chroot /usr/bin/pacman-key --populate archlinuxarm
arch_chroot /usr/bin/pacman -Sy --noconfirm

for repo in core extra alarm aur; do
  [ -f "$rootfs_dir/var/lib/pacman/sync/$repo.db" ] || ci_die "seed did not download $repo.db"
  install -m 0644 "$rootfs_dir/var/lib/pacman/sync/$repo.db" "$lock_dir/repo/aarch64/$repo/$repo.db"
  if [ -f "$rootfs_dir/var/lib/pacman/sync/$repo.db.sig" ]; then
    install -m 0644 "$rootfs_dir/var/lib/pacman/sync/$repo.db.sig" "$lock_dir/repo/aarch64/$repo/$repo.db.sig"
  fi
done

mirror_root=${ARCH_MIRROR%/\$arch/\$repo}
[[ $mirror_root =~ ^https://[A-Za-z0-9.-]+$ ]] || ci_die "unsafe Arch mirror root: $mirror_root"

download_package_url() {
  local url=$1 rel repo filename destination
  case "$url" in
    "$mirror_root/aarch64/core/"*|"$mirror_root/aarch64/extra/"*|\
    "$mirror_root/aarch64/alarm/"*|"$mirror_root/aarch64/aur/"*) ;;
    *) ci_die "pacman emitted a package URL outside the pinned mirror: $url" ;;
  esac
  rel=${url#"$mirror_root/"}
  [[ $rel =~ ^aarch64/(core|extra|alarm|aur)/([A-Za-z0-9][A-Za-z0-9+._@:-]*\.pkg\.tar\.(xz|zst|gz|bz2|lz4|lrz|lzo|Z))$ ]] ||
    ci_die "unsafe package URL path: $url"
  repo=${BASH_REMATCH[1]}
  filename=${BASH_REMATCH[2]}
  destination="$lock_dir/repo/aarch64/$repo/$filename"
  if [ ! -f "$destination" ]; then
    ci_log "locking package: $repo/$filename"
    curl -fL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 900 \
      "$url" -o "$destination"
    curl -fL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 120 \
      "$url.sig" -o "$destination.sig"
  fi
}

key_url=$(arch_chroot /usr/bin/pacman -Sp --print-format '%l' archlinuxarm-keyring 2>/dev/null |
  awk '/^https?:\/\// { print; exit }')
[ -n "$key_url" ] || ci_die 'failed to resolve archlinuxarm-keyring URL from the frozen database'
download_package_url "$key_url"
key_filename=${key_url##*/}
arch_chroot_offline /usr/bin/pacman -U --noconfirm \
  "/run/tb321fu-pacman-lock/repo/aarch64/core/$key_filename"
arch_chroot /usr/bin/pacman-key --populate archlinuxarm

mapfile -t requested < <(build_package_list)
[ "${#requested[@]}" -gt 0 ] || ci_die 'package request list is empty'
printf '%s\n' "${requested[@]}" > "$lock_dir/requested-packages.txt"

mapfile -t package_urls < <(
  arch_chroot /usr/bin/pacman -Syu --print --noconfirm --needed --print-format '%l' -- "${requested[@]}" 2>/dev/null |
    awk '/^https?:\/\// { print }' | LC_ALL=C sort -u
)
[ "${#package_urls[@]}" -gt 0 ] || ci_die 'frozen pacman transaction emitted no package URLs'
for url in "${package_urls[@]}"; do
  download_package_url "$url"
done

printf 'Server = file:///run/tb321fu-pacman-lock/repo/$arch/$repo\n' > "$rootfs_dir/etc/pacman.d/mirrorlist"
ci_log 'running the complete frozen pacman transaction in an isolated network namespace'
arch_chroot_offline /usr/bin/pacman -Syu --noconfirm --needed --disable-download-timeout -- "${requested[@]}"
arch_chroot_offline /usr/bin/pacman -Q | LC_ALL=C sort > "$lock_dir/expected-installed-packages.txt"

printf 'repo\tfilename\tsha256\n' > "$lock_dir/PACKAGE-FILES.tsv"
while IFS= read -r -d '' package; do
  relative=${package#"$lock_dir/repo/aarch64/"}
  repo=${relative%%/*}
  filename=${relative##*/}
  printf '%s\t%s\t%s\n' "$repo" "$filename" "$(sha256sum "$package" | awk '{print $1}')" >> "$lock_dir/PACKAGE-FILES.tsv"
done < <(find "$lock_dir/repo/aarch64" -type f -name '*.pkg.tar.*' ! -name '*.sig' -print0 | LC_ALL=C sort -z)

requested_sha=$(sha256sum "$lock_dir/requested-packages.txt" | awk '{print $1}')
installed_sha=$(sha256sum "$lock_dir/expected-installed-packages.txt" | awk '{print $1}')
cat > "$lock_dir/LOCK-INFO.env" <<INFO
lock_schema=1
arch=aarch64
rootfs_url=$ARCH_ROOTFS_URL
rootfs_sha256=$ARCH_ROOTFS_SHA256
source_mirror=$ARCH_MIRROR
requested_packages_sha256=$requested_sha
expected_installed_packages_sha256=$installed_sha
seed_run_id=${GITHUB_RUN_ID:-local}
seed_commit=${GITHUB_SHA:-unknown}
INFO

(cd "$lock_dir" && find . -type f ! -name SHA256SUMS -printf '%P\0' | LC_ALL=C sort -z | xargs -0 sha256sum) > "$lock_dir/SHA256SUMS"
manifest_sha=$(sha256sum "$lock_dir/SHA256SUMS" | awk '{print $1}')

bash "$SCRIPT_DIR/verify-pacman-package-lock.sh" "$lock_dir" "$manifest_sha" "$ARCH_ROOTFS_SHA256" "$lock_dir/requested-packages.txt"
lock_archive="$OUTPUT_DIR/${OUTPUT_PREFIX}-pacman-lock.tar"
bash "$SCRIPT_DIR/pack-pacman-package-lock.sh" "$lock_dir" "$lock_archive" >/dev/null
archive_sha=$(awk '{ print $1 }' "$lock_archive.sha256")
[[ $archive_sha =~ ^[0-9a-f]{64}$ ]] || ci_die "invalid lock archive SHA-256: $archive_sha"
printf 'manifest_sha256=%s\narchive_sha256=%s\npackage_count=%s\n' \
  "$manifest_sha" "$archive_sha" "$(($(wc -l < "$lock_dir/PACKAGE-FILES.tsv") - 1))" > \
  "$OUTPUT_DIR/${OUTPUT_PREFIX}-pacman-lock.summary"
ci_log "pacman package lock complete: $lock_dir"

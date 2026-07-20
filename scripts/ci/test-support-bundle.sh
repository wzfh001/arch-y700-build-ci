#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
PROFILE="$REPO_ROOT/profiles/tablet-niri/rootfs-overlay"
collector="$PROFILE/usr/local/bin/tb321fu-support-bundle"
redactor="$PROFILE/usr/local/libexec/tb321fu-redact-support-bundle"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-support-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'support bundle test failure: %s\n' "$*" >&2
  exit 1
}

for path in "$collector" "$redactor"; do
  [ -x "$path" ] || fail "not executable: $path"
done
bash -n "$collector"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m py_compile "$redactor"

fixture="$tmp/fixture"
mkdir -p "$fixture"
cat > "$fixture/secrets.txt" <<'EOF'
machine-id=0123456789abcdef0123456789abcdef
psk=correct-horse-battery-staple
Password: hunter2
Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345
OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz012345
remote=https://alice:secret@example.invalid/repository
-----BEGIN OPENSSH PRIVATE KEY-----
private-private-private
-----END OPENSSH PRIVATE KEY-----
useful-hardware-line=ath12k_pci 0000:01:00.0
EOF

"$redactor" --tree "$fixture"
for secret in \
  correct-horse-battery-staple \
  hunter2 \
  abcdefghijklmnopqrstuvwxyz012345 \
  sk-abcdefghijklmnopqrstuvwxyz012345 \
  'alice:secret' \
  private-private-private; do
  if grep -RIFq -- "$secret" "$fixture"; then
    fail "redactor retained fixture secret: $secret"
  fi
done
grep -Fq 'useful-hardware-line=ath12k_pci 0000:01:00.0' "$fixture/secrets.txt" || \
  fail 'redactor removed useful hardware evidence'
grep -Fq 'files_changed=' "$fixture/REDACTION-REPORT.txt" || \
  fail 'redaction report is missing change counts'

for required in \
  'journalctl -b' \
  '/sys/class/udc' \
  '/sys/class/typec' \
  '/sys/kernel/config/usb_gadget' \
  'niri msg outputs' \
  'wpctl status' \
  '/sys/class/power_supply' \
  'SHA256SUMS.txt'; do
  grep -Fq "$required" "$collector" || fail "collector is missing $required"
done

if grep -Eq '/home/[^/]+/\.ssh|/root/\.ssh|NetworkManager/system-connections/.+cat' "$collector"; then
  fail 'collector attempts to read a credential store'
fi

output="$tmp/output"
mkdir -p "$output"
archive=$(TB321FU_REDACTOR="$redactor" "$collector" "$output")
[ -f "$archive" ] || fail 'collector did not create an archive'
[ "$(stat -c '%a' "$archive")" = 600 ] || fail 'support archive is not mode 0600'
archive_tree="$tmp/archive-tree"
mkdir -p "$archive_tree"
case "$archive" in
  *.tar.zst) tar --zstd -xf "$archive" -C "$archive_tree" ;;
  *.tar.gz) tar -xzf "$archive" -C "$archive_tree" ;;
  *) fail "collector produced an unknown archive format: $archive" ;;
esac
for member in README.txt COLLECTION-NOTES.txt REDACTION-REPORT.txt SHA256SUMS.txt; do
  [ -s "$archive_tree/$member" ] || fail "archive member is missing or empty: $member"
done
(
  cd "$archive_tree"
  sha256sum -c SHA256SUMS.txt >/dev/null
) || fail 'support archive checksum manifest did not verify'

printf 'SUPPORT_BUNDLE=PASS\n'

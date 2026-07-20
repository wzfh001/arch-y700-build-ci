# Arch Linux ARM Y700/TB321FU Build CI

Build an Arch Linux ARM rootfs and GRUB image for the Lenovo Y700 2025
(`TB321FU`). The default profile is a touch-oriented `niri + Noctalia` system.
The repository remains separate from the Ubuntu/Kubuntu build and reuses only
the verified TB321FU boot, kernel, firmware, and device payload sources.

The project is still hardware bring-up work. A successful CI artifact is not
automatically safe to flash.

## Default tablet-niri system

The `tablet-niri` profile provides:

- niri 26.04 with native `xwayland-satellite` integration
- Noctalia v5, built from a pinned release tag
- greetd direct login to the `fuhao` graphical session
- fixed `DSI-1` landscape output at `1600x2560@120`, transform `270`, scale `2.3`
- Noctalia Wi-Fi, Bluetooth, audio, brightness, battery, notifications, and
  session controls
- a manually toggled `wvkbd` touch keyboard
- Fcitx5 US/Pinyin input without global GTK/Qt IM-module overrides
- Foot with Bash as the guaranteed terminal
- NetworkManager, BlueZ, PipeWire/WirePlumber, UPower, and the verified TB321FU
  audio/haptics payload
- Dolphin, Ark, mpv, VLC, Elisa, Gwenview, Okular, Firefox, and Zen Browser
- Git, Node.js, npm, pnpm, Python, Rust, ripgrep, fd, jq, tmux, Neovim,
  `base-devel`, and `paru`
- official ARM64 builds of CC Switch, Mihomo Party, and OpenAI Codex CLI,
  repackaged as pacman-owned packages
- LAN-only SSH firewall policy, automatic USB NCM plus ACM serial rescue,
  automatic Bluetooth NAP rescue, first-boot ext4 growth, zram, persistent
  journal limits, and pre-upgrade configuration snapshots

There is no Plasma session, SDDM, automatic screen lock, automatic suspend,
Office suite, Docker, Fish, or Starship in this profile. Ghostty is not in the
audited Arch Linux ARM repositories and its required Zig toolchain is not part
of the deterministic first build, so Foot is used as the explicit fallback.

The complete design and source matrix are in:

- `docs/TABLET-NIRI-ARCHITECTURE.md`
- `docs/TABLET-NIRI-PACKAGE-MATRIX.md`

## Desktop profiles

The workflow input `desktop_profile` supports:

- `tablet-niri`: TB321FU touch profile and workflow default
- `minimal`: legacy small Plasma baseline
- `standard`: legacy Plasma daily-use profile
- `full`: legacy Plasma plus `kde-applications-meta`

The Plasma profiles remain for compatibility. They do not share the
`tablet-niri` session/configuration writer.

## Accounts and required secrets

The tablet profile fixes both hostname and normal user name to `fuhao`. The
normal user has password-based sudo, the graphical session logs in
automatically, and the root account remains locked.

Configure these repository Actions secrets before running `tablet-niri`:

- `DEFAULT_USER_PASSWORD_HASH`: SHA-512 `crypt(3)` hash for the bootstrap user
- `DEFAULT_USER_AUTHORIZED_KEYS`: one or more complete OpenSSH public-key lines
- `ROOT_PASSWORD_HASH`: optional and unused while `ROOT_PASSWORD_MODE=locked`

Credential material is accepted only as step-scoped secret environment data.
It is rejected from workflow inputs and config files and is not serialized to
build notes, manifests, or release notes. SSH host private keys are removed
from the image and generated uniquely on first boot.

The personalized filesystem necessarily contains the user password hash and
authorized public key. Keep the first run artifact-only, download it promptly,
do not publish a Release, and change the bootstrap password before using the
tablet on an untrusted network.

## ARM64 third-party inputs

The first profile pins these upstream ARM64 assets by SHA-256:

- Zen Browser `1.21.8b`
- CC Switch `3.17.0`
- Mihomo Party `2.0.0`
- OpenAI Codex CLI `0.144.6`

No Debian maintainer script is executed. The assets are repackaged into native
Arch packages and checked for AArch64 ELF identity. Mihomo Party is installed
without the blanket setuid bits used by its AUR binary recipe; proxy/TUN
privilege changes require a separate review.

No Codex account, CC Switch data, Mihomo subscription, API key, proxy profile,
or Wi-Fi credential is included. Those are migrated after first boot over SSH.

## Hardware payload strategy

Arch cannot install the existing Ubuntu `.deb` packages with `dpkg`, but their
tested TB321FU payload files are still required. The build extracts and
repackages those files as native Arch packages while preserving:

- `/usr/lib/modules/7.1.1-g5df8e852ea72`
- Qualcomm firmware under `/usr/lib/firmware` and compatibility paths
- Y700/TB321FU udev rules and systemd services
- sensor, haptics, camera, and audio helper files

The build runs `depmod -b`, rejects unsafe ownership/modes, and fails if the
required modules, firmware, services, or native package ownership are missing.
The Plasma-only KSystemStats GPU plugin is disabled in `tablet-niri`.

## Build inputs

Important workflow inputs are:

- `release_tag`: leave empty for Actions artifacts only
- `prerelease`: required only for an explicitly requested remediation release
- `output_prefix`: artifact and image filename prefix
- `arch_rootfs_url` and `arch_rootfs_sha256`: reviewed Arch Linux ARM rootfs pin
- `desktop_profile`: defaults to `tablet-niri`
- `rootfs_image_size`: defaults to `20G`
- `rootfs_config`, `boot_config`, `source_config`: advanced `KEY=value`
  overrides; secrets are forbidden

Current Arch Linux ARM rootfs baseline:

```text
URL=https://de3.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
Last-Modified=2026-06-06T03:25:25Z
Size=818293654
SHA256=3cf5764fb6fec7bffdff98787e52ccd15d5d6390a2496c7028d7c4950404c56a
OpenPGP signer=68B3537F39A313B3E574D06777193F152BDBE6A6
```

The upstream filename is rolling. Changed bytes fail closed until the URL,
hash, and signature evidence are deliberately reviewed.

## Outputs

An artifact-only run emits:

- compressed rootfs image and raw-image SHA-256
- compressed GRUB/FAT image and raw-image SHA-256
- the verified existing `boot.img.7z`
- combined `SHA256SUMS.txt`
- final pacman package list
- rootfs file manifest
- pinned third-party asset manifest
- non-secret build parameters

Release assets, when explicitly enabled, use short names:

- `boot.img.7z`
- `grub.img.7z`
- `rootfs.img.7z.000`, `rootfs.img.7z.001`, and later parts if required
- `SHA256SUMS.txt`

Recombine split rootfs parts in lexical order before extraction:

```sh
cat rootfs.img.7z.* > rootfs.img.7z
```

## Validation gates

Before any device write, verify at least:

1. All workflow, boundary, archive, package lifecycle, and profile tests pass.
2. Rootfs, GRUB, boot, and combined checksums pass after download.
3. Every archive passes a full integrity test.
4. The extracted rootfs has greetd, niri, Noctalia, SSH, the unlocked normal
   user, a locked root account, and no inherited SSH host key or secret config.
5. Plasma/SDDM packages and automatic suspend/lock policies are absent.
6. The Kubuntu backup and the device-specific rollback/write plan are still
   available.

The first device acceptance checks touch, Wi-Fi, Bluetooth, speaker,
headphones, microphone, haptics, brightness, battery, and 120 Hz. Camera and
suspend are not first-image pass gates. Manual suspend remains available only
through a warning wrapper and captures pre/post DRM, kernel, Wi-Fi, and audio
logs.

Do not write the large `userdata` image with Fastboot. The previously observed
Fastboot path reported success while omitting tail data. Any eventual switch
must use the separately verified GPT-specific raw-write procedure and must be
explicitly authorized at that time.

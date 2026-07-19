# TB321FU tablet-niri package matrix

Status: source and architecture freeze for implementation
Date: 2026-07-19

Versions below are the ARM Linux audit snapshot used to design the profile.
Official repository versions remain rolling; the build records the exact
installed package set in its manifest. Third-party release assets are pinned
by URL and digest in the build source.

## Official Arch Linux ARM packages

All packages in this section were found as `aarch64` or `any` in the ALARM
`core`, `extra`, or `alarm` databases fetched from the official `de3` mirror.

### Session, compositor, and touch

```text
niri 26.04-1
xwayland-satellite 0.8.1-2
greetd 0.10.3-2
greetd-tuigreet 0.9.1-2
foot 1.27.0-1
fuzzel 1.14.1-1
xdg-desktop-portal-gnome 50.0-1
xdg-desktop-portal-gtk 1.15.3-1
wl-clipboard 1:2.3.0-1
wtype 0.4-2
brightnessctl 0.5.1-3
```

`wvkbd` is not an official package and is listed below. `squeekboard` is
officially available as `1.43.1-5`, but is not selected for the first profile.

### Network, power, audio, and device integration

```text
networkmanager 1.56.1-2
wpa_supplicant 2:2.11-5
bluez 5.87-2
bluez-utils 5.87-2
upower 1.91.3-1
udisks2 2.11.1-2
power-profiles-daemon 0.30-1
nftables 1:1.1.6-3
zram-generator 1.2.1-1
iio-sensor-proxy 3.9-1
feedbackd 0.8.9-2
alsa-ucm-conf 1.2.16.1-1
alsa-utils 1.2.16-1
pipewire 1:1.6.8-1
pipewire-alsa 1:1.6.8-1
pipewire-pulse 1:1.6.8-1
wireplumber 0.5.15-1
```

### Graphics and portals

```text
mesa 1:26.1.5-1
vulkan-freedreno 1:26.1.5-1
vulkan-tools 1.4.350.1-1
libglvnd
xdg-desktop-portal-gnome
xdg-desktop-portal-gtk
polkit-gnome 0.105-12
```

The TB321FU kernel/module/firmware payload remains a separately owned native
package. The Plasma-only `tb321fu-ksystemstats-gpu` package is disabled for
this profile.

### Input method and fonts

```text
fcitx5 5.1.21-1
fcitx5-chinese-addons 5.1.13-2
fcitx5-configtool 5.1.14-1
fcitx5-qt 5.1.14-1
fcitx5-gtk 5.1.7-1
noto-fonts 1:2026.07.01-1
noto-fonts-cjk 20240730-1
noto-fonts-emoji 1:2.051-1
ttf-jetbrains-mono-nerd 3.4.0-2
```

### Required applications

```text
dolphin 26.04.3-1
ark 26.04.3-1
mpv 1:0.41.0-3
vlc 3.0.23_2-9
elisa 26.04.3-1
gwenview 26.04.3-1
okular 26.04.3-1
firefox 152.0.6-1
```

Firefox is the ARM64 browser fallback. Zen is installed from its official
ARM64 release asset when the custom package check passes.

### Development and rescue tools

```text
base-devel git openssh rsync curl wget ca-certificates gnupg fakeroot
nodejs npm pnpm python rust
ripgrep fd jq tmux neovim
bash-completion file htop nano vim less which tar unzip 7zip
usbutils pciutils iproute2 inetutils
```

The ALARM snapshot contains `rust 1:1.97.1-1`; using `rust` rather than an
unbootstrapped `rustup` toolchain makes Rust usable immediately. `rustup` may
be added later if a project specifically requires toolchain pinning.

## Source-built ARM64 packages

These packages are built in the target aarch64 environment from pinned source
tarballs. The implementation vendors a small, reviewable recipe for each one;
it does not execute an unpinned `paru` command during the image build.

| Package | Version | Source and pin | Reason |
| --- | --- | --- | --- |
| `noctalia` | `5.0.0_beta.3-2` | GitHub tag `v5.0.0-beta.3`; SHA-256 `0cd9d718acb95eec8500e6159c2981de46070f13f0fdacf7cb1e51cb2cbddb5e` | Native Noctalia v5 shell; AUR declares `aarch64` |
| `wvkbd` | `0.19.4-1` | Source tarball; SHA-512 `e9a877eac4913375a3ea160966d0822ed15be540234148ba2638e5b7c19cfa885b962eba260a0f782a762324732454cf48668d85307a748decb198abeb009784` | Manual touch keyboard |
| `paru` | `2.1.0-2` | GitHub tag `v2.1.0`; SHA-256 `eea4dbb524db765d5316f540f9ee670c0bf81aae4827b5417eebb4c9b5651727` | Post-boot AUR helper; aarch64 recipe with a pinned libalpm 16 compatibility update |

Paru's upstream lock file predates libalpm 16. The recipe applies only four
exact Cargo updates: `alpm 4.0.4`, `alpm-sys 4.0.5`, `alpm-utils 4.0.3`, and
`pacmanconf 3.1.0`. Their crates.io SHA-256 checksums are respectively
`119e8b82e2473323f2fe4ee81599286430bc9a64b31f5e67eb6dec806858c9cd`,
`4071fa385bbb17c2a6eceb65b9a52e8f5c9f97800b1c125ac09a0f160f36b076`,
`ca8f443e4db722be178e03d5f5047b5fff8234f7e2b684746f3a123315871c07`,
and `1087f8994e545eed9f7453376282f2964f18ca4b739e42f0dc7f2fed246d76c3`.
`alpm-sys 4.0.5` is required because it recognizes patch releases such as the
target rootfs's libalpm `16.0.1`, rather than only the exact `16.0.0` string.

Noctalia's runtime dependencies are official ARM packages, including
`meson`, `ninja`, `sdbus-cpp`, `tomlplusplus`, `nlohmann-json`, `stb`, PipeWire,
Wayland, and the graphics libraries. Build failures must stop the image;
there is no silent fallback to a different shell.

## Official ARM64 binary packages

The following are repackaged into native Arch packages so pacman owns their
files. Each asset is downloaded once, verified by its GitHub digest, checked
for the expected architecture, and recorded in the build manifest.

| Package | Upstream version | Asset | SHA-256 |
| --- | --- | --- | --- |
| `tb321fu-zen-browser` | `1.21.8b` | `zen.linux-aarch64.tar.xz` | `0586ff279d7a1f93207fdb195c5586ef0d6813bd4f4318badcd0984adc39db39` |
| `tb321fu-cc-switch` | `3.17.0` | `CC-Switch-v3.17.0-Linux-arm64.deb` | `8b1b2ba9cca007d0b5070670b7d8904d45789402f5ab915ba9d619cad3621052` |
| `tb321fu-mihomo-party` | `2.0.0` | `mihomo-party-linux-2.0.0-arm64.deb` | `bfa25f96e27982d87232e017e6ee0f3f9ab7aa8d2d69a8f06e418b38ac3ab690` |
| `tb321fu-codex-cli` | `0.144.6` | `codex-aarch64-unknown-linux-musl.tar.gz` | `8eddae5e6c009dff9ba51ae1bfe3bdd9ff4c1ccc93a48cc6860db1cd9fdf11be` |

Sources:

- Zen: `https://github.com/zen-browser/desktop/releases/tag/1.21.8b`
- CC Switch: `https://github.com/farion1231/cc-switch/releases/tag/v3.17.0`
- Mihomo Party: `https://github.com/mihomo-party-org/mihomo-party/releases/tag/v2.0.0`
- Codex CLI: `https://github.com/openai/codex/releases/tag/rust-v0.144.6`

The Debian assets are extracted and repackaged; Debian maintainer scripts are
not executed inside the target rootfs. The Mihomo Party sidecar binaries do
not receive blanket setuid bits. TUN mode, if later required, must use an
explicit reviewed privilege mechanism rather than an inherited AUR shortcut.

## Deliberate fallback: Ghostty

Ghostty is not in the current ALARM repositories. The current AUR source
recipe advertises aarch64 but requires a specific Zig 0.13 toolchain that is
not present in the audited ALARM package set. Building that toolchain and a
large terminal from source is not part of the first image's deterministic
path. Foot is therefore the guaranteed terminal for `tablet-niri`.

A later optional package can revisit Ghostty after an ARM64 source build is
independently verified. Its failure must never make the first image boot
without a terminal.

## Excluded packages and features

```text
plasma-meta plasma-desktop plasma-workspace sddm plasma-keyboard
kde-applications-meta konsole office-suite docker
fish starship
```

The profile does not preload Wi-Fi, Mihomo, CC Switch, or Codex credentials.
It also does not package camera applications as an acceptance requirement.

## Packaging and update rules

1. Official packages come from the pinned ALARM mirror and are installed with
   a full `pacman -Syu` transaction.
2. Third-party source and binary inputs have explicit version and digest pins.
3. Every custom file is owned by a named native package or is installed by a
   reviewed system configuration step with an explicit manifest entry.
4. Custom packages are listed in `IgnorePkg` only after their names and update
   policy are recorded; official core libraries are never partially frozen.
5. The final package list, custom asset manifest, and checksums are emitted
   outside the root filesystem and are scanned for secrets.
6. No account password, SSH key, API key, subscription, or user config is
   embedded in a source archive or metadata artifact.

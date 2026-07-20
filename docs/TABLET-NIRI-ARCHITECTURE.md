# TB321FU Arch Linux ARM tablet-niri architecture

Status: design freeze for the first implementation pass
Date: 2026-07-19
Base commit: `c36b1275c9016a219c1883c1ecfeb033e1bee2d3`

This document defines the first Arch Linux ARM image for the Lenovo Y700 2025
(TB321FU). It is deliberately separate from the existing Plasma profile. The
first image is an artifact-only CI deliverable until the image, rollback path,
and hardware acceptance evidence have been reviewed.

## Product role

The tablet complements a computer. It is intended for mobile entertainment,
development, network work, and hardware debugging. It is not a desktop-office
replacement and does not include Plasma, an office suite, Docker, or a second
desktop environment.

The touch screen must be usable for ordinary operation. A keyboard and mouse
may be connected later, so TTY, Bash, SSH, and text-mode rescue paths remain
available.

## Hardware invariants

The current Kubuntu baseline is the source of truth for display geometry:

- DRM connector: `DSI-1`
- Native mode: `1600x2560@120.00`
- Logical presentation: landscape, with the physical buttons and speakers at
  the top edge
- KWin transform: `Rotated270`
- KWin scale: `2.3`

The niri equivalent is therefore:

```kdl
output "DSI-1" {
    mode "1600x2560@120.000"
    scale 2.3
    transform "270"
}

input {
    touch {
        map-to-output "DSI-1"
    }
}
```

The output block is intentionally explicit. No auto-rotation, monitor
discovery policy, or desktop-monitor rule is copied from the PC configuration.
The 120 Hz mode is a required acceptance test, not an assumption made only in
the configuration file.

## Profile boundary

The repository keeps `minimal`, `standard`, and `full` for compatibility with
the existing build interface. A new `tablet-niri` profile is the only profile
used for this device. It must not be implemented by conditionally deleting
Plasma packages from `standard`; the package list, services, user session, and
configuration writers are separate.

The profile has these invariants:

- `fuhao` is both the hostname and the normal user name.
- The normal user has a password and password-based `sudo`.
- The graphical session logs in automatically without asking for that
  password.
- `root` SSH is permanently disabled.
- SSH accepts both the injected public key and a password, but the firewall
  permits new SSH connections only from private/local address ranges.
- There is no screen locker and no automatic lock transition.
- Suspend is available from the session menu for diagnostics, but is never
  selected by an idle timer.
- Plasma, SDDM, `plasma-keyboard`, and KWin-specific configuration are absent.

## Boot and session

The session path is:

```text
greetd -> initial_session(fuhao) -> niri-session -> niri.service
                                            -> graphical-session.target
                                            -> Noctalia, Fcitx5, PipeWire user units
```

`greetd` uses an `initial_session` for direct graphical login and retains a
`tuigreet`/TTY fallback if the session exits. This gives the image a usable
rescue path without making a graphical password prompt part of normal use.

Noctalia is a native v5 build, started as a systemd user service with
`Restart=on-failure` and a short restart delay. The service is ordered after
the graphical session target and is not hidden in an untracked compositor
startup command.

Fcitx5 is a user service or session startup unit, with `XMODIFIERS` set for
legacy applications. Global `GTK_IM_MODULE` and `QT_IM_MODULE` overrides are
not installed: native Wayland text-input paths must remain available to Qt,
GTK, Firefox, and Electron applications.

The default shell is Bash. Foot is the guaranteed ARM64 terminal in the first
image. Fish, Starship, and Plasma Konsole are intentionally not installed.

## Noctalia interaction design

The Noctalia v5 configuration is a tablet adaptation of the current PC visual
language, not a copy of the PC monitor rules or wallpaper paths.

### Bar

The bar is a top bar with touch-sized controls. The implementation target is a
40 logical-pixel bar, transparent outer background, translucent capsule
widgets, restrained radius, and no blur dependency. The final values must be
validated against the pinned Noctalia schema before packaging.

The module order is:

```text
start: launcher, workspaces, active_window
end:   media, tray, network, bluetooth, proxy, brightness, volume, battery,
       osk, notifications, session
```

`proxy` and `osk` are Noctalia custom-button widgets:

- `proxy` launches `mihomo-party` on demand. It does not start the proxy at
  boot and does not contain a subscription or credential.
- `osk` invokes `tb321fu-osk-toggle`, which starts or stops `wvkbd`.

The network and Bluetooth widgets use Noctalia's NetworkManager and BlueZ
integrations. Brightness and battery use Noctalia's backlight and UPower
integrations. The control center exposes Wi-Fi, Bluetooth, audio, brightness,
power profile, and session controls without adding a second panel.

An auto-hide dock may be enabled for touch access to a small set of common
applications. It must not reserve a permanent strip of screen space or
duplicate a full desktop launcher.

### Keyboard and input method

Niri v26.04 exposes the Wayland virtual-keyboard and input-method protocols.
`wvkbd` is used for the explicit on-demand keyboard because it is a small
layer-shell client with an ARM64-capable source package and no login-locker
dependency. `squeekboard` is available in the official ARM repository, but is
not the first choice because its Phosh-oriented activation behavior is less
suited to a manually invoked keyboard.

The first image must validate all of these paths:

1. Open the keyboard from the Noctalia bar.
2. Enter text into a native Wayland GTK application.
3. Enter text into a Qt application.
4. Switch Fcitx5 between the US keyboard and Pinyin.
5. Close the keyboard without leaving a stale layer surface.

## Power and display-off policy

Noctalia's idle behavior is configured as follows:

```toml
[idle.behavior.screen-off]
timeout = 600
action = "screen_off"
enabled = true

[idle.behavior.lock]
enabled = false
```

`screen_off` delegates to the compositor's monitor power action. Niri
documents that any input wakes a monitor after `power-off-monitors`; no lock
screen is involved.

The short physical power key is handled by niri and runs
`power-off-monitors`. `systemd-logind` is configured not to suspend or power
off on the short key, so the key remains a display toggle. Long-press behavior
is left as an explicit emergency power-off policy.

The Noctalia session menu contains reboot, shutdown, and a separately labeled
diagnostic suspend action. Logout is intentionally omitted because it would
drop a touch-only user into the text greetd fallback. The suspend command is
overridden with `tb321fu-suspend`, which displays a warning and then calls
`systemctl suspend`.
The image does not mask suspend targets and does not force either `deep` or
`s2idle`; the active kernel default is recorded before each manual test.

Every suspend attempt is logged by a system-sleep hook. The pre/post records
include DRM state, kernel messages, display modes, power-sleep mode, Wi-Fi
state, audio state, and relevant service status. The pre-suspend record is
flushed before the suspend request so a failed display resume still leaves
evidence on disk.

## Network, audio, and hardware services

NetworkManager with `wpa_supplicant` handles Wi-Fi. No Wi-Fi credentials are
preloaded. The first connection is made through Noctalia or `nmtui`. The
custom `ath12k_wifi7` module is explicitly loaded because this device cannot
depend on generic Arch module-autoload behavior for its only primary network
interface.

The image has two local-only rescue networks:

- USB-C exposes a composite CDC NCM network device and CDC ACM serial console.
  NetworkManager serves DHCP from `10.77.0.1/24`; SSH is always reachable at
  `10.77.0.1`, and `ttyGS0` provides a password-protected serial login.
- BlueZ and NetworkManager advertise a Bluetooth NAP on `10.78.0.1/24` so a
  paired computer can initiate the PAN connection without typing commands on
  the tablet.

The USB service explicitly loads `pmic_glink`, `ucsi_glink`, `libcomposite`,
`usb_f_acm`, and `usb_f_ncm`, then waits indefinitely for a UDC instead of
failing when the cable is absent during boot. The normal TB321FU controller is
`a600000.usb`, but the service discovers it dynamically. Both rescue profiles
use NetworkManager shared mode with `dnsmasq`; the firewall admits DHCP, DNS,
ICMP, and private-range SSH while retaining a default-drop input policy.

BlueZ is enabled for Bluetooth. PipeWire/WirePlumber is enabled globally for
the user session. The existing TB321FU audio route and haptics payloads remain
owned by native Arch packages and are not copied as unowned files.

The first hardware acceptance list is:

- touch input and orientation mapping
- Wi-Fi association and DHCP
- Bluetooth scan and pairing
- internal speaker
- USB-C/3.5 mm headphone route
- internal microphone capture
- haptics
- brightness control
- battery and charging telemetry
- 120 Hz display mode

Camera functionality is allowed to remain unavailable and is not a first-image
pass/fail gate.

## Storage and maintenance

The flashed image starts with a 20 GiB ext4 filesystem. A first-boot oneshot
verifies that `/` is the expected ext4 `userdata` filesystem and runs an
online `resize2fs` to consume the full target partition. It writes a marker
only after a successful resize and never formats or repartitions the device.

`zram-generator` provides compressed swap; no disk swap partition or swap file
is created. Persistent journald is capped at approximately 300 MiB, with a
smaller runtime cap.

There are no unattended updates. An explicit `pacman -Syu` is the supported
update path. A pre-transaction hook saves a package list and selected system
configuration before an upgrade. The custom kernel, module/firmware payload,
TB321FU camera package, Noctalia, and the locally packaged ARM64 applications
are pinned or explicitly ignored until a new image has passed its own tests.

The user may install and use `paru` after boot. AUR builds are never performed
as root and are not allowed to replace official packages implicitly.

## Security and secrets

The build receives `DEFAULT_USER_PASSWORD_HASH` and the authorized public key
only as step-scoped CI secrets. Neither value is placed in workflow inputs,
build notes, package manifests, release notes, or source files. Codex, CC
Switch, and Mihomo configuration, API keys, and subscriptions are migrated
after first boot over SSH and never enter an artifact.

The password is a bootstrap credential and must be changed before the tablet
is used on an untrusted network. A password hash necessarily exists in the
personalized filesystem, so the first build remains artifact-only, is not
published as a Release, and is deleted from remote CI storage after local
download and audit when practical. The firewall and SSH rate limit are defense
in depth, not a substitute for changing the bootstrap credential.

The image removes any inherited SSH host keys so `sshdgenkeys.service` creates
unique keys on first boot. Artifact checks fail if private host keys, private
keys, tokens, or known secret configuration paths are present.

## Build and acceptance gates

The implementation must provide these gates in order:

1. Shell/config/static tests pass without requiring a device.
2. The `tablet-niri` package list contains no Plasma, SDDM, or lock-screen
   package and contains all required official/custom packages.
3. Every downloaded ARM64 binary has a pinned SHA-256 and is checked with an
   ELF architecture test where applicable.
4. No custom binary receives an unreviewed setuid bit. Mihomo Party sidecars
   are packaged without the AUR recipe's blanket setuid installation.
5. The rootfs, GRUB image, and boot image checksums and archive tests pass.
6. The extracted rootfs contains the expected user/session/services and no
   secret material.
7. The current Kubuntu rollback artifacts and GPT-specific write boundaries
   are reviewed again.
8. Only then is a device test considered; the first test still does not write
   `userdata` through Fastboot.

Suspend recovery is a diagnostic capability, not a first-release hardware
pass gate. A reproducible suspend log and a working reboot/SSH recovery path
are required before it is tested.

## Explicit non-goals

- Plasma, SDDM, KDE desktop session, or Plasma Keyboard
- Office applications and Docker
- Preconfigured Wi-Fi, proxy subscriptions, Codex accounts, or API keys
- Automatic proxy startup
- Automatic screen rotation
- Automatic screen locking
- Camera as a release gate
- Fastboot writing of the large `userdata` image

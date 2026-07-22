#!/usr/bin/env bash

# Shared package request list for the normal rootfs build and the pacman lock
# seed.  The caller must source common.sh first because ci_bool/ci_die are
# intentionally shared validation primitives.

build_package_list() {
  local base_packages=(
    base bash-completion sudo openssh rsync curl wget ca-certificates gnupg fakeroot
    nano vim less which file htop usbutils pciutils iproute2 inetutils
    networkmanager bluez bluez-utils power-profiles-daemon udisks2 upower
    linux-firmware
    alsa-ucm-conf alsa-utils iio-sensor-proxy feedbackd
    glib2 libgudev polkit protobuf-c libqmi libqrtr-glib
    libevent libyaml gstreamer gst-plugins-base gst-plugins-base-libs gst-plugins-good gst-plugin-libcamera gtk3 gdk-pixbuf2 libunwind elfutils gnutls libglvnd
    mesa vulkan-freedreno vulkan-tools
    pipewire pipewire-alsa pipewire-pulse wireplumber
  )
  local desktop_standard=(
    plasma-meta sddm sddm-kcm plasma-keyboard xdg-desktop-portal-kde
    dolphin konsole kate ark gwenview okular spectacle discover packagekit-qt6 bluedevil
    packagekit
    noto-fonts noto-fonts-cjk ttf-dejavu ttf-liberation
  )
  local desktop_full=(kde-applications-meta)
  local tablet_niri=(
    niri xwayland-satellite greetd greetd-tuigreet foot fuzzel
    xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk qt6-wayland
    wl-clipboard wtype playerctl grim slurp satty zenity brightnessctl
    nftables zram-generator e2fsprogs wpa_supplicant dnsmasq
    pavucontrol gvfs kio-extras ffmpegthumbnailer phonon-qt6-vlc
    dolphin ark mpv vlc elisa gwenview okular
    noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd
    base-devel git nodejs npm pnpm python rust ripgrep fd jq tmux neovim
    7zip zip unzip unrar zstd exfatprogs dosfstools
    gtk3 libxt mailcap shared-mime-info desktop-file-utils hicolor-icon-theme
    gtk-update-icon-cache
    dbus-glib nss ffmpeg4.4 libnotify libxss libxtst
    xdg-utils at-spi2-core util-linux-libs libsecret libayatana-appindicator
    webkit2gtk-4.1
    cairo fontconfig freetype2 gcc-libs glib2 glibc jemalloc libpipewire
    libqalculate librsvg libwebp libwireplumber libxkbcommon libxml2 md4c pam
    polkit pango sdbus-cpp tomlplusplus wayland meson ninja nlohmann-json
    pkgconf stb wayland-protocols scdoc
  )
  local fcitx_packages=(
    fcitx5 fcitx5-chinese-addons fcitx5-configtool fcitx5-qt fcitx5-gtk fcitx5-material-color
  )
  local browser_packages=(firefox)
  local camera_app_packages=(snapshot kamoso)
  local gpu_sensor_build_packages=(cmake extra-cmake-modules gcc make libksysguard ksystemstats qt6-base kcoreaddons ki18n)
  local packages=("${base_packages[@]}")

  case "$DESKTOP_PROFILE" in
    minimal)
      packages+=(plasma-desktop plasma-workspace sddm plasma-keyboard konsole dolphin noto-fonts-cjk)
      ;;
    standard)
      packages+=("${desktop_standard[@]}")
      ;;
    full)
      packages+=("${desktop_standard[@]}" "${desktop_full[@]}")
      ;;
    tablet-niri)
      packages+=("${tablet_niri[@]}")
      ;;
    *) ci_die "unsupported DESKTOP_PROFILE=$DESKTOP_PROFILE" ;;
  esac

  if ci_bool "$INSTALL_FCITX5_CHINESE"; then
    packages+=("${fcitx_packages[@]}")
  fi
  if ci_bool "$INSTALL_FIREFOX"; then
    packages+=("${browser_packages[@]}")
  fi
  if ci_bool "$INSTALL_CAMERA_APPS"; then
    packages+=("${camera_app_packages[@]}")
  fi
  if ci_bool "$BUILD_TB321FU_GPU_SENSOR"; then
    packages+=("${gpu_sensor_build_packages[@]}")
  fi
  if [ -n "$PACKAGE_LIST" ]; then
    while IFS= read -r package; do
      [ -n "$package" ] && packages+=("$package")
    done <<< "$PACKAGE_LIST"
  fi

  printf '%s\n' "${packages[@]}" | awk 'NF && !seen[$0]++'
}

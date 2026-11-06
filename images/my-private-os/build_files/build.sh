#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /
# Required for NetworkManager to even consider them
chmod 600 /etc/NetworkManager/system-connections/OpenAP.conf /etc/NetworkManager/system-connections/SecureAP.nmconnection

# Enable rpmfusion
dnf5 install -y  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf5 install -y  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Install packages for wifi
# NetworkManager-config-connectivity-fedora lets NetworkManager tell "has a
# network" from "has internet", ap-role relies on it
dnf5 install -y NetworkManager-wifi wpa_supplicant wireless-regdb dnsmasq NetworkManager-config-connectivity-fedora
# Install packages for monitoring
dnf5 install -y htop cockpit cockpit-podman cockpit-ostree cockpit-files
# Install dependencies for argon one - libgpiod for the power button, smbus (python3-i2c-tools) for the fan
dnf5 install -y python3-libgpiod i2c-tools python3-i2c-tools smartmontools
# Fedora 45's python3-libgpiod puts gpiod/__init__.py in /usr/lib/python3.*
# but its compiled _ext module in /usr/lib64/python3.*, so `import gpiod` fails
# ("cannot import name '_ext'") and argononed with it. Link _ext next to
# __init__.py; does nothing once the package ships them together again.
for ext in /usr/lib64/python3.*/site-packages/gpiod/_ext.*.so; do
    [ -e "$ext" ] || continue
    pkg="/usr/lib/${ext#/usr/lib64/}"
    pkg="${pkg%/*}"
    if [ -e "$pkg/__init__.py" ] && [ ! -e "$pkg/${ext##*/}" ]; then
        ln -s "$ext" "$pkg/"
    fi
done
# argononed needs both, fail the build if either can't be imported
python3 -c 'import gpiod, smbus; print("gpiod", gpiod.__version__)'
# Install dnf5-plugins to be able to use copr repos
dnf5 install -y dnf5-plugins

# Install netbird - repo and service are created via system_files
dnf5 install -y --setopt=tsflags=noscripts netbird

# Install zellij from copr
dnf5 -y copr enable varlad/zellij
dnf5 install -y zellij
dnf5 -y copr disable varlad/zellij

# Install niri and dms from copr
dnf5 -y copr enable avengemedia/dms
dnf5 install -y niri dms
systemctl --global add-wants niri.service dms
dnf5 -y copr disable avengemedia/dms

# Install greetd with the tuigreet login prompt, it starts niri (see
# /usr/share/my-private-os/greetd.toml)
dnf5 install -y greetd tuigreet

# Caddy serves the gamja web IRC client, Ergo itself runs as a quadlet
# (/usr/share/containers/systemd/ergo.container)
dnf5 install -y caddy

# Retro gaming: RetroArch comes from Flathub (installed on the Pi by
# retroarch-install.service), cage runs it fullscreen as a greetd session
# (/usr/share/wayland-sessions/retroarch.desktop)
dnf5 install -y flatpak cage

# Install cli tools
dnf5 install -y fish helix git rsync

# Install useful graphical applications
dnf5 install -y firefox thunderbird

# Swap Fedora's ffmpeg-free (pulled in by niri/dms and firefox) for RPM Fusion's
# full ffmpeg: ffmpeg-free has no HEVC, E-AC3 or VC-1 decoder and only decodes
# H.264 through openh264, so Kodi couldn't play most video files
dnf5 swap -y --allowerasing ffmpeg-free ffmpeg

# Install kodi, inputstream-adaptive (needed by most streaming add-ons) and
# game controller support
dnf5 install -y kodi kodi-inputstream-adaptive kodi-peripheral-joystick
# Fail the build if a later change pulls ffmpeg-free back in
if rpm -q libavcodec-free; then
    echo "libavcodec-free is installed, Kodi would lose codecs" >&2
    exit 1
fi
# kodi.service runs the binary directly
test -x /usr/lib64/kodi/kodi.bin
# The package's Kodi login session runs it in GBM mode as the logged-in user,
# who can't read keyboards and mice (only the input group can), so Kodi froze.
# /usr/share/wayland-sessions/kodi-user.desktop runs it in cage instead.
rm -f /usr/share/wayland-sessions/kodi-gbm.desktop

systemctl enable podman.socket
systemctl enable cockpit.socket
systemctl enable argononed.service
systemctl enable netbird.service
systemctl enable screen-role.service
systemctl enable ap-role.service
# greetd is display-manager.service, which graphical.target pulls in
systemctl enable greetd.service
systemctl set-default graphical.target
# IRC: ergo.service is generated from its quadlet, enabled by its [Install]
systemctl enable caddy.service
systemctl enable podman-auto-update.timer
systemctl enable retroarch-install.service
systemctl enable flatpak-system-update.timer

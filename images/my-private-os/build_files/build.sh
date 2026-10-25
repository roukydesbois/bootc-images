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

systemctl enable podman.socket
systemctl enable cockpit.socket
systemctl enable argononed.service
systemctl enable netbird.service
systemctl enable screen-role.service
systemctl enable ap-role.service

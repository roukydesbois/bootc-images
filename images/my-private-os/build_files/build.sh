#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /
# Required for NetworkManager to even consider it
chmod 600 /etc/NetworkManager/system-connections/OpenAP.conf

# Enable rpmfusion
dnf5 install -y  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf5 install -y  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Install packages for wifi
dnf5 install -y NetworkManager-wifi wpa_supplicant wireless-regdb dnsmasq
# Install packages for monitoring
dnf5 install -y htop cockpit cockpit-podman cockpit-ostree
# Install dependencies for argon one - maybe python-gpiozero is needed
dnf5 install -y python-pigpio python3-rpi-gpio2 i2c-tools python3-i2c-tools smartmontools
# Install dnf5-plugins to be able to use copr repos
dnf5 install -y dnf5-plugins

# Install netbird - repo and service are created via system_files
dnf5 install -y --setopt=tsflags=noscripts netbird

# Install zellij - repo is created via system_files
dnf5 -y copr enable varlad/zellij
dnf5 install -y zellij
dnf5 -y copr disable varlad/zellij

# Install niri - repo is created via system_files
dnf5 -y copr enable avengemedia/dms
dnf5 install -y niri dms
systemctl --global add-wants niri.service dms
dnf5 -y copr disable avengemedia/dms

# Install cli tools
dnf5 install -y fish helix git

# Install useful graphical applications
dnf5 install -y firefox thunderbird

# Install kodi
dnf5 install -y kodi

systemctl enable podman.socket
systemctl enable cockpit.socket
systemctl enable argononed.service
systemctl enable netbird.service

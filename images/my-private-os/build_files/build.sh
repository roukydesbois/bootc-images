#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /
# Required for NetworkManager to even consider it
chmod 600 /usr/lib/NetworkManager/system-connections/OpenAP.conf

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# Install regular packages
dnf5 install -y htop cockpit cockpit-podman cockpit-ostree
# Install dependencies for argon one - maybe python-gpiozero is needed
dnf5 install -y python-pigpio python3-rpi-gpio2 i2c-tools python3-i2c-tools smartmontools

# Install netbird - repo and service are created via system_files
dnf5 install -y --setopt=tsflags=noscripts netbird

# Install zellij - repo is created via system_files
dnf5 install -y zellij

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket
systemctl enable cockpit.socket
systemctl enable argononed.service
systemctl enable netbird.service

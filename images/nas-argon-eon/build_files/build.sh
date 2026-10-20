#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# Install dependencies for the Argon EON scripts (fan, power button, OLED, RTC, HDD temperature)
dnf5 install -y python3-libgpiod python3-i2c-tools i2c-tools smartmontools

# Install packages for the data disks (LUKS unlocked through Tang) and the NFS exports
dnf5 install -y cryptsetup clevis clevis-luks clevis-systemd btrfs-progs nfs-utils
# Compressed swap in RAM, the OS lives on an SD card
dnf5 install -y zram-generator-defaults

# / is read-only once deployed, so the NFS mount points have to exist in the image
mkdir -p /export/thomelab-dynamic-4tb-hdd /export/thomelab-dynamic-2tb-ssd /export/thomelab-dynamic-1tb-ssd

systemctl enable podman.socket
systemctl enable argononed.service
systemctl enable argoneond.service
# _netdev crypttab entries only start through this target
systemctl enable remote-cryptsetup.target
systemctl enable clevis-luks-askpass.path
systemctl enable var-srv-hdd4tb.mount var-srv-ssd2tb.mount var-srv-ssd1tb.mount
systemctl enable 'export-thomelab\x2ddynamic\x2d4tb\x2dhdd.mount' 'export-thomelab\x2ddynamic\x2d2tb\x2dssd.mount' 'export-thomelab\x2ddynamic\x2d1tb\x2dssd.mount'
systemctl enable nfs-server.service

# Updates are applied by hand (bootc upgrade + reboot): an unplanned reboot takes
# down NFS for thomelab and Garage, which has no replica
systemctl mask bootc-fetch-apply-updates.timer

#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# Install dependencies for the Argon EON scripts (fan, power button, OLED, RTC, HDD temperature)
dnf5 install -y python3-libgpiod python3-i2c-tools i2c-tools smartmontools

systemctl enable podman.socket
systemctl enable argononed.service
systemctl enable argoneond.service

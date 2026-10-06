#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
# dnf5 install -y tmux

dnf5 -y install helix fish iio-sensor-proxy squeekboard

dnf5 -y copr enable dejan/lazygit
dnf5 -y install lazygit
dnf5 -y copr disable dejan/lazygit

dnf5 -y remove firefox

dnf5 -y copr enable varlad/zellij
dnf5 install -y zellij
dnf5 -y copr disable varlad/zellij

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

# Install niri - repo is created via system_files
dnf5 -y copr enable avengemedia/dms
dnf5 install -y niri dms dms-greeter dankcalendar-git
systemctl --global add-wants niri.service dms
dnf5 -y copr disable avengemedia/dms

# Install linux-surface kernel - wait for PR https://github.com/linux-surface/linux-surface/pull/2092 to be merged and have fedora 44 support
# dnf5 -y config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
# dnf5 -y install --allowerasing kernel-surface iptsd libwacom-surface

#### Example for enabling a System Unit File

# systemctl enable podman.socket
systemctl enable greetd
systemctl --user enable dcal

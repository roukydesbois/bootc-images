#!/bin/bash

set -ouex pipefail

### Install packages

# Regular stuff
dnf5 -y install helix fish nautilus papers
# For the tablet mode
dnf5 -y install iio-sensor-proxy
# Runtime libraries for wvkbd (built in its own stage, see Containerfile)
dnf5 -y install cairo pango libxkbcommon

dnf5 -y remove firefox

# COPRs are disabled again right after use so they don't end up enabled on the
# final image
dnf5 -y copr enable dejan/lazygit
dnf5 -y install lazygit
dnf5 -y copr disable dejan/lazygit

dnf5 -y copr enable varlad/zellij
dnf5 -y install zellij
dnf5 -y copr disable varlad/zellij

# niri + DankMaterialShell (shell and greeter)
dnf5 -y copr enable avengemedia/dms
dnf5 -y install niri dms dms-greeter dankcalendar-git
dnf5 -y copr disable avengemedia/dms

# Install linux-surface kernel - wait for PR https://github.com/linux-surface/linux-surface/pull/2092 to be merged and have fedora 44 support
# dnf5 -y config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
# dnf5 -y install --allowerasing kernel-surface iptsd libwacom-surface

### Configuration

# Copied after package installs so our files win over packaged defaults
# instead of relying on RPM's %config(noreplace) handling
cp -avf "/ctx/system_files"/. /

# Fail the build rather than ship a niri config that doesn't parse
niri validate -c /usr/share/niri/surfacego3.kdl
# /usr/share/user-tmpfiles.d relies on the per-user tmpfiles service
test -e /usr/lib/systemd/user/basic.target.wants/systemd-tmpfiles-setup.service

### Services

systemctl --global add-wants niri.service dms
systemctl enable greetd

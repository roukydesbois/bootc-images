#!/bin/bash

set -ouex pipefail

### Install packages

# Regular stuff
# Nautilus also provides the file chooser behind xdg-desktop-portal-gnome,
# which niri's portal config uses for file dialogs
dnf5 -y install helix fish nautilus papers chezmoi
# Phones and cameras in Nautilus: Android (MTP), iPhone (AFC, with the
# base image's usbmuxd) and cameras/photo mode (PTP)
dnf5 -y install gvfs-mtp gvfs-afc gvfs-gphoto2
# French locale (/etc/locale.conf) and OCR language
dnf5 -y install glibc-langpack-fr
# quickCapture DMS plugin: recording, exports, OCR and QR scanning (ffmpeg
# comes with the base image). Installed by command so package names don't
# matter.
dnf5 -y install wf-recorder /usr/bin/magick /usr/bin/img2pdf \
    /usr/bin/tesseract tesseract-langpack-fra /usr/bin/zbarimg
# For the tablet mode
dnf5 -y install iio-sensor-proxy
# Runtime libraries for wvkbd (built in its own stage, see Containerfile)
dnf5 -y install cairo pango libxkbcommon

dnf5 -y remove firefox

# NetBird client (netbirdStatus DMS plugin). The repo is only needed at build
# time; the service unit comes from system_files, so skip the package
# scripts, which would try to install one with `netbird service install`.
cat > /etc/yum.repos.d/netbird.repo <<'REPO'
[netbird]
name=netbird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=1
REPO
dnf5 -y install --setopt=tsflags=noscripts netbird
rm /etc/yum.repos.d/netbird.repo

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
# Unlock the login keyring with the greetd login password. Fedora's
# /etc/pam.d/greetd already calls pam_gnome_keyring, but as optional
# ("-auth"), so it was silently skipped: gnome-keyring comes in as a weak
# dependency, its PAM module doesn't.
dnf5 -y install gnome-keyring-pam

# Install linux-surface kernel - wait for PR https://github.com/linux-surface/linux-surface/pull/2092 to be merged and have fedora 44 support
# dnf5 -y config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
# dnf5 -y install --allowerasing kernel-surface iptsd libwacom-surface

### Configuration

# Copied after package installs so our files win over packaged defaults
# instead of relying on RPM's %config(noreplace) handling
cp -avf "/ctx/system_files"/. /

# Fail the build rather than ship a niri config that doesn't parse
niri validate -c /usr/share/niri/surfacego3.kdl
# greetd only unlocks the keyring if the module is there and the PAM config
# still calls it
test -e /usr/lib64/security/pam_gnome_keyring.so
grep -q pam_gnome_keyring /etc/pam.d/greetd
test -x /usr/libexec/gvfsd-mtp

### Services

systemctl --global add-wants niri.service dms
systemctl enable greetd
systemctl enable surfacego3-flatpak-preinstall.service
systemctl enable netbird.service
# Applies /usr/share/user-tmpfiles.d (per-user niri config) at login
systemctl --global enable systemd-tmpfiles-setup.service
systemctl --global is-enabled systemd-tmpfiles-setup.service

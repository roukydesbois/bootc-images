#!/bin/bash

set -ouex pipefail

# Desktop variant, from the Containerfile's DESKTOP build arg
DESKTOP=${1:?usage: build.sh niri|gnome|kde}
case "$DESKTOP" in
    niri | gnome | kde) ;;
    *) echo "unknown desktop: $DESKTOP" >&2; exit 1 ;;
esac

### Install packages (all desktops)

# Regular stuff
dnf5 -y install helix fish chezmoi
# French locale (/etc/locale.conf)
dnf5 -y install glibc-langpack-fr
# For the tablet mode (screen rotation)
dnf5 -y install iio-sensor-proxy

# Firefox comes as a Flatpak (preinstall.d). base-main, silverblue-main and
# kinoite-main all ship the RPM today; don't fail if one stops doing so.
if rpm -q firefox >/dev/null; then
    dnf5 -y remove firefox
fi

# NetBird client (also the netbirdStatus DMS plugin). The repo is only needed
# at build time; the service unit comes from system_files, so skip the
# package scripts, which would try to install one with
# `netbird service install`.
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

# Install linux-surface kernel - wait for PR https://github.com/linux-surface/linux-surface/pull/2092 to be merged and have fedora 44 support
# dnf5 -y config-manager addrepo --from-repofile=https://pkg.surfacelinux.com/fedora/linux-surface.repo
# dnf5 -y install --allowerasing kernel-surface iptsd libwacom-surface

### Install packages (per desktop)

case "$DESKTOP" in
niri)
    # Nautilus also provides the file chooser behind xdg-desktop-portal-gnome,
    # which niri's portal config uses for file dialogs
    dnf5 -y install nautilus papers
    # Phones and cameras in Nautilus: Android (MTP), iPhone (AFC, with the
    # base image's usbmuxd) and cameras/photo mode (PTP)
    dnf5 -y install gvfs-mtp gvfs-afc gvfs-gphoto2
    # quickCapture DMS plugin: recording, exports, OCR and QR scanning
    # (ffmpeg comes with the base image). Installed by command so package
    # names don't matter.
    dnf5 -y install wf-recorder /usr/bin/magick /usr/bin/img2pdf \
        /usr/bin/tesseract tesseract-langpack-fra /usr/bin/zbarimg
    # Runtime libraries for wvkbd (built in its own stage, see Containerfile)
    dnf5 -y install cairo pango libxkbcommon

    # niri + DankMaterialShell (shell and greeter)
    dnf5 -y copr enable avengemedia/dms
    dnf5 -y install niri dms dms-greeter dankcalendar-git
    dnf5 -y copr disable avengemedia/dms
    # Unlock the login keyring with the greetd login password. Fedora's
    # greetd PAM config already calls pam_gnome_keyring, but as optional
    # ("-auth"), so it was silently skipped: gnome-keyring comes in as a
    # weak dependency, its PAM module doesn't.
    dnf5 -y install gnome-keyring-pam
    ;;
gnome)
    # silverblue-main already has GNOME's on-screen keyboard, autorotate,
    # Nautilus, Papers and GDM (which unlocks the keyring). Phones and
    # cameras in Nautilus, as on niri (no-ops if the base has them).
    dnf5 -y install gvfs-mtp gvfs-afc gvfs-gphoto2
    ;;
kde)
    # On-screen keyboard, made the default in /etc/xdg/kwinrc. Kinoite only
    # ships Maliit, which works less well with the Plasma 6 shell.
    dnf5 -y install plasma-keyboard
    ;;
esac

### Configuration

# Copied after package installs so our files win over packaged defaults
# instead of relying on RPM's %config(noreplace) handling
cp -avf /ctx/system_files/common/. /
if [ -d "/ctx/system_files/$DESKTOP" ]; then
    cp -avf "/ctx/system_files/$DESKTOP/." /
fi

### Checks and services

systemctl enable surfacego3-flatpak-preinstall.service
systemctl enable netbird.service

case "$DESKTOP" in
niri)
    # Fail the build rather than ship a niri config that doesn't parse
    niri validate -c /usr/share/niri/surfacego3.kdl
    # greetd only unlocks the keyring if the module is there and the PAM
    # config still calls it. Fedora 45 ships greetd's PAM config in
    # /usr/lib/pam.d instead of /etc/pam.d; check whichever one PAM will use
    # (/etc wins).
    test -e /usr/lib64/security/pam_gnome_keyring.so
    greetd_pam=/etc/pam.d/greetd
    [ -e "$greetd_pam" ] || greetd_pam=/usr/lib/pam.d/greetd
    grep -q pam_gnome_keyring "$greetd_pam"
    test -x /usr/libexec/gvfsd-mtp

    systemctl --global add-wants niri.service dms
    systemctl enable greetd
    # Applies /usr/share/user-tmpfiles.d (per-user niri config) at login
    systemctl --global enable systemd-tmpfiles-setup.service
    systemctl --global is-enabled systemd-tmpfiles-setup.service
    ;;
gnome)
    test -x /usr/bin/gnome-shell
    test -x /usr/libexec/gvfsd-mtp
    # The base image's login screen is still enabled
    readlink /etc/systemd/system/display-manager.service | grep -q gdm
    ;;
kde)
    test -x /usr/bin/plasmashell
    # The kwinrc default must point at a desktop file that exists
    test -e "$(sed -n 's/^InputMethod=//p' /etc/xdg/kwinrc)"
    # The base image's login screen (SDDM or Plasma Login) is still enabled
    readlink -e /etc/systemd/system/display-manager.service
    ;;
esac

### Image signature check
# bootc only accepts updates of this image signed with its cosign key
# (images/surfacego3-os/cosign.pub): a sigstoreSigned scope for this repository in
# containers-policy.json, with the signatures read from the registry
# (use-sigstore-attachments). The default policy stays as it is, so other
# images (quadlets, flatpak runtimes, ...) aren't affected. This also works
# with a plain `bootc switch` (no --enforce-container-sigpolicy, which
# refuses a policy whose default is insecureAcceptAnything).
image=ghcr.io/roukydesbois/bootc-images/surfacego3-os
key=/etc/pki/containers/surfacego3-os.pub
install -Dm0644 /ctx/cosign.pub "$key"
command -v jq >/dev/null || dnf5 -y install jq
# Fedora ships the default policy in /usr/share/containers (read when /etc
# has none); ublue's base images have their own in /etc. Start from the one
# in effect and write the result to /etc, which takes precedence.
current=/etc/containers/policy.json
[ -f "$current" ] || current=/usr/share/containers/policy.json
policy=$(jq --arg image "$image" --arg key "$key" \
    '.transports.docker[$image] = [{type: "sigstoreSigned", keyPath: $key, signedIdentity: {type: "matchRepository"}}]' \
    "$current")
mkdir -p /etc/containers/registries.d
printf '%s\n' "$policy" >/etc/containers/policy.json
cat >/etc/containers/registries.d/bootc-images-surfacego3-os.yaml <<YAML
docker:
  $image:
    use-sigstore-attachments: true
YAML
jq -e --arg image "$image" '.transports.docker[$image][0].type == "sigstoreSigned"' /etc/containers/policy.json

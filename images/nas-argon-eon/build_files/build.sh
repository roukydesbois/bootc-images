#!/bin/bash

set -ouex pipefail

# Shared files first (common/), so this image's own files can override them
cp -avf /ctx/common_files/. /
# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# Install dependencies for the Argon EON scripts (fan, power button, OLED, RTC, HDD temperature)
dnf5 install -y python3-libgpiod python3-i2c-tools i2c-tools smartmontools
# Fedora 45's python3-libgpiod (2.3.1, 2.3.2 in testing) installs gpiod's Python files under
# /usr/lib but its compiled _ext under /usr/lib64, so `import gpiod` fails (related to
# rhbz#2559419). Link _ext next to the Python files; no-op once both live in one place.
for ext in /usr/lib64/python3*/site-packages/gpiod/_ext*.so; do
	pure="/usr/lib/${ext#/usr/lib64/}"
	if [ -d "$(dirname "$pure")" ] && [ ! -e "$pure" ]; then
		ln -s "$ext" "$pure"
	fi
done
# Fail the build if the Argon scripts can't import their libraries on this Fedora/Python
python3 -c 'import gpiod, smbus'

# Install packages for the data disks (LUKS unlocked through Tang) and the NFS exports
dnf5 install -y cryptsetup clevis clevis-luks clevis-systemd btrfs-progs nfs-utils
# Host firewall (nas-firewall.service, its own nftables table)
dnf5 install -y nftables
# Compressed swap in RAM, the OS lives on an SD card
dnf5 install -y zram-generator-defaults
# greenboot: health checks after each boot, rollback to the previous image if
# the required ones fail (/usr/lib/greenboot/check). Not
# greenboot-default-health-checks: it makes the checks wait for network-online.
dnf5 install -y greenboot
# NetBird client (repo and service come from system_files), for NetBird SSH from
# admins. The peer is enrolled on the machine with a setup key (README).
dnf5 install -y --setopt=tsflags=noscripts netbird
semodule -i /usr/share/nas-argon-eon/selinux/netbird-ssh-login.cil

# zellij, terminal multiplexer for SSH sessions (config: /etc/zellij from
# common/). Upstream's static "no-web" build: Fedora and EPEL don't package
# zellij, and the COPR the desktops use is stuck at 0.42 (too old for this
# config). The published checksum is the binary's, so check after unpacking.
# renovate: datasource=github-releases depName=zellij-org/zellij
ZELLIJ_VERSION=v0.46.0
zellij_name="zellij-no-web-$(uname -m)-unknown-linux-musl"
zellij_url="https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VERSION}/${zellij_name}"
zellij_tmp=$(mktemp -d)
curl -fsSL --retry 3 -o "$zellij_tmp/zellij.tar.gz" "${zellij_url}.tar.gz"
curl -fsSL --retry 3 -o "$zellij_tmp/zellij.sha256sum" "${zellij_url}.sha256sum"
tar -xzf "$zellij_tmp/zellij.tar.gz" -C "$zellij_tmp" zellij
echo "$(cut -d' ' -f1 "$zellij_tmp/zellij.sha256sum")  $zellij_tmp/zellij" | sha256sum -c -
install -m 0755 "$zellij_tmp/zellij" /usr/bin/zellij
rm -rf "$zellij_tmp"

# Backups to BorgBase (see /etc/borgmatic.d)
dnf5 install -y borgmatic borgbackup

# Cockpit web console: system, storage (LUKS/btrfs/disks), network, SELinux, the
# Garage container, files, and bootc deployments (cockpit-ostree). No weak deps:
# they'd pull cockpit-packagekit + PackageKit, which can't do anything on bootc.
dnf5 install -y --setopt=install_weak_deps=False \
	cockpit-ws cockpit-bridge cockpit-system cockpit-storaged udisks2-btrfs \
	cockpit-networkmanager cockpit-selinux cockpit-podman cockpit-ostree cockpit-files

# / is read-only once deployed, so the NFS mount points have to exist in the image
mkdir -p /export/thomelab-dynamic-4tb-hdd /export/thomelab-dynamic-2tb-ssd /export/thomelab-dynamic-1tb-ssd

systemctl enable podman.socket
systemctl enable cockpit.socket
# Disk health and update notifications (ntfy, see /etc/nas-argon-eon/README)
systemctl enable smartd.service
systemctl enable nas-smart-check.timer nas-btrfs-errors.timer nas-check-update.timer
systemctl enable nas-backup.timer
# The Pi has no clock Linux reads at boot, so each boot starts with an old date.
# OnCalendar timers wait for time-sync.target, but without chrony-wait nothing
# holds it until chrony has synced: Persistent=true timers then ignore their
# last-run stamp ("in the future") and run again (a 2nd daily backup on every
# reboot). chrony-wait waits for at most 180 s.
systemctl enable chrony-wait.service
systemctl enable netbird.service
systemctl enable nas-btrfs-scrub-ssd1tb.timer nas-btrfs-scrub-ssd2tb.timer nas-btrfs-scrub-hdd4tb.timer
systemctl enable argononed.service
systemctl enable argoneond.service
systemctl enable argon-enable-i2c.service
# greenboot: the checks, and the boot counter that makes a failing image roll back
systemctl enable greenboot-healthcheck.service greenboot-set-rollback-trigger.service
# _netdev crypttab entries only start through this target
systemctl enable remote-cryptsetup.target
systemctl enable clevis-luks-askpass.path
systemctl enable var-srv-hdd4tb.mount var-srv-ssd2tb.mount var-srv-ssd1tb.mount
systemctl enable 'export-thomelab\x2ddynamic\x2d4tb\x2dhdd.mount' 'export-thomelab\x2ddynamic\x2d2tb\x2dssd.mount' 'export-thomelab\x2ddynamic\x2d1tb\x2dssd.mount'
systemctl enable nfs-server.service
# Starts only once /etc/nas-argon-eon/firewall-local.nft exists (README)
systemctl enable nas-firewall.service

# Updates are applied by hand (nas-update: soft reboot when the kernel is
# unchanged): an unplanned reboot takes down NFS for thomelab and Garage, which
# has no replica
systemctl mask bootc-fetch-apply-updates.timer

# Metrics pushed to thomelab (node-exporter + prometheus-agent quadlets, enabled
# by their [Install] section). Their images are logically bound: `bootc upgrade`
# pulls them before restarting, so a (soft) reboot never waits on a registry.
mkdir -p /usr/lib/bootc/bound-images.d
for quadlet in node-exporter.container prometheus-agent.container garage.container; do
	ln -sf "/usr/share/containers/systemd/$quadlet" "/usr/lib/bootc/bound-images.d/$quadlet"
done

### Image signature check
# bootc only accepts updates of this image signed with its cosign key
# (images/nas-argon-eon/cosign.pub): a sigstoreSigned scope for this repository in
# containers-policy.json, with the signatures read from the registry
# (use-sigstore-attachments). The default policy stays as it is, so other
# images (quadlets, flatpak runtimes, ...) aren't affected. This also works
# with a plain `bootc switch` (no --enforce-container-sigpolicy, which
# refuses a policy whose default is insecureAcceptAnything).
image=ghcr.io/roukydesbois/bootc-images/nas-argon-eon
key=/etc/pki/containers/nas-argon-eon.pub
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
cat >/etc/containers/registries.d/bootc-images-nas-argon-eon.yaml <<YAML
docker:
  $image:
    use-sigstore-attachments: true
YAML
jq -e --arg image "$image" '.transports.docker[$image][0].type == "sigstoreSigned"' /etc/containers/policy.json

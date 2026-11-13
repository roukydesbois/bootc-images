#!/bin/bash
set -euxo pipefail

### Packages
# greenboot: health checks after each update, rollback if they fail
dnf -y install nftables greenboot greenboot-default-health-checks jq

# NetBird and Tailscale clients. Their repos are only needed at build time.
# NetBird's service unit comes from system_files, so skip the package
# scripts, which would try to install one with `netbird service install`.
cat >/etc/yum.repos.d/netbird.repo <<'REPO'
[netbird]
name=netbird
baseurl=https://pkgs.netbird.io/yum/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.netbird.io/yum/repodata/repomd.xml.key
repo_gpgcheck=1
REPO
dnf -y install --setopt=tsflags=noscripts netbird
rm /etc/yum.repos.d/netbird.repo

curl -fsSL -o /etc/yum.repos.d/tailscale.repo https://pkgs.tailscale.com/stable/centos/10/tailscale.repo
dnf -y install tailscale
rm /etc/yum.repos.d/tailscale.repo

### Configuration
cp -avf /ctx/system_files/. /
chmod 0440 /etc/sudoers.d/wheel-nopasswd
ln -sf ../usr/share/zoneinfo/Europe/Paris /etc/localtime

# Fail the build rather than ship a firewall, sudoers or sshd config that
# doesn't parse
nft -c -f /usr/share/public-node/firewall.nft
visudo -c -f /etc/sudoers.d/wheel-nopasswd
ssh-keygen -q -t ed25519 -N '' -f /tmp/sshd-check-key
sshd -t -h /tmp/sshd-check-key
test -s /usr/share/public-node/ssh/roukydesbois.keys

### Services
systemctl enable public-node-firewall.service
systemctl enable sshd.service
systemctl enable netbird.service
systemctl enable tailscaled.service tailscale-netfilter-off.service
# First boot only: they run when the install left a key on the disk
systemctl enable public-node-netbird-enroll.service public-node-tailscale-enroll.service
systemctl enable greenboot-healthcheck.service greenboot-task-runner.service \
    redboot-task-runner.service redboot-auto-reboot.service greenboot-status.service \
    greenboot-grub2-set-counter.service greenboot-grub2-set-success.service \
    greenboot-rpm-ostree-grub2-check-fallback.service
# Nightly updates (timer drop-in in system_files)
systemctl enable bootc-fetch-apply-updates.timer
# The stock nftables.service would `flush ruleset` on reload/stop, wiping
# NetBird's, Tailscale's and podman's tables
systemctl mask nftables.service

### Image signature check
# bootc only accepts updates of this image signed with its cosign key
# (images/public-node/cosign.pub): a sigstoreSigned scope for this repository in
# containers-policy.json, with the signatures read from the registry
# (use-sigstore-attachments). The default policy stays as it is, so other
# images (quadlets, flatpak runtimes, ...) aren't affected. This also works
# with a plain `bootc switch` (no --enforce-container-sigpolicy, which
# refuses a policy whose default is insecureAcceptAnything).
image=ghcr.io/roukydesbois/bootc-images/public-node
key=/etc/pki/containers/public-node.pub
install -Dm0644 /ctx/cosign.pub "$key"
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
cat >/etc/containers/registries.d/bootc-images-public-node.yaml <<YAML
docker:
  $image:
    use-sigstore-attachments: true
YAML
jq -e --arg image "$image" '.transports.docker[$image][0].type == "sigstoreSigned"' /etc/containers/policy.json

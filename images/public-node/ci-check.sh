#!/bin/bash
# Run by the build workflow after the image is built: checks that need a
# running container. Usage: ci-check.sh <image>
set -euo pipefail
image="$1"

# The firewall ruleset parses. nft --check needs netlink: its own network
# namespace with NET_ADMIN, nothing is loaded on the runner.
podman run --rm --network none --cap-add NET_ADMIN "$image" \
    nft --check --file /usr/share/public-node/firewall.nft

# The enabled units exist (a renamed unit would only show at boot)
podman run --rm "$image" systemctl --root=/ is-enabled \
    public-node-firewall.service sshd.service netbird.service tailscaled.service \
    tailscale-netfilter-off.service public-node-netbird-enroll.service \
    public-node-tailscale-enroll.service greenboot-healthcheck.service \
    greenboot-set-rollback-trigger.service bootc-fetch-apply-updates.timer

#!/bin/bash
# Run by the build workflow after the image is built: checks that need a
# running container. Usage: ci-check.sh <image>
set -euo pipefail
image="$1"

# The firewall ruleset parses. nft --check needs netlink: its own network
# namespace with NET_ADMIN, nothing is loaded on the runner.
podman run --rm --network none --cap-add NET_ADMIN "$image" \
    nft --check --file /usr/share/public-node/firewall.nft

# The quadlets generate valid units
podman run --rm "$image" /usr/libexec/podman/quadlet -dryrun >/dev/null

# Each logically bound image points at an existing quadlet
podman run --rm "$image" sh -c 'for f in /usr/lib/bootc/bound-images.d/*; do test -e "$f" || { echo "dangling: $f" >&2; exit 1; }; done'

# NetBird's config renders from the template with every secret in place, and
# the template has no secret left in it
podman run --rm "$image" sh -c '
    set -e
    mkdir -p /tmp/s
    for n in relay-secret datastore-encryption-key idp-client-secret proxy-token; do echo "test-$n" >/tmp/s/$n; done
    SECRETS=/tmp/s OUT=/tmp/o /usr/libexec/public-node/netbird-config
    jq -e ".Relay.Secret == \"test-relay-secret\" and .DataStoreEncryptionKey == \"test-datastore-encryption-key\" and .IdpManagerConfig.ClientConfig.ClientSecret == \"test-idp-client-secret\"" /tmp/o/management.json >/dev/null
    grep -qx NB_AUTH_SECRET=test-relay-secret /tmp/o/relay.env
    grep -qx NB_PROXY_TOKEN=test-proxy-token /tmp/o/proxy.env
    jq -e ".Relay.Secret == \"\" and .DataStoreEncryptionKey == \"\" and .IdpManagerConfig.ClientConfig.ClientSecret == \"\"" /usr/share/public-node/netbird/management.json >/dev/null
'

# The enabled units exist (a renamed unit would only show at boot). Quadlet
# units like traefik.service are generated at boot: checked by -dryrun above.
podman run --rm "$image" systemctl --root=/ is-enabled \
    public-node-firewall.service sshd.service netbird.service tailscaled.service \
    tailscale-netfilter-off.service public-node-netbird-enroll.service \
    public-node-tailscale-enroll.service greenboot-healthcheck.service \
    greenboot-set-rollback-trigger.service bootc-fetch-apply-updates.timer

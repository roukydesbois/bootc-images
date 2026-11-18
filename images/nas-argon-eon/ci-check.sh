#!/bin/bash
# Run by the build workflow after the image is built: checks that need a
# running container. Usage: ci-check.sh <image>
set -euo pipefail
image="$1"

# nas-update uses --soft-reboot: fail the build if this bootc doesn't know
# it, rather than the next update
podman run --rm "$image" bootc upgrade --help | grep -q -- '--soft-reboot'
podman run --rm "$image" test -x /usr/libexec/bootc-images/sepolicy-match-image
podman run --rm "$image" bash -n /usr/bin/nas-update

# The quadlets generate valid units
podman run --rm "$image" /usr/libexec/podman/quadlet -dryrun >/dev/null

# Each logically bound image points at an existing quadlet
podman run --rm "$image" sh -c 'for f in /usr/lib/bootc/bound-images.d/*; do test -e "$f" || { echo "dangling: $f" >&2; exit 1; }; done'

# The Prometheus agent's config is valid (promtool from the same image)
prom_image=$(podman run --rm "$image" sed -n 's/^Image=//p' /usr/share/containers/systemd/prometheus-agent.container)
prom_cfg=$(mktemp)
podman run --rm "$image" cat /usr/share/nas-argon-eon/prometheus/agent.yml >"$prom_cfg"
# mktemp makes it 0600; the Prometheus image runs as nobody
chmod 0644 "$prom_cfg"
podman run --rm --network none --entrypoint promtool -v "$prom_cfg:/agent.yml:ro,Z" "$prom_image" \
    check config --agent /agent.yml

# The firewall ruleset parses, with an example local file. nft --check needs
# netlink: its own network namespace with NET_ADMIN, nothing is loaded.
podman run --rm --network none --cap-add NET_ADMIN "$image" sh -c '
    set -e
    mkdir -p /etc/nas-argon-eon
    printf "add element inet nas_argon_eon clients { 192.0.2.0/24 }\nadd element inet nas_argon_eon admins { 198.51.100.7 }\n" >/etc/nas-argon-eon/firewall-local.nft
    nft --check --file /usr/share/nas-argon-eon/firewall.nft
'
podman run --rm "$image" systemctl --root=/ is-enabled nas-firewall.service

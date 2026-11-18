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

# Weekly updates are on, with the soft-reboot drop-in, and the "update
# available" reminder is off
podman run --rm "$image" systemctl --root=/ is-enabled bootc-fetch-apply-updates.timer
podman run --rm "$image" grep -q -- "--soft-reboot=auto" /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/20-soft-reboot.conf
! podman run --rm "$image" systemctl --root=/ is-enabled --quiet nas-check-update.timer

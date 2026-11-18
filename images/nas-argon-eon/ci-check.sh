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
# promtool also wants the files the config points to (Garage's token)
prom_secrets=$(mktemp -d)
echo test-token >"$prom_secrets/garage-metrics-token"
chmod 0755 "$prom_secrets" && chmod 0644 "$prom_secrets/garage-metrics-token"
podman run --rm --network none --entrypoint promtool -v "$prom_cfg:/agent.yml:ro,Z" \
    -v "$prom_secrets:/etc/prometheus/secrets:ro,Z" "$prom_image" \
    check config --agent /agent.yml

# smartctl_exporter knows the flags its quadlet passes (a renamed flag would
# only show as a failing unit on the NAS)
smart_image=$(podman run --rm "$image" sed -n 's/^Image=//p' /usr/share/containers/systemd/smartctl-exporter.container)
smart_help=$(podman run --rm "$smart_image" --help 2>&1)
for flag in --web.listen-address --smartctl.scan-device-type --smartctl.interval; do
    grep -q -- "$flag" <<<"$smart_help" || { echo "smartctl_exporter has no $flag" >&2; exit 1; }
done

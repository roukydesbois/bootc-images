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

# greenboot's checks parse, and its units are enabled (a renamed unit would
# only show at boot)
podman run --rm "$image" sh -c 'for f in /usr/lib/greenboot/check/*/*.sh; do bash -n "$f" || exit 1; test -x "$f" || { echo "not executable: $f" >&2; exit 1; }; done'
podman run --rm "$image" systemctl --root=/ is-enabled \
    greenboot-healthcheck.service greenboot-set-rollback-trigger.service

# Garage's version guard: an older version than the one stamped is refused
# (stub sender), the same or newer passes and raises the stamp
podman run --rm "$image" sh -c '
    set -e
    printf "#!/bin/sh\nexit 0\n" >/tmp/stub && chmod +x /tmp/stub
    run() { printf "Image=docker.io/dxflrs/garage:%s@sha256:x\n" "$1" >/tmp/q; QUADLET=/tmp/q STAMP=/tmp/s NOTIFY=/tmp/stub /usr/libexec/nas-argon-eon/garage-version-guard; }
    run v2.5.0 && test "$(cat /tmp/s)" = v2.5.0
    ! run v2.2.0
    run v2.10.0 && test "$(cat /tmp/s)" = v2.10.0
    ! run v2.5.0
    grep -q "^ExecCondition=/usr/libexec/nas-argon-eon/garage-version-guard" /usr/share/containers/systemd/garage.container
'

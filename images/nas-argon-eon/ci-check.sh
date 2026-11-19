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

# The failure alert (common/): the handler keeps the log and calls the
# sender with the unit name, priority and tags (stub instead of ntfy); the
# NAS's ntfy.env is linked where the shared sender reads it
podman run --rm "$image" sh -c '
    set -e
    test -f /usr/lib/systemd/system/bootc-images-notify-failure@.service
    grep -q "^ExecStart=/usr/libexec/bootc-images/notify-unit-failure" /usr/lib/systemd/system/nas-notify-failure@.service
    mkdir -p /tmp/failures
    printf "#!/bin/sh\necho \"\$1|\$3|\$4\" >/tmp/sent\n" >/tmp/stub && chmod +x /tmp/stub
    FAILURES=/tmp/failures NOTIFY=/tmp/stub /usr/libexec/bootc-images/notify-unit-failure test.service
    grep -qx "test.service failed|high|warning" /tmp/sent
    grep -qx "L /etc/bootc-images/ntfy.env - - - - /etc/nas-argon-eon/ntfy.env" /usr/lib/tmpfiles.d/nas-argon-eon.conf
'
# No unit names a ntfy failure handler that doesn't exist (only ours:
# Fedora's own units have other OnFailure= targets, like getty@%i)
podman run --rm "$image" sh -c '
    for h in $(grep -rhoE "OnFailure=[^ ]*notify-failure@%n\.service" /usr/lib/systemd/system /usr/share/containers/systemd | sed "s/OnFailure=//; s/%n//" | sort -u); do
        test -f "/usr/lib/systemd/system/$h" || { echo "missing OnFailure handler $h" >&2; exit 1; }
    done
'

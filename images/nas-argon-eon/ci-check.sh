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

# The firewall ruleset parses, with an example local file. nft --check needs
# netlink: its own network namespace with NET_ADMIN, nothing is loaded.
podman run --rm --network none --cap-add NET_ADMIN "$image" sh -c '
    set -e
    mkdir -p /etc/nas-argon-eon
    printf "add element inet nas_argon_eon clients { 192.0.2.0/24 }\nadd element inet nas_argon_eon admins { 198.51.100.7 }\n" >/etc/nas-argon-eon/firewall-local.nft
    nft --check --file /usr/share/nas-argon-eon/firewall.nft
'
podman run --rm "$image" systemctl --root=/ is-enabled nas-firewall.service

# The failure alert (common/): the handler keeps the log and calls the
# sender with the unit name, priority and tags (stub instead of ntfy); the
# NAS's ntfy.env is linked where the shared sender reads it
podman run --rm "$image" sh -c '
    set -e
    test -f /usr/lib/systemd/system/bootc-images-notify-failure@.service
    # The NAS-only names are gone: nothing may still call them
    if grep -rnE "nas-notify-failure@|/usr/libexec/nas-argon-eon/notify( |\"|$)" /usr/lib/systemd /usr/share/containers/systemd /usr/libexec /usr/lib/greenboot; then echo "removed notify names still used" >&2; exit 1; fi
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

# The system backup's helper parses, and every borgmatic job validates
podman run --rm "$image" bash -n /usr/libexec/nas-argon-eon/system-backup-prepare
podman run --rm -e BORGBASE_REPO=ssh://test@example.invalid/./repo "$image" \
    sh -c 'for f in /etc/borgmatic.d/*.yaml; do borgmatic config validate -c "$f" || exit 1; done'
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
    run v2.5.0
    test "$(cat /tmp/s)" = v2.5.0
    if run v2.2.0; then echo "guard let an older Garage start" >&2; exit 1; fi
    run v2.10.0
    test "$(cat /tmp/s)" = v2.10.0
    if run v2.5.0; then echo "guard let an older Garage start" >&2; exit 1; fi
    grep -q "^ExecCondition=/usr/libexec/nas-argon-eon/garage-version-guard" /usr/share/containers/systemd/garage.container
'

# No ordering cycles in the boot transaction: systemd breaks one by silently
# dropping a unit's start job (argononed after greenboot waited on it)
cycles=$(podman run --rm "$image" systemd-analyze verify multi-user.target 2>&1 | grep -i 'ordering cycle' || true)
[ -z "$cycles" ] || { echo "$cycles" >&2; exit 1; }

# zellij (common/ config, upstream binary from build.sh): runs, and the
# config in /etc/zellij parses with this exact version
podman run --rm -e HOME=/tmp "$image" sh -c '
    set -e
    zellij --version
    zellij setup --check | grep -q "\[CONFIG FILE\]: Well defined"
    zellij setup --check | grep -q "LOOKING FOR CONFIG FILE FROM\]: \"/etc/zellij/config.kdl\""
'

# nas-smart-check alerts on the right SMART attributes, once per change
# (fake smartctl and ntfy, smart-check-test.sh)
podman run --rm -v "$PWD/smart-check-test.sh:/smart-check-test.sh:ro,Z" "$image" sh /smart-check-test.sh

#!/bin/bash
# greenboot: a boot that fails these is rolled back to the previous image.
# Local checks only: anything that depends on the network or other hosts
# (NetBird management, ACME, ...) would roll back good images during an
# outage elsewhere. Each check says why it failed (greenboot logs stderr).
set -uo pipefail

nft list table inet public_node >/dev/null || { echo "firewall table inet public_node not loaded" >&2; exit 1; }

# sshd and Traefik only need the image and their static config, so a failure
# here is this image's fault. greenboot runs early in the boot (the drop-in
# orders it after them), so give each a minute.
wait_for() {
    local what="$1"; shift
    for _ in $(seq 1 12); do
        "$@" && return 0
        sleep 5
    done
    echo "$what" >&2
    exit 1
}
wait_for "sshd.service isn't active" systemctl is-active --quiet sshd.service
wait_for "traefik doesn't answer on 127.0.0.1:8080/ping" curl -fsS --max-time 5 -o /dev/null http://127.0.0.1:8080/ping
# ...and loaded its routes: a file provider that fails to start leaves
# Traefik answering /ping with no route at all
wait_for "traefik has no routes from /etc/traefik/dynamic" \
    sh -c 'curl -fsS --max-time 5 http://127.0.0.1:8080/api/http/routers | jq -e "any(.[]; .provider == \"file\")" >/dev/null'

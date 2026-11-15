#!/bin/bash
# greenboot: a boot that fails these is rolled back to the previous image.
# Local checks only: anything that depends on the network or other hosts
# (NetBird management, ACME, ...) would roll back good images during an
# outage elsewhere.
set -euo pipefail
nft list table inet public_node >/dev/null
systemctl is-active --quiet sshd.service
# Every public service goes through Traefik. It only needs its static config
# and the image, which bootc pulled before the reboot, so a failure here is
# this image's fault. Give it a minute to start.
for _ in $(seq 1 12); do
    curl -fsS --max-time 5 http://127.0.0.1:8080/ping >/dev/null && exit 0
    sleep 5
done
echo "traefik doesn't answer on 127.0.0.1:8080/ping" >&2
exit 1

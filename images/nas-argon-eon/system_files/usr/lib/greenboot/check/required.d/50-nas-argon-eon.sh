#!/bin/bash
# greenboot: a boot that fails these is rolled back to the previous image.
# Each check says why it failed (greenboot logs stderr).
#
# Only what this image is responsible for. The data disks unlock through Tang
# on another host: if they aren't unlocked after a few minutes, that's
# Tang's or the network's problem, not this image's, so the checks that need
# the disks are skipped (wanted.d warns) instead of rolling back a good image.
set -uo pipefail

wait_for() {
    local tries="$1" what="$2"; shift 2
    for _ in $(seq 1 "$tries"); do
        "$@" && return 0
        sleep 5
    done
    echo "$what" >&2
    return 1
}

# sshd only needs the image: a minute is plenty
wait_for 12 "sshd.service isn't active" systemctl is-active --quiet sshd.service || exit 1
# The quadlet generator turned garage.container into a unit
systemctl cat garage.service >/dev/null 2>&1 || { echo "garage.service wasn't generated from its quadlet" >&2; exit 1; }

# The disks: up to 5 minutes for Tang, then give up on the disk checks
if ! wait_for 60 "data disks not mounted after 5 minutes (Tang?), disk checks skipped" \
    sh -c 'mountpoint -q /var/srv/hdd4tb && mountpoint -q /var/srv/ssd2tb && mountpoint -q /var/srv/ssd1tb'; then
    exit 0
fi

# With the disks there, NFS and Garage have everything they need
wait_for 24 "nfs-server.service isn't active" systemctl is-active --quiet nfs-server.service || exit 1
wait_for 12 "no NFS export is active (exportfs)" sh -c 'exportfs | grep -q "^/export/"' || exit 1
wait_for 36 "Garage doesn't answer 127.0.0.1:3903/health" \
    curl -fsS --max-time 5 -o /dev/null http://127.0.0.1:3903/health || exit 1
exit 0

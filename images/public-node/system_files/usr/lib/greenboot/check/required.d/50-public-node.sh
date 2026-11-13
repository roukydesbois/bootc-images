#!/bin/bash
# greenboot: a boot that fails these is rolled back to the previous image.
# Local checks only: anything that depends on the network or other hosts
# (NetBird management, ACME, ...) would roll back good images during an
# outage elsewhere.
set -euo pipefail
nft list table inet public_node >/dev/null
systemctl is-active --quiet sshd.service

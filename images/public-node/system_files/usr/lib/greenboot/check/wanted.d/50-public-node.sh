#!/bin/bash
# greenboot: logged as a warning, no rollback
set -euo pipefail
systemctl is-active --quiet netbird.service
systemctl is-active --quiet tailscaled.service

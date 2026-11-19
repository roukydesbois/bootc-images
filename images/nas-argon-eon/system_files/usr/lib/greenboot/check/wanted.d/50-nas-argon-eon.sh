#!/bin/bash
# greenboot: logged as a warning, no rollback. Checks every item (no early
# exit) so the log lists everything that's off.
set -uo pipefail
rc=0
warn() { echo "$1" >&2; rc=1; }

for unit in netbird.service node-exporter.service prometheus-agent.service \
    argononed.service argoneond.service; do
    # Masked by hand (as after the Fedora 45 upgrade) means no fan control
    [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = masked ] && warn "$unit is masked"
    systemctl is-active --quiet "$unit" || warn "$unit isn't active"
done
for disk in hdd4tb ssd2tb ssd1tb; do
    [ -e "/dev/mapper/$disk" ] || warn "data disk $disk isn't unlocked"
done
exit "$rc"

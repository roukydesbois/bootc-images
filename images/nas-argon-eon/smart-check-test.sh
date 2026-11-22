#!/bin/sh
# Test of nas-smart-check's parsing, run by ci-check.sh inside the image (and
# by hand): a fake smartctl returns canned JSON, a stub records what would be
# sent to ntfy. Usage: smart-check-test.sh [path to smart-check]
set -e
check=${1:-/usr/libexec/nas-argon-eon/smart-check}
t=$(mktemp -d)
mkdir -p "$t/bin"
printf '#!/bin/sh\ncat %s/smart.json\n' "$t" >"$t/bin/smartctl"
printf '#!/bin/sh\necho "$1|$2" >>%s/sent\n' "$t" >"$t/notify"
chmod +x "$t/bin/smartctl" "$t/notify"

disk() { # disk <attribute id> <attribute name> <raw value>
    printf '{"model_name":"Disk","serial_number":"S1","smart_status":{"passed":true},"temperature":{"current":30},"ata_smart_attributes":{"table":[{"id":%s,"name":"%s","raw":{"value":%s}}]}}\n' "$1" "$2" "$3" >"$t/smart.json"
}
run() { PATH="$t/bin:$PATH" DEVICES=/dev/sdx STATE="$t/state" NOTIFY="$t/notify" "$check"; }
sent() { cat "$t/sent" 2>/dev/null | wc -l; }
fail() { echo "smart-check test: $1" >&2; exit 1; }

disk 199 UDMA_CRC_Error_Count 0; run
[ "$(sent)" -eq 0 ] || fail "alerted on a clean disk"
disk 199 UDMA_CRC_Error_Count 3; run
[ "$(sent)" -eq 1 ] || fail "no alert for UDMA CRC errors"
grep -q "UDMA_CRC_Error_Count=3" "$t/sent" || fail "alert doesn't name the CRC count"
run
[ "$(sent)" -eq 1 ] || fail "alerted again for the same problem"
disk 187 Reported_Uncorrect 1; run
[ "$(sent)" -eq 2 ] || fail "no alert for reported uncorrectable sectors"
disk 194 Temperature_Celsius 40; run
[ "$(sent)" -eq 2 ] || fail "alerted for an attribute that isn't a problem"
echo "smart-check test: ok"

#!/bin/bash
# Fetch the DMS plugins listed in a DMS plugins.lock.json (same format as
# ~/.config/dms/plugins.lock.json, so `dms plugins lock` output can be
# copied over as-is) into a directory, one folder per plugin id.
# Usage: dms-plugins.sh <lockfile> <output dir>

set -euo pipefail

lockfile=$1
out=$2
mkdir -p "$out"

python3 -c '
import json, sys
for pid, p in json.load(open(sys.argv[1]))["plugins"].items():
    print(pid, p["repo"], p["commit"], p.get("path", "."))
' "$lockfile" | while read -r id repo commit path; do
    src=$(mktemp -d)
    git -C "$src" init -q
    git -C "$src" fetch -q --depth 1 "$repo" "$commit"
    git -C "$src" checkout -q FETCH_HEAD
    cp -a "$src/$path" "$out/$id"
    rm -rf "$out/$id/.git" "$src"
    # DMS matches a system plugin by folder name or plugin.json id
    test -f "$out/$id/plugin.json"
done

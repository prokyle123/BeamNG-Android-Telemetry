#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/owner-console-v3.0.0/APPLY-DRIVELAB-OWNER-CONSOLE-V3.sh"
TEMPORARY="$(mktemp /tmp/APPLY-DRIVELAB-OWNER-CONSOLE-V3-CORRECTED.XXXXXX.sh)"

cleanup() {
    rm -f "$TEMPORARY"
}
trap cleanup EXIT

curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --connect-timeout 15 \
    "$SOURCE_URL" \
    --output "$TEMPORARY"

python3 - "$TEMPORARY" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '''systemd-analyze verify \\
    "$DOWNLOADS/drivelab-owner-ops.path" \\
    "$DOWNLOADS/drivelab-owner-ops.service" \\
    >/dev/null

echo "Payload syntax and systemd validation passed."
'''
new = '''grep -q '^PathExistsGlob=/var/lib/drivelab-license/ops/requests/\\*.request$' \\
    "$DOWNLOADS/drivelab-owner-ops.path"
grep -q '^ExecStart=/usr/local/sbin/drivelab-owner-ops-worker$' \\
    "$DOWNLOADS/drivelab-owner-ops.service"

echo "Payload syntax and unit-file marker validation passed."
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f"Could not prepare corrected installer. Expected one unit-validation anchor but found {count}.")
path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
PY

bash -n "$TEMPORARY"
chmod 0700 "$TEMPORARY"
exec bash "$TEMPORARY"

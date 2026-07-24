#!/usr/bin/env bash
set -Eeuo pipefail

ORIGINAL_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/e9ceadc4932cf3adb7023ae288ba37bfdee7a828/patches/lifecycle-intelligence-v1/server/PROMOTE-TESTED-STAGE.sh"
WORK_ROOT="/var/lib/drivelab-lifecycle-promotion-host-fix"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$WORK_ROOT/$STAMP"
ORIGINAL="$WORK/PROMOTE-TESTED-STAGE.original.sh"
PATCHED="$WORK/PROMOTE-TESTED-STAGE.host-fixed.sh"
STAGE="${1:-}"

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this promotion helper with sudo." >&2
    exit 1
fi

if [[ -z "$STAGE" || ! -d "$STAGE" ]]; then
    echo "Usage: sudo bash $0 /var/lib/drivelab-lifecycle-staging/v1-YYYYMMDD-HHMMSS" >&2
    exit 1
fi

for command in curl python3 bash grep; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command is missing: $command" >&2
        exit 1
    }
done

mkdir -p "$WORK"
chmod 0700 "$WORK"

curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
    "$ORIGINAL_URL?host-fix=$STAMP" --output "$ORIGINAL"
[[ -s "$ORIGINAL" ]] || {
    echo "The pinned promotion script was not downloaded." >&2
    exit 1
}

python3 - "$ORIGINAL" "$PATCHED" <<'PYFIX'
from __future__ import annotations

import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

anchor = (
    'ADMIN_PORT="${DLT_ADMIN_PORT:-8788}"\n'
    'ADMIN_TOKEN="${DLT_ADMIN_TOKEN:-}"\n'
)
replacement = (
    'ADMIN_PORT="${DLT_ADMIN_PORT:-8788}"\n'
    'ADMIN_HOST="${DLT_ADMIN_HOST:-127.0.0.1}"\n'
    'case "$ADMIN_HOST" in\n'
    '    0.0.0.0|::|"[::]") ADMIN_CHECK_HOST="127.0.0.1" ;;\n'
    '    *) ADMIN_CHECK_HOST="$ADMIN_HOST" ;;\n'
    'esac\n'
    'ADMIN_TOKEN="${DLT_ADMIN_TOKEN:-}"\n'
)

if text.count(anchor) != 1:
    raise SystemExit(
        "Admin host fix expected one environment anchor but found "
        f"{text.count(anchor)}."
    )
text = text.replace(anchor, replacement, 1)

old_url = 'http://127.0.0.1:$ADMIN_PORT'
count = text.count(old_url)
if count != 4:
    raise SystemExit(
        "Admin host fix expected four loopback Owner Console URLs but found "
        f"{count}."
    )
text = text.replace(old_url, 'http://$ADMIN_CHECK_HOST:$ADMIN_PORT')

old_output = 'Owner dashboard: http://192.168.1.132:$ADMIN_PORT/owner/lifecycle'
new_output = 'Owner dashboard: http://$ADMIN_CHECK_HOST:$ADMIN_PORT/owner/lifecycle'
if text.count(old_output) != 1:
    raise SystemExit("Admin host fix could not find the Owner dashboard output line.")
text = text.replace(old_output, new_output, 1)

old_control = 'Control Center: http://192.168.1.132:$ADMIN_PORT/owner/control-center'
new_control = 'Control Center: http://$ADMIN_CHECK_HOST:$ADMIN_PORT/owner/control-center'
if text.count(old_control) != 1:
    raise SystemExit("Admin host fix could not find the Control Center output line.")
text = text.replace(old_control, new_control, 1)

marker = 'echo "Owner Console health target: http://$ADMIN_CHECK_HOST:$ADMIN_PORT"\n'
health_anchor = 'echo "Current License API and Owner Console are healthy."\n'
if text.count(health_anchor) != 1:
    raise SystemExit("Admin host fix could not find the preflight success anchor.")
text = text.replace(health_anchor, marker + health_anchor, 1)

destination.write_text(text, encoding="utf-8", newline="\n")
PYFIX

chmod 0700 "$ORIGINAL" "$PATCHED"
bash -n "$PATCHED"
grep -q 'ADMIN_CHECK_HOST' "$PATCHED"
grep -q 'Owner Console health target' "$PATCHED"
grep -q 'AUTOMATICALLY RESTORING THE PREVIOUS SERVER' "$PATCHED"
grep -q 'DRIVELAB LIFECYCLE INTELLIGENCE PROMOTED SUCCESSFULLY' "$PATCHED"

echo "Owner Console host fix validated. Starting the exact tested promotion."
exec bash "$PATCHED" "$STAGE"

#!/usr/bin/env bash
set -Eeuo pipefail

ORIGINAL_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/3e7926a55cdb1a4de4f9acb6c6c0dadb4350fb7e/patches/lifecycle-intelligence-v1/server/PREPARE-AND-TEST.sh"
WORK_ROOT="/var/lib/drivelab-lifecycle-wrapper-r2"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$WORK_ROOT/$STAMP"
ORIGINAL="$WORK/PREPARE-AND-TEST.original.sh"
PATCHED="$WORK/PREPARE-AND-TEST.numeric-r2.sh"

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this staging test with sudo." >&2
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
    "$ORIGINAL_URL?r2=$STAMP" --output "$ORIGINAL"
[[ -s "$ORIGINAL" ]] || {
    echo "The original isolated staging script was not downloaded." >&2
    exit 1
}

python3 - "$ORIGINAL" "$PATCHED" <<'PYWRAP'
from __future__ import annotations

import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
needle = "done\n\npython3 -m py_compile \\\n"
if text.count(needle) != 1:
    raise SystemExit(
        "R2 wrapper expected one payload-download anchor but found "
        f"{text.count(needle)}."
    )
replacement = r'''done

echo
echo "===== APPLYING LIFECYCLE NUMERIC CLAMP HOTFIX R2 ====="
python3 - "$PAYLOAD/lifecycle.py" <<'PYNUMERIC'
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = (
    "    number = min(maximum, max(minimum, number))\n"
    "    return int(number) if number.is_integer() else round(number, 4)\n"
)
new = (
    "    number = float(min(maximum, max(minimum, number)))\n"
    "    return int(number) if number.is_integer() else round(number, 4)\n"
)
count = text.count(old)
if count != 1:
    raise SystemExit(
        "Numeric clamp hotfix expected one lifecycle.py anchor but found "
        f"{count}."
    )
path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
print("Lifecycle numeric clamp hotfix R2 applied.")
PYNUMERIC
grep -q 'number = float(min(maximum, max(minimum, number)))' "$PAYLOAD/lifecycle.py"
echo "Lifecycle numeric clamp hotfix R2 verified."

python3 -m py_compile \
'''
destination.write_text(text.replace(needle, replacement, 1), encoding="utf-8", newline="\n")
PYWRAP

chmod 0700 "$ORIGINAL" "$PATCHED"
bash -n "$PATCHED"
grep -q 'APPLYING LIFECYCLE NUMERIC CLAMP HOTFIX R2' "$PATCHED"
grep -q 'PRODUCTION WAS NOT MODIFIED' "$PATCHED"

echo "R2 wrapper validation passed. Starting the corrected isolated stage."
exec bash "$PATCHED"

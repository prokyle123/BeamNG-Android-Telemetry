#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/owner-console-v3.0.0/safe-deploy/PREPARE-AND-TEST.sh?checksum-fix=20260723-2030"
TARGET="/home/kali/PREPARE-DRIVELAB-OWNER-V3-FIXED.sh"
TEMPORARY="$(mktemp /tmp/PREPARE-DRIVELAB-OWNER-V3-FIXED.XXXXXX.sh)"

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

python3 - "$TEMPORARY" <<'PYFIX'
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = 'sha256sum "$PAYLOAD"/* > "$STAGE/payload.sha256"'
new = '''python3 - "$PAYLOAD" "$STAGE/payload.sha256" <<'PYHASH'
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
destination = Path(sys.argv[2])
lines = []
for item in sorted(root.iterdir(), key=lambda value: value.name):
    if not item.is_file():
        continue
    digest = hashlib.sha256(item.read_bytes()).hexdigest()
    lines.append(f"{digest}  {item}")
if not lines:
    raise SystemExit("No payload files were available to hash.")
destination.write_text("\\n".join(lines) + "\\n", encoding="utf-8")
PYHASH'''

count = text.count(old)
if count != 1:
    raise SystemExit(f"Expected exactly one payload checksum line but found {count}.")
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8", newline="\n")
PYFIX

bash -n "$TEMPORARY"
grep -q 'No payload files were available to hash' "$TEMPORARY"
grep -q 'ISOLATED STAGING TEST' "$TEMPORARY"
install -o kali -g kali -m 0700 "$TEMPORARY" "$TARGET"

echo "Prepared corrected isolated staging script: $TARGET"
echo "This helper has not used sudo and has not changed production."

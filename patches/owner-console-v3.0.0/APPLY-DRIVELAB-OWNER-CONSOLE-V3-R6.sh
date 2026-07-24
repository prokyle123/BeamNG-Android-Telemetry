#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/owner-console-v3.0.0/APPLY-DRIVELAB-OWNER-CONSOLE-V3.sh?r6-base=1"
TEMPORARY="$(mktemp /tmp/APPLY-DRIVELAB-OWNER-CONSOLE-V3-R6.XXXXXX.sh)"

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


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor but found {count}.")
    text = text.replace(old, new, 1)


replace_once(
    '''    owner_control_center.py \\
    drivelab-owner-ops-worker \\
''',
    '''    owner_control_center.py \\
    drivelab-owner-test-runner-r6.py \\
    drivelab-owner-ops-worker \\
''',
    "payload list",
)

replace_once(
    '''        "$BASE_URL/$file" \\
        --output "$DOWNLOADS/$file"
''',
    '''        "$BASE_URL/$file?owner-v3-r6=20260723-2015" \\
        --output "$DOWNLOADS/$file"
''',
    "payload cache bust",
)

replace_once(
    '''python3 -m py_compile \\
    "$DOWNLOADS/owner_control_center.py" \\
    "$DOWNLOADS/drivelab-owner-ops-worker"
''',
    '''python3 -m py_compile \\
    "$DOWNLOADS/owner_control_center.py" \\
    "$DOWNLOADS/drivelab-owner-test-runner-r6.py" \\
    "$DOWNLOADS/drivelab-owner-ops-worker"
''',
    "payload compilation",
)

replace_once(
    '''systemd-analyze verify \\
    "$DOWNLOADS/drivelab-owner-ops.path" \\
    "$DOWNLOADS/drivelab-owner-ops.service" \\
    >/dev/null

echo "Payload syntax and systemd validation passed."
''',
    '''grep -q '^PathExistsGlob=/var/lib/drivelab-license/ops/requests/\\*.request$' \\
    "$DOWNLOADS/drivelab-owner-ops.path"
grep -q '^ExecStart=/usr/local/sbin/drivelab-owner-ops-worker$' \\
    "$DOWNLOADS/drivelab-owner-ops.service"

echo "Payload syntax and unit-file marker validation passed."
''',
    "unit validation",
)

replace_once(
    '''echo "===== COMPILING AND TESTING STAGED SOURCE ====="
mkdir -p "$WORK/pycache"
chown -R drivelab-license:drivelab-license "$WORK/pycache" "$STAGE"

runuser -u drivelab-license -- env \\
    PYTHONPATH="$STAGE" \\
    PYTHONPYCACHEPREFIX="$WORK/pycache" \\
    "$APP_ROOT/.venv/bin/python" \\
    -m compileall \\
    -q \\
    "$STAGE/drivelab_license"

if [[ -d "$STAGE/tests" ]] && find "$STAGE/tests" -type f -name 'test_*.py' -print -quit | grep -q .; then
    runuser -u drivelab-license -- env \\
        PYTHONPATH="$STAGE" \\
        PYTHONPYCACHEPREFIX="$WORK/pycache" \\
        "$APP_ROOT/.venv/bin/python" \\
        -m pytest \\
        -q \\
        "$STAGE/tests"
fi

echo "Staged source compilation and tests passed."
''',
    '''echo "===== COMPILING AND TESTING STAGED SOURCE ====="
mkdir -p "$WORK/pycache"
chmod 0755 "$WORK"
chown -R drivelab-license:drivelab-license "$WORK/pycache" "$STAGE"
chmod 0755 "$STAGE" "$STAGE/drivelab_license" "$STAGE/tests"

runuser -u drivelab-license -- env \\
    PYTHONPATH="$STAGE" \\
    PYTHONPYCACHEPREFIX="$WORK/pycache" \\
    "$APP_ROOT/.venv/bin/python" \\
    -m compileall \\
    -q \\
    "$STAGE/drivelab_license"

if [[ -d "$STAGE/tests" ]] && find "$STAGE/tests" -type f -name 'test_*.py' -print -quit | grep -q .; then
    if runuser -u drivelab-license -- "$APP_ROOT/.venv/bin/python" -c 'import pytest' >/dev/null 2>&1; then
        runuser -u drivelab-license -- env \\
            PYTHONPATH="$STAGE" \\
            PYTHONPYCACHEPREFIX="$WORK/pycache" \\
            "$APP_ROOT/.venv/bin/python" \\
            -m pytest \\
            -q \\
            "$STAGE/tests"
    else
        echo "pytest is not installed; using the dependency-free DriveLab test runner R6."
        runuser -u drivelab-license -- env \\
            PYTHONPATH="$STAGE" \\
            PYTHONPYCACHEPREFIX="$WORK/pycache" \\
            "$APP_ROOT/.venv/bin/python" \\
            "$DOWNLOADS/drivelab-owner-test-runner-r6.py" \\
            "$STAGE/tests"
    fi
fi

echo "Staged source compilation and tests passed."
''',
    "compile and test block",
)

replace_once(
    '''for file in \\
    /usr/local/sbin/drivelab-owner-ops-worker \\
''',
    '''for file in \\
    /usr/local/sbin/drivelab-owner-test-runner.py \\
    /usr/local/sbin/drivelab-owner-ops-worker \\
''',
    "backup file list",
)

replace_once(
    "for name in drivelab-owner-ops-worker drivelab-owner-ops.path drivelab-owner-ops.service; do",
    "for name in drivelab-owner-test-runner.py drivelab-owner-ops-worker drivelab-owner-ops.path drivelab-owner-ops.service; do",
    "rollback loop names",
)

replace_once(
    r'''        drivelab-owner-ops-worker) destination=\"/usr/local/sbin/\\$name\" ;;''',
    r'''        drivelab-owner-test-runner.py|drivelab-owner-ops-worker) destination=\"/usr/local/sbin/\\$name\" ;;''',
    "rollback executable destination",
)

replace_once(
    r'''\"\\$name\" == drivelab-owner-ops-worker''',
    r'''\"\\$name\" == drivelab-owner-ops-worker || \"\\$name\" == drivelab-owner-test-runner.py''',
    "rollback executable mode",
)

replace_once(
    '''install -o root -g root -m 0750 \\
    "$DOWNLOADS/drivelab-owner-ops-worker" \\
    /usr/local/sbin/drivelab-owner-ops-worker
''',
    '''install -o root -g drivelab-license -m 0750 \\
    "$DOWNLOADS/drivelab-owner-test-runner-r6.py" \\
    /usr/local/sbin/drivelab-owner-test-runner.py
install -o root -g root -m 0750 \\
    "$DOWNLOADS/drivelab-owner-ops-worker" \\
    /usr/local/sbin/drivelab-owner-ops-worker
''',
    "test runner installation",
)

path.write_text(text, encoding="utf-8", newline="\n")
PY

bash -n "$TEMPORARY"
chmod 0700 "$TEMPORARY"
exec bash "$TEMPORARY"

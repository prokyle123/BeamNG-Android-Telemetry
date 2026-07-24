#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
APP_ROOT="/opt/drivelab-license"
PACKAGE_ROOT="$APP_ROOT/drivelab_license"
VENV_PYTHON="$APP_ROOT/.venv/bin/python"
TEST_RUNNER="/usr/local/sbin/drivelab-owner-test-runner.py"
ENV_FILE="/etc/drivelab-license/license.env"
BACKUP_PARENT="/var/backups/drivelab-lifecycle-intelligence"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_PARENT/$STAMP"
STAGE="${1:-}"
CHANGED=0

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this promotion with sudo." >&2
    exit 1
fi

for command in curl python3 sha256sum systemctl runuser install readlink; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command is missing: $command" >&2
        exit 1
    }
done

if [[ -z "$STAGE" || ! -d "$STAGE" ]]; then
    echo "Usage: sudo bash $0 /var/lib/drivelab-lifecycle-staging/v1-YYYYMMDD-HHMMSS" >&2
    exit 1
fi
STAGE="$(readlink -f "$STAGE")"
READY="$STAGE/READY.json"
SRC="$STAGE/src"

for required in \
    "$READY" \
    "$STAGE/live-source-after.sha256" \
    "$STAGE/staged-source.sha256" \
    "$SRC/drivelab_license/main.py" \
    "$SRC/drivelab_license/admin_app.py" \
    "$SRC/drivelab_license/owner_control_center.py" \
    "$SRC/drivelab_license/lifecycle.py" \
    "$SRC/drivelab_license/owner_lifecycle.py" \
    "$SRC/tests/test_lifecycle.py" \
    "$VENV_PYTHON" \
    "$TEST_RUNNER" \
    "$ENV_FILE"
do
    [[ -f "$required" ]] || {
        echo "The tested stage is incomplete: $required" >&2
        exit 1
    }
done

set +u
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
set -u

LIVE_DB="${DLT_DATABASE_PATH:-/var/lib/drivelab-license/licenses.db}"
API_PORT="${DLT_API_PORT:-8787}"
ADMIN_PORT="${DLT_ADMIN_PORT:-8788}"
ADMIN_TOKEN="${DLT_ADMIN_TOKEN:-}"
[[ -f "$LIVE_DB" ]] || {
    echo "The live database is missing: $LIVE_DB" >&2
    exit 1
}
[[ -n "$ADMIN_TOKEN" ]] || {
    echo "DLT_ADMIN_TOKEN is missing from the existing environment." >&2
    exit 1
}

restore_optional_source() {
    local name="$1"
    if [[ -f "$BACKUP/source/$name" ]]; then
        install -o drivelab-license -g drivelab-license -m 0640 \
            "$BACKUP/source/$name" "$PACKAGE_ROOT/$name"
    else
        rm -f "$PACKAGE_ROOT/$name"
    fi
}

restore_optional_test() {
    local name="$1"
    if [[ -f "$BACKUP/tests/$name" ]]; then
        mkdir -p "$APP_ROOT/tests"
        install -o drivelab-license -g drivelab-license -m 0640 \
            "$BACKUP/tests/$name" "$APP_ROOT/tests/$name"
    else
        rm -f "$APP_ROOT/tests/$name"
    fi
}

restore_backup() {
    echo
    echo "===== AUTOMATICALLY RESTORING THE PREVIOUS SERVER ====="
    systemctl stop drivelab-license-admin.service drivelab-license-api.service || true

    install -o drivelab-license -g drivelab-license -m 0640 \
        "$BACKUP/source/main.py" "$PACKAGE_ROOT/main.py"
    install -o drivelab-license -g drivelab-license -m 0640 \
        "$BACKUP/source/admin_app.py" "$PACKAGE_ROOT/admin_app.py"
    install -o drivelab-license -g drivelab-license -m 0640 \
        "$BACKUP/source/owner_control_center.py" "$PACKAGE_ROOT/owner_control_center.py"
    restore_optional_source "lifecycle.py"
    restore_optional_source "owner_lifecycle.py"
    restore_optional_test "test_lifecycle.py"

    local db_parent db_temp
    db_parent="$(dirname "$LIVE_DB")"
    db_temp="$db_parent/.lifecycle-auto-rollback-$$.db"
    install -o drivelab-license -g drivelab-license -m 0640 \
        "$BACKUP/database/licenses.db" "$db_temp"
    rm -f "${LIVE_DB}-wal" "${LIVE_DB}-shm"
    mv -f "$db_temp" "$LIVE_DB"
    chown drivelab-license:drivelab-license "$LIVE_DB"
    chmod 0640 "$LIVE_DB"

    systemctl start drivelab-license-api.service drivelab-license-admin.service || true
    echo "Automatic rollback attempted from: $BACKUP"
}

handle_error() {
    local status="$1"
    local line="$2"
    trap - ERR
    set +e
    echo
    echo "PROMOTION FAILED at line $line with status $status." >&2
    if [[ "$CHANGED" -eq 1 && -d "$BACKUP" ]]; then
        restore_backup
    else
        echo "Production installation had not started; no rollback was required." >&2
    fi
    exit "$status"
}
trap 'handle_error $? $LINENO' ERR

echo
echo "============================================================"
echo "DRIVELAB LIFECYCLE INTELLIGENCE V${VERSION} — TESTED PROMOTION"
echo "============================================================"
echo "Stage: $STAGE"
echo "Backup: $BACKUP"
echo

echo "===== VERIFYING READY MARKER AND EXACT TESTED FILES ====="
$VENV_PYTHON - "$READY" "$STAGE" <<'PYREADY'
import json
import sys
from pathlib import Path
ready_path = Path(sys.argv[1])
stage = Path(sys.argv[2]).resolve()
value = json.loads(ready_path.read_text(encoding="utf-8"))
expected = {
    "schema": 1,
    "component": "drivelab-lifecycle-intelligence-server",
    "version": "1.0.0",
    "status": "READY_FOR_PROMOTION",
}
for key, wanted in expected.items():
    if value.get(key) != wanted:
        raise SystemExit(f"READY marker mismatch for {key}: {value.get(key)!r}")
if Path(str(value.get("stage", ""))).resolve() != stage:
    raise SystemExit("READY marker points to a different stage.")
tests = value.get("tests")
if not isinstance(tests, dict) or not tests or any(result != "passed" for result in tests.values()):
    raise SystemExit("READY marker does not report a complete passing test set.")
print("READY marker validation passed.")
PYREADY

sha256sum -c "$STAGE/staged-source.sha256"
sha256sum -c "$STAGE/live-source-after.sha256"
grep -q 'number = float(min(maximum, max(minimum, number)))' "$SRC/drivelab_license/lifecycle.py"
grep -q 'LIFECYCLE_VERSION = "1.0.0"' "$SRC/drivelab_license/lifecycle.py"
grep -q 'OWNER_LIFECYCLE_VERSION = "1.0.0"' "$SRC/drivelab_license/owner_lifecycle.py"
grep -q 'CONTROL_CENTER_VERSION = "3.1.0"' "$SRC/drivelab_license/owner_control_center.py"
echo "Stage hashes, production baseline, R2 numeric fix, and source markers passed."

echo
echo "===== CHECKING CURRENT PRODUCTION HEALTH ====="
systemctl is-active --quiet drivelab-license-api.service
systemctl is-active --quiet drivelab-license-admin.service
[[ "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "http://127.0.0.1:$API_PORT/v1/health" || true)" == "200" ]]
[[ "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "http://127.0.0.1:$ADMIN_PORT/login" || true)" == "200" ]]
echo "Current License API and Owner Console are healthy."

echo
echo "===== CREATING VERIFIED PRE-PROMOTION BACKUP ====="
mkdir -p "$BACKUP/source" "$BACKUP/tests" "$BACKUP/database"
chmod 0700 "$BACKUP"

for name in main.py admin_app.py owner_control_center.py lifecycle.py owner_lifecycle.py; do
    if [[ -f "$PACKAGE_ROOT/$name" ]]; then
        cp -a "$PACKAGE_ROOT/$name" "$BACKUP/source/$name"
    fi
done
if [[ -f "$APP_ROOT/tests/test_lifecycle.py" ]]; then
    cp -a "$APP_ROOT/tests/test_lifecycle.py" "$BACKUP/tests/test_lifecycle.py"
fi

$VENV_PYTHON - "$LIVE_DB" "$BACKUP/database/licenses.db" <<'PYBACKUP'
import sqlite3
import sys
source = sqlite3.connect(sys.argv[1], timeout=30)
target = sqlite3.connect(sys.argv[2])
try:
    source.backup(target)
finally:
    target.close()
    source.close()
PYBACKUP
chmod 0600 "$BACKUP/database/licenses.db"

$VENV_PYTHON - "$BACKUP/database/licenses.db" <<'PYCHECK'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1], timeout=30)
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Backup database quick_check failed: {result}")
finally:
    connection.close()
print("Backup database integrity passed.")
PYCHECK

$VENV_PYTHON - "$BACKUP/MANIFEST.json" "$STAGE" "$LIVE_DB" "$STAMP" <<'PYMANIFEST'
import hashlib
import json
import sys
from pathlib import Path
manifest = Path(sys.argv[1])
stage = Path(sys.argv[2]).resolve()
live_database = Path(sys.argv[3])
backup_stamp = sys.argv[4]
files = {}
for root_name in ("source", "tests", "database"):
    root = manifest.parent / root_name
    for path in sorted(root.rglob("*")):
        if path.is_file():
            relative = str(path.relative_to(manifest.parent))
            files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
value = {
    "schema": 1,
    "component": "drivelab-lifecycle-intelligence-backup",
    "version": "1.0.0",
    "created_at": backup_stamp,
    "tested_stage": str(stage),
    "live_database": str(live_database),
    "files": files,
}
manifest.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PYMANIFEST
chmod 0600 "$BACKUP/MANIFEST.json"
echo "Verified backup completed: $BACKUP"

echo
echo "===== INSTALLING EXACT TESTED LIFECYCLE SOURCE ====="
CHANGED=1
systemctl stop drivelab-license-admin.service drivelab-license-api.service

install -o drivelab-license -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/main.py" "$PACKAGE_ROOT/main.py"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/admin_app.py" "$PACKAGE_ROOT/admin_app.py"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/owner_control_center.py" "$PACKAGE_ROOT/owner_control_center.py"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/lifecycle.py" "$PACKAGE_ROOT/lifecycle.py"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/owner_lifecycle.py" "$PACKAGE_ROOT/owner_lifecycle.py"
mkdir -p "$APP_ROOT/tests"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$SRC/tests/test_lifecycle.py" "$APP_ROOT/tests/test_lifecycle.py"

mkdir -p /var/lib/drivelab-license/pycache
chown drivelab-license:drivelab-license /var/lib/drivelab-license/pycache
runuser -u drivelab-license -- env \
    PYTHONPATH="$APP_ROOT" \
    PYTHONPYCACHEPREFIX=/var/lib/drivelab-license/pycache \
    "$VENV_PYTHON" -m compileall -q \
    "$PACKAGE_ROOT/main.py" \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_control_center.py" \
    "$PACKAGE_ROOT/lifecycle.py" \
    "$PACKAGE_ROOT/owner_lifecycle.py"

runuser -u drivelab-license -- env \
    PYTHONPATH="$APP_ROOT" \
    PYTHONPYCACHEPREFIX=/var/lib/drivelab-license/pycache \
    "$VENV_PYTHON" "$TEST_RUNNER" "$APP_ROOT/tests"

runuser -u drivelab-license -- env \
    PYTHONPATH="$APP_ROOT" \
    PYTHONPYCACHEPREFIX=/var/lib/drivelab-license/pycache \
    "$VENV_PYTHON" - "$LIVE_DB" <<'PYSCHEMA'
import sqlite3
import sys
from pathlib import Path
from drivelab_license.lifecycle import ensure_lifecycle_schema
path = Path(sys.argv[1])
ensure_lifecycle_schema(path)
connection = sqlite3.connect(path, timeout=30)
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Live database quick_check failed after schema installation: {result}")
    required = {
        "device_lifecycle_events",
        "device_active_days",
        "device_version_history",
        "device_edition_history",
        "device_relationships",
        "device_diagnostic_reports",
    }
    present = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    missing = sorted(required - present)
    if missing:
        raise SystemExit("Live lifecycle schema is missing: " + ", ".join(missing))
finally:
    connection.close()
print("Live additive lifecycle schema and database integrity passed.")
PYSCHEMA

systemctl start drivelab-license-api.service drivelab-license-admin.service

echo
echo "===== VALIDATING LIVE API AND OWNER CONSOLE ====="
API_HEALTH=""
LIFECYCLE_HEALTH=""
ADMIN_LOGIN=""
for attempt in $(seq 1 60); do
    API_HEALTH="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 \
        "http://127.0.0.1:$API_PORT/v1/health" || true)"
    LIFECYCLE_HEALTH="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 \
        "http://127.0.0.1:$API_PORT/v1/lifecycle/health" || true)"
    ADMIN_LOGIN="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 \
        "http://127.0.0.1:$ADMIN_PORT/login" || true)"
    if [[ "$API_HEALTH" == "200" && "$LIFECYCLE_HEALTH" == "200" && "$ADMIN_LOGIN" == "200" ]]; then
        break
    fi
    if ! systemctl is-active --quiet drivelab-license-api.service || \
       ! systemctl is-active --quiet drivelab-license-admin.service; then
        break
    fi
    sleep 1
done

[[ "$API_HEALTH" == "200" ]]
[[ "$LIFECYCLE_HEALTH" == "200" ]]
[[ "$ADMIN_LOGIN" == "200" ]]
systemctl is-active --quiet drivelab-license-api.service
systemctl is-active --quiet drivelab-license-admin.service

AUTH_HEADER="Authorization: Bearer $ADMIN_TOKEN"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$ADMIN_PORT/owner/lifecycle" \
    --output "$BACKUP/live-lifecycle-overview.html"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$ADMIN_PORT/owner/control-center" \
    --output "$BACKUP/live-control-center.html"
grep -q 'Device lifecycle intelligence' "$BACKUP/live-lifecycle-overview.html"
grep -q 'Control Center v3.1.0' "$BACKUP/live-control-center.html"
grep -q "href='/owner/lifecycle'" "$BACKUP/live-control-center.html"

$VENV_PYTHON - \
    "$STAGE/staged-source.sha256" \
    "$BACKUP/promoted-source.sha256" \
    "$PACKAGE_ROOT/main.py" \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_control_center.py" \
    "$PACKAGE_ROOT/lifecycle.py" \
    "$PACKAGE_ROOT/owner_lifecycle.py" \
    "$APP_ROOT/tests/test_lifecycle.py" <<'PYVERIFY'
import hashlib
import sys
from pathlib import Path
expected_file = Path(sys.argv[1])
output_file = Path(sys.argv[2])
live_paths = [Path(value) for value in sys.argv[3:]]
expected = {}
for raw in expected_file.read_text(encoding="utf-8").splitlines():
    raw = raw.strip()
    if not raw:
        continue
    digest, filename = raw.split(None, 1)
    expected[Path(filename.strip()).name] = digest.lower()
actual = {}
lines = []
for path in live_paths:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    actual[path.name] = digest
    lines.append(f"{digest}  {path}")
if expected != actual:
    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    changed = sorted(name for name in set(expected) & set(actual) if expected[name] != actual[name])
    raise SystemExit(
        "Promoted source does not exactly match the tested stage. "
        f"Missing={missing}, extra={extra}, changed={changed}"
    )
output_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Promoted source hashes exactly match the tested stage.")
PYVERIFY

date -Is > "$BACKUP/PROMOTION-SUCCEEDED.txt"
chmod 0600 "$BACKUP/PROMOTION-SUCCEEDED.txt" "$BACKUP/promoted-source.sha256" \
    "$BACKUP/live-lifecycle-overview.html" "$BACKUP/live-control-center.html"
CHANGED=0
trap - ERR

echo
echo "============================================================"
echo "DRIVELAB LIFECYCLE INTELLIGENCE PROMOTED SUCCESSFULLY"
echo "============================================================"
echo "Lifecycle API: http://127.0.0.1:$API_PORT/v1/lifecycle/health"
echo "Owner dashboard: http://192.168.1.132:$ADMIN_PORT/owner/lifecycle"
echo "Control Center: http://192.168.1.132:$ADMIN_PORT/owner/control-center"
echo "Backup: $BACKUP"
echo
echo "The existing APK, signed update feed, license keys, signing keys,"
echo "customer records, RaceLink data, and public website content were not replaced."
echo "Only the tested lifecycle server source, additive database schema, and Owner Console pages were promoted."

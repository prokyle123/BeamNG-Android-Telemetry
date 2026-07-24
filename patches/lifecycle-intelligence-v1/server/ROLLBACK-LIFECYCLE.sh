#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="/opt/drivelab-license"
PACKAGE_ROOT="$APP_ROOT/drivelab_license"
VENV_PYTHON="$APP_ROOT/.venv/bin/python"

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this rollback with sudo." >&2
    exit 1
fi

BACKUP="${1:-}"
if [[ -z "$BACKUP" || ! -d "$BACKUP" ]]; then
    echo "Usage: sudo bash $0 /var/backups/drivelab-lifecycle-intelligence/<backup>" >&2
    exit 1
fi

for required in \
    "$BACKUP/source/main.py" \
    "$BACKUP/source/admin_app.py" \
    "$BACKUP/source/owner_control_center.py" \
    "$BACKUP/database/licenses.db" \
    "$BACKUP/MANIFEST.json"
do
    [[ -f "$required" ]] || {
        echo "Rollback backup is incomplete: $required" >&2
        exit 1
    }
done

LIVE_DB="$($VENV_PYTHON - "$BACKUP/MANIFEST.json" <<'PYDBPATH'
import json
import sys
from pathlib import Path
value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(value["live_database"])
PYDBPATH
)"

[[ -n "$LIVE_DB" ]] || {
    echo "The rollback manifest does not contain a live database path." >&2
    exit 1
}

restore_optional() {
    local name="$1"
    if [[ -f "$BACKUP/source/$name" ]]; then
        install -o drivelab-license -g drivelab-license -m 0640 \
            "$BACKUP/source/$name" "$PACKAGE_ROOT/$name"
    else
        rm -f "$PACKAGE_ROOT/$name"
    fi
}

restore_test() {
    local name="$1"
    if [[ -f "$BACKUP/tests/$name" ]]; then
        mkdir -p "$APP_ROOT/tests"
        install -o drivelab-license -g drivelab-license -m 0640 \
            "$BACKUP/tests/$name" "$APP_ROOT/tests/$name"
    else
        rm -f "$APP_ROOT/tests/$name"
    fi
}

echo
echo "============================================================"
echo "ROLLING BACK DRIVELAB LIFECYCLE INTELLIGENCE"
echo "============================================================"
echo "Backup: $BACKUP"

systemctl stop drivelab-license-admin.service drivelab-license-api.service || true

install -o drivelab-license -g drivelab-license -m 0640 \
    "$BACKUP/source/main.py" "$PACKAGE_ROOT/main.py"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$BACKUP/source/admin_app.py" "$PACKAGE_ROOT/admin_app.py"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$BACKUP/source/owner_control_center.py" "$PACKAGE_ROOT/owner_control_center.py"
restore_optional "lifecycle.py"
restore_optional "owner_lifecycle.py"
restore_test "test_lifecycle.py"

DB_PARENT="$(dirname "$LIVE_DB")"
mkdir -p "$DB_PARENT"
DB_TEMP="$DB_PARENT/.lifecycle-rollback-$$.db"
install -o drivelab-license -g drivelab-license -m 0640 \
    "$BACKUP/database/licenses.db" "$DB_TEMP"
rm -f "${LIVE_DB}-wal" "${LIVE_DB}-shm"
mv -f "$DB_TEMP" "$LIVE_DB"
chown drivelab-license:drivelab-license "$LIVE_DB"
chmod 0640 "$LIVE_DB"

systemctl start drivelab-license-api.service drivelab-license-admin.service

for attempt in $(seq 1 45); do
    API_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 \
        http://127.0.0.1:8787/v1/health || true)"
    ADMIN_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 \
        http://127.0.0.1:8788/login || true)"
    if [[ "$API_CODE" == "200" && "$ADMIN_CODE" == "200" ]]; then
        break
    fi
    sleep 1
done

[[ "${API_CODE:-}" == "200" ]] || {
    systemctl status drivelab-license-api.service --no-pager -l || true
    echo "Rollback restored files, but the License API did not return HTTP 200." >&2
    exit 1
}
[[ "${ADMIN_CODE:-}" == "200" ]] || {
    systemctl status drivelab-license-admin.service --no-pager -l || true
    echo "Rollback restored files, but the Owner Console did not return HTTP 200." >&2
    exit 1
}

$VENV_PYTHON - "$LIVE_DB" <<'PYCHECK'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1], timeout=30)
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Restored database quick_check failed: {result}")
finally:
    connection.close()
print("Restored database integrity passed.")
PYCHECK

echo
echo "Rollback completed successfully."
echo "The previous Owner Console, License API source, tests, and database are active."

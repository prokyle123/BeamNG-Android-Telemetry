#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
BRANCH="lifecycle-intelligence-v1"
BASE_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/$BRANCH/patches/lifecycle-intelligence-v1/server"
APP_ROOT="/opt/drivelab-license"
PACKAGE_ROOT="$APP_ROOT/drivelab_license"
ENV_FILE="/etc/drivelab-license/license.env"
VENV_PYTHON="$APP_ROOT/.venv/bin/python"
TEST_RUNNER="/usr/local/sbin/drivelab-owner-test-runner.py"
STAGING_PARENT="/var/lib/drivelab-lifecycle-staging"
STAMP="$(date +%Y%m%d-%H%M%S)"
STAGE="$STAGING_PARENT/v1-$STAMP"
SRC="$STAGE/src"
PAYLOAD="$STAGE/payload"
DATA="$STAGE/data"
REPORT="$STAGE/STAGE-REPORT.txt"
READY="$STAGE/READY.json"
LATEST_LINK="$STAGING_PARENT/LATEST"
HOME_REPORT="/home/kali/DriveLab-Lifecycle-STAGE-REPORT.txt"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

fail() {
    echo "FAILED: $*" | tee -a "$REPORT" >&2
    exit 1
}

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this staging test with sudo." >&2
    exit 1
fi

for command in curl python3 sha256sum runuser systemctl diff; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command is missing: $command" >&2
        exit 1
    }
done

for required in \
    "$PACKAGE_ROOT/main.py" \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_control_center.py" \
    "$PACKAGE_ROOT/database.py" \
    "$PACKAGE_ROOT/service.py" \
    "$VENV_PYTHON" \
    "$TEST_RUNNER" \
    "$ENV_FILE"
do
    [[ -e "$required" ]] || {
        echo "Required live file is missing: $required" >&2
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
LIVE_UPDATE_DIR="${DLT_UPDATE_DIR:-/var/lib/drivelab-license/updates}"
ADMIN_TOKEN="${DLT_ADMIN_TOKEN:-}"
[[ -f "$LIVE_DB" ]] || fail "Live database was not found: $LIVE_DB"
[[ -n "$ADMIN_TOKEN" ]] || fail "DLT_ADMIN_TOKEN is missing from the existing environment file."

mkdir -p "$SRC/drivelab_license" "$SRC/tests" "$PAYLOAD" "$DATA/updates"
touch "$REPORT"
chmod 0600 "$REPORT"
exec > >(tee -a "$REPORT") 2>&1

echo
echo "============================================================"
echo "DRIVELAB LIFECYCLE INTELLIGENCE V${VERSION} — ISOLATED STAGE"
echo "============================================================"
echo "Stage: $STAGE"
echo
echo "This phase does not modify production source, the live SQLite database,"
echo "running services, the APK, update feed, license keys, or customer records."
echo

echo "===== RECORDING LIVE SOURCE HASHES ====="
sha256sum \
    "$PACKAGE_ROOT/main.py" \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_control_center.py" \
    > "$STAGE/live-source-before.sha256"
cat "$STAGE/live-source-before.sha256"

echo
echo "===== DOWNLOADING LIFECYCLE PAYLOAD ====="
download() {
    local name="$1"
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
        "$BASE_URL/$name?stage=$STAMP" --output "$PAYLOAD/$name"
    [[ -s "$PAYLOAD/$name" ]] || fail "Downloaded payload is empty: $name"
}

for name in lifecycle.py owner_lifecycle.py test_lifecycle.py patch_stage.py; do
    download "$name"
done

python3 -m py_compile \
    "$PAYLOAD/lifecycle.py" \
    "$PAYLOAD/owner_lifecycle.py" \
    "$PAYLOAD/test_lifecycle.py" \
    "$PAYLOAD/patch_stage.py"
grep -q 'LIFECYCLE_VERSION = "1.0.0"' "$PAYLOAD/lifecycle.py"
grep -q 'OWNER_LIFECYCLE_VERSION = "1.0.0"' "$PAYLOAD/owner_lifecycle.py"
grep -q 'Lifecycle server patch completed and parsed successfully' "$PAYLOAD/patch_stage.py"
python3 - "$PAYLOAD" "$STAGE/payload.sha256" <<'PYHASH'
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
    lines.append(f"{hashlib.sha256(item.read_bytes()).hexdigest()}  {item}")
if not lines:
    raise SystemExit("No lifecycle payload files were available to hash.")
destination.write_text("\n".join(lines) + "\n", encoding="utf-8")
PYHASH
echo "Payload syntax, markers, and checksums passed."

echo
echo "===== COPYING LIVE SOURCE AND DATA INTO ISOLATED STAGE ====="
cp -a "$PACKAGE_ROOT/." "$SRC/drivelab_license/"
if [[ -d "$APP_ROOT/tests" ]]; then
    cp -a "$APP_ROOT/tests/." "$SRC/tests/"
fi
python3 - "$LIVE_DB" "$DATA/licenses.db" <<'PYDB'
import sqlite3
import sys
source = sqlite3.connect(sys.argv[1], timeout=30)
target = sqlite3.connect(sys.argv[2])
try:
    source.backup(target)
finally:
    target.close()
    source.close()
PYDB
if [[ -d "$LIVE_UPDATE_DIR" ]]; then
    cp -a "$LIVE_UPDATE_DIR/." "$DATA/updates/"
fi

python3 "$PAYLOAD/patch_stage.py" "$SRC" "$PAYLOAD"

echo
echo "===== COMPILING AND RUNNING STAGED TESTS ====="
chown -R drivelab-license:drivelab-license "$STAGE"
find "$STAGE" -type d -exec chmod 0750 {} +
find "$STAGE" -type f -exec chmod 0640 {} +
chmod 0750 "$PAYLOAD/patch_stage.py"
mkdir -p "$STAGE/pycache"
chown drivelab-license:drivelab-license "$STAGE/pycache"

runuser -u drivelab-license -- env \
    PYTHONPATH="$SRC" \
    PYTHONPYCACHEPREFIX="$STAGE/pycache" \
    "$VENV_PYTHON" -m compileall -q "$SRC/drivelab_license"

runuser -u drivelab-license -- env \
    PYTHONPATH="$SRC" \
    PYTHONPYCACHEPREFIX="$STAGE/pycache" \
    "$VENV_PYTHON" "$TEST_RUNNER" "$SRC/tests"

runuser -u drivelab-license -- env \
    PYTHONPATH="$SRC" \
    PYTHONPYCACHEPREFIX="$STAGE/pycache" \
    "$VENV_PYTHON" - "$DATA/licenses.db" <<'PYSCHEMA'
import sqlite3
import sys
from pathlib import Path
from drivelab_license.lifecycle import ensure_lifecycle_schema
path = Path(sys.argv[1])
ensure_lifecycle_schema(path)
connection = sqlite3.connect(path)
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Staged database quick_check failed: {result}")
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
        raise SystemExit("Staged lifecycle schema is missing: " + ", ".join(missing))
    columns = {row[1] for row in connection.execute("PRAGMA table_info(device_presence)")}
    for required_column in ("device_key_hash", "launch_count", "active_days", "clean_sessions", "diagnostic_count"):
        if required_column not in columns:
            raise SystemExit(f"Staged device_presence is missing: {required_column}")
finally:
    connection.close()
print("Staged lifecycle schema and database integrity passed.")
PYSCHEMA

free_port() {
    python3 - <<'PYPORT'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PYPORT
}

export PYTHONPATH="$SRC"
export PYTHONPYCACHEPREFIX="$STAGE/pycache"
export DLT_DATABASE_PATH="$DATA/licenses.db"
export DLT_UPDATE_DIR="$DATA/updates"

echo
echo "===== STARTING TEMPORARY STAGED LIFECYCLE API ====="
API_PORT="$(free_port)"
runuser -u drivelab-license --preserve-environment -- \
    "$VENV_PYTHON" -m uvicorn drivelab_license.main:app \
    --host 127.0.0.1 --port "$API_PORT" \
    > "$STAGE/staged-api.log" 2>&1 &
SERVER_PID="$!"

API_CODE=""
for _attempt in $(seq 1 45); do
    API_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 "http://127.0.0.1:$API_PORT/v1/lifecycle/health" || true)"
    [[ "$API_CODE" == "200" ]] && break
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat "$STAGE/staged-api.log"
        fail "The staged lifecycle API exited before becoming ready."
    fi
    sleep 1
done
[[ "$API_CODE" == "200" ]] || {
    cat "$STAGE/staged-api.log"
    fail "The staged lifecycle health endpoint returned HTTP $API_CODE instead of 200."
}

runuser -u drivelab-license --preserve-environment -- \
    "$VENV_PYTHON" - "$API_PORT" <<'PYHTTP'
from __future__ import annotations
import base64
import hashlib
import json
import sys
import time
import urllib.request
import uuid
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

port = int(sys.argv[1])
base = f"http://127.0.0.1:{port}"
key = ec.generate_private_key(ec.SECP256R1())
public = base64.b64encode(
    key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
).decode("ascii")
installation = "staged-http-lifecycle-12345"
version = "2.4.0"

def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")

def sign(message: str) -> str:
    return b64url(key.sign(message.encode("utf-8"), ec.ECDSA(hashes.SHA256())))

def post(path: str, body: dict) -> dict:
    request = urllib.request.Request(
        base + path,
        data=json.dumps(body, separators=(",", ":")).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        if response.status != 200:
            raise SystemExit(f"{path} returned HTTP {response.status}")
        return json.loads(response.read().decode("utf-8"))

from drivelab_license.crypto import device_key_hash
stamp = int(time.time())
nonce = "stage-register-0001"
key_hash = device_key_hash(public)
message = f"lifecycle_register|{installation}|{stamp}|{nonce}|{version}|{key_hash}"
registered = post(
    "/v1/lifecycle/register",
    {
        "installation_id": installation,
        "device_public_key": public,
        "timestamp": stamp,
        "nonce": nonce,
        "app_version": version,
        "proof_signature": sign(message),
    },
)
if not registered.get("registered") or registered.get("edition") != "free":
    raise SystemExit(f"Unexpected registration response: {registered}")

events = [
    {
        "event_id": str(uuid.uuid4()),
        "event_type": "app_launch",
        "occurred_at": stamp,
        "session_id": "stage-app-session",
        "properties": {
            "launch_reason": "staged_test",
            "previous_run_clean": True,
            "android_version": "16",
            "device_model": "staged-device",
        },
    },
    {
        "event_id": str(uuid.uuid4()),
        "event_type": "beamng_connected",
        "occurred_at": stamp,
        "session_id": "stage-app-session",
        "properties": {"mode": "outgauge", "time_to_first_packet_ms": 300},
    },
]
canonical = json.dumps(events, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
payload_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
nonce = "stage-batch-0002"
message = f"lifecycle_batch:{payload_hash}|{installation}|{stamp}|{nonce}|{version}"
accepted = post(
    "/v1/lifecycle/batch",
    {
        "installation_id": installation,
        "timestamp": stamp,
        "nonce": nonce,
        "app_version": version,
        "events": events,
        "proof_signature": sign(message),
    },
)
if accepted.get("accepted") != 2 or accepted.get("duplicates") != 0:
    raise SystemExit(f"Unexpected batch response: {accepted}")
print("Signed staged lifecycle registration and HTTP event ingestion passed.")
PYHTTP

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

echo
echo "===== STARTING TEMPORARY STAGED OWNER LIFECYCLE DASHBOARD ====="
ADMIN_PORT="$(free_port)"
export DLT_ADMIN_HOST="127.0.0.1"
export DLT_ADMIN_PORT="$ADMIN_PORT"
runuser -u drivelab-license --preserve-environment -- \
    "$VENV_PYTHON" -m uvicorn drivelab_license.admin_app:app \
    --host 127.0.0.1 --port "$ADMIN_PORT" \
    > "$STAGE/staged-admin.log" 2>&1 &
SERVER_PID="$!"

LOGIN_CODE=""
for _attempt in $(seq 1 45); do
    LOGIN_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 "http://127.0.0.1:$ADMIN_PORT/login" || true)"
    [[ "$LOGIN_CODE" == "200" ]] && break
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat "$STAGE/staged-admin.log"
        fail "The staged Owner Lifecycle dashboard exited before becoming ready."
    fi
    sleep 1
done
[[ "$LOGIN_CODE" == "200" ]] || {
    cat "$STAGE/staged-admin.log"
    fail "The staged admin login page returned HTTP $LOGIN_CODE instead of 200."
}

AUTH_HEADER="Authorization: Bearer $ADMIN_TOKEN"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$ADMIN_PORT/owner/lifecycle" \
    --output "$STAGE/lifecycle-overview.html"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$ADMIN_PORT/owner/lifecycle/staged-http-lifecycle-12345" \
    --output "$STAGE/lifecycle-device.html"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$ADMIN_PORT/owner/control-center" \
    --output "$STAGE/control-center.html"
grep -q 'Device lifecycle intelligence' "$STAGE/lifecycle-overview.html"
grep -q 'Lifecycle timeline' "$STAGE/lifecycle-device.html"
grep -q 'Control Center v3.1.0' "$STAGE/control-center.html"
grep -q "href='/owner/lifecycle'" "$STAGE/control-center.html"
UNAUTH_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 4 "http://127.0.0.1:$ADMIN_PORT/owner/lifecycle" || true)"
[[ "$UNAUTH_CODE" == "303" ]] || fail "Unauthenticated lifecycle page returned HTTP $UNAUTH_CODE instead of 303."

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""
echo "Staged lifecycle API and Owner Console pages rendered and authenticated correctly."

echo
echo "===== PROVING PRODUCTION WAS NOT CHANGED ====="
sha256sum \
    "$PACKAGE_ROOT/main.py" \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_control_center.py" \
    > "$STAGE/live-source-after.sha256"
diff -u "$STAGE/live-source-before.sha256" "$STAGE/live-source-after.sha256" >/dev/null \
    || fail "A production source hash changed during isolated staging."
systemctl is-active --quiet drivelab-license-api.service \
    || fail "The production License API is not active after staging."
systemctl is-active --quiet drivelab-license-admin.service \
    || fail "The production Owner Console is not active after staging."

sha256sum \
    "$SRC/drivelab_license/main.py" \
    "$SRC/drivelab_license/admin_app.py" \
    "$SRC/drivelab_license/owner_control_center.py" \
    "$SRC/drivelab_license/lifecycle.py" \
    "$SRC/drivelab_license/owner_lifecycle.py" \
    "$SRC/tests/test_lifecycle.py" \
    > "$STAGE/staged-source.sha256"

python3 - "$READY" "$STAGE" "$STAMP" <<'PYREADY'
import json
import sys
from pathlib import Path
ready = Path(sys.argv[1])
stage = Path(sys.argv[2])
stamp = sys.argv[3]
value = {
    "schema": 1,
    "component": "drivelab-lifecycle-intelligence-server",
    "version": "1.0.0",
    "status": "READY_FOR_PROMOTION",
    "created_at": stamp,
    "stage": str(stage),
    "live_source_hashes": str(stage / "live-source-after.sha256"),
    "staged_source_hashes": str(stage / "staged-source.sha256"),
    "payload_hashes": str(stage / "payload.sha256"),
    "tests": {
        "existing_license_flow": "passed",
        "existing_signed_update": "passed",
        "lifecycle_service": "passed",
        "signed_lifecycle_http": "passed",
        "owner_lifecycle_http": "passed",
        "copied_database_integrity": "passed",
        "production_source_unchanged": "passed",
    },
}
ready.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PYREADY
chmod 0640 "$READY"
chown drivelab-license:drivelab-license "$READY"
ln -sfn "$STAGE" "$LATEST_LINK"

cat <<EOF

============================================================
LIFECYCLE STAGING PASSED — PRODUCTION WAS NOT MODIFIED
============================================================
Stage: $STAGE
Ready marker: $READY

Passed:
  - current production source baseline
  - deterministic lifecycle source patch
  - Python compilation
  - existing license and signed-update tests
  - lifecycle registration, privacy, conversion, dedupe and replay tests
  - copied SQLite schema and integrity
  - real signed lifecycle registration and batch HTTP ingestion
  - authenticated lifecycle overview and device timeline pages
  - Control Center 3.1 navigation integration
  - production source hashes unchanged
  - production API and Owner Console remained active

No APK, update feed, live database, production source, key, or service was changed.
EOF

cp "$REPORT" "$HOME_REPORT"
chown kali:kali "$HOME_REPORT" 2>/dev/null || true
chmod 0640 "$HOME_REPORT"
echo "Report copy: $HOME_REPORT"

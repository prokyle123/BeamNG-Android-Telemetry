from __future__ import annotations

import base64
import hashlib
import json
import os
import time
import uuid
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec


def setup_env(tmp_path: Path) -> None:
    os.environ["DLT_DATABASE_PATH"] = str(tmp_path / "licenses.db")
    os.environ["DLT_PRIVATE_KEY_PATH"] = str(tmp_path / "private.pem")
    os.environ["DLT_PUBLIC_KEY_PATH"] = str(tmp_path / "public.pem")
    os.environ["DLT_UPDATE_DIR"] = str(tmp_path / "updates")
    os.environ["DLT_LICENSE_PEPPER"] = "test-pepper-0123456789abcdef"
    os.environ["DLT_ADMIN_TOKEN"] = "test-admin-0123456789abcdef"
    os.environ["DLT_CERT_REFRESH_DAYS"] = "7"
    os.environ["DLT_CERT_GRACE_DAYS"] = "30"


def make_device():
    key = ec.generate_private_key(ec.SECP256R1())
    public_der = key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return key, base64.b64encode(public_der).decode("ascii")


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def sign(key, message: str) -> str:
    return b64url(key.sign(message.encode("utf-8"), ec.ECDSA(hashes.SHA256())))


def register_body(key, public_key: str, installation_id: str, app_version: str, nonce: str):
    from drivelab_license.crypto import device_key_hash

    timestamp = int(time.time())
    key_hash = device_key_hash(public_key)
    message = f"lifecycle_register|{installation_id}|{timestamp}|{nonce}|{app_version}|{key_hash}"
    return {
        "installation_id": installation_id,
        "device_public_key": public_key,
        "timestamp": timestamp,
        "nonce": nonce,
        "app_version": app_version,
        "proof_signature": sign(key, message),
    }


def batch_body(key, installation_id: str, app_version: str, nonce: str, events: list[dict]):
    timestamp = int(time.time())
    canonical = json.dumps(events, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    payload_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    message = f"lifecycle_batch:{payload_hash}|{installation_id}|{timestamp}|{nonce}|{app_version}"
    return {
        "installation_id": installation_id,
        "timestamp": timestamp,
        "nonce": nonce,
        "app_version": app_version,
        "events": events,
        "proof_signature": sign(key, message),
    }


def test_lifecycle_registration_batch_conversion_and_replay(tmp_path: Path):
    setup_env(tmp_path)

    from drivelab_license.config import load_settings
    from drivelab_license.crypto import generate_license_key, generate_signing_keys, hmac_hash, normalize_license_key
    from drivelab_license.database import Database
    from drivelab_license.lifecycle import LifecycleService
    from drivelab_license.service import LicenseError, LicenseService

    settings = load_settings()
    generate_signing_keys(settings.private_key_path, settings.public_key_path)
    database = Database(settings.database_path)
    database.initialize()

    installation_id = "install-lifecycle-123456"
    device_key, device_public = make_device()
    license_service = LicenseService(settings)
    lifecycle = LifecycleService(license_service)

    registered = lifecycle.register(
        register_body(
            device_key,
            device_public,
            installation_id,
            "2.4.0",
            "register-free-0001",
        )
    )
    assert registered["edition"] == "free"
    assert registered["license_associated"] is False

    now = int(time.time())
    events = [
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "app_launch",
            "occurred_at": now,
            "session_id": "app-session-0001",
            "properties": {
                "launch_reason": "launcher",
                "previous_run_clean": True,
                "android_version": "16",
                "device_model": "test-device",
            },
        },
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "beamng_connected",
            "occurred_at": now,
            "session_id": "app-session-0001",
            "properties": {
                "mode": "full_telemetry",
                "time_to_first_packet_ms": 410,
            },
        },
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "feature_opened",
            "occurred_at": now,
            "session_id": "app-session-0001",
            "properties": {"feature": "drift_lab"},
        },
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "app_session_ended",
            "occurred_at": now,
            "session_id": "app-session-0001",
            "properties": {"clean": True, "duration_seconds": 420},
        },
    ]
    accepted = lifecycle.ingest_batch(
        batch_body(
            device_key,
            installation_id,
            "2.4.0",
            "batch-free-0001",
            events,
        )
    )
    assert accepted["accepted"] == 4
    assert accepted["duplicates"] == 0
    assert accepted["active_days"] == 1

    license_key = generate_license_key()
    license_id = "DLT-LIFECYCLE-TEST"
    with database.connect() as connection:
        connection.execute(
            "INSERT INTO licenses(id,key_hash,key_hint,customer_email,edition,device_limit,status,created_at,notes) VALUES(?,?,?,?,?,?,?,?,?)",
            (
                license_id,
                hmac_hash(settings.license_pepper, normalize_license_key(license_key)),
                license_key[-9:],
                "lifecycle@example.com",
                "full",
                2,
                "active",
                now,
                "",
            ),
        )
    activated = license_service.activate(
        license_key,
        installation_id,
        device_public,
        "2.4.0",
    )
    assert activated.refresh_token

    registered_full = lifecycle.register(
        register_body(
            device_key,
            device_public,
            installation_id,
            "2.4.0",
            "register-full-0002",
        )
    )
    assert registered_full["edition"] == "full"
    assert registered_full["license_associated"] is True

    second_events = [
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "version_changed",
            "occurred_at": now,
            "session_id": "app-session-0002",
            "properties": {"from_version": "2.3.0", "to_version": "2.4.0"},
        },
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "drive_session_summary",
            "occurred_at": now,
            "session_id": "drive-session-0001",
            "properties": {
                "duration_seconds": 900,
                "distance_meters": 12500,
                "max_speed_mph": 126.5,
                "peak_g": 1.8,
                "crash_count": 0,
                "drift_score": 5400,
                "max_drift_angle_deg": 31.5,
                "total_shifts": 44,
                "abuse_score": 8,
                "shift_score": 92,
                "automatic": True,
            },
        },
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "diagnostic_report",
            "occurred_at": now,
            "session_id": "app-session-0002",
            "properties": {
                "summary": "BeamNG connection test requested by user",
                "categories": ["connection"],
                "error_count": 1,
                "connection_state": "waiting_for_game",
                "database_ok": True,
                "recent_errors": ["No packets received during the test window"],
            },
        },
    ]
    full_result = lifecycle.ingest_batch(
        batch_body(
            device_key,
            installation_id,
            "2.4.0",
            "batch-full-0002",
            second_events,
        )
    )
    assert full_result["edition"] == "full"
    assert full_result["accepted"] == 3

    duplicate_result = lifecycle.ingest_batch(
        batch_body(
            device_key,
            installation_id,
            "2.4.0",
            "batch-duplicate-0003",
            second_events,
        )
    )
    assert duplicate_result["accepted"] == 0
    assert duplicate_result["duplicates"] == 3

    replay_body = batch_body(
        device_key,
        installation_id,
        "2.4.0",
        "batch-replay-0004",
        [
            {
                "event_id": str(uuid.uuid4()),
                "event_type": "app_foreground",
                "occurred_at": now,
                "session_id": "app-session-0003",
                "properties": {"background_seconds": 30},
            }
        ],
    )
    lifecycle.ingest_batch(replay_body)
    try:
        lifecycle.ingest_batch(replay_body)
        raise AssertionError("replayed lifecycle request should fail")
    except LicenseError as exc:
        assert exc.code == "replayed_request"

    with database.connect() as connection:
        presence = connection.execute(
            "SELECT * FROM device_presence WHERE installation_id=?",
            (installation_id,),
        ).fetchone()
        assert presence["edition"] == "full"
        assert presence["current_license_id"] == license_id
        assert int(presence["launch_count"]) == 1
        assert int(presence["active_days"]) == 1
        assert int(presence["clean_sessions"]) == 1
        assert int(presence["feature_open_count"]) == 1
        assert int(presence["session_summary_count"]) == 1
        assert int(presence["diagnostic_count"]) == 1
        assert connection.execute(
            "SELECT COUNT(*) FROM device_version_history WHERE installation_id=?",
            (installation_id,),
        ).fetchone()[0] == 1
        assert connection.execute(
            "SELECT COUNT(*) FROM device_edition_history WHERE installation_id=?",
            (installation_id,),
        ).fetchone()[0] == 2
        assert connection.execute(
            "SELECT COUNT(*) FROM device_diagnostic_reports WHERE installation_id=?",
            (installation_id,),
        ).fetchone()[0] == 1


def test_lifecycle_rejects_unknown_properties_and_changed_identity(tmp_path: Path):
    setup_env(tmp_path)

    from drivelab_license.config import load_settings
    from drivelab_license.crypto import generate_signing_keys
    from drivelab_license.database import Database
    from drivelab_license.lifecycle import LifecycleService
    from drivelab_license.service import LicenseError, LicenseService

    settings = load_settings()
    generate_signing_keys(settings.private_key_path, settings.public_key_path)
    Database(settings.database_path).initialize()
    lifecycle = LifecycleService(LicenseService(settings))

    installation_id = "install-lifecycle-privacy"
    key, public_key = make_device()
    lifecycle.register(
        register_body(key, public_key, installation_id, "2.4.0", "register-privacy-01")
    )

    now = int(time.time())
    unsafe_events = [
        {
            "event_id": str(uuid.uuid4()),
            "event_type": "drive_session_summary",
            "occurred_at": now,
            "session_id": "drive-privacy-test",
            "properties": {
                "duration_seconds": 100,
                "gps_coordinates": "41.0,-87.0",
            },
        }
    ]
    try:
        lifecycle.ingest_batch(
            batch_body(
                key,
                installation_id,
                "2.4.0",
                "batch-privacy-01",
                unsafe_events,
            )
        )
        raise AssertionError("unsupported location property should fail")
    except LicenseError as exc:
        assert exc.code == "unsupported_event_property"

    other_key, other_public = make_device()
    try:
        lifecycle.register(
            register_body(
                other_key,
                other_public,
                installation_id,
                "2.4.0",
                "register-other-key-02",
            )
        )
        raise AssertionError("changed lifecycle identity should fail")
    except LicenseError as exc:
        assert exc.code == "device_identity_changed"

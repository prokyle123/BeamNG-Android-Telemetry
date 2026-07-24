from __future__ import annotations

import hashlib
import json
import math
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException

from .crypto import device_key_hash, verify_device_signature
from .service import LicenseError, LicenseService


LIFECYCLE_VERSION = "1.0.0"
MAX_BATCH_EVENTS = 50
MAX_EVENT_PROPERTIES_BYTES = 4096
MAX_DIAGNOSTIC_BYTES = 16000
REQUEST_WINDOW_SECONDS = 300
EVENT_PAST_WINDOW_SECONDS = 90 * 86400
EVENT_FUTURE_WINDOW_SECONDS = 600

EVENT_TYPES = {
    "app_launch",
    "app_foreground",
    "app_session_ended",
    "version_changed",
    "edition_changed",
    "beamng_connect_attempt",
    "beamng_connected",
    "beamng_connect_failed",
    "beamng_disconnected",
    "feature_opened",
    "feature_completed",
    "drive_session_summary",
    "diagnostic_report",
}

PROPERTY_ALLOWLIST: dict[str, set[str]] = {
    "app_launch": {
        "launch_reason",
        "previous_run_clean",
        "android_version",
        "device_model",
    },
    "app_foreground": {"background_seconds"},
    "app_session_ended": {"clean", "duration_seconds"},
    "version_changed": {"from_version", "to_version"},
    "edition_changed": {"from_edition", "to_edition"},
    "beamng_connect_attempt": {"mode"},
    "beamng_connected": {"mode", "time_to_first_packet_ms"},
    "beamng_connect_failed": {"reason"},
    "beamng_disconnected": {"reason", "duration_seconds", "reconnect_count"},
    "feature_opened": {"feature"},
    "feature_completed": {"feature", "result"},
    "drive_session_summary": {
        "duration_seconds",
        "distance_meters",
        "max_speed_mph",
        "peak_g",
        "crash_count",
        "drift_score",
        "max_drift_angle_deg",
        "total_shifts",
        "abuse_score",
        "shift_score",
        "automatic",
    },
    "diagnostic_report": {
        "summary",
        "categories",
        "error_count",
        "connection_state",
        "database_ok",
        "recent_errors",
    },
}

FEATURE_NAMES = {
    "live",
    "cockpit",
    "tracklab",
    "drag_lab",
    "brake_lab",
    "drift_lab",
    "offroad_lab",
    "racelink",
    "progress",
    "achievements",
    "temperatures",
    "damage",
    "coach",
    "dynamics",
    "records",
    "protocol",
    "sessions",
    "graphs",
    "setup",
    "license_activation",
    "diagnostic_report",
}

LIFECYCLE_SCHEMA = """
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS device_lifecycle_nonces (
    installation_id TEXT NOT NULL,
    nonce TEXT NOT NULL,
    used_at INTEGER NOT NULL,
    PRIMARY KEY(installation_id, nonce)
);

CREATE TABLE IF NOT EXISTS device_lifecycle_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    installation_id TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    received_at INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    app_version TEXT NOT NULL DEFAULT '',
    edition TEXT NOT NULL DEFAULT 'free',
    license_id TEXT NOT NULL DEFAULT '',
    session_id TEXT NOT NULL DEFAULT '',
    properties_json TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS device_active_days (
    installation_id TEXT NOT NULL,
    active_date TEXT NOT NULL,
    first_seen_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    launch_count INTEGER NOT NULL DEFAULT 0,
    foreground_count INTEGER NOT NULL DEFAULT 0,
    connection_successes INTEGER NOT NULL DEFAULT 0,
    connection_failures INTEGER NOT NULL DEFAULT 0,
    clean_sessions INTEGER NOT NULL DEFAULT 0,
    unclean_sessions INTEGER NOT NULL DEFAULT 0,
    feature_opens INTEGER NOT NULL DEFAULT 0,
    feature_completions INTEGER NOT NULL DEFAULT 0,
    drive_summaries INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(installation_id, active_date)
);

CREATE TABLE IF NOT EXISTS device_version_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    installation_id TEXT NOT NULL,
    app_version TEXT NOT NULL,
    first_seen_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    launch_count INTEGER NOT NULL DEFAULT 0,
    UNIQUE(installation_id, app_version)
);

CREATE TABLE IF NOT EXISTS device_edition_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    installation_id TEXT NOT NULL,
    edition TEXT NOT NULL,
    license_id TEXT NOT NULL DEFAULT '',
    first_seen_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    UNIQUE(installation_id, edition, license_id)
);

CREATE TABLE IF NOT EXISTS device_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_installation_id TEXT NOT NULL,
    target_installation_id TEXT NOT NULL,
    relationship_type TEXT NOT NULL DEFAULT 'replacement',
    note TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    UNIQUE(source_installation_id, target_installation_id, relationship_type)
);

CREATE TABLE IF NOT EXISTS device_diagnostic_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id TEXT NOT NULL UNIQUE,
    installation_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    received_at INTEGER NOT NULL,
    app_version TEXT NOT NULL DEFAULT '',
    edition TEXT NOT NULL DEFAULT 'free',
    license_id TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    payload_json TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'new',
    owner_note TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_lifecycle_events_install_time
ON device_lifecycle_events(installation_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_lifecycle_events_type_time
ON device_lifecycle_events(event_type, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_active_days_date
ON device_active_days(active_date DESC);

CREATE INDEX IF NOT EXISTS idx_version_history_version
ON device_version_history(app_version, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS idx_diagnostic_status
ON device_diagnostic_reports(status, received_at DESC);
"""

PRESENCE_COLUMNS: dict[str, str] = {
    "device_public_key": "TEXT NOT NULL DEFAULT ''",
    "device_key_hash": "TEXT NOT NULL DEFAULT ''",
    "first_app_version": "TEXT NOT NULL DEFAULT ''",
    "previous_app_version": "TEXT NOT NULL DEFAULT ''",
    "version_changed_at": "INTEGER NOT NULL DEFAULT 0",
    "previous_edition": "TEXT NOT NULL DEFAULT ''",
    "edition_changed_at": "INTEGER NOT NULL DEFAULT 0",
    "current_license_id": "TEXT NOT NULL DEFAULT ''",
    "launch_count": "INTEGER NOT NULL DEFAULT 0",
    "active_days": "INTEGER NOT NULL DEFAULT 0",
    "last_active_day": "TEXT NOT NULL DEFAULT ''",
    "last_event_at": "INTEGER NOT NULL DEFAULT 0",
    "last_connection_status": "TEXT NOT NULL DEFAULT ''",
    "last_connection_at": "INTEGER NOT NULL DEFAULT 0",
    "clean_sessions": "INTEGER NOT NULL DEFAULT 0",
    "unclean_sessions": "INTEGER NOT NULL DEFAULT 0",
    "feature_open_count": "INTEGER NOT NULL DEFAULT 0",
    "feature_complete_count": "INTEGER NOT NULL DEFAULT 0",
    "session_summary_count": "INTEGER NOT NULL DEFAULT 0",
    "diagnostic_count": "INTEGER NOT NULL DEFAULT 0",
}


def _connect(database_path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(database_path, timeout=30)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    return connection


def ensure_lifecycle_schema(database_path: Path) -> None:
    database_path.parent.mkdir(parents=True, exist_ok=True)
    with _connect(database_path) as connection:
        connection.executescript(LIFECYCLE_SCHEMA)
        columns = {
            str(row["name"])
            for row in connection.execute("PRAGMA table_info(device_presence)").fetchall()
        }
        if not columns:
            raise RuntimeError("The required device_presence table is missing.")
        for name, declaration in PRESENCE_COLUMNS.items():
            if name not in columns:
                connection.execute(
                    f"ALTER TABLE device_presence ADD COLUMN {name} {declaration}"
                )
        connection.commit()


def _text(value: Any, limit: int = 160) -> str:
    return str(value or "").strip()[:limit]


def _safe_number(value: Any, minimum: float, maximum: float) -> float | int:
    if isinstance(value, bool):
        return int(value)
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0
    if not math.isfinite(number):
        return 0
    number = min(maximum, max(minimum, number))
    return int(number) if number.is_integer() else round(number, 4)


def _sanitize_value(key: str, value: Any) -> Any:
    if key in {"clean", "previous_run_clean", "automatic", "database_ok"}:
        return bool(value)
    if key in {"categories", "recent_errors"}:
        if not isinstance(value, list):
            return []
        return [_text(item, 240) for item in value[:12] if _text(item, 240)]
    if key in {"feature"}:
        candidate = _text(value, 64).lower()
        return candidate if candidate in FEATURE_NAMES else "other"
    if key in {"from_edition", "to_edition"}:
        candidate = _text(value, 16).lower()
        return candidate if candidate in {"free", "full"} else "unknown"
    if key in {
        "duration_seconds",
        "background_seconds",
    }:
        return _safe_number(value, 0, 30 * 86400)
    if key in {"distance_meters"}:
        return _safe_number(value, 0, 10_000_000)
    if key in {"max_speed_mph"}:
        return _safe_number(value, 0, 1000)
    if key in {"peak_g", "max_drift_angle_deg"}:
        return _safe_number(value, 0, 100)
    if key in {
        "time_to_first_packet_ms",
        "reconnect_count",
        "crash_count",
        "drift_score",
        "total_shifts",
        "abuse_score",
        "shift_score",
        "error_count",
    }:
        return int(_safe_number(value, 0, 2_000_000))
    return _text(value, 240)


def sanitize_properties(event_type: str, raw: Any) -> dict[str, Any]:
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise LicenseError("invalid_event_properties", "Event properties must be an object.", 422)
    allowed = PROPERTY_ALLOWLIST[event_type]
    unknown = sorted(set(str(key) for key in raw) - allowed)
    if unknown:
        raise LicenseError(
            "unsupported_event_property",
            "Unsupported event property: " + ", ".join(unknown[:5]),
            422,
        )
    clean = {key: _sanitize_value(key, raw[key]) for key in allowed if key in raw}
    packed = json.dumps(clean, sort_keys=True, separators=(",", ":"))
    limit = MAX_DIAGNOSTIC_BYTES if event_type == "diagnostic_report" else MAX_EVENT_PROPERTIES_BYTES
    if len(packed.encode("utf-8")) > limit:
        raise LicenseError("event_properties_too_large", "Event properties exceed the allowed size.", 413)
    return clean


def _canonical_events(events: list[dict[str, Any]]) -> str:
    return json.dumps(events, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _day(timestamp: int) -> str:
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime("%Y-%m-%d")


class LifecycleService:
    def __init__(self, license_service: LicenseService):
        self.license_service = license_service
        self.database_path = Path(license_service.settings.database_path)
        ensure_lifecycle_schema(self.database_path)

    @staticmethod
    def _validate_request_time(timestamp: int) -> int:
        now = int(time.time())
        if abs(now - int(timestamp)) > REQUEST_WINDOW_SECONDS:
            raise LicenseError(
                "stale_request",
                "The signed lifecycle request timestamp is outside the five-minute window.",
                401,
            )
        return now

    @staticmethod
    def _validate_identity(installation_id: str, app_version: str, nonce: str) -> tuple[str, str, str]:
        installation_id = _text(installation_id, 128)
        app_version = _text(app_version, 40)
        nonce = _text(nonce, 128)
        if not 12 <= len(installation_id) <= 128:
            raise LicenseError("invalid_installation", "Invalid installation ID.", 422)
        if not app_version:
            raise LicenseError("invalid_app_version", "The app version is required.", 422)
        if not 8 <= len(nonce) <= 128:
            raise LicenseError("invalid_nonce", "The lifecycle nonce is invalid.", 422)
        return installation_id, app_version, nonce

    @staticmethod
    def _edition_and_license(connection: sqlite3.Connection, installation_id: str) -> tuple[str, str, str]:
        row = connection.execute(
            "SELECT l.id license_id,l.edition,a.device_key_hash "
            "FROM activations a JOIN licenses l ON l.id=a.license_id "
            "WHERE a.installation_id=? AND a.status='active' AND l.status='active' "
            "ORDER BY a.last_seen_at DESC LIMIT 1",
            (installation_id,),
        ).fetchone()
        if row is None:
            return "free", "", ""
        edition = "full" if str(row["edition"] or "").lower() == "full" else "free"
        return edition, str(row["license_id"] or ""), str(row["device_key_hash"] or "")

    @staticmethod
    def _consume_nonce(connection: sqlite3.Connection, installation_id: str, nonce: str, now: int) -> None:
        connection.execute(
            "DELETE FROM device_lifecycle_nonces WHERE used_at<?",
            (now - 86400,),
        )
        try:
            connection.execute(
                "INSERT INTO device_lifecycle_nonces(installation_id,nonce,used_at) VALUES(?,?,?)",
                (installation_id, nonce, now),
            )
        except sqlite3.IntegrityError as exc:
            raise LicenseError("replayed_request", "This lifecycle request was already used.", 409) from exc

    @staticmethod
    def _record_version(connection: sqlite3.Connection, installation_id: str, app_version: str, now: int, launch: bool = False) -> None:
        connection.execute(
            "INSERT INTO device_version_history(installation_id,app_version,first_seen_at,last_seen_at,launch_count) "
            "VALUES(?,?,?,?,?) ON CONFLICT(installation_id,app_version) DO UPDATE SET "
            "last_seen_at=excluded.last_seen_at,launch_count=device_version_history.launch_count+excluded.launch_count",
            (installation_id, app_version, now, now, int(launch)),
        )

    @staticmethod
    def _record_edition(connection: sqlite3.Connection, installation_id: str, edition: str, license_id: str, now: int) -> None:
        connection.execute(
            "INSERT INTO device_edition_history(installation_id,edition,license_id,first_seen_at,last_seen_at) "
            "VALUES(?,?,?,?,?) ON CONFLICT(installation_id,edition,license_id) DO UPDATE SET last_seen_at=excluded.last_seen_at",
            (installation_id, edition, license_id, now, now),
        )

    def register(self, body: dict[str, Any]) -> dict[str, Any]:
        installation_id, app_version, nonce = self._validate_identity(
            body.get("installation_id", ""), body.get("app_version", ""), body.get("nonce", "")
        )
        timestamp = int(body.get("timestamp", 0) or 0)
        now = self._validate_request_time(timestamp)
        public_key = _text(body.get("device_public_key", ""), 2048)
        proof = _text(body.get("proof_signature", ""), 2048)
        if len(public_key) < 64 or len(proof) < 20:
            raise LicenseError("invalid_device_identity", "The device public key and proof are required.", 422)
        supplied_hash = device_key_hash(public_key)
        message = f"lifecycle_register|{installation_id}|{timestamp}|{nonce}|{app_version}|{supplied_hash}"
        if not verify_device_signature(public_key, message, proof):
            raise LicenseError("invalid_device_proof", "The lifecycle registration proof is invalid.", 401)

        with _connect(self.database_path) as connection:
            existing = connection.execute(
                "SELECT * FROM device_presence WHERE installation_id=?",
                (installation_id,),
            ).fetchone()
            if existing is not None and str(existing["device_key_hash"] or "") not in {"", supplied_hash}:
                raise LicenseError(
                    "device_identity_changed",
                    "This installation is already bound to a different device key.",
                    409,
                )
            edition, license_id, activation_key_hash = self._edition_and_license(connection, installation_id)
            if activation_key_hash and activation_key_hash != supplied_hash:
                raise LicenseError(
                    "activation_identity_mismatch",
                    "The active Full license is bound to a different device key.",
                    409,
                )
            self._consume_nonce(connection, installation_id, nonce, now)
            previous_version = str(existing["app_version"] or "") if existing is not None else ""
            previous_edition = str(existing["edition"] or "") if existing is not None else ""
            first_version = str(existing["first_app_version"] or "") if existing is not None else ""
            connection.execute(
                "INSERT INTO device_presence(installation_id,edition,app_version,first_seen_at,last_seen_at," 
                "device_public_key,device_key_hash,first_app_version,previous_app_version,version_changed_at," 
                "previous_edition,edition_changed_at,current_license_id,last_event_at) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(installation_id) DO UPDATE SET "
                "edition=excluded.edition,app_version=excluded.app_version,last_seen_at=excluded.last_seen_at," 
                "device_public_key=excluded.device_public_key,device_key_hash=excluded.device_key_hash," 
                "first_app_version=CASE WHEN device_presence.first_app_version='' THEN excluded.first_app_version ELSE device_presence.first_app_version END," 
                "previous_app_version=CASE WHEN device_presence.app_version<>excluded.app_version THEN device_presence.app_version ELSE device_presence.previous_app_version END," 
                "version_changed_at=CASE WHEN device_presence.app_version<>excluded.app_version THEN excluded.last_seen_at ELSE device_presence.version_changed_at END," 
                "previous_edition=CASE WHEN device_presence.edition<>excluded.edition THEN device_presence.edition ELSE device_presence.previous_edition END," 
                "edition_changed_at=CASE WHEN device_presence.edition<>excluded.edition THEN excluded.last_seen_at ELSE device_presence.edition_changed_at END," 
                "current_license_id=excluded.current_license_id,last_event_at=MAX(device_presence.last_event_at,excluded.last_event_at)",
                (
                    installation_id,
                    edition,
                    app_version,
                    now,
                    now,
                    public_key,
                    supplied_hash,
                    first_version or app_version,
                    previous_version if previous_version and previous_version != app_version else "",
                    now if previous_version and previous_version != app_version else 0,
                    previous_edition if previous_edition and previous_edition != edition else "",
                    now if previous_edition and previous_edition != edition else 0,
                    license_id,
                    now,
                ),
            )
            self._record_version(connection, installation_id, app_version, now)
            self._record_edition(connection, installation_id, edition, license_id, now)
            connection.commit()

        return {
            "registered": True,
            "lifecycle_version": LIFECYCLE_VERSION,
            "edition": edition,
            "license_associated": bool(license_id),
            "max_batch_events": MAX_BATCH_EVENTS,
        }

    def ingest_batch(self, body: dict[str, Any]) -> dict[str, Any]:
        installation_id, app_version, nonce = self._validate_identity(
            body.get("installation_id", ""), body.get("app_version", ""), body.get("nonce", "")
        )
        timestamp = int(body.get("timestamp", 0) or 0)
        now = self._validate_request_time(timestamp)
        proof = _text(body.get("proof_signature", ""), 2048)
        raw_events = body.get("events")
        if not isinstance(raw_events, list) or not 1 <= len(raw_events) <= MAX_BATCH_EVENTS:
            raise LicenseError(
                "invalid_event_batch",
                f"A lifecycle batch must contain 1 to {MAX_BATCH_EVENTS} events.",
                422,
            )

        clean_events: list[dict[str, Any]] = []
        for raw in raw_events:
            if not isinstance(raw, dict):
                raise LicenseError("invalid_event", "Each lifecycle event must be an object.", 422)
            event_id = _text(raw.get("event_id", ""), 128)
            event_type = _text(raw.get("event_type", ""), 64).lower()
            session_id = _text(raw.get("session_id", ""), 128)
            if not 12 <= len(event_id) <= 128:
                raise LicenseError("invalid_event_id", "A lifecycle event ID is invalid.", 422)
            if event_type not in EVENT_TYPES:
                raise LicenseError("unsupported_event_type", f"Unsupported lifecycle event: {event_type}", 422)
            occurred_at = int(raw.get("occurred_at", 0) or 0)
            if occurred_at < now - EVENT_PAST_WINDOW_SECONDS or occurred_at > now + EVENT_FUTURE_WINDOW_SECONDS:
                raise LicenseError("invalid_event_time", "A lifecycle event timestamp is outside the accepted window.", 422)
            properties = sanitize_properties(event_type, raw.get("properties", {}))
            clean_events.append(
                {
                    "event_id": event_id,
                    "event_type": event_type,
                    "occurred_at": occurred_at,
                    "session_id": session_id,
                    "properties": properties,
                }
            )

        canonical = _canonical_events(clean_events)
        payload_hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
        message = f"lifecycle_batch:{payload_hash}|{installation_id}|{timestamp}|{nonce}|{app_version}"

        with _connect(self.database_path) as connection:
            presence = connection.execute(
                "SELECT * FROM device_presence WHERE installation_id=?",
                (installation_id,),
            ).fetchone()
            if presence is None or not str(presence["device_public_key"] or ""):
                raise LicenseError(
                    "lifecycle_registration_required",
                    "This installation must register its signed lifecycle identity first.",
                    409,
                )
            if not verify_device_signature(str(presence["device_public_key"]), message, proof):
                raise LicenseError("invalid_device_proof", "The lifecycle batch proof is invalid.", 401)
            edition, license_id, activation_key_hash = self._edition_and_license(connection, installation_id)
            if activation_key_hash and activation_key_hash != str(presence["device_key_hash"] or ""):
                raise LicenseError(
                    "activation_identity_mismatch",
                    "The active Full license does not match this lifecycle identity.",
                    409,
                )
            self._consume_nonce(connection, installation_id, nonce, now)

            accepted = 0
            duplicates = 0
            launch_increment = 0
            clean_increment = 0
            unclean_increment = 0
            feature_open_increment = 0
            feature_complete_increment = 0
            summary_increment = 0
            diagnostic_increment = 0
            last_connection_status = ""
            last_connection_at = 0
            active_days: set[str] = set()

            for event in clean_events:
                packed = json.dumps(event["properties"], sort_keys=True, separators=(",", ":"))
                try:
                    connection.execute(
                        "INSERT INTO device_lifecycle_events(event_id,installation_id,occurred_at,received_at,event_type,app_version,edition,license_id,session_id,properties_json) "
                        "VALUES(?,?,?,?,?,?,?,?,?,?)",
                        (
                            event["event_id"],
                            installation_id,
                            event["occurred_at"],
                            now,
                            event["event_type"],
                            app_version,
                            edition,
                            license_id,
                            event["session_id"],
                            packed,
                        ),
                    )
                except sqlite3.IntegrityError:
                    duplicates += 1
                    continue

                accepted += 1
                event_type = event["event_type"]
                props = event["properties"]
                day = _day(event["occurred_at"])
                active_days.add(day)
                counters = {
                    "launch_count": int(event_type == "app_launch"),
                    "foreground_count": int(event_type == "app_foreground"),
                    "connection_successes": int(event_type == "beamng_connected"),
                    "connection_failures": int(event_type == "beamng_connect_failed"),
                    "clean_sessions": int(event_type == "app_session_ended" and bool(props.get("clean"))),
                    "unclean_sessions": int(
                        (event_type == "app_session_ended" and not bool(props.get("clean")))
                        or (event_type == "app_launch" and props.get("previous_run_clean") is False)
                    ),
                    "feature_opens": int(event_type == "feature_opened"),
                    "feature_completions": int(event_type == "feature_completed"),
                    "drive_summaries": int(event_type == "drive_session_summary"),
                }
                connection.execute(
                    "INSERT INTO device_active_days(installation_id,active_date,first_seen_at,last_seen_at,launch_count,foreground_count,connection_successes,connection_failures,clean_sessions,unclean_sessions,feature_opens,feature_completions,drive_summaries) "
                    "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(installation_id,active_date) DO UPDATE SET "
                    "last_seen_at=MAX(device_active_days.last_seen_at,excluded.last_seen_at)," 
                    "launch_count=device_active_days.launch_count+excluded.launch_count," 
                    "foreground_count=device_active_days.foreground_count+excluded.foreground_count," 
                    "connection_successes=device_active_days.connection_successes+excluded.connection_successes," 
                    "connection_failures=device_active_days.connection_failures+excluded.connection_failures," 
                    "clean_sessions=device_active_days.clean_sessions+excluded.clean_sessions," 
                    "unclean_sessions=device_active_days.unclean_sessions+excluded.unclean_sessions," 
                    "feature_opens=device_active_days.feature_opens+excluded.feature_opens," 
                    "feature_completions=device_active_days.feature_completions+excluded.feature_completions," 
                    "drive_summaries=device_active_days.drive_summaries+excluded.drive_summaries",
                    (
                        installation_id,
                        day,
                        event["occurred_at"],
                        event["occurred_at"],
                        counters["launch_count"],
                        counters["foreground_count"],
                        counters["connection_successes"],
                        counters["connection_failures"],
                        counters["clean_sessions"],
                        counters["unclean_sessions"],
                        counters["feature_opens"],
                        counters["feature_completions"],
                        counters["drive_summaries"],
                    ),
                )

                launch_increment += counters["launch_count"]
                clean_increment += counters["clean_sessions"]
                unclean_increment += counters["unclean_sessions"]
                feature_open_increment += counters["feature_opens"]
                feature_complete_increment += counters["feature_completions"]
                summary_increment += counters["drive_summaries"]

                if event_type in {"beamng_connected", "beamng_connect_failed", "beamng_disconnected"}:
                    last_connection_status = event_type.removeprefix("beamng_")
                    last_connection_at = max(last_connection_at, int(event["occurred_at"]))

                if event_type == "diagnostic_report":
                    diagnostic_increment += 1
                    report_id = event["event_id"]
                    summary = _text(props.get("summary", ""), 500)
                    connection.execute(
                        "INSERT OR IGNORE INTO device_diagnostic_reports(report_id,installation_id,created_at,received_at,app_version,edition,license_id,summary,payload_json) "
                        "VALUES(?,?,?,?,?,?,?,?,?)",
                        (
                            report_id,
                            installation_id,
                            event["occurred_at"],
                            now,
                            app_version,
                            edition,
                            license_id,
                            summary,
                            packed,
                        ),
                    )

            previous_version = str(presence["app_version"] or "")
            previous_edition = str(presence["edition"] or "")
            self._record_version(connection, installation_id, app_version, now, launch=launch_increment > 0)
            self._record_edition(connection, installation_id, edition, license_id, now)
            active_day_count = int(
                connection.execute(
                    "SELECT COUNT(*) FROM device_active_days WHERE installation_id=?",
                    (installation_id,),
                ).fetchone()[0]
            )
            last_day = max(active_days) if active_days else str(presence["last_active_day"] or "")
            connection.execute(
                "UPDATE device_presence SET edition=?,app_version=?,last_seen_at=?,last_event_at=?," 
                "previous_app_version=CASE WHEN app_version<>? THEN app_version ELSE previous_app_version END," 
                "version_changed_at=CASE WHEN app_version<>? THEN ? ELSE version_changed_at END," 
                "previous_edition=CASE WHEN edition<>? THEN edition ELSE previous_edition END," 
                "edition_changed_at=CASE WHEN edition<>? THEN ? ELSE edition_changed_at END," 
                "current_license_id=?,launch_count=launch_count+?,active_days=?,last_active_day=?," 
                "last_connection_status=CASE WHEN ?<>'' THEN ? ELSE last_connection_status END," 
                "last_connection_at=MAX(last_connection_at,?),clean_sessions=clean_sessions+?," 
                "unclean_sessions=unclean_sessions+?,feature_open_count=feature_open_count+?," 
                "feature_complete_count=feature_complete_count+?,session_summary_count=session_summary_count+?," 
                "diagnostic_count=diagnostic_count+? WHERE installation_id=?",
                (
                    edition,
                    app_version,
                    now,
                    now,
                    app_version,
                    app_version,
                    now,
                    edition,
                    edition,
                    now,
                    license_id,
                    launch_increment,
                    active_day_count,
                    last_day,
                    last_connection_status,
                    last_connection_status,
                    last_connection_at,
                    clean_increment,
                    unclean_increment,
                    feature_open_increment,
                    feature_complete_increment,
                    summary_increment,
                    diagnostic_increment,
                    installation_id,
                ),
            )
            connection.commit()

        return {
            "accepted": accepted,
            "duplicates": duplicates,
            "edition": edition,
            "license_associated": bool(license_id),
            "active_days": active_day_count,
        }


def install_lifecycle_api(app: FastAPI, settings: Any, license_service: LicenseService) -> None:
    lifecycle = LifecycleService(license_service)

    @app.get("/v1/lifecycle/health")
    def lifecycle_health():
        ensure_lifecycle_schema(Path(settings.database_path))
        return {
            "status": "ok",
            "version": LIFECYCLE_VERSION,
            "max_batch_events": MAX_BATCH_EVENTS,
            "raw_gameplay_telemetry": False,
        }

    @app.post("/v1/lifecycle/register")
    def lifecycle_register(body: dict[str, Any]):
        try:
            return lifecycle.register(body)
        except LicenseError:
            raise
        except (TypeError, ValueError) as exc:
            raise HTTPException(status_code=422, detail="Invalid lifecycle registration payload.") from exc

    @app.post("/v1/lifecycle/batch")
    def lifecycle_batch(body: dict[str, Any]):
        try:
            return lifecycle.ingest_batch(body)
        except LicenseError:
            raise
        except (TypeError, ValueError) as exc:
            raise HTTPException(status_code=422, detail="Invalid lifecycle event batch.") from exc

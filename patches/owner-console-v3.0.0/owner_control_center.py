from __future__ import annotations

import html
import json
import re
import shutil
import sqlite3
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import quote

from fastapi import Cookie, Form, Header, HTTPException, Query
from fastapi.responses import HTMLResponse, RedirectResponse

from .admin_metrics import record_metrics_snapshot
from .database import Database
from .release_admin import current_release_status, list_archives


CONTROL_CENTER_VERSION = "3.0.0"
CACHE_SECONDS = 25

CONTROL_SCHEMA = """
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS owner_customer_meta (
    license_id TEXT PRIMARY KEY REFERENCES licenses(id) ON DELETE CASCADE,
    classification TEXT NOT NULL DEFAULT 'customer',
    tags TEXT NOT NULL DEFAULT '',
    support_status TEXT NOT NULL DEFAULT 'normal',
    last_contact_at INTEGER NOT NULL DEFAULT 0,
    replacement_for TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS owner_support_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    happened_at INTEGER NOT NULL,
    license_id TEXT NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL DEFAULT 'note',
    note TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS owner_operation_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    happened_at INTEGER NOT NULL,
    action TEXT NOT NULL,
    status TEXT NOT NULL,
    detail TEXT NOT NULL DEFAULT '',
    duration_ms INTEGER NOT NULL DEFAULT 0,
    request_id TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS owner_health_history (
    captured_at INTEGER PRIMARY KEY,
    overall TEXT NOT NULL,
    critical_count INTEGER NOT NULL DEFAULT 0,
    warning_count INTEGER NOT NULL DEFAULT 0,
    api_ok INTEGER NOT NULL DEFAULT 0,
    website_ok INTEGER NOT NULL DEFAULT 0,
    racelink_ok INTEGER NOT NULL DEFAULT 0,
    database_ok INTEGER NOT NULL DEFAULT 0,
    backup_ok INTEGER NOT NULL DEFAULT 0,
    release_ok INTEGER NOT NULL DEFAULT 0,
    free_disk_bytes INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_owner_support_events_license
ON owner_support_events(license_id, happened_at DESC);

CREATE INDEX IF NOT EXISTS idx_owner_operation_history_time
ON owner_operation_history(happened_at DESC);

CREATE INDEX IF NOT EXISTS idx_owner_customer_meta_status
ON owner_customer_meta(support_status, classification);
"""

STYLE = r"""
:root{color-scheme:dark;--bg:#0c1118;--panel:#131d28;--panel2:#172433;--line:#2d4055;--text:#edf5fc;--muted:#9fb0c2;--cyan:#50d8f2;--green:#67dda0;--amber:#ffc766;--red:#ff7280;--purple:#be8cff;--blue:#7ba7ff}
*{box-sizing:border-box}body{margin:0 auto;padding:22px;max-width:1700px;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,Segoe UI,sans-serif}a{color:var(--cyan);text-decoration:none}a:hover{text-decoration:underline}h1,h2,h3{margin:.2rem 0 .65rem}.topbar{display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:14px;margin-bottom:14px}.nav{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.nav a{padding:8px 11px;border:1px solid var(--line);border-radius:8px;background:#152130}.panel{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px;margin:14px 0;box-shadow:0 7px 24px #0005}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:11px}.card{background:var(--panel2);border:1px solid #324a62;border-radius:10px;padding:13px}.card strong{display:block;font-size:1.5rem;margin-bottom:3px}.card span{color:var(--muted)}.two{display:grid;grid-template-columns:repeat(auto-fit,minmax(390px,1fr));gap:14px}.three{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:14px}.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:10px}table{width:100%;border-collapse:collapse;min-width:900px;background:#101923}td,th{text-align:left;vertical-align:middle;border-bottom:1px solid #283b50;padding:9px}th{background:#192737;color:#d6e8f7;position:sticky;top:0}tr:hover td{background:#152333}.ok{color:var(--green);font-weight:800}.warn{color:var(--amber);font-weight:800}.bad{color:var(--red);font-weight:800}.info{color:var(--cyan);font-weight:800}.muted{color:var(--muted)}.small{font-size:.86rem}.mono,code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace}code{background:#091018;padding:2px 5px;border-radius:4px}.notice,.warning,.error,.info-box{padding:11px 13px;margin:9px 0;border-radius:8px}.notice{background:#143625;border:1px solid #3b8e65;color:#c1f6d7}.warning{background:#35270f;border:1px solid #93712d;color:#ffe3a6}.error{background:#471c24;border:1px solid #a94352;color:#ffd0d5}.info-box{background:#103142;border:1px solid #28728d;color:#c8f4ff}.health-row{display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-bottom:1px solid #263a4d}.health-row:last-child{border-bottom:0}.badge{display:inline-block;padding:3px 8px;border-radius:999px;border:1px solid #46627e;font-size:.75rem;font-weight:800}.badge.ok{background:#143625}.badge.warn{background:#35270f}.badge.bad{background:#471c24}.progress{height:12px;background:#09131d;border:1px solid #2b4359;border-radius:999px;overflow:hidden}.progress>span{display:block;height:100%;background:linear-gradient(90deg,var(--cyan),var(--green))}.checklist{list-style:none;padding:0;margin:0}.checklist li{display:flex;gap:9px;padding:8px 0;border-bottom:1px solid #263a4d}.checklist li:last-child{border-bottom:0}.checkmark{width:22px;font-weight:900}.actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.actions form{margin:0}.actions button{width:auto}.form-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:8px}input,select,textarea,button{width:100%;padding:9px 10px;background:#142333;color:#fff;border:1px solid #46627e;border-radius:7px}textarea{min-height:96px;resize:vertical}button{font-weight:750;cursor:pointer}button:hover{filter:brightness(1.12)}button.secondary{background:#25364a;border-color:#5a7693}button.warn{background:#594116;border-color:#d9a743}button.danger{background:#5d2028;border-color:#dd6674}.timeline{display:grid;gap:8px}.event{display:grid;grid-template-columns:150px 105px 1fr;gap:10px;padding:11px;background:#101a25;border:1px solid #293e53;border-radius:9px}.event .kind{text-transform:uppercase;letter-spacing:.06em;font-size:.72rem;font-weight:900}.filters{display:flex;gap:8px;flex-wrap:wrap}.filters>*{width:auto;min-width:145px}.score{font-size:2.2rem;font-weight:900}.nowrap{white-space:nowrap}@media(max-width:800px){body{padding:10px}.panel{padding:11px}.two,.three{grid-template-columns:1fr}.event{grid-template-columns:1fr}.filters>*{width:100%}}
"""

_CLASSIFICATIONS = {
    "owner": "Owner",
    "customer": "Customer",
    "tester": "Tester",
    "complimentary": "Complimentary",
    "replacement": "Replacement",
}

_SUPPORT_STATUSES = {
    "normal": "Normal",
    "needs_attention": "Needs attention",
    "waiting_customer": "Waiting on customer",
    "resolved": "Resolved",
    "refunded": "Refunded",
}

_EVENT_TYPES = {
    "note": "Note",
    "contact": "Customer contact",
    "issue": "Issue reported",
    "resolution": "Resolution",
    "replacement": "Replacement",
    "refund": "Refund / payment",
}

_ROOT_ACTIONS = {
    "verified-backup": {"label": "Create verified backup", "confirm": ""},
    "restore-test": {"label": "Run backup restore test", "confirm": ""},
    "run-tests": {"label": "Run server test suite", "confirm": ""},
    "refresh-public-status": {"label": "Refresh public status", "confirm": ""},
    "restart-api": {"label": "Restart License API", "confirm": "RESTART API"},
    "restart-site": {"label": "Restart public website", "confirm": "RESTART SITE"},
    "restart-racelink-dashboard": {"label": "Restart RaceLink dashboard", "confirm": "RESTART RACELINK"},
}

_HEALTH_CACHE: dict[str, Any] = {"captured": 0.0, "value": None}


def _e(value: Any) -> str:
    return html.escape("" if value is None else str(value))


def _fmt_time(value: Any) -> str:
    try:
        stamp = int(value or 0)
    except (TypeError, ValueError):
        return "-"
    if stamp <= 0:
        return "-"
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(stamp))


def _age(value: Any) -> str:
    try:
        seconds = max(0, int(time.time() - float(value or 0)))
    except (TypeError, ValueError):
        return "unknown"
    if seconds < 120:
        return f"{seconds}s ago"
    if seconds < 7200:
        return f"{seconds // 60}m ago"
    if seconds < 172800:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def _short(value: Any, start: int = 8, end: int = 5) -> str:
    text = str(value or "")
    if len(text) <= start + end + 2:
        return text
    return f"{text[:start]}…{text[-end:]}"


def _connect(database_path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(database_path, timeout=30)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    return connection


def ensure_control_schema(database_path: Path) -> None:
    with _connect(database_path) as connection:
        connection.executescript(CONTROL_SCHEMA)
        connection.commit()


def _table_exists(connection: sqlite3.Connection, table: str) -> bool:
    return connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone() is not None


def _service_state(unit: str) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["systemctl", "is-active", unit],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)
    state = (result.stdout or result.stderr or "unknown").strip()
    return result.returncode == 0 and state == "active", state


def _http_status(url: str) -> dict[str, Any]:
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=3.0) as response:
            body = response.read(32768).decode("utf-8", errors="replace")
            elapsed = int((time.perf_counter() - started) * 1000)
            payload: Any = None
            try:
                payload = json.loads(body)
            except (ValueError, json.JSONDecodeError):
                payload = None
            return {
                "ok": 200 <= int(response.status) < 300,
                "status": int(response.status),
                "ms": elapsed,
                "detail": body[:500],
                "payload": payload,
            }
    except (OSError, urllib.error.URLError, ValueError) as exc:
        return {
            "ok": False,
            "status": 0,
            "ms": int((time.perf_counter() - started) * 1000),
            "detail": str(exc),
            "payload": None,
        }


def _latest_backup(database_path: Path) -> tuple[Path | None, int]:
    roots = [Path("/var/backups/drivelab-license"), database_path.parent / "owner-backups"]
    candidates: list[Path] = []
    for root in roots:
        try:
            if not root.exists():
                continue
            if root == Path("/var/backups/drivelab-license"):
                candidates.extend(root.glob("drivelab-backup-*.tar.gz"))
            else:
                candidates.extend(root.rglob("*.db"))
        except OSError:
            continue
    candidates = [path for path in candidates if path.is_file()]
    candidates.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    return (candidates[0], len(candidates)) if candidates else (None, 0)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, json.JSONDecodeError):
        return {}


def _restore_status(database_path: Path) -> dict[str, Any]:
    return _read_json(database_path.parent / "ops" / "last-restore-test.json")


def _test_status(database_path: Path) -> dict[str, Any]:
    direct = _read_json(database_path.parent / "ops" / "last-test-run.json")
    if direct:
        return direct
    results = database_path.parent / "ops" / "results"
    try:
        paths = sorted(results.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
    except OSError:
        paths = []
    for path in paths:
        item = _read_json(path)
        if item.get("action") == "run-tests":
            return item
    return {}


def _virus_total_status(release: dict[str, Any]) -> dict[str, Any]:
    version = str(release.get("version_name") or "").strip()
    security_root = Path("/opt/drivelab-site/static/security")
    candidates: list[Path] = []
    if version:
        candidates.append(security_root / f"DriveLab-Telem-v{version}-VirusTotal.json")
    try:
        candidates.extend(
            sorted(
                security_root.glob("*VirusTotal.json"),
                key=lambda path: path.stat().st_mtime,
                reverse=True,
            )
        )
    except OSError:
        pass
    seen: set[Path] = set()
    for path in candidates:
        if path in seen or not path.is_file():
            continue
        seen.add(path)
        raw = _read_json(path)
        data = raw.get("data") if isinstance(raw.get("data"), dict) else {}
        attributes = data.get("attributes") if isinstance(data.get("attributes"), dict) else {}
        stats = attributes.get("last_analysis_stats") if isinstance(attributes.get("last_analysis_stats"), dict) else {}
        sha256 = str(data.get("id") or attributes.get("sha256") or "").lower()
        malicious = int(stats.get("malicious", 0) or 0)
        suspicious = int(stats.get("suspicious", 0) or 0)
        total = sum(int(value or 0) for value in stats.values() if isinstance(value, (int, float)))
        expected = str(release.get("actual_sha256") or "").lower()
        return {
            "found": True,
            "path": str(path),
            "sha256": sha256,
            "matches_release": bool(expected and sha256 and expected == sha256),
            "malicious": malicious,
            "suspicious": suspicious,
            "total": total,
            "analysis_date": int(attributes.get("last_analysis_date", 0) or 0),
            "url": f"https://www.virustotal.com/gui/file/{sha256}" if sha256 else "",
        }
    return {"found": False, "matches_release": False, "malicious": 0, "suspicious": 0, "total": 0}


def _version_key(value: str) -> tuple[int, ...]:
    numbers = [int(item) for item in re.findall(r"\d+", str(value or ""))[:4]]
    return tuple(numbers or [0])


def _is_current_version(reported: str, current: str) -> bool:
    reported = str(reported or "").strip()
    current = str(current or "").strip()
    if not current:
        return False
    return reported == current or reported.startswith(current + " ") or reported.startswith(current + "(")


def _version_inventory(connection: sqlite3.Connection, current_version: str) -> dict[str, Any]:
    now = int(time.time())
    rows: list[sqlite3.Row] = []
    if _table_exists(connection, "device_presence"):
        rows = connection.execute(
            "SELECT CASE WHEN app_version='' THEN '(unknown)' ELSE app_version END version,"
            "COUNT(*) count,MIN(first_seen_at) first_seen,MAX(last_seen_at) last_seen,"
            "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_24h,"
            "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_7d,"
            "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_30d "
            "FROM device_presence GROUP BY app_version ORDER BY count DESC,version ASC",
            (now - 86400, now - 7 * 86400, now - 30 * 86400),
        ).fetchall()
        summary = connection.execute(
            "SELECT COUNT(*) total,"
            "SUM(CASE WHEN first_seen_at>=? THEN 1 ELSE 0 END) new_7d,"
            "SUM(CASE WHEN first_seen_at<? AND last_seen_at>=? THEN 1 ELSE 0 END) returning_7d,"
            "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_24h,"
            "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_7d,"
            "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_30d,"
            "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_90d "
            "FROM device_presence",
            (
                now - 7 * 86400,
                now - 7 * 86400,
                now - 7 * 86400,
                now - 86400,
                now - 7 * 86400,
                now - 30 * 86400,
                now - 90 * 86400,
            ),
        ).fetchone()
    else:
        rows = connection.execute(
            "SELECT CASE WHEN app_version='' THEN '(unknown)' ELSE app_version END version,"
            "COUNT(DISTINCT installation_id) count,MIN(created_at) first_seen,MAX(last_seen_at) last_seen,"
            "COUNT(DISTINCT CASE WHEN last_seen_at>=? THEN installation_id END) active_24h,"
            "COUNT(DISTINCT CASE WHEN last_seen_at>=? THEN installation_id END) active_7d,"
            "COUNT(DISTINCT CASE WHEN last_seen_at>=? THEN installation_id END) active_30d "
            "FROM activations GROUP BY app_version ORDER BY count DESC,version ASC",
            (now - 86400, now - 7 * 86400, now - 30 * 86400),
        ).fetchall()
        summary = connection.execute(
            "SELECT COUNT(DISTINCT installation_id) total,"
            "COUNT(DISTINCT CASE WHEN created_at>=? THEN installation_id END) new_7d,"
            "COUNT(DISTINCT CASE WHEN created_at<? AND last_seen_at>=? THEN installation_id END) returning_7d,"
            "COUNT(DISTINCT CASE WHEN last_seen_at>=? THEN installation_id END) active_24h,"
            "COUNT(DISTINCT CASE WHEN last_seen_at>=? THEN installation_id END) active_7d,"
            "COUNT(DISTINCT CASE WHEN last_seen_at>=? THEN installation_id END) active_30d,"
            "COUNT(DISTINCT CASE WHEN last_seen_at>=? THEN installation_id END) active_90d FROM activations",
            (
                now - 7 * 86400,
                now - 7 * 86400,
                now - 7 * 86400,
                now - 86400,
                now - 7 * 86400,
                now - 30 * 86400,
                now - 90 * 86400,
            ),
        ).fetchone()

    total = int(summary["total"] or 0)
    current_count = 0
    outdated = 0
    unknown = 0
    items: list[dict[str, Any]] = []
    current_key = _version_key(current_version)
    for row in rows:
        version = str(row["version"] or "(unknown)")
        count = int(row["count"] or 0)
        is_current = _is_current_version(version, current_version)
        is_unknown = version == "(unknown)" or _version_key(version) == (0,)
        is_outdated = bool(current_version and not is_current and not is_unknown and _version_key(version) < current_key)
        if is_current:
            current_count += count
        elif is_unknown:
            unknown += count
        elif is_outdated:
            outdated += count
        items.append(
            {
                "version": version,
                "count": count,
                "percent": round((count / total * 100.0), 1) if total else 0.0,
                "first_seen": int(row["first_seen"] or 0),
                "last_seen": int(row["last_seen"] or 0),
                "active_24h": int(row["active_24h"] or 0),
                "active_7d": int(row["active_7d"] or 0),
                "active_30d": int(row["active_30d"] or 0),
                "is_current": is_current,
                "is_outdated": is_outdated,
                "is_unknown": is_unknown,
            }
        )
    return {
        "total": total,
        "current": current_count,
        "current_percent": round((current_count / total * 100.0), 1) if total else 0.0,
        "outdated": outdated,
        "unknown": unknown,
        "new_7d": int(summary["new_7d"] or 0),
        "returning_7d": int(summary["returning_7d"] or 0),
        "active_24h": int(summary["active_24h"] or 0),
        "active_7d": int(summary["active_7d"] or 0),
        "active_30d": int(summary["active_30d"] or 0),
        "active_90d": int(summary["active_90d"] or 0),
        "versions": items,
    }


def _recent_root_results(database_path: Path, limit: int = 12) -> list[dict[str, Any]]:
    root = database_path.parent / "ops" / "results"
    try:
        paths = sorted(root.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)[:limit]
    except OSError:
        paths = []
    values: list[dict[str, Any]] = []
    for path in paths:
        item = _read_json(path)
        if item:
            item["result_file"] = path.name
            values.append(item)
    return values


def _record_health(database_path: Path, snapshot: dict[str, Any]) -> None:
    stamp = int(time.time())
    stamp -= stamp % 300
    try:
        with _connect(database_path) as connection:
            connection.execute(
                "INSERT OR REPLACE INTO owner_health_history("
                "captured_at,overall,critical_count,warning_count,api_ok,website_ok,racelink_ok,"
                "database_ok,backup_ok,release_ok,free_disk_bytes) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                (
                    stamp,
                    snapshot["overall"],
                    len(snapshot["critical"]),
                    len(snapshot["warnings"]),
                    int(snapshot["api"]["ok"]),
                    int(snapshot["website"]["ok"]),
                    int(snapshot["racelink"]["ok"]),
                    int(snapshot["database_ok"]),
                    int(snapshot["backup_ok"]),
                    int(snapshot["release_ok"]),
                    int(snapshot["disk"].free),
                ),
            )
            connection.commit()
    except sqlite3.Error:
        return


def _health_snapshot(settings: Any, db: Any, *, force: bool = False) -> dict[str, Any]:
    now_monotonic = time.monotonic()
    if not force and _HEALTH_CACHE["value"] is not None and now_monotonic - float(_HEALTH_CACHE["captured"]) < CACHE_SECONDS:
        return dict(_HEALTH_CACHE["value"])

    database_path = Path(settings.database_path)
    ensure_control_schema(database_path)
    quick_check = "missing"
    database_ok = False
    license_count = 0
    active_paid = 0
    over_limit = 0
    customer_attention = 0
    with db.connect() as connection:
        quick_check = str(connection.execute("PRAGMA quick_check").fetchone()[0])
        database_ok = quick_check.lower() == "ok"
        license_count = int(connection.execute("SELECT COUNT(*) FROM licenses").fetchone()[0] or 0)
        active_paid = int(
            connection.execute(
                "SELECT COUNT(*) FROM activations a JOIN licenses l ON l.id=a.license_id "
                "WHERE a.status='active' AND l.status='active'"
            ).fetchone()[0]
            or 0
        )
        over_limit = int(
            connection.execute(
                "SELECT COUNT(*) FROM licenses l WHERE (SELECT COUNT(*) FROM activations a "
                "WHERE a.license_id=l.id AND a.status='active')>l.device_limit"
            ).fetchone()[0]
            or 0
        )
        customer_attention = int(
            connection.execute(
                "SELECT COUNT(*) FROM owner_customer_meta WHERE support_status IN ('needs_attention','waiting_customer')"
            ).fetchone()[0]
            or 0
        )

    api = _http_status(f"http://127.0.0.1:{int(settings.api_port)}/v1/health")
    website = _http_status("http://127.0.0.1:8790/healthz")
    racelink = _http_status(f"http://127.0.0.1:{int(settings.api_port)}/v1/racelink/health")
    services = {
        unit: _service_state(unit)
        for unit in (
            "drivelab-license-admin.service",
            "drivelab-license-api.service",
            "drivelab-site.service",
            "drivelab-racelink-dashboard.service",
            "cloudflared.service",
            "drivelab-license-metrics.timer",
            "drivelab-admin-backup-v2.timer",
            "drivelab-admin-restore-test.timer",
            "drivelab-owner-ops.path",
        )
    }

    latest_backup, backup_count = _latest_backup(database_path)
    backup_age = time.time() - latest_backup.stat().st_mtime if latest_backup else 10**12
    backup_ok = latest_backup is not None and backup_age <= 36 * 3600
    restore = _restore_status(database_path)
    restore_ok = bool(restore.get("ok")) and int(time.time()) - int(restore.get("checked_at", 0) or 0) <= 14 * 86400
    tests = _test_status(database_path)
    tests_ok = bool(tests.get("ok")) and int(time.time()) - int(tests.get("finished_at", tests.get("checked_at", 0)) or 0) <= 7 * 86400
    disk = shutil.disk_usage(database_path.parent)
    release = current_release_status(settings)
    release_ok = bool(release.get("published") and release.get("verified"))
    vt = _virus_total_status(release)
    archives = list_archives(settings)
    current_archive = next(
        (item for item in archives if str(item.get("version_name")) == str(release.get("version_name"))),
        {},
    )
    archive_ok = bool(current_archive.get("verified"))
    with db.connect() as connection:
        versions = _version_inventory(connection, str(release.get("version_name") or ""))

    critical: list[str] = []
    warnings: list[str] = []
    if not database_ok:
        critical.append("Database integrity check is not OK.")
    if not api["ok"]:
        critical.append("License API health check failed.")
    if not Path(settings.private_key_path).is_file() or not Path(settings.public_key_path).is_file():
        critical.append("One or more licensing signing-key files are missing.")
    if disk.free < 512 * 1024 * 1024:
        critical.append("Less than 512 MiB of free storage remains.")
    elif disk.free < 2 * 1024 * 1024 * 1024:
        warnings.append("Less than 2 GiB of free storage remains.")
    if not release_ok:
        critical.append("The production APK and signed manifest are missing or do not agree.")
    if latest_backup is None:
        critical.append("No local backup was found.")
    elif not backup_ok:
        warnings.append("The newest local backup is older than 36 hours.")
    if not restore_ok:
        warnings.append("A successful backup restore test has not completed within 14 days.")
    if not website["ok"]:
        warnings.append("The public website health check failed.")
    if not racelink["ok"]:
        warnings.append("The RaceLink health check failed.")
    if not services["cloudflared.service"][0]:
        warnings.append("Cloudflare Tunnel is not active.")
    if not services["drivelab-owner-ops.path"][0]:
        warnings.append("The safe Owner Console operations worker is not active.")
    if release_ok and not archive_ok:
        warnings.append("The current production release is not in the verified private archive.")
    if release_ok and (not vt.get("found") or not vt.get("matches_release")):
        warnings.append("A matching VirusTotal receipt was not found for the production APK.")
    if int(vt.get("malicious", 0)) > 0 or int(vt.get("suspicious", 0)) > 0:
        critical.append("The current VirusTotal receipt contains malicious or suspicious detections.")
    if not tests_ok:
        warnings.append("The server test suite has not passed within the last 7 days.")
    if versions["outdated"] > 0:
        warnings.append(f"{versions['outdated']} installation(s) report an older version than production.")
    if over_limit > 0:
        warnings.append(f"{over_limit} license(s) are above their configured active-device limit.")
    if customer_attention > 0:
        warnings.append(f"{customer_attention} customer record(s) need support attention.")

    overall = "CRITICAL" if critical else "DEGRADED" if warnings else "HEALTHY"
    checklist = [
        (database_ok, "Database integrity is OK"),
        (api["ok"], "License API is online"),
        (website["ok"], "Public website is online"),
        (racelink["ok"], "RaceLink is online"),
        (release_ok, "Production APK matches its signed manifest"),
        (archive_ok, "Production release is archived and verified"),
        (bool(vt.get("found") and vt.get("matches_release") and not vt.get("malicious") and not vt.get("suspicious")), "VirusTotal receipt matches the production APK"),
        (backup_ok, "A local backup is newer than 36 hours"),
        (restore_ok, "A restore test passed within 14 days"),
        (tests_ok, "The server test suite passed within 7 days"),
        (disk.free >= 2 * 1024 * 1024 * 1024, "At least 2 GiB of free storage remains"),
        (Path(settings.private_key_path).is_file() and Path(settings.public_key_path).is_file(), "Both licensing signing keys are present"),
    ]
    snapshot = {
        "captured_at": int(time.time()),
        "overall": overall,
        "critical": critical,
        "warnings": warnings,
        "database_ok": database_ok,
        "quick_check": quick_check,
        "license_count": license_count,
        "active_paid": active_paid,
        "over_limit": over_limit,
        "customer_attention": customer_attention,
        "api": api,
        "website": website,
        "racelink": racelink,
        "services": services,
        "latest_backup": latest_backup,
        "backup_count": backup_count,
        "backup_ok": backup_ok,
        "restore": restore,
        "restore_ok": restore_ok,
        "tests": tests,
        "tests_ok": tests_ok,
        "disk": disk,
        "release": release,
        "release_ok": release_ok,
        "vt": vt,
        "archives": archives,
        "archive_ok": archive_ok,
        "versions": versions,
        "checklist": checklist,
        "root_results": _recent_root_results(database_path),
    }
    _record_health(database_path, snapshot)
    _HEALTH_CACHE["captured"] = now_monotonic
    _HEALTH_CACHE["value"] = dict(snapshot)
    return snapshot


def dashboard_alert_html(settings: Any, db: Any) -> str:
    try:
        snapshot = _health_snapshot(settings, db)
    except Exception as exc:
        return (
            "<div class='error'><strong>Control Center check failed:</strong> "
            f"{_e(exc)} <a href='/owner/control-center'>Open Control Center</a></div>"
        )
    status_class = {"HEALTHY": "notice", "DEGRADED": "warning", "CRITICAL": "error"}[snapshot["overall"]]
    messages = snapshot["critical"] + snapshot["warnings"]
    summary = "All monitored DriveLab systems are healthy."
    if messages:
        summary = " ".join(messages[:3])
        if len(messages) > 3:
            summary += f" Plus {len(messages) - 3} more alert(s)."
    return (
        f"<div class='{status_class}'><strong>Owner Control Center: {_e(snapshot['overall'])}</strong> — "
        f"{_e(summary)} <a href='/owner/control-center'>Open full status</a></div>"
    )


def _page(title: str, content: str) -> str:
    nav = (
        "<div class='topbar'><div><h1>DriveLab Owner Console</h1>"
        f"<div class='muted'>Control Center v{CONTROL_CENTER_VERSION} · licensing, releases, operations, customers, and recovery</div></div>"
        "<div class='nav'>"
        "<a href='/'>Dashboard</a>"
        "<a href='/owner/control-center'>Control Center</a>"
        "<a href='/owner/activity'>Activity</a>"
        "<a href='/owner/customers'>Customers</a>"
        "<a href='/owner/operations'>Operations</a>"
        "<a href='/owner/releases'>Releases</a>"
        "<a href='/owner/devices'>Devices</a>"
        "<a href='/owner/backups'>Backups</a>"
        "<a href='/logout'>Sign out</a>"
        "</div></div>"
    )
    return (
        "<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{_e(title)} - DriveLab Owner Console</title><style>{STYLE}</style></head>"
        f"<body>{nav}{content}</body></html>"
    )


def _finish(content: str, csrf: str, existing: str | None) -> HTMLResponse:
    response = HTMLResponse(content)
    if not existing:
        response.set_cookie("dlt_csrf", csrf, httponly=True, samesite="strict", max_age=8 * 60 * 60)
    return response


def _operation_record(database_path: Path, action: str, status: str, detail: str, duration_ms: int, request_id: str = "") -> None:
    with _connect(database_path) as connection:
        connection.execute(
            "INSERT INTO owner_operation_history(happened_at,action,status,detail,duration_ms,request_id) VALUES(?,?,?,?,?,?)",
            (int(time.time()), action[:80], status[:30], detail[:8000], max(0, int(duration_ms)), request_id[:80]),
        )
        connection.commit()


def _queue_root_action(database_path: Path, action: str, wait_seconds: float = 12.0) -> dict[str, Any]:
    if action not in _ROOT_ACTIONS:
        raise RuntimeError("The requested operation is not allowlisted.")
    root = database_path.parent / "ops"
    requests = root / "requests"
    results = root / "results"
    requests.mkdir(parents=True, exist_ok=True)
    results.mkdir(parents=True, exist_ok=True)
    request_id = uuid.uuid4().hex
    destination = requests / f"{request_id}.request"
    temporary = requests / f".{request_id}.tmp"
    payload = {"request_id": request_id, "action": action, "requested_at": int(time.time())}
    temporary.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(destination)
    result_path = results / f"{request_id}.json"
    deadline = time.monotonic() + wait_seconds
    while time.monotonic() < deadline:
        if result_path.is_file():
            result = _read_json(result_path)
            if result:
                return result
        time.sleep(0.2)
    return {
        "ok": True,
        "queued": True,
        "request_id": request_id,
        "action": action,
        "detail": "The operation was queued. Its result will appear in Recent operations.",
    }


def _create_customer_meta(connection: sqlite3.Connection, license_id: str, now: int) -> None:
    connection.execute(
        "INSERT OR IGNORE INTO owner_customer_meta(license_id,classification,tags,support_status,last_contact_at,replacement_for,created_at,updated_at) "
        "VALUES(?,'customer','','normal',0,'',?,?)",
        (license_id, now, now),
    )


def _activity_rows(database_path: Path, kind: str, query: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    with _connect(database_path) as connection:
        if kind in {"all", "admin"}:
            for row in connection.execute("SELECT * FROM audit_log ORDER BY happened_at DESC LIMIT 400").fetchall():
                events.append({
                    "time": int(row["happened_at"] or 0),
                    "kind": "admin",
                    "title": str(row["action"] or "Administrative event"),
                    "subject": _short(row["license_id"] or row["activation_id"]),
                    "detail": str(row["detail"] or ""),
                })
        if kind in {"all", "support"}:
            for row in connection.execute(
                "SELECT s.*,l.customer_name,l.customer_email FROM owner_support_events s "
                "LEFT JOIN licenses l ON l.id=s.license_id ORDER BY s.happened_at DESC LIMIT 400"
            ).fetchall():
                events.append({
                    "time": int(row["happened_at"] or 0),
                    "kind": "support",
                    "title": str(row["event_type"] or "Support note"),
                    "subject": str(row["customer_name"] or row["customer_email"] or _short(row["license_id"])),
                    "detail": str(row["note"] or ""),
                })
        if kind in {"all", "operations"}:
            for row in connection.execute("SELECT * FROM owner_operation_history ORDER BY happened_at DESC LIMIT 400").fetchall():
                events.append({
                    "time": int(row["happened_at"] or 0),
                    "kind": "operations",
                    "title": f"{row['action']} · {row['status']}",
                    "subject": _short(row["request_id"]),
                    "detail": str(row["detail"] or ""),
                })
        if kind in {"all", "install"}:
            if _table_exists(connection, "device_presence"):
                for row in connection.execute(
                    "SELECT installation_id,edition,app_version,first_seen_at,last_seen_at FROM device_presence "
                    "ORDER BY first_seen_at DESC LIMIT 300"
                ).fetchall():
                    events.append({
                        "time": int(row["first_seen_at"] or 0),
                        "kind": "install",
                        "title": "Installation first seen",
                        "subject": _short(row["installation_id"]),
                        "detail": f"{str(row['edition'] or 'free').upper()} · version {row['app_version'] or '(unknown)'} · last seen {_fmt_time(row['last_seen_at'])}",
                    })
        if kind in {"all", "racelink"} and _table_exists(connection, "racelink_dashboard_events"):
            for row in connection.execute(
                "SELECT * FROM racelink_dashboard_events ORDER BY happened_at DESC,id DESC LIMIT 400"
            ).fetchall():
                events.append({
                    "time": int(row["happened_at"] or 0),
                    "kind": "racelink",
                    "title": str(row["event_type"] or "RaceLink event"),
                    "subject": str(row["actor_name"] or row["room_code"] or _short(row["activation_id"])),
                    "detail": str(row["detail"] or ""),
                })
    if kind in {"all", "operations"}:
        for row in _recent_root_results(database_path, 100):
            events.append({
                "time": int(row.get("finished_at") or row.get("started_at") or 0),
                "kind": "operations",
                "title": f"{row.get('action', 'root operation')} · {'passed' if row.get('ok') else 'failed'}",
                "subject": _short(row.get("request_id")),
                "detail": str(row.get("detail") or row.get("stderr") or row.get("stdout") or ""),
            })
    search = query.strip().lower()
    if search:
        events = [
            row for row in events
            if search in " ".join(str(row.get(key) or "") for key in ("kind", "title", "subject", "detail")).lower()
        ]
    events.sort(key=lambda row: int(row.get("time") or 0), reverse=True)
    return events[:700]


def install_owner_control_center(
    app: Any,
    settings: Any,
    db: Any,
    authenticated: Any,
    require_auth: Any,
    require_csrf: Any,
) -> None:
    database_path = Path(settings.database_path)
    ensure_control_schema(database_path)

    @app.get("/owner/control-center", response_class=HTMLResponse)
    def control_center(
        notice: str = Query(default=""),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            return RedirectResponse(url="/login", status_code=303)
        csrf = dlt_csrf or __import__("secrets").token_urlsafe(32)
        snapshot = _health_snapshot(settings, db, force=True)
        status_class = {"HEALTHY": "ok", "DEGRADED": "warn", "CRITICAL": "bad"}[snapshot["overall"]]
        release = snapshot["release"]
        versions = snapshot["versions"]
        vt = snapshot["vt"]
        disk = snapshot["disk"]
        latest_backup = snapshot["latest_backup"]
        completed = sum(1 for ok, _label in snapshot["checklist"] if ok)
        total_checks = len(snapshot["checklist"])
        score = round(completed / total_checks * 100) if total_checks else 0

        body: list[str] = []
        if notice:
            body.append(f"<div class='notice'>{_e(notice)}</div>")
        body.append(
            f"<div class='panel'><h2>System status: <span class='{status_class}'>{_e(snapshot['overall'])}</span></h2>"
            f"<p class='muted'>Checked {_e(_fmt_time(snapshot['captured_at']))}. This page reads the live services, database, backups, release files, version reports, and security receipt.</p>"
        )
        for message in snapshot["critical"]:
            body.append(f"<div class='error'>{_e(message)}</div>")
        for message in snapshot["warnings"]:
            body.append(f"<div class='warning'>{_e(message)}</div>")
        if not snapshot["critical"] and not snapshot["warnings"]:
            body.append("<div class='notice'>All monitored DriveLab systems are healthy.</div>")
        body.append("</div>")

        cards = [
            (snapshot["license_count"], "licenses"),
            (snapshot["active_paid"], "active paid devices"),
            (versions["total"], "known installations"),
            (versions["active_24h"], "active in 24 hours"),
            (versions["new_7d"], "new in 7 days"),
            (versions["returning_7d"], "returning in 7 days"),
            (f"{versions['current_percent']:.1f}%", "on production version"),
            (versions["outdated"], "outdated installations"),
            (snapshot["over_limit"], "licenses over limit"),
            (snapshot["customer_attention"], "support records needing attention"),
            (snapshot["backup_count"], "local backups"),
            (f"{disk.free / 1024 / 1024 / 1024:.1f} GiB", "free storage"),
        ]
        body.append("<div class='grid'>")
        for value, label in cards:
            body.append(f"<div class='card'><strong>{_e(value)}</strong><span>{_e(label)}</span></div>")
        body.append("</div>")

        body.append("<div class='two'>")
        body.append("<div class='panel'><h2>Service health</h2>")
        health_items = [
            ("License API", snapshot["api"]["ok"], f"{snapshot['api']['ms']} ms"),
            ("Public website", snapshot["website"]["ok"], f"{snapshot['website']['ms']} ms"),
            ("RaceLink API", snapshot["racelink"]["ok"], f"{snapshot['racelink']['ms']} ms"),
            ("Database", snapshot["database_ok"], snapshot["quick_check"]),
            ("Cloudflare Tunnel", snapshot["services"]["cloudflared.service"][0], snapshot["services"]["cloudflared.service"][1]),
            ("Owner operations worker", snapshot["services"]["drivelab-owner-ops.path"][0], snapshot["services"]["drivelab-owner-ops.path"][1]),
        ]
        for label, ok, detail in health_items:
            body.append(
                f"<div class='health-row'><span>{_e(label)}</span><span class='{'ok' if ok else 'bad'}'>{'ONLINE' if ok else 'FAILED'} · {_e(detail)}</span></div>"
            )
        body.append("</div>")

        body.append("<div class='panel'><h2>Recovery readiness</h2>")
        body.append(f"<div class='score'>{score}%</div><div class='progress'><span style='width:{score}%'></span></div>")
        body.append("<ul class='checklist'>")
        for ok, label in snapshot["checklist"]:
            body.append(
                f"<li><span class='checkmark {'ok' if ok else 'bad'}'>{'✓' if ok else '!'}</span><span>{_e(label)}</span></li>"
            )
        body.append("</ul>")
        if latest_backup:
            body.append(f"<p class='small muted'>Newest backup: {_e(latest_backup.name)} · {_e(_age(latest_backup.stat().st_mtime))}</p>")
        body.append("</div></div>")

        body.append("<div class='two'>")
        body.append("<div class='panel'><h2>Production release</h2>")
        if release.get("published"):
            body.append(
                f"<p>Version: <strong>{_e(release.get('version_name'))}</strong> (build {_e(release.get('version_code'))})</p>"
                f"<p>APK: <code>{_e(release.get('apk_filename'))}</code></p>"
                f"<p>Manifest integrity: <strong class='{'ok' if snapshot['release_ok'] else 'bad'}'>{'VERIFIED' if snapshot['release_ok'] else 'FAILED'}</strong></p>"
                f"<p>Private archive: <strong class='{'ok' if snapshot['archive_ok'] else 'warn'}'>{'VERIFIED' if snapshot['archive_ok'] else 'MISSING'}</strong></p>"
                f"<p class='mono small'>SHA-256: {_e(release.get('actual_sha256'))}</p>"
            )
        else:
            body.append("<p class='bad'>No production release is published.</p>")
        body.append("<p><a href='/owner/releases'>Open release management</a></p></div>")

        body.append("<div class='panel'><h2>APK security receipt</h2>")
        if vt.get("found"):
            detection_class = "ok" if not vt.get("malicious") and not vt.get("suspicious") and vt.get("matches_release") else "bad"
            body.append(
                f"<p>Production hash match: <strong class='{'ok' if vt.get('matches_release') else 'bad'}'>{'YES' if vt.get('matches_release') else 'NO'}</strong></p>"
                f"<p>Analysis: <strong class='{detection_class}'>{int(vt.get('malicious', 0))} malicious · {int(vt.get('suspicious', 0))} suspicious · {int(vt.get('total', 0))} engines</strong></p>"
                f"<p>Scanned: {_e(_fmt_time(vt.get('analysis_date')))}</p>"
            )
            if vt.get("url"):
                body.append(f"<p><a href='{_e(vt['url'])}' rel='noopener noreferrer'>Open VirusTotal report</a></p>")
        else:
            body.append("<p class='warn'>No VirusTotal JSON receipt was found for the production version.</p>")
        body.append("</div></div>")

        body.append("<div class='panel'><h2>Version adoption</h2><div class='table-wrap'><table><thead><tr><th>Version</th><th>Installations</th><th>Share</th><th>Active 24h</th><th>Active 7d</th><th>First seen</th><th>Last seen</th><th>Status</th></tr></thead><tbody>")
        for item in versions["versions"]:
            state = "CURRENT" if item["is_current"] else "OUTDATED" if item["is_outdated"] else "UNKNOWN" if item["is_unknown"] else "NEWER"
            state_class = "ok" if state == "CURRENT" else "warn" if state in {"OUTDATED", "UNKNOWN"} else "info"
            body.append(
                f"<tr><td><strong>{_e(item['version'])}</strong></td><td>{item['count']}</td><td>{item['percent']:.1f}%</td>"
                f"<td>{item['active_24h']}</td><td>{item['active_7d']}</td><td>{_e(_fmt_time(item['first_seen']))}</td>"
                f"<td>{_e(_fmt_time(item['last_seen']))}</td><td class='{state_class}'>{state}</td></tr>"
            )
        if not versions["versions"]:
            body.append("<tr><td colspan='8' class='muted'>No version reports exist yet.</td></tr>")
        body.append("</tbody></table></div></div>")

        body.append("<div class='panel'><h2>Safe operations</h2><p class='muted'>Actions are written to an allowlisted request queue and executed by a separate root worker. The Owner Console keeps NoNewPrivileges enabled.</p><div class='actions'>")
        body.append(
            "<form method='post' action='/owner/control-center/action'>"
            f"<input type='hidden' name='csrf_token' value='{_e(csrf)}'><input type='hidden' name='action' value='health'>"
            "<button class='secondary'>Run health check</button></form>"
        )
        body.append(
            "<form method='post' action='/owner/control-center/action'>"
            f"<input type='hidden' name='csrf_token' value='{_e(csrf)}'><input type='hidden' name='action' value='record-metrics'>"
            "<button class='secondary'>Record metric snapshot</button></form>"
        )
        for action, config in _ROOT_ACTIONS.items():
            confirm = str(config["confirm"])
            onsubmit = ""
            if confirm:
                prompt = json.dumps(f"Type {confirm} to continue.")
                expected = json.dumps(confirm)
                onsubmit = f" onsubmit=\"const v=prompt({html.escape(prompt, quote=True)});if(v!=={html.escape(expected, quote=True)})return false;this.elements.confirmation.value=v;return true;\""
            button_class = "danger" if action.startswith("restart-") else "secondary"
            body.append(
                f"<form method='post' action='/owner/control-center/action'{onsubmit}>"
                f"<input type='hidden' name='csrf_token' value='{_e(csrf)}'><input type='hidden' name='action' value='{_e(action)}'>"
                f"<input type='hidden' name='confirmation' value=''><button class='{button_class}'>{_e(config['label'])}</button></form>"
            )
        body.append("</div></div>")

        body.append("<div class='panel'><h2>Recent operations</h2><div class='table-wrap'><table><thead><tr><th>Time</th><th>Action</th><th>Result</th><th>Duration</th><th>Detail</th></tr></thead><tbody>")
        for result in snapshot["root_results"]:
            ok = bool(result.get("ok"))
            body.append(
                f"<tr><td>{_e(_fmt_time(result.get('finished_at') or result.get('started_at')))}</td>"
                f"<td>{_e(result.get('action'))}</td><td class='{'ok' if ok else 'bad'}'>{'PASSED' if ok else 'FAILED'}</td>"
                f"<td>{int(result.get('duration_ms', 0) or 0)} ms</td><td class='small'>{_e(result.get('detail') or result.get('stderr') or result.get('stdout'))}</td></tr>"
            )
        if not snapshot["root_results"]:
            body.append("<tr><td colspan='5' class='muted'>No queued-operation results yet.</td></tr>")
        body.append("</tbody></table></div></div>")
        return _finish(_page("Control Center", "".join(body)), csrf, dlt_csrf)

    @app.post("/owner/control-center/action")
    def control_center_action(
        action: str = Form(...),
        confirmation: str = Form(default=""),
        csrf_token: str = Form(...),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        require_auth(dlt_admin, authorization)
        require_csrf(csrf_token, dlt_csrf)
        started = time.perf_counter()
        status = "passed"
        detail = ""
        request_id = ""
        try:
            if action == "health":
                _HEALTH_CACHE["value"] = None
                snapshot = _health_snapshot(settings, db, force=True)
                detail = f"Health check completed with status {snapshot['overall']}."
            elif action == "record-metrics":
                created = record_metrics_snapshot(database_path, database_path.parent / "updates", force=True)
                detail = "Metric snapshot recorded." if created else "Metric snapshot was already current."
            elif action in _ROOT_ACTIONS:
                expected = str(_ROOT_ACTIONS[action]["confirm"])
                if expected and confirmation != expected:
                    raise HTTPException(status_code=400, detail=f"Type {expected} exactly to run this operation.")
                result = _queue_root_action(database_path, action, wait_seconds=18.0 if action != "run-tests" else 2.0)
                request_id = str(result.get("request_id") or "")
                if not result.get("ok"):
                    raise RuntimeError(str(result.get("detail") or result.get("stderr") or "Operation failed."))
                detail = str(result.get("detail") or ("Operation queued." if result.get("queued") else "Operation completed."))
            else:
                raise HTTPException(status_code=400, detail="Unknown Owner Console action.")
        except HTTPException:
            raise
        except Exception as exc:
            status = "failed"
            detail = str(exc)
        duration = int((time.perf_counter() - started) * 1000)
        _operation_record(database_path, action, status, detail, duration, request_id)
        with db.connect() as connection:
            Database.audit(
                connection,
                int(time.time()),
                "owner_control_action",
                detail=json.dumps(
                    {"action": action, "status": status, "detail": detail[:1000], "request_id": request_id},
                    separators=(",", ":"),
                ),
            )
        _HEALTH_CACHE["value"] = None
        return RedirectResponse(url=f"/owner/control-center?notice={quote(detail)}", status_code=303)

    @app.get("/owner/customers", response_class=HTMLResponse)
    def customers_page(
        q: str = Query(default=""),
        status: str = Query(default="all"),
        classification: str = Query(default="all"),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            return RedirectResponse(url="/login", status_code=303)
        csrf = dlt_csrf or __import__("secrets").token_urlsafe(32)
        now = int(time.time())
        with _connect(database_path) as connection:
            for row in connection.execute("SELECT id FROM licenses").fetchall():
                _create_customer_meta(connection, str(row["id"]), now)
            connection.commit()
            rows = connection.execute(
                "SELECT l.*,m.classification,m.tags,m.support_status,m.last_contact_at,m.replacement_for,"
                "(SELECT COUNT(*) FROM activations a WHERE a.license_id=l.id AND a.status='active') active_devices,"
                "(SELECT MAX(last_seen_at) FROM activations a WHERE a.license_id=l.id) last_seen "
                "FROM licenses l LEFT JOIN owner_customer_meta m ON m.license_id=l.id ORDER BY l.created_at DESC"
            ).fetchall()
        query = q.strip().lower()
        filtered: list[sqlite3.Row] = []
        for row in rows:
            row_status = str(row["support_status"] or "normal")
            row_class = str(row["classification"] or "customer")
            searchable = " ".join(
                str(row[key] or "")
                for key in ("id", "customer_name", "customer_email", "order_number", "marketplace", "tags", "support_status", "classification", "support_notes")
            ).lower()
            if status != "all" and row_status != status:
                continue
            if classification != "all" and row_class != classification:
                continue
            if query and query not in searchable:
                continue
            filtered.append(row)
        body = [
            "<div class='panel'><h2>Customer and support records</h2><p class='muted'>Classify customers, track support state, add tags, record contact, and connect replacement licenses without changing activation behavior.</p>",
            "<form method='get' class='filters'>",
            f"<input name='q' value='{_e(q)}' placeholder='Search customer, email, order, tag, or license'>",
            "<select name='status'><option value='all'>All support states</option>",
        ]
        for value, label in _SUPPORT_STATUSES.items():
            body.append(f"<option value='{_e(value)}' {'selected' if status == value else ''}>{_e(label)}</option>")
        body.append("</select><select name='classification'><option value='all'>All classifications</option>")
        for value, label in _CLASSIFICATIONS.items():
            body.append(f"<option value='{_e(value)}' {'selected' if classification == value else ''}>{_e(label)}</option>")
        body.append("</select><button class='secondary'>Apply filters</button></form></div>")
        counts = {
            "total": len(rows),
            "attention": sum(1 for row in rows if str(row["support_status"] or "") == "needs_attention"),
            "waiting": sum(1 for row in rows if str(row["support_status"] or "") == "waiting_customer"),
            "testers": sum(1 for row in rows if str(row["classification"] or "") == "tester"),
            "complimentary": sum(1 for row in rows if str(row["classification"] or "") == "complimentary"),
        }
        body.append("<div class='grid'>")
        for value, label in ((counts["total"], "customer records"), (counts["attention"], "need attention"), (counts["waiting"], "waiting on customer"), (counts["testers"], "testers"), (counts["complimentary"], "complimentary")):
            body.append(f"<div class='card'><strong>{value}</strong><span>{_e(label)}</span></div>")
        body.append("</div>")
        body.append("<div class='panel'><div class='table-wrap'><table><thead><tr><th>Customer</th><th>Classification</th><th>Support</th><th>Tags</th><th>Order</th><th>Devices</th><th>Last contact</th><th>Last seen</th><th>Actions</th></tr></thead><tbody>")
        for row in filtered:
            customer = str(row["customer_name"] or row["customer_email"] or row["id"])
            support = str(row["support_status"] or "normal")
            support_class = "bad" if support == "needs_attention" else "warn" if support == "waiting_customer" else "ok" if support == "resolved" else ""
            body.append(
                f"<tr><td><strong>{_e(customer)}</strong><div class='small muted'>{_e(row['customer_email'])}</div><code>{_e(_short(row['id']))}</code></td>"
                f"<td>{_e(_CLASSIFICATIONS.get(str(row['classification'] or 'customer'), str(row['classification'])))}</td>"
                f"<td class='{support_class}'>{_e(_SUPPORT_STATUSES.get(support, support))}</td><td>{_e(row['tags'])}</td>"
                f"<td>{_e(row['order_number'] or '-')}<div class='small muted'>{_e(row['marketplace'])}</div></td>"
                f"<td>{int(row['active_devices'] or 0)}/{int(row['device_limit'] or 0)}</td><td>{_e(_fmt_time(row['last_contact_at']))}</td>"
                f"<td>{_e(_fmt_time(row['last_seen']))}</td><td><a href='/owner/customers/{quote(str(row['id']))}'>Support record</a> · <a href='/owner/licenses/{quote(str(row['id']))}'>License</a></td></tr>"
            )
        if not filtered:
            body.append("<tr><td colspan='9' class='muted'>No customer records match the filters.</td></tr>")
        body.append("</tbody></table></div></div>")
        return _finish(_page("Customers", "".join(body)), csrf, dlt_csrf)

    @app.get("/owner/customers/{license_id}", response_class=HTMLResponse)
    def customer_detail(
        license_id: str,
        notice: str = Query(default=""),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            return RedirectResponse(url="/login", status_code=303)
        csrf = dlt_csrf or __import__("secrets").token_urlsafe(32)
        now = int(time.time())
        with _connect(database_path) as connection:
            license_row = connection.execute("SELECT * FROM licenses WHERE id=?", (license_id,)).fetchone()
            if license_row is None:
                raise HTTPException(status_code=404, detail="License not found")
            _create_customer_meta(connection, license_id, now)
            connection.commit()
            meta = connection.execute("SELECT * FROM owner_customer_meta WHERE license_id=?", (license_id,)).fetchone()
            events = connection.execute(
                "SELECT * FROM owner_support_events WHERE license_id=? ORDER BY happened_at DESC,id DESC LIMIT 300",
                (license_id,),
            ).fetchall()
        customer = str(license_row["customer_name"] or license_row["customer_email"] or license_id)
        body: list[str] = []
        if notice:
            body.append(f"<div class='notice'>{_e(notice)}</div>")
        body.append(
            f"<div class='panel'><h2>{_e(customer)}</h2><p><code>{_e(license_id)}</code> · <a href='/owner/licenses/{quote(license_id)}'>Open license controls</a></p></div>"
        )
        body.append(
            "<div class='two'><div class='panel'><h2>Support profile</h2>"
            f"<form method='post' action='/owner/customers/{quote(license_id)}/meta'><input type='hidden' name='csrf_token' value='{_e(csrf)}'><div class='form-grid'>"
            "<select name='classification'>"
        )
        for value, label in _CLASSIFICATIONS.items():
            body.append(f"<option value='{_e(value)}' {'selected' if str(meta['classification']) == value else ''}>{_e(label)}</option>")
        body.append("</select><select name='support_status'>")
        for value, label in _SUPPORT_STATUSES.items():
            body.append(f"<option value='{_e(value)}' {'selected' if str(meta['support_status']) == value else ''}>{_e(label)}</option>")
        body.append(
            f"</select><input name='tags' value='{_e(meta['tags'])}' placeholder='Tags, comma separated'>"
            f"<input name='last_contact' type='date' value='{_e(time.strftime('%Y-%m-%d', time.localtime(int(meta['last_contact_at']))) if int(meta['last_contact_at'] or 0) > 0 else '')}'>"
            f"<input name='replacement_for' value='{_e(meta['replacement_for'])}' placeholder='Original/replaced license ID'></div>"
            "<button>Save support profile</button></form></div>"
            "<div class='panel'><h2>Add support event</h2>"
            f"<form method='post' action='/owner/customers/{quote(license_id)}/event'><input type='hidden' name='csrf_token' value='{_e(csrf)}'>"
            "<select name='event_type'>"
        )
        for value, label in _EVENT_TYPES.items():
            body.append(f"<option value='{_e(value)}'>{_e(label)}</option>")
        body.append("</select><textarea name='note' placeholder='What happened, what was changed, or what needs follow-up' required></textarea><button>Add support event</button></form></div></div>")
        body.append("<div class='panel'><h2>Support timeline</h2><div class='timeline'>")
        for event in events:
            body.append(
                f"<div class='event'><div>{_e(_fmt_time(event['happened_at']))}</div><div class='kind info'>{_e(event['event_type'])}</div><div>{_e(event['note'])}</div></div>"
            )
        if not events:
            body.append("<p class='muted'>No support events have been recorded.</p>")
        body.append("</div></div>")
        return _finish(_page("Customer support record", "".join(body)), csrf, dlt_csrf)

    @app.post("/owner/customers/{license_id}/meta")
    def customer_meta_save(
        license_id: str,
        classification: str = Form(default="customer"),
        support_status: str = Form(default="normal"),
        tags: str = Form(default=""),
        last_contact: str = Form(default=""),
        replacement_for: str = Form(default=""),
        csrf_token: str = Form(...),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        require_auth(dlt_admin, authorization)
        require_csrf(csrf_token, dlt_csrf)
        if classification not in _CLASSIFICATIONS or support_status not in _SUPPORT_STATUSES:
            raise HTTPException(status_code=400, detail="Invalid customer classification or support status.")
        last_contact_at = 0
        if last_contact.strip():
            try:
                last_contact_at = int(time.mktime(time.strptime(last_contact.strip(), "%Y-%m-%d")))
            except ValueError as exc:
                raise HTTPException(status_code=400, detail="Last contact date must use YYYY-MM-DD.") from exc
        now = int(time.time())
        with _connect(database_path) as connection:
            exists = connection.execute("SELECT id FROM licenses WHERE id=?", (license_id,)).fetchone()
            if exists is None:
                raise HTTPException(status_code=404, detail="License not found")
            _create_customer_meta(connection, license_id, now)
            connection.execute(
                "UPDATE owner_customer_meta SET classification=?,tags=?,support_status=?,last_contact_at=?,replacement_for=?,updated_at=? WHERE license_id=?",
                (classification, tags[:500], support_status, last_contact_at, replacement_for[:80], now, license_id),
            )
            connection.commit()
        with db.connect() as connection:
            Database.audit(connection, now, "edit_customer_meta", license_id, detail=f"{classification}:{support_status}")
        _HEALTH_CACHE["value"] = None
        return RedirectResponse(url=f"/owner/customers/{quote(license_id)}?notice=Support profile saved", status_code=303)

    @app.post("/owner/customers/{license_id}/event")
    def customer_event_add(
        license_id: str,
        event_type: str = Form(default="note"),
        note: str = Form(...),
        csrf_token: str = Form(...),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        require_auth(dlt_admin, authorization)
        require_csrf(csrf_token, dlt_csrf)
        if event_type not in _EVENT_TYPES:
            raise HTTPException(status_code=400, detail="Invalid support event type.")
        clean_note = note.strip()
        if not clean_note:
            raise HTTPException(status_code=400, detail="A support note is required.")
        now = int(time.time())
        with _connect(database_path) as connection:
            exists = connection.execute("SELECT id FROM licenses WHERE id=?", (license_id,)).fetchone()
            if exists is None:
                raise HTTPException(status_code=404, detail="License not found")
            _create_customer_meta(connection, license_id, now)
            connection.execute(
                "INSERT INTO owner_support_events(happened_at,license_id,event_type,note) VALUES(?,?,?,?)",
                (now, license_id, event_type, clean_note[:8000]),
            )
            if event_type == "contact":
                connection.execute("UPDATE owner_customer_meta SET last_contact_at=?,updated_at=? WHERE license_id=?", (now, now, license_id))
            connection.commit()
        with db.connect() as connection:
            Database.audit(connection, now, "add_support_event", license_id, detail=event_type)
        return RedirectResponse(url=f"/owner/customers/{quote(license_id)}?notice=Support event added", status_code=303)

    @app.get("/owner/activity", response_class=HTMLResponse)
    def activity_page(
        kind: str = Query(default="all"),
        q: str = Query(default=""),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            return RedirectResponse(url="/login", status_code=303)
        csrf = dlt_csrf or __import__("secrets").token_urlsafe(32)
        allowed_kinds = {"all", "admin", "support", "operations", "install", "racelink"}
        selected = kind if kind in allowed_kinds else "all"
        events = _activity_rows(database_path, selected, q)
        body = [
            "<div class='panel'><h2>Unified activity timeline</h2><p class='muted'>Administrative activity, customer support, first-seen installations, safe operations, and RaceLink operational events in one place.</p>",
            "<form method='get' class='filters'>",
            f"<input name='q' value='{_e(q)}' placeholder='Search events'>",
            "<select name='kind'>",
        ]
        for value, label in (("all", "All activity"), ("admin", "Administration"), ("support", "Support"), ("operations", "Operations"), ("install", "Installations"), ("racelink", "RaceLink")):
            body.append(f"<option value='{value}' {'selected' if selected == value else ''}>{label}</option>")
        body.append("</select><button class='secondary'>Apply filters</button></form></div>")
        body.append(f"<div class='panel'><h2>{len(events)} event(s)</h2><div class='timeline'>")
        for event in events:
            kind_class = "bad" if "fail" in str(event["title"]).lower() else "warn" if event["kind"] in {"support", "operations"} else "info"
            body.append(
                f"<div class='event'><div class='nowrap'>{_e(_fmt_time(event['time']))}</div><div class='kind {kind_class}'>{_e(event['kind'])}</div>"
                f"<div><strong>{_e(event['title'])}</strong> <span class='muted'>{_e(event['subject'])}</span><div class='small'>{_e(event['detail'])}</div></div></div>"
            )
        if not events:
            body.append("<p class='muted'>No events match the current filters.</p>")
        body.append("</div></div>")
        return _finish(_page("Activity", "".join(body)), csrf, dlt_csrf)

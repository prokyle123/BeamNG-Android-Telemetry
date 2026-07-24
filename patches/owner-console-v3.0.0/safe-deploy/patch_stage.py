#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import shutil
from pathlib import Path

MARKER = "DriveLab Owner Control Center v3.0.0"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact anchor, found {count}")
    return text.replace(old, new, 1)


def patch(stage_root: Path, payload: Path) -> None:
    package = stage_root / "drivelab_license"
    admin_app_path = package / "admin_app.py"
    owner_path = package / "owner_console.py"
    ops_path = package / "admin_ops.py"
    destination = package / "owner_control_center.py"

    for required in (admin_app_path, owner_path, ops_path, payload):
        if not required.is_file():
            raise RuntimeError(f"Required file is missing: {required}")

    admin_app = read(admin_app_path)
    owner = read(owner_path)
    ops = read(ops_path)

    if MARKER in admin_app:
        raise RuntimeError("The staged source already contains Owner Console v3")
    if "# DriveLab Owner Console v2" not in admin_app:
        raise RuntimeError("The expected Owner Console v2 marker is missing")
    if "DL_ADMIN_METRICS_V1" not in owner:
        raise RuntimeError("The expected History & Trends marker is missing")
    if 'ADMIN_OPS_VERSION = "1.0.4"' not in ops:
        raise RuntimeError("The expected admin operations v1.0.4 marker is missing")

    install_anchor = '''install_admin_ops(
    app,
    settings,
    db,
    authenticated,
    require_auth,
    require_csrf,
)
'''
    install_block = install_anchor + '''

# DriveLab Owner Control Center v3.0.0
from .owner_control_center import install_owner_control_center

install_owner_control_center(
    app,
    settings,
    db,
    authenticated,
    require_auth,
    require_csrf,
)
'''
    admin_app = replace_once(
        admin_app,
        install_anchor,
        install_block,
        "admin_app module registration",
    )

    metrics_import = '''from .admin_metrics import (
    METRICS_STYLE,
    ensure_metrics_schema,
    load_metrics_dashboard,
    record_metrics_snapshot,
    render_metrics_dashboard,
)
'''
    owner = replace_once(
        owner,
        metrics_import,
        metrics_import + "from .owner_control_center import dashboard_alert_html\n",
        "owner_console Control Center import",
    )

    owner_nav = '''            "<a href='/'>Dashboard</a>"
            "<a href='/owner/operations'>Operations</a>"
'''
    owner_nav_new = '''            "<a href='/'>Dashboard</a>"
            "<a href='/owner/control-center'>Control Center</a>"
            "<a href='/owner/activity'>Activity</a>"
            "<a href='/owner/customers'>Customers</a>"
            "<a href='/owner/operations'>Operations</a>"
'''
    owner = replace_once(owner, owner_nav, owner_nav_new, "owner_console navigation")
    owner = replace_once(
        owner,
        "        content = [notice_html(notice)]\n",
        "        content = [notice_html(notice)]\n        content.append(dashboard_alert_html(settings, db))\n",
        "owner_console dashboard alert",
    )

    ops_nav = '''        "<a href='/'>Dashboard</a>"
        "<a href='/owner/operations'>Operations</a>"
'''
    ops_nav_new = '''        "<a href='/'>Dashboard</a>"
        "<a href='/owner/control-center'>Control Center</a>"
        "<a href='/owner/activity'>Activity</a>"
        "<a href='/owner/customers'>Customers</a>"
        "<a href='/owner/operations'>Operations</a>"
'''
    ops = replace_once(ops, ops_nav, ops_nav_new, "admin_ops navigation")

    shutil.copy2(payload, destination)
    write(admin_app_path, admin_app)
    write(owner_path, owner)
    write(ops_path, ops)

    for path in (admin_app_path, owner_path, ops_path, destination):
        ast.parse(read(path), filename=str(path))

    checks = {
        admin_app_path: (MARKER, "install_owner_control_center("),
        owner_path: ("dashboard_alert_html", "/owner/control-center", "/owner/activity", "/owner/customers"),
        ops_path: ("/owner/control-center", "/owner/activity", "/owner/customers"),
        destination: ("CONTROL_CENTER_VERSION = \"3.0.0\"", "install_owner_control_center("),
    }
    for path, markers in checks.items():
        text = read(path)
        for marker in markers:
            if marker not in text:
                raise RuntimeError(f"Validation marker missing from {path.name}: {marker}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("stage_root", type=Path)
    parser.add_argument("payload", type=Path)
    args = parser.parse_args()
    patch(args.stage_root.resolve(), args.payload.resolve())
    print("Stage patch completed and parsed successfully.")

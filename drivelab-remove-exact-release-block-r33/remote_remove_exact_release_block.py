#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import stat
import sys
import time
from pathlib import Path

HOMEPAGE = Path("/opt/drivelab-site/public/index.html")
START_MARKER = b"<!-- DL-RELEASE-TRUST-START -->"
END_MARKER = b"<!-- DL-RELEASE-TRUST-END -->"


def fail(message: str) -> None:
    raise RuntimeError(message)


def main() -> int:
    if not HOMEPAGE.is_file():
        fail(f"Homepage not found: {HOMEPAGE}")

    original = HOMEPAGE.read_bytes()

    if original.count(START_MARKER) != 1:
        fail(
            "Expected exactly one DL-RELEASE-TRUST start marker. "
            "Nothing was changed."
        )

    if original.count(END_MARKER) != 1:
        fail(
            "Expected exactly one DL-RELEASE-TRUST end marker. "
            "Nothing was changed."
        )

    start = original.index(START_MARKER)
    end = original.index(END_MARKER, start) + len(END_MARKER)

    if end <= start:
        fail("The release-trust marker order is invalid. Nothing was changed.")

    removed = original[start:end]

    required_inside = (
        b"Verified release",
        b"DriveLab Telem 2.2.1 security check",
        b"VirusTotal report",
    )

    for marker in required_inside:
        if marker not in removed:
            fail(
                "The marked block did not contain the expected release text. "
                "Nothing was changed."
            )

    updated = original[:start] + original[end:]

    if START_MARKER in updated or END_MARKER in updated:
        fail("Marker removal validation failed. Nothing was changed.")

    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup_dir = Path(
        f"/var/backups/drivelab-website/remove-exact-release-block-{stamp}"
    )
    backup_dir.mkdir(parents=True, exist_ok=False)
    backup_file = backup_dir / "index.html"
    shutil.copy2(HOMEPAGE, backup_file)

    current = HOMEPAGE.stat()
    temp_file = HOMEPAGE.with_name(HOMEPAGE.name + ".remove-release-block.tmp")

    try:
        temp_file.write_bytes(updated)
        os.chmod(temp_file, stat.S_IMODE(current.st_mode))
        os.chown(temp_file, current.st_uid, current.st_gid)
        os.replace(temp_file, HOMEPAGE)

        installed = HOMEPAGE.read_bytes()

        if installed != updated:
            fail("The installed homepage does not match the exact expected bytes.")

        if installed[:start] != original[:start]:
            fail("Content before the removed block changed unexpectedly.")

        if installed[start:] != original[end:]:
            fail("Content after the removed block changed unexpectedly.")

    except Exception:
        shutil.copy2(backup_file, HOMEPAGE)
        temp_file.unlink(missing_ok=True)
        raise

    print()
    print("============================================================")
    print("EXACT BOTTOM RELEASE BLOCK REMOVED")
    print("============================================================")
    print(f"Homepage: {HOMEPAGE}")
    print(f"Backup:   {backup_file}")
    print(f"Bytes removed: {len(removed)}")
    print("No bytes before or after the marked block were changed.")
    print()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        print(
            "The homepage was left unchanged or restored from backup.",
            file=sys.stderr,
        )
        raise SystemExit(1)

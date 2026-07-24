#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import inspect
import sys
import tempfile
import traceback
from pathlib import Path


OPTIONAL_TEST_DEPENDENCY_MARKERS = (
    "starlette.testclient module requires",
    "testclient module requires",
)


def _load_module(path: Path, index: int):
    name = f"drivelab_owner_test_{index}_{path.stem}"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _optional_dependency_missing(exc: BaseException) -> bool:
    message = str(exc).lower()
    return any(marker in message for marker in OPTIONAL_TEST_DEPENDENCY_MARKERS)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    root = Path(args[0] if args else "/opt/drivelab-license/tests")
    if not root.is_dir():
        print(f"No test directory found: {root}")
        return 0

    files = sorted(root.glob("test_*.py"))
    if not files:
        print(f"No test files found in {root}")
        return 0

    failures = 0
    executed = 0
    skipped = 0

    for file_index, path in enumerate(files):
        module = _load_module(path, file_index)
        tests = [
            (name, function)
            for name, function in inspect.getmembers(module, inspect.isfunction)
            if name.startswith("test_") and function.__module__ == module.__name__
        ]

        for name, function in tests:
            executed += 1
            temporary: tempfile.TemporaryDirectory[str] | None = None
            try:
                parameters = inspect.signature(function).parameters
                kwargs = {}
                unsupported = [parameter for parameter in parameters if parameter != "tmp_path"]
                if unsupported:
                    raise RuntimeError(
                        f"Unsupported fixture(s): {', '.join(unsupported)}. Install pytest to run this test."
                    )
                if "tmp_path" in parameters:
                    temporary = tempfile.TemporaryDirectory(prefix="drivelab-owner-test-")
                    kwargs["tmp_path"] = Path(temporary.name)
                function(**kwargs)
                print(f"PASS {path.name}::{name}")
            except RuntimeError as exc:
                if _optional_dependency_missing(exc):
                    skipped += 1
                    print(
                        f"SKIP {path.name}::{name} - optional Starlette TestClient dependency is not installed; live HTTP validation will cover the deployed endpoints."
                    )
                else:
                    failures += 1
                    print(f"FAIL {path.name}::{name}", file=sys.stderr)
                    traceback.print_exc()
            except Exception:
                failures += 1
                print(f"FAIL {path.name}::{name}", file=sys.stderr)
                traceback.print_exc()
            finally:
                if temporary is not None:
                    temporary.cleanup()

    passed = executed - failures - skipped
    print(
        f"Dependency-free test runner: {passed} passed, {skipped} skipped, "
        f"{failures} failed, {executed} total"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

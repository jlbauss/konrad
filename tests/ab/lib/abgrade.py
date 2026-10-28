# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared helpers for the A/B task graders (tests/ab/<task>/grade.py).

A grader runs in a konrad image (python from /opt/venv, LibreOffice on PATH)
with the trial's workspace read-only at the path it gets as argv[1], and
prints one JSON object: {"checks": [{"name", "pass", "detail"}, ...]}.
scripts/ab-test.sh scores a run as the share of checks that passed.
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


class Checks:
    def __init__(self):
        self.items = []

    def add(self, name, ok, detail=""):
        self.items.append({"name": name, "pass": bool(ok), "detail": str(detail)[:300]})
        return bool(ok)

    def emit(self):
        print(json.dumps({"checks": self.items}, ensure_ascii=False))


def run(grade, names):
    """Run grade(ws, checks); a crash fails every check it didn't reach.

    `names` lists every check the grader can add, in order, so a run that
    dies early still reports the same set of checks as one that finishes,
    and the per-check table compares like with like.
    """
    checks = Checks()
    try:
        grade(Path(sys.argv[1]), checks)
    except Exception as exc:  # noqa: BLE001 — any crash is a finding
        done = {c["name"] for c in checks.items}
        for name in names:
            if name not in done:
                checks.add(name, False, f"not reached: {type(exc).__name__}: {exc}")
    checks.emit()


def recalc(path):
    """A copy of the workbook with every formula computed by LibreOffice."""
    out = Path(tempfile.mkdtemp())
    src = out / "in" / Path(path).name
    src.parent.mkdir()
    shutil.copyfile(path, src)
    subprocess.run(
        ["soffice", "--headless", "--calc", "--convert-to", "xlsx:Calc MS Excel 2007 XML",
         "--outdir", str(out), str(src)],
        capture_output=True, timeout=180, check=False, env={"HOME": str(out), "PATH": "/usr/bin:/bin"},
    )
    produced = out / Path(path).name
    if not produced.exists():
        raise RuntimeError("LibreOffice could not recalculate the workbook")
    return produced


def is_formula(value):
    return isinstance(value, str) and value.startswith("=")


def close(a, b, tol=0.01):
    try:
        return abs(float(a) - float(b)) <= tol
    except (TypeError, ValueError):
        return False

# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade code-fix: rechnung.py fixed so the committed tests pass, and the same bugs fixed for cases they don't cover."""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import run  # noqa: E402

TASK = Path(__file__).resolve().parent
TESTS = re.findall(r"def (test_\w+)", (TASK / "input/test_rechnung.py").read_text())
NAMES = ["rechnung.py imports"] + [f"test passes: {t}" for t in TESTS] + [
    "tests left unchanged", "unseen: negative amount with thousands", "unseen: half-up on an exact half cent",
    "unseen: VAT rounded half-up", "command line prints the totals",
]
# Each probe prints a JSON value; the fixed module has to give the expected one.
UNSEEN = [
    ("parse_betrag('-1.000,00')", -1000.0),
    ("zeile(1, 0.125)", 0.13),
    ("summen([(1, 10.5)])['mwst']", 2.0),
]


def py(cwd, *args):
    return subprocess.run([sys.executable, *args], cwd=cwd, capture_output=True, text=True, timeout=60, check=False)


def grade(ws_dir, c):
    work = Path(tempfile.mkdtemp()) / "ws"
    shutil.copytree(ws_dir, work)
    # Always test with the committed test file, whatever the run did to its copy.
    shutil.copy(TASK / "input/test_rechnung.py", work / "test_rechnung.py")
    imp = py(work, "-c", "import rechnung")
    if not c.add(NAMES[0], imp.returncode == 0, imp.stderr[-200:]):
        raise RuntimeError("rechnung.py doesn't import")
    out = py(work, "-m", "unittest", "-v", "test_rechnung")
    for i, t in enumerate(TESTS, 1):
        c.add(NAMES[i], re.search(rf"^{t} \(.*\) \.\.\. ok$", out.stderr, re.M) is not None,
              next((line for line in out.stderr.splitlines() if line.startswith(t)), "")[-150:])
    n = len(TESTS) + 1
    c.add(NAMES[n], (ws_dir / "test_rechnung.py").read_bytes() == (TASK / "input/test_rechnung.py").read_bytes())
    for k, (expr, want) in enumerate(UNSEEN, n + 1):
        r = py(work, "-c", f"import json; from rechnung import *; print(json.dumps(float({expr})))")
        try:
            got = json.loads(r.stdout)
        except ValueError:
            got = r.stderr.strip().splitlines()[-1:] or "no output"
        c.add(NAMES[k], got == want, f"{expr} -> {got}, want {want}")
    cli = py(work, "rechnung.py", "positionen.csv")
    c.add(NAMES[-1], all(v in cli.stdout for v in ("1426.14", "270.97", "1697.11")), cli.stdout[-200:])


run(grade, NAMES)

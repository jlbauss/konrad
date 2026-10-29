# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade pdf-extract-table: page 2's revenue table of bericht.pdf as a plain, comma-separated umsatz.csv."""

import csv
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import close, run  # noqa: E402

TASK = Path(__file__).resolve().parent
NAMES = [
    "umsatz.csv is UTF-8 CSV", "five columns with a header", "one row per branch, no total row",
    "branch names exact", "revenue columns correct", "change column correct", "staff column correct",
    "plain numbers (no separators or %)", "bericht.pdf untouched",
]


def source():
    sys.path.insert(0, str(TASK))
    from make_input import ROWS
    return ROWS


def num(cell):
    try:
        return float(cell.strip())
    except ValueError:
        return None


def grade(ws_dir, c):
    src = source()
    path = ws_dir / "umsatz.csv"
    try:
        text = path.read_bytes().decode("utf-8-sig")
    except (FileNotFoundError, UnicodeDecodeError) as exc:
        c.add(NAMES[0], False, type(exc).__name__)
        raise RuntimeError("no readable umsatz.csv") from exc
    rows = [r for r in csv.reader(io.StringIO(text)) if any(x.strip() for x in r)]
    c.add(NAMES[0], len(rows) > 1 and all(len(r) > 1 for r in rows), rows[:1])
    head, body = rows[0], rows[1:]
    c.add(NAMES[1], len(head) == 5 and head[0].strip() == "Filiale" and num(head[1]) is None, head)
    names = [r[0].strip() for r in body]
    c.add(NAMES[2], len(body) == len(src) and "Gesamt" not in names, f"{len(body)} rows: {names[-2:]}")
    c.add(NAMES[3], names == [s[0] for s in src], names)
    by = {r[0].strip(): r for r in body if len(r) >= 5}
    got = [(by.get(s[0]), s) for s in src]
    c.add(NAMES[4], all(r and close(num(r[1]), s[1]) and close(num(r[2]), s[2]) for r, s in got),
          [r[1:3] for r, _ in got if r][:2])
    c.add(NAMES[5], all(r and close(num(r[3]), s[3]) for r, s in got), [r[3] for r, _ in got if r][:3])
    c.add(NAMES[6], all(r and close(num(r[4]), s[4]) for r, s in got), [r[4] for r, _ in got if r][:3])
    c.add(NAMES[7], all(num(x) is not None for r in body for x in r[1:5]),
          [x for r in body for x in r[1:5] if num(x) is None][:3])
    c.add(NAMES[8], (ws_dir / "bericht.pdf").read_bytes() == (TASK / "input/bericht.pdf").read_bytes())


run(grade, NAMES)

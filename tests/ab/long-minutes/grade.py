# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade long-minutes: the six spending decisions buried in two years of minutes, and nothing that wasn't one."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import has_amount, run  # noqa: E402

TASK = Path(__file__).resolve().parent
sys.path.insert(0, str(TASK))
from make_input import DECIDED, NOT_DECIDED, REVERSED  # noqa: E402

MONTHS = "Januar Februar März April Mai Juni Juli August September Oktober November Dezember".split()
NAMES = ["beschluesse.md written as a table"] + [f"decision found: {k}" for _, k, _, _ in DECIDED] + [
    "decisions carry their meeting dates", "rejected or put-off proposals left out", "reversed decision marked",
    "protokolle.md untouched",
]
REVERSAL_WORDS = ("aufgehoben", "widerrufen", "zurückgenommen", "storniert", "rückgängig", "entfällt", "reversed",
                  "revoked", "cancel")


def dates(d):
    return (f"{d:%d.%m.%Y}", d.isoformat(), f"{d.day}. {MONTHS[d.month - 1]} {d.year}", f"{d.day}.{d.month}.{d.year}",
            f"{d:%d.%m.%y}")


def grade(ws_dir, c):
    path = ws_dir / "beschluesse.md"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    rows = [line for line in text.splitlines() if line.lstrip().startswith("|")]
    if not c.add(NAMES[0], len(rows) >= 3, "missing" if not path.exists() else f"{len(rows)} table lines"):
        raise RuntimeError("no table in beschluesse.md")
    found = {}
    for i, (meeting, key, amount, _) in enumerate(DECIDED, 1):
        row = next((r for r in rows if has_amount(r, amount)), None)
        found[key] = (row, meeting)
        c.add(NAMES[i], row is not None, f"{amount} €")
    c.add(NAMES[7], all(row and any(d in row for d in dates(m)) for row, m in found.values()),
          [k for k, (row, m) in found.items() if not (row and any(d in row for d in dates(m)))])
    c.add(NAMES[8], not any(has_amount(r, amount) for r in rows for _, amount, _ in NOT_DECIDED),
          [a for _, a, _ in NOT_DECIDED if any(has_amount(r, a) for r in rows)])
    rev = found.get(REVERSED[1], (None, None))[0] or ""
    reversal = rev.lower() + " " + text.lower().split(REVERSED[1].lower(), 1)[-1][:400]
    c.add(NAMES[9], bool(rev) and any(w in reversal for w in REVERSAL_WORDS), rev[:200])
    c.add(NAMES[10], (ws_dir / "protokolle.md").read_bytes() == (TASK / "input/protokolle.md").read_bytes())


run(grade, NAMES)

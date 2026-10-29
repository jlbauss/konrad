# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade receipt-photo: the receipt in beleg.jpg read and added to ausgaben.json in the existing format."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import close, run  # noqa: E402

TASK = Path(__file__).resolve().parent
NAMES = [
    "ausgaben.json is valid JSON", "one entry added, old ones kept", "same fields and types", "date",
    "merchant", "gross amount", "VAT rate and amount", "payment method", "category fits",
]


def grade(ws_dir, c):
    old = json.loads((TASK / "input/ausgaben.json").read_text())
    try:
        got = json.loads((ws_dir / "ausgaben.json").read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError) as exc:
        c.add(NAMES[0], False, type(exc).__name__)
        raise RuntimeError("no readable ausgaben.json") from exc
    c.add(NAMES[0], isinstance(got, list), type(got).__name__)
    c.add(NAMES[1], len(got) == len(old) + 1 and got[:len(old)] == old, f"{len(got)} entries")
    new = next((e for e in got if isinstance(e, dict) and e not in old), {})
    c.add(NAMES[2], set(new) == set(old[0]) and all(type(new[k]) in (type(old[0][k]), int, float)
                                                     if isinstance(old[0][k], (int, float)) else type(new[k]) is str
                                                     for k in old[0] if k in new), new)
    c.add(NAMES[3], new.get("datum") == "2026-10-14", new.get("datum"))
    c.add(NAMES[4], "schulze" in str(new.get("haendler", "")).lower(), new.get("haendler"))
    c.add(NAMES[5], close(new.get("betrag_brutto"), 87.40), new.get("betrag_brutto"))
    c.add(NAMES[6], close(new.get("mwst_satz"), 19) and close(new.get("mwst"), 13.95),
          f"{new.get('mwst_satz')} / {new.get('mwst')}")
    pay = str(new.get("zahlungsart", "")).lower()
    c.add(NAMES[7], any(w in pay for w in ("giro", "ec", "debit", "karte", "card")) and "kredit" not in pay, pay)
    c.add(NAMES[8], "büro" in str(new.get("kategorie", "")).lower(), new.get("kategorie"))


run(grade, NAMES)

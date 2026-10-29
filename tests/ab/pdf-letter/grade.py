# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade pdf-letter: a one-page A4 cancellation letter from notizen.txt, its address where a window envelope shows it."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import run  # noqa: E402

import pdfplumber  # noqa: E402

TASK = Path(__file__).resolve().parent
MM = 72 / 25.4
NAMES = [
    "brief.pdf opens", "one page", "A4", "recipient's address complete", "sender named", "dated 29 October 2026",
    "subject names the cancellation and the contract", "ends on 31 December 2026", "asks for written confirmation",
    "closing and signer", "address in the envelope window", "umlauts intact", "notizen.txt untouched",
]


def grade(ws_dir, c):
    try:
        pdf = pdfplumber.open(ws_dir / "brief.pdf")
        page = pdf.pages[0]
    except Exception as exc:  # noqa: BLE001 — a missing or broken PDF fails the lot
        c.add(NAMES[0], False, type(exc).__name__)
        raise RuntimeError("no readable brief.pdf") from exc
    c.add(NAMES[0], True)
    c.add(NAMES[1], len(pdf.pages) == 1, f"{len(pdf.pages)} pages")
    c.add(NAMES[2], abs(page.width - 210 * MM) < 3 and abs(page.height - 297 * MM) < 3, (page.width, page.height))
    text = "\n".join(p.extract_text() or "" for p in pdf.pages)
    flat = " ".join(text.split())
    c.add(NAMES[3], all(s in flat for s in ("Kältetechnik Musterland GmbH", "Siegburger Straße 230", "12347 Musterstadt")), "")
    c.add(NAMES[4], "Miriam Achterberg" in flat, "")
    c.add(NAMES[5], "29.10.2026" in flat or "29. Oktober 2026" in flat, "")
    lines = [line for line in text.splitlines() if "Kündigung" in line and "WV-2023-0471" in line]
    c.add(NAMES[6], bool(lines), lines[:1])
    c.add(NAMES[7], "31.12.2026" in flat or "31. Dezember 2026" in flat, "")
    c.add(NAMES[8], "bestätig" in flat.lower() or "Bestätigung" in flat, "")
    tail = flat.split("Mit freundlichen Grüßen", 1)
    c.add(NAMES[9], len(tail) == 2 and "Achterberg" in tail[1], tail[-1][-80:])
    words = page.extract_words()
    hit = next((w for w in words if w["text"].startswith("Kältetechnik")
                and 35 * MM <= w["top"] <= 95 * MM and 15 * MM <= w["x0"] <= 35 * MM), None)
    first = next((w for w in words if w["text"].startswith("Kältetechnik")), None)
    c.add(NAMES[10], hit is not None,
          f"at {first['x0'] / MM:.0f} mm from left, {first['top'] / MM:.0f} mm from top" if first else "not found")
    c.add(NAMES[11], "Kältetechnik" in flat and "ß" in flat and "Ã" not in flat, "")
    c.add(NAMES[12], (ws_dir / "notizen.txt").read_bytes() == (TASK / "input/notizen.txt").read_bytes())


run(grade, NAMES)

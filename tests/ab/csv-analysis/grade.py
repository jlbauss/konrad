# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade csv-analysis: analyse.md with revenue per region, the best month, the top three products and a chart."""

import collections
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import has_amount, run  # noqa: E402

from PIL import Image  # noqa: E402

TASK = Path(__file__).resolve().parent
NAMES = [
    "analyse.md written", "revenue per region correct", "regions as a table", "best month named",
    "top three products named", "umsatz.png is a chart image", "chart shown in the document", "verkaeufe.csv untouched",
]
DE = "januar februar märz april mai juni juli august september oktober november dezember".split()
EN = "january february march april may june july august september october november december".split()


def month_names(m):
    return (DE[m - 1], EN[m - 1], f"2025-{m:02d}", f"{m:02d}/2025", f"{m:02d}.2025")


def expected():
    rows = list(csv.DictReader((TASK / "input/verkaeufe.csv").open(encoding="utf-8")))
    region, product, month = collections.Counter(), collections.Counter(), collections.Counter()
    for r in rows:
        region[r["region"]] += float(r["umsatz"])
        product[r["produkt"]] += float(r["umsatz"])
        month[int(r["datum"][5:7])] += float(r["umsatz"])
    return region, [p for p, _ in product.most_common(3)], month.most_common(1)[0][0]


def grade(ws_dir, c):
    region, top3, best = expected()
    path = ws_dir / "analyse.md"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    if not c.add(NAMES[0], text.strip(), "missing" if not path.exists() else "empty"):
        raise RuntimeError("no analyse.md")
    c.add(NAMES[1], all(has_amount(text, v, tol=1.0) for v in region.values()),
          {k: round(v, 2) for k, v in region.items() if not has_amount(text, v, tol=1.0)})
    rows = [line for line in text.splitlines() if line.lstrip().startswith("|")]
    c.add(NAMES[2], all(any(r in line for line in rows) for r in region), rows[:3])
    low = text.lower() + " "
    c.add(NAMES[3], any(m in low for m in month_names(best)), f"expected month {best}")
    c.add(NAMES[4], all(p in text for p in top3), [p for p in top3 if p not in text])
    png = ws_dir / "umsatz.png"
    try:
        with Image.open(png) as im:
            size = im.size
            ok = im.format == "PNG" and im.width >= 400 and len(im.convert("RGB").getcolors(1 << 20) or []) > 2
    except (FileNotFoundError, OSError) as exc:
        size, ok = type(exc).__name__, False
    c.add(NAMES[5], ok, size)
    c.add(NAMES[6], re.search(r"!\[[^\]]*\]\(<?(\./)?umsatz\.png>?\)", text) is not None, "")
    c.add(NAMES[7], (ws_dir / "verkaeufe.csv").read_bytes() == (TASK / "input/verkaeufe.csv").read_bytes())


run(grade, NAMES)

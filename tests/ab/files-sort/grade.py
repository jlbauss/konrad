# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade files-sort: twelve letters renamed to date_sender, filed by year, and listed in post/index.csv."""

import csv
import hashlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import run  # noqa: E402

TASK = Path(__file__).resolve().parent
sys.path.insert(0, str(TASK))
from make_input import LETTERS  # noqa: E402

NAMES = [
    "every letter kept, unaltered", "named by the letter's own date", "named by the sender", "filed in its year's folder",
    "nothing left under the old names", "index.csv has the four columns", "index lists every letter once",
    "index dates right", "index subjects right",
]


def fold(s):
    s = s.lower()
    for a, b in (("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")):
        s = s.replace(a, b)
    return re.sub(r"[^a-z0-9]", "", s)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def grade(ws_dir, c):
    post = ws_dir / "post"
    where = {}
    for f in post.rglob("*") if post.is_dir() else []:
        if f.is_file() and f.suffix.lower() == ".pdf":
            where.setdefault(digest(f), []).append(f)
    placed = {}
    for scan, *_ in LETTERS:
        found = where.get(digest(TASK / "input/post" / scan), [])
        placed[scan] = next((f for f in found if f.name != scan), found[0] if found else None)
    c.add(NAMES[0], all(placed.values()), [s for s, f in placed.items() if not f])
    got = [(f, letter) for letter in LETTERS if (f := placed[letter[0]])]
    c.add(NAMES[1], len(got) == len(LETTERS) and all(re.fullmatch(rf"{d}_.+\.pdf", f.name) for f, (_, _, _, d, _, _) in got),
          [f.name for f, letter in got if not f.name.startswith(letter[3])][:3])
    c.add(NAMES[2], len(got) == len(LETTERS) and all(key in fold(f.stem) for f, (_, _, key, _, _, _) in got),
          [f.name for f, letter in got if letter[2] not in fold(f.stem)][:3])
    c.add(NAMES[3], len(got) == len(LETTERS) and all(f.parent == post / d[:4] for f, (_, _, _, d, _, _) in got),
          sorted({str(f.parent.relative_to(ws_dir)) for f, _ in got})[:4])
    c.add(NAMES[4], not any((post / s).exists() for s, *_ in LETTERS), [s for s, *_ in LETTERS if (post / s).exists()][:3])
    index = post / "index.csv"
    rows = []
    if index.exists():
        text = index.read_bytes().decode("utf-8-sig", errors="replace")
        try:
            dialect = csv.Sniffer().sniff(text.splitlines()[0], delimiters=",;\t")
        except (csv.Error, IndexError):
            dialect = csv.excel
        rows = list(csv.DictReader(text.splitlines(), dialect=dialect))
    cols = [k.strip().lower() for k in (rows[0].keys() if rows else [])]
    c.add(NAMES[5], cols[:4] == ["datei", "datum", "absender", "betreff"], cols)
    by_file = {}
    for r in rows:
        name = Path(str(r.get("datei") or r.get("Datei") or "").strip()).name
        by_file.setdefault(name, []).append({k.strip().lower(): (v or "").strip() for k, v in r.items() if k})
    listed = [(by_file.get(f.name, []), letter) for f, letter in got]
    c.add(NAMES[6], len(rows) == len(LETTERS) and all(len(e) == 1 for e, _ in listed) and len(listed) == len(LETTERS),
          f"{len(rows)} rows, {sum(len(e) == 1 for e, _ in listed)} matched")

    def same_date(s, iso):
        y, m, d = iso.split("-")
        return s in (iso, f"{d}.{m}.{y}")
    c.add(NAMES[7], len(listed) == len(LETTERS) and all(e and same_date(e[0].get("datum", ""), letter[3]) for e, letter in listed),
          [e[0].get("datum") for e, letter in listed if e and not same_date(e[0].get("datum", ""), letter[3])][:3])
    c.add(NAMES[8], len(listed) == len(LETTERS) and all(e and letter[4] in e[0].get("betreff", "") for e, letter in listed),
          [e[0].get("betreff") for e, letter in listed if e and letter[4] not in e[0].get("betreff", "")][:3])


run(grade, NAMES)

# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade docx-edit-contract: a rename, a tracked change and a comment in contract.docx (see prompt.md)."""

import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import W, norm, run, to_pdf  # noqa: E402

from docx import Document  # noqa: E402
from lxml import etree  # noqa: E402

TASK = Path(__file__).resolve().parent
NAMES = [
    "contract-v2.docx opens", "old name gone", "new name in all six places", "party name still bold",
    "30 → 45 is a tracked change", "clause 4 reads 45 days", "comment text", "comment on the Liability heading",
    "everything else unchanged", "logo kept", "LibreOffice renders it", "contract.docx untouched",
]
OLD, NEW = "Nordlicht GmbH", "Polarstern AG"
PART = re.compile(r"word/(document|header\d*|footer\d*)\.xml$")


def parts(path):
    """{part name: root element} for the body, headers and footers."""
    with zipfile.ZipFile(path) as z:
        return {n: etree.fromstring(z.read(n)) for n in sorted(z.namelist()) if PART.match(n)}


def accepted(p):
    """A paragraph's text as it reads with every tracked change accepted."""
    return "".join(t.text or "" for t in p.iter(f"{W}t") if not any(a.tag == f"{W}del" for a in t.iterancestors()))


def style(p):
    el = p.find(f"{W}pPr/{W}pStyle")
    return el.get(f"{W}val") if el is not None else ""


def paragraphs(root):
    return [p for p in root.iter(f"{W}p")]


def media(path):
    with zipfile.ZipFile(path) as z:
        return sum(1 for n in z.namelist() if n.startswith("word/media/"))


def grade(ws_dir, c):
    src = TASK / "input/contract.docx"
    path = ws_dir / "contract-v2.docx"
    exists = path.exists()
    if not c.add(NAMES[0], exists and Document(path) is not None, "" if exists else "missing"):
        raise RuntimeError("no contract-v2.docx")
    got, orig = parts(path), parts(src)
    # python-docx adds an empty part for every first-page or even-page header it is asked about; with
    # neither switched on, Word never shows them, so a new part without text doesn't count.
    got = {n: r for n, r in got.items() if n in orig or any(accepted(p).strip() for p in paragraphs(r))}
    texts = {n: [accepted(p) for p in paragraphs(r)] for n, r in got.items()}
    every = "\n".join(t for ts in texts.values() for t in ts)
    c.add(NAMES[1], OLD not in every and "Nordlicht" not in every, every.count("Nordlicht"))
    counts = {n: sum(t.count(NEW) for t in ts) for n, ts in texts.items()}
    want = {n: sum(accepted(p).count(OLD) for p in paragraphs(r)) for n, r in orig.items()}
    c.add(NAMES[2], counts == want and sum(counts.values()) == 6, f"{counts} vs {want}")

    body = paragraphs(got["word/document.xml"])
    party = next((p for p in body if accepted(p).startswith("between")), None)
    runs = [r for r in party.iter(f"{W}r") if "Polarstern" in "".join(t.text or "" for t in r.iter(f"{W}t"))] \
        if party is not None else []
    c.add(NAMES[3], runs and all(r.find(f"{W}rPr/{W}b") is not None for r in runs), f"{len(runs)} run(s)")

    pay = next((p for p in body if "payable" in accepted(p)), None)
    if pay is None:
        raise RuntimeError("clause 4 paragraph gone")
    deleted = "".join(t.text or "" for d in pay.iter(f"{W}del") for t in d.iter(f"{W}delText"))
    inserted = "".join(t.text or "" for i in pay.iter(f"{W}ins") for t in i.iter(f"{W}t"))
    c.add(NAMES[4], "30" in deleted and "45" in inserted and "45" not in deleted,
          f"deleted {deleted!r}, inserted {inserted!r}")
    c.add(NAMES[5], norm(accepted(pay)) == "Invoices are payable within 45 days of receipt", accepted(pay))

    with zipfile.ZipFile(path) as z:
        comments = etree.fromstring(z.read("word/comments.xml")) if "word/comments.xml" in z.namelist() else None
    ids = [cm.get(f"{W}id") for cm in (comments.iter(f"{W}comment") if comments is not None else [])
           if "confirm the cap" in "".join(t.text or "" for t in cm.iter(f"{W}t"))]
    c.add(NAMES[6], bool(ids), f"{len(ids)} matching comment(s)")
    anchored = [(accepted(p), style(p)) for p in body for tag in ("commentRangeStart", "commentReference")
                for el in p.iter(f"{W}{tag}") if el.get(f"{W}id") in ids]
    c.add(NAMES[7], any("Liability" in t and s.startswith("Heading") for t, s in anchored), anchored)

    def plain(ts, rename):
        return [norm(t.replace(OLD, NEW) if rename else t) for t in ts if "payable" not in t]

    differ = [n for n, r in orig.items()
              if plain(texts.get(n, []), False) != plain([accepted(p) for p in paragraphs(r)], True)]
    c.add(NAMES[8], not differ and set(got) == set(orig), differ + sorted(set(got) ^ set(orig)))
    c.add(NAMES[9], media(path) >= media(src), f"{media(path)} image(s), input has {media(src)}")
    c.add(NAMES[10], to_pdf(path) is not None)
    c.add(NAMES[11], (ws_dir / "contract.docx").read_bytes() == src.read_bytes())


run(grade, NAMES)

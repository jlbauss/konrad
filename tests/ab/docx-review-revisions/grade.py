# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade docx-review-revisions: one reviewer accepted, the other rejected, comments kept (see prompt.md)."""

import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import W, norm, run, to_pdf  # noqa: E402

from docx import Document  # noqa: E402
from lxml import etree  # noqa: E402

TASK = Path(__file__).resolve().parent
NAMES = [
    "review-final.docx opens", "no tracked changes left", "Anna's changes accepted", "Ben's changes rejected",
    "text exactly as expected", "three comments kept", "comments still anchored", "comments.txt",
    "LibreOffice renders it", "review.docx untouched",
]
EXPECTED = [
    "Pilot Report: New Branch System", "Results",
    "The pilot ran in five branches from June to September.",
    "Staff rated the new system positively, with few complaints.",
    "Support tickets fell by 23 percent.",
    "The rollout to all branches is planned for January.",
    "Status", "Item", "Value", "Phase", "Rollout", "Budget owner", "Finance",
    "Next review: 15 November.",
]
ANNA = {"five branches", "23 percent", "Rollout", "15 November"}
BEN = {"positively, with few complaints", "is planned for January", "Finance"}
COMMENTS = {("Anna Berg", "Five, not four – see the branch list."), ("Ben Ott", "Do we have a new date?"),
            ("Anna Berg", "Confirm after the steering meeting.")}


def grade(ws_dir, c):
    src = TASK / "input/review.docx"
    path = ws_dir / "review-final.docx"
    exists = path.exists()
    if not c.add(NAMES[0], exists and Document(path) is not None, "" if exists else "missing"):
        raise RuntimeError("no review-final.docx")
    with zipfile.ZipFile(path) as z:
        body = etree.fromstring(z.read("word/document.xml"))
        comments = etree.fromstring(z.read("word/comments.xml")) if "word/comments.xml" in z.namelist() else None
    marks = len(list(body.iter(f"{W}ins"))) + len(list(body.iter(f"{W}del")))
    c.add(NAMES[1], marks == 0, f"{marks} w:ins/w:del left")

    # With no marks left, the plain text is the result; with some left, read it as Word shows it, marks and all.
    paras = ["".join(t.text or "" for t in p.iter(f"{W}t", f"{W}delText")) for p in body.iter(f"{W}p")]
    paras = [norm(p) for p in paras if p.strip()]
    text = "\n".join(paras)
    c.add(NAMES[2], all(s in text for s in ANNA) and "four" not in text and "Pilot\n" not in text,
          [s for s in ANNA if s not in text])
    c.add(NAMES[3], all(s in text for s in BEN) and not any(s in text for s in ("very", "overall", "slip", "TBD")),
          [s for s in BEN if s not in text])
    c.add(NAMES[4], paras == [norm(e) for e in EXPECTED],
          next((f"{g!r} vs {e!r}" for g, e in zip(paras, EXPECTED) if g != norm(e)), f"{len(paras)} paragraphs"))

    got = {(cm.get(f"{W}author"), norm("".join(t.text or "" for t in cm.iter(f"{W}t"))))
           for cm in (comments.iter(f"{W}comment") if comments is not None else [])}
    want = {(a, norm(t)) for a, t in COMMENTS}
    c.add(NAMES[5], got == want, sorted(got))
    ids = {cm.get(f"{W}id") for cm in (comments.iter(f"{W}comment") if comments is not None else [])}
    refs = {el.get(f"{W}id") for el in body.iter(f"{W}commentReference")}
    c.add(NAMES[6], ids and ids <= refs, f"comments {sorted(ids)}, referenced {sorted(refs)}")

    txt = ws_dir / "comments.txt"
    lines = {norm(line) for line in txt.read_text(encoding="utf-8").splitlines() if line.strip()} \
        if txt.exists() else set()
    c.add(NAMES[7], lines == {norm(f"{a}: {t}") for a, t in COMMENTS}, sorted(lines) if txt.exists() else "missing")
    c.add(NAMES[8], to_pdf(path) is not None)
    c.add(NAMES[9], (ws_dir / "review.docx").read_bytes() == src.read_bytes())


run(grade, NAMES)

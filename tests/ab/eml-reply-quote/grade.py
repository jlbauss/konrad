# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Grade eml-reply-quote: a threaded German reply as antwort.eml, the quote in the text and as angebot.pdf."""

import email
import email.policy
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
from abgrade import has_amount, pdf_text, run  # noqa: E402

TASK = Path(__file__).resolve().parent
NAMES = [
    "antwort.eml parses as an email", "to the customer", "from the sales address", "subject is a reply",
    "threaded (In-Reply-To, References)", "umlauts intact", "line totals in the text", "net, VAT and gross in the text",
    "offers the 18 November date", "angebot.pdf attached", "angebot.pdf shows the gross total", "anfrage.eml untouched",
]
ORIG_ID = "<20261027091512.4711@baeckerei-krueger.example>"
LINES, NET, VAT, GROSS = (1556.00, 1499.00, 240.00, 95.00), 3390.00, 644.10, 4034.10


def grade(ws_dir, c):
    path = ws_dir / "antwort.eml"
    msg = email.message_from_bytes(path.read_bytes(), policy=email.policy.default) if path.exists() else None
    body = msg.get_body(preferencelist=("plain", "html")) if msg else None
    text = body.get_content() if body else ""
    if not c.add(NAMES[0], msg is not None and msg["From"] and text.strip(), "missing" if msg is None else "no body"):
        raise RuntimeError("no usable antwort.eml")
    c.add(NAMES[1], "s.krueger@baeckerei-krueger.example" in str(msg["To"]), msg["To"])
    c.add(NAMES[2], "vertrieb@werkstatt-mueller.example" in str(msg["From"]), msg["From"])
    subject = str(msg["Subject"] or "")
    c.add(NAMES[3], subject.lower().startswith(("re:", "aw:")) and "Angebot für Regale und Montage" in subject, subject)
    c.add(NAMES[4], str(msg["In-Reply-To"] or "").strip() == ORIG_ID and ORIG_ID in str(msg["References"] or ""),
          f"In-Reply-To {msg['In-Reply-To']}, References {msg['References']}")
    c.add(NAMES[5], any(u in text for u in "äöüß") and not any(m in text + subject for m in ("Ã", "�", "=C3")),
          text[:120])
    c.add(NAMES[6], all(has_amount(text, v) for v in LINES), [v for v in LINES if not has_amount(text, v)])
    c.add(NAMES[7], all(has_amount(text, v) for v in (NET, VAT, GROSS)),
          [v for v in (NET, VAT, GROSS) if not has_amount(text, v)])
    c.add(NAMES[8], "18.11" in text or "18. November" in text, "")
    pdfs = [p for p in msg.iter_attachments() if (p.get_filename() or "").lower() == "angebot.pdf"]
    data = pdfs[0].get_content() if pdfs else b""
    c.add(NAMES[9], data[:5] == b"%PDF-", [p.get_filename() for p in msg.iter_attachments()])
    shown = ""
    if data[:5] == b"%PDF-":
        tmp = Path(tempfile.mkdtemp()) / "angebot.pdf"
        tmp.write_bytes(data)
        shown = pdf_text(tmp)
    c.add(NAMES[10], has_amount(shown, GROSS), shown[:200])
    c.add(NAMES[11], (ws_dir / "anfrage.eml").read_bytes() == (TASK / "input/anfrage.eml").read_bytes())


run(grade, NAMES)

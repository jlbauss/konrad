# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Regenerate input/post/*.pdf (committed, so every trial starts from the same bytes).

Run in a konrad image. Twelve one-page letters under scanner names, across
three years. Most carry more than one date (a due date, "Ihr Schreiben vom
…"), so the letter's own date has to be told from the others. The grader
imports LETTERS from here.

    podman run --rm -v "$PWD/tests/ab/files-sort:/t:z" --entrypoint /opt/venv/bin/python \\
        konrad:local /t/make_input.py /t/input/post
"""

import sys
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

FONT = "/usr/share/fonts/truetype/noto/NotoSans-"
pdfmetrics.registerFont(TTFont("Noto", FONT + "Regular.ttf"))
pdfmetrics.registerFont(TTFont("Noto-Bold", FONT + "Bold.ttf"))

# scan name, sender (letterhead), key the file name must contain, place and date, subject, body
LETTERS = [
    ("SCAN0001.pdf", "Stadtwerke Musterstadt GmbH", "stadtwerke", "2025-02-03", "Jahresabrechnung Strom 2024",
     "für den Abrechnungszeitraum 01.01.2024 bis 31.12.2024 ergibt sich ein Guthaben von 84,12 €, das wir bis zum "
     "17.02.2025 auf Ihr Konto überweisen."),
    ("SCAN0002.pdf", "Finanzamt Musterstadt-Nord", "finanzamt", "2025-06-18", "Einkommensteuerbescheid 2024",
     "anbei erhalten Sie den Bescheid für 2024. Gegen den Bescheid kann bis zum 18.07.2025 Einspruch eingelegt werden."),
    ("SCAN0003.pdf", "Hausverwaltung Kessler & Partner", "kessler", "2024-11-29", "Nebenkostenabrechnung 2023",
     "bezugnehmend auf Ihr Schreiben vom 04.11.2024 übersenden wir die korrigierte Abrechnung. Die Nachzahlung von "
     "212,40 € ist fällig bis 31.12.2024."),
    ("SCAN0004.pdf", "Allgemeine Ortskrankenkasse Musterland", "krankenkasse", "2026-01-12", "Beitragssatz ab 2026",
     "zum 01.01.2026 ändert sich der Zusatzbeitrag. Für Sie ändert sich nichts weiter; bitte bewahren Sie dieses "
     "Schreiben auf."),
    ("SCAN0005.pdf", "Zahnarztpraxis Dr. Okafor", "okafor", "2025-09-08", "Rechnung Nr. 2025-1187",
     "für die Behandlung am 26.08.2025 berechnen wir 146,90 €. Bitte überweisen Sie den Betrag bis zum 22.09.2025."),
    ("SCAN0006.pdf", "Stadtwerke Musterstadt GmbH", "stadtwerke", "2026-02-02", "Jahresabrechnung Strom 2025",
     "für den Abrechnungszeitraum 01.01.2025 bis 31.12.2025 ergibt sich eine Nachzahlung von 37,55 €, die wir am "
     "16.02.2026 abbuchen."),
    ("SCAN0007.pdf", "Musterstädter Volksbank eG", "volksbank", "2024-12-16", "Neue Konditionen Ihres Girokontos",
     "ab dem 01.03.2025 gelten für Ihr Konto neue Entgelte. Die Übersicht finden Sie auf der Rückseite."),
    ("SCAN0008.pdf", "Kfz-Versicherung Rheinstern AG", "rheinstern", "2025-11-20", "Beitragsrechnung 2026",
     "Ihr Beitrag für das Versicherungsjahr 2026 beträgt 412,80 €. Er wird am 01.01.2026 fällig."),
    ("SCAN0009.pdf", "Hausverwaltung Kessler & Partner", "kessler", "2026-03-04", "Ankündigung Fensteraustausch",
     "in der Zeit vom 13.04.2026 bis 24.04.2026 werden im Haus die Fenster getauscht. Wir bitten um Zugang zur "
     "Wohnung."),
    ("SCAN0010.pdf", "Finanzamt Musterstadt-Nord", "finanzamt", "2024-07-22", "Einkommensteuerbescheid 2023",
     "anbei erhalten Sie den Bescheid für 2023. Die Erstattung von 318,00 € wird in den nächsten Tagen überwiesen."),
    ("SCAN0011.pdf", "Bürgeramt Musterstadt", "buergeramt", "2025-04-02", "Ihr Personalausweis liegt bereit",
     "Ihr am 10.03.2025 beantragter Personalausweis kann abgeholt werden. Bitte bringen Sie den alten Ausweis mit."),
    ("SCAN0012.pdf", "Zahnarztpraxis Dr. Okafor", "okafor", "2026-05-27", "Erinnerung Kontrolltermin",
     "Ihr nächster Kontrolltermin ist am 16.06.2026 um 8:30 Uhr. Bitte sagen Sie spätestens 24 Stunden vorher ab, "
     "wenn Sie verhindert sind."),
]


def letter(path, sender, date, subject, body):
    c = canvas.Canvas(str(path), pagesize=A4)
    w, h = A4
    c.setFont("Noto-Bold", 13)
    c.drawString(25 * mm, h - 20 * mm, sender)
    c.setFont("Noto", 8)
    c.drawString(25 * mm, h - 47 * mm, f"{sender} · Postfach 10 20 30 · 12345 Musterstadt")
    c.setFont("Noto", 11)
    for i, line in enumerate(["Herrn", "Jonas Petersen", "Lindenweg 14", "12345 Musterstadt"]):
        c.drawString(25 * mm, h - (55 + 5 * i) * mm, line)
    y, m, d = date.split("-")
    c.drawRightString(w - 20 * mm, h - 98 * mm, f"Musterstadt, {d}.{m}.{y}")
    c.setFont("Noto-Bold", 11)
    c.drawString(25 * mm, h - 108 * mm, subject)
    c.setFont("Noto", 11)
    t = c.beginText(25 * mm, h - 120 * mm)
    t.setLeading(15)
    words, line = ("Sehr geehrter Herr Petersen,\n\n" + body + "\n\nMit freundlichen Grüßen\n\n" + sender).split(" "), ""
    for word in words:
        for k, part in enumerate(word.split("\n")):
            if k:
                t.textLine(line)
                line = ""
            if c.stringWidth(line + " " + part, "Noto", 11) > w - 45 * mm:
                t.textLine(line)
                line = part
            else:
                line = (line + " " + part).strip()
    t.textLine(line)
    c.drawText(t)
    c.setTitle("")
    c.setAuthor("")
    c.setCreator("Scanner")
    c.save()


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for name, sender, _, date, subject, body in LETTERS:
        letter(out / name, sender, date, subject, body)


if __name__ == "__main__":
    main(sys.argv[1])

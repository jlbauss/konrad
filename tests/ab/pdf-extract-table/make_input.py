# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Regenerate input/bericht.pdf (committed, so every trial starts from the same bytes).

Run in a konrad image. Three pages: prose, the revenue table on page 2 in German
number format (with a total row to leave out), and a second table on page 3
that isn't the one asked for. The branch names carry umlauts.

    podman run --rm -v "$PWD/tests/ab/pdf-extract-table:/t:z" --entrypoint /opt/venv/bin/python \\
        konrad:local /t/make_input.py /t/input/bericht.pdf
"""

import sys

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

FONT = "/usr/share/fonts/truetype/noto/NotoSans-"
pdfmetrics.registerFont(TTFont("Noto", FONT + "Regular.ttf"))
pdfmetrics.registerFont(TTFont("Noto-Bold", FONT + "Bold.ttf"))

# Filiale, Umsatz Q3 2026, Umsatz Q3 2025, Veränderung %, Mitarbeitende
ROWS = [
    ("Köln-Ehrenfeld", 412650.80, 398120.40, 3.6, 14),
    ("Düsseldorf Altstadt", 389004.15, 401877.90, -3.2, 13),
    ("Münster", 201330.00, 187415.25, 7.4, 8),
    ("Bonn", 176905.60, 176905.60, 0.0, 7),
    ("Essen-Rüttenscheid", 254118.95, 239870.10, 5.9, 10),
    ("Aachen", 143877.30, 151204.75, -4.8, 6),
    ("Wuppertal", 98450.00, 91233.40, 7.9, 4),
    ("Gütersloh", 75112.45, 80001.00, -6.1, 3),
]


def de(x, d=2):
    return f"{x:,.{d}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def main(out):
    st = getSampleStyleSheet()
    for s in st.byName.values():
        s.fontName = "Noto-Bold" if "Heading" in s.name or s.name == "Title" else "Noto"
    p = lambda t, s="BodyText": Paragraph(t, st[s])  # noqa: E731
    style = TableStyle([("FONT", (0, 0), (-1, -1), "Noto", 9), ("FONT", (0, 0), (-1, 0), "Noto-Bold", 9),
                        ("FONT", (0, -1), (-1, -1), "Noto-Bold", 9), ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
                        ("LINEBELOW", (0, 0), (-1, 0), 0.8, colors.black), ("LINEABOVE", (0, -1), (-1, -1), 0.8, colors.black),
                        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.white, colors.HexColor("#f1f1ee")])])
    head = ["Filiale", "Umsatz Q3 2026 (€)", "Umsatz Q3 2025 (€)", "Veränderung", "Mitarbeitende"]
    total = [sum(r[1] for r in ROWS), sum(r[2] for r in ROWS)]
    data = [head] + [[r[0], de(r[1]), de(r[2]), f"{de(r[3], 1)} %", str(r[4])] for r in ROWS] + \
        [["Gesamt", de(total[0]), de(total[1]), f"{de((total[0] / total[1] - 1) * 100, 1)} %", str(sum(r[4] for r in ROWS))]]
    staff = [["Bereich", "Vollzeit", "Teilzeit", "Auszubildende"], ["Filialen", "41", "24", "6"],
             ["Zentrale Köln", "18", "5", "2"], ["Logistik", "12", "3", "1"]]
    story = [p("Quartalsbericht Q3 2026", "Title"), p("Zusammenfassung", "Heading2"),
             p("Das dritte Quartal 2026 schloss mit einem leichten Umsatzplus gegenüber dem Vorjahr. Getragen wurde "
               "das Wachstum von den Filialen in Münster, Essen und Wuppertal, während Düsseldorf, Aachen und "
               "Gütersloh hinter dem Vorjahr blieben. Die Umbauarbeiten in Düsseldorf führten im August zu zwei "
               "Schließtagen."),
             p("Im Online-Geschäft stieg der Anteil der Abholbestellungen weiter. Die Einführung des neuen "
               "Kassensystems ist in allen Filialen abgeschlossen; die Schulungen laufen bis Ende Oktober."),
             PageBreak(), p("Umsatz nach Filiale", "Heading2"),
             p("Umsätze netto, ohne Online-Versand. Die Veränderung bezieht sich auf das dritte Quartal 2025."),
             Spacer(1, 4 * mm), Table(data, style=style, colWidths=[48 * mm, 34 * mm, 34 * mm, 24 * mm, 26 * mm]),
             Spacer(1, 6 * mm),
             p("Bonn blieb unverändert, weil die Filiale im Vorjahresquartal wegen eines Wasserschadens ebenfalls "
               "nur eingeschränkt geöffnet war."),
             PageBreak(), p("Personal", "Heading2"), p("Stand 30. September 2026, Köpfe."), Spacer(1, 4 * mm),
             Table(staff, style=TableStyle(style.getCommands()[:6]))]
    SimpleDocTemplate(out, pagesize=A4, title="Quartalsbericht Q3 2026", author="Controlling").build(story)


if __name__ == "__main__":
    main(sys.argv[1])

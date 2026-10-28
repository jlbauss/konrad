# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""A neutral outline of an office file for a blind judge: outline(path), or abdump.py <file>.

The judge gets this outline, the rendered pages and the text instead of the
file itself, so nothing about how a file was made (core properties, part
names, leftover parts) can tell it which side produced it. Covers .docx,
.pptx and .xlsx; anything else prints nothing.
"""

import json
import sys
from pathlib import Path


def docx(path):
    from docx import Document

    doc = Document(path)
    body = [{"style": p.style.name, "text": p.text} for p in doc.paragraphs if p.text.strip()]
    tables = [[[c.text for c in row.cells] for row in t.rows] for t in doc.tables]
    sec = doc.sections[0]
    xml = doc.element.xml
    return {
        "page_mm": [round(sec.page_width.mm), round(sec.page_height.mm)],
        "paragraphs": body,
        "tables": tables,
        "header": [p.text for s in doc.sections for p in s.header.paragraphs if p.text.strip()],
        "footer": [p.text for s in doc.sections for p in s.footer.paragraphs if p.text.strip()],
        "footer_fields": sorted({f for s in doc.sections for f in ("PAGE", "NUMPAGES")
                                 if f in s.footer._element.xml}),
        "tracked_insertions": xml.count("<w:ins "), "tracked_deletions": xml.count("<w:del "),
        "comments": [{"author": c.author, "text": c.text} for c in getattr(doc, "comments", [])],
        "images": len(doc.inline_shapes),
    }


def pptx(path):
    from pptx import Presentation

    deck = Presentation(path)
    slides = []
    for s in deck.slides:
        shapes = []
        for sh in s.shapes:
            item = {"kind": str(sh.shape_type).split(".")[-1].split(" ")[0].lower(),
                    "box_in": [round(v / 914400, 2) for v in (sh.left or 0, sh.top or 0, sh.width or 0, sh.height or 0)]}
            if sh.has_text_frame and sh.text_frame.text.strip():
                item["text"] = sh.text_frame.text
            fields = sorted({f.get("type") for f in sh._element.iter("{http://schemas.openxmlformats.org/drawingml/2006/main}fld")})
            if fields:
                item["fields"] = fields  # e.g. slidenum: a live field, not typed text
            if getattr(sh, "has_chart", False) and sh.has_chart:
                plot = sh.chart.plots[0]
                item["chart"] = {"type": str(sh.chart.chart_type).split(" ")[0],
                                 "categories": list(plot.categories),
                                 "series": {s.name: list(s.values) for s in plot.series}}
            if getattr(sh, "has_table", False) and sh.has_table:
                item["table"] = [[c.text for c in row.cells] for row in sh.table.rows]
            shapes.append(item)
        slides.append({"layout": s.slide_layout.name,
                       "title": s.shapes.title.text if s.shapes.title is not None else None,
                       "shapes": shapes,
                       "notes": s.notes_slide.notes_text_frame.text if s.has_notes_slide else ""})
    return {"slide_in": [round(deck.slide_width / 914400, 2), round(deck.slide_height / 914400, 2)], "slides": slides}


def xlsx(path):
    from openpyxl import load_workbook

    wb = load_workbook(path)
    out = {}
    for ws in wb.worksheets:
        rows = [[c.value if not hasattr(c.value, "isoformat") else c.value.isoformat() for c in row]
                for row in ws.iter_rows(max_row=min(ws.max_row, 60))]
        out[ws.title] = {"dimensions": ws.dimensions, "charts": len(ws._charts), "rows": rows}
    return out


def outline(path):
    """The outline as a dict, or None for a file type it doesn't cover."""
    kind = {".docx": docx, ".pptx": pptx, ".xlsx": xlsx}.get(Path(path).suffix.lower())
    return kind(path) if kind else None


if __name__ == "__main__":
    print(json.dumps(outline(sys.argv[1]), ensure_ascii=False, indent=1, default=str))

#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
annotate_apply.py — render highlight and blacken annotations from a JSON spec.

Usage:
    python3 annotate_apply.py spec.json

Spec format:
    {
      "source": "/path/to/input.pdf",
      "output": "/path/to/output.pdf",
      "annotations": [
        {
          "type": "highlight",
          "page": 0,
          "rect": {"x0": 72, "top": 100, "x1": 310, "bottom": 114},
          "color": "yellow"
        },
        {
          "type": "blacken",
          "page": 1,
          "rect": {"x0": 200, "top": 540, "x1": 480, "bottom": 556}
        }
      ]
    }

Rect coordinates follow pdfplumber's system: top-left origin, y increases downward.
Colors for highlight: "yellow" (default), "green", "pink".

When the spec contains any blacken, the script rasterizes the entire
output PDF after applying overlays so no extractable text remains
anywhere (real redaction, not just visual cover). See
_flatten_to_image_pdf for the why and the trade-offs.

Prints the output path and touched page indices (0-based) on stdout.
"""

import io
import json
import sys
from collections import defaultdict
from pathlib import Path

import pypdfium2 as pdfium
from pypdf import PdfReader, PdfWriter
from reportlab.lib.colors import Color
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas as rl_canvas

COLORS = {
    "yellow": Color(1.00, 0.94, 0.00, alpha=0.45),
    "green":  Color(0.42, 0.83, 0.42, alpha=0.45),
    "pink":   Color(1.00, 0.71, 0.76, alpha=0.45),
}

PAD    = 2.0  # highlight padding (points, each side)
RADIUS = 3.0  # highlight corner radius (points)

# Rasterization config used when the spec contains any blacken — the
# whole PDF is re-rendered as images so no extractable text remains.
# 200 DPI is screen-grade legible; JPEG quality 92 keeps file size
# reasonable without visible artifacts on text.
RASTER_DPI     = 200
JPEG_QUALITY   = 92


def _build_overlay(page_w: float, page_h: float, annots: list[dict]) -> PdfReader:
    buf = io.BytesIO()
    c = rl_canvas.Canvas(buf, pagesize=(page_w, page_h))
    for a in annots:
        r = a["rect"]
        x0, x1 = float(r["x0"]), float(r["x1"])
        # pdfplumber 'top'/'bottom' count from the top of the page;
        # reportlab y counts from the bottom — flip both edges.
        rl_bot = page_h - float(r["bottom"])
        rl_top = page_h - float(r["top"])
        w = x1 - x0
        h = rl_top - rl_bot

        # Each annotation gets its own graphics state so fill colour /
        # alpha can't bleed from one into the next (e.g. a highlight's
        # alpha=0.45 leaking into a subsequent blacken).
        c.saveState()
        t = a["type"]
        if t == "highlight":
            c.setFillColor(COLORS.get(a.get("color", "yellow"), COLORS["yellow"]))
            c.roundRect(
                x0 - PAD, rl_bot - PAD,
                w + 2 * PAD, h + 2 * PAD,
                RADIUS, fill=1, stroke=0,
            )
        elif t == "blacken":
            c.setFillColor(Color(0, 0, 0, alpha=1.0))
            c.rect(x0, rl_bot, w, h, fill=1, stroke=0)
        else:
            print(f"Warning: unknown annotation type {t!r} — skipped", file=sys.stderr)
        c.restoreState()

    c.save()
    buf.seek(0)
    return PdfReader(buf)


def _flatten_to_image_pdf(pdf_bytes: bytes, dpi: int = RASTER_DPI) -> bytes:
    """Re-render every page as a raster image and rebuild the PDF.

    After this transform the PDF contains no text objects — only embedded
    images. Any overlays (highlight, blacken) become pixels; text
    extraction (pdftotext, pdfplumber, copy/paste) returns nothing. This
    is the redaction guarantee for blacken: the text the overlay covers
    is no longer present in the file.

    Side effect: text on EVERY page becomes non-selectable and
    non-searchable. That's the price of real redaction — partial
    flattening would leak the redacted term wherever else it appears.
    """
    src_doc = pdfium.PdfDocument(pdf_bytes)
    src_reader = PdfReader(io.BytesIO(pdf_bytes))
    writer = PdfWriter()
    scale = dpi / 72.0

    for page_idx, src_page in enumerate(src_reader.pages):
        page_w = float(src_page.mediabox.width)
        page_h = float(src_page.mediabox.height)

        img = src_doc[page_idx].render(scale=scale).to_pil()
        if img.mode != "RGB":
            img = img.convert("RGB")

        img_buf = io.BytesIO()
        img.save(img_buf, format="JPEG", quality=JPEG_QUALITY, optimize=True)
        img_buf.seek(0)

        pdf_buf = io.BytesIO()
        c = rl_canvas.Canvas(pdf_buf, pagesize=(page_w, page_h))
        c.drawImage(ImageReader(img_buf), 0, 0, width=page_w, height=page_h)
        c.save()
        pdf_buf.seek(0)

        writer.add_page(PdfReader(pdf_buf).pages[0])

    out_buf = io.BytesIO()
    writer.write(out_buf)
    return out_buf.getvalue()


def main() -> None:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} spec.json", file=sys.stderr)
        sys.exit(1)

    spec = json.loads(Path(sys.argv[1]).read_text())
    src, dst = spec["source"], spec["output"]

    by_page: dict[int, list[dict]] = defaultdict(list)
    for a in spec["annotations"]:
        by_page[int(a["page"])].append(a)

    has_blacken = any(a["type"] == "blacken" for a in spec["annotations"])

    reader = PdfReader(src)
    writer = PdfWriter()

    for idx, page in enumerate(reader.pages):
        if idx in by_page:
            box = page.mediabox
            overlay = _build_overlay(float(box.width), float(box.height), by_page[idx])
            page.merge_page(overlay.pages[0])
        writer.add_page(page)

    Path(dst).parent.mkdir(parents=True, exist_ok=True)

    if has_blacken:
        intermediate = io.BytesIO()
        writer.write(intermediate)
        flattened = _flatten_to_image_pdf(intermediate.getvalue(), dpi=RASTER_DPI)
        Path(dst).write_bytes(flattened)
        print(f"Written: {dst} (rasterized — no extractable text remains)")
    else:
        with open(dst, "wb") as f:
            writer.write(f)
        print(f"Written: {dst}")

    touched = sorted(by_page)
    print(f"Touched pages (0-based): {touched}")


if __name__ == "__main__":
    main()

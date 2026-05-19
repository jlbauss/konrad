#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
pdf_helpers.py — Region discovery and highlight emission for the pdf skill.

Importable module, not a CLI. The skill's `edit.md` recipes use these
helpers to avoid re-deriving coordinate flips and per-page iteration.

Typical import dance from agent code:

    import sys
    sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
    from pdf_helpers import anchor_bands, highlight_rects

What's here:

    find_words(pdf_path, predicate, fields=None)
        Yield every word matching predicate(word) across all pages.
        Pass `fields=("text", "x0", "top")` (or similar) to get slim
        dicts for probe-style structure inspection — saves ~5x on
        output bytes vs the default full word dict.

    pdf_rect_from_pdfplumber(word, page_height)
        Convert a pdfplumber word bbox (top-left origin) to a PDF-native
        rect (x1, y1, x2, y2) with bottom-left origin.

    anchor_bands(pdf_path, anchor, height_above, height_below, ...)
        Build horizontal bands anchored to each match. Optional `stop_at`
        clamps the band's bottom edge to just above the nearest matching
        word below the anchor (within stop_at_max_distance).

    highlight_rects(src, rects, dst, color="ffff00")
        Take [(page_index, (x1, y1, x2, y2))] in PDF-native coords and
        emit Highlight annotations.

All region-returning helpers yield PDF-native rects so the output of one
can feed straight into highlight_rects without further conversion.
"""

from __future__ import annotations

from typing import Callable, Iterable, Iterator, Optional

import pdfplumber
from pypdf import PdfReader, PdfWriter
from pypdf.annotations import Highlight
from pypdf.generic import ArrayObject, FloatObject


# Word predicates take a pdfplumber word dict. The dict has at least:
#   "text", "x0", "x1", "top", "bottom"
WordPredicate = Callable[[dict], bool]

# A rect is PDF-native (bottom-left origin): (x1, y1, x2, y2) where
# y1 < y2 (y1 is the lower edge, y2 is the upper edge).
Rect = tuple[float, float, float, float]
PageRect = tuple[int, Rect]


def pdf_rect_from_pdfplumber(word: dict, page_height: float) -> Rect:
    """Convert one pdfplumber word bbox to a PDF-native rect.

    pdfplumber: origin top-left, with top < bottom numerically.
    PDF native: origin bottom-left, with y1 (bottom) < y2 (top).
    """
    return (
        float(word["x0"]),
        page_height - float(word["bottom"]),
        float(word["x1"]),
        page_height - float(word["top"]),
    )


def find_words(
    pdf_path: str,
    predicate: WordPredicate,
    *,
    fields: Optional[tuple[str, ...]] = None,
) -> Iterator[tuple[int, "pdfplumber.page.Page", dict]]:
    """Yield (page_index, page, word) for every word matching predicate.

    The page object is yielded too so callers can read page.width /
    page.height without reopening the document.

    `fields` controls the shape of the yielded word dict:

    - `None` (default) — yield the full pdfplumber word dict (~10 fields
      including bbox, doctop, direction, etc.). Use this when you need
      bbox info to build rects (the text-search highlight recipe etc.).
    - A tuple of field names — yield a slim dict containing only those
      keys. Use this for probing the document structure when you only
      want to print summary info; a typical choice is
      `("text", "x0", "top")`. Five-times smaller output than the full
      dict; matters when probing returns many matches.

    The predicate always receives the full word dict, so position /
    bbox filters keep working regardless of `fields`. Only the yielded
    word is slim.
    """
    with pdfplumber.open(pdf_path) as pdf:
        for i, page in enumerate(pdf.pages):
            for word in page.extract_words():
                if predicate(word):
                    if fields is None:
                        yield i, page, word
                    else:
                        yield i, page, {k: word[k] for k in fields}


def anchor_bands(
    pdf_path: str,
    anchor: WordPredicate,
    *,
    height_above: float = 0.0,
    height_below: float = 0.0,
    stop_at: Optional[WordPredicate] = None,
    stop_at_max_distance: float = 200.0,
    stop_at_padding: float = 5.0,
    left: Optional[float] = None,
    right: Optional[float] = None,
) -> list[PageRect]:
    """Build horizontal bands anchored to each match of `anchor`.

    For each matching word, the band's vertical extent is:
        top    = anchor.top - height_above
        bottom = anchor.top + height_below
                 (or, if stop_at is given and a match is found within
                  stop_at_max_distance below the anchor, clamped to
                  nearest_stop.top - stop_at_padding)

    Horizontal extent defaults to the full page width (left=0,
    right=page.width). Pass `left` / `right` to override.

    Returns [(page_index, (x1, y1, x2, y2))] in PDF-native coords —
    feeds directly into highlight_rects().
    """
    bands: list[PageRect] = []
    with pdfplumber.open(pdf_path) as pdf:
        for i, page in enumerate(pdf.pages):
            words = page.extract_words()
            anchors = [w for w in words if anchor(w)]
            if not anchors:
                continue
            page_width = float(page.width)
            page_height = float(page.height)
            x1 = left if left is not None else 0.0
            x2 = right if right is not None else page_width
            for a in anchors:
                top_plumb = float(a["top"]) - height_above
                bottom_plumb = float(a["top"]) + height_below
                if stop_at is not None:
                    below = [
                        w for w in words
                        if stop_at(w)
                        and float(w["top"]) > float(a["top"])
                        and float(w["top"]) - float(a["top"]) <= stop_at_max_distance
                    ]
                    if below:
                        nearest = min(below, key=lambda w: float(w["top"]))
                        bottom_plumb = float(nearest["top"]) - stop_at_padding
                if top_plumb < 0:
                    top_plumb = 0.0
                if bottom_plumb > page_height:
                    bottom_plumb = page_height
                if bottom_plumb <= top_plumb:
                    continue
                y1 = page_height - bottom_plumb
                y2 = page_height - top_plumb
                bands.append((i, (x1, y1, x2, y2)))
    return bands


def highlight_rects(
    src: str,
    rects: Iterable[PageRect],
    dst: str,
    *,
    color: str = "ffff00",
) -> int:
    """Emit Highlight annotations for each (page_index, rect) and write
    the annotated PDF to `dst`. Returns the number of annotations added.

    `color` is a 6-char hex string without leading '#'. Default is yellow.
    """
    reader = PdfReader(src)
    writer = PdfWriter(clone_from=reader)
    count = 0
    for page_idx, (x1, y1, x2, y2) in rects:
        if y1 > y2:
            y1, y2 = y2, y1
        if x1 > x2:
            x1, x2 = x2, x1
        quad = ArrayObject([
            FloatObject(x1), FloatObject(y2),  # top-left
            FloatObject(x2), FloatObject(y2),  # top-right
            FloatObject(x1), FloatObject(y1),  # bottom-left
            FloatObject(x2), FloatObject(y1),  # bottom-right
        ])
        writer.add_annotation(
            page_number=page_idx,
            annotation=Highlight(
                rect=(x1, y1, x2, y2),
                quad_points=quad,
                highlight_color=color,
            ),
        )
        count += 1
    with open(dst, "wb") as out:
        writer.write(out)
    return count

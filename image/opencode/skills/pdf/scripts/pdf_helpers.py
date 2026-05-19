#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
pdf_helpers.py — discovery primitives for the ANNOTATE route.

Two helpers, both yielding **pdfplumber-native** records (top-left origin,
y increases downward). The `x0` / `x1` / `top` / `bottom` fields can be
copied straight into an `annotate_apply.py` spec — no coordinate flips
needed; the script handles the conversion to PDF-native internally.

Typical import:

    import sys
    sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
    from pdf_helpers import find_words, find_lines

API:

    find_words(pdf_path, predicate, *, fields=None)
        Yield (page_idx, page, word_dict) for every word matching the
        predicate. word_dict comes from pdfplumber's extract_words().

    find_lines(pdf_path, predicate, *, fields=None)
        Yield (page_idx, page, line_dict) for every line matching the
        predicate. line_dict comes from pdfplumber's extract_text_lines().

Both dicts include at minimum: `text`, `x0`, `x1`, `top`, `bottom`
(in points, pdfplumber's top-left coord system). The page object is
yielded too so callers can read `page.width` / `page.height` without
reopening the document.

`fields` controls the shape of the yielded dict:

  - None      — full dict (default; use when you need the bbox to build rects)
  - tuple     — slim dict with only those keys (for probe-style structure prints)

Slim probes are ~5× smaller per match. Use them while surveying document
structure, then drop `fields=` when you move from probing to building rects.
"""

from __future__ import annotations

from typing import Callable, Iterator, Optional

import pdfplumber

Predicate = Callable[[dict], bool]


def _iter_matches(
    pdf_path: str,
    extractor: str,
    predicate: Predicate,
    fields: Optional[tuple[str, ...]],
) -> Iterator[tuple[int, "pdfplumber.page.Page", dict]]:
    with pdfplumber.open(pdf_path) as pdf:
        for i, page in enumerate(pdf.pages):
            for item in getattr(page, extractor)():
                if predicate(item):
                    yield i, page, (item if fields is None else {k: item[k] for k in fields})


def find_words(
    pdf_path: str,
    predicate: Predicate,
    *,
    fields: Optional[tuple[str, ...]] = None,
) -> Iterator[tuple[int, "pdfplumber.page.Page", dict]]:
    """Yield (page_idx, page, word_dict) for every word matching predicate."""
    yield from _iter_matches(pdf_path, "extract_words", predicate, fields)


def find_lines(
    pdf_path: str,
    predicate: Predicate,
    *,
    fields: Optional[tuple[str, ...]] = None,
) -> Iterator[tuple[int, "pdfplumber.page.Page", dict]]:
    """Yield (page_idx, page, line_dict) for every line matching predicate."""
    yield from _iter_matches(pdf_path, "extract_text_lines", predicate, fields)

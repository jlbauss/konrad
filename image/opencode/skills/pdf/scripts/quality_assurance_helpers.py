#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
quality_assurance_helpers.py — Rasterize touched pages for visual
quality assurance of PDF deliverables.

Importable module, not a CLI. Feeds the **`quality-assurance` skill**
(at `~/.config/opencode/skills/quality-assurance/SKILL.md`), which
governs the verification cycle this helper supports.

Typical import dance from agent code:

    import sys
    sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
    from quality_assurance_helpers import rasterize_touched

Default behavior writes PNGs into a fresh tempdir (caller is responsible
for cleanup). Pass `persist_to=<path>` to drop the images into a known
directory instead — used on verification failure to leave evidence
under `/workspace/.agent/quality-assurance/<timestamp>/` (auto-pruned
>7d by konrad).
"""

from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Iterable, Optional

from pdf2image import convert_from_path


def rasterize_touched(
    pdf_path: str,
    page_indices: Iterable[int],
    *,
    dpi: int = 100,
    persist_to: Optional[Path] = None,
) -> tuple[Path, list[Path]]:
    """Rasterize the selected pages of `pdf_path` to PNG.

    Args:
        pdf_path: Path to the PDF.
        page_indices: 0-based page indices to rasterize. Duplicates are
            deduplicated; order in the returned list is ascending.
        dpi: 100 is the default — sufficient for routine placement-grade
            checks (highlight covers the right area, watermark legible,
            FreeText in the right spot, FILL value in its field). Vision
            cost on most APIs scales with pixel count, so dpi=100 vs
            dpi=150 is roughly half the per-page token cost. Push to
            dpi=150 when annotation alignment precision matters (off-by-
            a-few-points coord-flip bugs); dpi=200+ only when print-grade
            precision is needed (sub-pixel font rendering, etc.).
        persist_to: If None, a fresh tempdir is created and returned —
            the caller owns cleanup. If a Path is given, that directory
            is used (created if needed) and survives the process. Use
            this on verification failure to keep evidence.

    Returns:
        (output_dir, [paths]) — output_dir is the directory containing
        the PNGs; paths are the rasterized files in ascending page order.
        File naming: `page_<one-based-3-digit>.png`.
    """
    if persist_to is None:
        out_dir = Path(tempfile.mkdtemp(prefix="pdfqa_"))
    else:
        out_dir = Path(persist_to)
        out_dir.mkdir(parents=True, exist_ok=True)

    paths: list[Path] = []
    for idx in sorted(set(page_indices)):
        pages = convert_from_path(
            pdf_path,
            dpi=dpi,
            first_page=idx + 1,
            last_page=idx + 1,
        )
        out = out_dir / f"page_{idx + 1:03d}.png"
        pages[0].save(out, "PNG")
        paths.append(out)
    return out_dir, paths

#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
font_helpers.py — bridge between konrad's bundled font palette and reportlab.

Background: konrad ships seven OFL font families at /usr/local/share/fonts/
konrad/ and an optional user overlay at /home/node/.local/share/fonts/konrad-
user/. Everything fontconfig-aware (Typst, Playwright, LibreOffice) finds
them automatically. **reportlab does not read fontconfig** — it maintains
its own registry. This helper resolves family names to file paths and
registers them with reportlab in one call, so skill recipes can say
`setFont(register_font("Inter"), 11)` instead of hardcoding "Helvetica"
or hand-rolling per-weight registrations.

Typical import:

    import sys
    sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
    from font_helpers import register_font, available_families

API:

    register_font(family)
        Register `family` with reportlab (idempotent — calling twice is
        cheap). Returns the registered family name string, which is what
        you pass to canvas.setFont() or to the rich-text `<font face=...>`
        tag. Raises FontNotFound if no matching files exist.

    available_families()
        Return the sorted list of family names that register_font() can
        resolve right now — baked + overlay.

Conventions:

  * The baked palette uses Regular / Italic / Bold / BoldItalic for static
    families, and a single variable file for Fraunces. The helper
    registers all available weights and wires them up via
    registerFontFamily so reportlab's bold/italic switching works.

  * Overlay fonts under ~/.local/share/fonts/konrad-user/ are picked up
    if they follow the `<Family>-<Weight>.ttf` (or `.otf`) naming, where
    Weight ∈ {Regular, Italic, Bold, BoldItalic}. Family-name matching
    is case-insensitive; a single-file overlay (Family.ttf) is also
    accepted as the Regular weight.

  * The helper memoizes registrations — calling `register_font("Inter")`
    in three recipes during one process registers Inter once.

See references/fonts.md for the family catalogue.
"""

from __future__ import annotations

import os
from pathlib import Path

from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.pdfbase.ttfonts import TTFont

BAKED_DIR = Path("/usr/local/share/fonts/konrad")
OVERLAY_DIR = Path("/home/node/.local/share/fonts/konrad-user")

# Canonical family name → on-disk subdirectory under BAKED_DIR.
# Family names match the strings the agent should pass to register_font()
# and to canvas.setFont() (after registration).
_BAKED_FAMILIES: dict[str, str] = {
    "Inter": "Inter",
    "Source Serif 4": "SourceSerif4",
    "Fraunces": "Fraunces",
    "JetBrains Mono": "JetBrainsMono",
    "EB Garamond": "EBGaramond",
    "IBM Plex Sans": "IBMPlexSans",
    "Atkinson Hyperlegible": "AtkinsonHyperlegible",
}

# Weight slug used in filenames → (reportlab variant suffix, is_italic, is_bold)
# Source Serif 4 uses "It" / "BoldIt" instead of "Italic" / "BoldItalic";
# everything else follows the canonical form.
_WEIGHT_VARIANTS = [
    ("Regular", "", False, False),
    ("Italic", "-Italic", True, False),
    ("It", "-Italic", True, False),
    ("Bold", "-Bold", False, True),
    ("BoldItalic", "-BoldItalic", True, True),
    ("BoldIt", "-BoldItalic", True, True),
]

_registered: set[str] = set()


class FontNotFound(RuntimeError):
    """No font files found for the requested family."""


def _candidate_files(family: str) -> list[tuple[Path, str, bool, bool]]:
    """Find all on-disk font files for `family`.

    Returns a list of (path, variant_suffix, italic, bold) tuples in
    registration order. Searches the baked palette first, then the
    overlay. Returns an empty list if nothing matches.
    """
    found: list[tuple[Path, str, bool, bool]] = []
    seen_variants: set[str] = set()

    # Baked palette — canonical naming, predictable layout.
    if family in _BAKED_FAMILIES:
        baked_subdir = BAKED_DIR / _BAKED_FAMILIES[family]
        if baked_subdir.is_dir():
            stem = _BAKED_FAMILIES[family]
            for weight_slug, suffix, italic, bold in _WEIGHT_VARIANTS:
                if suffix in seen_variants:
                    continue
                path = baked_subdir / f"{stem}-{weight_slug}.ttf"
                if path.is_file():
                    found.append((path, suffix, italic, bold))
                    seen_variants.add(suffix)
            # Variable font fallback (Fraunces): one file covers Regular.
            if not found:
                for path in sorted(baked_subdir.glob("*.ttf")):
                    italic = "Italic" in path.name
                    suffix = "-Italic" if italic else ""
                    if suffix not in seen_variants:
                        found.append((path, suffix, italic, False))
                        seen_variants.add(suffix)

    # Overlay — case-insensitive family-name matching, looser naming.
    if OVERLAY_DIR.is_dir():
        lc_family = family.lower().replace(" ", "")
        for path in sorted(OVERLAY_DIR.glob("*.ttf")) + sorted(OVERLAY_DIR.glob("*.otf")):
            stem = path.stem
            lc_stem = stem.lower().replace(" ", "").replace("-", "")
            if not lc_stem.startswith(lc_family):
                continue
            tail = stem[len(family.replace(" ", "")):].lstrip("-")
            for weight_slug, suffix, italic, bold in _WEIGHT_VARIANTS:
                if tail == weight_slug and suffix not in seen_variants:
                    found.append((path, suffix, italic, bold))
                    seen_variants.add(suffix)
                    break
            else:
                # Bare "<Family>.ttf" or anything we didn't classify → Regular.
                if not tail and "" not in seen_variants:
                    found.append((path, "", False, False))
                    seen_variants.add("")

    return found


def register_font(family: str) -> str:
    """Register `family` with reportlab; return the family name to use in setFont().

    Idempotent: subsequent calls for the same family are no-ops.
    """
    if family in _registered:
        return family

    candidates = _candidate_files(family)
    if not candidates:
        raise FontNotFound(
            f"No font files found for {family!r}. "
            f"Looked in {BAKED_DIR}/<family>/ and {OVERLAY_DIR}/. "
            f"Use available_families() to list what's installed."
        )

    family_kwargs: dict[str, str] = {}
    for path, suffix, italic, bold in candidates:
        ps_name = f"{family}{suffix}"
        pdfmetrics.registerFont(TTFont(ps_name, str(path)))
        if not italic and not bold:
            family_kwargs["normal"] = ps_name
        elif italic and not bold:
            family_kwargs["italic"] = ps_name
        elif bold and not italic:
            family_kwargs["bold"] = ps_name
        else:
            family_kwargs["boldItalic"] = ps_name

    if "normal" in family_kwargs:
        registerFontFamily(family, **family_kwargs)
    _registered.add(family)
    return family


def available_families() -> list[str]:
    """Return the families register_font() can resolve right now."""
    families: set[str] = set()
    for fam in _BAKED_FAMILIES:
        if _candidate_files(fam):
            families.add(fam)
    if OVERLAY_DIR.is_dir():
        for path in list(OVERLAY_DIR.glob("*.ttf")) + list(OVERLAY_DIR.glob("*.otf")):
            stem = path.stem
            for weight_slug, _, _, _ in _WEIGHT_VARIANTS:
                if stem.endswith(f"-{weight_slug}"):
                    fam = stem[: -(len(weight_slug) + 1)]
                    families.add(fam)
                    break
            else:
                families.add(stem)
    return sorted(families)


if __name__ == "__main__":  # pragma: no cover — sanity probe
    fams = available_families()
    print(f"Available font families ({len(fams)}):")
    for f in fams:
        marker = "[baked]" if f in _BAKED_FAMILIES else "[overlay]"
        print(f"  {marker} {f}")
    # Smoke test: register each baked family.
    for f in _BAKED_FAMILIES:
        if f in fams:
            try:
                register_font(f)
                print(f"  registered: {f}")
            except Exception as e:  # noqa: BLE001
                print(f"  FAILED:     {f}: {e}")

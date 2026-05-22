# Fonts

konrad ships a curated typographic palette and a small helper that wires
each family into reportlab on demand. Everything fontconfig-aware (Typst,
Playwright, LibreOffice) discovers the same set automatically through the
system font path.

## The palette

Seven families, all SIL Open Font License 1.1, baked into the image at
`/usr/local/share/fonts/konrad/`. Each ships Regular / Italic / Bold /
BoldItalic, except **Fraunces** which ships as a variable font.

| Family | Role | When to reach for it |
|---|---|---|
| **Inter** | UI / body sans | Default sans-serif. Designed for screens, excellent at small sizes, broad Latin coverage. |
| **Source Serif 4** | Body serif | General-purpose serif. Pairs cleanly with Inter; good language coverage. |
| **EB Garamond** | Literary serif | Long-form prose, classical / book-like documents. More personality than Source Serif. |
| **Fraunces** | Display | Headlines, posters, distinctive titling. Variable font (opsz / soft / wonk axes). |
| **IBM Plex Sans** | Corporate sans | Neutral alternative to Inter for corporate-feeling output. Latin Extended only. |
| **Atkinson Hyperlegible** | Accessibility | When readability outranks style — signage, forms, low-vision contexts. Designed by the Braille Institute. |
| **JetBrains Mono** | Code / mono | Code listings, console output, anything where columns matter. |

Pick by *use* first, *aesthetic* second:

- **Body text in a document** → Inter (sans) or Source Serif 4 (serif).
- **Long-form prose / a book-feeling doc** → EB Garamond.
- **A title that wants to be loud** → Fraunces (variable opsz axis lets the
  display weight read as a single typeface across sizes).
- **A code block** → JetBrains Mono.
- **A form a user fills in or signage** → Atkinson Hyperlegible.

## Using a font in reportlab

reportlab does not read fontconfig — it has its own registry. Use
`font_helpers.register_font()` to bridge:

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from font_helpers import register_font

body = register_font("Inter")            # → "Inter"
title = register_font("Fraunces")        # → "Fraunces"

c.setFont(body, 11)                       # Regular weight
c.setFont(f"{body}-Bold", 14)             # Bold variant
c.setFont(f"{body}-Italic", 11)           # Italic
c.setFont(f"{body}-BoldItalic", 11)       # Bold italic
```

`register_font()` is idempotent — calling it three times in three recipes
during one process registers the font once. It raises `FontNotFound` if
the family isn't installed (typo, or the user removed it from the
overlay).

`available_families()` lists what's registerable right now (baked +
overlay) — useful when an agent needs to enumerate options instead of
guessing names.

For the `<font face="…">` tag inside reportlab's rich-text strings, pass
the same string you got back from `register_font()`.

### Variable fonts (Fraunces)

Fraunces ships as one variable file rather than four static weights.
`register_font("Fraunces")` registers the default fvar instance — that's
the Regular weight at the default opsz/soft/wonk axis positions. The
`{family}-Bold` / `-Italic` variants are not available for Fraunces;
reach for a static-weight family if you need explicit bold/italic
switching.

## Using a font in Typst, Playwright, LibreOffice

These all use fontconfig and find the palette automatically. Refer to
families by their canonical names — `"Inter"`, `"Source Serif 4"`,
`"Fraunces"`, etc. — in the tool's native syntax (`text(font: "Inter", …)`
in Typst, `font-family: 'Source Serif 4'` in CSS, the font-picker in
LibreOffice).

## Script coverage

The curated palette covers Latin / Latin Extended / Cyrillic / Greek
(plus Vietnamese in Inter and Fraunces). Konrad also installs
`fonts-noto-core` from Debian, which adds broad Unicode fallback for
Arabic, Hebrew, Devanagari, Bengali, Tamil, Thai, Tibetan, Ethiopic,
Khmer, Lao, Myanmar, and more. fontconfig handles fallback automatically
— if a glyph isn't in the requested family, the renderer pulls it from
the best-matching Noto face.

**Not covered out of the box:**

- **CJK** (Chinese / Japanese / Korean). `fonts-noto-cjk` is ~50 MB and
  was deliberately not baked in. If a user needs CJK, point them at the
  overlay path below — they can drop the relevant Noto TTC files into
  `~/.config/konrad/fonts/` and konrad picks them up on the next launch.
- **Emoji.** No font in the baked palette ships colour-emoji tables.
  Same fix: drop `NotoColorEmoji.ttf` into the overlay.

If a generated document has tofu boxes where a script should be, that's
the diagnosis — the script isn't in either the curated palette or
`fonts-noto-core`. QA's `rasterize_touched` + vision check catches this
reliably; the watermark / FreeText / annotation per-op checklists in
[qa.md](../qa.md) name "fonts render — not boxes, not tofu" explicitly.

## Adding your own fonts

Drop `.ttf` / `.otf` / `.ttc` files into `~/.config/konrad/fonts/` on the
host. konrad bind-mounts the directory into the container, symlinks it
into `~/.local/share/fonts/`, and runs `fc-cache -f` on every launch.

For reportlab specifically, follow the naming convention
`<FamilyName>-<Weight>.ttf` where Weight ∈ {Regular, Italic, Bold,
BoldItalic} — then `register_font("YourFamilyName")` finds it. A single
`YourFamily.ttf` (no weight suffix) is also accepted as the Regular
weight. For fontconfig-aware tools, naming doesn't matter; the
embedded family name inside the font file is what gets matched.

The overlay layers on top of the baked palette — collisions are resolved
in fontconfig's standard precedence (more-specific path wins). To
replace a baked family entirely, ship a same-named file in the overlay.

## Attribution

All seven families are SIL OFL 1.1. Per-family copyright notices ship at
`/usr/local/share/fonts/konrad/<family>/LICENSE.txt` inside the image
and are mirrored in this repo at `image/fonts/konrad/<family>/`. The
consolidated list is in the project's `NOTICE` file.

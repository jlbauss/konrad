# EDIT — merge, split, rotate, watermark, annotate, encrypt, images, metadata

For operations whose output is another PDF derived from an existing one
(or, for image extraction, image files derived from one). Backed by
**pypdf** for almost everything; **pdf2image** when you need rasterized
pages; **poppler-utils** (`pdfimages`) for raw image extraction;
**reportlab** for building text-watermark overlays; and **pdfplumber**
when annotations need to find words on the page by string.

If the user wants to produce a brand-new PDF with no input document
(a one-page note, a cover sheet on its own), route to
[generate.md](generate.md) instead — that's GENERATE, not EDIT.

Every snippet below writes files into `/workspace/` by default. Match the
user's chosen output path; don't write into the skill folder.

## Merge

```python
from pypdf import PdfReader, PdfWriter

writer = PdfWriter()
for src in ["a.pdf", "b.pdf", "c.pdf"]:
    reader = PdfReader(src)
    for page in reader.pages:
        writer.add_page(page)

with open("/workspace/merged.pdf", "wb") as out:
    writer.write(out)
```

If the user gives a page range per source, use `reader.pages[i:j]`
slicing — `i` is 0-based.

## Split

### One PDF per page

```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("input.pdf")
for i, page in enumerate(reader.pages, start=1):
    w = PdfWriter()
    w.add_page(page)
    with open(f"/workspace/page_{i:03d}.pdf", "wb") as out:
        w.write(out)
```

### A specific page range into one PDF

```python
reader = PdfReader("input.pdf")
w = PdfWriter()
# user says "pages 5–12" → 0-based slice [4:12]
for page in reader.pages[4:12]:
    w.add_page(page)
with open("/workspace/pages_5_to_12.pdf", "wb") as out:
    w.write(out)
```

When the user gives page numbers, confirm whether they mean 1-based
("page 1 is the first page", almost always) or 0-based. Output filenames
should use the 1-based numbers the user gave.

## Rotate

`page.rotate(degrees)` accepts multiples of 90. Positive = clockwise.

```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("input.pdf")
w = PdfWriter()
for i, page in enumerate(reader.pages):
    if i == 2:                # rotate page 3 (1-based)
        page.rotate(90)
    w.add_page(page)
with open("/workspace/rotated.pdf", "wb") as out:
    w.write(out)
```

To rotate every page by the same angle, drop the conditional.

> **QA**: rotation has a visual deliverable — see [qa.md](qa.md) and
> rasterize the rotated page(s) to verify orientation and no clipping
> before reporting.

## Watermark

Two modes: stamping with an **existing watermark PDF** (preferred when
the user has one), or building a **text overlay** on the fly (the narrow
"create" exception).

### From an existing watermark PDF

The watermark PDF should be a single page sized to match (or be smaller
than) the target pages. Transparent backgrounds work best.

```python
from pypdf import PdfReader, PdfWriter

watermark = PdfReader("watermark.pdf").pages[0]
reader = PdfReader("input.pdf")
w = PdfWriter()
for page in reader.pages:
    page.merge_page(watermark)
    w.add_page(page)
with open("/workspace/watermarked.pdf", "wb") as out:
    w.write(out)
```

### From a text string (overlay built on the fly)

Keep the overlay contents to the user-supplied text — don't bolt on
logos, decorations, or extra pages. (For overlays with arbitrary text at
arbitrary positions on the page, see [Annotations](#annotations) below —
`FreeText` is the right primitive for "put this caption here".)

Three things matter for a watermark that actually looks like a watermark:

1. The overlay's page size must match the **target page's `MediaBox`**, not be hardcoded to letter — otherwise the overlay's centre lands off-centre on A4, A5, legal, etc.
2. The font must scale to the **page diagonal**, not be a fixed point size. 72 pt looks tiny on any real page; sizing relative to the diagonal gives a watermark that spans most of the page regardless of paper size.
3. `drawCentredString(x, y, text)` puts the text **baseline** at `y`, not its visual midline. Offset by ~⅓ of the font size so the cap-height passes through the page centre.

```python
import io
from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas
from reportlab.lib.colors import Color


def build_text_watermark(
    text: str,
    page_size: tuple[float, float],
    *,
    font_size: float | None = None,
    opacity: float = 0.25,
) -> "PdfReader":
    """One-page overlay sized to `page_size`, with `text` rotated 45°
    and visually centred. `font_size` defaults to diagonal/8."""
    w, h = page_size
    if font_size is None:
        font_size = ((w * w + h * h) ** 0.5) / 8

    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=page_size)
    c.saveState()
    c.translate(w / 2, h / 2)
    c.rotate(45)
    c.setFillColor(Color(0.5, 0.5, 0.5, alpha=opacity))
    c.setFont("Helvetica-Bold", font_size)
    c.drawCentredString(0, -font_size * 0.35, text)   # cap-height on midline
    c.restoreState()
    c.save()
    buf.seek(0)
    return PdfReader(buf)


reader = PdfReader("input.pdf")
writer = PdfWriter()
for page in reader.pages:
    box  = page.mediabox
    size = (float(box.width), float(box.height))
    overlay = build_text_watermark("DRAFT", size).pages[0]
    page.merge_page(overlay)
    writer.add_page(page)
with open("/workspace/watermarked.pdf", "wb") as out:
    writer.write(out)
```

A fresh overlay is built per page so it matches each page's exact
`MediaBox`. For PDFs with mixed page sizes (booklets, mixed-format
reports) this is correct. For uniform PDFs it's mildly wasteful — feel
free to lift the `build_text_watermark` call out of the loop if the
first page's size is representative.

> **QA**: watermarks need visual verification — see [qa.md](qa.md).
> Sample three pages (first / middle / last) and check legibility,
> opacity, and that nothing got clipped. Common parametric failures
> (too dark, too small, off-centre) are retry-eligible up to twice.

## Annotations

Highlight passages, drop a sticky note, paint a free-text caption onto
the page, or frame an area with a box. Backed by `pypdf.annotations`
(part of the pypdf install). For "highlight every instance of *invoice*"
or any other find-and-mark workflow, pair with `pdfplumber` to locate the
word bounding boxes.

### Coordinate primer (read once, refer back)

Two coordinate systems collide here:

- **PDF native** (what pypdf annotations expect): origin at the **bottom-left**
  of the page, units in **points** (1/72 inch), so the top-left corner of a
  page is `(0, page_height)`.
- **pdfplumber** word bboxes: origin at the **top-left**, units in **points**,
  with `x0, x1, top, bottom` fields where `top < bottom` numerically.

The skill ships a helper to do the conversion so you don't have to flip
signs by hand — `pdf_rect_from_pdfplumber(word, page_height)` in
`scripts/pdf_helpers.py`. The recipes below use it via the named helpers
(`find_words`, `anchor_bands`, `highlight_rects`); reach for the
primitive directly only when assembling a one-off rect.

### Helpers cheat sheet

All recipes in this section import from the same module. Repeat this
three-line dance at the top of any annotation script — `scripts/` isn't
on the Python path by default:

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import (
    find_words,          # word-level discovery
    anchor_bands,        # label-anchored horizontal band discovery
    highlight_rects,     # emit Highlight annotations for a list of rects
    pdf_rect_from_pdfplumber,  # one-off coord flip
)
```

| Helper | Returns | When to reach for it |
|---|---|---|
| `find_words(pdf, predicate, *, fields=None)` | iterator of `(page_idx, page, word)` | discovery that doesn't fit a named pattern. Pass `fields=("text", "x0", "top")` for slim probe output |
| `anchor_bands(pdf, anchor, height_above, height_below, stop_at=None, ...)` | `[(page_idx, rect)]` | horizontal bands anchored to a label or marker word |
| `highlight_rects(src, rects, dst, color="ffff00")` | int (annotation count) | emit Highlight annotations once you have rects |
| `pdf_rect_from_pdfplumber(word, page_height)` | `(x1, y1, x2, y2)` PDF-native | one word's bbox, primitive use |

### Highlight by coordinates

When you already know the rect — coordinates dictated by the user, read
from a layout file, or computed from a structural cue — feed it straight
to `highlight_rects`. Skip the manual writer/quad_points dance.

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import highlight_rects

# rect is (x1, y1, x2, y2) in PDF-native coords (bottom-left origin).
rects = [
    (0, (100, 600, 300, 620)),  # page 0, one rect
]
count = highlight_rects("input.pdf", rects, "/workspace/highlighted.pdf")
print(f"Added {count} highlights")
```

For a word's bbox specifically: use `pdf_rect_from_pdfplumber(word,
page.height)` to flip pdfplumber's top-left coords to PDF-native, then
pass `[(page_idx, rect)]` into `highlight_rects`.

### Highlight by text (search + mark)

`find_words` returns every word matching your predicate; convert each
match to a rect via `pdf_rect_from_pdfplumber`; emit with
`highlight_rects`. The whole pattern is six lines:

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import find_words, pdf_rect_from_pdfplumber, highlight_rects

target = "invoice"
src    = "input.pdf"

rects = [
    (page_idx, pdf_rect_from_pdfplumber(word, float(page.height)))
    for page_idx, page, word
    in find_words(src, lambda w: w["text"].strip(".,;:()[]").lower() == target.lower())
]
count = highlight_rects(src, rects, "/workspace/highlighted.pdf")
print(f"Highlighted {count} match(es) of '{target}'")
```

Match semantics worth surfacing to the user before running:

- `extract_words()` (used inside `find_words`) returns whitespace-separated
  tokens, so this finds whole-word matches only — "invoice" won't match
  inside "invoiced".
- Punctuation is stripped above with `.strip(".,;:()[]")`; adjust for the
  user's actual text.
- Comparison is case-insensitive here; drop the `.lower()` calls for
  case-sensitive matching.
- For multi-word phrases, `extract_words()` won't span tokens — use
  pdfplumber's `page.search(pattern, regex=True)` directly, or fall back
  to a per-line scan. Tracked under Future features in ROADMAP.

### Region discovery — finding what to highlight

The recipes above cover the degenerate case where the rect to highlight
**is the matched word**. The richer case — highlighting a *region*
around the matched word — decomposes into three steps regardless of
what the region looks like:

1. **Find anchors** — words matching a predicate (text, position, font,
   whatever's distinctive).
2. **Expand to a region** — turn each anchor into the rect to highlight
   (a horizontal band, a paragraph, a column, a line).
3. **Emit** — feed the rects into `highlight_rects`.

`anchor_bands` is the named primitive for step 2 when the region is a
**horizontal band**. Before reaching for it, probe the document
structure (next subsection) so the anchor predicate matches what's
actually there.

### Probing the structure (always do this first — it is not optional)

Before reaching for `anchor_bands`, you **must** probe the document to
see what the anchor candidates actually look like. Writing the anchor
predicate from your head — based on what the user said the regions are —
is the single most common failure mode for this class of task. Probe
first, then pick the predicate from what you see.

**The user's description of a region rarely matches the document's
literal label for it.** Section headings are often coded (`§3.1`,
`Art. IV`, `Q-7`); staff or column labels are often single characters;
callout markers are often symbols or abbreviations. When a user asks
to highlight "every section" / "every question" / "every chapter", the
document's actual anchor text may be `§`, `Q:`, `Ch.`, or a single
letter — not the descriptive word the user used. The whole point of
probing is to discover what's there, so do not assume.

Two rules for probe output:

1. **Slim print.** Pass `fields=("text", "x0", "top")` to `find_words`
   so each match yields a 3-field dict instead of the full ~10-field
   pdfplumber word dict. About 5× smaller output per match. On a
   document with hundreds of candidate matches, this is the difference
   between a clean probe and a truncated one.
2. **Stop once you've seen the pattern.** For a regular document, after
   5–10 matches you know the cluster of anchor positions. Don't dump
   200 rows that all say the same thing — slice the iterator or break
   out once positions stabilize.

The canonical first probe — generic enough to surface most anchor
shapes (single-char staff labels, `Q:` / `§N` markers, "Note:" /
"Chorus:" / "Warning:" callouts, short numeric codes):

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import find_words

src = "input.pdf"

for page_idx, _, w in find_words(
    src,
    lambda w: w["x0"] < 80 and len(w["text"]) <= 12,
    fields=("text", "x0", "top"),
):
    print(f"p{page_idx:2d}  {w['text']!r:>14}  x0={w['x0']:5.1f}  top={w['top']:6.1f}")
```

Run this **before** writing a narrower predicate. Look at the output.
The labels that repeat across pages at consistent `(text, x0, top)`
positions are your anchor candidates. The label the user *named* is
probably **not** the label in the document — it's a description of what
the labels point to.

Adjust the filter if needed: relax `len(text) <= 12` if your expected
labels are longer; raise `x0 < 80` if the layout puts anchors past the
80-pt left margin; tighten one or the other if body text is leaking
into the output.

For an irregular layout (a page break that shifts everything, an
inserted heading that moves the markers), you'll see the anomalies in
the same print and can pick a `stop_at` predicate that adapts.

Slim print is for probing only. When you move from probe to highlight,
drop `fields=` so the yielded word has bbox info — you'll need it to
build rects via `pdf_rect_from_pdfplumber`.

### Highlight label-anchored bands

`anchor_bands` builds horizontal bands anchored to each match of an
`anchor` predicate. Per match, the band extends from
`anchor.top - height_above` down to either `anchor.top + height_below`
(fixed offset, when the layout is regular) or to just above the nearest
match of an optional `stop_at` predicate below (adaptive, when the
per-block height varies). Horizontal extent defaults to the full page
width and can be clipped via `left` / `right`.

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import anchor_bands, highlight_rects

bands = anchor_bands(
    "input.pdf",
    anchor=lambda w: ...,           # whatever marks the start of each band
    height_above=...,
    height_below=...,               # fixed fallback height
    stop_at=lambda w: ...,          # optional: clamp to nearest match below
    stop_at_max_distance=...,       # optional: cap how far below to search
)
highlight_rects("input.pdf", bands, "/workspace/out.pdf")
```

Parameter notes:

- **`anchor`**: a predicate over pdfplumber word dicts (`text`, `x0`,
  `x1`, `top`, `bottom`). Combine text predicates with position filters
  to avoid false hits in body text. The Probing subsection above is
  how you decide what the predicate should be.
- **`height_above` / `height_below`**: fixed offsets in points. Sufficient
  on regular layouts; combine with `stop_at` for variable per-block height.
- **`stop_at`**: optional. When given, the band's bottom edge is clamped
  to just above the nearest matching word below the anchor (within
  `stop_at_max_distance`, default 200 pt). Adapts to whatever the next
  block actually is — the same `stop_at` works across pages where the
  spacing differs.
- **`left` / `right`**: horizontal clipping. Default to full page width.

Some shapes this primitive covers (anchor / stop_at predicates are
sketches — adapt to your document):

| Region shape | `anchor` predicate sketch | `stop_at` predicate sketch |
|---|---|---|
| One band per labeled section | label text + left-margin position filter | the same label predicate (next section) |
| One band per Q&A pair | opening marker (`"Q:"` etc.) | the same opening marker |
| One band per callout / note | callout label | callout label, or page-edge fallback |
| One band per row in a tagged list | tag text at known column | next tag |

**Sanity-check the match count before reporting.** If the user asked
for "every X" / "all Y" / "each Z" and `anchor_bands` returned 0, 1, or
2 matches on a multi-page document, your anchor predicate is almost
certainly wrong. Go back to the probe, broaden the filter, look at what
the document actually has, pick a new predicate. Don't ship 1 highlight
when the user asked for "every" — that's a silent failure that the user
won't catch until they open the file. The shape you want is "32
matches for 32 anchors", not "1 match because the literal word the user
used appears once in the title."

For region shapes that aren't horizontal bands — paragraph bboxes,
column regions, font-anchored runs — drop down to `find_words` and
assemble rects directly, or wait on the day-2 region-discovery helpers
tracked in ROADMAP.

### Sticky note (Text annotation)

A pin anchored to a point, with the comment visible on click.

```python
from pypdf.annotations import Text

writer.add_annotation(
    page_number=0,
    annotation=Text(
        rect=(100, 700, 120, 720),   # tiny rect — viewers render it as an icon
        text="Check this figure against Q3 numbers.",
        open=False,                   # True opens the popup by default
    ),
)
```

The `rect` is the clickable region for the pin icon; the body of the
comment lives in `text` and shows up in the popup. Most viewers render
the icon at a fixed visual size regardless of `rect`'s dimensions, but
giving it a small square keeps the on-page footprint honest.

### Free-text overlay (caption painted onto the page)

For arbitrary text at an arbitrary position — captions, labels, footers
added per page.

```python
from pypdf.annotations import FreeText

writer.add_annotation(
    page_number=0,
    annotation=FreeText(
        text="Figure 1: revised after audit",
        rect=(100, 80, 400, 100),
        font="Helvetica",
        font_size="11pt",
        font_color="000000",          # hex without leading #
        background_color="ffffff",    # set to None for transparent
        border_color=None,
    ),
)
```

Distinct from the watermark overlay above: a `FreeText` annotation is a
proper annotation object (the PDF spec calls it `/Subtype /FreeText`), not
a merged content stream. It can be edited or removed later by tools that
respect annotations; a watermark cannot, because it's baked into the page
content.

### Box, line, frame

To draw attention to an area without adding text:

```python
from pypdf.annotations import Rectangle, Line

# Box around an area
writer.add_annotation(
    page_number=0,
    annotation=Rectangle(rect=(100, 600, 300, 700)),
)

# Arrow / underline-style line
writer.add_annotation(
    page_number=0,
    annotation=Line(p1=(100, 590), p2=(300, 590)),
)
```

`Polyline` (open path) and `Polygon` (closed path) are available the same
way when a single line or rectangle isn't enough.

### Underline / strikethrough / squiggly

These share the `Highlight` family of annotation subtypes in the PDF spec
(§12.5.6.10) but pypdf doesn't ship dedicated wrapper classes for all of
them. Two options:

1. Use a `Rectangle` or thin `Line` along the baseline of the word — works
   for emphasis-style underlines.
2. Construct the annotation directly using `pypdf.generic.DictionaryObject`
   with `/Subtype /Underline` (or `/StrikeOut` / `/Squiggly`) and the same
   `quad_points` shape as `Highlight`. Same coordinate rules apply.

If the user specifically needs strikethrough on legal redaction-style
output, surface that **annotation strikethrough is not real redaction** —
the underlying text remains in the file. True redaction (content removal)
is out of scope for this skill.

### Reporting annotations

After annotating, tell the user the same as any edit (path, page count)
plus:

- How many annotations were added, broken down by type
- For text-search highlights: the search term used and the match count
  per page
- That annotations are non-destructive (the underlying content is
  unchanged) — useful framing when the user expected redaction

> **QA**: annotations are the highest-stakes operation in this skill
> for visual correctness — a coord flip lands the highlight on the
> wrong word silently. **Always** rasterize every touched page and
> verify against [qa.md](qa.md)'s highlight/FreeText/box checklists
> before reporting. Parametric failures (highlight extends slightly
> past the word, FreeText off by a known offset) are retry-eligible up
> to twice; structural failures (wrong word, overlapping body content,
> wrong page) escalate to the user immediately with the evidence
> images.

## Encrypt / decrypt

### Add a password

```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("input.pdf")
w = PdfWriter()
for page in reader.pages:
    w.add_page(page)
w.encrypt(user_password="user_pw", owner_password="owner_pw")
with open("/workspace/encrypted.pdf", "wb") as out:
    w.write(out)
```

`user_password` is the password needed to open the document.
`owner_password` is the one that allows changing permissions. Setting
them to the same value is the common case.

### Remove a password

```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("encrypted.pdf")
if reader.is_encrypted:
    reader.decrypt("the_password")

w = PdfWriter()
for page in reader.pages:
    w.add_page(page)
with open("/workspace/decrypted.pdf", "wb") as out:
    w.write(out)
```

If `reader.decrypt(...)` returns `0`, the password was wrong — surface
this to the user and stop.

## Extract images

### Raw embedded images (preserves original format)

The fastest, most faithful path is `pdfimages` from poppler-utils. It
extracts images exactly as embedded — no re-compression, original colour
space.

```bash
mkdir -p /workspace/images
pdfimages -all input.pdf /workspace/images/img
# Files: /workspace/images/img-000.jpg, img-001.png, ...
```

Use `-j` instead of `-all` to keep only JPEGs in their native form (other
formats get converted to PPM); `-all` keeps everything in its original
format.

### Images per page via pypdf (useful when you need page context)

```python
from pypdf import PdfReader

reader = PdfReader("input.pdf")
for page_num, page in enumerate(reader.pages, start=1):
    for j, img in enumerate(page.images):
        with open(f"/workspace/images/p{page_num:03d}_{j}.{img.name.split('.')[-1]}", "wb") as f:
            f.write(img.data)
```

### Rasterize whole pages to PNG (for thumbnails / previews)

Use this when the user wants "an image of page N", not "the images
inside page N".

```python
from pdf2image import convert_from_path

pages = convert_from_path("input.pdf", dpi=200)
for i, img in enumerate(pages, start=1):
    img.save(f"/workspace/page_{i:03d}.png", "PNG")
```

`dpi=200` is a good default for legibility; `dpi=100` is fine for thumbs;
`dpi=300+` only if the user explicitly wants print-ready output.

## Read or update metadata

```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("input.pdf")
meta = reader.metadata
print(meta.title, meta.author, meta.subject, meta.creator, meta.producer)

w = PdfWriter(clone_from=reader)
w.add_metadata({
    "/Title":   "New title",
    "/Author":  "Jane Doe",
    "/Subject": "Quarterly update",
})
with open("/workspace/with_meta.pdf", "wb") as out:
    w.write(out)
```

Keys must start with `/` and use the PDF metadata names (`/Title`,
`/Author`, `/Subject`, `/Keywords`, `/Creator`, `/Producer`,
`/CreationDate`, `/ModDate`).

## Reporting

After each edit, tell the user:
- Output path
- Page count of the result
- **QA verdict** (for ops that earn QA — see [qa.md](qa.md)'s applies
  matrix): pass, pass-with-caveat, fail (with evidence dir), or skipped
  (with the reason — no vision or user opt-out)
- For merges: which source files contributed in which order
- For splits: how many files were written
- For watermarks: text mode vs file mode
- For annotations: count by type, search term + per-page match count for
  text-search highlights, and that annotations don't alter the underlying
  content (not redaction)
- For encryption changes: that the file is now encrypted / decrypted
  (don't print the password back)
- For image extraction: how many images were written

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

Conversion (pdfplumber → PDF native):

```python
y_pdf_bottom = page.height - word["bottom"]   # lower edge in PDF coords
y_pdf_top    = page.height - word["top"]      # upper edge in PDF coords
rect = (word["x0"], y_pdf_bottom, word["x1"], y_pdf_top)
```

Annotations attach to a writer page by **page index** (0-based). The
writer must be cloned from the reader so pages stay editable:

```python
from pypdf import PdfReader, PdfWriter

reader = PdfReader("input.pdf")
writer = PdfWriter(clone_from=reader)
# ... add annotations to writer ...
with open("/workspace/annotated.pdf", "wb") as out:
    writer.write(out)
```

The recipes below assume that `reader` / `writer` pair is already set up.

### Highlight by coordinates

```python
from pypdf.annotations import Highlight
from pypdf.generic import ArrayObject, FloatObject

x1, y1, x2, y2 = 100, 600, 300, 620   # bottom-left, top-right (PDF coords)
quad = ArrayObject([FloatObject(v) for v in (x1, y2, x2, y2, x1, y1, x2, y1)])

writer.add_annotation(
    page_number=0,
    annotation=Highlight(rect=(x1, y1, x2, y2), quad_points=quad),
)
```

`quad_points` is a flat array of 8 floats per highlighted quad: top-left,
top-right, bottom-left, bottom-right (each as x, y). For a single
axis-aligned rect, the four corners of `rect` in that order — that's what
the snippet above does. To highlight multiple non-contiguous rects in one
annotation (e.g. a word that wraps across two lines), extend `quad_points`
with another 8 floats per additional quad.

### Highlight by text (search + mark)

```python
import pdfplumber
from pypdf import PdfReader, PdfWriter
from pypdf.annotations import Highlight
from pypdf.generic import ArrayObject, FloatObject

target = "invoice"
src    = "input.pdf"

reader = PdfReader(src)
writer = PdfWriter(clone_from=reader)

with pdfplumber.open(src) as pdf:
    for page_index, plumb_page in enumerate(pdf.pages):
        for word in plumb_page.extract_words():
            if word["text"].strip(".,;:()[]").lower() != target.lower():
                continue
            x1, x2 = word["x0"], word["x1"]
            y1 = plumb_page.height - word["bottom"]   # lower edge
            y2 = plumb_page.height - word["top"]      # upper edge
            quad = ArrayObject(
                [FloatObject(v) for v in (x1, y2, x2, y2, x1, y1, x2, y1)]
            )
            writer.add_annotation(
                page_number=page_index,
                annotation=Highlight(
                    rect=(x1, y1, x2, y2), quad_points=quad
                ),
            )

with open("/workspace/highlighted.pdf", "wb") as out:
    writer.write(out)
```

Match semantics worth surfacing to the user before running:

- `extract_words()` returns whitespace-separated tokens, so this finds
  whole-word matches only — "invoice" won't match inside "invoiced".
- Punctuation is stripped above with `.strip(".,;:()[]")`; adjust for the
  user's actual text.
- Comparison is case-insensitive in this snippet; drop the `.lower()` calls
  for case-sensitive matching.
- For multi-word phrases, `extract_words()` won't span tokens — use
  `page.search(pattern, regex=True)` (pdfplumber 0.11+) or roll a per-line
  scan instead.

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

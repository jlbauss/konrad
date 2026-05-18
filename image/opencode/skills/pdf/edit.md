# EDIT — merge, split, rotate, watermark, encrypt, images, metadata

For operations whose output is another PDF (or, for image extraction,
image files). Backed by **pypdf** for almost everything; **pdf2image**
when you need rasterized pages; **poppler-utils** (`pdfimages`) for raw
image extraction; and **reportlab** for the single small case of building
a text-watermark overlay.

> Reminder: generating a PDF "from scratch" (designed report, resume,
> cover layout) is out of scope. The text-watermark overlay below is the
> sole narrow exception — it builds a one-page transparent overlay so the
> user-facing op is still "stamp a watermark onto an existing PDF".

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

This is the only place this skill creates a PDF. Keep the overlay
contents to the user-supplied text — don't bolt on logos, decorations,
or extra pages.

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
- For merges: which source files contributed in which order
- For splits: how many files were written
- For watermarks: text mode vs file mode
- For encryption changes: that the file is now encrypted / decrypted
  (don't print the password back)
- For image extraction: how many images were written

# EDIT — merge, split, rotate, encrypt, images, metadata

For structural PDF operations: combining and splitting files, rotating
pages, password protection, extracting embedded images, reading and
writing metadata. Backed by **pypdf** for most things, **pdf2image**
for whole-page rasterization, and **poppler-utils** (`pdfimages`) for
raw image extraction.

For anything that **draws content onto a page** (highlight, blacken,
sticky note, free-text, box, line, watermark), see [annotate.md](annotate.md)
— ANNOTATE, not EDIT.

For a brand-new PDF with no input document, see [generate.md](generate.md)
— GENERATE, not EDIT.

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

> **Verify**: rotation has a visual deliverable — invoke the
> **`quality-assurance`** skill and rasterize the rotated page(s) to
> check orientation and no clipping before reporting. Per-op checks
> in [checklists.md](checklists.md#rotate).

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
- **Quality-assurance verdict** (for ops that earn it — see the
  applies matrix in [checklists.md](checklists.md#when-does-pdf-earn-verification)):
  pass, pass-with-caveat, fail (with evidence dir), or skipped (with
  the reason — no vision or user opt-out)
- For merges: which source files contributed in which order
- For splits: how many files were written
- For encryption changes: that the file is now encrypted / decrypted
  (don't print the password back)
- For image extraction: how many images were written

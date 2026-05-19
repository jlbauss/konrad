# GENERATE — produce a new PDF from scratch

For deliverables that don't start from an existing PDF: a cover sheet, a
one-page note, a quick test fixture. Distinct from [EDIT](edit.md), which
mutates an input document, and from [EXTRACT](extract.md), which reads one.

## Status

**This route is intentionally minimal right now.** The full design — themed
templates, structured content trees, designed reports, resumes, multi-page
layouts — is parked in `ROADMAP.md` under Future features.

If the user wants polished output (designed report, branded cover, resume),
say so plainly: this skill can produce a bare-bones page, but it won't look
designed. Offer two options:

1. They bring an existing document and we [EDIT](edit.md) it.
2. They accept a minimal `reportlab` page now and we revisit when the full
   GENERATE pipeline lands.

## Bare-bones page

Single page, default size A4, one block of text. This is the same
`reportlab` machinery the watermark overlay uses — no new dependencies.

```python
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.pdfgen import canvas

c = canvas.Canvas("/workspace/out.pdf", pagesize=A4)
w, h = A4

c.setFont("Helvetica-Bold", 18)
c.drawString(2 * cm, h - 3 * cm, "Title goes here")

c.setFont("Helvetica", 11)
c.drawString(2 * cm, h - 4 * cm, "Body line one.")
c.drawString(2 * cm, h - 4.5 * cm, "Body line two.")

c.showPage()
c.save()
```

`pagesize` accepts `A4`, `letter`, `legal`, `A5`, etc. from
`reportlab.lib.pagesizes`. Coordinates are in points (1/72 in.) with the
origin at the **bottom-left** of the page. `cm` and `inch` from
`reportlab.lib.units` make the call sites readable.

For multi-page output, call `c.showPage()` between pages and lay out each
page's content before the next `showPage()`.

> **QA**: generated output needs visual verification — see [qa.md](qa.md).
> Rasterize the page(s) and check text fits, no clipping at right or
> bottom edges, fonts render (not tofu/boxes), and layout matches what
> the user asked for. Parametric failures (text overruns the page) are
> retry-eligible up to twice; structural failures (wrong content) go
> straight to the user.

## What this route deliberately does not do

- Themed templates, style sheets, or design tokens — no typography or
  colour decisions get made here.
- Content trees / structured documents (headings → sections → paragraphs
  with automatic flow). `reportlab.platypus` would be the entry point and
  is available, but isn't wrapped here yet — bring it in when the
  Future-features bullet lands.
- HTML-to-PDF (Playwright, WeasyPrint). Not in the image. Adding it is part
  of the same Future-features bullet.

## Reporting

After generating a PDF, tell the user:

- Output path
- Page count
- Page size used (A4, Letter, etc.) if it wasn't the default
- **QA verdict** (see [qa.md](qa.md)): pass, pass-with-caveat, fail
  (with evidence dir), or skipped
- That the page is bare-bones — no design — and that polished output is on
  the roadmap, not in this skill today

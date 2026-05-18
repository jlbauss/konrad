---
name: pdf
description: >
  Work with PDF files: extract text, convert to Markdown or JSON, chunk
  for RAG, analyze structure, merge, split, rotate, watermark, encrypt or
  decrypt, extract images, read or update metadata, and fill in PDF form
  fields. Use this skill any time the user mentions a `.pdf` file, says
  "parse / convert / OCR / extract text from this", "merge these PDFs",
  "split these pages", "rotate page 3", "add a watermark", "remove the
  password", "extract the images", "fill in this form", or asks to chunk
  a PDF for ingestion. Trigger on PDF intent even when the file extension
  is not spelled out — "the report attached", "this scanned document",
  "the form they sent me" all count when context makes the PDF obvious.
license: GPL-3.0-only
compatibility: >
  Requires Python 3.10+. pypdf, pdfplumber, pdf2image, reportlab, and
  docling-slim[standard] are preinstalled in the konrad image's
  /opt/venv. poppler-utils is available system-wide for rasterization
  and raw image extraction.
metadata:
  author: konrad
  version: "1.0"
  # Attribution for borrowed content lives in the project-level NOTICE at
  # the repo root: minimax-pdf (MIT) for the FILL route, docling-project
  # (MIT) for the EXTRACT route.
---

# PDF skill

Three task families, three reference docs. Pick the one that matches the
user's intent and follow it. The references are deliberately separated
because each has its own conventions (CLI vs Python, coordinate systems,
JSON shapes) and loading all of them at once is just noise.

## Out of scope

Generating new PDFs from scratch (cover layouts, designed reports, resumes)
is **deliberately not covered**. If the user asks for that, say so and ask
whether they want to bring an existing document to edit, or whether they
can switch to a tool that specializes in PDF generation. The one small
exception is the text-watermark overlay in [edit.md](edit.md), which builds
a single transparent overlay page to stamp onto an existing document — the
user-facing operation is still "add a watermark", not "create a PDF".

## Route table

| User intent | Route | Read |
|---|---|---|
| Extract text / convert / parse / OCR / chunk / analyze structure | **EXTRACT** | [extract.md](extract.md) |
| Merge, split, rotate, watermark, encrypt/decrypt, extract images, read or set metadata | **EDIT** | [edit.md](edit.md) |
| Fill in form fields in an existing PDF | **FILL** | [forms.md](forms.md) |

**When in doubt between EXTRACT and EDIT**: if the deliverable is text (or
chunks, or a JSON tree of the document), it's EXTRACT. If the deliverable
is another PDF, it's EDIT.

**When in doubt between EDIT and FILL**: form fields are AcroForm widgets
that show up when `fill_inspect.py` lists them. If the PDF has no fillable
fields and the user wants text written onto specific positions on the page,
that's not in scope for this skill — say so and ask how they'd like to
proceed (re-create the form with fillable fields, or use a different tool).

## Working conventions

- **Working directory.** Default output dir is `/workspace` (or whichever
  path the user gives). Don't write into the skill folder itself.
- **Script paths.** Scripts in this skill live at `scripts/` *relative to
  this file*. Invoke them with their full path under the skill folder:
  `python3 ~/.config/opencode/skills/pdf/scripts/fill_inspect.py …`. The
  short form `python3 scripts/…` only works if you've cd'd into the skill
  folder, which you usually shouldn't.
- **Report what you did.** When you produce an output file, tell the user
  the path, the page count (for PDFs), and any non-default flags you used.
  For extraction, also report whether OCR ran (the konrad image only ships
  docling's standard pipeline with RapidOCR — see [extract.md](extract.md)).

## Dependencies

These are preinstalled in the konrad image, so usually nothing to do:

| Library / tool | Used for | Where |
|---|---|---|
| `docling` | EXTRACT — text/conversion/chunking/structure | Python venv |
| `pypdf` | EDIT (merge/split/rotate/watermark/encrypt), FILL | Python venv |
| `pdfplumber` | EDIT — text/table extraction fallback | Python venv |
| `pdf2image` | EDIT — rasterize pages to PNG/JPG | Python venv |
| `reportlab` | EDIT — build the text-watermark overlay | Python venv |
| `poppler-utils` | EDIT — `pdfimages` raw image extract, `pdftotext` quick extract | apt |

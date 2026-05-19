---
name: pdf
description: >
  Work with PDF files: extract text, convert to Markdown or JSON, chunk
  for RAG, analyze structure, merge, split, rotate, watermark, encrypt or
  decrypt, extract images, read or update metadata, annotate (highlight,
  sticky note, free-text overlay, frame), fill in PDF form fields, and
  generate a bare-bones PDF from scratch. Use this skill any time the
  user mentions a `.pdf` file, says "parse / convert / OCR / extract text
  from this", "merge these PDFs", "split these pages", "rotate page 3",
  "add a watermark", "remove the password", "extract the images",
  "highlight this passage", "add a sticky note", "fill in this form",
  "make me a one-page PDF", or asks to chunk a PDF for ingestion. Trigger
  on PDF intent even when the file extension is not spelled out — "the
  report attached", "this scanned document", "the form they sent me" all
  count when context makes the PDF obvious.
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

Four task families, four reference docs. Pick the one that matches the
user's intent and follow it. The references are deliberately separated
because each has its own conventions (CLI vs Python, coordinate systems,
JSON shapes) and loading all of them at once is just noise.

## Route table

| User intent | Route | Read |
|---|---|---|
| Extract text / convert / parse / OCR / chunk / analyze structure | **EXTRACT** | [extract.md](extract.md) |
| Merge, split, rotate, watermark, encrypt/decrypt, extract images, read or set metadata, highlight / annotate | **EDIT** | [edit.md](edit.md) |
| Fill in form fields in an existing PDF | **FILL** | [forms.md](forms.md) |
| Generate a new PDF from scratch (minimal — see route for scope) | **GENERATE** | [generate.md](generate.md) |

**When in doubt between EXTRACT and EDIT**: if the deliverable is text (or
chunks, or a JSON tree of the document), it's EXTRACT. If the deliverable
is another PDF derived from an input PDF, it's EDIT.

**When in doubt between EDIT and GENERATE**: EDIT mutates or annotates an
**existing** PDF. GENERATE produces a brand-new PDF with no input document.
A user who hands you a PDF and asks for "a cover page in front of this" is
EDIT (merge a generated overlay onto their file). A user who asks for "a
one-page PDF that says X" with no input file is GENERATE.

**When in doubt between EDIT and FILL**: form fields are AcroForm widgets
that show up when `fill_inspect.py` lists them. If the PDF has no fillable
fields and the user wants text written onto specific positions on the
page, FILL doesn't apply — but EDIT's `FreeText` annotation (see
[edit.md](edit.md#annotations)) can paint text at given coordinates as
an annotation. That's not "real" form filling (no AcroForm widget, no
roundtrip through form tools) but it's the right answer when the user
just needs filled-in text on a scanned or flat form. Surface the
trade-off before choosing.

## Working conventions

- **Working directory.** Default output dir is `/workspace` (or whichever
  path the user gives). Don't write into the skill folder itself.
- **Script paths.** Scripts in this skill live at `scripts/` *relative to
  this file*. Two patterns, depending on the script:
  - **CLI scripts** (`fill_inspect.py`, `fill_write.py`) — invoke with
    the full path: `python3 ~/.config/opencode/skills/pdf/scripts/fill_inspect.py …`.
  - **Importable helper modules** (`pdf_helpers.py`, `qa_helpers.py`) —
    insert the scripts dir on `sys.path` first:
    ```python
    import sys
    sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
    from pdf_helpers import anchor_bands, highlight_rects
    ```
    Every recipe in `edit.md` / `qa.md` that uses helpers repeats this
    three-line dance at the top — copy it.
- **Use the shipped helpers; don't reinvent.** When a recipe says "use
  `anchor_bands`" or "use `rasterize_touched`", reach for the helper
  rather than reimplementing the coordinate flip / per-page iteration /
  tempdir creation. The helpers exist because re-deriving them per task
  is where weak models lose the thread. Drop down to raw `pdfplumber` /
  `pypdf` / `convert_from_path` only when the recipe explicitly says so
  or your task doesn't fit a named pattern.
- **To *see* a PDF, rasterize. To *parse* a PDF, extract.** The agent's
  `read` tool doesn't return useful image content for `.pdf` files — it
  returns a stub. If you need to look at the page (layout questions,
  annotation verification), rasterize via `rasterize_touched` from
  `qa_helpers` and read the PNG. If you need to know what's on the page
  (text content, word positions), use `pdfplumber.extract_words()` or
  `find_words` from `pdf_helpers` — text extraction is dramatically
  cheaper than rasterize-and-look.
- **Extract before you rasterize when probing layout.** If you're trying
  to understand a PDF's structure before working on it, start with
  `find_words` to inspect text + positions. Only rasterize if text
  alone doesn't tell you enough (typically: graphical-heavy documents,
  scanned pages, music scores where labels matter but glyph soup
  doesn't). Rasterize-then-read is the most expensive probe in this
  skill — earn it before reaching for it.
- **Slim-print when probing with `find_words`.** Pass
  `fields=("text", "x0", "top")` so each match yields a 3-field dict
  instead of the full ~10-field pdfplumber word dict. About 5× smaller
  per-match output; matters on documents with hundreds of candidate
  matches where the full-dict default can fill opencode's tool-output
  buffer and force truncation. Drop `fields=` when you move from probe
  to highlight — recipes that build rects via `pdf_rect_from_pdfplumber`
  need the full bbox info.
- **Visually QA outputs that have a visual deliverable.** After EDIT
  (watermark, annotations, rotate), GENERATE, or FILL produce a PDF,
  rasterize the touched pages and look at them yourself before reporting.
  See [qa.md](qa.md) for the rasterization recipe, the per-op checklist,
  the retry policy (max 2 parametric retries; zero for structural
  failures), and the evidence-directory convention on failure. Skip QA
  for non-visual ops (encrypt/decrypt, metadata, EXTRACT) — qa.md lists
  the full applies/skips matrix.
- **After `rasterize_touched`, you have exactly two acceptable next
  moves**: (a) read each returned PNG with your image-reading tool and
  render the verdict based on what you actually saw, or (b) say "QA
  skipped" in the final report with a reason ("my model can't read
  images", "user said skip", etc.). Reporting "pass" without reading
  the PNGs is a contract violation — it's the most common dishonest QA
  pattern this skill sees. If you didn't look, say so. See qa.md's
  post-rasterize contract for the canonical phrasings.
- **Report what you did.** When you produce an output file, tell the user
  the path, the page count (for PDFs), and any non-default flags you used.
  For extraction, also report whether OCR ran (the konrad image only ships
  docling's standard pipeline with RapidOCR — see [extract.md](extract.md)).
  After QA, include the verdict in the report — see qa.md's Reporting
  section for the exact phrasings (pass / pass-with-caveat / fail / QA
  skipped).

## Dependencies

These are preinstalled in the konrad image, so usually nothing to do:

| Library / tool | Used for | Where |
|---|---|---|
| `docling` | EXTRACT — text/conversion/chunking/structure | Python venv |
| `pypdf` | EDIT (merge/split/rotate/watermark/encrypt/annotate), FILL | Python venv |
| `pdfplumber` | EDIT — text/table extraction fallback, word bounding-boxes for text-search annotations | Python venv |
| `pdf2image` | EDIT — rasterize pages to PNG/JPG; QA — rasterize touched pages for vision review | Python venv |
| `reportlab` | EDIT — text-watermark overlay; GENERATE — bare-bones page output | Python venv |
| `poppler-utils` | EDIT — `pdfimages` raw image extract, `pdftotext` quick extract | apt |

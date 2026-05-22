---
name: pdf
description: >
  Work with PDF files: extract text, convert to Markdown or JSON, chunk
  for RAG, analyze structure, merge, split, rotate, watermark, encrypt or
  decrypt, extract images, read or update metadata, highlight passages,
  blacken / redact areas, fill in PDF form fields, and generate a
  bare-bones PDF from scratch. Use this skill any time the user mentions
  a `.pdf` file, says "parse / convert / OCR / extract text from this",
  "merge these PDFs", "split these pages", "rotate page 3", "add a
  watermark", "remove the password", "extract the images", "highlight
  this passage", "blacken / redact this", "fill in this form", "make me
  a one-page PDF", or asks to chunk a PDF for ingestion. Trigger on PDF
  intent even when the file extension is not spelled out — "the report
  attached", "this scanned document", "the form they sent me" all count
  when context makes the PDF obvious.
license: AGPL-3.0-only
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

Five task families, five reference docs. Pick the one that matches the
user's intent and follow it. The references are deliberately separated
because each has its own conventions (CLI vs Python, coordinate systems,
JSON shapes) and loading all of them at once is just noise.

## Route table

| User intent | Route | Read |
|---|---|---|
| Extract text / convert / parse / OCR / chunk / analyze structure | **EXTRACT** | [extract.md](extract.md) |
| Merge, split, rotate, encrypt/decrypt, extract images, read or set metadata | **EDIT** | [edit.md](edit.md) |
| Overlay anything onto the page — highlight, blacken, sticky note, free-text caption, box, line, watermark | **ANNOTATE** | [annotate.md](annotate.md) |
| Fill in form fields in an existing PDF | **FILL** | [forms.md](forms.md) |
| Generate a new PDF from scratch (minimal — see route for scope) | **GENERATE** | [generate.md](generate.md) |

**When in doubt between EXTRACT and EDIT**: if the deliverable is text (or
chunks, or a JSON tree of the document), it's EXTRACT. If the deliverable
is another PDF derived from an input PDF, it's EDIT or ANNOTATE.

**When EDIT vs ANNOTATE**: EDIT for structural ops (merge, split, rotate,
encrypt, images, metadata). ANNOTATE for anything that draws content
onto the page — highlight, blacken, sticky note, free-text, box, line,
watermark. Rule of thumb: if the change is **additive over the page**,
it's ANNOTATE; if it's **about the document as a whole**, it's EDIT.

**When ANNOTATE vs GENERATE**: ANNOTATE adds overlays to an **existing**
PDF. GENERATE produces a brand-new PDF with no input document. "Put a
cover page in front of this file" → GENERATE the cover page, then EDIT
to merge. "Stamp DRAFT on every page" → ANNOTATE.

**When ANNOTATE vs FILL**: form fields are AcroForm widgets that show up
when `fill_inspect.py` lists them. If the PDF has no fillable fields and
the user wants text written onto specific positions, FILL doesn't apply
— but ANNOTATE's free-text overlay (see [annotate.md](annotate.md#free-text-overlay))
can paint text at given coordinates. That's not "real" form filling (no
AcroForm widget) but it's the right answer for scanned or flat forms.
Surface the trade-off before choosing.

## Working conventions

- **Working directory.** Default output dir is `/workspace` (or whichever
  path the user gives). Don't write into the skill folder itself.
- **Script paths.** Scripts in this skill live at `scripts/` *relative
  to this file*.
  - **CLI scripts** (`fill_inspect.py`, `fill_write.py`, `annotate_apply.py`)
    — invoke with the full path:
    `python3 ~/.config/opencode/skills/pdf/scripts/<name>.py …`.
  - **Importable helper modules** (`pdf_helpers.py`, `qa_helpers.py`) —
    `sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")`
    then `from pdf_helpers import …`. Route docs repeat this three-line
    dance at the top of recipes that use helpers.
- **To *see* a PDF, rasterize. To *parse* a PDF, extract.** The agent's
  `read` tool doesn't return useful image content for `.pdf` files — it
  returns a stub. To look at a page, rasterize via `rasterize_touched`
  from `qa_helpers`. To know what's on a page (text, word positions),
  use `pdfplumber.extract_words()` or `find_words` from `pdf_helpers` —
  dramatically cheaper than rasterize-and-look.
- **Visually QA visual deliverables.** EDIT, ANNOTATE, GENERATE, FILL
  all produce visual output; verify before reporting. See [qa.md](qa.md)
  for the applies/skips matrix, the **progressive-verification rule
  (start with one page)**, the post-rasterize contract (read PNGs or
  declare QA skipped honestly), the retry policy, and the
  evidence-directory convention.
- **Report what you did.** Output path, page count, any non-default
  flags. For EXTRACT, report whether OCR ran. After QA, include the
  verdict using qa.md's canonical phrasings (pass / pass-with-caveat /
  fail / QA skipped).

## Dependencies

These are preinstalled in the konrad image, so usually nothing to do:

| Library / tool | Used for | Where |
|---|---|---|
| `docling` | EXTRACT — text / conversion / chunking / structure | Python venv |
| `pypdf` | EDIT (merge/split/rotate/encrypt/metadata); ANNOTATE (sticky note, free-text, box, line, overlay merging); FILL | Python venv |
| `pdfplumber` | ANNOTATE — word / line discovery for spec building (`find_words`, `find_lines`); EXTRACT — fallback table extraction | Python venv |
| `pdf2image` | QA — rasterize touched pages for vision review | Python venv |
| `pypdfium2` | ANNOTATE — whole-PDF rasterization when blacken is present (real redaction). Transitive dep of pdfplumber | Python venv |
| `reportlab` | ANNOTATE — overlay rendering for highlight / blacken / watermark / free-text; GENERATE — bare-bones page output | Python venv |
| `poppler-utils` | EDIT — `pdfimages` raw image extract | apt |

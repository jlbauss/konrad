# EXTRACT — text, conversion, chunking, structure

For text/markdown/JSON extraction from PDFs, conversion to readable
formats, chunking for RAG, and structure analysis. Backed by **docling**'s
standard PDF pipeline (CPU, with OCR via RapidOCR when needed).

docling's thread count auto-scales to the container's CPU budget (the
host sets `OMP_NUM_THREADS`), so you don't need `--num-threads` — large
documents already use the cores available to the run.

> The konrad image installs `docling-slim[standard]`, which ships with
> **RapidOCR** as the OCR engine — not EasyOCR (docling's normal default).
> The **VLM pipeline**, **Apple-MLX backend**, and alternative OCR
> engines (Tesseract, ocrmac) are **not available** here. If a document
> genuinely needs them (handwriting, formulas, very dense multi-column
> layouts), say so and stop — the user can run docling separately with
> the full install.

Use the `docling` CLI for plain conversions. Fall back to the Python API
only when you need chunking — that's the one feature the CLI doesn't
expose.

> **Use the language flavour of quality assurance for this route.**
> EXTRACT produces text / markdown / JSON, not a visual artifact, so
> the rasterize-and-look loop doesn't apply. Invoke the
> **`quality-assurance`** skill and use its language flavour. The
> concrete EXTRACT checks live in [§ Verification](#verification)
> below; the cross-skill cycle (verdict vocabulary, retry budget,
> post-verification contract) lives in the `quality-assurance` skill.

## Convert via CLI

The CLI accepts local paths and URLs.

```bash
# Markdown (default)
docling report.pdf --output /workspace/

# Structured JSON (lossless DoclingDocument)
docling report.pdf --to json --output /workspace/

# OCR engine (RapidOCR is the only one preinstalled)
docling report.pdf --ocr-engine rapidocr --output /workspace/

# Speed: skip table detection or OCR
docling report.pdf --no-tables --output /workspace/
docling report.pdf --no-ocr    --output /workspace/

# Password-protected PDF
docling secret.pdf --pdf-password "$PW" --output /workspace/
```

Output is written into `--output`, named after the input
(`report.pdf` → `report.md` or `report.json`).

CLI reference: <https://docling-project.github.io/docling/reference/cli/>

### Asking the user about format

If they don't say: Markdown for "convert this to text" / "make this
readable"; JSON for "ingest into a RAG store" / "I want to operate on
the structure".

## Convert via Python API

Use this when you need chunking. Everything else, prefer the CLI.

Docling 2.81+ requires `InputFormat` keys, not strings. Passing
`{"pdf": opts}` raises `AttributeError` on pipeline options.

```python
from docling.document_converter import DocumentConverter, PdfFormatOption
from docling.datamodel.base_models import InputFormat
from docling.datamodel.pipeline_options import PdfPipelineOptions

converter = DocumentConverter(
    format_options={
        InputFormat.PDF: PdfFormatOption(
            pipeline_options=PdfPipelineOptions(
                do_ocr=True,
                do_table_structure=True,
            ),
        ),
    }
)
result = converter.convert("report.pdf")
doc = result.document     # DoclingDocument
```

To go back to text or a JSON tree:

```python
md = doc.export_to_markdown()
js = doc.export_to_dict()
```

## Chunk for RAG (Python API only)

Default is the **hybrid chunker** — splits by heading hierarchy first,
then subdivides oversized sections by token count. This preserves
semantic boundaries while respecting context-window limits.

The tokenizer API changed in docling-core 2.8.0: pass a `BaseTokenizer`
object, not a model name string.

```python
from docling.chunking import HybridChunker
from docling_core.transforms.chunker.tokenizer.huggingface import HuggingFaceTokenizer

tokenizer = HuggingFaceTokenizer.from_pretrained(
    model_name="sentence-transformers/all-MiniLM-L6-v2",
    max_tokens=512,
)
chunker = HybridChunker(tokenizer=tokenizer, merge_peers=True)
chunks = list(chunker.chunk(doc))

for chunk in chunks:
    text = chunker.contextualize(chunk)    # full text with heading prefix
    print(chunk.meta.headings)             # heading breadcrumb
    print(chunk.meta.origin.page_no)       # source page
```

For OpenAI embedding models:

```python
import tiktoken
from docling_core.transforms.chunker.tokenizer.openai import OpenAITokenizer

tokenizer = OpenAITokenizer(
    tokenizer=tiktoken.encoding_for_model("text-embedding-3-small"),
    max_tokens=8192,
)
# Requires: uv pip install 'docling-core[chunking-openai]'
```

When reporting chunks: total count + min/max/avg token count is usually
enough. Show an example chunk only if the user asked to see them.

## Analyze structure

```python
for item, level in doc.iterate_items():
    if hasattr(item, "label") and item.label.name == "SECTION_HEADER":
        print(f"{'#' * level} {item.text}")

for table in doc.tables:
    print(table.export_to_dataframe())   # pandas DataFrame
    print(table.export_to_markdown())

for picture in doc.pictures:
    print(picture.caption_text(doc))     # caption if present
```

For a structure summary: heading tree first, then table count + figure
count, before going into detail.

## Verification

Invoke the **`quality-assurance`** skill (language flavour) after
every conversion. EXTRACT-specific checks:

- **Output exists at the expected path and is non-empty.** A zero-byte
  output on a non-empty source is the first failure to catch — it
  usually means OCR didn't run on a scanned document.
- **Page count matches.** `pdf2image` or `pdfplumber` against the
  source PDF for the page count; compare to docling's `result.pages`
  or to the number of `===` page-separator markers in the output.
- **Headings survived.** For markdown output, `grep -c '^#' output.md`
  against the visible heading count in the source. Loss of all
  headings is a structural failure (probably a wrong-pipeline issue,
  not a parameter knob).
- **Roughly-right length.** A 50-page document produces tens of
  thousands of words, not a few hundred. Order-of-magnitude check
  catches catastrophic OCR collapse.
- **No `�` replacement-character clusters.** A few are tolerable; a
  run of 20+ is a structural failure — the standard pipeline can't
  recover these, surface to the user.
- **Tables present where they're visible in the source.** For JSON
  output, `len(doc.tables)`; for markdown, search for `|---|` patterns.
  Missing tables that the user expected is a fail.

### Cost-aware reading of the deliverable

docling outputs can be **megabytes** on long documents. Don't read
the whole file to verify structure — most failure modes show up at
the boundaries.

- **Get the size first.** `ls -lh output.md` before any read.
- **Structural probe** before full read: `head -50 output.md` for
  the opening, `tail -20 output.md` for the closing, `grep -c '^#'`
  for heading count, `wc -l output.md` for line count.
- **Spot-read** for body quality: `sed -n '5000,5050p' output.md` on
  a known mid-document section, rather than reading sequentially.
- **Full read** only when the spot-read surfaced something suspicious
  and you need context, or when the file is small (under ~20 KB).

The read-window discipline costs almost nothing on small docs and
saves significant tokens on large ones — and the same set of checks
verifies the deliverable either way.

### Common failure modes and refusal points

| Symptom | Likely fix or refusal |
|---|---|
| Output near-empty on a non-empty PDF | OCR is on by default; confirm it ran (no `--no-ocr`) and that RapidOCR is selected (`--ocr-engine rapidocr`). If the document is scanned and RapidOCR struggles, **refuse**: surface to the user, propose they re-OCR with a different tool. |
| Tables missing where they're visually obvious | Drop `--no-tables` if you used it. Docling's standard table detection has known limits on dense or rotated tables; **flag honestly** rather than over-promising. |
| `�` replacement characters | The standard pipeline can't recover these. **Refuse**: tell the user, suggest re-OCRing the source with a different tool, or providing a born-digital version if one exists. |
| Reading order shuffled (multi-column) | The standard pipeline doesn't reorder. **Surface honestly** and let the user decide whether to keep the output. |
| Handwriting or formulas missed | **Refuse**: out of scope for the standard pipeline. Surface and stop. |

The unifying rule: **this skill does the standard pipeline well; it
does not silently retry with bigger hammers**. If the standard
pipeline can't handle the document, the right answer is a one-line
refusal naming what went wrong and what the user can try elsewhere.

Verdict vocabulary follows the `quality-assurance` skill: pass /
pass-with-caveat / fail / skipped-with-reason. Most EXTRACT failures
are *structural* (wrong pipeline for the document), not parametric —
the retry budget is therefore thin: at most one rerun with a
different flag (e.g. `--no-tables` if the standard pipeline crashes
on tables), then escalate.

## Edge cases

| Situation | Handling |
|---|---|
| Password-protected PDF | `--pdf-password PW`; wrong password raises `ConversionError` |
| Very large document (500+ pages) | Consider `--no-tables` for speed |
| URL behind auth | Pre-download to a temp file, then pass the local path |

## Reporting

After every conversion, tell the user:
- Output path(s)
- Page count
- Any non-default flags used (`--no-ocr`, `--no-tables`, …)
- For chunking: chunk count + token stats
- For structure analysis: heading tree summary + table count + figure count

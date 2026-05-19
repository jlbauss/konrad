# EXTRACT — text, conversion, chunking, structure

For text/markdown/JSON extraction from PDFs, conversion to readable
formats, chunking for RAG, and structure analysis. Backed by **docling**'s
standard PDF pipeline (CPU, with OCR via RapidOCR when needed).

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

> **No vision QA for this route.** EXTRACT produces text / markdown / JSON,
> not a visual artifact, so the rasterize-and-look loop in [qa.md](qa.md)
> doesn't apply. Light text-level QA (does the output have the structure
> docling promised? did headings survive? is the body roughly the right
> length?) is the agent's job in the moment. A source-vs-extracted
> cross-check loop (rasterize each page, compare with the extracted
> text) is plausible future work — flag it to the user if they want it.

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

## Quality checklist

Eyeball the output for these failure modes and re-run with different
flags if you see them. Don't iterate more than three times — instead,
summarize what worked and what didn't.

| Symptom | Likely fix |
|---|---|
| Output near-empty on a non-empty PDF | OCR is on by default; confirm it ran (no `--no-ocr`) and that RapidOCR is selected (`--ocr-engine rapidocr`). If the document is scanned and RapidOCR struggles, stop and surface the issue to the user. |
| Tables missing where they're visually obvious | Drop `--no-tables` if you used it. Docling's standard table detection has known limits on dense or rotated tables; flag this honestly rather than over-promising. |
| `�` replacement characters | The standard pipeline can't recover these. Tell the user and suggest re-OCRing the source with a different tool, or providing a born-digital version if one exists. |
| Reading order shuffled (multi-column) | The standard pipeline doesn't reorder. Surface this and let the user decide whether to keep the output. |
| Handwriting or formulas missed | Out of scope for the standard pipeline. Surface and stop. |

In short: this skill does the standard pipeline well. It does **not**
silently retry with bigger hammers — if the standard pipeline can't
handle the document, say so.

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

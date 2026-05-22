# ANNOTATE — overlays on an existing PDF

Anything that draws content **on top of** existing pages: highlights,
blackened areas, sticky notes, free-text captions, frames, lines,
watermarks. Most overlays are additive (underlying text unchanged) —
the exception is **blacken**, which triggers full-PDF rasterization
so the redacted text is actually removed from the file. See [Highlight
& blacken](#highlight--blacken) for the trade-offs.

If the deliverable is structural (merge / split / rotate / encrypt /
extract images / metadata), that's EDIT, not ANNOTATE.

| Overlay | Mechanism | Section |
|---|---|---|
| highlight | JSON spec → `annotate_apply.py` | [Highlight & blacken](#highlight--blacken) |
| blacken (real redaction)    | JSON spec → `annotate_apply.py` | [Highlight & blacken](#highlight--blacken) |
| sticky note | pypdf `Text` annotation | [Sticky note](#sticky-note) |
| free-text | pypdf `FreeText` annotation | [Free-text overlay](#free-text-overlay) |
| box / line | pypdf `Rectangle` / `Line` annotation | [Box / line](#box--line) |
| watermark | reportlab overlay merged per page | [Watermark](#watermark) |

QA is **skill-wide**: see [qa.md](qa.md) for the progressive-verification
rule (start with one page), post-rasterize contract, retry policy.

---

## Highlight & blacken

The agent finds **where** the rects go and writes them into a JSON spec.
The script applies them with fixed visual styles:

- **highlight** — 2 pt padding on each side, 3 pt rounded corners, 45 % opacity. Colors: `yellow` (default), `green`, `pink`.
- **blacken** — exact 1:1 solid black, no padding, fully opaque. **Triggers real redaction**: when the spec contains any blacken, the script rasterizes the whole output PDF at 200 DPI so no extractable text remains anywhere. See [strategy 7](#7--pii-redaction-regex-over-words) for the full trade-offs the user needs to know.

### Workflow

1. **Probe** the document to see what's actually there (see [Probing](#probing) below).
2. **Pick a strategy** that matches the user's wish (see [Strategies](#strategies-for-common-annotation-tasks) below).
3. **Build the spec** by adapting the recipe's predicate to your case.
4. **Apply** — `python3 annotate_apply.py spec.json`.
5. **QA** — see [qa.md](qa.md). One page first; expand if it passes.

Rect coords in the spec always use **pdfplumber's system** (top-left
origin, y increases downward, points). The script handles the flip to
PDF-native internally — you never compute it.

### Probing

Don't write predicates from memory. The document's literal text (anchor
labels, headings, label phrasings) rarely matches the user's description
of it. Probe first, look at what's there, then pick the predicate.

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import find_words   # or find_lines

# Survey words near the left margin — typical anchor location.
# Slim print: 3 fields per match, ~5× smaller than the full word dict.
for page_idx, _, w in find_words(
    "input.pdf",
    lambda w: w["x0"] < 80 and len(w["text"]) <= 12,
    fields=("text", "x0", "top"),
):
    print(f"p{page_idx:2d}  {w['text']!r:>14}  x0={w['x0']:5.1f}  top={w['top']:6.1f}")
```

Drop `fields=` once you move from probe to spec — building rects needs
`x1` and `bottom` too. For line-level surveys, use `find_lines`
identically — line dicts have `text`, `x0`, `x1`, `top`, `bottom`.

**Sanity-check the match count.** If the user asked for "every X" and
your predicate yields 1, the predicate is wrong — re-probe with a broader
filter, look at the document's actual anchor text, pick a new predicate.

### Strategies for common annotation tasks

Each strategy is a self-contained recipe that builds a spec and writes it
to `/workspace/spec.json`. Apply with:

```bash
python3 ~/.config/opencode/skills/pdf/scripts/annotate_apply.py /workspace/spec.json
```

Adapt the predicate / target / color in the recipe; the rest is mechanical.

#### 1 — Every occurrence of a word

```python
import sys, json
from pathlib import Path
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import find_words

src = "input.pdf"
spec = {"source": src, "output": "/workspace/highlighted.pdf", "annotations": []}

target = "invoice"
for page_idx, _, w in find_words(
    src,
    lambda w: w["text"].lower().strip(".,;:()[]") == target.lower(),
):
    spec["annotations"].append({
        "type": "highlight", "page": page_idx,
        "rect": {"x0": w["x0"], "top": w["top"], "x1": w["x1"], "bottom": w["bottom"]},
        "color": "yellow",
    })

Path("/workspace/spec.json").write_text(json.dumps(spec, indent=2))
print(f"{len(spec['annotations'])} match(es)")
```

`extract_words()` returns whitespace-separated tokens, so this matches
whole words — "invoice" won't hit inside "invoiced". Drop `.lower()`
calls for case-sensitive matching; adjust the `.strip(...)` set if
punctuation differs.

#### 2 — A specific phrase (consecutive words on one line)

```python
import sys, json
from pathlib import Path
import pdfplumber

src = "input.pdf"
spec = {"source": src, "output": "/workspace/highlighted.pdf", "annotations": []}

phrase = ["the", "contract", "terms"]  # lower-case, in order
SAME_LINE_TOL = 2.0  # points

with pdfplumber.open(src) as pdf:
    for page_idx, page in enumerate(pdf.pages):
        words = page.extract_words()
        for i in range(len(words) - len(phrase) + 1):
            window = words[i:i + len(phrase)]
            texts = [w["text"].lower().strip(".,;:()[]") for w in window]
            if texts != phrase:
                continue
            if max(w["top"] for w in window) - min(w["top"] for w in window) > SAME_LINE_TOL:
                continue   # span crosses a line — skip; use strategy 5 instead
            spec["annotations"].append({
                "type": "highlight", "page": page_idx,
                "rect": {
                    "x0":     window[0]["x0"],
                    "top":    min(w["top"]    for w in window),
                    "x1":     window[-1]["x1"],
                    "bottom": max(w["bottom"] for w in window),
                },
            })

Path("/workspace/spec.json").write_text(json.dumps(spec, indent=2))
```

#### 3 — A whole line by text content

```python
import sys, json
from pathlib import Path
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import find_lines

src = "input.pdf"
spec = {"source": src, "output": "/workspace/highlighted.pdf", "annotations": []}

for page_idx, _, line in find_lines(
    src,
    lambda l: "important notice" in l["text"].lower(),
):
    spec["annotations"].append({
        "type": "highlight", "page": page_idx,
        "rect": {"x0": line["x0"], "top": line["top"], "x1": line["x1"], "bottom": line["bottom"]},
    })

Path("/workspace/spec.json").write_text(json.dumps(spec, indent=2))
```

The line's `x0` / `x1` bound the actual rendered text — no whitespace
padding at the right, no full-page-width overshoot.

#### 4 — The value next to a label (form-style: "Total: 1,234.56")

```python
import sys, json
from pathlib import Path
import pdfplumber

src = "input.pdf"
spec = {"source": src, "output": "/workspace/highlighted.pdf", "annotations": []}

LABEL = "Total:"
SAME_LINE_TOL = 2.0

with pdfplumber.open(src) as pdf:
    for page_idx, page in enumerate(pdf.pages):
        words = page.extract_words()
        labels = [w for w in words if w["text"] == LABEL]
        for label in labels:
            right_of = sorted(
                [w for w in words
                 if abs(w["top"] - label["top"]) <= SAME_LINE_TOL
                 and w["x0"] > label["x1"]],
                key=lambda w: w["x0"],
            )
            if not right_of:
                continue
            # take just the first token to the right; for the whole rest
            # of the line, replace `[right_of[0]]` with `right_of`
            value = [right_of[0]]
            spec["annotations"].append({
                "type": "highlight", "page": page_idx,
                "rect": {
                    "x0":     value[0]["x0"],
                    "top":    min(w["top"] for w in value),
                    "x1":     value[-1]["x1"],
                    "bottom": max(w["bottom"] for w in value),
                },
            })

Path("/workspace/spec.json").write_text(json.dumps(spec, indent=2))
```

#### 5 — A multi-line block (paragraph / clause / quote)

Multi-line spans need **one rect per line** — a single rect across lines
covers the inter-line gutter and looks like a marker that bled.

This recipe finds a paragraph starting with a known sentence and walks
forward through consecutive lines until a vertical gap signals the
paragraph break.

```python
import sys, json
from pathlib import Path
import pdfplumber

src = "input.pdf"
spec = {"source": src, "output": "/workspace/highlighted.pdf", "annotations": []}

START_TEXT = "Whereas"
GAP_RATIO  = 0.7   # gap > 0.7 × line-height ends the paragraph

with pdfplumber.open(src) as pdf:
    for page_idx, page in enumerate(pdf.pages):
        lines = page.extract_text_lines()
        for i, line in enumerate(lines):
            if not line["text"].lstrip().startswith(START_TEXT):
                continue
            paragraph = [line]
            for nxt in lines[i + 1:]:
                prev = paragraph[-1]
                gap = nxt["top"] - prev["bottom"]
                line_h = prev["bottom"] - prev["top"]
                if gap > GAP_RATIO * line_h:
                    break
                paragraph.append(nxt)
            for pl in paragraph:
                spec["annotations"].append({
                    "type": "highlight", "page": page_idx,
                    "rect": {"x0": pl["x0"], "top": pl["top"], "x1": pl["x1"], "bottom": pl["bottom"]},
                })

Path("/workspace/spec.json").write_text(json.dumps(spec, indent=2))
```

#### 6 — A section between two headings (may span pages)

```python
import sys, json, re
from pathlib import Path
import pdfplumber

src = "input.pdf"
spec = {"source": src, "output": "/workspace/highlighted.pdf", "annotations": []}

START_HEADING = "§3"
HEADING_RE    = re.compile(r"^§\d+")

in_section = False
with pdfplumber.open(src) as pdf:
    for page_idx, page in enumerate(pdf.pages):
        for line in page.extract_text_lines():
            text = line["text"].lstrip()
            if text.startswith(START_HEADING):
                in_section = True
            elif in_section and HEADING_RE.match(text):
                in_section = False
            if in_section:
                spec["annotations"].append({
                    "type": "highlight", "page": page_idx,
                    "rect": {"x0": line["x0"], "top": line["top"], "x1": line["x1"], "bottom": line["bottom"]},
                })

Path("/workspace/spec.json").write_text(json.dumps(spec, indent=2))
```

`in_section` carries across pages, so a section that starts on page 2 and
ends on page 4 highlights correctly through page 3.

#### 7 — PII redaction (regex over words)

```python
import sys, json, re
from pathlib import Path
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from pdf_helpers import find_words

src = "input.pdf"
spec = {"source": src, "output": "/workspace/redacted.pdf", "annotations": []}

PATTERNS = [
    re.compile(r"^[\w.+-]+@[\w.-]+\.\w+$"),         # email
    re.compile(r"^\+?[\d][\d\s\-()]{6,}$"),          # phone (loose)
    # add more as needed (SSN, IBAN, etc.)
]

def matches_any(text):
    return any(p.match(text) for p in PATTERNS)

for page_idx, _, w in find_words(src, lambda w: matches_any(w["text"])):
    spec["annotations"].append({
        "type": "blacken", "page": page_idx,
        "rect": {"x0": w["x0"], "top": w["top"], "x1": w["x1"], "bottom": w["bottom"]},
    })

Path("/workspace/spec.json").write_text(json.dumps(spec, indent=2))
```

**Blacken is real redaction.** When the spec contains any `blacken`,
the script rasterizes the **entire output PDF** at 200 DPI after
applying overlays. The result contains no text objects — only embedded
images — so `pdftotext`, copy/paste, and pdfplumber all return nothing.

**Trade-offs you must surface to the user:**

- Text on **every page** (not just the redacted one) becomes
  non-selectable and non-searchable. Partial flattening would leak the
  redacted term wherever else it appears, which is why we don't do it.
- Output file gets larger (a one-page doc grows from ~2 KB to ~80 KB).
- Accessibility: screen readers can no longer read the document text.
- Mixing `highlight` and `blacken` in one spec: the highlights on
  blacken-bearing pages also become pixels. Visually identical, but
  no longer interactive annotations.

#### When none of these fit

The strategies above cover the common shapes. For anything else (a
specific table cell, an irregular region, a callout box keyed off
graphical elements), drop down to `pdfplumber.open(src)` and inspect
`page.extract_words()`, `page.extract_text_lines()`, `page.find_tables()`,
or `page.chars` directly to assemble the rect by hand. The spec format
is the same; only the discovery step is custom.

### Spec format reference

```json
{
  "source": "/workspace/input.pdf",
  "output": "/workspace/annotated.pdf",
  "annotations": [
    {
      "type": "highlight",
      "page": 0,
      "rect": {"x0": 72, "top": 100, "x1": 310, "bottom": 114},
      "color": "yellow"
    },
    {
      "type": "blacken",
      "page": 1,
      "rect": {"x0": 200, "top": 540, "x1": 480, "bottom": 556}
    }
  ]
}
```

| Field | Values |
|---|---|
| `type` | `"highlight"` or `"blacken"` |
| `page` | integer, 0-based |
| `rect` | `{x0, top, x1, bottom}` (pdfplumber coords) |
| `color` | highlight only — `"yellow"` (default), `"green"`, `"pink"` |

### Apply

```bash
python3 ~/.config/opencode/skills/pdf/scripts/annotate_apply.py spec.json
```

The script prints the output path and the touched page indices (0-based)
— use that for QA.

---

## Sticky note

A pin anchored to a point with a popup comment. Native PDF annotation
(`/Subtype /Text`), so coords are **PDF-native** (bottom-left origin).
Convert from pdfplumber: `y_pdf = page_height - y_plumb`.

```python
from pypdf import PdfReader, PdfWriter
from pypdf.annotations import Text

reader = PdfReader("input.pdf")
writer = PdfWriter(clone_from=reader)
writer.add_annotation(
    page_number=0,
    annotation=Text(
        rect=(100, 700, 120, 720),    # tiny rect — viewers render as a fixed-size pin icon
        text="Check this figure against Q3 numbers.",
        open=False,                   # True opens the popup by default
    ),
)
with open("/workspace/with_note.pdf", "wb") as f:
    writer.write(f)
```

The popup body lives in `text=`; usually can't be visually verified
without opening it — note this in the report.

---

## Free-text overlay

For arbitrary text painted onto the page at a fixed position. Native PDF
annotation (`/Subtype /FreeText`), so coords are **PDF-native**.

```python
from pypdf import PdfReader, PdfWriter
from pypdf.annotations import FreeText

reader = PdfReader("input.pdf")
writer = PdfWriter(clone_from=reader)
writer.add_annotation(
    page_number=0,
    annotation=FreeText(
        text="Figure 1: revised after audit",
        rect=(100, 80, 400, 100),
        font="Helvetica",                   # pypdf FreeText takes a PDF base-14 name
        font_size="11pt",                   # or a name embedded in the document;
        font_color="000000",                # the konrad font palette is for canvas-
        background_color="ffffff",          # drawn content, not FreeText viewer-side
        border_color=None,                  # rendering. See references/fonts.md.
    ),
)
with open("/workspace/captioned.pdf", "wb") as f:
    writer.write(f)
```

Distinct from watermark below: a `FreeText` annotation is removable by
viewers that respect annotations; a watermark is baked into the page
content stream.

---

## Box / line

Frame an area or draw a baseline-style underline. Coords are PDF-native.

```python
from pypdf import PdfReader, PdfWriter
from pypdf.annotations import Rectangle, Line

reader = PdfReader("input.pdf")
writer = PdfWriter(clone_from=reader)
writer.add_annotation(page_number=0, annotation=Rectangle(rect=(100, 600, 300, 700)))
writer.add_annotation(page_number=0, annotation=Line(p1=(100, 590), p2=(300, 590)))
with open("/workspace/boxed.pdf", "wb") as f:
    writer.write(f)
```

`Polyline` (open path) and `Polygon` (closed path) work the same way.

---

## Watermark

Two modes: stamp an **existing watermark PDF** (preferred when the user
has one), or build a **text overlay** on the fly.

### From an existing watermark PDF

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

Transparent-background watermarks work best.

### From a text string

Three things matter for a watermark that looks like a watermark:

1. Overlay page size must match each target page's `MediaBox` — hardcoded letter lands off-centre on A4.
2. Font scales to the page diagonal, not a fixed point size.
3. `drawCentredString` places the **baseline** at `y`; offset by ~⅓ of font size so cap-height passes through the page centre.

```python
import io
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from font_helpers import register_font

from pypdf import PdfReader, PdfWriter
from reportlab.pdfgen import canvas
from reportlab.lib.colors import Color


def build_text_watermark(text, page_size, *, opacity=0.25, font_size=None,
                         family="Inter"):
    fam = register_font(family)
    w, h = page_size
    if font_size is None:
        font_size = ((w * w + h * h) ** 0.5) / 8
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=page_size)
    c.translate(w / 2, h / 2)
    c.rotate(45)
    c.setFillColor(Color(0.5, 0.5, 0.5, alpha=opacity))
    c.setFont(f"{fam}-Bold", font_size)
    c.drawCentredString(0, -font_size * 0.35, text)
    c.save()
    buf.seek(0)
    return PdfReader(buf)


reader = PdfReader("input.pdf")
writer = PdfWriter()
for page in reader.pages:
    box = page.mediabox
    size = (float(box.width), float(box.height))
    overlay = build_text_watermark("DRAFT", size).pages[0]
    page.merge_page(overlay)
    writer.add_page(page)
with open("/workspace/watermarked.pdf", "wb") as out:
    writer.write(out)
```

Built per-page so each page's exact `MediaBox` is honored (booklets,
mixed-format reports). For uniform PDFs you can lift the build call out
of the loop — minor perf, not correctness.

---

## Reporting

Tell the user:

- Output path, page count
- Annotation breakdown — e.g. *"5 highlights on pages 0, 3, 7; 2 blackened areas on page 1; 1 watermark on every page"*
- For text-search highlights: search term + per-page match count
- For specs **without** blacken: annotations are non-destructive — the underlying text is unchanged, the PDF still has selectable text and proper accessibility.
- For specs **with** blacken: the output is a flattened image-only PDF — no extractable text anywhere, every page is now pixels. State this plainly so the user understands what they got. Include the file-size delta in the report (typically 30–50× the original on text-heavy documents).
- QA verdict per qa.md's Reporting section

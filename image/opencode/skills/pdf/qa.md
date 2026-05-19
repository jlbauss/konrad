# QA — verify visual outputs before reporting

After any operation that has a **visual** deliverable, rasterize the
touched pages, look at them with your own vision, and judge whether the
output matches the user's intent before handing it back. This is the PDF
skill's concrete take on the "no AI slop" rule: deliver work you can
stand behind, or say plainly why you can't.

The QA cycle is **opt-in by operation**, not blanket — see the table
below for which ops earn it and which skip it.

## When QA applies

| Route | Op | QA |
|---|---|---|
| EDIT | watermark (text or file) | **Yes** — placement, opacity, legibility, clipping |
| EDIT | highlight by coords or text | **Yes** — every match covered, no neighbours hit |
| EDIT | FreeText / sticky note / box / line | **Yes** — coords sensible, no overlap with body |
| EDIT | rotate | **Yes** — affected pages right-way-up, no clip |
| EDIT | merge | Light — page count + first/last-page spot-check |
| EDIT | split | Light — page count of each output |
| EDIT | encrypt / decrypt / metadata | **Skip** — no visual change |
| EDIT | image extraction | **Skip** — separate eyeball-the-image loop, not in scope here |
| GENERATE | bare-bones page | **Yes** — text fits, fonts render, no clipping |
| FILL | filled form | **Yes** — every value in its field, no overflow |
| EXTRACT | text / markdown / JSON | **Skip** — non-visual deliverable. See note below. |

EXTRACT QA is a different loop (compare extracted text to a rasterized
source page) and isn't covered here yet — flag it to the user if they
want this kind of cross-check.

## When QA can't run

Two reasons to skip:

1. **No vision capability.** If you can't actually read images, you
   can't do this QA. Say so plainly to the user — *"my model can't see
   images, so I produced the output but didn't visually verify it"* — and
   deliver. Do not pretend QA ran. (`README.md` documents that konrad
   silently fails when the user runs text-only models; this is the
   skill-level honest version.)
2. **User opted out.** If the user said "skip QA" or "just do it
   quickly", honour that. Note in the report that QA was skipped.

In both cases, downgrade the closing language from *"I checked the
output and it looks right"* to *"output produced; no visual
verification"*.

## Rasterize the touched pages

`pdf2image` is preinstalled. Write rasterized PNGs into a tempdir so they
don't clutter `/workspace`. Only promote to a persistent `/workspace/.qa/`
directory on failure (see Evidence below).

```python
import tempfile
from datetime import datetime
from pathlib import Path
from pdf2image import convert_from_path


def rasterize_touched(
    pdf_path: str,
    page_indices: list[int],          # 0-based
    *,
    dpi: int = 150,
    persist_to: Path | None = None,
) -> tuple[Path, list[Path]]:
    """Rasterize selected pages to PNG.

    Returns (output_dir, [paths]). If `persist_to` is None, output_dir
    is a fresh tempdir — the caller is responsible for cleanup. If
    `persist_to` is given (use this on QA failure to keep evidence),
    that directory is used instead and survives the process.
    """
    if persist_to is None:
        out_dir = Path(tempfile.mkdtemp(prefix="pdfqa_"))
    else:
        out_dir = persist_to
        out_dir.mkdir(parents=True, exist_ok=True)

    paths: list[Path] = []
    for idx in sorted(set(page_indices)):
        pages = convert_from_path(
            pdf_path, dpi=dpi,
            first_page=idx + 1, last_page=idx + 1,
        )
        out = out_dir / f"page_{idx + 1:03d}.png"
        pages[0].save(out, "PNG")
        paths.append(out)
    return out_dir, paths
```

`dpi=150` is the sweet spot — text is legible, annotations are
distinguishable, and the PNG stays small enough that vision-token cost
is reasonable. Drop to `dpi=100` if the user explicitly wants the
cheapest QA possible; push to `dpi=200+` only when fine detail matters
(e.g. tightly-cropped highlights on small text).

### Which pages count as "touched"

| Op | Touched set |
|---|---|
| Watermark | All pages that received the watermark (usually every page) — but for QA, sample 3: first, middle, last |
| Highlight by coords | Just the page(s) you annotated |
| Highlight by text-search | Every page that produced at least one match |
| FreeText / sticky / box / line | Just the page(s) you annotated |
| Rotate | The page(s) you rotated |
| Merge | First page of the merged output, and the join page between each input boundary |
| Split | First page of each output file (one-time check that the slicing landed) |
| GENERATE bare-bones | The only page (or all pages, if multi-page) |
| FILL | Every page that contains a field you filled (read off the `fill_inspect.py` output to know which pages those are) |

For watermark across long PDFs, sampling 3 pages is enough — the overlay
is built per-page from the same template, so issues are systemic, not
per-page. For text-search highlights across a long PDF, *every* match
page must be checked — false positives and missed matches are per-page.

## Per-operation checklists

Each checklist is short. Vision does the work; the doc tells you what
verdict to render.

### Watermark

- Text is legible at normal zoom.
- Not clipped by page edges.
- Opacity sits in "visible but content readable beneath" — not so dark
  it obscures body text, not so light it disappears.
- For diagonal mode: cap-height passes through page centre (the
  `-font_size * 0.35` offset in `edit.md` exists for this — verify it
  worked).
- The same watermark text appears on every sampled page (i.e. the
  rendering loop didn't skip pages).

### Highlight (coords or text-search)

- Every overlay sits **on** the intended word/area, not next to it.
- Overlay doesn't extend into adjacent words or trailing punctuation by
  more than ~10% of word width. Wider bleed is a coord-flip bug.
- Multi-line text matches: both halves are highlighted (one quad isn't
  enough — needs a `quad_points` extension or a second annotation per
  match).
- Pages with zero expected matches have zero overlays.
- Underlying text remains readable through the highlight.

### FreeText

- Text lands at the requested position, not 100 pt off.
- Doesn't overlap meaningful body content.
- Font size readable at normal zoom (~10–14 pt for captions; bigger if
  the user asked for a callout).
- Not clipped by its rect, not clipped by the page edge.
- Background colour (if set) doesn't make the text invisible.

### Sticky note (Text annotation)

- Pin icon at approximately the requested location.
- Doesn't overlap critical content the user wanted left alone.
- (The popup body usually can't be visually verified without opening it —
  trust the `text=` you passed and note this in the report.)

### Box / line / polyline / polygon

- Frames the intended area, not the adjacent one.
- Line weight and colour are visible against the page background.
- For lines indicating direction (arrow-style underlines): orientation
  matches what the user asked for.

### Rotate

- Affected page(s) are right-way-up.
- Content not clipped by the rotation (especially for non-square pages
  rotated 90° / 270°).
- Other pages unchanged.

### FILL

- Each filled value appears in its field.
- Values don't overflow the field's visible area (text running past the
  right edge is a real defect — flag it).
- Values are vertically aligned within the field (text isn't floating
  above or sunk below).
- Checkbox / radio states are visually checked when set to true.
- No "(empty)" rendering artifacts where you set a value.

### GENERATE (bare-bones page)

- Text fits the page — no clipping at right or bottom.
- Fonts render correctly — not boxes, not garbled tofu.
- Layout matches what the user asked for (title above body, etc.).
- Page count matches expectation.

## Failure handling

Three verdicts after looking at the rasterized pages:

### Pass

Output matches intent. Deliver normally; the closing report can include
*"I rasterized pages X, Y, Z and they look correct"* if the user is the
kind who wants the receipt — otherwise stay quiet.

### Pass with caveat

Output is acceptable but imperfect. Examples: highlight covers the word
but extends slightly into a comma; FreeText caption is positioned where
asked but is one line longer than its rect (text still fits because the
viewer reflows). Deliver, but **name the imperfection** in the report.
Offer one targeted fix the user can accept or skip.

### Fail

Output is wrong in a way that matters. Two sub-cases:

**Parametric failure** — one knob is wrong (opacity too dark, coords off
by a known offset, font size too large, highlight quad flipped). The
agent **may retry** with an adjusted parameter, subject to these
guardrails:

- **Hard cap: 2 retries.** After two adjusted attempts that didn't fix
  it, treat as structural and surface to the user.
- **Each retry must produce a measurably-different output.** Re-running
  with the same params is a no-op — that's not a retry, that's a loop.
  Adjust the knob, re-render, re-rasterize, re-QA.
- **Stop on oscillation.** If retry 1 over-corrected (too light) and
  retry 2 over-corrected the other way (too dark), the parameter space
  isn't converging — stop, surface to user, propose they pick a value.

**Structural failure** — wrong word highlighted, FreeText overlaps real
content, rotation applied to the wrong page, watermark hides body text
entirely. **Zero retries.** Surface to the user immediately, with the
evidence images, and propose alternatives (re-search with a stricter
pattern, choose a different anchor coord, etc.).

### Evidence on failure

When you escalate to the user, persist the rasterized PNGs that
informed your verdict so the user can verify your read:

```python
from datetime import datetime
from pathlib import Path

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
evidence = Path(f"/workspace/.qa/{stamp}")
out_dir, paths = rasterize_touched(
    "/workspace/annotated.pdf",
    touched_page_indices,
    persist_to=evidence,
)
# Tell the user: "I saved the QA images to /workspace/.qa/<stamp>/."
```

`/workspace/.qa/` accumulates over time. Mention the cleanup path to the
user once: `trash /workspace/.qa/<stamp>/` for one run, or
`trash /workspace/.qa/*` to clear all evidence. (Prefer `trash` over
`rm` per the repo's working agreement — recoverable from
`/workspace/.Trash-1000/`.)

## Reporting after QA

Add to the normal Reporting block from each route:

- **Pass**: nothing extra needed beyond the route's normal report. If
  you want to receipt it, *"I rasterized N page(s) and visually
  verified the output"* is the right level.
- **Pass with caveat**: name the imperfection, name the fix you didn't
  attempt, ask if the user wants you to retry.
- **Fail (after retries)**: name what's wrong, point at
  `/workspace/.qa/<stamp>/`, propose 1–2 concrete next moves.
- **QA skipped (no vision)**: *"output produced; my model can't see
  images, so I didn't visually verify it. Open the file to confirm it
  looks right."*
- **QA skipped (user opted out)**: *"output produced; QA skipped per
  your request."*

## Cost note

Vision-token cost scales with page count and DPI. The "touched pages
only" default keeps it cheap on typical operations: a single annotation
costs one page-render. A watermark on a long PDF costs three (first /
middle / last). A FILL on a 50-page tax form costs as many pages as
contain widgets — usually 3–8.

If the user explicitly asks for full-document QA, or you suspect a
systemic issue you couldn't catch on a sample, escalate to full-doc QA
and tell them you're doing so. Otherwise don't.

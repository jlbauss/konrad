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
| ANNOTATE | highlight, blacken | **Yes** — every rect on the intended area, no neighbours hit |
| ANNOTATE | sticky note, free-text, box, line | **Yes** — coords sensible, no overlap with body |
| ANNOTATE | watermark | **Yes** — placement, opacity, legibility, clipping |
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

## Progressive verification — start with one page

Skill-wide rule. Applies to every visual-QA operation: EDIT, ANNOTATE,
GENERATE, FILL.

After your code produces an output:

1. **Rasterize one page** — the first touched page (or page 1 for ops
   that touch every page).
2. **Look at it.** If it's right, expand to the rest of the touched set
   per the "Which pages count as touched" table below. For systemic ops
   (watermark on a long doc), expand means spot-check first / middle /
   last.
3. **If it's wrong**, fix the recipe / spec / inputs and re-run **before**
   rasterizing more. Rasterizing every page of a failing output is
   wasted vision tokens — they all fail the same way.

Why this is the default:

- Recipe-level mistakes (wrong color, wrong rect math, wrong page index)
  show up identically across every touched page. One page catches them.
- Per-page surprises (one match landed wrong while siblings landed right)
  are second-pass concerns — find them by spot-checking after the recipe
  is provably right.
- Vision tokens scale linearly with rasterized pages; pre-fix full-doc
  QA is the most expensive form of "I didn't catch the bug sooner".

The "Which pages count as touched" table below is the **upper bound** —
that's the set you expand to if and only if the first page passes.

## The post-rasterize contract (read, or declare skipped)

Calling `rasterize_touched` is a commitment, not a checkbox. From the
moment the helper returns paths, you have **exactly two** acceptable
next moves:

1. **Read each returned PNG with your image-reading tool**, then render
   a pass / pass-with-caveat / fail verdict based on what you actually
   saw. This is the QA cycle as designed.
2. **Declare QA skipped in your final answer**, with the reason —
   "my model has no vision," "vision budget exhausted," "user said
   skip." Honest abdication, not a verdict.

Reporting "pass" without reading the PNGs is the single most common
dishonest QA pattern this skill sees. If you didn't look, say you
didn't look. The user can re-run with a vision-capable model, ask you
to look harder, or accept the output unverified — but they need to
know which.

### Reasons to declare QA skipped

1. **No vision capability.** Some models on the konrad image are
   text-only or only weakly multimodal. If you can't read images
   reliably, say so plainly — *"my model can't read images, so I
   produced the output but didn't visually verify it"* — and deliver.
   Do not pretend QA ran. `README.md` documents this silent failure
   mode at the konrad level; this is the skill-level honest version.
2. **User opted out.** If the user said "skip QA" or "just do it
   quickly", honour that. Note in the report that QA was skipped.

In both skipped cases, downgrade the closing language from *"I checked
the output and it looks right"* to *"output produced; no visual
verification — [reason]"*.

## Rasterize the touched pages

`pdf2image` is preinstalled. The skill ships `rasterize_touched()` so you
don't roll your own — it writes PNGs into a fresh tempdir by default
(automatic cleanup, no `/workspace` pollution), or into a persistent
directory when you pass `persist_to=` for failure evidence.

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from qa_helpers import rasterize_touched

# touched_pages is a list of 0-based page indices you just annotated.
out_dir, paths = rasterize_touched(
    "/workspace/annotated.pdf",
    touched_pages,
    # dpi=150 by default; persist_to=None means tempdir.
)
# `paths` is the list of PNG paths to read with your vision tool.
```

`dpi=100` is the default — sufficient for routine placement-grade QA
(every checklist below: highlight covers the right area, watermark
legible, FreeText positioned, FILL value in its field). Vision-token
cost on most APIs scales with pixel count, so the default is chosen for
cheap-by-default routine passes. Push to `dpi=150` when annotation
*alignment* precision matters (verifying a highlight isn't off by a
few points, that kind of bug); `dpi=200+` only when print-grade
precision is needed.

> Don't reimplement this inline. Re-rolling `convert_from_path` calls in
> ad-hoc scripts is the most common QA-related mistake — it leaks PNGs
> into `/workspace/`, drifts from the dpi default, and skips the
> dedup/sort the helper does. Use the import.

### Which pages count as "touched"

| Op | Touched set |
|---|---|
| Highlight / blacken | The pages `annotate_apply.py` prints as "Touched pages" |
| Sticky note / free-text / box / line | Just the page(s) you annotated |
| Watermark | All pages that received the watermark (usually every page) — for QA, sample 3: first, middle, last |
| Rotate | The page(s) you rotated |
| Merge | First page of the merged output, and the join page between each input boundary |
| Split | First page of each output file (one-time check that the slicing landed) |
| GENERATE bare-bones | The only page (or all pages, if multi-page) |
| FILL | Every page that contains a field you filled (read off `fill_inspect.py`) |

For watermark on long PDFs, sampling 3 pages is enough — the overlay
is built per-page from the same template, so issues are systemic, not
per-page. For text-driven highlights on long PDFs where the user said
"every X", spot-check the touched pages a script returned — false
positives and missed matches are per-page.

## Per-operation checklists

Each checklist is short. Vision does the work; the doc tells you what
verdict to render.

### Watermark

- Text is legible at normal zoom.
- Not clipped by page edges.
- Opacity sits in "visible but content readable beneath" — not so dark
  it obscures body text, not so light it disappears.
- For diagonal mode: cap-height passes through page centre (the
  `-font_size * 0.35` offset in the watermark recipe in `annotate.md`
  exists for this — verify it worked).
- The same watermark text appears on every sampled page (i.e. the
  rendering loop didn't skip pages).

### Highlight

- Every overlay sits **on** the intended word/area, not next to it.
- Overlay doesn't extend into adjacent words or trailing punctuation by
  more than ~10% of word width. Wider bleed is a rect-build bug.
- Multi-line spans: every line is highlighted as a separate rect
  (the recipes in `annotate.md` emit one rect per line specifically to
  avoid the inter-line gutter being filled).
- Pages with zero expected matches have zero overlays.
- Underlying text remains readable through the highlight.

### Blacken (real redaction)

- Every blackened area is **fully opaque** — no text visible through it.
- Underlying text is gone: a quick `pdfplumber.open(out).pages[0].extract_text()`
  on a redacted page returns empty (the script rasterizes the whole
  output when blacken is present).
- Other pages: text is no longer selectable / searchable on any of them
  (expected — flag it to the user as a trade-off, not a bug).
- File size: 30–50× the input on text-heavy documents is normal; far
  larger suggests the DPI got bumped or the input was already an image PDF.

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
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from qa_helpers import rasterize_touched

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

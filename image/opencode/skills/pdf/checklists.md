# Verification checklists — pdf skill

Per-operation "what correct looks like" lists for the pdf skill's
visual deliverables. The **`quality-assurance`** skill governs the
verification cycle (progressive verification, post-rasterize contract,
verdicts, retry budget, evidence directory); this file says what to
look at when rasterizing each kind of op's output.

Use after invoking `rasterize_touched` from `quality_assurance_helpers`
on the touched pages.

## Which pages count as "touched"

| Op | Touched set |
|---|---|
| Highlight / blacken | The pages `annotate_apply.py` prints as "Touched pages" |
| Sticky note / free-text / box / line | Just the page(s) you annotated |
| Watermark | All pages that received the watermark (usually every page) — sample 3: first, middle, last |
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

## Watermark

- Text is legible at normal zoom.
- Not clipped by page edges.
- Opacity sits in "visible but content readable beneath" — not so
  dark it obscures body text, not so light it disappears.
- For diagonal mode: cap-height passes through page centre (the
  `-font_size * 0.35` offset in the watermark recipe in `annotate.md`
  exists for this — verify it worked).
- The same watermark text appears on every sampled page (i.e. the
  rendering loop didn't skip pages).

## Highlight

- Every overlay sits **on** the intended word/area, not next to it.
- Overlay doesn't extend into adjacent words or trailing punctuation
  by more than ~10% of word width. Wider bleed is a rect-build bug.
- Multi-line spans: every line is highlighted as a separate rect (the
  recipes in `annotate.md` emit one rect per line specifically to
  avoid the inter-line gutter being filled).
- Pages with zero expected matches have zero overlays.
- Underlying text remains readable through the highlight.

## Blacken (real redaction)

- Every blackened area is **fully opaque** — no text visible through
  it.
- Underlying text is gone: a quick
  `pdfplumber.open(out).pages[0].extract_text()` on a redacted page
  returns empty (the script rasterizes the whole output when blacken
  is present).
- Other pages: text is no longer selectable / searchable on any of
  them (expected — flag it to the user as a trade-off, not a bug).
- File size: 30–50× the input on text-heavy documents is normal; far
  larger suggests the DPI got bumped or the input was already an
  image PDF.

## FreeText

- Text lands at the requested position, not 100 pt off.
- Doesn't overlap meaningful body content.
- Font size readable at normal zoom (~10–14 pt for captions; bigger
  if the user asked for a callout).
- Not clipped by its rect, not clipped by the page edge.
- Background colour (if set) doesn't make the text invisible.

## Sticky note (Text annotation)

- Pin icon at approximately the requested location.
- Doesn't overlap critical content the user wanted left alone.
- (The popup body usually can't be visually verified without opening
  it — trust the `text=` you passed and note this in the report.)

## Box / line / polyline / polygon

- Frames the intended area, not the adjacent one.
- Line weight and colour are visible against the page background.
- For lines indicating direction (arrow-style underlines):
  orientation matches what the user asked for.

## Rotate

- Affected page(s) are right-way-up.
- Content not clipped by the rotation (especially for non-square
  pages rotated 90° / 270°).
- Other pages unchanged.

## FILL

- Each filled value appears in its field.
- Values don't overflow the field's visible area (text running past
  the right edge is a real defect — flag it).
- Values are vertically aligned within the field (text isn't
  floating above or sunk below).
- Checkbox / radio states are visually checked when set to true.
- No "(empty)" rendering artifacts where you set a value.

## GENERATE (bare-bones page)

- Text fits the page — no clipping at right or bottom.
- Fonts render correctly — not boxes, not garbled tofu.
- Layout matches what the user asked for (title above body, etc.).
- Page count matches expectation.

## When does pdf earn verification?

| Route | Op | Quality assurance |
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
| EXTRACT | text / markdown / JSON | **Skip the visual cycle** — use the language flavour in the `quality-assurance` skill against the spec in `task.md`. |

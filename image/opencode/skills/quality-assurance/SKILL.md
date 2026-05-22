---
name: quality-assurance
description: >
  Verification cycle for any deliverable the agent produces — a PDF, a
  spreadsheet, a transformed dataset, a generated document, an
  extracted text/JSON file. TRIGGER after you finish producing a
  deliverable a user will consume, BEFORE the closing report. The
  skill defines the cycle (produce → self-check → render verdict →
  deliver-or-escalate), the verdict vocabulary (pass /
  pass-with-caveat / fail / skipped-with-reason), the two flavours
  (visual via rasterize-and-look, language via read-and-judge), the
  retry budget (2 parametric, 0 structural), the post-verification
  contract (look-or-declare-skipped), and the cost-aware defaults
  (smallest useful DPI, read the deliverable not the source). Other
  skills' route docs reference this skill for the cycle; each
  producer carries its own per-operation checklists in its own route
  files. Also TRIGGER when a route doc says "see the
  quality-assurance skill" or names a quality-assurance step.
license: AGPL-3.0-only
metadata:
  author: konrad
  version: "1.0"
---

# Quality assurance

Verify what you produced against what was asked, before reporting back.
This is konrad's concrete take on the **honest** half of its working
principles: deliver work you stand behind, or say plainly why you can't.

Quality assurance is **opt-in by deliverable**, not blanket. A pure
lookup, a status check, a "what's in this file" answer — none of these
have a deliverable; nothing to verify. The trigger is producing
**something a user will consume** — a PDF, a spreadsheet, a transformed
file, a generated document, an extracted dataset. If you wrote
`.agent/task.md`, you have a deliverable; this skill applies.

## The cycle

After producing the deliverable, before reporting:

1. **Re-read `task.md ## Success looks like`** — what does the user
   actually want from this output? Verification is *against the spec*,
   not against some generic notion of "looks fine".
2. **Pick a flavour** based on what the deliverable is:
   - **Visual** (PDF/image): rasterize and look. See § Visual flavour.
   - **Language** (text, JSON, CSV, structured data): read and judge.
     See § Language flavour.
3. **Render a verdict** in the vocabulary below.
4. **Act on the verdict** — deliver, deliver with caveat, fix once
   more, or escalate to the user.

## Verdict vocabulary

Four verdicts, used consistently across every skill and report:

- **Pass** — output matches the spec. Deliver normally; the closing
  report may include *"I checked X and Y; the output is correct"* if
  the user is the kind who wants the receipt.
- **Pass with caveat** — output is acceptable but imperfect. Examples:
  highlight covers the word but extends slightly into a comma; an
  extracted row is correct but its date format isn't ISO. Deliver, but
  **name the imperfection** in the report. Offer one targeted fix.
- **Fail** — output is wrong in a way that matters. Split by sub-kind
  below: parametric vs. structural.
- **Skipped (reason)** — quality assurance could not run. Honest
  abdication, not a hidden verdict. The agent does **not** report
  "pass" when verification didn't happen. Reasons that earn a skip:
  - *No vision capability* — your model can't read images, so a visual
    check isn't possible. Deliver and say so.
  - *User opted out* — the user said "just do it" or "skip the check."
    Honour, note in the report.
  - *No spec to verify against* — `task.md` lacks a meaningful
    `## Success looks like` (e.g. an exploratory task with no concrete
    deliverable shape). Deliver and say so.

## The two-stage flow

```
producer (you)                              quality-assurance subagent
──────────────                              ──────────────────────────
1. Produce deliverable
2. Re-read task.md ## Success looks like
3. Self-check (this skill)
4. Structural failure → escalate (no fix)
5. Parametric failure → up to 2 fixes
6. Satisfied  ──hand off task.md+deliverable──▶ 7. Independent verdict
                                                8. Pass → producer reports
                                                   Pass-with-caveat →
                                                     producer surfaces it
                                                   Fail → producer fixes
                                                     one round, or escalates
```

> **Status: the producer-side cycle (steps 1–6) ships in this skill
> today.** The quality-assurance subagent (steps 7–8) is staged for a
> follow-up. Until it lands, step 6 is also the handoff to the user:
> deliver with your verdict, name skipped checks honestly, escalate
> structural failures. The producer remains responsible.

When the subagent does land, conflict-resolution rules:

- **Subagent verdict is final.** Producer doesn't argue. Pass-with-
  caveat → surface the caveat in the report. Fail → producer fixes
  one round (parametric only) or escalates to the user honestly.
- **Trivial work doesn't trigger either stage.** A pure lookup,
  read-only research, a status query — no `task.md`, no deliverable,
  no verification. Same gate as the planning contract.

## Visual flavour

The deliverable is a PDF, image, or any other artifact that has to
*look* a certain way. Verification means rasterizing and looking.

### Progressive verification — start with one page

Skill-wide rule for any visual op:

1. **Rasterize one page** — the first touched page (or page 1 for ops
   that touch every page).
2. **Look at it.** If it's right, expand to the rest of the touched
   set. For systemic ops (watermark on a long doc), expand means
   spot-check first / middle / last; full-doc verification is wasted
   vision tokens unless the user asked for it.
3. **If it's wrong**, fix the recipe / spec / inputs and re-run
   **before** rasterizing more. Rasterizing every page of a failing
   output is wasted vision tokens — they all fail the same way.

Recipe-level mistakes (wrong colour, wrong rect math, wrong page
index) show up identically across every touched page; one page
catches them. Per-page surprises (one match landed wrong while
siblings landed right) are second-pass concerns — find them by
spot-checking after the recipe is provably right.

### Rasterize the touched pages

The PDF skill ships `rasterize_touched()` for this — see
`pdf/scripts/quality_assurance_helpers.py`. Other skills that produce
visual output can import the same helper or roll their own; the
contract is "produce PNG paths the agent can read with its vision
tool."

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from quality_assurance_helpers import rasterize_touched

# touched_pages is a list of 0-based page indices you just touched.
out_dir, paths = rasterize_touched(
    "/workspace/annotated.pdf",
    touched_pages,
    # dpi=100 by default; persist_to=None means tempdir.
)
# `paths` is the list of PNG paths to read with your vision tool.
```

**Default DPI is 100.** Cost-aware default — vision-token cost on most
APIs scales with pixel count, and dpi=100 is sufficient for routine
placement-grade checks (overlay covers the right area, watermark
legible, free-text positioned, filled value in its field). Push to
**dpi=150** when alignment precision matters (verifying an overlay
isn't off by a few points). **dpi=200+** only when print-grade
precision is needed.

> Don't reimplement this inline. Re-rolling `convert_from_path` calls
> in ad-hoc scripts leaks PNGs into `/workspace/`, drifts from the dpi
> default, and skips the dedup/sort the helper does. Use the import.

### The post-rasterize contract

Calling `rasterize_touched` is a **commitment**, not a checkbox. From
the moment the helper returns paths, you have exactly two acceptable
next moves:

1. **Read each returned PNG with your image-reading tool**, then
   render a verdict based on what you actually saw.
2. **Declare skipped in your final answer**, with the reason — "my
   model has no vision," "vision budget exhausted," "user said skip."

Reporting "pass" without reading the PNGs is the single most common
dishonest verification pattern. If you didn't look, say you didn't
look. The user can re-run with a vision-capable model, ask you to
look harder, or accept the output unverified — but they need to know
which.

### Per-operation checklists

Per-operation checklists live in the producer skill (e.g. the PDF
skill carries the watermark / highlight / blacken / FILL checklists
in its route docs). The quality-assurance skill defines the cycle;
each producer fills in what "looks correct" means for its outputs.

## Language flavour

The deliverable is text — extracted JSON, a transformed CSV, a
markdown document, a structured dataset. Verification means
**reading the deliverable** and judging it against the spec.

### The cycle

1. **Read `task.md ## Success looks like`.** Concrete: what shape does
   the output have, what fields must be present, what's the cardinality
   constraint, what's the no-fabrication rule for unknown values?
2. **Read the deliverable, not the source.** Read the output file you
   just wrote — not the input. The whole point of language
   verification is to catch fabrications, dropped rows, schema
   violations, format slippage that wouldn't show up by re-reading
   the input.
3. **Check the four cardinal failure modes**:
   - **Cardinality** — does the row / record / item count match what
     the spec asked for? 1:1 transforms must produce 1:1 outputs. If
     the spec said "all 47 rows," count the output.
   - **Schema** — every required field present, no extra fields, types
     consistent (dates parse, numbers aren't stringified accidentally).
   - **Spot-check** — pick 3–5 records spanning the file (start,
     middle, end; ideally including a pathological case if you saw
     one earlier). Verify each maps to its source faithfully.
   - **No fabrication** — for any field you couldn't derive from the
     source, the value is the spec's missing-value sentinel (e.g.
     `MISSING`, `null`, empty string per spec), **not** a plausible
     guess.
4. **Render a verdict** using the standard vocabulary.

### The post-read contract

Same shape as the visual one: calling for the deliverable file means
either reading it and judging, or declaring skipped honestly. "Looks
good" without actually reading it back is the dishonest pattern at
the language end.

### Cost-aware reading

- **Slim before reading.** If the deliverable is large (>~50 KB), use
  `head` / `tail` / a structural probe before reading the whole file.
  For tabular data, read the header + a sample of rows before
  committing to a full-file read. The PDF skill's `find_words(...,
  fields=("text","x0","top"))` pattern is the model here.
- **Read at the lowest useful granularity.** If the spec is "rows have
  these 4 columns and no extras," reading 5 rows verifies that;
  reading every row to verify the same thing is waste.
- **Full-file read is a deliberate choice**, used when the per-row
  content is what's being verified (no-fabrication check on a
  no-source dataset, or a known-pathological set the user wants
  every row checked on).

## Failure handling

### Parametric failure — retry budget

One knob is wrong: opacity too dark, coords off by a known offset,
font size too large, a date format that slipped. The agent **may
retry** with an adjusted parameter, subject to:

- **Hard cap: 2 retries.** After two adjusted attempts that didn't
  fix it, treat as structural and surface to the user.
- **Each retry must produce a measurably-different output.** Re-running
  with the same params is a no-op — that's not a retry, that's a loop.
- **Stop on oscillation.** Retry 1 over-corrects (too light), retry 2
  over-corrects the other way (too dark) — the parameter space isn't
  converging. Stop, surface, propose the user pick a value.

### Structural failure — zero retries

Wrong record extracted, schema doesn't match the spec, output count
doesn't match input count, fabricated values for fields the source
didn't have, wrong word highlighted, watermark hides body text
entirely. **Zero retries.** Surface to the user immediately with the
evidence and propose alternatives — different anchor, looser pattern,
manual transformer subagent, etc.

The line between parametric and structural: if a knob-tweak could
plausibly fix it, parametric. If the *recipe* is wrong, structural.

### Evidence on failure

When you escalate to the user, persist the evidence so the user can
verify your read:

```python
import sys
sys.path.insert(0, "/home/node/.config/opencode/skills/pdf/scripts")
from quality_assurance_helpers import rasterize_touched

from datetime import datetime
from pathlib import Path

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
evidence = Path(f"/workspace/.agent/quality-assurance/{stamp}")
out_dir, paths = rasterize_touched(
    "/workspace/annotated.pdf",
    touched_page_indices,
    persist_to=evidence,
)
# Tell the user: "I saved the verification images to
# .agent/quality-assurance/<stamp>/."
```

For language failures, write a short `verdict.md` alongside the
deliverable in the same evidence directory, naming what failed and
which records / fields you spot-checked.

`.agent/quality-assurance/` is **auto-pruned** at every konrad
launch — anything older than 7 days is removed by the entrypoint.
You don't have to ask the user to clean up after every failed run.
If they want to drop a specific run immediately, the standard path is
`rm -rf .agent/quality-assurance/<stamp>/`.

## Reporting language

Append to whatever the producer skill's normal report looks like:

- **Pass**: optional receipt — *"I verified X and Y; the output is
  correct."* Skip if the user isn't asking for receipts.
- **Pass with caveat**: name the imperfection, name the fix you
  didn't attempt, ask if the user wants you to retry.
- **Fail (after retries)**: name what's wrong, point at
  `.agent/quality-assurance/<stamp>/` for evidence, propose 1–2
  concrete next moves.
- **Skipped (no vision)**: *"output produced; my model can't read
  images, so I didn't visually verify it. Open the file to confirm it
  looks right."*
- **Skipped (user opted out)**: *"output produced; verification
  skipped per your request."*
- **Skipped (no spec)**: *"output produced; nothing concrete to
  verify against in this task. Eyes on it before you keep it."*

## Cost notes

Verification cost scales with the deliverable. The "smallest useful"
default keeps it cheap on typical operations:

- Visual: rasterize touched pages only, at dpi=100. A single
  annotation costs one page-render; a watermark on a long PDF costs
  three (sampled first / middle / last); a FILL on a 50-page form
  costs the pages that contain widgets.
- Language: read the deliverable, not the source. Slim-print before
  full read for large outputs. Spot-check rather than full-file
  verify when the spec is per-record-shape (not per-record-content).

If the user explicitly asks for fuller verification, or you suspect
a systemic issue you couldn't catch on a sample, escalate to fuller
verification and tell them you're doing so. Otherwise don't.

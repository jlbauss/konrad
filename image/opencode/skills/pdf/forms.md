# FILL — fillable PDF form fields

Fill AcroForm fields in an existing PDF without altering layout or design.
Two scripts, two steps. This route — both the workflow and the two
scripts — is adapted from
[MiniMax-AI/skills](https://github.com/MiniMax-AI/skills)
(MIT-licensed); attribution lives in the project-level NOTICE at the
repo root.

> **Non-fillable forms: the FILL route stops here, but EDIT can help.**
> This route only handles PDFs whose fields are real AcroForm widgets
> (the ones a viewer lets you click and type into). If `fill_inspect.py`
> reports `has_fields: false`, FILL is done. The next move depends on
> what the user actually needs:
>
> - **Annotation-style "fill"** (text laid on top of the page, viewer
>   recognises it as an annotation that can be moved or removed): route
>   to EDIT's [Annotations section](edit.md#annotations) and use
>   `FreeText` annotations at the right coordinates per field. Good for
>   reviewable forms, casual fill-ins, scanned forms where the user just
>   needs text "next to the printed label".
> - **Real form recreation** (build proper AcroForm widgets so the PDF
>   becomes fillable in any viewer): out of scope for this skill — say
>   so and suggest a dedicated tool (Acrobat Pro, LibreOffice Draw,
>   `pdftk` `generate_fdf`).
>
> The annotation path is *not* a substitute for proper form filling — it
> won't roundtrip through form-handling tools and the "field" is just
> text painted on the page. Tell the user that trade-off before picking
> it.

## The two steps

```bash
# Step 1: inspect — list every field, its type, current value, and choices.
python3 ~/.config/opencode/skills/pdf/scripts/fill_inspect.py \
  --input form.pdf

# Step 2: fill — write values for the fields you want to set.
python3 ~/.config/opencode/skills/pdf/scripts/fill_write.py \
  --input form.pdf \
  --out   /workspace/filled.pdf \
  --values '{"FirstName": "Jane", "Agree": "true", "Country": "US"}'
```

**Always run `fill_inspect.py` first to get exact field names.** PDF
field names are case-sensitive, sometimes namespaced
(`Section1.Address.Street`), and sometimes arbitrary (`Text1`,
`CheckBox12`). Guessing wastes a round trip when you could have looked.

`fill_inspect.py` can also write its JSON to a file with `--out
fields.json` — useful when there are many fields and you want to refer
back without rerunning.

## Field types and value formats

| Field type | What you pass in `--values` |
|---|---|
| `text` | Any string. |
| `checkbox` | `"true"` or `"false"` (also accepts `"1"`, `"yes"`, `"on"`). |
| `dropdown` | Must match a `value` from the `choices` list returned by `fill_inspect.py`. The `label` is for display only — pass the `value`. |
| `radio` | Must match one of the `radio_values` from inspect. PDF radio values usually start with `/` (e.g. `/Choice2`). The fill script will add the leading `/` if you forget it. |
| `listbox` | Same as dropdown — pass the `value`, not the label. |
| `signature` | Not supported. Surface this to the user — they need to sign in a PDF viewer. |

## Passing values

Two ways:

### Inline JSON (small forms, one-shot)

```bash
python3 ~/.config/opencode/skills/pdf/scripts/fill_write.py \
  --input form.pdf --out /workspace/filled.pdf \
  --values '{"FirstName": "Jane", "LastName": "Doe", "Agree": "true"}'
```

### JSON file (larger forms, easier to review)

```bash
# Write values to a file the user can read and confirm before filling.
cat > /workspace/values.json <<'EOF'
{
  "FirstName": "Jane",
  "LastName":  "Doe",
  "Country":   "US",
  "Agree":     "true"
}
EOF

python3 ~/.config/opencode/skills/pdf/scripts/fill_write.py \
  --input form.pdf --out /workspace/filled.pdf \
  --data /workspace/values.json
```

For anything more than three or four fields, prefer the file path —
it's easier to review and easier to re-run.

## What the fill output tells you

`fill_write.py` prints a JSON result with:

- `status` — `ok` on success, `error` on read/write failure
- `filled_count` and `filled_fields` — fields actually written
- `validation_errors` — field/value pairs the script couldn't apply
  (e.g. dropdown value not in the choices list). The file is still
  written; the other fields go through. Surface these to the user
  rather than swallowing them.
- `not_found` — keys in your values JSON that the script didn't see
  in the PDF. Most of the time this means a misspelled field name —
  re-check inspect output.

A successful run also prints a human-readable summary to stderr.

## Conversational pattern

When the user asks to fill a form:

1. Run `fill_inspect.py` and look at what came back.
2. If `has_fields: false`, surface the trade-off described in the
   non-fillable callout above — offer the EDIT annotations escape hatch
   (`FreeText` at coordinates) and let the user pick before continuing.
3. Show the user the field list — names, types, and (for choice fields)
   the allowed values. This is short and worth the screen space.
4. Ask for the values, unless the user already supplied them. For long
   forms, asking field-by-field is tedious — instead, paste the inspect
   output back to them and ask "fill these in:" so they can hand you a
   block of values at once.
5. Build the values JSON, write it to `/workspace/values.json` for
   transparency, then run `fill_write.py`.
6. **Run vision QA on the filled output** — see [qa.md](qa.md). Touched
   pages are the ones containing fields you just wrote to (the inspect
   output identifies which page each field lives on). Verify each value
   landed in its field, nothing overflows the visible field area, and
   checkbox/radio states render as checked when set to true.
   Parametric failures (text overflow at the right edge of a field) are
   retry-eligible up to twice with a shorter value or a wrap; structural
   failures (value in the wrong field, fields blank in the rendered
   output despite `/NeedAppearances=true`) surface to the user.
7. Report: output path, filled count, **QA verdict**, and anything in
   `validation_errors` or `not_found`.

## Common pitfalls

- **Hierarchical field names.** PDFs created in Acrobat often namespace
  fields (`topmostSubform[0].Page1[0].FirstName[0]`). `fill_inspect.py`
  returns the full dotted path; use it verbatim in your values JSON.
- **Read-only fields.** Some PDFs mark fields read-only via flags; the
  writer will still try to set `/V`, but viewers may refuse to display
  it. If a value seems to "not stick", check whether the field is
  read-only and tell the user.
- **Appearance streams.** `fill_write.py` sets
  `/NeedAppearances=true` on the form, which tells the viewer to
  regenerate appearance streams. If the user opens the result in a
  viewer that doesn't honour that flag (rare), they may see empty
  fields with values stored underneath. Re-saving in a normal viewer
  fixes it; flag this to the user only if they report it.
- **Forms over scanned pages.** Some PDFs have AcroForm widgets overlaid
  on a scanned background. These count as fillable — they work fine
  with these scripts. The user just sees text appear in the right
  places because the widgets are positioned over the scan.

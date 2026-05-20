# Examples — Do It Manually

Three concrete walkthroughs of the workflow. Read these to anchor your sense of what a "good" run looks like.

---

## Example 1 — PDF receipts to CSV (the goldilocks case)

**Input:** `/workspace/data/receipts.txt` — 180 lines of OCR-extracted text from a stack of receipts. Each "row" spans 3–5 lines, in inconsistent layouts. Some receipts are German, some English. OCR errors throughout. The user wants a CSV with columns `date,vendor,total_eur,category`.

**What you'd do without this skill:** write a Python parser using regex for dates, fail on the German receipts that use `den 14. März`, add a second branch, fail on the OCR error `März` → `Marz`, add a third branch, swallow exceptions, output a 60-row CSV from 180 lines of input and not notice that 30 receipts were dropped.

### Step 1 — Reality check

> Switching to manual transformation for `receipts.txt`. My last three regex attempts left 28 receipts unparsed and the bug list is growing. The file has 60 distinct receipts with irregular OCR-mangled layouts — this is exactly the long-tail case the `do-it-manually` skill is for. I'll estimate the size, dispatch the `manual-transformer` subagent to produce a clean CSV at `.agent/artifacts/manual-output.csv`, verify its report, and then continue computing monthly totals from the clean file.

### Step 2 — Estimate size

```
$ bash $CLAUDE_SKILL_DIR/scripts/estimate-tokens.sh /workspace/data/receipts.txt
/workspace/data/receipts.txt        4820 chars        180 lines  ~ 1377 tokens
```

1377 tokens, well under 30k → dispatch a single subagent, no chunking.

### Step 3 — Dispatch

Call the Task tool with `manual-transformer` and the prompt:

> Input: `/workspace/data/receipts.txt` — ~60 OCR-extracted receipts, mixed German/English, irregular layouts.
> Output: `.agent/artifacts/manual-output.csv` with columns `date,vendor,total_eur,category`.
> Rules: Dates in ISO 8601. Vendor names canonicalized to brand (e.g. "EDEKA Müller Straße 12" → "Edeka"). Category from {groceries, travel, pharmacy, other}. 1:1 cardinality, no filtering. Use `MISSING` for unreadable fields. Return the standard QA report.

### Step 4 — Verify the report

The subagent returns:

> - Output: `/workspace/.agent/artifacts/manual-output.csv` (61 lines = 60 records + header)
> - Cardinality: 60 input receipts → 60 output rows ✓
> - Spot-check (lines 7, 42, 88, 119, 165): all matched literally except line 119 (vendor was "Penny Markt 234" → canonicalized to "Penny" per rules).
> - Field-invariant: dates preserved verbatim (just reformatted to ISO) ✓
> - Suspicious-result scan: 1 row with `MISSING` for vendor + category (line 47, fully illegible OCR). No clusters.
> - `MISSING` rows: row 47 only.
> - Fixes during QA: none.

Looks clean. Confirm `.agent/artifacts/manual-output.csv` exists, peek at it briefly, proceed.

### Step 5 — Continue original task

> The clean CSV is at `.agent/artifacts/manual-output.csv` with 60 verified rows (one has `MISSING` for vendor/category — see row 47). Now computing monthly totals by category with `pandas`.

```python
import pandas as pd
df = pd.read_csv('.agent/artifacts/manual-output.csv')
df = df[df['vendor'] != 'MISSING']            # drop the unreadable one
df['month'] = pd.to_datetime(df['date']).dt.to_period('M')
df.groupby(['month', 'category'])['total_eur'].sum()
```

Done.

---

## Example 2 — When NOT to use the skill (anti-signal)

**Input:** `/workspace/data/transactions.csv` — 12,000 rows exported from a bank, schema `date,description,amount,balance`. The user wants to flag rows where the description starts with `LASTSCHRIFT`.

**Wrong move:** invoke `do-it-manually`. 12,000 rows is solidly over the "use code" threshold, and the data is genuinely uniform — one rule works for every row.

**Right move:** stay in the primary agent, write a one-liner:

```bash
awk -F, 'NR==1 || $2 ~ /^"?LASTSCHRIFT/' transactions.csv > flagged.csv
```

This is the case the skill is *not* for. Recognize it (uniform data, large size, mechanical filter) and don't invoke. The skill's anti-signals exist precisely so you don't reach for it as a hammer just because you have it.

---

## Example 3 — Borderline case requiring chunking

**Input:** `/workspace/data/meeting-notes.md` — 4,200 lines, hand-typed meeting notes from 18 months. The user wants a structured JSON of all decisions made, one per meeting, with `date`, `decision`, `owner`.

### Step 2 — Estimate size says:

```
meeting-notes.md     38200 chars       4200 lines  ~ 10914 tokens
```

11k tokens → comfortably under 30k → dispatch a single subagent.

But suppose the file were 5× bigger (~55k tokens). That's the 30 000 – 80 000 row of the table — still one subagent, but flag the size in the prompt. And if it were 10× bigger (~110k tokens), we'd need to split:

```bash
csplit meeting-notes.md '/^# 2023/' '/^# 2024/' '/^# 2025/'
```

Then dispatch one `manual-transformer` subagent per year, each producing `.agent/artifacts/manual-output-2023.json`, `.agent/artifacts/manual-output-2024.json`, etc. After all subagents return, concatenate and re-verify cardinality across the whole:

```bash
jq -s 'add' .agent/artifacts/manual-output-*.json > .agent/artifacts/manual-output.json
echo "total decisions: $(jq 'length' .agent/artifacts/manual-output.json)"
```

Then continue with the original task on the merged file. Use a natural boundary (year, section, source file) rather than splitting mid-record — splitting mid-record is the one way to confuse the subagent and lose data.

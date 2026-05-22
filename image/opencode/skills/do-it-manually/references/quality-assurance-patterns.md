# Quality-assurance patterns for manual transformation

This file is a deeper toolbox for Phase 4 of `do-it-manually`. SKILL.md lists the four mandatory checks; this file shows concrete patterns for executing them, plus optional checks for higher-stakes work. These checks are this skill's contribution to the cross-skill `quality-assurance` cycle (the language flavour): you read the deliverable, compare it to the spec in `task.md`, and render a verdict.

## 1 — Cardinality check

The simplest possible check: did you preserve the count of records?

### Tabular (CSV, TSV, line-oriented text)

```bash
echo "input  records: $(($(wc -l < input.csv) - 1))"   # minus header
echo "output records: $(($(wc -l < .agent/artifacts/manual-output.csv) - 1))"
```

### JSON array

```bash
echo "input  records: $(jq 'length' input.json)"
echo "output records: $(jq 'length' .agent/artifacts/manual-output.json)"
```

### Nested / hierarchical

For "list of objects each containing a list" structures, count at every level and compare:

```bash
jq '[.[] | .items | length] | add' input.json
jq '[.[] | .items | length] | add' .agent/artifacts/manual-output.json
```

A mismatch at the parent level is a missing object; a mismatch at the child level is a missing item within an object.

**Important:** if your task involved intentional filtering or merging, the counts should *not* match — but you should still know exactly what the expected count is, and verify it.

## 2 — Random spot-check

The point: catch the hallucinations that hide in the middle of the file, where you lost focus.

### Picking lines fairly

```bash
# 5 line numbers spread roughly evenly through the file
shuf -i 1-$(wc -l < input.csv) -n 5 | sort -n
```

Then for each line N: `sed -n "${N}p" input.csv` to see the input row, and find the corresponding output row (by matching the ID, not by line number, unless cardinality is guaranteed identical).

### What to compare

- **ID-like fields** (primary keys, timestamps, hashes, URLs): byte-for-byte. Any difference is a bug.
- **Cleaned text fields**: semantic equivalence. "John  Smith " → "John Smith" is correct; "John Smith" → "Jon Smith" is a hallucination.
- **Reformatted fields** (e.g. date `12/3/2024` → `2024-12-03`): the underlying value must match. Use your judgment on the transformation rules you committed to.

Report the 5 line numbers you checked, what you found, and any fixes you applied. A clean spot-check log is the strongest evidence the user has that verification actually happened.

## 3 — Field-invariant check

For fields that should pass through *unchanged*, verify the set of values is identical:

```bash
# Extract the ID column from input and output, sort, diff
cut -d, -f1 input.csv | tail -n +2 | sort > /tmp/input-ids
cut -d, -f1 .agent/artifacts/manual-output.csv | tail -n +2 | sort > /tmp/output-ids
diff /tmp/input-ids /tmp/output-ids
```

Empty diff → invariant held. Non-empty → those rows changed, investigate which way.

For JSON:

```bash
jq -r '.[].id' input.json | sort > /tmp/input-ids
jq -r '.[].id' .agent/artifacts/manual-output.json | sort > /tmp/output-ids
diff /tmp/input-ids /tmp/output-ids
```

This is the single highest-leverage check when the user said "clean up the formatting but don't change the IDs."

## 4 — Suspicious-result scan

Look for patterns that *suggest* something went wrong, even if no individual row is provably broken.

### Clusters of MISSING

```bash
grep -n MISSING .agent/artifacts/manual-output.csv | head -20
```

A few scattered `MISSING` is fine and expected. A run of 8 consecutive `MISSING` rows means you gave up on a difficult section — go back and re-read those input rows carefully.

### Duplicate keys

```bash
cut -d, -f1 .agent/artifacts/manual-output.csv | tail -n +2 | sort | uniq -d
```

In a context where IDs should be unique, any output is a bug.

### Value-range outliers

If a numeric column has a known range:

```bash
# rough min/max of column 3
awk -F, 'NR>1 {print $3}' .agent/artifacts/manual-output.csv | sort -n | head -1
awk -F, 'NR>1 {print $3}' .agent/artifacts/manual-output.csv | sort -n | tail -1
```

Values outside the expected range are either real outliers in the input (preserve them) or a manual transcription error (you typo'd `100000` instead of `1000`). Spot-check the row to decide.

### Row-length anomalies

For CSV: rows with the wrong number of commas have a structural error.

```bash
awk -F, '{print NF}' .agent/artifacts/manual-output.csv | sort | uniq -c
```

If you expect every row to have 7 fields, anything other than "all 7" rows is broken.

### Unusual NULL / empty patterns

A column that is normally populated suddenly being empty for 10 consecutive rows is a clue. `grep -c '^,' file.csv` etc.

## 5 — Catch-all overuse check

When the target schema includes a catch-all class (`other`, `misc`, `unknown`), the catch-all becomes the easiest landing spot for fabrication. The failure mode: an unreadable input that should produce `MISSING` instead gets dumped into `other` because it feels "less missing than missing."

Check the catch-all rate. Roughly:

```bash
# Count how many output rows land in 'other' (assuming category is the last column)
awk -F, 'NR>1 {print $NF}' .agent/artifacts/manual-output.csv | sort | uniq -c
```

If `other` accounts for more than ~30 % of all rows — or, even more telling, if `other` shows up disproportionately in rows where another field is also `MISSING` — that is a fabrication smell.

Cross-tabulate with `MISSING` in other fields to catch the worst case:

```bash
# rows where vendor is MISSING — what category did they get?
awk -F, '$2 == "MISSING" {print $NF}' .agent/artifacts/manual-output.csv | sort | uniq -c
```

A receipt whose vendor is `MISSING` (because the input was illegible) cannot have a meaningful category either — unless the category was knowable from non-vendor signals like layout or amount. Any `other` (or any non-`MISSING` value) in this combination deserves a manual re-check. The right answer is almost always: if the row provides no signal for a field, that field is `MISSING`, no matter how tempting the catch-all class looks.

## Optional / advanced checks

For higher-stakes work, also consider:

### Round-trip on a sample

Take the manual output, run it through whatever downstream code you would have written, and confirm the downstream code does not complain (no parse errors, no schema violations). The fact that the output is "loadable" is a much weaker check than "correct", but a useful smoke test.

### Diff-against-input for cleanup-only tasks

If the task was "remove trailing whitespace, fix encoding" — i.e. a near-identity transformation — then `diff input output` should be small and every diff hunk explicable. Read every hunk.

### Cross-check against a second source

If the input was extracted from a richer source (a PDF with metadata, an HTML page with structured tags), spot-check 2 output rows against the original source rather than the input you were given. This catches errors that were already in the input you received.

## When to escalate

If any of these patterns trigger a cascade — fixing one row reveals two more, or you keep finding MISSING-clusters — stop the manual approach. The signal is that either:

- The input is too pathological for the manual approach to converge (rare).
- You misunderstood the schema, so your "errors" are actually your output being right and your check being wrong, or vice versa.
- The task is too large for one manual pass — split it up.

Tell the user what you found and ask for direction. A half-finished manual transformation is much worse than admitting the approach is not working.

---
name: do-it-manually
description: A reality-check for data-transformation and cleanup tasks better solved by reading and rewriting than by coding. TRIGGER when you have spent 3+ iterations writing or debugging code (Python scripts, regex, parsers, scrapers) on the same problem without converging; when input data is "structured-irregular" — each item a different special case rather than uniform; when the data lives in a long tail of formatting pathologies no single parser can fully handle; when you catch yourself thinking "if I could just look at this myself, I'd be done in 5 minutes." The skill dispatches a dedicated `manual-transformer` subagent that reads the input in fresh context, writes a clean intermediate output, and runs mandatory QA (cardinality, spot-checks, no-fabrication). You then continue your original task with the verified clean intermediate. Use this skill whenever you would otherwise reach for the Nth regex patch.
user-invocable: true
allowed-tools: "Read Write Edit Bash Glob Grep Task"
---

# Do It Manually

## Why this skill exists

You are a language model. Your reflex when you see data is to write code that processes it. That reflex serves you well 90% of the time — but it has a catastrophic failure mode on **structured-irregular** data, the kind where every input item is a slightly different special case.

The failure mode looks like this:

> Iteration 1: write a regex.
> Iteration 2: regex misses 3 lines, patch it.
> Iteration 3: patch breaks 2 other lines.
> Iteration 4: add a try/except.
> Iteration 5: now exceptions are swallowed and the output is silently wrong.
> Iteration 6: …

You are not making progress, you are oscillating — because the input does not have a regular grammar. It has 200 special cases, and your code can hold maybe 10 of them at a time. **A language model** can hold all 200 in its head if it just reads them. But you don't, because "I'll just read it and rewrite it" feels like cheating, or like failure. It is neither. It is the right tool.

This skill exists to make that approach a clean, repeatable workflow — by dispatching the `manual-transformer` subagent, which does the manual work in its own fresh context and returns a verified clean intermediate file. You then continue your original task on the clean file.

## When to invoke

Strong signals you should be using this skill RIGHT NOW:

- You have written 3+ code iterations against the same input and the bug list is growing, not shrinking.
- You catch yourself adding `if/elif` branches for individual rows or specific values.
- The input is roughly the size of a long email or short report (a few hundred lines), not a database export (millions of rows).
- Each row/item has its own pathology — there is no shared grammar to learn.
- You thought "if I could just transcribe this by hand, I'd be done."

Anti-signals — do NOT use this skill:

- The data is genuinely uniform. A CSV with a stable schema where one parser works for every row belongs to code.
- The data is large (10k+ records). Manual transformation does not scale, and a subagent's context window does not stretch infinitely.
- The transformation is purely mechanical (sort, dedupe, count, join). Use code.
- The task is "analyze this data, summarize the findings." That is reasoning, not transformation. Read the data normally.

## Why a subagent and not just "do it yourself"

Two reasons, both important:

1. **Fresh context.** Your current conversation has already spent tokens on the failing-code attempts, prior reasoning, intermediate files. The subagent starts with an empty window — every token of its budget is available for the manual work, which is exactly when faithful transcription is most reliable. Doing it in your own context, after a long debugging trail, is when hallucination risk peaks.

2. **Role separation.** The subagent has one job and a strict prompt around it. You orchestrate; it transcribes. That separation makes both halves of the work clearer and easier to verify after the fact.

opencode does not currently expose remaining-context information to a running agent, so we cannot dynamically decide "do I have room?" The subagent dispatch sidesteps that limitation entirely.

## The workflow

### Step 1 — Reality check

Tell the user — in one short paragraph — what you are doing and why. Cover:

- What the failing-code symptom was (e.g. "three regex iterations and 28 receipts still don't parse").
- That you are dispatching the `manual-transformer` subagent.
- What the expected output is and where it will land.

The user can stop you here, which is much cheaper than discovering disagreement after the subagent finishes.

### Step 2 — Estimate input size

Run the bundled estimator on the input file(s):

```
bash $CLAUDE_SKILL_DIR/scripts/estimate-tokens.sh <input-file>
```

Use the result to decide whether one subagent can handle it, or whether you need to split first:

| Estimated input tokens | Action |
|---|---|
| < 30 000 | Dispatch directly. Fits comfortably in any modern subagent's window. |
| 30 000 – 80 000 | Dispatch directly. Mention the size in the dispatch prompt so the subagent knows it has a tight budget for working room. |
| > 80 000 | Split the input externally — by year, section, file, or any natural boundary — and dispatch one subagent per chunk. Concatenate results and re-verify cardinality across the whole. |

These are absolute bounds, not percentages. opencode does not surface the subagent's remaining budget to you or to the subagent, so we treat ~128 000 tokens as the typical local-model context window and reserve ~48 000 for working room, output, and the QA artifacts. Konrad targets 30B-class local models — these bounds are conservative for that class.

### Step 3 — Dispatch the `manual-transformer` subagent

Use the Task tool to invoke the `manual-transformer` subagent. Give it everything it needs in the task prompt:

- **Input file path** — absolute, e.g. `/workspace/data/receipts.txt`.
- **Desired output** — format (CSV, JSON, etc.), schema (column names, field types), and target path (use `.agent/manual-output.<ext>` by convention so it sits with other agent working memory).
- **Task-specific rules** — any normalization that IS required (e.g. "canonicalize vendor names to brand"), fields that must be preserved verbatim, expected cardinality (1:1 or filtered with the filter rule).
- **Sentinel for missing data** — `MISSING` by default; override if the user prefers something else.
- **Encoding handling** — only if relevant. If the input shows mojibake (`Ã¼`, `Ã¶`, etc.), say whether you want it repaired or preserved as-is. The subagent will ask if you don't specify, which costs a roundtrip.

Example dispatch prompt:

> Input: `/workspace/data/receipts.txt` — ~60 OCR-extracted receipts, mixed German/English, irregular layouts.
> Output: `.agent/manual-output.csv` with columns `date,vendor,total_eur,category`.
> Rules: Dates in ISO 8601 (`YYYY-MM-DD`). Vendor names canonicalized to brand (e.g. "EDEKA Müller Straße 12" → "Edeka"). Category from a fixed set: groceries, travel, pharmacy, other. 1:1 cardinality, no filtering. Use `MISSING` for any unreadable field. Run all four QA checks and return the standard report.

A vague task prompt produces a vague output. The subagent is faithful but not psychic — it cannot guess your schema or your normalization rules.

### Step 4 — Verify the subagent's report

The subagent returns a structured report. Inspect it before you continue:

- The output file exists at the agreed path. (Use `ls -la <path>` if in doubt.)
- Cardinality numbers match (or match the explicit delta you specified).
- The spot-check log shows actual content comparisons of named line numbers, not just "looks good."
- The field-invariant check passed for fields you said should be preserved.
- `MISSING` rows, if any, are listed with which fields and why.
- The "Suspicious-result scan" did not turn up clusters.

If something looks off — for example, the cardinality is wrong, or the spot-check reveals a transcription error — you have two options:

1. **Re-dispatch with corrections.** Tell the subagent "row N is wrong, here is the correct value, please fix and re-verify."
2. **Escalate.** If the issue is the task definition, not the transcription, fix the dispatch prompt and re-dispatch. If the issue is the input being too pathological even for manual processing, tell the user — that is a real signal worth surfacing.

Do not silently accept the report. Verification is part of the workflow, not optional.

### Step 5 — Continue your original task

You now have a clean intermediate file with verified structure. Continue with normal scripting on it — Python, awk, jq, whatever the original task needs. The dirty input is done.

The intermediate file is a great artifact for the user to inspect or version-control, so leave it in place. Do not delete it when you finish.

## Anti-patterns

- **Skipping Step 1.** The user agreeing to manual mode is a real checkpoint. They may know something about the data you do not (e.g. "actually only the first 50 rows matter").
- **Doing the manual work yourself instead of dispatching.** Your current context is already partly spent. The subagent gets a fresh, full window — that is the whole point. If you do the transcription in your own context, hallucination risk goes up sharply for no benefit.
- **Vague task prompts.** "Clean up this file" gives the subagent no schema, no rules, no cardinality target. Spec the output precisely.
- **Skipping Step 4.** A subagent returning "done" is not a verified result. Read the report.
- **Using this skill on uniform data.** If one regex works on all 200 rows, write the regex. This skill is for the long-tail case where regex keeps growing without converging.

## Future iteration ideas

These are not implemented yet, but on the radar:

- **Reactive hook:** auto-inject a hint when a `Bash` tool call to `python` fails 3 times in a row on the same script.
- **Context-budget plugin:** if/when opencode adds a way to expose remaining context to the agent (issue [#17412](https://github.com/anomalyco/opencode/issues/17412)), Step 2's bounds can become adaptive percentages again.
- **Chunk reconciliation script:** for the > 80k token case, a helper that re-runs cardinality and spot-checks across concatenated chunks.

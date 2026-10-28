# Verification checklist — spreadsheets

What "correct" means for an `.xlsx` / `.csv` / `.tsv` deliverable, whichever skill built it. The cycle, verdicts and retry budget are in `SKILL.md`; this is the **language** flavour (read the deliverable back, check it against `task.md ## Success looks like`), not the visual one.

The `xlsx` skill's scripts do the reading (`~/.config/opencode/skills/xlsx/scripts/`):

```bash
X=~/.config/opencode/skills/xlsx/scripts
python $X/xlsx_read.py out.xlsx --sheets          # names, dimensions, merges, charts
python $X/xlsx_recalc.py out.xlsx                 # LibreOffice fills in formula results
python $X/xlsx_read.py out.xlsx --formulas        # each formula next to its result
python $X/xlsx_read.py out.xlsx --json --sheet S  # the values themselves
```

- **Cardinality.** The row count matches the spec: a 1:1 transform gives 1:1 rows, and a deliberate filter changes the count by the amount it should, not by surprise.
- **Nothing lost** (editing an existing file). The output has the input's sheets, same names, same order, and the cells the task didn't ask to change still hold what they held. Dump the same sheet from both files and compare. Charts and images: `--sheets` reports the chart count; if it dropped, re-saving lost them, so say so instead of delivering.
- **Headers.** Column headers exactly as the spec names them: no renamed (`Date` → `date`), dropped or duplicated column.
- **Formulas are formulas.** Every derived cell holds a formula, not a typed-in number; `--formulas` lists them. A formula the spec asked for that ended up as a constant is a structural failure.
- **Formulas compute.** After `xlsx_recalc.py`, no result is `#REF!`, `#NAME?`, `#VALUE!`, `#DIV/0!` or empty where a number belongs, and a sample of results matches a figure you worked out independently (a pandas sum over the source).
- **Numbers are numbers.** A numeric column reads back as numbers, not as text that looks like numbers.
- **UTF-8 intact.** Non-ASCII text round-trips cleanly: no `Ã¼` / `Ã¶` mojibake in headers or cells.

If the output lost something the input had (charts, images, pivot tables, macros the user didn't ask to touch), that's a **fail**, not a caveat to bury: say what was lost and offer the choices (re-add it, the user makes the edit in a spreadsheet app, or they accept the loss). Never ship a "fixed" file that silently lost part of the original.

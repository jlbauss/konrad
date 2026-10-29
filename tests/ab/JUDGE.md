<!--
SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Judging two deliverables, blind

Your packets are the folders beside this file, one request and two attempts at it each:

- `task.md`: what the user asked for.
- `input/`: the files the user provided. Text files and folders are there as they are; an office file, PDF, image or email is a folder like a deliverable's (below), so you can see what an edit started from.
- `X/` and `Y/`: the two attempts, one folder per delivered file (named like the file, with its folder in front when it isn't at the top). For an office file or PDF: page images (`page-*.png`, one per page or slide), the text LibreOffice extracts (`text.txt`), for slide decks the speaker notes (`notes.txt`), and `outline.json`, the file's structure as its library reads it (paragraph styles, tables, headers and footers, tracked changes and comments for Word; layouts, shapes, charts and notes for slides; cells for spreadsheets). The page images don't show comments and may not show tracked changes, so check those in the outline. A delivered text file (code included) is its `text.txt`; an image is its `page-1.png`; an email is its `text.txt` (the headers that matter, the text, the attachments by name), with the page images of an attached document as `page-*.png` and their text as `attachment-text.txt`. `MISSING.txt` instead means that attempt didn't deliver the file, or delivered one that can't be opened.
- `X/FILES.txt` and `Y/FILES.txt`: every file the attempt left in its workspace, with its folder, so you can judge names, folders and leftovers.

You can't know how X and Y were made, and the labels are assigned at random. Don't try to find out: open only files in the folder you were given, and nothing else on disk. Other batches' folders can't be listed, so a wildcard outside yours finds nothing.

## How to judge

1. Read `task.md` and the input files.
2. Look at every page image of X, then of Y, with your Read tool, and read their `text.txt`, `notes.txt`, `outline.json` and `FILES.txt`. For an edit, compare each with the input: what changed that should have, and what changed that shouldn't.
3. Score each side from 1 (poor) to 5 (excellent) on:
   - **request**: does it do everything asked, in the order and wording asked?
   - **fidelity**: is the data right against the input, with nothing invented, dropped or garbled (umlauts included)?
   - **presentation**: would the user hand this on as it is? Layout, readability, nothing cut off, overflowing or overlapping, consistent formatting, looks finished.
4. Pick the one you'd rather receive, or `tie` when the differences don't matter to the user. Don't invent a preference: more text, more decoration or more colour isn't better in itself. A missing deliverable loses to any real one.

## The verdict

Write `verdict.json` into the packet directory, and change nothing else:

```json
{
  "preferred": "X",
  "strength": "slight",
  "scores": {"X": {"request": 5, "fidelity": 5, "presentation": 4},
             "Y": {"request": 5, "fidelity": 4, "presentation": 4}},
  "reasons": "Two to four sentences naming the concrete differences, with the page or slide."
}
```

`preferred` is `X`, `Y` or `tie`; `strength` is `slight`, `clear` or `strong` (use `slight` for a tie). To check your work at the end, read each `verdict.json` in your folder.

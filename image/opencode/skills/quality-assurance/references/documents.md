# Verification checklist — Word documents

What "correct" means for a `.docx` deliverable, whichever skill built it. The cycle, verdicts and retry budget are in `SKILL.md`; this is the **language** flavour (read the document back, check it against `task.md ## Success looks like`), with one rendered page as the visual check.

The `docx` skill's scripts do the reading (`~/.config/opencode/skills/docx/scripts/`):

```bash
D=~/.config/opencode/skills/docx/scripts
python $D/docx_read.py out.docx --structure   # heading outline, paragraph/table/section counts
python $D/docx_read.py out.docx --text        # body, table cells, headers and footers
python $D/docx_read.py out.docx --revisions   # tracked changes and comments present
python $D/docx_comments.py list out.docx      # each comment and the text it's anchored to
python $D/docx_validate.py out.docx           # package health; exit 1 on errors
```

- **Structure is real.** Headings use heading styles (`Heading 1`, `Heading 2`, …), so the outline in `--structure` shows them; bold body text that looks like a heading isn't one. Lists use list styles, tables are tables, not tab-aligned text.
- **Every occurrence.** A replace or rename reaches body, tables, headers and footers: `--text` has no old string left, and the new one appears as often as the old did. Word splits text into runs, so a phrase that "wasn't found" usually was split; the skill's `replace` handles that.
- **Nothing lost** (editing an existing file). The paragraph and table counts change only by what the task asked for; images, headers, footers, comments and tracked changes the task didn't touch are still there (`--structure`, `--revisions`), and formatting on the edited text survived (a bold name is still bold).
- **Review marks when asked.** "As a tracked change" means `w:ins`/`w:del` in the file (`--revisions` reports them), not a silent edit; a comment is anchored to the text the task names (`docx_comments.py list`).
- **Healthy package.** `docx_validate.py` exits 0 on anything you produced through revision, comment or field surgery.
- **UTF-8 intact.** Umlauts and other non-ASCII text read back cleanly.
- **One page looks right.** Convert with `soffice --headless --convert-to pdf --outdir <tmp> out.docx` and look at the first touched page with `rasterize_touched()` (§ Visual flavour). Fields such as a table of contents or page numbers fill in only when the file is rendered, so this is also where you see them.

If the output lost something the input had, that's a **fail**: say what was lost and offer the choices (re-add it, the user makes the edit in Word, or they accept the loss).

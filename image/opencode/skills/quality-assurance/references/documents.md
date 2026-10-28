# Verification checklist — Word documents

What "correct" means for a `.docx` deliverable. The cycle, verdicts and retry budget are in `SKILL.md`; this is the **language** flavour (read the document back, check it against `task.md ## Success looks like`), with one rendered page as the visual check.

Read it back with pandoc, which shows the title, headings, lists, tables, comments and tracked changes with their authors (headers and footers it leaves out; python-docx reads those):

```bash
pandoc --track-changes=all -s out.docx -t markdown   # title: in the front matter, # headings, [..]{.insertion author=..}
soffice --headless --convert-to pdf --outdir /tmp/render out.docx   # then rasterize_touched() on the PDF
```

- **A title that reads as one.** The document's title uses the `Title` style (pandoc shows it as `title:`), not a heading the size of every section heading.
- **Structure is real.** Headings use heading styles (`#`, `##` in pandoc's output); bold body text that looks like a heading isn't one. Lists are lists, tables are tables, not tab-aligned text.
- **Every occurrence.** A replace or rename reaches body, tables, headers and footers: no old string left, and the new one appears as often as the old did. Word splits text into runs, so a phrase that "wasn't found" usually was split across them; join the runs of a paragraph before you search it.
- **Nothing lost** (editing an existing file). Paragraphs and tables change only by what the task asked for; images, headers, footers, comments and tracked changes the task didn't touch are still there, and formatting on the edited text survived (a bold name is still bold).
- **Review marks when asked.** "As a tracked change" means an insertion and deletion in the file (pandoc shows `{.insertion}` / `{.deletion}`), not a silent edit; a comment sits on the text the task names (`{.comment-start}` right before it).
- **UTF-8 intact.** Umlauts and other non-ASCII text read back cleanly.
- **One page looks right.** Render it and look at the first touched page with `rasterize_touched()` (§ Visual flavour). Fields such as a table of contents or page numbers fill in only when the file is rendered, so this is also where you see them.

If the output lost something the input had, that's a **fail**: say what was lost and offer the choices (re-add it, the user makes the edit in Word, or they accept the loss).

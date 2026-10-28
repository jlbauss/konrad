# Verification checklist — presentations

What "correct" means for a `.pptx` deliverable, whichever skill built it. The cycle, verdicts and retry budget are in `SKILL.md`; a deck gets both flavours: read the outline back against `task.md ## Success looks like`, then look at the rendered slides.

The `powerpoint` skill's scripts do the reading and rendering (`~/.config/opencode/skills/powerpoint/scripts/`):

```bash
P=~/.config/opencode/skills/powerpoint/scripts
python $P/pptx_read.py out.pptx --outline           # per slide: layout, texts, tables, charts, images, notes
python $P/pptx_render.py out.pptx --outdir <tmp>     # one PNG per slide (LibreOffice + pdftoppm)
```

- **Slides as asked.** Count and order match the spec; each slide's title sits in its title placeholder, so the outline lists it as the title rather than as loose text.
- **Data stays data.** A chart is a native chart whose categories and values match the source (`--outline` lists them), not a picture of one; a table is a table.
- **Every occurrence.** A rename reaches titles, body text, tables, chart titles and speaker notes.
- **Nothing lost** (editing an existing deck). Slides, images, charts and notes the task didn't touch are still there and unchanged; a removed or moved slide is the one the task named.
- **Notes where asked.** Speaker notes are in the notes, not on the slide.
- **It fits.** Render the slides and look: no text running off the slide or over another shape, nothing cut off, readable contrast. Start with the slides you touched (§ Visual flavour's progressive rule). Without vision, say the visual check was skipped.
- **UTF-8 intact.** Umlauts and other non-ASCII text read back cleanly.

If the output lost something the input had, that's a **fail**: say what was lost and offer the choices (re-add it, the user makes the edit in PowerPoint, or they accept the loss).

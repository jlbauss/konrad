# Verification checklist — presentations

What "correct" means for a `.pptx` deliverable. The cycle, verdicts and retry budget are in `SKILL.md`; a deck gets both flavours: read it back against `task.md ## Success looks like`, then look at the rendered slides.

```python
from pptx import Presentation          # read back: per slide its layout, title, shapes and notes
d = Presentation("out.pptx")
print(d.slide_width / 914400, "x", d.slide_height / 914400, "in")
for i, s in enumerate(d.slides, 1):
    print(i, s.slide_layout.name, repr(s.shapes.title.text if s.shapes.title else None))
    for sh in s.shapes:
        print("   ", sh.shape_type, round(sh.left / 914400, 2), round(sh.width / 914400, 2),
              sh.has_chart and sh.chart.chart_type, sh.has_text_frame and sh.text_frame.text[:60])
    print("    notes:", s.has_notes_slide and s.notes_slide.notes_text_frame.text)
```

```bash
soffice --headless --convert-to pdf --outdir /tmp/render out.pptx   # then rasterize_touched() on the PDF
```

- **Slides as asked.** Count and order match the spec; each slide's title sits in its title placeholder, so it reads back as the title rather than as loose text.
- **Centred on its slide.** Titles and body text span the slide. python-pptx's default template is drawn for a 10-inch 4:3 slide: on a 16:9 deck (13.33 inches), widen its placeholders, or titles sit in the left three quarters.
- **Data stays data.** A chart is a native chart whose categories and values match the source, not a picture of one; a table is a table.
- **Every occurrence.** A rename reaches titles, body text, tables, chart titles and speaker notes, and keeps their formatting (a renamed chart title keeps its size).
- **Nothing lost** (editing an existing deck). Slides, images, charts and notes the task didn't touch are still there and unchanged; a removed or moved slide is the one the task named.
- **Notes where asked.** Speaker notes are in the notes, not on the slide.
- **It fits.** Look at the rendered slides: no text running off the slide or over another shape, nothing cut off, readable contrast. Start with the slides you touched (§ Visual flavour's progressive rule). Without vision, say the visual check was skipped.
- **UTF-8 intact.** Umlauts and other non-ASCII text read back cleanly.

If the output lost something the input had, that's a **fail**: say what was lost and offer the choices (re-add it, the user makes the edit in PowerPoint, or they accept the loss).

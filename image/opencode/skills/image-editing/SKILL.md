---
name: image-editing
description: >
  Manipulate raster images: resize, rotate, flip, crop, pad, border,
  thumbnail (smart crop-to-fit), brightness / contrast / saturation,
  blur / sharpen, grayscale / sepia / tint, text & image watermarks,
  format conversion (JPEG / PNG / WebP / TIFF / HEIC), transparency
  operations (flatten, mask extract / apply, autocrop), color-space
  conversion, EXIF read / strip, DPI control, quality control, target
  file-size optimization, visual diff, and batch processing. Use this
  skill whenever the user wants to transform, convert, optimize, or
  inspect an image — "resize this", "convert to webp", "make a
  thumbnail", "reduce the file size", "rotate / flip", "add a
  watermark", "strip EXIF", "set the DPI", "compare these two images",
  "batch resize this folder". Trigger on image intent even when the
  extension is not spelled out — "the photo they sent", "this screenshot"
  count when context makes the raster image obvious.
license: MIT
compatibility: >
  Requires Python 3.10+. pillow, pillow-heif, and numpy are preinstalled
  in the konrad image's /opt/venv — the script runs against that venv
  directly, no `uv run` and no runtime dependency fetching (the konrad
  container is offline-sandboxed).
metadata:
  author: konrad
  version: "1.0"
  # Vendored from jlouage's Image-Editing-Claude-Skill (MIT). Attribution
  # lives in `REUSE.toml`. Adapted for konrad: invocation switched
  # from `uv run` (PEP 723 inline deps) to the baked /opt/venv, and a
  # quality-assurance verification step added before reporting.
---

# Image editing

A single CLI — `image_edit.py` — does every operation. It applies one or
more operations in a fixed pipeline order and emits structured JSON
describing what it produced. One invocation can chain many operations.

## Invocation

The script lives at `scripts/` relative to this file. Invoke it against
the baked venv with its full path:

```bash
python3 ~/.config/opencode/skills/image-editing/scripts/image_edit.py INPUT [OPTIONS]
```

Do **not** call it with `uv run` — the upstream skill did, but the konrad
image bakes `pillow`, `pillow-heif`, and `numpy` into `/opt/venv` and has
no network to fetch deps at runtime. Plain `python3` picks up the venv.

## Working conventions

- **Working directory.** Write outputs to `/workspace` (or the path the
  user gives). Never write into the skill folder.
- **The script never overwrites the input.** When `-o` is omitted it
  auto-names the output from the operations applied (`photo.png` +
  `--rotate 90 --sepia` → `photo_rotate_sepia.png`). Pass `-o` for an
  explicit path, or `--output=-` to stream the bytes to stdout for
  piping.
- **Don't read the image back to "check" it.** The output JSON already
  reports dimensions, file size, and the operations applied. To *verify*
  a visual result, use the quality-assurance cycle below — reading raw
  bytes back tells you nothing.
- **Refuse rather than over-promise.** This is raster editing via Pillow.
  Vector formats (SVG), animated GIF/APNG frames, RAW camera files, and
  AI background removal / generative fill are out of scope — say so
  plainly instead of producing a degraded result.

## Querying an image first

When you don't know an image's dimensions, format, or mode, ask before
editing:

```bash
python3 ~/.config/opencode/skills/image-editing/scripts/image_edit.py INPUT --info
```

Returns JSON with dimensions, format, file size, color mode, DPI, and
EXIF (if present). No output file is written.

## Operations

Operation flags can be combined in one call; they always apply in this
fixed pipeline order regardless of flag order:

> rotate → flip → autocrop → crop → thumbnail/resize → pad → border →
> brightness → contrast → saturation → blur → sharpen → mask → grayscale
> → sepia → tint → color-space → transparency → watermark → strip-exif → dpi

**Transforms**
- `--rotate ANGLE` — rotate counterclockwise (90 / 180 / 270, or any angle)
- `--flip horizontal|vertical` — mirror
- `--width W` / `--height H` — resize (aspect ratio preserved if only one given)
- `--thumbnail W,H` — smart center-crop to the target aspect, then resize to exact size
- `--crop PIXELS` — crop from edges (single, `V,H`, or `T,R,B,L`)
- `--pad PIXELS` [`--pad-color COLOR`] [`--pad-edge`] — add padding
- `--border PX` [`--border-color COLOR`] [`--border-inside`] — add a border

**Adjustments**
- `--brightness F` / `--contrast F` / `--saturation F` — 1.0 = unchanged, >1 stronger, <1 weaker (0 saturation = gray)
- `--blur R` — Gaussian blur, radius R
- `--sharpen A` — sharpen (1 = light, >1 = unsharp mask)

**Color effects**
- `--grayscale` — single-channel grayscale
- `--sepia` — sepia tone
- `--tint COLOR` [`--tint-strength S`] — color overlay, strength 0.0–1.0 (default 0.3)
- `--color-space SPACE` — RGB / CMYK / L / RGBA / P3

**Watermark**
- `--watermark-text TEXT` or `--watermark-image PATH`
- `--watermark-position` — top-left / top-right / bottom-left / bottom-right / center
- `--watermark-opacity A` — 0–255 (default 128)
- `--watermark-font-size PX` (text, default 24), `--watermark-color COLOR` (text, default white)
- `--watermark-scale S` — image watermark scale 0–1 (default 0.2)

**Quality & format** (output format follows the `-o` extension)
- `--quality Q` — 1–100 (JPEG/WebP; default JPEG 95, WebP 90)
- `--dpi DPI` — 72 screen / 150 web / 300 print
- `--max-size MB` — binary-search down to a target file size

**Transparency**
- `--remove-transparency` — flatten alpha onto white
- `--replace-transparency COLOR` — flatten alpha onto a color
- `--extract-mask` — save the alpha channel as a grayscale mask
- `--mask MASK_PATH` — apply a grayscale mask as the alpha channel
- `--autocrop-transparency THRESHOLD` — trim transparent borders (0–100%)

**EXIF** — `--strip-exif` removes all metadata; EXIF is otherwise preserved for JPEG/TIFF/WebP.

**Comparison** — `--diff PATH` writes a visual diff and reports `totalPixels`, `changedPixels`, `changePercent`, `meanDifference`.

**Batch** — `--batch` treats INPUT as a quoted glob (`"*.png"`); `-o` then names an output **directory**. Returns `totalFiles` / `successful` / `failed` / per-file `results`.

## Color formats

| Format | Examples |
|--------|----------|
| Named | `red`, `coral`, `darkslategray` (140+ CSS colors) |
| Hex | `#RGB`, `#RRGGBB`, `#RRGGBBAA` |
| RGB | `255,128,0` or `rgb(255,128,0)` |
| HSL | `hsl(120,100%,50%)` |

## Quality guide

| Use case | Format | Quality | DPI |
|----------|--------|---------|-----|
| Web / screen | WebP | 80–85 | 72 |
| Social media | JPEG | 85–90 | 72 |
| Print (standard) | JPEG/PNG | 95 | 150 |
| Print (high quality) | TIFF/PNG | 100 | 300 |
| Thumbnail | WebP | 70–75 | 72 |
| Archive | PNG | — | original |

## Examples

```bash
SKILL=~/.config/opencode/skills/image-editing/scripts/image_edit.py

# Resize + adjust + sepia + border + print DPI, in one pass
python3 "$SKILL" input.png -o output.jpg \
  --rotate 90 --width 800 \
  --brightness 1.2 --contrast 1.1 \
  --border 3 --border-color coral --sepia \
  --quality 85 --dpi 150

# Exact thumbnail with smart crop-to-fit
python3 "$SKILL" input.png --thumbnail 300,300 -o thumb.png

# Format conversion (extension drives the format)
python3 "$SKILL" input.heic -o output.jpg
python3 "$SKILL" input.png  -o output.webp

# Text watermark
python3 "$SKILL" input.png --watermark-text "© 2026" \
  --watermark-position center --watermark-opacity 180 \
  --watermark-font-size 48 --watermark-color red -o watermarked.png

# Reduce to a target file size
python3 "$SKILL" big.jpg --max-size 0.5 -o small.jpg

# Batch-resize a folder
python3 "$SKILL" "*.png" --width 800 --batch -o /workspace/out

# Visual diff between two images
python3 "$SKILL" before.png --diff after.png -o diff.png
```

## Verify before reporting

Editing, conversion, watermarking, thumbnailing, and diff all produce a
**visual deliverable** — invoke the **`quality-assurance`** skill before
reporting. It carries the verification cycle, the progressive-verification
rule, the post-rasterize "read the PNG or declare skipped honestly"
contract, the retry policy, and the evidence-directory convention. For an
image, "rasterize" is just looking at the output file; for HEIC or other
formats the agent's `read` tool can't display, first convert a copy to
PNG with this same script, then look at that.

After verifying, report: the output path, final dimensions, file size,
the operations applied, and any non-default quality/DPI — plus the
quality-assurance verdict using the canonical phrasings from that skill
(pass / pass-with-caveat / fail / skipped-with-reason).

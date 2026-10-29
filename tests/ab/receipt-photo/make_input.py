# SPDX-FileCopyrightText: 2026 Jan-Luca Bauß
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Regenerate input/beleg.jpg (committed, so every trial starts from the same bytes).

Run in a konrad image. A till receipt drawn on off-white paper, slightly
rotated, on a darker table, with some noise and JPEG compression: no text
layer, so reading it takes the model's eyes or OCR.

    podman run --rm -v "$PWD/tests/ab/receipt-photo:/t:z" --entrypoint /opt/venv/bin/python \\
        konrad:local /t/make_input.py /t/input/beleg.jpg
"""

import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

MONO = "/usr/share/fonts/truetype/noto/NotoSansMono-"
LINES = [
    ("B", "Bürobedarf Schulze"), ("", "Musterstraße 211"), ("", "12345 Musterstadt"), ("", ""),
    ("", "14.10.2026        16:42"), ("", "Bon 0087   Kasse 2"), ("", "-" * 28),
    ("", "Kopierpapier A4 5x500"), ("", "  2 x 21,90       43,80"), ("", "Ordner breit blau"),
    ("", "  6 x  3,45       20,70"), ("", "Gelstifte 10er"), ("", "  1 x 12,95       12,95"),
    ("", "Haftnotizen 76x76"), ("", "  1 x  9,95        9,95"), ("", "-" * 28),
    ("B", "SUMME EUR         87,40"), ("", ""), ("", "Gegeben girocard  87,40"), ("", ""),
    ("", "MwSt   Netto   Steuer"), ("", "A 19%  73,45    13,95"), ("", ""), ("", "Vielen Dank für Ihren Einkauf!"),
]


def main(out):
    rnd = random.Random(7)
    reg, bold = ImageFont.truetype(MONO + "Regular.ttf", 30), ImageFont.truetype(MONO + "Bold.ttf", 34)
    paper = Image.new("RGB", (620, 60 + 46 * len(LINES)), (247, 244, 236))
    d = ImageDraw.Draw(paper)
    for i, (kind, text) in enumerate(LINES):
        font = bold if kind == "B" else reg
        x = (620 - d.textlength(text, font=font)) / 2 if i < 3 or i == len(LINES) - 1 else 40
        d.text((x, 30 + 46 * i), text, font=font, fill=(40 + rnd.randint(0, 25),) * 3)
    paper = paper.rotate(-2.5, expand=True, fillcolor=(92, 78, 64), resample=Image.BICUBIC)
    photo = Image.new("RGB", (paper.width + 160, paper.height + 160), (92, 78, 64))
    photo.paste(paper, (80, 70))
    px = photo.load()
    for _ in range(photo.width * photo.height // 12):
        x, y = rnd.randrange(photo.width), rnd.randrange(photo.height)
        r, g, b = px[x, y]
        n = rnd.randint(-18, 18)
        px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))
    photo.filter(ImageFilter.GaussianBlur(0.8)).save(out, "JPEG", quality=72)


if __name__ == "__main__":
    main(sys.argv[1])

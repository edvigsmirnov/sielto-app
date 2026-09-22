"""Cuts the Sielto mark out of a rendered icon sheet onto transparency.

    python tools/extract_mark.py <source.png>

The source is artwork delivered as a flat image: a pale leaf wreath embossed
on a green rounded plate, on a pale ground. The plate is found by its
greenness and cropped inside its corners. The leaves are lighter than the
plate around them, so the alpha is each pixel's lightness above a local plate
estimate — local, because the plate is shaded and a single threshold would cut
one corner and flood the other.

The ink is recoloured flat to the `accent` token: the emboss shading belongs to
the render, not the mark. Writes `tools/sielto_mark.png`, which `make_icon.py`
reads. Needs Pillow and numpy. Only rerun this when new artwork arrives.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

_HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(_HERE, 'sielto_mark.png')

# Sage `accent`, light theme.
INK = (0x8F, 0xB9, 0x96)

# Share of the plate's width trimmed off each side, clearing the corners.
INSET = 0.08

# Wider than any leaf, so the min filter sees only plate.
PLATE_WINDOW = 41

# Lightness above the plate estimate: the plate stays under ~48, the leaves
# start past ~64.
FLOOR = 50.0
RAMP = 10.0


def extract(path):
    src = Image.open(path).convert('RGB')
    a = np.asarray(src).astype(np.int16)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]

    green = (g > r + 15) & (g > b + 10)
    if not green.any():
        raise SystemExit('no green plate found in %s' % path)
    ys, xs = np.nonzero(green)
    inset = int((xs.max() - xs.min()) * INSET)
    plate = src.crop((
        xs.min() + inset, ys.min() + inset,
        xs.max() - inset, ys.max() - inset,
    ))

    lum = plate.convert('L')
    ground = lum.filter(ImageFilter.MinFilter(PLATE_WINDOW)).filter(
        ImageFilter.GaussianBlur(25))
    lift = np.asarray(lum, np.float32) - np.asarray(ground, np.float32)
    alpha = Image.fromarray(
        (np.clip((lift - FLOOR) / RAMP, 0.0, 1.0) * 255.0).astype(np.uint8))

    img = Image.new('RGBA', plate.size, INK + (0,))
    img.putalpha(alpha)
    return img.crop(img.getbbox())


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    mark = extract(sys.argv[1])
    mark.save(OUT)
    print('%s  %dx%d' % (OUT, mark.width, mark.height))

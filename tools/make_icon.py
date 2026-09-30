"""Generates the Sielto icons and brand assets for every platform.

    python tools/make_icon.py .

Two masters, both 1024 px squares from the delivered packs:

- `tools/icon/app_icon.png` — the wallet and sprout on textured sage, full
  bleed. Becomes the launcher icons, the Linux PNG and the Windows ICO.
- `tools/icon/wordmark.png` — "sielto" on flat dark green. Cropped to the text
  for the welcome screen; its green is `SageBrand.night` and the splash colour.

Needs Pillow. Writes everything in place. Set SCRATCH to also get proof sheets
at 512 and 48.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

_HERE = os.path.dirname(os.path.abspath(__file__))
APP_ICON = os.path.join(_HERE, 'icon', 'app_icon.png')
WORDMARK = os.path.join(_HERE, 'icon', 'wordmark.png')
SS = 8

# The wordmark's text with an even margin, in master pixels. The background is
# flat to within 1/255 except for the embossing's faint halo around the
# letters, which showed as a box at the crop's edge; the edge is faded out.
WORDMARK_CROP = (90, 330, 934, 675)
WORDMARK_FEATHER = 36

# Launcher densities: legacy icon, adaptive layer (108dp), splash circle (192dp).
# The splash canvas is 288dp, Android 12's size for an icon without background.
DENSITIES = {
    'mdpi': (48, 108, 192), 'hdpi': (72, 162, 288), 'xhdpi': (96, 216, 384),
    'xxhdpi': (144, 324, 576), 'xxxhdpi': (192, 432, 768),
}

# How much of the adaptive layer the artwork covers. Android shows the middle
# 72dp of 108 and a round mask keeps 66dp of it; the sprout's tip and the
# wallet's base sit near the master's edges, so the whole square shrinks until
# they clear the circle. The layer behind is the same artwork, larger and
# blurred, so the shrunk square has no visible edge.
ADAPTIVE_ART = 0.74


def art(size):
    return Image.open(APP_ICON).convert('RGBA').resize((size, size), Image.LANCZOS)


def rounded(size, radius_ratio=0.22):
    """The artwork with rounded corners, for launchers that do not mask."""
    n = size * SS
    mask = Image.new('L', (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, n - 1, n - 1], radius=int(n * radius_ratio), fill=255,
    )
    out = art(size)
    out.putalpha(mask.resize((size, size), Image.LANCZOS))
    return out


def feathered(size, edge_ratio=0.06):
    """The artwork with its outer edge faded to nothing."""
    out = art(size)
    edge = max(1, int(size * edge_ratio))
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rectangle(
        [edge, edge, size - 1 - edge, size - 1 - edge], fill=255,
    )
    out.putalpha(mask.filter(ImageFilter.GaussianBlur(edge / 2)))
    return out


def adaptive_background(layer):
    return art(layer).filter(ImageFilter.GaussianBlur(layer / 40))


def adaptive_foreground(layer):
    canvas = Image.new('RGBA', (layer, layer), (0, 0, 0, 0))
    inner = int(layer * ADAPTIVE_ART)
    canvas.alpha_composite(feathered(inner), ((layer - inner) // 2,) * 2)
    return canvas


def adaptive_preview(layer, circle):
    """What a launcher draws: both layers, the middle 72dp, masked."""
    full = adaptive_background(layer)
    full.alpha_composite(adaptive_foreground(layer))
    shown = int(layer * 72 / 108)
    off = (layer - shown) // 2
    view = full.crop((off, off, off + shown, off + shown))
    mask = Image.new('L', (shown, shown), 0)
    draw = ImageDraw.Draw(mask)
    if circle:
        draw.ellipse([0, 0, shown - 1, shown - 1], fill=255)
    else:
        draw.rounded_rectangle([0, 0, shown - 1, shown - 1],
                               radius=int(shown * 0.3), fill=255)
    view.putalpha(mask)
    return view


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    scratch = os.environ.get('SCRATCH')
    res = os.path.join(root, 'android', 'app', 'src', 'main', 'res')

    for name, (legacy, layer, splash) in DENSITIES.items():
        folder = os.path.join(res, 'mipmap-%s' % name)
        os.makedirs(folder, exist_ok=True)
        rounded(legacy).save(os.path.join(folder, 'ic_launcher.png'))
        drawables = os.path.join(res, 'drawable-%s' % name)
        os.makedirs(drawables, exist_ok=True)
        canvas = Image.new('RGBA', (splash * 3 // 2,) * 2, (0, 0, 0, 0))
        canvas.alpha_composite(
            adaptive_preview(splash * 108 // 72, circle=True),
            (splash // 4, splash // 4))
        canvas.save(os.path.join(drawables, 'splash_icon.webp'),
                    lossless=False, quality=92, method=6)
        adaptive_foreground(layer).save(
            os.path.join(folder, 'ic_launcher_foreground.png'))
        adaptive_background(layer).convert('RGB').save(
            os.path.join(folder, 'ic_launcher_background.png'))

    rounded(512).save(
        os.path.join(root, 'linux', 'runner', 'resources', 'sielto.png'))
    rounded(256).save(
        os.path.join(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
        sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)],
    )

    brand = os.path.join(root, 'assets', 'brand')
    os.makedirs(brand, exist_ok=True)
    mark = Image.open(WORDMARK).convert('RGBA').crop(WORDMARK_CROP)
    fade = Image.new('L', mark.size, 0)
    ImageDraw.Draw(fade).rectangle(
        [WORDMARK_FEATHER, WORDMARK_FEATHER,
         mark.width - 1 - WORDMARK_FEATHER, mark.height - 1 - WORDMARK_FEATHER],
        fill=255,
    )
    mark.putalpha(fade.filter(ImageFilter.GaussianBlur(WORDMARK_FEATHER / 2)))
    mark.save(os.path.join(brand, 'wordmark.png'), optimize=True)
    # What the Android 12 splash draws — the adaptive icon in its circle — so
    # Flutter's first frame can take over from it without a visible change.
    adaptive_preview(864, circle=True).save(
        os.path.join(brand, 'splash_icon.png'), optimize=True)

    if scratch:
        sheet = Image.new('RGBA', (512 * 3 + 40, 512), (255, 255, 255, 255))
        sheet.alpha_composite(rounded(512), (0, 0))
        sheet.alpha_composite(
            adaptive_preview(768, circle=True).resize((512, 512)), (532, 0))
        sheet.alpha_composite(
            adaptive_preview(768, circle=False).resize((512, 512)), (1064, 0))
        sheet.save(os.path.join(scratch, 'icon_preview.png'))
        # Small, where a mark either survives or does not.
        rounded(48).resize((192, 192), Image.NEAREST).save(
            os.path.join(scratch, 'icon_small.png'))
    print('done')

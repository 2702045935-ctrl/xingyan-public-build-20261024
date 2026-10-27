from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SIZE = 2048
CENTER = SIZE / 2


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def bezier(p0, p1, p2, p3, t: float):
    u = 1 - t
    return (
        u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
        u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
    )


def star_mask(size: int, outer: float, inner: float) -> Image.Image:
    """Four-point star with softly curved arms, centred on a transparent canvas."""
    c = size / 2
    points = [
        (c, c - outer),
        (c + inner, c - inner),
        (c + outer * 0.84, c),
        (c + inner, c + inner),
        (c, c + outer),
        (c - inner, c + inner),
        (c - outer * 0.84, c),
        (c - inner, c - inner),
    ]

    def catmull_rom(p0, p1, p2, p3, t: float):
        t2, t3 = t * t, t * t * t
        return (
            0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t
                   + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                   + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3),
            0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t
                   + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                   + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3),
        )

    curve = []
    for i in range(len(points)):
        p0 = points[(i - 1) % len(points)]
        p1 = points[i]
        p2 = points[(i + 1) % len(points)]
        p3 = points[(i + 2) % len(points)]
        for step in range(24):
            curve.append(catmull_rom(p0, p1, p2, p3, step / 24))

    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).polygon(curve, fill=255)
    return m


def diagonal_gradient(size: int, top: tuple[int, int, int],
                      bottom: tuple[int, int, int]) -> Image.Image:
    y, x = np.mgrid[0:size, 0:size]
    t = np.clip((x * 0.34 + y * 0.66) / (size - 1), 0, 1)
    arr = np.zeros((size, size, 3), dtype=np.uint8)
    for i in range(3):
        arr[..., i] = (top[i] + (bottom[i] - top[i]) * t).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def build_icon() -> Image.Image:
    bg = diagonal_gradient(SIZE, (16, 48, 39), (4, 13, 11)).convert("RGBA")

    # A restrained central atmosphere keeps the icon dimensional without looking glossy.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((330, 240, 1718, 1628), fill=(45, 150, 119, 48))
    glow = glow.filter(ImageFilter.GaussianBlur(190))
    bg = Image.alpha_composite(bg, glow)

    # Tilted orbit, one quiet jade ellipse and one champagne-gold ellipse.
    ring = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.ellipse((318, 704, 1730, 1360), outline=(112, 203, 169, 86), width=22)
    ring = ring.rotate(-27, resample=Image.Resampling.BICUBIC, center=(CENTER, CENTER))
    ring = ring.filter(ImageFilter.GaussianBlur(0.7))
    bg = Image.alpha_composite(bg, ring)

    ring2 = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rd2 = ImageDraw.Draw(ring2)
    rd2.arc((430, 760, 1618, 1308), 194, 338, fill=(224, 196, 132, 176), width=27)
    ring2 = ring2.rotate(-27, resample=Image.Resampling.BICUBIC, center=(CENTER, CENTER))
    bg = Image.alpha_composite(bg, ring2)

    # Main four-point star: ivory at the crown, warm champagne gold at the roots.
    mask = star_mask(1500, 720, 208)
    star_layer = Image.new("RGBA", (1500, 1500), (0, 0, 0, 0))
    gold = diagonal_gradient(1500, (255, 249, 226), (207, 161, 86)).convert("RGBA")
    gold.putalpha(mask)
    star_layer.alpha_composite(gold)
    star_layer = star_layer.resize((SIZE, SIZE), Image.Resampling.LANCZOS)

    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 105), (0, 0), star_layer.getchannel("A"))
    shadow = shadow.filter(ImageFilter.GaussianBlur(48))
    shadow = ImageChops.offset(shadow, 0, 34)
    bg = Image.alpha_composite(bg, shadow)
    bg = Image.alpha_composite(bg, star_layer)

    # A clipped inner highlight makes the mark feel cut from solid material.
    shine = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    sd.ellipse((740, 280, 1300, 840), fill=(255, 255, 248, 28))
    shine.putalpha(ImageChops.multiply(shine.getchannel("A"), star_layer.getchannel("A")))
    bg = Image.alpha_composite(bg, shine)

    d = ImageDraw.Draw(bg)
    # Two satellites on the orbit become readable at very small sizes.
    d.ellipse((1510, 510, 1570, 570), fill=(255, 250, 231, 238))
    d.ellipse((1488, 488, 1592, 592), outline=(255, 250, 231, 42), width=8)
    d.ellipse((482, 1435, 520, 1473), fill=(112, 203, 169, 205))

    # Very low-contrast inner rim gives the icon a crafted edge without text.
    rim = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle((3, 3, SIZE - 4, SIZE - 4), radius=448,
                                          outline=(247, 245, 239, 28), width=5)
    return Image.alpha_composite(bg, rim).convert("RGB")


def main() -> None:
    icon = build_icon()
    icon.resize((1024, 1024), Image.Resampling.LANCZOS).save(
        ROOT / "app-icon-starorbit-1024.png", optimize=True
    )
    icon.resize((120, 120), Image.Resampling.LANCZOS).save(
        ROOT / "AppIcon60x60@2x.png", optimize=True
    )
    icon.resize((180, 180), Image.Resampling.LANCZOS).save(
        ROOT / "AppIcon60x60@3x.png", optimize=True
    )


if __name__ == "__main__":
    main()

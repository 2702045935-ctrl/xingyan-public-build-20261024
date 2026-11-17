from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "server" / "public" / "emoji" / "nova-courier"

SIZE = 320
SUPERSAMPLE = 2
S = SIZE * SUPERSAMPLE
FRAME_COUNT = 20
FRAME_MS = 72
CHARACTER_SIDE = 410.0

# Xingyan's first-party emoji system. These colours are deliberately limited:
# midnight cobalt, porcelain, a light signal-blue and one warm accent.
COBALT_DEEP = (7, 17, 42, 255)
COBALT = (37, 91, 242, 255)
COBALT_LIGHT = (112, 184, 255, 255)
PORCELAIN = (255, 250, 237, 255)
PORCELAIN_SHADE = (226, 228, 229, 255)
INK = (11, 18, 32, 255)
WHITE_BLUE = (236, 248, 255, 255)
CORAL = (255, 105, 92, 255)
GOLD = (255, 202, 96, 255)
MINT = (109, 228, 193, 255)

SPECS = [
    ("收到", "shou-dao", "check"),
    ("在呢", "zai-ne", "presence"),
    ("等等", "deng-deng", "wait"),
    ("谢谢", "xie-xie", "thanks"),
    ("笑死", "xiao-si", "laugh"),
    ("震惊", "zhen-jing", "shock"),
    ("无语", "wu-yu", "speechless"),
    ("抱抱", "bao-bao", "hug"),
    ("晚安", "wan-an", "night"),
    ("听歌", "ting-ge", "music"),
    ("想你", "xiang-ni", "miss"),
    ("赞", "zan", "like"),
    ("冲", "chong", "boost"),
    ("拒绝", "ju-jue", "decline"),
    ("摸鱼", "mo-yu", "slack"),
    ("开会", "kai-hui", "meeting"),
]


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def smoothstep(a: float, b: float, value: float) -> float:
    if a == b:
        return float(value >= b)
    x = clamp((value - a) / (b - a))
    return x * x * (3.0 - 2.0 * x)


def mix(a: tuple[int, ...], b: tuple[int, ...], amount: float) -> tuple[int, ...]:
    return tuple(round(a[i] + (b[i] - a[i]) * amount) for i in range(4))


def wave(value: float, turns: float = 1.0, phase: float = 0.0) -> float:
    return math.sin((value * turns + phase) * math.tau)


def rgba(color: tuple[int, ...], alpha: float) -> tuple[int, int, int, int]:
    return color[0], color[1], color[2], round(clamp(alpha, 0.0, 1.0) * color[3])


def body_gradient(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = image.load()
    for y in range(size):
        py = y / max(1, size - 1)
        for x in range(size):
            px = x / max(1, size - 1)
            diagonal = clamp(px * 0.52 + py * 0.48)
            color = (mix(COBALT_LIGHT, COBALT, smoothstep(0.0, 0.58, diagonal))
                     if diagonal < 0.58
                     else mix(COBALT, COBALT_DEEP, smoothstep(0.58, 1.0, diagonal)))
            rim = clamp(1.0 - abs(px - 0.18) * 0.72 - abs(py - 0.15) * 0.58)
            color = mix(color, WHITE_BLUE, max(0.0, rim - 0.72) * 0.34)
            pixels[x, y] = color
    return image


BODY_GRADIENT = body_gradient(S)


def draw_arc(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    rx: float,
    ry: float,
    start: float,
    end: float,
    fill: tuple[int, ...],
    width: int,
    tilt: float = 0.0,
) -> None:
    points: list[tuple[float, float]] = []
    steps = max(10, int(abs(end - start) * 48))
    ct, st = math.cos(tilt), math.sin(tilt)
    for index in range(steps + 1):
        angle = start + (end - start) * index / steps
        x = rx * math.cos(angle)
        y = ry * math.sin(angle)
        points.append((cx + x * ct - y * st, cy + x * st + y * ct))
    if len(points) > 1:
        draw.line(points, fill=fill, width=width, joint="curve")


def draw_star(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    radius: float,
    color: tuple[int, ...],
    rotation: float = 0.0,
) -> None:
    points: list[tuple[float, float]] = []
    for index in range(8):
        angle = rotation - math.pi / 2 + index * math.pi / 4
        r = radius if index % 2 == 0 else radius * 0.22
        points.append((cx + math.cos(angle) * r, cy + math.sin(angle) * r))
    draw.polygon(points, fill=color)


def draw_heart(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    scale: float,
    color: tuple[int, ...],
) -> None:
    radius = 12 * scale
    draw.ellipse((cx - 2 * radius, cy - radius, cx, cy + radius), fill=color)
    draw.ellipse((cx, cy - radius, cx + 2 * radius, cy + radius), fill=color)
    draw.polygon(
        [(cx - 2 * radius + 1, cy + 3 * scale),
         (cx + 2 * radius - 1, cy + 3 * scale),
         (cx, cy + 2.25 * radius)],
        fill=color,
    )


def draw_check(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    scale: float,
    color: tuple[int, ...],
) -> None:
    width = max(3, round(8 * scale))
    draw.line(
        [(cx - 24 * scale, cy),
         (cx - 7 * scale, cy + 17 * scale),
         (cx + 28 * scale, cy - 22 * scale)],
        fill=color,
        width=width,
        joint="curve",
    )


def draw_music_note(
    draw: ImageDraw.ImageDraw,
    cx: float,
    cy: float,
    scale: float,
    color: tuple[int, ...],
) -> None:
    width = max(2, round(4.5 * scale))
    draw.ellipse((cx - 12 * scale, cy + 12 * scale,
                  cx + 1 * scale, cy + 25 * scale), fill=color)
    draw.ellipse((cx + 12 * scale, cy + 7 * scale,
                  cx + 25 * scale, cy + 20 * scale), fill=color)
    draw.line((cx, cy + 17 * scale, cx, cy - 24 * scale), fill=color, width=width)
    draw.line((cx + 23 * scale, cy + 13 * scale,
               cx + 23 * scale, cy - 28 * scale), fill=color, width=width)
    draw.line((cx, cy - 24 * scale, cx + 23 * scale, cy - 28 * scale),
              fill=color, width=max(2, round(6 * scale)))


def draw_moon(
    frame: Image.Image,
    cx: float,
    cy: float,
    scale: float,
    color: tuple[int, ...],
) -> None:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    radius = 25 * scale
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color)
    cut = 23 * scale
    draw.ellipse(
        (cx - cut + 10 * scale, cy - cut - 7 * scale,
         cx + cut + 10 * scale, cy + cut - 7 * scale),
        fill=(0, 0, 0, 0),
    )
    frame.alpha_composite(layer)


def body_mask(side: float, cx: float, cy: float) -> Image.Image:
    mask = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(mask)
    radius = round(side * 0.29)
    draw.rounded_rectangle(
        (cx - side / 2, cy - side / 2,
         cx + side / 2, cy + side / 2),
        radius=radius,
        fill=255,
    )
    # A clipped comet fin gives the mascot an original silhouette without
    # adding a visual weight that disappears in small emoji rows.
    fin = [
        (cx - side * 0.44, cy - side * 0.02),
        (cx - side * 0.55, cy - side * 0.23),
        (cx - side * 0.30, cy - side * 0.22),
    ]
    draw.polygon(fin, fill=255)
    return mask


def draw_orbital_signal(frame: Image.Image, t: float, cx: float, cy: float, side: float) -> None:
    draw = ImageDraw.Draw(frame, "RGBA")
    ring_alpha = 0.16 + 0.05 * (0.5 + 0.5 * wave(t, 1))
    draw_arc(
        draw,
        cx,
        cy - side * 0.01,
        side * 0.57,
        side * 0.30,
        math.pi * 1.03,
        math.pi * 1.88,
        rgba(COBALT_LIGHT, ring_alpha),
        max(2, round(2.1 * SUPERSAMPLE)),
        tilt=-0.24,
    )
    angle = -2.72 + t * math.tau
    x = cx + math.cos(angle) * side * 0.57
    y = cy - side * 0.01 + math.sin(angle) * side * 0.30
    px = cx + (x - cx) * math.cos(-0.24) - (y - cy) * math.sin(-0.24)
    py = cy + (x - cx) * math.sin(-0.24) + (y - cy) * math.cos(-0.24)
    radius = 4.3 * SUPERSAMPLE
    draw_star(draw, px, py, radius, rgba(GOLD, 0.98), rotation=t * math.tau * 0.5)


def draw_character(
    frame: Image.Image,
    t: float,
    kind: str,
    *,
    cx: float,
    cy: float,
    scale: float,
    blink: float,
    blush: float,
    look: tuple[float, float],
    mood: str,
) -> None:
    side = CHARACTER_SIDE * scale
    left = round(cx - side / 2)
    top = round(cy - side / 2)

    draw_orbital_signal(frame, t, cx, cy, side)

    # Studio shadow keeps the white porcelain face visible on light wallpapers.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.ellipse(
        (cx - side * 0.40, cy + side * 0.24,
         cx + side * 0.40, cy + side * 0.50),
        fill=(3, 11, 30, 72),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(16 * SUPERSAMPLE))
    frame.alpha_composite(shadow)

    mask = body_mask(side, cx, cy)
    body_layer = BODY_GRADIENT.copy()
    body_layer.putalpha(mask)
    frame.alpha_composite(body_layer)

    # Thin ceramic rim and a directional sheen: two restrained light passes.
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim)
    rim_draw.rounded_rectangle(
        (left, top, left + side, top + side),
        radius=round(side * 0.29),
        outline=rgba(COBALT_LIGHT, 0.82),
        width=max(2, round(2.3 * SUPERSAMPLE)),
    )
    rim_draw.line(
        [
            (cx - side * 0.44, cy - side * 0.02),
            (cx - side * 0.55, cy - side * 0.23),
            (cx - side * 0.30, cy - side * 0.22),
        ],
        fill=rgba(COBALT_LIGHT, 0.74),
        width=max(2, round(2.0 * SUPERSAMPLE)),
        joint="curve",
    )
    frame.alpha_composite(rim)

    shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shine_draw = ImageDraw.Draw(shine)
    shine_draw.ellipse(
        (cx - side * 0.30, cy - side * 0.37,
         cx - side * 0.01, cy - side * 0.22),
        fill=(239, 250, 255, 84),
    )
    shine = shine.filter(ImageFilter.GaussianBlur(8 * SUPERSAMPLE))
    frame.alpha_composite(shine)

    d = ImageDraw.Draw(frame, "RGBA")

    # Asymmetric porcelain mask: recognisable at 28 pt and materially different
    # from a standard smiley or a human-style sticker.
    face = (
        cx - side * 0.27,
        cy - side * 0.12,
        cx + side * 0.25,
        cy + side * 0.29,
    )
    d.rounded_rectangle(face, radius=round(side * 0.21), fill=PORCELAIN)
    d.arc(
        (face[0] + side * 0.02, face[1] + side * 0.02,
         face[2] - side * 0.02, face[3] - side * 0.02),
        start=193,
        end=348,
        fill=rgba(PORCELAIN_SHADE, 0.72),
        width=max(1, round(1.5 * SUPERSAMPLE)),
    )

    # A tiny brand-blue forehead jewel anchors the character across all moods.
    jewel_x = cx + side * 0.18
    jewel_y = cy - side * 0.035
    draw_star(d, jewel_x, jewel_y, side * 0.032,
              rgba(COBALT, 0.96), rotation=0.18)

    eye_y = cy + side * 0.085
    eye_dx = side * 0.132
    eye_w = side * 0.064
    eye_h = side * 0.145
    lx = look[0] * side * 0.020
    ly = look[1] * side * 0.014
    window = max(0.035, 1.0 - blink)
    stroke = max(3, round(5.3 * SUPERSAMPLE * scale))

    for index in (-1, 1):
        ex = cx + index * eye_dx + lx
        ey = eye_y + ly
        if mood in {"speechless", "night"}:
            d.line(
                [(ex - eye_w * 0.62, ey), (ex + eye_w * 0.62, ey)],
                fill=INK,
                width=stroke,
            )
            if mood == "night":
                d.line(
                    [(ex - eye_w * 0.50, ey + side * 0.040),
                     (ex + eye_w * 0.50, ey + side * 0.040)],
                    fill=INK,
                    width=max(2, round(3.0 * SUPERSAMPLE)),
                )
        elif mood == "laugh":
            draw_arc(
                d, ex, ey + side * 0.020, eye_w * 0.72, eye_h * 0.38,
                math.pi * 1.08, math.pi * 1.92, INK, stroke,
            )
        elif mood == "decline":
            d.line(
                [(ex - eye_w * 0.54, ey - eye_h * 0.20),
                 (ex + eye_w * 0.54, ey + eye_h * 0.20)],
                fill=INK, width=stroke,
            )
            d.line(
                [(ex - eye_w * 0.54, ey + eye_h * 0.20),
                 (ex + eye_w * 0.54, ey - eye_h * 0.20)],
                fill=INK, width=stroke,
            )
        else:
            height = eye_h * window * (1.10 if mood == "shock" else 1.0)
            width = eye_w * (1.18 if mood == "shock" else 1.0)
            d.rounded_rectangle(
                (ex - width / 2, ey - height / 2,
                 ex + width / 2, ey + height / 2),
                radius=min(width, height) / 2,
                fill=INK,
            )
            if window > 0.44:
                r = max(1.6, 2.3 * SUPERSAMPLE * scale)
                d.ellipse(
                    (ex - width * 0.13 - r, ey - height * 0.20 - r,
                     ex - width * 0.13 + r, ey - height * 0.20 + r),
                    fill=(247, 253, 255, 238),
                )

    if blush > 0.01:
        for index in (-1, 1):
            bx = cx + index * side * 0.233
            by = cy + side * 0.225
            d.ellipse(
                (bx - side * 0.055, by - side * 0.019,
                 bx + side * 0.055, by + side * 0.019),
                fill=(255, 151, 147, round(104 * blush)),
            )

    mouth_y = cy + side * 0.225
    if mood == "shock":
        d.ellipse(
            (cx - side * 0.027, mouth_y - side * 0.031,
             cx + side * 0.027, mouth_y + side * 0.031),
            fill=INK,
        )
    elif mood == "speechless":
        d.line(
            [(cx - side * 0.056, mouth_y), (cx + side * 0.056, mouth_y)],
            fill=INK,
            width=max(2, round(3.6 * SUPERSAMPLE * scale)),
        )
    elif mood == "laugh":
        d.arc(
            (cx - side * 0.083, mouth_y - side * 0.044,
             cx + side * 0.083, mouth_y + side * 0.053),
            start=14, end=166,
            fill=INK, width=max(2, round(3.8 * SUPERSAMPLE * scale)),
        )
    elif mood == "decline":
        d.arc(
            (cx - side * 0.064, mouth_y + side * 0.010,
             cx + side * 0.064, mouth_y + side * 0.070),
            start=195, end=345,
            fill=INK, width=max(2, round(3.4 * SUPERSAMPLE * scale)),
        )
    elif mood != "night":
        d.arc(
            (cx - side * 0.052, mouth_y - side * 0.040,
             cx + side * 0.052, mouth_y + side * 0.041),
            start=18, end=162,
            fill=INK, width=max(2, round(3.4 * SUPERSAMPLE * scale)),
        )

    # Antenna star is part of the character and doubles as a subtle animation
    # beat while the face itself remains stable.
    antenna_y = cy - side * 0.46 + wave(t, 1) * side * 0.012
    d.line(
        [(cx + side * 0.11, cy - side * 0.39),
         (cx + side * 0.14, antenna_y + side * 0.030)],
        fill=rgba(COBALT_LIGHT, 0.88),
        width=max(2, round(2.0 * SUPERSAMPLE)),
    )
    draw_star(
        d,
        cx + side * 0.145,
        antenna_y,
        side * 0.050,
        rgba(GOLD, 0.98),
        rotation=t * math.tau * 0.35,
    )


def draw_effect(
    frame: Image.Image,
    kind: str,
    t: float,
    cx: float,
    cy: float,
    side: float,
) -> None:
    d = ImageDraw.Draw(frame, "RGBA")
    enter = smoothstep(0.0, 0.15, t)
    leave = 1.0 - smoothstep(0.83, 1.0, t)
    visible = enter * leave
    if visible <= 0:
        return

    if kind == "check":
        pulse = 1.0 + 0.08 * wave(t, 1)
        draw_check(
            d,
            cx + side * 0.43,
            cy + side * 0.23,
            1.35 * SUPERSAMPLE * pulse,
            rgba(MINT, visible),
        )
        draw_star(d, cx - side * 0.46, cy + side * 0.21,
                  side * 0.032 * visible, rgba(GOLD, visible))
    elif kind == "presence":
        radius = (0.55 + 0.45 * abs(wave(t, 1))) * side * 0.075
        x = cx + side * 0.44
        y = cy + side * 0.25
        d.ellipse((x - radius, y - radius, x + radius, y + radius),
                  fill=rgba(MINT, visible * 0.22))
        d.ellipse((x - side * 0.040, y - side * 0.040,
                   x + side * 0.040, y + side * 0.040),
                  fill=rgba(MINT, visible))
    elif kind == "wait":
        for index in range(3):
            phase = (t + index / 3.0) % 1.0
            alpha = 0.32 + 0.68 * math.sin(phase * math.pi)
            x = cx + side * (0.30 + index * 0.095)
            y = cy + side * 0.44 - math.sin(phase * math.pi) * side * 0.025
            radius = side * 0.017
            d.ellipse((x - radius, y - radius, x + radius, y + radius),
                      fill=rgba(WHITE_BLUE, alpha * visible))
    elif kind == "thanks":
        for index, (angle, distance, size) in enumerate(
            [(-2.45, 0.48, 0.030), (-0.60, 0.53, 0.024),
             (0.42, 0.47, 0.021), (2.60, 0.51, 0.018)]
        ):
            twinkle = 0.58 + 0.42 * wave(t, 2, index * 0.17)
            x = cx + math.cos(angle + t * 0.55) * side * distance
            y = cy + math.sin(angle + t * 0.55) * side * distance
            draw_star(d, x, y, side * size * twinkle,
                      rgba(GOLD if index % 2 == 0 else WHITE_BLUE, visible))
        draw_heart(d, cx, cy - side * 0.44, 1.15 * SUPERSAMPLE,
                   rgba(CORAL, visible * 0.88))
    elif kind == "laugh":
        for side_sign in (-1, 1):
            x = cx + side_sign * side * 0.38
            y = cy - side * 0.31 + side_sign * side * 0.018
            draw_star(d, x, y, side * 0.033 * (0.82 + 0.18 * abs(wave(t, 3))),
                      rgba(GOLD if side_sign < 0 else MINT, visible * 0.94))
        for side_sign in (-1, 1):
            x1 = cx + side_sign * side * 0.245
            y1 = cy + side * 0.17
            x2 = x1 + side_sign * side * 0.035
            y2 = y1 + side * (0.095 + 0.018 * wave(t, 2))
            d.line([(x1, y1), (x2, y2)], fill=rgba(COBALT_LIGHT, visible),
                   width=max(2, round(2.4 * SUPERSAMPLE)))
            d.ellipse((x2 - side * 0.018, y2 - side * 0.024,
                       x2 + side * 0.018, y2 + side * 0.024),
                      fill=rgba(COBALT_LIGHT, visible))
    elif kind == "shock":
        x = cx + side * 0.44
        y = cy - side * 0.27
        d.rounded_rectangle(
            (x - side * 0.018, y - side * 0.085,
             x + side * 0.018, y + side * 0.020),
            radius=side * 0.018,
            fill=rgba(CORAL, visible),
        )
        d.ellipse((x - side * 0.018, y + side * 0.050,
                   x + side * 0.018, y + side * 0.086),
                  fill=rgba(CORAL, visible))
        draw_star(d, cx - side * 0.44, cy + side * 0.20,
                  side * 0.026, rgba(GOLD, visible))
    elif kind == "speechless":
        for index in range(3):
            alpha = 0.52 + 0.48 * math.sin((t + index * 0.08) * math.tau)
            x = cx + side * (0.30 + index * 0.085)
            y = cy + side * 0.42
            radius = side * 0.016
            d.ellipse((x - radius, y - radius, x + radius, y + radius),
                      fill=rgba(WHITE_BLUE, alpha * visible))
    elif kind == "hug":
        for side_sign in (-1, 1):
            x = cx + side_sign * side * 0.28
            y = cy + side * 0.31
            d.ellipse((x - side * 0.095, y - side * 0.060,
                       x + side * 0.095, y + side * 0.060),
                      fill=rgba(COBALT_LIGHT, visible * 0.88))
            d.rounded_rectangle(
                (x - side * 0.025, y - side * 0.018,
                 x - side * 0.010, y + side * 0.018),
                radius=side * 0.010,
                fill=rgba(INK, visible),
            )
            d.rounded_rectangle(
                (x + side * 0.010, y - side * 0.018,
                 x + side * 0.025, y + side * 0.018),
                radius=side * 0.010,
                fill=rgba(INK, visible),
            )
        draw_heart(d, cx, cy - side * 0.43, 1.05 * SUPERSAMPLE,
                   rgba(CORAL, visible * 0.94))
    elif kind == "night":
        x = cx + math.cos(t * math.tau) * side * 0.41
        y = cy - side * 0.36 + math.sin(t * math.tau) * side * 0.035
        draw_moon(frame, x, y, 1.05 * SUPERSAMPLE, rgba(WHITE_BLUE, visible))
        for index in range(4):
            twinkle = 0.50 + 0.50 * abs(wave(t, 2, index * 0.21))
            sx = cx + side * (-0.42 + index * 0.28)
            sy = cy + side * (-0.41 + (index % 2) * 0.22)
            draw_star(d, sx, sy, side * (0.014 + (index % 2) * 0.007) * twinkle,
                      rgba(GOLD if index % 2 else WHITE_BLUE, visible * 0.85))
    elif kind == "music":
        bounce = math.sin(t * math.tau * 2) * side * 0.014
        draw_music_note(d, cx + side * 0.43, cy - side * 0.28 + bounce,
                        1.05 * SUPERSAMPLE, rgba(WHITE_BLUE, visible))
        for side_sign in (-1, 1):
            x = cx + side_sign * side * 0.29
            y = cy + side * 0.17
            d.rounded_rectangle(
                (x - side * 0.030, y - side * 0.045,
                 x + side * 0.030, y + side * 0.100),
                radius=side * 0.025,
                fill=rgba(COBALT_LIGHT, visible * 0.86),
            )
    elif kind == "miss":
        pulse = 1.0 + 0.12 * wave(t, 1)
        draw_heart(d, cx, cy - side * 0.45, 1.20 * SUPERSAMPLE * pulse,
                   rgba(CORAL, visible * 0.96))
        for index, side_sign in enumerate((-1, 1)):
            twinkle = 0.55 + 0.45 * wave(t, 2, index * 0.25)
            draw_star(d, cx + side_sign * side * 0.43, cy - side * 0.16,
                      side * 0.025 * twinkle,
                      rgba(GOLD, visible * 0.84))
    elif kind == "like":
        pulse = 1.0 + 0.10 * abs(wave(t, 1))
        draw_star(d, cx + side * 0.43, cy - side * 0.23,
                  side * 0.060 * pulse, rgba(GOLD, visible))
        draw_heart(d, cx - side * 0.43, cy + side * 0.20,
                   0.85 * SUPERSAMPLE, rgba(CORAL, visible * 0.86))
    elif kind == "boost":
        for index in range(3):
            offset = (t + index / 3.0) % 1.0
            x = cx - side * (0.30 + offset * 0.23)
            y = cy + side * (0.28 + (index - 1) * 0.09)
            length = side * (0.070 + (1.0 - offset) * 0.085)
            d.line([(x, y), (x - length, y)],
                   fill=rgba(CORAL if index == 1 else GOLD, visible * (1.0 - offset * 0.55)),
                   width=max(2, round((4.0 - index * 0.7) * SUPERSAMPLE)))
    elif kind == "decline":
        radius = side * 0.095
        x = cx + side * 0.41
        y = cy + side * 0.24
        d.ellipse((x - radius, y - radius, x + radius, y + radius),
                  fill=rgba(CORAL, visible))
        d.line([(x - radius * 0.48, y - radius * 0.48),
                (x + radius * 0.48, y + radius * 0.48)],
               fill=rgba(PORCELAIN, visible),
               width=max(3, round(3.4 * SUPERSAMPLE)))
        d.line([(x - radius * 0.48, y + radius * 0.48),
                (x + radius * 0.48, y - radius * 0.48)],
               fill=rgba(PORCELAIN, visible),
               width=max(3, round(3.4 * SUPERSAMPLE)))
    elif kind == "slack":
        y = cy + side * 0.42 + wave(t, 1) * side * 0.018
        x = cx + side * 0.36
        d.ellipse((x - side * 0.105, y - side * 0.055,
                   x + side * 0.080, y + side * 0.055),
                  fill=rgba(COBALT_LIGHT, visible * 0.92))
        d.polygon([(x + side * 0.065, y),
                   (x + side * 0.125, y - side * 0.045),
                   (x + side * 0.125, y + side * 0.045)],
                  fill=rgba(COBALT_LIGHT, visible * 0.92))
        d.ellipse((x - side * 0.070, y - side * 0.012,
                   x - side * 0.050, y + side * 0.008),
                  fill=rgba(INK, visible))
        for index in range(2):
            bubble_x = x - side * (0.13 + index * 0.05)
            bubble_y = y - side * (0.07 + index * 0.06)
            radius = side * 0.014
            d.ellipse((bubble_x - radius, bubble_y - radius,
                       bubble_x + radius, bubble_y + radius),
                      fill=rgba(WHITE_BLUE, visible * 0.58))
    elif kind == "meeting":
        x = cx + side * 0.42
        y = cy + side * 0.20
        card_w = side * 0.15
        card_h = side * 0.16
        d.rounded_rectangle(
            (x - card_w / 2, y - card_h / 2,
             x + card_w / 2, y + card_h / 2),
            radius=side * 0.026,
            fill=rgba(PORCELAIN, visible),
            outline=rgba(COBALT_LIGHT, visible),
            width=max(1, round(1.6 * SUPERSAMPLE)),
        )
        d.line([(x - card_w * 0.34, y - card_h * 0.12),
                (x + card_w * 0.34, y - card_h * 0.12)],
               fill=rgba(CORAL, visible),
               width=max(1, round(1.5 * SUPERSAMPLE)))
        d.ellipse((x - card_w * 0.25, y + card_h * 0.12,
                   x - card_w * 0.11, y + card_h * 0.28),
                  fill=rgba(COBALT, visible))
        d.line([(x - card_w * 0.05, y + card_h * 0.18),
                (x + card_w * 0.28, y + card_h * 0.18)],
               fill=rgba(COBALT, visible),
               width=max(1, round(1.8 * SUPERSAMPLE)))


def motion(kind: str, t: float) -> tuple[float, float, float, float, float, tuple[float, float], str]:
    idle = wave(t, 1) * 2.3 * SUPERSAMPLE
    x = 0.0
    y = idle
    scale = 1.0
    blink = 0.0
    blush = 0.0
    look = (0.0, 0.0)
    mood = "normal"

    if kind == "check":
        y += abs(wave(t, 1)) * 4 * SUPERSAMPLE
        look = (0.20, -0.16)
    elif kind == "presence":
        look = (wave(t, 1) * 0.72, 0.0)
        blink = smoothstep(0.44, 0.48, t) * (1 - smoothstep(0.52, 0.58, t))
        blush = 0.38
    elif kind == "wait":
        look = (wave(t, 2) * 0.64, wave(t, 1, 0.25) * 0.22)
    elif kind == "thanks":
        y += abs(wave(t, 1)) * 2.5 * SUPERSAMPLE
        blush = 0.78
        look = (0.0, 0.20)
    elif kind == "laugh":
        x += wave(t, 3) * 5.2 * SUPERSAMPLE
        y += abs(wave(t, 2)) * 6.0 * SUPERSAMPLE
        mood = "laugh"
        blush = 0.92
    elif kind == "shock":
        impact = math.sin(clamp(t * 3.2) * math.pi) if t < 0.75 else 0.0
        scale = 1.0 + 0.075 * impact
        x += wave(t, 4) * 2.3 * SUPERSAMPLE * impact
        mood = "shock"
        look = (0.0, -0.22)
    elif kind == "speechless":
        x += wave(t, 1) * 6.0 * SUPERSAMPLE
        mood = "speechless"
        look = (-0.58, -0.12)
    elif kind == "hug":
        scale = 1.0 + wave(t, 2) * 0.022
        blush = 0.94
        look = (0.0, 0.26)
    elif kind == "night":
        mood = "night"
        y += 3.2 * SUPERSAMPLE * wave(t, 1)
        blink = 0.88
        blush = 0.20
    elif kind == "music":
        x += wave(t, 2) * 4.0 * SUPERSAMPLE
        y += wave(t, 2, 0.10) * 4.0 * SUPERSAMPLE
        blink = smoothstep(0.46, 0.49, t) * (1 - smoothstep(0.52, 0.56, t))
        look = (0.45, 0.0)
    elif kind == "miss":
        scale = 1.0 + 0.030 * wave(t, 1)
        blush = 0.90
        look = (wave(t, 1, 0.25) * 0.35, -0.12)
    elif kind == "like":
        scale = 1.0 + 0.045 * abs(wave(t, 1))
        blush = 0.58
        y -= 2.0 * SUPERSAMPLE * abs(wave(t, 1))
    elif kind == "boost":
        x += 4.0 * SUPERSAMPLE * abs(wave(t, 1))
        y -= 3.0 * SUPERSAMPLE * abs(wave(t, 2))
        look = (0.82, -0.08)
    elif kind == "decline":
        x -= wave(t, 1) * 2.2 * SUPERSAMPLE
        mood = "decline"
        look = (0.0, -0.18)
    elif kind == "slack":
        y += 2.0 * SUPERSAMPLE * wave(t, 1)
        blink = smoothstep(0.44, 0.48, t) * (1 - smoothstep(0.54, 0.60, t))
        mood = "speechless"
        look = (-0.55, 0.15)
    elif kind == "meeting":
        y += 1.8 * SUPERSAMPLE * wave(t, 1)
        blink = smoothstep(0.50, 0.54, t) * (1 - smoothstep(0.57, 0.61, t))
        mood = "speechless"
        look = (0.32, -0.12)

    return x, y, scale, blink, blush, look, mood


def render_frame(index: int, kind: str) -> Image.Image:
    t = index / FRAME_COUNT
    frame = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    cx = S / 2
    cy = S / 2 - 4 * SUPERSAMPLE
    x, y, scale, blink, blush, look, mood = motion(kind, t)
    draw_character(
        frame,
        t,
        kind,
        cx=cx + x,
        cy=cy + y,
        scale=scale,
        blink=blink,
        blush=blush,
        look=look,
        mood=mood,
    )
    draw_effect(frame, kind, t, cx, cy, CHARACTER_SIDE * scale)
    return frame.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def make_gif(kind: str, path: Path) -> Image.Image:
    frames: list[Image.Image] = []
    for index in range(FRAME_COUNT):
        rgba_frame = render_frame(index, kind)
        alpha = rgba_frame.getchannel("A").point(lambda value: 0 if value < 16 else 255)
        rgba_frame.putalpha(alpha)
        palette = rgba_frame.convert("RGB").quantize(
            colors=255,
            method=Image.Quantize.MEDIANCUT,
            dither=Image.Dither.NONE,
        )
        palette.paste(255, mask=Image.eval(rgba_frame.getchannel("A"),
                                          lambda value: 255 if value == 0 else 0))
        frames.append(palette)

    frames[0].save(
        path,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_MS,
        loop=0,
        disposal=2,
        transparency=255,
        optimize=True,
        comment=b"Original Xingyan Nova Courier emoji. Generated in-repo.",
    )
    return frames[0].convert("RGBA")


def preview_sheet(icons: list[tuple[str, Image.Image]], path: Path) -> None:
    columns = 4
    cell_w, cell_h = 300, 340
    rows = math.ceil(len(icons) / columns)
    sheet = Image.new("RGBA", (columns * cell_w, rows * cell_h), (8, 13, 24, 255))
    draw = ImageDraw.Draw(sheet)
    try:
        title_font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 24)
        detail_font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 15)
    except Exception:
        title_font = None
        detail_font = None

    for index, (name, icon) in enumerate(icons):
        col = index % columns
        row = index // columns
        x = col * cell_w
        y = row * cell_h
        draw.rounded_rectangle(
            (x + 12, y + 12, x + cell_w - 12, y + cell_h - 12),
            radius=28,
            fill=(18, 28, 49, 255),
            outline=(68, 106, 194, 255),
            width=1,
        )
        thumb = icon.copy().resize((176, 176), Image.Resampling.LANCZOS)
        sheet.alpha_composite(thumb, (x + 62, y + 28))
        label = f"星核邮差 · {name}"
        if title_font:
            box = draw.textbbox((0, 0), label, font=title_font)
            draw.text(
                (x + (cell_w - (box[2] - box[0])) / 2, y + 218),
                label,
                font=title_font,
                fill=(247, 251, 255, 255),
            )
            technical = f"{SIZE}px · {FRAME_COUNT}f · {FRAME_MS}ms"
            box = draw.textbbox((0, 0), technical, font=detail_font)
            draw.text(
                (x + (cell_w - (box[2] - box[0])) / 2, y + 265),
                technical,
                font=detail_font,
                fill=(135, 169, 231, 255),
            )
        else:
            draw.text((x + 70, y + 226), f"NOVA / {name}", fill=(247, 251, 255, 255))

    sheet.convert("RGB").save(path, quality=95)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    icons: list[tuple[str, Image.Image]] = []
    files: list[str] = []

    for name, slug, kind in SPECS:
        path = OUT_DIR / f"{slug}.gif"
        icons.append((name, make_gif(kind, path)))
        files.append(path.name)

    (OUT_DIR / "icon.gif").write_bytes((OUT_DIR / "shou-dao.gif").read_bytes())

    catalog = {
        "categories": [
            {"id": "xingyan-original", "name": "星言原创"}
        ],
        "packs": [
            {
                "id": "nova-courier-premium",
                "name": "星核邮差",
                "category": "xingyan-original",
                "dir": "/emoji/nova-courier",
                "icon": "/emoji/nova-courier/icon.gif",
                "files": files,
            }
        ],
    }
    (OUT_DIR / "pack.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    manifest = {
        "name": "星核邮差",
        "version": 1,
        "author": "Xingyan / original in-house artwork",
        "license": "All rights reserved by the Xingyan project. Generated from code in this repository.",
        "source": "tools/generate_nova_courier_emojis.py",
        "canvas": {
            "width": SIZE,
            "height": SIZE,
            "frames": FRAME_COUNT,
            "frame_ms": FRAME_MS,
            "loop": True,
        },
        "design": {
            "mascot": "Nova Courier",
            "silhouette": "porcelain-faced cobalt comet with an antenna star",
            "palette": ["midnight cobalt", "porcelain", "signal blue", "coral", "gold"],
            "rules": [
                "one continuous ceramic rim",
                "one asymmetric face mask",
                "props stay outside the body silhouette",
                "no borrowed character or third-party sticker artwork",
            ],
        },
        "items": [
            {"name": name, "file": f"{slug}.gif", "animation": kind}
            for name, slug, kind in SPECS
        ],
    }
    (OUT_DIR / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (OUT_DIR / "README.txt").write_text(
        "星言原创动态表情：星核邮差\n"
        "==============================\n\n"
        "本目录由 tools/generate_nova_courier_emojis.py 程序化生成。\n"
        "角色、轮廓、配色、动作和道具均为星言项目原创，不包含第三方 IP。\n\n"
        "规格：320 x 320，20 帧，72ms/帧，无限循环，透明背景。\n"
        "设计目标：统一陶瓷外沿、非对称月白面罩、克制的品牌提示色；\n"
        "所有道具放在角色轮廓外，保证小尺寸表情栏中的识别度。\n",
        encoding="utf-8",
    )
    preview_sheet(icons, OUT_DIR / "preview.png")
    print(f"Generated {len(SPECS)} animated stickers in {OUT_DIR}")


if __name__ == "__main__":
    main()

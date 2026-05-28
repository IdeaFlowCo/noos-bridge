#!/usr/bin/env python3
"""Generate production and development app icons for Noos Bridge."""

from __future__ import annotations

import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
SIZES = [16, 32, 64, 128, 256, 512, 1024]


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()


def rounded_rect_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        for x in range(size):
            vignette = 1.0 - 0.12 * math.hypot((x / size) - 0.5, (y / size) - 0.42)
            color = tuple(int((top[i] * (1 - t) + bottom[i] * t) * vignette) for i in range(3))
            px[x, y] = (*color, 255)
    return img


def draw_bridge_icon(path: Path, *, dev: bool) -> None:
    size = 1024
    scale = size / 1024
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    if dev:
        top, bottom = (30, 94, 110), (12, 28, 40)
        accent = (255, 191, 71)
        accent2 = (41, 207, 164)
        ribbon = (255, 132, 41)
    else:
        top, bottom = (22, 74, 115), (8, 22, 42)
        accent = (65, 154, 255)
        accent2 = (46, 216, 190)
        ribbon = None

    card = gradient(size, top, bottom)
    mask = rounded_rect_mask(size, int(224 * scale))
    base.alpha_composite(card)
    base.putalpha(mask)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (42, 58, size - 42, size - 18),
        radius=int(218 * scale),
        fill=(0, 0, 0, 88),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    composed = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    composed.alpha_composite(shadow)
    composed.alpha_composite(base)
    draw = ImageDraw.Draw(composed)

    # Inner gloss and boundary.
    draw.rounded_rectangle(
        (44, 38, size - 44, size - 54),
        radius=int(198 * scale),
        outline=(255, 255, 255, 34),
        width=int(8 * scale),
    )

    # Bridge piers.
    for x in (296, 512, 728):
        draw.rounded_rectangle(
            (x - 28, 420, x + 28, 724),
            radius=28,
            fill=(235, 247, 255, 235),
        )
        draw.ellipse((x - 42, 370, x + 42, 454), fill=(235, 247, 255, 245))

    # Bridge deck.
    draw.rounded_rectangle((220, 654, 804, 734), radius=40, fill=(235, 247, 255, 248))
    draw.rounded_rectangle((254, 688, 770, 706), radius=9, fill=(24, 75, 107, 130))

    # Connection arcs.
    for inset, color, width in [
        (166, (*accent, 235), 34),
        (234, (*accent2, 226), 24),
    ]:
        box = (inset, 220 + inset // 5, size - inset, 826 - inset // 5)
        draw.arc(box, start=202, end=338, fill=color, width=width)

    # Nodes.
    for x, y, color in [
        (230, 606, accent),
        (512, 328, (244, 250, 255)),
        (794, 606, accent2),
    ]:
        draw.ellipse((x - 46, y - 46, x + 46, y + 46), fill=(*color, 255))
        draw.ellipse((x - 25, y - 25, x + 25, y + 25), fill=(16, 47, 76, 205))

    # Noos mark.
    n_font = font(128)
    draw.text((512, 780), "N", font=n_font, fill=(245, 250, 255, 238), anchor="mm")

    if ribbon:
        ribbon_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        rdraw = ImageDraw.Draw(ribbon_layer)
        rdraw.polygon(
            [(618, 0), (1024, 0), (1024, 406), (946, 440), (584, 78)],
            fill=(*ribbon, 248),
        )
        rdraw.line([(625, 0), (1024, 399)], fill=(255, 255, 255, 70), width=7)
        dev_font = font(86)
        text_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        tdraw = ImageDraw.Draw(text_layer)
        tdraw.text((833, 180), "DEV", font=dev_font, fill=(30, 23, 18, 235), anchor="mm")
        text_layer = text_layer.rotate(45, resample=Image.Resampling.BICUBIC, center=(833, 180))
        ribbon_layer.alpha_composite(text_layer)
        composed.alpha_composite(ribbon_layer)

    composed.save(path)


def make_iconset(master: Path, iconset: Path) -> None:
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)
    for size in SIZES:
        for scale in (1, 2):
            pixels = size * scale
            if pixels > 1024:
                continue
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            out = iconset / name
            subprocess.run(
                ["sips", "-z", str(pixels), str(pixels), str(master), "--out", str(out)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )


def make_icns(name: str, *, dev: bool) -> None:
    png = RESOURCES / f"{name}.png"
    iconset = RESOURCES / f"{name}.iconset"
    icns = RESOURCES / f"{name}.icns"
    draw_bridge_icon(png, dev=dev)
    make_iconset(png, iconset)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
    shutil.rmtree(iconset)
    print(f"wrote {png.relative_to(ROOT)} and {icns.relative_to(ROOT)}")


def main() -> None:
    RESOURCES.mkdir(exist_ok=True)
    make_icns("AppIcon", dev=False)
    make_icns("AppIconDev", dev=True)


if __name__ == "__main__":
    main()

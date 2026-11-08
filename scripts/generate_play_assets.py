#!/usr/bin/env python3
"""Generates the Google Play icon (512x512) and feature graphic (1024x500)
from assets/branding into android/app/src/main/play/listings/en-US/graphics.

Requires Pillow. Run from anywhere: python3 scripts/generate_play_assets.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "assets" / "branding"
OUT = ROOT / "android/app/src/main/play/listings/en-US/graphics"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BG = (15, 20, 23)
ACCENT = (53, 197, 244)


def icon() -> None:
    # Same composition as the adaptive launcher icon: light square + padded logo.
    base = Image.new("RGBA", (512, 512), (237, 237, 237, 255))
    fg = Image.open(BRAND / "logo_foreground.png").convert("RGBA").resize((512, 512), Image.LANCZOS)
    base.alpha_composite(fg)
    (OUT / "icon").mkdir(parents=True, exist_ok=True)
    base.save(OUT / "icon" / "icon.png", optimize=True)


def feature_graphic() -> None:
    w, h = 1024, 500
    im = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(im)
    for x in range(w):
        k = x / w
        d.line([(x, 0), (x, h)], fill=(int(15 + 15 * k), int(20 + 40 * k), int(23 + 55 * k)))
    logo = Image.open(BRAND / "logo.png").convert("RGBA").resize((300, 300), Image.LANCZOS)
    im.paste(logo, (90, 100), logo)
    title = ImageFont.truetype(FONT_BOLD, 92)
    sub = ImageFont.truetype(FONT, 34)
    d.text((430, 150), "Sonarr", font=title, fill="white")
    d.text((434, 272), "Unofficial companion app", font=sub, fill=ACCENT)
    d.text((434, 322), "Manage your server on the go", font=sub, fill=(190, 200, 205))
    (OUT / "feature-graphic").mkdir(parents=True, exist_ok=True)
    im.save(OUT / "feature-graphic" / "feature.png", optimize=True)


if __name__ == "__main__":
    icon()
    feature_graphic()
    print("Generated assets in", OUT)

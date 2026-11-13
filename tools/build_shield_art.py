#!/usr/bin/env python3
"""Draw images2.0/general/Shield.png: the UI's shield glyph (U+1F6E1) as a picture.

A shield is WRITTEN as the glyph in text (an enemy's badge, the inventory) and
DRAWN as art where a number of them stand in a row (the pips over the hero, the
chip beside the Health, the OBS overlay). This makes the art from the glyph, in
the shield's own blue (BattlefieldView.SHIELD_BLUE), so the two are one icon and
it matches the rest of the basic set. The pixel shield that used to be this file
is Brutal Orchestra's shield icon (images2.0/icons/Shields/).

Run it after tools/build_glyph_font.py if the glyph's font ever changes. Needs
Pillow.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "fonts", "NotoSansSymbols2-Subset.ttf")
OUT = os.path.join(ROOT, "images2.0", "general", "Shield.png")
GLYPH = "\U0001F6E1"
SIDE = 128
BLUE = (158, 199, 242, 255)   # SHIELD_BLUE, Color(0.62, 0.78, 0.95)


def main():
	font = ImageFont.truetype(FONT, SIDE)
	big = Image.new("RGBA", (SIDE * 3, SIDE * 3), (0, 0, 0, 0))
	ImageDraw.Draw(big).text((SIDE, SIDE), GLYPH, font=font, fill=BLUE)
	glyph = big.crop(big.getbbox())
	# Fitted to the square with a hair of margin, centred.
	scale = (SIDE - 8) / max(glyph.size)
	glyph = glyph.resize((round(glyph.width * scale), round(glyph.height * scale)), Image.LANCZOS)
	out = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
	out.alpha_composite(glyph, ((SIDE - glyph.width) // 2, (SIDE - glyph.height) // 2))
	out.save(OUT, optimize=True)
	print("wrote", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
	main()

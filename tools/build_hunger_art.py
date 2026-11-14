#!/usr/bin/env python3
"""Draw images2.0/general/Hunger.png: the basic Hunger icon, the UI's chicken-leg
glyph (U+1F357) as a picture.

Hunger is DRAWN, never written: five of these stand in the header for a player
with Hunger (docs/players-design.md §4), lit for each point and dimmed for the
rest. This makes the basic one from the glyph, in Hunger's own amber
(HungerSystem.COLOR), the way tools/build_shield_art.py makes the basic shield —
so it belongs to the same basic set as ♥ ◉ 🛡. A worn Hunger icon
(images2.0/icons/Hunger/, docs/customization.md) replaces it.

Run it after tools/build_glyph_font.py if the glyph's font ever changes. Needs
Pillow.
"""

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "fonts", "NotoEmoji-Subset.ttf")
OUT = os.path.join(ROOT, "images2.0", "general", "Hunger.png")
GLYPH = "\U0001F357"
# 256, not the shield's 128: over UITheme.SMALL_ART_MAX it is drawn as a painted
# picture, shrunk cleanly to the icon's real screen size (UITheme.shrunk) rather
# than sampled as pixel art.
SIDE = 256
AMBER = (235, 168, 77, 255)   # HungerSystem.COLOR, Color(0.92, 0.66, 0.30)


def main():
	font = ImageFont.truetype(FONT, SIDE)
	big = Image.new("RGBA", (SIDE * 3, SIDE * 3), (0, 0, 0, 0))
	ImageDraw.Draw(big).text((SIDE, SIDE), GLYPH, font=font, fill=AMBER)
	box = big.getbbox()
	if box is None:
		raise SystemExit("%s has no %r: run tools/build_glyph_font.py" % (FONT, GLYPH))
	glyph = big.crop(box)
	# Fitted to the square with a hair of margin, centred.
	scale = (SIDE - 8) / max(glyph.size)
	glyph = glyph.resize((round(glyph.width * scale), round(glyph.height * scale)), Image.LANCZOS)
	out = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
	out.alpha_composite(glyph, ((SIDE - glyph.width) // 2, (SIDE - glyph.height) // 2))
	out.save(OUT, optimize=True)
	print("wrote", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
	main()

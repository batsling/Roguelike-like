#!/usr/bin/env python3
"""Draw images2.0/general/Timer.png: the TEMPORARY badge's basic icon, from ⏱.

The badge in the corner of anything temporary (UITheme.timed_art: a status
borrowed for a game, a shield that expires with the game) is drawn like the rest
of the basic set (the owner, 22 Nov 2026): the UI's own ⏱ glyph, the one the
text already writes ("⏱ This game only."), in the highlight gold. The stopwatch
picture it used to be is Mewgenics' unlock, images2.0/icons/Timer/
(docs/customization.md), worn through Cosmetics.timer_art().

It sits OVER art, in a corner, so it carries a dark outline to read against
anything under it. 256 px and thickened for the reasons tools/build_status_art.py
gives (under 128 px the UI treats a picture as pixel art).

  python3 tools/build_timer_art.py      # needs Pillow
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "fonts", "NotoSansSymbols2-Subset.ttf")
OUT = os.path.join(ROOT, "images2.0", "general", "Timer.png")
GLYPH = "⏱"
SIDE = 256
BOLD = 9
OUTLINE = 21
GOLD = (255, 204, 102, 255)   # UITheme.GOLD, Color(1.0, 0.80, 0.40)
DARK = (20, 12, 14, 255)      # near UITheme.BG_DEEP


def main():
	font = ImageFont.truetype(FONT, SIDE)
	big = Image.new("RGBA", (SIDE * 3, SIDE * 3), (0, 0, 0, 0))
	ImageDraw.Draw(big).text((SIDE, SIDE), GLYPH, font=font, fill=GOLD)
	art = big.crop(big.getbbox())
	# A wider margin than the statuses': the outline has to fit inside the square.
	scale = (SIDE - 2 * OUTLINE) / max(art.size)
	art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
	shape = Image.new("L", (SIDE, SIDE), 0)
	shape.paste(art.split()[3], ((SIDE - art.width) // 2, (SIDE - art.height) // 2))
	fill = shape.filter(ImageFilter.MaxFilter(BOLD))
	ring = shape.filter(ImageFilter.MaxFilter(OUTLINE))
	out = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
	under = Image.new("RGBA", (SIDE, SIDE), DARK)
	under.putalpha(ring)
	out.alpha_composite(under)
	top = Image.new("RGBA", (SIDE, SIDE), GOLD)
	top.putalpha(fill)
	out.alpha_composite(top)
	out.save(OUT, optimize=True)
	print("wrote", os.path.relpath(OUT, ROOT), out.size)


if __name__ == "__main__":
	main()

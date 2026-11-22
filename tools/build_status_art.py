#!/usr/bin/env python3
"""Draw images2.0/statuses/<Status>.png: each status's BASIC icon, from one glyph.

The owner, 22 Nov 2026: the statuses' pictures should "fit the rest of the
icons", and the game pictures they used to be become that game's unlocks. The
rest of the basic set is one Noto glyph per thing, drawn in one colour (the
shield, tools/build_shield_art.py; Hunger's 🍗, tools/build_hunger_art.py), so
these are made the same way: the glyph the owner picked for each status, drawn
once at 128 px, BUFFS in the UI's success green and DEBUFFS in its danger red
(UITheme.SUCCESS / UITheme.DANGER — the owner's choice over a colour each).

The game pictures live in images2.0/icons/Statuses/<Status>/<Name>_<Game>.png
now: earned from that game's ranks like any icon (docs/customization.md), and
worn in place of these (`Cosmetics.status_art`).

The glyphs are not in the UI's subset fonts (fonts/): nothing writes them as
text, so they are drawn from the full Noto families, fetched from the same
@fontsource packages tools/build_glyph_font.py uses. Needs Pillow, fonttools,
brotli and network access:

  python3 tools/build_status_art.py
"""
import io
import json
import os
import tarfile
import tempfile
import urllib.request

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "images2.0", "statuses")
SIDE = 128

GREEN = (77, 199, 107, 255)   # UITheme.SUCCESS, Color(0.30, 0.78, 0.42)
RED = (230, 84, 71, 255)      # UITheme.DANGER,  Color(0.90, 0.33, 0.28)

# The owner's picks (22 Nov 2026), from a sheet of four candidates each.
STATUSES = {
	"Strength": ("\U0001F4AA", GREEN),    # 💪 flexed arm
	"Dexterity": ("✋", GREEN),       # ✋ open hand
	"Speed": ("\U0001FABD", GREEN),       # 🪽 wing
	"Burn": ("\U0001F525", RED),          # 🔥 flame
	"Bleed": ("\U0001FA78", RED),         # 🩸 drop of blood
	"Marked": ("\U0001F3AF", RED),        # 🎯 target
	"Stun": ("\U0001F4AB", RED),          # 💫 dizzy star
}

# Where a glyph is looked for, best first (the same priority as the UI's chain).
FONTS = [
	("noto-emoji", "noto-emoji-emoji-400-normal.woff2"),
	("noto-sans-symbols-2", "noto-sans-symbols-2-symbols-400-normal.woff2"),
	("noto-sans-symbols", "noto-sans-symbols-symbols-400-normal.woff2"),
]


def fetch_font(package, filename, into):
	from fontTools.ttLib import TTFont
	meta = json.load(urllib.request.urlopen(
		"https://registry.npmjs.org/@fontsource/%s" % package, timeout=60))
	tarball = meta["versions"][meta["dist-tags"]["latest"]]["dist"]["tarball"]
	blob = urllib.request.urlopen(tarball, timeout=180).read()
	with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
		data = tar.extractfile("package/files/%s" % filename).read()
	font = TTFont(io.BytesIO(data))
	font.flavor = None
	path = os.path.join(into, package + ".ttf")
	font.save(path)
	return path, set(font.getBestCmap().keys())


def draw(glyph, font_path, colour):
	font = ImageFont.truetype(font_path, SIDE)
	big = Image.new("RGBA", (SIDE * 3, SIDE * 3), (0, 0, 0, 0))
	ImageDraw.Draw(big).text((SIDE, SIDE), glyph, font=font, fill=colour)
	art = big.crop(big.getbbox())
	# Fitted to the square with a hair of margin, centred — as the shield is.
	scale = (SIDE - 8) / max(art.size)
	art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
	out = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
	out.alpha_composite(art, ((SIDE - art.width) // 2, (SIDE - art.height) // 2))
	return out


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	with tempfile.TemporaryDirectory() as tmp:
		fonts = [fetch_font(pkg, fn, tmp) for pkg, fn in FONTS]
		for name, (glyph, colour) in STATUSES.items():
			path = next((p for p, cmap in fonts if ord(glyph) in cmap), None)
			if path is None:
				raise SystemExit("%s: no font has U+%04X" % (name, ord(glyph)))
			out = os.path.join(OUT_DIR, name + ".png")
			draw(glyph, path, colour).save(out, optimize=True)
			print("wrote", os.path.relpath(out, ROOT))


if __name__ == "__main__":
	main()

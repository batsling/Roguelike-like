#!/usr/bin/env python3
"""Render Rogue's own letters for the main menu's title: the whole IBM PC font.

The title is spelled out of letters cut from real roguelikes' logos
(tools/logo_letters.py), and since 31 Oct 2026 those are UNLOCKED, one per rank
(docs/content-authoring.md "Title letters"). What every player has from the
start is the font Rogue itself was played in on the PC: the IBM VGA 8x16 text
mode font (code page 437), every printable ASCII character of it, upper and lower
case, digits and punctuation.

Each character lands at

    images2.0/custom/title/<piece>/rogue.png          the upper case, digits, punctuation
    images2.0/custom/title/<piece>/rogue__lower.png   a letter's lower case

with <piece> the folder TitleLetters._folder_for gives the character (`a`,
`7`, `dash`, `period`...). The index entries carry `"game": "rogue"`, the
`case` of a letter ("upper"/"lower", which the title matches to the text it
spells) and `"pixel": true` (drawn with sharp pixels).

THE BOX. Every glyph's box, down, is the font's CAP BAND (the rows a capital X
fills), not its own ink: so a lower-case `a` stands lower-case-sized beside a
capital, a `-` is a dash rather than a block the line's height, and a `g`
hangs its tail below the line the way any font does. Across, it is the glyph's
own ink, as for every cut letter.

The pixels: the glyph in Rogue's terminal grey with a one-pixel black edge
(so it reads on the blue portal the way the logos' outlines do), scaled
SCALE x as sharp pixels.

    python3 tools/rogue_letters.py

The font is Px437 IBM VGA 8x16 from VileR's Ultimate Oldschool PC Font Pack
(https://int10h.org/oldschool-pc-fonts/), CC BY-SA 4.0 — the licence is beside
it in fonts/ (LICENSE-Px437-CC-BY-SA-4.0.txt), and the PNGs this writes are under the same licence.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "fonts" / "Px437_IBM_VGA_8x16.ttf"
OUT_DIR = ROOT / "images2.0" / "custom" / "title"
GAME = "rogue"
CONFIG = "rogue_letters.py"
CELL = (8, 16)
SCALE = 8
FACE = (0xD8, 0xD8, 0xD8, 255)    # the grey of a PC's text mode (colour 7)
EDGE = (0, 0, 0, 255)

# Keep in step with TitleLetters.PUNCT (test_title_letters.gd checks every
# entry this writes is a folder some character reaches).
PUNCT = {
    "-": "dash", "!": "exclaim", '"': "quote", "#": "hash", "$": "dollar",
    "%": "percent", "&": "ampersand", "'": "apostrophe", "(": "paren_left",
    ")": "paren_right", "*": "asterisk", "+": "plus", ",": "comma",
    ".": "period", "/": "slash", ":": "colon", ";": "semicolon", "<": "less",
    "=": "equals", ">": "greater", "?": "question", "@": "at",
    "[": "bracket_left", "\\": "backslash", "]": "bracket_right", "^": "caret",
    "_": "underscore", "`": "backtick", "{": "brace_left", "|": "bar",
    "}": "brace_right", "~": "tilde",
}


def folder_for(ch: str) -> str:
    return PUNCT.get(ch, ch.lower())


def glyph(font, ch):
    im = Image.new("L", CELL, 0)
    ImageDraw.Draw(im).text((0, 0), ch, font=font, fill=255)
    return [[im.getpixel((x, y)) > 127 for x in range(CELL[0])] for y in range(CELL[1])]


def ink_rows(g):
    return [y for y, row in enumerate(g) if any(row)]


def ink_cols(g):
    return [x for x in range(CELL[0]) if any(row[x] for row in g)]


def render(g):
    """The glyph, a pixel of black edge round it (and a pixel of room for it)."""
    w, h = CELL[0] + 2, CELL[1] + 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    on = {(x + 1, y + 1) for y, row in enumerate(g) for x, v in enumerate(row) if v}
    for (x, y) in on:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in on:
                    img.putpixel((x + dx, y + dy), EDGE)
    for p in on:
        img.putpixel(p, FACE)
    return img.resize((w * SCALE, h * SCALE), Image.NEAREST)


def main():
    font = ImageFont.truetype(str(FONT), 16)
    cap = ink_rows(glyph(font, "X"))
    cap_top, cap_bottom = cap[0], cap[-1] + 1          # rows, in the cell
    h = CELL[1] + 2
    w = CELL[0] + 2
    index_path = OUT_DIR / "index.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else {}
    index = {k: v for k, v in index.items() if v.get("config") != CONFIG}
    written = 0
    for code in range(0x21, 0x7F):
        ch = chr(code)
        g = glyph(font, ch)
        cols = ink_cols(g)
        if not cols:
            continue
        lower = ch.isalpha() and ch.islower()
        name = GAME + ("__lower" if lower else "")
        rel = f"{folder_for(ch)}/{name}.png"
        dest = OUT_DIR / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        render(g).save(dest, optimize=True)
        # +1: the edge pixel's room on every side of the cell.
        x0, x1 = cols[0] + 1, cols[-1] + 2
        entry = {
            "game": GAME,
            "config": CONFIG,
            "style": GAME,
            "body_center": round((cap_top + cap_bottom) / 2.0 / h + 1.0 / h, 4),
            "body_height": round((cap_bottom - cap_top) / h, 4),
            "body_center_x": round((x0 + x1) / 2.0 / w, 4),
            "body_width": round((x1 - x0) / w, 4),
            "pixel": True,
        }
        if ch.isalpha():
            entry["case"] = "lower" if lower else "upper"
        index[rel] = entry
        written += 1
    index_path.write_text(json.dumps(dict(sorted(index.items())), indent=1) + "\n")
    print(f"{written} Rogue letters written to {OUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

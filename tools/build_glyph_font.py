#!/usr/bin/env python3
"""Build the subsetted symbol fonts the UI theme falls back to (`fonts/*.ttf`).

WHY THIS EXISTS. Godot's built-in font covers two of the 73 non-ASCII glyphs the
UI is drawn with (`−` and `≈`); every other one — ⚔ ☠ ⚡ 🏆 🎲 🍀 and the rest —
misses it, and Godot answers a miss by searching the host's fonts *during
shaping*, uncached. Measured, that is ~2 ms every time a Label carrying one is
created, which was half of a full overworld repaint. It also means those glyphs
are drawn from whatever the player happens to have installed, so the game looks
different on different machines.

This bakes exactly the glyphs the source actually uses into small subsetted
files — 72 of them in about 25 KB — so the lookup is resolved from a resource we
ship instead of from the host.

Sources, all SIL Open Font License 1.1 with no Reserved Font Name (see
fonts/LICENSE-Noto.txt), fetched from the @fontsource npm packages:

    noto-sans-symbols-2   the arrows, geometric shapes, dingbats, misc symbols
    noto-emoji            the emoji, MONOCHROME — see the note below
    noto-sans-symbols     a handful the newer family dropped
    noto-sans-math        the circle arrows

MONOCHROME ON PURPOSE. The UI tints every glyph through the theme
(`add_theme_color_override("font_color", …)`) — Bash is amber, Dash is blue, the
Amulet is gold. A colour emoji font ignores that and paints its own colours, which
is what the host's Noto Color Emoji was doing: a blue shopping trolley in a green
SHOP badge. Monochrome glyphs take the tint they are given.

Run it when the set of glyphs in `scripts/` changes:

    python3 tools/build_glyph_font.py            # rebuild, report what moved
    python3 tools/build_glyph_font.py --check    # verify the shipped fonts, write nothing

The scan is over `scripts/**/*.gd` string literals — the same place the glyphs
are authored. A glyph no font here covers is REPORTED rather than skipped
silently: today that is `▁` (U+2581, the run map's minimise button), which none of
the Noto web subsets ship. It still renders, by the host search this file exists
to avoid, and one button opened once is a cost worth not redesigning around.
"""

import argparse
import io
import json
import os
import sys
import tarfile
import unicodedata
import urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
SCAN_DIR = os.path.join(PROJECT_ROOT, "scripts")
OUT_DIR = os.path.join(PROJECT_ROOT, "fonts")

# npm package -> (subset file, output name), best first. The @fontsource packages
# ship one file per unicode subset; these are the ones carrying anything this
# project uses. A glyph is taken from the FIRST source that has it, so the order
# here is the priority order, and each output holds a disjoint set.
#
# FOUR FILES RATHER THAN ONE. Merging them was tried and abandoned: the families
# disagree about OS/2 version, units-per-em and which optional tables exist, and
# fontTools' merger asserts its way through every one of those. Godot takes a
# CHAIN of fallbacks natively (see UITheme.glyph_font), so the merge bought
# nothing but a way to go wrong. Keeping them separate also keeps each file under
# its own family name, which is the tidiest thing to do with an OFL font.
SOURCES = [
    ("noto-sans-symbols-2", "noto-sans-symbols-2-symbols-400-normal.woff2",
     "NotoSansSymbols2-Subset.ttf"),
    ("noto-emoji", "noto-emoji-emoji-400-normal.woff2", "NotoEmoji-Subset.ttf"),
    ("noto-sans-symbols", "noto-sans-symbols-symbols-100-normal.woff2",
     "NotoSansSymbols-Subset.ttf"),
    ("noto-sans-math", "noto-sans-math-latin-400-normal.woff2",
     "NotoSansMath-Subset.ttf"),
]

# Godot's built-in font, exactly: 4096 units per em, ascender 4378, descender
# 1200. Read off it with Font.get_ascent(4096) / get_descent(4096).
#
# EVERY SUBSET IS RESCALED ONTO THIS GRID, and it is not cosmetic. Godot takes a
# font's height to be the MAXIMUM over the font and its whole fallback chain, so
# one subset with a taller ascender makes every line in the entire game taller —
# these four disagree enough to add 9px a line, which grew the overworld by 63px
# and broke the "fits a 720p window" tests (test_overworld2's _assert_fits).
#
# THE SAME GRID rather than the same ratio, because Godot takes the CEILING of
# size x ratio: two fonts a rounding error apart agree at most sizes and differ
# by a pixel at the ones where the ceiling falls differently, which is how the
# first attempt at this passed at font size 14 and failed at 10, 12, 13, 15
# and 22. Identical units cannot do that.
FONT_UPEM = 4096
FONT_ASCENT = 4378
FONT_DESCENT = 1200

# Codepoints below this are the base font's job — ASCII and the typographic
# punctuation Godot's built-in font already has.
MIN_CODEPOINT = 0x2000
# Punctuation the built-in font covers; scanning would otherwise drag it in.
SKIP = set("‘’“”…–—′″·•")


def used_glyphs() -> dict:
    """Every non-ASCII glyph in the project's GDScript, -> how often it appears."""
    counts = {}
    for root, _dirs, files in os.walk(SCAN_DIR):
        for name in files:
            if not name.endswith(".gd"):
                continue
            with open(os.path.join(root, name), encoding="utf-8") as fh:
                for ch in fh.read():
                    if ord(ch) > MIN_CODEPOINT and ch not in SKIP:
                        counts[ch] = counts.get(ch, 0) + 1
    return counts


def fetch(package: str, filename: str) -> bytes:
    """One subset file out of an @fontsource npm tarball."""
    meta = json.load(urllib.request.urlopen(
        "https://registry.npmjs.org/@fontsource/%s" % package, timeout=60))
    tarball = meta["versions"][meta["dist-tags"]["latest"]]["dist"]["tarball"]
    blob = urllib.request.urlopen(tarball, timeout=180).read()
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
        member = tar.extractfile("package/files/%s" % filename)
        if member is None:
            raise SystemExit("%s: no %s in the tarball" % (package, filename))
        return member.read()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="verify the shipped font covers what the source uses")
    args = ap.parse_args()

    try:
        from fontTools.ttLib import TTFont
        from fontTools.subset import Subsetter
        from fontTools.ttLib.scaleUpem import scale_upem
    except ImportError:
        raise SystemExit("needs fonttools + brotli:  pip install fonttools brotli")

    wanted = used_glyphs()
    print("%d distinct glyphs used across %s" % (len(wanted), os.path.relpath(SCAN_DIR, PROJECT_ROOT)))

    if args.check:
        have = set()
        for _pkg, _sub, out_name in SOURCES:
            path = os.path.join(OUT_DIR, out_name)
            if not os.path.exists(path):
                raise SystemExit("%s is missing — run without --check" % path)
            have |= set(TTFont(path).getBestCmap().keys())
        missing = sorted((c for c in wanted if ord(c) not in have), key=ord)
        for ch in missing:
            print("  NOT COVERED  U+%04X %s  (x%d)  %s" % (
                ord(ch), ch, wanted[ch], unicodedata.name(ch, "?")))
        print("%d/%d covered by fonts/" % (len(wanted) - len(missing), len(wanted)))
        return

    # Assign each glyph to the FIRST source that has it, so the families stay in
    # the priority order above and a glyph is never taken from two of them.
    need = {ord(c) for c in wanted}
    os.makedirs(OUT_DIR, exist_ok=True)
    taken = set()
    total = 0
    for package, filename, out_name in SOURCES:
        if not (need - taken):
            break
        print("fetching @fontsource/%s …" % package)
        font = TTFont(io.BytesIO(fetch(package, filename)))
        mine = (need - taken) & set(font.getBestCmap().keys())
        if not mine:
            font.close()
            continue
        sub = Subsetter()
        sub.populate(unicodes=mine)
        sub.subset(font)
        # A fallback font for single symbols needs a cmap and outlines and
        # nothing else, so the layout tables go — most of the file size, and
        # none of it used when the glyph is one character on its own.
        for tag in ("MATH", "GSUB", "GPOS", "GDEF", "BASE", "JSTF", "DSIG"):
            if tag in font:
                del font[tag]
        _match_metrics(font, scale_upem)
        path = os.path.join(OUT_DIR, out_name)
        font.save(path)
        taken |= mine
        size = os.path.getsize(path)
        total += size
        print("   %-28s %2d glyphs, %5.1f KB" % (out_name, len(mine), size / 1024.0))

    for cp in sorted(need - taken):
        print("  NOT COVERED  U+%04X %s  (x%d)  %s" % (
            cp, chr(cp), wanted[chr(cp)], unicodedata.name(chr(cp), "?")))
    print("%d/%d glyphs, %.1f KB in fonts/" % (len(taken), len(need), total / 1024.0))


# Put one subset on the base font's em grid and give it the base font's vertical
# metrics. See FONT_UPEM above for why both halves are needed.
def _match_metrics(font, scale_upem) -> None:
    if font["head"].unitsPerEm != FONT_UPEM:
        scale_upem(font, FONT_UPEM)
    hhea = font["hhea"]
    hhea.ascender, hhea.descender, hhea.lineGap = FONT_ASCENT, -FONT_DESCENT, 0
    os2 = font["OS/2"]
    os2.sTypoAscender = FONT_ASCENT
    os2.sTypoDescender = -FONT_DESCENT
    os2.sTypoLineGap = 0
    os2.usWinAscent, os2.usWinDescent = FONT_ASCENT, FONT_DESCENT


if __name__ == "__main__":
    main()

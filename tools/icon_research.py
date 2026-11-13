#!/usr/bin/env python3
"""Icons from the games themselves: find the BEST version of a picture, hold it
as a candidate for the owner to say yes or no to, and move a yes into the game.

    python3 tools/icon_research.py best "Brotato" Max_HP.png
    python3 tools/icon_research.py best "Into the Breach" coin          # a search, when the name is not known
    python3 tools/icon_research.py best --api https://x.wiki.gg/api.php "Some Game" Shield.png --against my.png
    python3 tools/icon_research.py add Health "Max HP" "Brotato" Max_HP.png --what "The Max HP stat's icon"
    python3 tools/icon_research.py add Gold Coin "Into the Breach" path/or/url.png --page https://…
    python3 tools/icon_research.py add Chests "Bronze Chest" "Rogue Legacy 2" bronze.png --range 0-0   # one of a set
    python3 tools/icon_research.py sheet            # a numbered contact sheet of everything waiting
    python3 tools/icon_research.py apply            # after `research.py sync`: every yes into images2.0/icons/

**Best version, every time an icon is added** (the owner, 13 Nov 2026: "when
adding future icons, automatically check for the best version of the image").
Whatever the owner pastes is a starting point, usually a wiki THUMBNAIL: Brotato's
four arrived at 60px with a dither pattern, and the wiki's originals were clean
96px. So before a file goes into images2.0/icons/, `best` asks the game's wiki
(research/wikis.json, or --api) for

  1. the ORIGINAL of that file, not the /thumb/ rendering of it;
  2. every other file whose name matches, largest first — a wiki often keeps
     `Coin.png`, `Mini Coin.png` and a `Coin HD.png` side by side;
  3. lossless bytes: Fandom re-encodes to WebP unless asked for `format=original`.

and saves what it found under .research_work/icons/ with its real pixel size.
Bigger is not better by itself: a larger file with a frame, a background or a
different drawing is a different icon, so LOOK at the candidates (`sheet`, or
read the PNG) before choosing. Never upscale; the game scales at draw time.

**Research for the owner to tick** is the `icons` kind of tools/research.py
(docs/research.md §6.8): rows in research/icons.csv, pictures in
research/icons/<Kind>/<File>.png (research/ is .gdignore'd, so Godot never
imports a candidate), shown in Research.xlsx's `icons` sheet beside the yellow
Owner column. It is done when ASKED FOR, not for every game that is added.
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import research as R  # noqa: E402
from build_cosmetics_index import game_ids, suffix_game  # noqa: E402

from PIL import Image  # noqa: E402

WORK = os.path.join(R.WORK, "icons")


def get(url):
    """The bytes at `url`, original encoding where the host re-encodes."""
    if "static.wikia.nocookie.net" in url and "format=original" not in url:
        url += ("&" if "?" in url else "?") + "format=original"
    with urllib.request.urlopen(urllib.request.Request(url, headers=R.UA), timeout=60) as r:
        return r.read()


def as_png(data):
    """`data` as PNG bytes and its size. A PNG is kept byte for byte."""
    im = Image.open(io.BytesIO(data))
    if im.format == "PNG":
        return data, im.size
    buf = io.BytesIO()
    im.convert("RGBA").save(buf, "PNG")
    return buf.getvalue(), im.size


def api_of(game, override):
    base = override or R.load_json(R.WIKIS, {}).get(game, {}).get("api", "")
    if not base:
        sys.exit(f"no wiki on record for {game!r}: pass --api https://<wiki>/api.php")
    return base


def wiki_files(base, query):
    """[(title, w, h, url)] for the file named `query` and every file whose
    name matches it, largest first."""
    stem = re.sub(r"\.(png|webp|gif|jpe?g|svg)$", "", query, flags=re.I).replace("_", " ")
    titles = {"File:" + query.replace("_", " ")} if "." in query else set()
    words = stem.split()
    for prefix in {stem, words[0], words[-1]}:
        d = R.api(base, action="query", list="allimages", aiprefix=prefix.replace(" ", "_"), ailimit=50) or {}
        titles |= {"File:" + i["name"].replace("_", " ") for i in d.get("query", {}).get("allimages", [])}
    d = R.api(base, action="query", list="search", srnamespace=6, srsearch=stem, srlimit=30) or {}
    titles |= {h["title"] for h in d.get("query", {}).get("search", [])}
    out = []
    titles = sorted(titles)
    for i in range(0, len(titles), 40):
        d = R.api(base, action="query", titles="|".join(titles[i:i + 40]), prop="imageinfo",
                  iiprop="url|size|mime") or {}
        for page in d.get("query", {}).get("pages", {}).values():
            for info in page.get("imageinfo", [])[:1]:
                out.append((page["title"], info["width"], info["height"], info["url"]))
    return sorted(out, key=lambda f: -f[1] * f[2])


def cmd_best(args):
    base = api_of(args.game, args.api)
    files = wiki_files(base, args.file)
    if not files:
        sys.exit(f"nothing on {base} matches {args.file!r}")
    os.makedirs(WORK, exist_ok=True)
    exact = "file:" + args.file.replace("_", " ").lower()
    print(f"{len(files)} file(s) on {urllib.parse.urlparse(base).netloc}, largest first:")
    for title, w, h, url in files[:args.n]:
        mark = "  <- the file asked for (its ORIGINAL)" if title.lower() == exact else ""
        try:
            data, size = as_png(get(url))
        except Exception as e:  # one dead link does not end the comparison
            print(f"  {w:>5} x {h:<5} {title}  (could not fetch: {e})")
            continue
        out = os.path.join(WORK, R.slug(args.game) + "--" + re.sub(r"[^A-Za-z0-9.]+", "_", title[5:]))
        out = os.path.splitext(out)[0] + ".png"
        open(out, "wb").write(data)
        print(f"  {size[0]:>5} x {size[1]:<5} {title}{mark}\n                -> {os.path.relpath(out, R.ROOT)}")
    if args.against:
        w, h = Image.open(args.against).size
        print(f"the copy in hand, {args.against}: {w} x {h}")
    print("Look at them before choosing: bigger with a frame or a background is a different icon.")


def cmd_add(args):
    if args.kind not in R.icon_kinds():
        sys.exit(f"kind should be one of {R.icon_kinds()}")
    if args.game not in R.catalog():
        sys.exit(f"{args.game!r} is not a game on the sheet")
    stem = f"{args.name}_{args.game}"
    stem = re.sub(r"[^A-Za-z0-9&'!+.-]+", "_", stem).strip("_")
    game, shown = suffix_game(stem, game_ids())
    if not game:
        sys.exit(f"{stem}: build_cosmetics_index.py would not find a game in that name")
    if args.range:  # one image of a SET: a chest's size, a difficulty's Fracture levels
        if not re.fullmatch(r"\d+-\d+", args.range):
            sys.exit("--range is <lo>-<hi>, as in 0-0 or 2-3")
        stem += "_" + args.range
    src = args.picture
    if not re.match(r"https?://", src) and not os.path.exists(src):
        src = os.path.join(WORK, src)  # a name `best` printed
    data, size = as_png(get(src) if re.match(r"https?://", src) else open(src, "rb").read())
    rows = R.read_rows("icons")
    if stem.lower() in R.icons_in_game() or any(r["File"].lower() == stem.lower() for r in rows):
        sys.exit(f"{stem} is already an icon or a candidate")
    row = {c: "" for c in R.KINDS["icons"]["columns"]}
    row.update(Kind=args.kind, File=stem, Name=shown, Game=args.game, Size=f"{size[0]}x{size[1]}",
               Source=args.page or (args.picture if re.match(r"https?://", args.picture) else ""),
               Confidence="ok", Status="to review")
    row["What it is there"] = args.what
    out = R.icon_candidate(row)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "wb").write(data)
    R.write_rows("icons", rows + [row])
    print(f"candidate: {os.path.relpath(out, R.ROOT)} ({row['Size']}), shown in game as {shown!r} from {game}")


def waiting():
    return [r for r in R.read_rows("icons") if r["Status"] == "to review" and r["Owner"].lower() != "no"
            and os.path.exists(R.icon_candidate(r))]


def cmd_sheet(args):
    from PIL import ImageDraw
    rows = waiting()
    if not rows:
        sys.exit("no icon is waiting for review")
    cell, per = 150, min(6, len(rows))
    sheet = Image.new("RGBA", (cell * per, (cell + 34) * -(-len(rows) // per)), (34, 34, 42, 255))
    draw = ImageDraw.Draw(sheet)
    for n, r in enumerate(rows):
        x, y = (n % per) * cell, (n // per) * (cell + 34)
        art = Image.open(R.icon_candidate(r)).convert("RGBA")
        k = 112 / max(art.size)
        art = art.resize((max(1, round(art.width * k)), max(1, round(art.height * k))),
                         Image.NEAREST if k >= 1 else Image.LANCZOS)
        sheet.alpha_composite(art, (x + (cell - art.width) // 2, y + 8 + (112 - art.height) // 2))
        draw.text((x + 6, y + 124), f"{n + 1}. {r['Kind']}: {r['Name']}", fill=(255, 255, 255, 255))
        draw.text((x + 6, y + 140), f"{r['Game']}  {r['Size']}"[:26], fill=(170, 170, 185, 255))
        print(f"{n + 1}. {r['Kind']}: {r['Name']} ({r['Game']}) {r['Size']}  {r['ID']}")
    os.makedirs(WORK, exist_ok=True)
    out = args.out or os.path.join(WORK, "to_review.png")
    sheet.save(out)
    print("->", out)


def cmd_apply(args):
    """Every `yes` moves into the art folder; every `no` loses its picture and
    keeps its row, so the same icon is not proposed twice."""
    rows, moved = R.read_rows("icons"), 0
    for r in rows:
        cand = R.icon_candidate(r)
        if not os.path.exists(cand):
            continue
        if r["Owner"].lower() == "yes":
            shutil.move(cand, os.path.join(R.ICON_ART, r["Kind"], r["File"] + ".png"))
            moved += 1
            print(f"in the game: {r['Kind']}/{r['File']}.png")
        elif r["Owner"].lower() == "no":
            os.remove(cand)
            print(f"turned down: {r['File']}")
    if moved:
        subprocess.check_call([sys.executable, os.path.join(R.TOOLS, "build_cosmetics_index.py")])
        print("now: `python3 tools/research.py build`, `godot --headless --editor --quit`, and\n"
              "tools/gut.sh test_customization (it pins which games have a Health, damage and gold icon)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("best", help="the original and every look-alike of a wiki file, largest first")
    p.add_argument("game")
    p.add_argument("file", help="the wiki's file name (Max_HP.png), or words to search for")
    p.add_argument("--api", help="the wiki's api.php, when it is not the one in research/wikis.json")
    p.add_argument("--against", help="the copy in hand, to compare sizes")
    p.add_argument("-n", type=int, default=12)
    p.set_defaults(fn=cmd_best)
    p = sub.add_parser("add", help="hold a picture as a candidate for the owner")
    p.add_argument("kind")
    p.add_argument("name")
    p.add_argument("game")
    p.add_argument("picture", help="a URL, a path, or a file name `best` saved")
    p.add_argument("--what", default="", help="what it is in its own game")
    p.add_argument("--page", default="", help="the page it came from")
    p.add_argument("--range", default="", help="<lo>-<hi> for one image of a set (customization.md §2)")
    p.set_defaults(fn=cmd_add)
    p = sub.add_parser("sheet", help="a numbered contact sheet of the candidates waiting")
    p.add_argument("--out")
    p.set_defaults(fn=cmd_sheet)
    p = sub.add_parser("apply", help="move every yes into images2.0/icons/ and rebuild the index")
    p.set_defaults(fn=cmd_apply)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()

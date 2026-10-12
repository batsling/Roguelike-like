#!/usr/bin/env python3
"""Add the songs in the player's music folder to the `radio` sheet.

The music never leaves the player's PC (docs/roguelike-radio.md §2a). The
Radio screen's "Export song list" button writes `tools/radio_import.json` (or
the user folder, from an exported build): every .mp3/.ogg/.wav under the music
folder, subfolders included, with its path relative to the folder and what its
own tags say (title, artist, album, year). This turns that list into rows:

    python3 tools/apply_radio_import.py                 # tools/radio_import.json -> sheet, then regenerate
    python3 tools/apply_radio_import.py path/to/file.json
    python3 tools/apply_radio_import.py --dry-run       # say what would be added, write nothing
    python3 tools/apply_radio_import.py --game "Some Folder=Hades"   # name a folder's game by hand

For each file not already on a row (matched by `File`, case-insensitively):

  Name    the title tag; without one, the file name less its track number
          ("01 - No Escape.mp3" -> "No Escape") and a leading "<game> - "
  Artist  the artist tag (the album artist when there isn't one)
  Album   the album tag
  Year    the year out of the date tag
  Game    the game whose name is a FOLDER on the file's path (innermost
          first), or failing that its album; soundtrack words are ignored, so
          "Slay the Spire OST" and "Hades (Original Soundtrack)" both match.
          Only an exact match counts. A file no game matches is still added,
          with Game blank (never drawn) and listed at the end, so its game can
          be typed into the sheet or given with --game and the script re-run
  File    the path as the export gives it ("Hades/01 No Escape.mp3"): the game
          plays it from that subfolder of the music folder
  Tags    `menu` when the title says it is the menu or title music (§3: a
          game's first song is its menu song); otherwise blank

It is IDEMPOTENT: a file already on a row is skipped, so the export can be
re-run whenever music is added and only the new files are written. Rows are
appended, and an existing row is only ever touched in two ways: a blank `Game`
is filled when a --game (or the catalog) now names its folder, and a `File`
the folder doesn't have is re-pointed at a file that is the same song (same
Name + Artist: a typo, a rename, the sheet's example row). Two DIFFERENT files
that would make one song id (two games' untagged "Main Menu.mp3") are told
apart by the game in brackets after the name, since the generator refuses two
rows with one id; a true duplicate is skipped and reported.

The sheet is written through `_xlsx_surgery` (never openpyxl's save, which drops
the workbook's charts), then `generate_song_tres.py` runs. Delete the JSON in
the same commit; it is spent.
"""

import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402
import generate_song_tres as songs  # noqa: E402
import generate_status_tres as dsl  # noqa: E402

ROOT = songs.PROJECT_ROOT
XLSX = songs.XLSX_PATH
DEFAULT = os.path.join(ROOT, "tools", "radio_import.json")
SHEET = songs.SHEET
HEADERS = list(songs.HEADERS)

# Words a soundtrack's folder or album carries that its game's name does not.
SOUNDTRACK_WORDS = re.compile(
    r"\b(original|official|game|video ?game|motion picture|complete|deluxe|extended|"
    r"sound ?tracks?|o\.?s\.?t\.?|score|music|songs|ost|vol(ume)?\.? ?\d+|disc ?\d+|cd ?\d+)\b",
    re.I)
MENU_TITLE = re.compile(r"\b(main )?menu\b|\btitle (screen|theme|music)\b|\bmain theme\b", re.I)
TRACK_NUMBER = re.compile(r"^\s*(\d{1,3}|[a-z]?\d{1,2}-\d{1,3})(\s*[-._)]\s*|\s+)", re.I)


def norm(s: str) -> str:
    """Lower case, '&' as 'and', punctuation to spaces, single spaces."""
    s = str(s or "").lower().replace("&", " and ").replace("'", "").replace("’", "")
    return " ".join(re.sub(r"[^a-z0-9]+", " ", s).split())


def strip_soundtrack(s: str) -> str:
    s = re.sub(r"[\(\[][^\)\]]*[\)\]]", " ", str(s or ""))  # (Original Soundtrack), [2020]
    s = SOUNDTRACK_WORDS.sub(" ", s)
    s = re.sub(r"\b(19|20)\d\d\b", " ", s)
    return norm(s)


def game_names() -> tuple:
    """({normalized name or id: id}, {id: display name}) off data/games/*.tres."""
    index, display = {}, {}
    for key, gid in songs.game_index().items():
        index.setdefault(norm(key), gid)
    for path in os.listdir(songs.GAMES_DIR):
        if not path.endswith(".tres"):
            continue
        with open(os.path.join(songs.GAMES_DIR, path), encoding="utf-8") as f:
            head = f.read(2048)
        gid = re.search(r'^id = &"([^"]+)"', head, re.M)
        name = re.search(r'^display_name = "((?:[^"\\]|\\.)*)"', head, re.M)
        if gid and name:
            display[gid.group(1)] = name.group(1).replace('\\"', '"')
    return index, display


def match_game(candidates, index: dict):
    """The id of the first candidate naming a game exactly, as is or less its
    soundtrack words; None when none does."""
    for c in candidates:
        for key in (norm(c), strip_soundtrack(c)):
            if key and key in index:
                return index[key]
    return None


def title_from_file(path: str, game_name: str) -> str:
    stem = os.path.splitext(os.path.basename(path))[0].replace("_", " ")
    stem = TRACK_NUMBER.sub("", stem, count=1).strip() or stem.strip()
    if game_name and " - " in stem:
        head, rest = stem.split(" - ", 1)
        if norm(head) == norm(game_name) and rest.strip():
            stem = rest.strip()
    return stem


def sheet_grid(wb) -> list:
    grid = wb.read_grid(SHEET)
    if not grid:
        sys.exit("radio: the sheet is empty — run tools/_radio_sheet_setup.py")
    header = [str(h).strip() for h in grid[0]]
    if header[:len(HEADERS)] != HEADERS:
        sys.exit("radio headers are %r, expected %r — the sheet's shape moved; "
                 "update this script" % (header, HEADERS))
    return grid


def plan(export: dict, grid: list, overrides: dict) -> tuple:
    """([new rows], [report lines], {folder: [files]} with no game, number of
    existing rows re-pointed). Re-pointing edits `grid` in place."""
    index, display = game_names()
    col = {h: i for i, h in enumerate(HEADERS)}
    in_folder = {str(e.get("file") or "").replace("\\", "/").strip("/").lower()
                 for e in export.get("files", [])}
    on_sheet = set()
    known = {}  # song id -> its row in `grid`
    for row in grid[1:]:
        while len(row) < len(HEADERS):
            row.append("")
        f = str(row[col["File"]] or "").strip().replace("\\", "/").lower()
        if f:
            on_sheet.add(f)
        name = str(row[col["Name"]] or "").strip()
        artist = str(row[col["Artist"]] or "").strip()
        if name:
            known[dsl.slugify("%s %s" % (name, artist) if artist else name)] = row

    rows, report, unmatched, repointed = [], [], {}, 0
    for entry in export.get("files", []):
        rel = str(entry.get("file") or "").replace("\\", "/").strip("/")
        if not rel or os.path.splitext(rel)[1].lower() not in songs.AUDIO:
            continue
        if rel.lower() in on_sheet:
            continue
        folders = rel.split("/")[:-1]
        folder = "/".join(folders)
        album = str(entry.get("album") or "").strip()
        gid = None
        for f in reversed(folders):  # a hand-named folder wins over a guess
            if norm(f) in overrides:
                gid = overrides[norm(f)]
                break
        if gid is None:
            gid = match_game(list(reversed(folders)) + [album], index)
        game = display.get(gid, gid) if gid else ""

        title = str(entry.get("title") or "").strip() or title_from_file(rel, game)
        artist = str(entry.get("artist") or "").strip()
        sid = dsl.slugify("%s %s" % (title, artist) if artist else title)
        if sid in known:
            row = known[sid]
            old = str(row[col["File"]] or "").strip()
            if old.replace("\\", "/").lower() in in_folder:
                # A different file with the same name and artist: two games'
                # untagged "Main Menu.mp3", most often. Told apart by its game
                # (or folder) in the Name; a real duplicate is still skipped.
                tell = game or (folders[-1] if folders else "")
                renamed = "%s (%s)" % (title, tell) if tell else ""
                rid = dsl.slugify("%s %s" % (renamed, artist) if artist else renamed)
                if not renamed or rid in known:
                    report.append("  SKIPPED %s: %r by %r is already a song, playing %s"
                                  % (rel, title, artist or "?", old))
                    continue
                title, sid = renamed, rid
            else:
                # The sheet knows this song but names a file the folder doesn't
                # have (a typo, a rename, the example row): this file is it.
                row[col["File"]] = rel
                on_sheet.add(rel.lower())
                repointed += 1
                report.append("  ~ %-28s %-36s File %s -> %s" % (
                    str(row[col["Game"]] or "(no game)")[:28], title[:36], old or "(blank)", rel))
                continue
        on_sheet.add(rel.lower())
        year = str(entry.get("year") or "").strip()
        tags = "menu" if MENU_TITLE.search(title) else ""
        rows.append([title, artist, album, int(year) if year.isdigit() else "",
                     game, rel, tags])
        known[sid] = rows[-1]
        report.append("  + %-28s %-36s %s%s" % ((game or "(no game)")[:28], title[:36],
                                                artist or "?", "  [menu]" if tags else ""))
        if not game:
            unmatched.setdefault(folder or "(top of the folder)", []).append(rel)
    return rows, report, unmatched, repointed


def fill_blank_games(grid: list, overrides: dict, report: list) -> int:
    """Give a game to rows already on the sheet without one, when a --game
    names their folder (or the catalog now has a game their folder names) —
    so the run after "NO GAME for ..." fixes the rows the first run added.
    Edits `grid` in place; returns how many rows it changed."""
    index, display = game_names()
    col = {h: i for i, h in enumerate(HEADERS)}
    n = 0
    for row in grid[1:]:
        while len(row) < len(HEADERS):
            row.append("")
        rel = str(row[col["File"]] or "").replace("\\", "/").strip("/")
        if str(row[col["Game"]] or "").strip() or not rel:
            continue
        folders = rel.split("/")[:-1]
        gid = next((overrides[norm(f)] for f in reversed(folders) if norm(f) in overrides), None)
        gid = gid or match_game(list(reversed(folders)) + [str(row[col["Album"]] or "")], index)
        if gid:
            row[col["Game"]] = display.get(gid, gid)
            report.append("  = %-28s %s (was blank)" % (row[col["Game"]][:28], rel))
            n += 1
    return n


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("path", nargs="?", default=DEFAULT)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-generate", action="store_true")
    ap.add_argument("--game", action="append", default=[], metavar="FOLDER=GAME",
                    help="the game a folder's songs belong to, when its name doesn't say")
    args = ap.parse_args()

    if not os.path.exists(args.path):
        sys.exit("no song list at %s — export it from the game first (the Radio "
                 "screen's Export song list button)" % os.path.relpath(args.path, ROOT))
    export = json.load(open(args.path, encoding="utf-8"))

    index, _display = game_names()
    overrides = {}
    for pair in args.game:
        folder, _, game = pair.partition("=")
        gid = index.get(norm(game))
        if not folder.strip() or gid is None:
            sys.exit("--game %r: expected FOLDER=GAME with GAME a game in the catalog" % pair)
        overrides[norm(folder)] = gid

    with Workbook(XLSX) as wb:
        grid = sheet_grid(wb)
        rows, report, unmatched, repointed = plan(export, grid, overrides)
        filled = fill_blank_games(grid, overrides, report)
        total = len(export.get("files", []))
        print("%s: %d file(s) in the list, %d new song(s) to add" % (
            os.path.relpath(args.path, ROOT), total, len(rows)))
        for line in report:
            print(line)
        if unmatched:
            print("\nNO GAME for %d folder(s) — added with Game blank (never drawn). Type "
                  "the game into the sheet, or re-run with --game \"FOLDER=GAME\":"
                  % len(unmatched))
            for folder, files in sorted(unmatched.items()):
                print("  %s (%d file%s)" % (folder, len(files), "" if len(files) == 1 else "s"))
        if args.dry_run or (not rows and not filled and not repointed):
            return 0  # nothing marked dirty, so the workbook is left as it was
        wb.write_grid(SHEET, grid + rows)
    print("\nwrote %d new row(s) to the radio sheet; %d existing row(s) given a game, "
          "%d pointed at the file the folder has" % (len(rows), filled, repointed))
    if not args.no_generate:
        return subprocess.call([sys.executable, os.path.join(ROOT, "tools", "generate_song_tres.py")])
    return 0


if __name__ == "__main__":
    sys.exit(main())

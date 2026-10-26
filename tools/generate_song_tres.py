#!/usr/bin/env python3
"""
Generate Godot SongData .tres from the `radio` sheet of tools/Roguelikes.xlsx
into data/songs/ — the songs of ROGUELIKE RADIO (docs/roguelike-radio.md).

  radio: Name | Artist | Album | Year | Game | File | Tags

The audio is the player's own and is never in the repo; `File` only names it.
`Game` may be a game's display name or its id, and must be a game in the
catalog: a song is unlocked by playing that game, drawn at random from its songs
still locked (Radio.earned has the rule). A row with no `Game` is never drawn.
The sheet once had `Unlock` and `Count` columns, one rule per song; they were
taken off in October 2026 (tools/oneshots/_radio_random_unlocks_setup.py), and a sheet
that still has them is refused rather than silently ignored, and so is one
missing any of the seven columns. It also once had an `Image` column for album
art; the owner took it off on 12 Oct 2026, because a song's picture is its
game's cover and nothing else, so that is what the radio shows.
A `menu` tag marks the game's menu song: the first song a game gives is its
menu song, if it has one (docs/roguelike-radio.md §3).

The output folder is REWRITTEN, not added to: a row deleted from the sheet takes
its song with it, so the example row the sheet was created with goes away the
moment it is deleted.

  python3 tools/generate_song_tres.py           # write data/songs/*.tres
  python3 tools/generate_song_tres.py --list    # print the parse, write nothing
"""

import argparse
import glob
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_status_tres as dsl  # noqa: E402  (slugify, gd_str, rows)

PROJECT_ROOT = dsl.PROJECT_ROOT
XLSX_PATH = dsl.XLSX_PATH
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "songs")
GAMES_DIR = os.path.join(PROJECT_ROOT, "data", "games")
SHEET = "radio"

# The columns songs no longer have, and what to do about one still there (see
# the docstring).
RETIRED = {
    "Unlock": "songs are drawn at random now; run tools/oneshots/_radio_random_unlocks_setup.py",
    "Count": "songs are drawn at random now; run tools/oneshots/_radio_random_unlocks_setup.py",
    "Image": "every song shows its game's cover; delete the column",
}
# Every column the generator reads. A missing one is refused by name: read as
# blank on every row instead, a renamed `Tags` would quietly take every song off
# its stations and out of the `menu` rule (docs/roguelike-radio.md §3).
HEADERS = ("Name", "Artist", "Album", "Year", "Game", "File", "Tags")
AUDIO = (".mp3", ".ogg", ".wav")


def _clean(v) -> str:
    return dsl._clean(v)


def game_index() -> dict:
    """lower-cased display name AND id -> id, read off data/games/*.tres.

    Only the two fields are read, by regex — the generator never loads a game.
    """
    out = {}
    for path in glob.glob(os.path.join(GAMES_DIR, "*.tres")):
        with open(path, encoding="utf-8") as f:
            head = f.read(2048)
        gid = re.search(r'^id = &"([^"]+)"', head, re.M)
        name = re.search(r'^display_name = "((?:[^"\\]|\\.)*)"', head, re.M)
        if not gid:
            continue
        out[gid.group(1).lower()] = gid.group(1)
        if name:
            out[name.group(1).replace('\\"', '"').lower()] = gid.group(1)
    return out


def _int(raw, what: str, name: str) -> int:
    s = _clean(raw)
    if not s:
        return 0
    try:
        return int(float(s))
    except ValueError:
        raise ValueError("radio %s: %s %r is not a number" % (name, what, raw))


def song_tres(row, games: dict) -> tuple:
    name = _clean(row.get("Name"))
    artist = _clean(row.get("Artist"))
    if not name:
        raise ValueError("radio: a row has no Name")
    sid = dsl.slugify("%s %s" % (name, artist) if artist else name)

    game_raw = _clean(row.get("Game"))
    game_id = games.get(game_raw.lower(), "") if game_raw else ""
    if game_raw and not game_id:
        raise ValueError("radio %s: Game %r is not a game in the catalog "
                         "(use its name as the games sheet spells it, or its id)"
                         % (name, game_raw))


    file = _clean(row.get("File"))
    if file and os.path.splitext(file)[1].lower() not in AUDIO:
        raise ValueError("radio %s: File %r must be one of %s"
                         % (name, file, " ".join(AUDIO)))

    tags = [t.strip().lower() for t in _clean(row.get("Tags")).split(",") if t.strip()]
    for t in tags:
        if t.startswith("*"):
            raise ValueError("radio %s: tag %r may not start with * (the radio keeps "
                             "those for its own stations, like *favorites)" % (name, t))

    lines = [
        '[gd_resource type="Resource" script_class="SongData" load_steps=2 '
        'format=3 uid="uid://song_%s"]' % sid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/SongData.gd" '
        'id="1_song"]',
        "",
        "[resource]",
        'script = ExtResource("1_song")',
        'id = &"%s"' % sid,
        'title = "%s"' % dsl.gd_str(name),
        'artist = "%s"' % dsl.gd_str(artist),
        'album = "%s"' % dsl.gd_str(_clean(row.get("Album"))),
        "year = %d" % _int(row.get("Year"), "Year", name),
        'game_id = &"%s"' % game_id,
        'file = "%s"' % dsl.gd_str(file),
        "tags = PackedStringArray(%s)" % ", ".join('"%s"' % dsl.gd_str(t) for t in tags),
    ]
    return sid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run tools/oneshots/_radio_sheet_setup.py"
                         % (XLSX_PATH, SHEET))
    header = [str(c.value).strip() if c.value is not None else "" for c in wb[SHEET][1]]
    stale = [h for h in RETIRED if h in header]
    if stale:
        raise SystemExit("radio: the sheet still has %s — %s"
                         % (" and ".join(stale), RETIRED[stale[0]]))
    missing = [h for h in HEADERS if h not in header]
    if missing:
        raise SystemExit("radio: the sheet is missing %s (the columns are %s)"
                         % (" and ".join(missing), " | ".join(HEADERS)))
    games = game_index()
    songs = {}
    for row in dsl.rows(wb[SHEET]):
        sid, text = song_tres(row, games)
        if sid in songs:
            raise ValueError("radio: two rows make the song id %r — give them "
                             "different names or artists" % sid)
        songs[sid] = (row, text)

    if args.list:
        for sid, (_row, text) in songs.items():
            print("=== %s ===\n%s" % (sid, text))
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    for stale in glob.glob(os.path.join(OUT_DIR, "*.tres")):
        if os.path.splitext(os.path.basename(stale))[0] not in songs:
            os.remove(stale)
    for sid, (_row, text) in songs.items():
        with open(os.path.join(OUT_DIR, sid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
    print("Wrote %d songs to %s" % (len(songs), OUT_DIR))
    for sid in songs:
        print("  -", sid)


if __name__ == "__main__":
    main()

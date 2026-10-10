#!/usr/bin/env python3
"""
Generate Godot SongData .tres from the `radio` sheet of tools/Roguelikes.xlsx
into data/songs/ — the songs of ROGUELIKE RADIO (docs/roguelike-radio.md).

  radio: Name | Artist | Album | Year | Game | Unlock | Count | File | Image | Tags

The audio is the player's own and is never in the repo; `File` only names it.
`Game` may be a game's display name or its id, and must be a game in the
catalog. `Unlock` is `goals` ("complete X distinct goals in Y" — every kind of
goal but curses), `wins` ("beat Y X times") or blank (blank = locked until it
has a rule). `enemies` is read as `goals`, the word the rule had for a while. `Image` is a base name under images2.0/radio/.

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
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "radio")
IMG_RES_PREFIX = "res://images2.0/radio/"
SHEET = "radio"

UNLOCKS = ("goals", "wins")
ALIASES = {"enemies": "goals", "enemy": "goals", "goal": "goals", "win": "wins"}
AUDIO = (".mp3", ".ogg", ".wav")
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")


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


def _image(raw) -> str:
    base = _clean(raw)
    if not base:
        return ""
    if os.path.splitext(base)[1].lower() in IMAGE_EXTS:
        return IMG_RES_PREFIX + base
    for ext in IMAGE_EXTS:
        if os.path.exists(os.path.join(IMG_DIR, base + ext)):
            return IMG_RES_PREFIX + base + ext
    return IMG_RES_PREFIX + base + ".png"


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

    unlock = _clean(row.get("Unlock")).lower()
    unlock = ALIASES.get(unlock, unlock)
    if unlock and unlock not in UNLOCKS:
        raise ValueError("radio %s: Unlock %r must be one of %s, or blank"
                         % (name, row.get("Unlock"), ", ".join(UNLOCKS)))
    count = _int(row.get("Count"), "Count", name)
    if unlock and not game_id:
        raise ValueError("radio %s: an Unlock rule needs a Game to count on" % name)
    if unlock and count < 1:
        raise ValueError("radio %s: Unlock %s needs a Count of 1 or more"
                         % (name, unlock))

    file = _clean(row.get("File"))
    if file and os.path.splitext(file)[1].lower() not in AUDIO:
        raise ValueError("radio %s: File %r must be one of %s"
                         % (name, file, " ".join(AUDIO)))

    tags = [t.strip().lower() for t in _clean(row.get("Tags")).split(",") if t.strip()]

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
        'unlock = &"%s"' % unlock,
        "count = %d" % count,
        'file = "%s"' % dsl.gd_str(file),
        'image_path = "%s"' % dsl.gd_str(_image(row.get("Image"))),
        "tags = PackedStringArray(%s)" % ", ".join('"%s"' % dsl.gd_str(t) for t in tags),
    ]
    return sid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run tools/_radio_sheet_setup.py"
                         % (XLSX_PATH, SHEET))
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
    for sid, (row, text) in songs.items():
        with open(os.path.join(OUT_DIR, sid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        img = _image(row.get("Image"))
        if img and not os.path.exists(os.path.join(PROJECT_ROOT, img[len("res://"):])):
            print("  ! %s: no art at %s" % (sid, img))
    print("Wrote %d songs to %s" % (len(songs), OUT_DIR))
    for sid in songs:
        print("  -", sid)


if __name__ == "__main__":
    main()

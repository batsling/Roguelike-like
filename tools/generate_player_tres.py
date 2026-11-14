#!/usr/bin/env python3
"""
Generate Godot PlayerData .tres from the `players` sheet of tools/Roguelikes.xlsx
into data/players/ (docs/players-design.md).

  players: Name | Mechanics | File | Hat

  Name         the player's name, as the picker shows it. Its id is the slug.
  Mechanics    what the player adds to a run: a comma list of NAMES from the
               `mechanics` sheet (generate_mechanic_tres.py), any mix of them —
               `Hunger, Unidentified Weapons`. A name with no row there is
               refused. Blank = the game as it is.
  File         the art's base name in images2.0/players/ (`RetroBat` ->
               images2.0/players/RetroBat.png). Blank, or no such file, = no art,
               and the picker shows the name instead. The SMALL token is
               images2.0/players/Icon/<File>.png when there is one (Batsaac's
               face, cut out so it reads at 26px), else the full picture.
  Hat          where a worn hat sits on the full picture (docs/customization.md
               §7, HatArt): `x, y, width, tilt` — the brim's spot as a percent of
               the picture across and down, the hat's width as a percent of the
               picture's, and the tilt in degrees clockwise (optional, 0). Blank =
               no spot, and the player wears no hat. The small token in Icon/
               never wears one (the owner, 14 Nov 2026).

What UNLOCKS a player is not here: it is a row of the `achievements` sheet under
the `Players` tab (docs/achievements.md), like a character's. Every player is an
original work.

The output folder is REWRITTEN, not added to: a row deleted from the sheet takes
its player with it.

  python3 tools/generate_player_tres.py          # write data/players/*.tres
  python3 tools/generate_player_tres.py --list   # print, write nothing
"""

import argparse
import glob
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_mechanic_tres import sheet_mechanics  # noqa: E402

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get("CARDS_XLSX", os.path.join(SCRIPT_DIR, "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "players")
ART_DIR = os.path.join(PROJECT_ROOT, "images2.0", "players")
SHEET = "players"
HEADERS = ("Name", "Mechanics", "File", "Hat")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v) -> str:
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def art_path(file: str, sub: str = "") -> str:
    """res:// path of the player's picture, matched case-insensitively, or "".
    `sub` "Icon" looks in images2.0/players/Icon/ for the small token instead."""
    folder = os.path.join(ART_DIR, sub) if sub else ART_DIR
    if not file or not os.path.isdir(folder):
        return ""
    for fn in os.listdir(folder):
        if fn.lower() == file.lower() + ".png":
            return "res://images2.0/players/%s%s" % (sub + "/" if sub else "", fn)
    return ""


def parse_mechanics(raw, who: str, known: dict) -> list:
    """`known` is the `mechanics` sheet: lower-cased name -> id."""
    out = []
    for term in [t.strip().lower() for t in _clean(raw).split(",") if t.strip()]:
        if term not in known:
            raise ValueError("players %s: Mechanics %r is not a row of the `mechanics` "
                             "sheet (%s)" % (who, term, ", ".join(sorted(known)) or "it is empty"))
        if known[term] not in out:
            out.append(known[term])
    return out


def parse_spot(raw, who: str, col: str) -> tuple:
    """`x, y, width[, tilt]` -> four floats, or None for a blank cell."""
    text = _clean(raw)
    if not text:
        return None
    try:
        nums = [float(t) for t in text.replace(";", ",").split(",") if t.strip()]
    except ValueError:
        raise ValueError("players %s: %s %r is not `x, y, width, tilt`" % (who, col, text))
    if len(nums) == 3:
        nums.append(0.0)
    if len(nums) != 4 or nums[2] <= 0:
        raise ValueError("players %s: %s %r is not `x, y, width, tilt` with a width over 0"
                         % (who, col, text))
    return tuple(nums)


def gd_vec4(spot) -> str:
    def n(v):
        return ("%g" % v) if v != int(v) else "%d" % v
    return "Vector4(%s)" % ", ".join(n(v) for v in (spot or (0, 0, 0, 0)))


def player_tres(row: dict, order: int, known: dict) -> tuple:
    name = _clean(row.get("Name"))
    if not name:
        raise ValueError("players: a row has no Name")
    pid = slugify(name)
    mechanics = parse_mechanics(row.get("Mechanics"), name, known)
    hat = parse_spot(row.get("Hat"), name, "Hat")
    lines = [
        '[gd_resource type="Resource" script_class="PlayerData" load_steps=2 '
        'format=3 uid="uid://player_%s"]' % pid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/PlayerData.gd" id="1_player"]',
        "",
        "[resource]",
        'script = ExtResource("1_player")',
        'id = &"%s"' % pid,
        'display_name = "%s"' % gd_str(name),
        "order = %d" % order,
        "mechanics = Array[StringName]([%s])" % ", ".join('&"%s"' % m for m in mechanics),
        'portrait_path = "%s"' % art_path(_clean(row.get("File"))),
        # The small token (the header, beside the character's): its own file in
        # Icon/ when the full picture does not read small (Batsaac's face), else
        # the full picture itself (Retro Bat).
        'icon_path = "%s"' % (art_path(_clean(row.get("File")), "Icon")
                              or art_path(_clean(row.get("File")))),
        "hat_spot = %s" % gd_vec4(hat),
    ]
    return pid, "\n".join(lines) + "\n"


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if not r or all(v is None or str(v).strip() == "" for v in r):
            continue
        yield dict(zip(headers, r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run tools/oneshots/_players_sheet_setup.py"
                         % (XLSX_PATH, SHEET))
    known = sheet_mechanics(wb)
    out = {}
    for i, row in enumerate(rows(wb[SHEET])):
        pid, text = player_tres(row, (i + 1) * 10, known)
        if pid in out:
            raise ValueError("players: two rows are called %r" % pid)
        out[pid] = text
    if args.list:
        for pid, text in out.items():
            print("=== %s ===\n%s" % (pid, text))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    for stale in glob.glob(os.path.join(OUT_DIR, "*.tres")):
        if os.path.splitext(os.path.basename(stale))[0] not in out:
            os.remove(stale)
    for pid, text in out.items():
        with open(os.path.join(OUT_DIR, pid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
    print("Wrote %d players to %s" % (len(out), OUT_DIR))
    for pid in out:
        print("  -", pid)


if __name__ == "__main__":
    main()

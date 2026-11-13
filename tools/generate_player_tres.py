#!/usr/bin/env python3
"""
Generate Godot PlayerData .tres from the `players` sheet of tools/Roguelikes.xlsx
into data/players/ (docs/players-design.md).

  players: Name | Description | Mechanics | File

  Name         the player's name, as the picker shows it. Its id is the slug.
  Description  one line about them.
  Mechanics    what the player adds to a run, comma-separated, by name:
               `Hunger`, `Unidentified Weapons` (MECHANICS below, mirroring
               PlayerData.MECHANICS). Blank = the game as it is.
  File         the art's base name in images2.0/players/ (`RetroBat` ->
               images2.0/players/RetroBat.png). Blank, or no such file, = no art,
               and the picker shows the name instead.

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

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get("CARDS_XLSX", os.path.join(SCRIPT_DIR, "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "players")
ART_DIR = os.path.join(PROJECT_ROOT, "images2.0", "players")
SHEET = "players"
HEADERS = ("Name", "Description", "Mechanics", "File")

# Sheet word -> PlayerData.MECHANICS id. Keep the two in step.
MECHANICS = {"hunger": "hunger", "unidentified weapons": "unidentified_weapons"}


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v) -> str:
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def art_path(file: str) -> str:
    """res:// path of the player's picture, matched case-insensitively, or ""."""
    if not file or not os.path.isdir(ART_DIR):
        return ""
    for fn in os.listdir(ART_DIR):
        if fn.lower() == file.lower() + ".png":
            return "res://images2.0/players/%s" % fn
    return ""


def parse_mechanics(raw, who: str) -> list:
    out = []
    for term in [t.strip().lower() for t in _clean(raw).split(",") if t.strip()]:
        if term not in MECHANICS:
            raise ValueError("players %s: Mechanics %r is not one of %s"
                             % (who, term, ", ".join(sorted(MECHANICS))))
        if MECHANICS[term] not in out:
            out.append(MECHANICS[term])
    return out


def player_tres(row: dict, order: int) -> tuple:
    name = _clean(row.get("Name"))
    if not name:
        raise ValueError("players: a row has no Name")
    pid = slugify(name)
    mechanics = parse_mechanics(row.get("Mechanics"), name)
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
        'description = "%s"' % gd_str(_clean(row.get("Description"))),
        "order = %d" % order,
        "mechanics = Array[StringName]([%s])" % ", ".join('&"%s"' % m for m in mechanics),
        'portrait_path = "%s"' % art_path(_clean(row.get("File"))),
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
    out = {}
    for i, row in enumerate(rows(wb[SHEET])):
        pid, text = player_tres(row, (i + 1) * 10)
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

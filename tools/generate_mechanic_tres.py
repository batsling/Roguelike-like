#!/usr/bin/env python3
"""
Generate Godot MechanicData .tres from the `mechanics` sheet of
tools/Roguelikes.xlsx into data/mechanics/ (docs/players-design.md §1).

  mechanics: Name | Description

  Name         the mechanic's name, as the `players` sheet's Mechanics column
               spells it and as the picker shows it. Its id is the slug
               (`Unidentified Weapons` -> unidentified_weapons).
  Description  what it does, as the player reads it on the player select, the
               manual and the hero's card.

A player's `Mechanics` cell is a comma list of these names, any mix of them
(generate_player_tres.py refuses a name with no row here).

The RULES of a mechanic are code: each asks `GameState.has_mechanic(<id>)`, and
the ids that have rules are `PlayerData.MECHANICS`. A row here whose id is not in
that list is written all the same, with a note printed: it is a name and a
sentence until its rule exists.

The output folder is REWRITTEN, not added to: a row deleted from the sheet takes
its mechanic with it.

  python3 tools/generate_mechanic_tres.py          # write data/mechanics/*.tres
  python3 tools/generate_mechanic_tres.py --list   # print, write nothing
"""

import argparse
import glob
import os
import re
import sys

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get("CARDS_XLSX", os.path.join(SCRIPT_DIR, "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "mechanics")
PLAYER_DATA = os.path.join(PROJECT_ROOT, "scripts", "resources", "PlayerData.gd")
SHEET = "mechanics"
HEADERS = ("Name", "Description")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v) -> str:
    return ("" if v is None else str(v)).strip()


def sheet_mechanics(wb) -> dict:
    """lower-cased Name -> id for every row of the sheet, in sheet order."""
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run "
                         "tools/oneshots/_mechanics_sheet_and_abandon_hat.py" % (XLSX_PATH, SHEET))
    out = {}
    for row in rows(wb[SHEET]):
        name = _clean(row.get("Name"))
        if name:
            out[name.lower()] = slugify(name)
    return out


def coded_ids() -> list:
    """The ids PlayerData.MECHANICS lists: the mechanics that have rules."""
    with open(PLAYER_DATA, encoding="utf-8") as f:
        m = re.search(r"^const MECHANICS := \[(.*?)\]", f.read(), re.M | re.S)
    return re.findall(r'&"([^"]+)"', m.group(1)) if m else []


def mechanic_tres(row: dict, order: int) -> tuple:
    name = _clean(row.get("Name"))
    if not name:
        raise ValueError("mechanics: a row has no Name")
    description = _clean(row.get("Description"))
    if not description:
        raise ValueError("mechanics %s: no Description — it is what the player reads" % name)
    mid = slugify(name)
    lines = [
        '[gd_resource type="Resource" script_class="MechanicData" load_steps=2 '
        'format=3 uid="uid://mechanic_%s"]' % mid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/MechanicData.gd" id="1_mech"]',
        "",
        "[resource]",
        'script = ExtResource("1_mech")',
        'id = &"%s"' % mid,
        'display_name = "%s"' % gd_str(name),
        'description = "%s"' % gd_str(description),
        "order = %d" % order,
    ]
    return mid, "\n".join(lines) + "\n"


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
    sheet_mechanics(wb)  # the missing-sheet message
    out = {}
    for i, row in enumerate(rows(wb[SHEET])):
        mid, text = mechanic_tres(row, (i + 1) * 10)
        if mid in out:
            raise ValueError("mechanics: two rows are called %r" % mid)
        out[mid] = text
    if args.list:
        for mid, text in out.items():
            print("=== %s ===\n%s" % (mid, text))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    for stale in glob.glob(os.path.join(OUT_DIR, "*.tres")):
        if os.path.splitext(os.path.basename(stale))[0] not in out:
            os.remove(stale)
    for mid, text in out.items():
        with open(os.path.join(OUT_DIR, mid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
    print("Wrote %d mechanics to %s" % (len(out), OUT_DIR))
    coded = coded_ids()
    for mid in out:
        print("  - %s%s" % (mid, "" if mid in coded
                            else "   (NOTE: no rule in code yet — not in PlayerData.MECHANICS)"))


if __name__ == "__main__":
    main()

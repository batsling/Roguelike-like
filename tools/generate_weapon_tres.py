#!/usr/bin/env python3
"""Generate Godot WeaponData .tres from the `weapons` sheet of
tools/Roguelikes.xlsx into data/weapons2.0/.

Weapons are the EIGHTH loot kind (docs/loot-passives.md §12): pieces that sit in
the pack like a trinket, are aimed at the board like a thrown potion, and charge
off their own goal.

  weapons: Name | Rarity | Size | Aim | Area | Effect | Type | Passive |
           Passive Effect | Goal | Charge | Tag | Game | Image

  Size            "HxW", ROWS FIRST, as trinkets and bags write a footprint.
  Aim             where the swing may be aimed:
                    any | front | back | column N | enemy | none | random
                  `random` needs no click: each strike lands on a random enemy
                  standing on the board (and whiffs on an empty one).
  Area            what it hits, measured from the aimed square:
                    a word    cell row col cross 3x3 5x5 board plus diagonals
                    RxC       a rectangle, rows first: its rows CENTRED on the
                              aimed square (an even height puts the extra row
                              below), its columns running AWAY from you starting
                              at it. 3x3 and 5x5 stay the words they already were
                              (a centred square), because potions use them.
                    a drawing rows split by "/", "#" a square it hits, "." one
                              it skips, "O" the aimed square (hit). Left is
                              toward you: ".#./#O#/.#." is a plus.
  Effect          comma-separated swing verbs, in the order they land:
                    stun N              N Stun on every enemy covered (required)
                    push <dir> N        then shove each enemy covered N squares
                                        toward <dir> — right (away from you),
                                        left (toward you), up or down — free,
                                        as far as it fits (GameLoop2.shove)
                  Anything else refuses.
  Type            Melee | Ranged — what kind of weapon it is (blank: Melee).
  Passive         the prose the player reads.
  Passive Effect  that prose in the loot-passive grammar
                  (generate_item_tres.parse_loot_passive); blank for none.
  Goal            written by tools/apply_goals_sheet.py from `goals` — edit it
                  there, never here.
  Charge          charges a swing needs and spends.

  python3 tools/generate_weapon_tres.py            # regenerate every weapon
  python3 tools/generate_weapon_tres.py --list     # print, write nothing
"""

import argparse
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_item_tres as items  # noqa: E402

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "WEAPONS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "weapons2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "weapons")

SIZE_RE = re.compile(r"^\s*(\d+)\s*[xX×]\s*(\d+)\s*$")
AREA_WORDS = {"cell", "row", "col", "column", "cross", "3x3", "5x5", "board", "all",
              "plus", "diagonals"}
AIM_WORDS = {"any", "front", "back", "enemy", "none", "random"}
PUSH_DIRS = ("right", "left", "up", "down")
WEAPON_TYPES = ("melee", "ranged")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def _clean(v):
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def parse_size(raw, name):
    m = SIZE_RE.match(_clean(raw) or "1x1")
    if not m or int(m.group(1)) < 1 or int(m.group(2)) < 1:
        raise ValueError("weapon %r: Size %r is not HxW" % (name, raw))
    return int(m.group(2)), int(m.group(1))


def parse_aim(raw, name):
    text = (_clean(raw) or "any").lower()
    m = re.fullmatch(r"col(?:umn)?\s+(\d+)", text)
    if m:
        return "column", int(m.group(1))
    if text not in AIM_WORDS:
        raise ValueError("weapon %r: Aim %r is not one of any, front, back, "
                         "column N, enemy, none, random" % (name, raw))
    return text, 0


def check_area(raw, name):
    """The Area as authored, refused unless WeaponArea / GameLoop2.area_cells
    can read it. Kept as text: the board it lands on is only known at runtime."""
    text = (_clean(raw) or "cell").strip()
    low = text.lower()
    if low in AREA_WORDS or re.fullmatch(r"\d+x\d+", low):
        if re.fullmatch(r"\d+x\d+", low) and "0" in low.split("x"):
            raise ValueError("weapon %r: Area %r has an empty side" % (name, raw))
        return low
    rows = text.split("/")
    if any(set(r) - set("#.O") for r in rows) or "".join(rows).count("O") != 1:
        raise ValueError("weapon %r: Area %r is not a word, an RxC rectangle, or a "
                         "drawing of # . and exactly one O split by /" % (name, raw))
    return text


def parse_effect(raw, name):
    """(stun, push_dir, push) from `stun N[, push <dir> N]`."""
    stun = None
    push_dir, push = "", 0
    for part in [p.strip() for p in (_clean(raw) or "").lower().split(",") if p.strip()]:
        m = re.fullmatch(r"stun\s+(\d+)", part)
        if m and stun is None:
            stun = int(m.group(1))
            continue
        m = re.fullmatch(r"push\s+(right|left|up|down)\s+(\d+)", part)
        if m and not push:
            push_dir, push = m.group(1), int(m.group(2))
            continue
        raise ValueError("weapon %r: Effect %r — %r is not `stun N` or "
                         "`push right|left|up|down N`" % (name, raw, part))
    if stun is None:
        raise ValueError("weapon %r: Effect %r has no `stun N`" % (name, raw))
    return stun, push_dir, push


def parse_type(raw, name):
    text = (_clean(raw) or "melee").lower()
    if text not in WEAPON_TYPES:
        raise ValueError("weapon %r: Type %r is not Melee or Ranged" % (name, raw))
    return text


def weapon_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    wid = slugify(name)
    rarity = _clean(row.get("Rarity")) or "Common"
    w, h = parse_size(row.get("Size"), name)
    aim, aim_col = parse_aim(row.get("Aim"), name)
    area = check_area(row.get("Area"), name)
    stun, push_dir, push = parse_effect(row.get("Effect"), name)
    wtype = parse_type(row.get("Type"), name)
    passive_text = _clean(row.get("Passive Effect"))
    passive = items.parse_loot_passive(name, passive_text, allow_empty=True)
    if passive["copy_neighbour"] or passive["bank_shields"] or passive["echo_first_loot"]:
        raise ValueError("weapon %r: copy_right / bank_shields / echo_first_loot "
                         "are not weapon passives" % name)
    goal = _clean(row.get("Goal"))
    if not goal:
        raise ValueError("weapon %r has no Goal — it could never charge. Author it "
                         "in `goals` (Owner Sheet `weapon`) and run "
                         "tools/apply_goals_sheet.py" % name)
    charge = _clean(row.get("Charge")) or "3"
    if not re.fullmatch(r"\d+", charge) or int(charge) < 1:
        raise ValueError("weapon %r: Charge %r is not a whole number >= 1" % (name, charge))
    file = _clean(row.get("Image"))
    if file and not os.path.exists(os.path.join(IMG_DIR, file + ".png")):
        raise ValueError("weapon %r: no art at images2.0/weapons/%s.png" % (name, file))
    tags = [t.strip().lower() for t in _clean(row.get("Tag")).split(",") if t.strip()]

    gd = items.gd_value
    lines = [
        '[gd_resource type="Resource" script_class="WeaponData" load_steps=2 '
        'format=3 uid="uid://weapon2_%s"]' % wid,
        "",
        '[ext_resource type="Script" '
        'path="res://scripts/resources/WeaponData.gd" id="1_weapon"]',
        "",
        "[resource]",
        'script = ExtResource("1_weapon")',
        'id = &"%s"' % wid,
        'display_name = "%s"' % items.gd_str(name),
        'rarity = "%s"' % items.gd_str(rarity),
        "size = Vector2i(%d, %d)" % (w, h),
        'aim = "%s"' % aim,
        "aim_column = %d" % aim_col,
        'area = "%s"' % items.gd_str(area),
        "stun = %d" % stun,
        'push_dir = "%s"' % push_dir,
        "push = %d" % push,
        'weapon_type = "%s"' % wtype,
        'goal = "%s"' % items.gd_str(goal),
        "max_charges = %d" % int(charge),
        'description = "%s"' % items.gd_str(_clean(row.get("Passive"))),
        "triggers = %s" % gd(passive["triggers"]),
        "stat_bonuses = %s" % gd(passive["stat_bonuses"]),
        "status_bonuses = %s" % gd(passive["status_bonuses"]),
        "weapon_stun = %s" % gd(passive["weapon_stun"]),
        "stun_per_food = %s" % gd(passive["stun_per_food"]),
        "replay_gain = %s" % gd(passive["replay_gain"]),
        "weapon_retrigger = %s" % gd(passive["weapon_retrigger"]),
        'source_game = "%s"' % items.gd_str(_clean(row.get("Game"))),
        "tags = %s" % items.packed(tags),
        'file = "%s"' % items.gd_str(file),
    ]
    return wid, "\n".join(lines) + "\n"


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if not r or r[0] is None:
            continue
        yield dict(zip(headers, r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in rows(wb["weapons"]):
        wid, text = weapon_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (wid, text))
            continue
        with open(os.path.join(OUT_DIR, wid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(wid)
    if not args.list:
        print("Wrote %d weapon .tres to %s" % (len(written), OUT_DIR))
        for w in written:
            print("  -", w)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate Godot BagData .tres from the `bags` sheet of tools/Roguelikes.xlsx
into data/bags2.0/.

Bags are the SEVENTH loot kind (docs/loot-passives.md §6): pieces of Backpack
Battles inventory that attach to the edge of the 3x3 and add their cells to it.

  bags: Name | Rarity | Size | Description | Effect | Game | Image

`Size` is "HxW" — ROWS FIRST, unrotated — the way the enemies sheet writes a
footprint, and the way the art is painted: the Potion Belt's "4x1" is four tall,
one wide, and its picture stands up. Any rectangle is allowed. The .tres keeps
`size` as Vector2i(columns, rows), so only this parse knows the sheet's order.

`Effect` is authored in the RELIC grammar and compiled by
generate_item_tres.parse_loot_passive, the one implementation shared with
trinkets and passive cards. UNLIKE A TRINKET'S, IT MAY BE BLANK (or N/A): a bag
that only adds room is a whole design, and Leather Bag is one.

  python3 tools/generate_bag2_tres.py            # regenerate every bag
  python3 tools/generate_bag2_tres.py --list     # print, write nothing
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
    "BAGS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "bags2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "bags")

SIZE_RE = re.compile(r"^\s*(\d+)\s*[xX×]\s*(\d+)\s*$")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def _clean(v):
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def parse_size(raw, name):
    text = _clean(raw)
    m = SIZE_RE.match(text)
    if not m:
        raise ValueError("bag %r: Size %r is not HxW" % (name, text))
    h, w = int(m.group(1)), int(m.group(2))
    if w < 1 or h < 1:
        raise ValueError("bag %r: Size %r has no cells" % (name, text))
    return w, h


def bag_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    bid = slugify(name)
    rarity = _clean(row.get("Rarity")) or "Common"
    description = _clean(row.get("Description"))
    effect = _clean(row.get("Effect"))
    passive = items.parse_loot_passive(name, effect) if effect else None
    if passive and (passive["copy_neighbour"] or passive["bank_shields"]
                    or passive["echo_first_loot"]):
        raise ValueError("bag %r: copy_right / bank_shields / echo_first_loot are "
                         "rules about a piece's slot, and a bag has none" % name)
    w, h = parse_size(row.get("Size"), name)
    file = _clean(row.get("Image"))
    if file and not os.path.exists(os.path.join(IMG_DIR, file + ".png")):
        raise ValueError("bag %r: no art at images2.0/bags/%s.png" % (name, file))

    gd = items.gd_value
    lines = [
        '[gd_resource type="Resource" script_class="BagData" load_steps=2 '
        'format=3 uid="uid://bag2_%s"]' % bid,
        "",
        '[ext_resource type="Script" '
        'path="res://scripts/resources/BagData.gd" id="1_bag"]',
        "",
        "[resource]",
        'script = ExtResource("1_bag")',
        'id = &"%s"' % bid,
        'display_name = "%s"' % items.gd_str(name),
        'rarity = "%s"' % items.gd_str(rarity),
        "size = Vector2i(%d, %d)" % (w, h),
        'description = "%s"' % items.gd_str(description),
        'source_game = "%s"' % items.gd_str(_clean(row.get("Game"))),
        'file = "%s"' % items.gd_str(file),
    ]
    if passive:
        lines += [
            "triggers = %s" % gd(passive["triggers"]),
            "stat_bonuses = %s" % gd(passive["stat_bonuses"]),
            "status_bonuses = %s" % gd(passive["status_bonuses"]),
        ]
        if passive["charge_bonus_chance"]:
            lines.append("charge_bonus_chance = %s" % passive["charge_bonus_chance"])
    return bid, "\n".join(lines) + "\n"


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
    for row in rows(wb["bags"]):
        bid, text = bag_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (bid, text))
            continue
        with open(os.path.join(OUT_DIR, bid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(bid)
    if not args.list:
        print("Wrote %d bag .tres to %s" % (len(written), OUT_DIR))
        for b in written:
            print("  -", b)


if __name__ == "__main__":
    main()

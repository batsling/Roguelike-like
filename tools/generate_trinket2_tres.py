#!/usr/bin/env python3
"""Generate Godot TrinketData .tres from the `trinkets` sheet of
tools/Roguelikes.xlsx into data/trinkets2.0/.

Trinkets are the SIXTH loot kind (docs/loot-passives.md): pieces that sit in the
pack and work from there rather than being spent.

  trinkets: Name | Rarity | Size | Description | Effect | Tag | Game | Image

`Effect` is authored in the RELIC grammar (docs/games-first-redesign.md §8.1) and
compiled by generate_item_tres.parse_loot_passive, the one implementation shared
with passive cards — so `gold_gained: 25% chance gain_hp 1` means exactly what it
means on a relic. A blank Effect raises: a trinket's whole pitch is the line on
it, and one that compiles to nothing is an authoring hole, not a design.

`Size` is "WxH". Every row is 1x1 today and the pack places only 1x1 pieces; a
larger one raises here until the pack learns shapes (§6 of the doc), rather than
being generated into a slot it cannot fit.

  python3 tools/generate_trinket2_tres.py            # regenerate every trinket
  python3 tools/generate_trinket2_tres.py --list     # print, write nothing
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
    "TRINKETS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "trinkets2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "trinkets")

SIZE_RE = re.compile(r"^\s*(\d+)\s*[xX×]\s*(\d+)\s*$")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def _clean(v):
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def parse_size(raw, name):
    text = _clean(raw) or "1x1"
    m = SIZE_RE.match(text)
    if not m:
        raise ValueError("trinket %r: Size %r is not WxH" % (name, text))
    w, h = int(m.group(1)), int(m.group(2))
    if (w, h) != (1, 1):
        raise ValueError("trinket %r is %dx%d — the pack only places 1x1 pieces "
                         "so far (docs/loot-passives.md §6)" % (name, w, h))
    return w, h


def trinket_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    tid = slugify(name)
    rarity = _clean(row.get("Rarity")) or "Common"
    description = _clean(row.get("Description"))
    effect = _clean(row.get("Effect"))
    if not effect:
        raise ValueError("trinket %r has no Effect authored" % name)
    passive = items.parse_loot_passive(name, effect)
    w, h = parse_size(row.get("Size"), name)
    file = _clean(row.get("Image"))
    if file and not os.path.exists(os.path.join(IMG_DIR, file + ".png")):
        raise ValueError("trinket %r: no art at images2.0/trinkets/%s.png" % (name, file))
    tags = [t.strip() for t in _clean(row.get("Tag")).split(",") if t.strip()]

    gd = items.gd_value
    lines = [
        '[gd_resource type="Resource" script_class="TrinketData" load_steps=2 '
        'format=3 uid="uid://trinket2_%s"]' % tid,
        "",
        '[ext_resource type="Script" '
        'path="res://scripts/resources/TrinketData.gd" id="1_trinket"]',
        "",
        "[resource]",
        'script = ExtResource("1_trinket")',
        'id = &"%s"' % tid,
        'display_name = "%s"' % items.gd_str(name),
        'rarity = "%s"' % items.gd_str(rarity),
        "size = Vector2i(%d, %d)" % (w, h),
        'description = "%s"' % items.gd_str(description),
        'source_game = "%s"' % items.gd_str(_clean(row.get("Game"))),
        "tags = %s" % items.packed(tags),
        'file = "%s"' % items.gd_str(file),
        "triggers = %s" % gd(passive["triggers"]),
        "stat_bonuses = %s" % gd(passive["stat_bonuses"]),
        "status_bonuses = %s" % gd(passive["status_bonuses"]),
    ]
    if passive["copy_neighbour"]:
        lines.append('copy_neighbour = "%s"' % passive["copy_neighbour"])
    if passive["bank_shields"]:
        lines.append("bank_shields = true")
    if passive["echo_first_loot"]:
        lines.append("echo_first_loot = %d" % passive["echo_first_loot"])
    return tid, "\n".join(lines) + "\n"


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
    for row in rows(wb["trinkets"]):
        tid, text = trinket_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (tid, text))
            continue
        with open(os.path.join(OUT_DIR, tid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(tid)
    if not args.list:
        print("Wrote %d trinket .tres to %s" % (len(written), OUT_DIR))
        for t in written:
            print("  -", t)


if __name__ == "__main__":
    main()

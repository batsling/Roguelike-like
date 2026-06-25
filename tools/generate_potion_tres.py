#!/usr/bin/env python3
"""
Generate Godot PotionData .tres files from the `potions` sheet of
tools/Roguelikes.xlsx.

Mirrors generate_item_tres.py: the spreadsheet is the source of truth and the
.tres are produced by this tool. Each sheet row carries the prose Effect line;
the structured `effects` array that the engine actually applies is authored
here in EFFECT_SPECS, keyed by potion name (the legacy build did the same with
a switch in scrolls-potions.js). Keeping the spec next to the generator means a
new potion is: add the sheet row, add an EFFECT_SPECS entry, rerun.

  python3 tools/generate_potion_tres.py            # regenerate every potion
  python3 tools/generate_potion_tres.py --list     # print the parse, write nothing

Magic-damage potions use damage_type "magic" so they scale with the player's
Arcane (Intelligence) exactly like a magic card — see Stats.resolve_damage.
"""

import argparse
import os
import re
import sys

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "POTIONS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "potions")
POTION_IMG_DIR = os.path.join(PROJECT_ROOT, "images", "potions")

# Structured effects per potion, applied to every affected target by
# PotionSystem.apply_effect. `cleave` widens the thrown AOE. Anything not listed
# here is skipped with a warning so the generator never invents behaviour.
EFFECT_SPECS = {
    "Fire Potion": {
        "effects": [{"op": "damage", "value": 20, "damage_type": "magic", "element": "fire"}],
    },
    "Block Potion": {
        "effects": [{"op": "block", "value": 12}],
    },
    "Energy Potion": {
        "effects": [{"op": "energy", "value": 2}],
    },
    "Weak Potion": {
        "effects": [{"op": "status", "status": "weak", "stacks": 3}],
    },
    "Vulnerable Potion": {
        "effects": [{"op": "status", "status": "vulnerable", "stacks": 3}],
    },
    "Speed Potion": {
        "effects": [{"op": "status", "status": "defense", "stacks": 5, "temp": True}],
    },
    "Flex Potion": {
        "effects": [{"op": "status", "status": "power", "stacks": 5, "temp": True}],
    },
    "Fruit Juice": {
        "effects": [{"op": "maxhp", "value": 5}],
    },
    "Dexterity Potion": {
        "effects": [{"op": "status", "status": "defense", "stacks": 2}],
    },
    "Strength Potion": {
        "effects": [{"op": "status", "status": "power", "stacks": 2}],
    },
    "Explosive Ampoule": {
        "effects": [{"op": "damage", "value": 10, "damage_type": "magic", "element": "fire"}],
        "cleave": True,
    },
    "Liquid Bronze": {
        "effects": [{"op": "status", "status": "thorns", "stacks": 3}],
    },
}


def slugify(name: str) -> str:
    s = name.strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def gd_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return '"%s"' % gd_str(v)
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (gd_str(k), gd_value(val)) for k, val in v.items()) + "}"
    raise TypeError(type(v))


def read_rows():
    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    ws = wb["potions"]
    rows = list(ws.iter_rows(values_only=True))
    header = [str(c).strip() if c is not None else "" for c in rows[0]]
    out = []
    for raw in rows[1:]:
        if raw is None or all(c is None for c in raw):
            continue
        row = {header[i]: raw[i] for i in range(len(header))}
        if not str(row.get("Name") or "").strip():
            continue
        out.append(row)
    return out


def potion_tres(row):
    name = str(row["Name"]).strip()
    iid = slugify(name)
    rarity = str(row.get("Rarity") or "Common").strip()
    reference = str(row.get("Reference") or "").strip()
    effect_text = str(row.get("Effect") or "").strip()
    img_file = str(row.get("File") or "").strip() or name.replace(" ", "").replace("'", "")

    spec = EFFECT_SPECS.get(name)
    if spec is None:
        print("  ! no EFFECT_SPECS for '%s' — skipping" % name, file=sys.stderr)
        return None
    effects = spec["effects"]
    cleave = bool(spec.get("cleave", False))

    img_res = None
    if os.path.exists(os.path.join(POTION_IMG_DIR, img_file + ".png")):
        img_res = "res://images/potions/%s.png" % img_file

    lines = []
    load_steps = 3 if img_res else 2
    lines.append('[gd_resource type="Resource" script_class="PotionData" load_steps=%d '
                 'format=3 uid="uid://potion_%s"]' % (load_steps, iid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/PotionData.gd" id="1_potion"]')
    if img_res:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img_res)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_potion")')
    lines.append('id = &"%s"' % iid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('rarity = "%s"' % gd_str(rarity))
    lines.append('reference = "%s"' % gd_str(reference))
    lines.append('file = "%s"' % gd_str(img_file))
    lines.append('effect_text = "%s"' % gd_str(effect_text))
    lines.append("effects = %s" % gd_value(effects))
    if cleave:
        lines.append("cleave = true")
    return iid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print the parse, write nothing")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in read_rows():
        res = potion_tres(row)
        if res is None:
            continue
        iid, text = res
        if args.list:
            print("=== %s ===" % iid)
            print(text)
            continue
        with open(os.path.join(OUT_DIR, iid + ".tres"), "w", encoding="utf-8") as fh:
            fh.write(text)
        written.append(iid)
    if not args.list:
        print("Wrote %d potion .tres to %s" % (len(written), OUT_DIR))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate Godot EvolutionData .tres from the `evolutions` sheet of
tools/Roguelikes.xlsx into data/evolutions2.0/ (docs/loot-passives.md §13).

  evolutions: Name | Requirement 1 | Requirement 2 | Outcome

  Name           the weapon it makes (a row of `weapons`)
  Requirement 1  the weapon that evolves (a row of `weapons`); it always turns
  Requirement 2  Any [N] Item(s) or Trinket(s) with "<tag>"
                 — or the NAME of one item or trinket (Thunder Loop's
                 `Duplicator`), checked against `items` and `trinkets`
  Outcome        Consume All  — the N tagged things are used up
                 Consume None — they are kept

Both weapon names are checked against the `weapons` sheet, so a typo is a
refusal here rather than an Evolve button that never lights.

  python3 tools/generate_evolution_tres.py            # regenerate
  python3 tools/generate_evolution_tres.py --list     # print, write nothing
"""

import argparse
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_item_tres as items  # noqa: E402
from generate_weapon_tres import slugify, rows, _clean  # noqa: E402

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "EVOLUTIONS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "evolutions2.0")

NEED_RE = re.compile(
    r'^any\s+(?:(\d+)\s+)?items?\s+or\s+trinkets?\s+with\s+["“”]([^"“”]+)["“”]$',
    re.I)
OUTCOMES = {"consume all": True, "consume none": False}


def parse_need(name, need, things):
    """(count, tag, need_id) for Requirement 2: a tag phrase, or one thing by name."""
    m = NEED_RE.match(need)
    if m:
        return int(m.group(1) or 1), m.group(2).strip().lower(), ""
    if slugify(need) in things:
        return 1, "", slugify(need)
    raise ValueError('evolution %r: Requirement 2 %r is not `Any [N] Item(s) or '
                     'Trinket(s) with "<tag>"`, nor the name of a row of `items` '
                     'or `trinkets`' % (name, need))


def evolution_tres(row, weapons, things=frozenset()) -> tuple:
    name = str(row["Name"]).strip()
    result = slugify(name)
    base_name = _clean(row.get("Requirement 1"))
    base = slugify(base_name)
    for label, wid, raw in (("Name", result, name), ("Requirement 1", base, base_name)):
        if wid not in weapons:
            raise ValueError("evolution %r: %s %r is not a row of `weapons`"
                             % (name, label, raw))
    need = _clean(row.get("Requirement 2"))
    count, tag, need_id = parse_need(name, need, things)
    outcome = (_clean(row.get("Outcome")) or "").lower()
    if outcome not in OUTCOMES:
        raise ValueError("evolution %r: Outcome %r is not Consume All or Consume None"
                         % (name, row.get("Outcome")))
    lines = [
        '[gd_resource type="Resource" script_class="EvolutionData" load_steps=2 '
        'format=3 uid="uid://evolution2_%s"]' % result,
        "",
        '[ext_resource type="Script" '
        'path="res://scripts/resources/EvolutionData.gd" id="1_evolution"]',
        "",
        "[resource]",
        'script = ExtResource("1_evolution")',
        'id = &"%s"' % result,
        'result = &"%s"' % result,
        'base = &"%s"' % base,
        "need_count = %d" % count,
        'need_tag = "%s"' % items.gd_str(tag),
        'need_id = &"%s"' % need_id,
        "consumes = %s" % ("true" if OUTCOMES[outcome] else "false"),
    ]
    return result, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    weapons = {slugify(r["Name"]) for r in rows(wb["weapons"])}
    things = {slugify(r["Name"]) for r in rows(wb["items"])} \
        | {slugify(r["Name"]) for r in rows(wb["trinkets"])}
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in rows(wb["evolutions"]):
        eid, text = evolution_tres(row, weapons, things)
        if args.list:
            print("=== %s ===\n%s" % (eid, text))
            continue
        with open(os.path.join(OUT_DIR, eid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(eid)
    if not args.list:
        print("Wrote %d evolution .tres to %s" % (len(written), OUT_DIR))
        for e in written:
            print("  -", e)


if __name__ == "__main__":
    main()

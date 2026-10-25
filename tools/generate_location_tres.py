#!/usr/bin/env python3
"""
Generate Godot LocationData .tres from the `locations` sheet of
tools/Roguelikes.xlsx into data/locations/ (docs/locations-design.md).

  locations: Name | Game | Difficulty | Description | Effect | Tag Type |
             Tag % Up | Img

  Name         the location's name. Required.
  Game         the game it comes from, as written (display only).
  Difficulty   1-Low, 2-Medium, 3-High or 4-Insane: the tier it is dealt at.
  Description  the owner's words, shown on the arrival popup and the hover card.
  Effect       what it does, in the grammar below.
  Tag Type     comma-separated tags the location leans toward (`fire`,
               `poop, stinky`). Blank: no lean.
  Tag % Up     how much a tagged thing's weight goes up in any roll, as a
               fraction (0.2 is +20%). Blank: 0.
  Img          art base name under images2.0/locations/ (no extension).

EFFECT GRAMMAR — semicolon-separated clauses, each under the header before it:

  arrive: <effect>[; …]        once, the moment the location is dealt
    spawn_enemy <tag> <n>      n random bodies of that tag walk on (the run's
                               tier, widening the way a curse's conjure does)
    place_tile <tile> <n>      that tile effect on n random empty squares
    place_unit <tag> <n> [favour=<unit>:<pct>]
                               n random units of that tag on random empty
                               squares; `favour` makes one of them pct% of the
                               draw and shares the rest between the others
    <anything an item's Effect column can say>
                               handed to the item grammar (item_dsl.py)
                               and run through EffectSystem — `gain_stat bombs 2`,
                               `apply_status burn 1`, `add_curse injury`,
                               `gain_loot 2`… — so a location can do whatever
                               an item already can, with no new code

  while: <rule>[; …]           true for as long as the run is there
    damage_taken_mult <x>      every hit that lands on you is worth x times
    offering_rift <n>          n cards of every offering are a free rift card
    push_mult <n>              every push and shove goes n times as far

  action <limit>: <cost> => <pay>
                               a button on the location card, usable up to
                               <limit> times while the run is there
    cost: lose_max_hp <n> | spend <stat> <n>   (stat: keys, bombs, gold, …)
    pay:  gain_chest <size> [<tag>]            small / medium / large / huge;
                               a tag makes it a chest only things carrying that
                               tag can come out of — or any item-grammar effect

The output folder is REWRITTEN, not added to: a row deleted from the sheet takes
its location with it. Its README.md is left alone.

  python3 tools/generate_location_tres.py           # write data/locations/*.tres
  python3 tools/generate_location_tres.py --list    # print the parse, write nothing
"""

import argparse
import glob
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_tile_tres as base  # noqa: E402  (slugify, gd_str, gd_value, _clean)
import item_dsl as items  # noqa: E402  (parse_one_effect: the item grammar)

PROJECT_ROOT = base.PROJECT_ROOT
XLSX_PATH = base.XLSX_PATH
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "locations")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "locations")
IMG_RES_PREFIX = "res://images2.0/locations/"

TIERS = {"low": 0, "medium": 1, "high": 2, "insane": 3}
CHEST_SIZES = {"small": 0, "medium": 1, "large": 2, "huge": 3}
# What `spend` may take: GameState's own counters.
SPEND_STATS = ("keys", "bombs", "gold", "bash", "dash", "transmute", "scramble",
               "push", "shields", "bonus_shields")
REQUIRED = ("Name", "Difficulty", "Description", "Effect", "Tag Type", "Tag % Up", "Img")


def _ids(folder: str) -> set:
    return {os.path.splitext(os.path.basename(p))[0]
            for p in glob.glob(os.path.join(PROJECT_ROOT, "data", folder, "*.tres"))}


def _unit_tags() -> set:
    out = set()
    for p in glob.glob(os.path.join(PROJECT_ROOT, "data", "units2.0", "*.tres")):
        m = re.search(r'^tags = PackedStringArray\((.*)\)$', open(p, encoding="utf-8").read(), re.M)
        if m:
            out.update(t.strip().strip('"') for t in m.group(1).split(",") if t.strip())
    return out


def parse_tier(cell, what: str) -> int:
    raw = base._clean(cell).lower()
    m = re.match(r"^\d*\s*-?\s*([a-z]+)$", raw)
    if not m or m.group(1) not in TIERS:
        raise ValueError("%s: Difficulty %r is not Low / Medium / High / Insane" % (what, cell))
    return TIERS[m.group(1)]


def parse_arrive(clause: str, what: str) -> dict:
    words = clause.split()
    op = words[0].lower() if words else ""
    if op == "spawn_enemy" and len(words) == 3:
        return {"op": op, "tag": words[1].lower(), "count": int(words[2])}
    if op == "place_tile" and len(words) == 3:
        tile = words[1].lower()
        if tile not in _ids("tiles2.0"):
            raise ValueError("%s: place_tile names %r, which is not a tile" % (what, tile))
        return {"op": op, "tile": tile, "count": int(words[2])}
    if op == "place_unit" and len(words) in (3, 4):
        tag = words[1].lower()
        if tag not in _unit_tags():
            raise ValueError("%s: place_unit names tag %r, which no unit carries" % (what, tag))
        out = {"op": op, "tag": tag, "count": int(words[2])}
        if len(words) == 4:
            m = re.match(r"^favour=([a-z_]+):(\d+)$", words[3].lower())
            if not m:
                raise ValueError("%s: cannot read %r — write favour=<unit>:<pct>" % (what, words[3]))
            if m.group(1) not in _ids("units2.0"):
                raise ValueError("%s: favour names %r, which is not a unit" % (what, m.group(1)))
            out["favour"] = m.group(1)
            out["favour_pct"] = int(m.group(2))
        return out
    return {"op": "effect", "effect": item_effect(clause, what)}


def item_effect(clause: str, what: str) -> dict:
    """Anything else, read by the item grammar: an EffectSystem effect dict."""
    got = items.parse_one_effect(clause)
    if not isinstance(got, dict) or not got.get("type"):
        raise ValueError("%s: %r is neither a location effect nor something the "
                         "item grammar can read" % (what, clause))
    return got


def parse_standing(clause: str, what: str) -> dict:
    words = clause.split()
    op = words[0].lower() if words else ""
    if op == "damage_taken_mult" and len(words) == 2:
        return {"op": op, "value": float(words[1].lstrip("x"))}
    if op == "offering_rift" and len(words) == 2:
        return {"op": op, "value": int(words[1])}
    if op == "push_mult" and len(words) == 2:
        return {"op": op, "value": int(float(words[1].lstrip("x")))}
    raise ValueError("%s: unknown while rule %r" % (what, clause))


def parse_action(limit: int, clause: str, what: str) -> dict:
    cost_s, sep, pay_s = clause.partition("=>")
    if not sep:
        raise ValueError("%s: an action is `<cost> => <pay>`, got %r" % (what, clause))
    cw = cost_s.split()
    if len(cw) == 2 and cw[0].lower() == "lose_max_hp":
        cost = {"op": "lose_max_hp", "value": int(cw[1])}
    elif len(cw) == 3 and cw[0].lower() == "spend" and cw[1].lower() in SPEND_STATS:
        cost = {"op": "spend", "stat": cw[1].lower(), "value": int(cw[2])}
    else:
        raise ValueError("%s: cannot read the action's cost %r" % (what, cost_s.strip()))
    pw = pay_s.split()
    if len(pw) in (2, 3) and pw[0].lower() == "gain_chest" and pw[1].lower() in CHEST_SIZES:
        pay = {"op": "gain_chest", "size": CHEST_SIZES[pw[1].lower()]}
        if len(pw) == 3:
            pay["pool"] = pw[2].lower()
    else:
        pay = {"op": "effect", "effect": item_effect(pay_s.strip(), what)}
    return {"limit": max(1, limit), "cost": cost, "pay": pay}


def parse_effect(cell, what: str):
    """`Effect` -> (arrive, standing, actions)."""
    arrive, standing, actions = [], [], []
    current = None
    for clause in [c.strip() for c in base._clean(cell).split(";") if c.strip()]:
        head, sep, payload = clause.partition(":")
        h = head.strip().lower()
        if sep and (h in ("arrive", "while") or re.match(r"^action(\s+\d+)?$", h)):
            current = h
            clause = payload.strip()
            if not clause:
                continue
        if current is None:
            raise ValueError("%s: %r has no header — write `arrive:`, `while:` or "
                             "`action N:`" % (what, clause))
        if current == "arrive":
            arrive.append(parse_arrive(clause, what))
        elif current == "while":
            standing.append(parse_standing(clause, what))
        else:
            n = re.search(r"\d+", current)
            actions.append(parse_action(int(n.group(0)) if n else 1, clause, what))
    return arrive, standing, actions


def location_tres(row: dict):
    name = base._clean(row.get("Name"))
    lid = base.slugify(name)
    what = "locations %s" % name
    tier = parse_tier(row.get("Difficulty"), what)
    arrive, standing, actions = parse_effect(row.get("Effect"), what)
    if not (arrive or standing or actions):
        raise ValueError("%s: the Effect column is empty — a location that does "
                         "nothing is not content" % what)
    tags = [t.strip().lower() for t in base._clean(row.get("Tag Type")).split(",") if t.strip()]
    up_raw = base._clean(row.get("Tag % Up"))
    try:
        up = float(up_raw.rstrip("%")) if up_raw else 0.0
    except ValueError:
        raise ValueError("%s: Tag %% Up %r is not a number" % (what, up_raw))
    if up_raw.endswith("%") or up > 5:
        up = up / 100.0          # "20%" or 20 both mean +20%
    file = base._clean(row.get("Img"))
    img = base.image_path(file, IMG_DIR, IMG_RES_PREFIX)

    lines = [
        '[gd_resource type="Resource" script_class="LocationData" load_steps=2 '
        'format=3 uid="uid://location_%s"]' % lid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/LocationData.gd" id="1_loc"]',
        "",
        "[resource]",
        'script = ExtResource("1_loc")',
        'id = &"%s"' % lid,
        'display_name = "%s"' % base.gd_str(name),
        'game = "%s"' % base.gd_str(base._clean(row.get("Game"))),
        "tier = %d" % tier,
        'description = "%s"' % base.gd_str(base._clean(row.get("Description"))),
        "arrive = %s" % base.gd_value(arrive),
        "standing = %s" % base.gd_value(standing),
        "actions = %s" % base.gd_value(actions),
        "tag_types = PackedStringArray(%s)" % ", ".join('"%s"' % base.gd_str(t) for t in tags),
        "tag_up = %s" % repr(round(up, 4)),
        'file = "%s"' % base.gd_str(file),
        'image_path = "%s"' % img,
    ]
    return lid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    sheet = wb["locations"]
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for needed in REQUIRED:
        if needed not in headers:
            raise SystemExit("locations has no %r column" % needed)
    built = []
    for r in sheet.iter_rows(min_row=2, values_only=True):
        row = dict(zip(headers, r))
        if not base._clean(row.get("Name")):
            continue
        built.append(location_tres(row))
    if args.list:
        for lid, text in built:
            print("=== %s ===\n%s" % (lid, text))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    for old in glob.glob(os.path.join(OUT_DIR, "*.tres")):
        os.remove(old)
    for lid, text in built:
        with open(os.path.join(OUT_DIR, lid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
    print("Wrote %d locations .tres to %s" % (len(built), OUT_DIR))
    for lid, _ in built:
        print("  -", lid)


if __name__ == "__main__":
    main()

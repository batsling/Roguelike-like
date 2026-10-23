#!/usr/bin/env python3
"""
Generate Godot UnitData .tres for the games-first redesign's UNITS, from the
`units2.0` sheet of tools/Roguelikes.xlsx into data/units2.0/.

A unit (docs/games-first-redesign.md §17) is a body of the PLAYER's standing on
one cell of the battlefield — the counterpart to a tile effect, which is something
done to the ground under it. They layer, and what happens when a particular pair
meets is authored in the two sheets' `Interactions` columns rather than anywhere
in code.

  units: Name | Type | Description | Effect | Interactions | On Destruction |
         Health | Tag | Img

The Effect and Interactions DSLs are the TILE sheet's, unchanged and imported
rather than restated — a unit and a tile effect react to the same board and the
same events, so a second grammar for the same two triggers would only be a second
thing to keep in step. See tools/generate_tile_tres.py for the full grammar; the
one verb units use that tiles do not is:

  detonate    go off where you stand, as a PROXY BOMB

`detonate` spends none of the player's Bombs, but everything that modifies a bomb
modifies it — Brimstone widens the blast, Sticky stuns what survives it, Blood
Bombs pays its Health, Hot Bombs leaves Fire behind. That is the whole reason the
Landmine is a unit rather than a one-off trap: it is worth exactly what the pack
has made bombs worth.

BLOCK is the one bare word the Effect column takes that is not a trigger. A
blocking unit is a WALL rather than a toll (docs/locations-design.md §5): no
body can step onto its cell, and a body whose step it stops strikes it instead,
for 1 — so both sides can break it, the player with anything that damages the
ground. The poops Dross lays are the first. `block` may stand alone, or before
the triggers (`block; damaged: detonate`).

ON DESTRUCTION is what a unit leaves behind when its Health runs out, in prose
the owner writes and this reads:

  50% Random Loot, 50% Random fly tagged Enemy
  50% 2 Gold, 30% 3 Gold, 10% 4 Gold, 5% 5 Gold, 5% Counterfeit Penny
  Gain +3 Health

Comma-separated. Parts that carry a `N%` are ONE weighted draw between them (they
must add up to 100); a part with no percentage always happens. Each outcome is
one of:

  Random Loot                    -> {op: loot}            a piece, on that square
  Random <tag> tagged Enemy      -> {op: spawn_enemy, tag}
  N Gold                         -> {op: gold, value}
  Gain +N Health                 -> {op: heal, value}
  <a loot piece's name>          -> {op: give, kind, id}  that piece, on that square

`Tag` is what the unit is (`poop`), for anything that picks units by tag — a
location laying "2 random poop-tagged units" — and for the tag boost a location
gives (docs/locations-design.md §4).

`Type` ("Inanimate") is carried through without being dispatched on. It is there
so an Animate unit that takes a turn of its own can arrive without a migration.

Art: Img -> res://images2.0/units/<Img>.png, referenced eagerly.

  python3 tools/generate_unit_tres.py           # regenerate every unit
  python3 tools/generate_unit_tres.py --list    # print the parse, write nothing
"""

import os
import re

import generate_tile_tres as base

PROJECT_ROOT = base.PROJECT_ROOT
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "units2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "units")
IMG_RES_PREFIX = "res://images2.0/units/"


# The loot folders a named On Destruction piece is looked for in, and the kind
# each one is in a pack entry.
LOOT_FOLDERS = (("trinkets2.0", "trinket"), ("scrolls2.0", "scroll"),
                ("potions2.0", "potion"), ("pills2.0", "pill"), ("cards2.0", "card"),
                ("wands2.0", "wand"), ("weapons2.0", "weapon"), ("bags2.0", "bag"))


def split_block(cell, what: str):
    """`Effect` -> (blocks, the rest for the tile grammar)."""
    raw = base._clean(cell)
    blocks = False
    kept = []
    for clause in [c.strip() for c in raw.split(";") if c.strip()]:
        if clause.lower() == "block" and not kept:
            blocks = True
            continue
        kept.append(clause)
    return blocks, "; ".join(kept)


def parse_outcome(text: str, what: str) -> dict:
    low = text.strip().lower()
    if low == "random loot":
        return {"op": "loot"}
    m = re.match(r"^random\s+([a-z_]+)\s+tagged\s+enemy$", low)
    if m:
        return {"op": "spawn_enemy", "tag": m.group(1)}
    m = re.match(r"^(\d+)\s+gold$", low)
    if m:
        return {"op": "gold", "value": int(m.group(1))}
    m = re.match(r"^gain\s+\+?(\d+)\s+health$", low)
    if m:
        return {"op": "heal", "value": int(m.group(1))}
    slug = base.slugify(text)
    for folder, kind in LOOT_FOLDERS:
        if os.path.exists(os.path.join(PROJECT_ROOT, "data", folder, slug + ".tres")):
            return {"op": "give", "kind": kind, "id": slug}
    raise ValueError("%s: cannot read On Destruction outcome %r" % (what, text))


def parse_destruction(cell, what: str) -> dict:
    """`On Destruction` -> {"always": [outcome…], "one_of": [{chance, …}…]}."""
    raw = base._clean(cell)
    always, one_of = [], []
    if not raw:
        return {"always": always, "one_of": one_of}
    for part in [p.strip() for p in raw.split(",") if p.strip()]:
        m = re.match(r"^(\d+(?:\.\d+)?)\s*%\s*(.+)$", part)
        if m:
            row = parse_outcome(m.group(2), what)
            row["chance"] = float(m.group(1))
            one_of.append(row)
        else:
            always.append(parse_outcome(part, what))
    total = sum(r["chance"] for r in one_of)
    if one_of and abs(total - 100.0) > 0.01:
        raise ValueError("%s: On Destruction's chances add up to %s%%, not 100%%"
                         % (what, total))
    return {"always": always, "one_of": one_of}


def unit_tres(row: dict):
    name = str(row.get("Name") or "").strip()
    uid = base.slugify(name)
    what = "units %s" % name
    blocks, effect = split_block(row.get("Effect"), what)
    triggers = base.parse_effect(effect, what)
    if not triggers and not blocks:
        raise ValueError("%s: the Effect column is empty — a unit that does "
                         "nothing is not content" % what)
    destruction = parse_destruction(row.get("On Destruction"), what)
    tags = [t.strip().lower() for t in base._clean(row.get("Tag")).split(",") if t.strip()]
    interactions = base.parse_interactions(row.get("Interactions"), what)
    health = row.get("Health")
    try:
        health = max(1, int(float(health)))
    except (TypeError, ValueError):
        raise ValueError("%s: Health %r is not a number" % (what, health))
    file = base._clean(row.get("Img"))
    img = base.image_path(file, IMG_DIR, IMG_RES_PREFIX)

    steps = 3 if img else 2
    lines = []
    lines.append('[gd_resource type="Resource" script_class="UnitData" load_steps=%d '
                 'format=3 uid="uid://unit2_%s"]' % (steps, uid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/UnitData.gd" id="1_unit"]')
    if img:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_unit")')
    lines.append('id = &"%s"' % uid)
    lines.append('display_name = "%s"' % base.gd_str(name))
    lines.append('unit_type = "%s"' % base.gd_str(base._clean(row.get("Type")) or "Inanimate"))
    lines.append('description = "%s"' % base.gd_str(base._clean(row.get("Description"))))
    lines.append("health = %d" % health)
    lines.append("blocks = %s" % ("true" if blocks else "false"))
    lines.append("triggers = %s" % base.gd_value(triggers))
    lines.append("on_destruction = %s" % base.gd_value(destruction))
    lines.append("tags = PackedStringArray(%s)" % ", ".join('"%s"' % base.gd_str(t) for t in tags))
    lines.append("interactions = %s" % base.gd_value(interactions))
    lines.append('file = "%s"' % base.gd_str(file))
    if img:
        lines.append('image = ExtResource("2_img")')
    return uid, "\n".join(lines) + "\n"


def main():
    base.generate("units", OUT_DIR,
                  ("Name", "Type", "Description", "Effect", "Interactions",
                   "Health", "Img"),
                  unit_tres, "units2.0")


if __name__ == "__main__":
    main()

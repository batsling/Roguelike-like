#!/usr/bin/env python3
"""
Generate Godot UnitData .tres for the games-first redesign's UNITS, from the
`units2.0` sheet of tools/Roguelikes.xlsx into data/units2.0/.

A unit (docs/games-first-redesign.md §17) is a body of the PLAYER's standing on
one cell of the battlefield — the counterpart to a tile effect, which is something
done to the ground under it. They layer, and what happens when a particular pair
meets is authored in the two sheets' `Interactions` columns rather than anywhere
in code.

  units2.0: Name | Type | Description | Effect | Interactions | Health | Img

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

`Type` ("Inanimate") is carried through without being dispatched on. It is there
so an Animate unit that takes a turn of its own can arrive without a migration.

Art: Img -> res://images2.0/units/<Img>.png, referenced eagerly.

  python3 tools/generate_unit_tres.py           # regenerate every unit
  python3 tools/generate_unit_tres.py --list    # print the parse, write nothing
"""

import os

import generate_tile_tres as base

PROJECT_ROOT = base.PROJECT_ROOT
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "units2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "units")
IMG_RES_PREFIX = "res://images2.0/units/"


def unit_tres(row: dict):
    name = str(row.get("Name") or "").strip()
    uid = base.slugify(name)
    what = "units2.0 %s" % name
    triggers = base.parse_effect(row.get("Effect"), what)
    if not triggers:
        raise ValueError("%s: the Effect column is empty — a unit that does "
                         "nothing is not content" % what)
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
    lines.append("triggers = %s" % base.gd_value(triggers))
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

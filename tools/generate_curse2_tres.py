#!/usr/bin/env python3
"""
Generate CURSE CARDS — Godot CardData .tres — from the `curses` sheet of
tools/Roguelikes.xlsx into data/curses2.0/.

A curse is a CARD since 14 Nov 2026 (the owner: "get rid of curse goals. These
curses will now count as cards"). It sits in a cell of the pack like a passive
card, is placed through the loot modal the moment it arrives, can never be binned
or left behind, and is never in the ordinary loot drop: only something that hands
out a curse by name (`add_curse injury`) or at random (`add_curse random`) can
put one in the pack. See docs/loot-passives.md §18.

  curses: Curse | Type | Game | Description | Effect | Keywords | Tag | Image

  Type         what KIND of curse the row is. `Card` is the only kind with rows:
               a curse is also a cursed weapon (Retro Bat's unidentified
               weapons, WeaponSystem.is_cursed), but that is a weapon's roll,
               not a row here. Any other Type is refused until something reads it.
  Description  what the curse does while carried, in words. Blank is fine: the
               card's line is COMPOSED here from its keywords, so it says
               "Can't be thrown away" etc. without anyone having to type it.
  Effect       what it does while carried, in the PASSIVE CARD grammar (the
               relic grammar, compiled by item_dsl.parse_loot_passive — the same
               as a `Passive` row of `cards`). Blank means it only takes up
               space, which is what the first three curses do. Blueprint copies
               a curse's effect exactly as it copies any other passive piece.
  Keywords     comma-separated, from KEYWORDS below (the owner's two):
                 Unmovable  it can't be moved — locked in the cell it was placed
                            in, and the bag holding that cell stays put too
                            (Poor Sleep).
                 Eternal    it can't be destroyed — by the Scroll of Remove
                            Curse, a card that destroys loot, anything (Curse of
                            the Bell).
               The player can never bin a curse either way.
  Tag          `random` puts the curse in the random deals (an event's
               `add_curse random`, the Hexer, Amnesia). A blank Tag keeps a curse
               out of them: it only arrives when something names it.
  Image        art base name under images2.0/curses/.

  python3 tools/generate_curse2_tres.py           # write data/curses2.0/*.tres
  python3 tools/generate_curse2_tres.py --list    # print, write nothing
"""

import argparse
import os
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_status_tres as dsl  # noqa: E402  (slugify, gd_str, gd_value, rows)
import item_dsl as items  # noqa: E402  (the passive card grammar)

PROJECT_ROOT = dsl.PROJECT_ROOT
XLSX_PATH = dsl.XLSX_PATH
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "curses2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "curses")
IMG_RES_PREFIX = "res://images2.0/curses/"
SHEET = "curses"

# The kinds of curse a row can be, as the sheet spells them.
TYPES = ("Card",)

# A curse card's keywords, and the rule each one says on the card.
KEYWORDS = {
    "Unmovable": "can't be moved",
    "Eternal": "can't be destroyed",
}


def _keywords(raw, name: str) -> list:
    out = []
    for word in dsl._clean(raw).split(","):
        word = word.strip()
        if not word:
            continue
        match = [k for k in KEYWORDS if k.lower() == word.lower()]
        if not match:
            raise ValueError("curses %s: keyword %r is not one of %s"
                             % (name, word, ", ".join(KEYWORDS)))
        if match[0] not in out:
            out.append(match[0])
    return out


# The Tag column: comma-separated, lower-cased.
def _tags(raw) -> list:
    text = dsl._clean(raw)
    return [t.strip().lower() for t in text.split(",") if t.strip()] if text else []


# What the card says, composed from what it does so the line can never claim a
# rule the card does not have. The authored Description (if any) leads, then each
# keyword with its rule: "Eternal: can't be destroyed."
def card_text(description: str, keywords: list) -> str:
    parts = [description.strip() if description.strip() else "Takes up a slot."]
    parts.append("Can't be thrown away.")
    for k in keywords:
        parts.append("%s: %s." % (k, KEYWORDS[k]))
    return " ".join(parts)


def curse_tres(row) -> tuple:
    name = str(row["Curse"]).strip()
    cid = dsl.slugify(name)
    kind = dsl._clean(row.get("Type")) or "Card"
    if kind.capitalize() not in TYPES:
        raise ValueError("curses %s: Type %r is not one of %s — a cursed weapon is a "
                         "weapon's roll, not a row" % (name, kind, ", ".join(TYPES)))
    keywords = _keywords(row.get("Keywords"), name)
    movable = "Unmovable" not in keywords
    destroyable = "Eternal" not in keywords
    effect = dsl._clean(row.get("Effect"))
    passive = items.parse_loot_passive(name, effect) if effect else None
    if passive is not None and passive["harmless_statuses"]:
        raise ValueError("curses %s: harmless_status is a trinket's rule "
                         "(docs/loot-passives.md §17)" % name)
    description = card_text(dsl._clean(row.get("Description")), keywords)
    tags = ["curse"] + [t for t in _tags(row.get("Tag")) if t != "curse"]

    lines = [
        '[gd_resource type="Resource" script_class="CardData" load_steps=2 '
        'format=3 uid="uid://curse2_%s"]' % cid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/CardData.gd" '
        'id="1_card"]',
        "",
        "[resource]",
        'script = ExtResource("1_card")',
        'id = &"%s"' % cid,
        'display_name = "%s"' % dsl.gd_str(name),
        'rarity = "Curse"',
        'source_game = "%s"' % dsl.gd_str(dsl._clean(row.get("Game"))),
        'description = "%s"' % dsl.gd_str(description),
        'file = "%s"' % dsl.gd_str(dsl._clean(row.get("Image"))),
        'art_folder = "curses"',
        'loot_type = "Curse"',
        "tags = PackedStringArray(%s)" % ", ".join('"%s"' % dsl.gd_str(t) for t in tags),
        # Never spent: a curse works (or does nothing) from its cell.
        "passive = true",
        "keywords = PackedStringArray(%s)" % ", ".join('"%s"' % k for k in keywords),
        "movable = %s" % ("true" if movable else "false"),
        "destroyable = %s" % ("true" if destroyable else "false"),
    ]
    if passive is not None:
        lines.append("triggers = %s" % dsl.gd_value(passive["triggers"]))
        lines.append("stat_bonuses = %s" % dsl.gd_value(passive["stat_bonuses"]))
        lines.append("status_bonuses = %s" % dsl.gd_value(passive["status_bonuses"]))
        if passive["copy_neighbour"]:
            lines.append('copy_neighbour = "%s"' % dsl.gd_str(passive["copy_neighbour"]))
        if passive["bank_shields"]:
            lines.append("bank_shields = true")
        if passive["echo_first_loot"]:
            lines.append("echo_first_loot = %d" % passive["echo_first_loot"])
    return cid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet" % (XLSX_PATH, SHEET))
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in dsl.rows(wb[SHEET]):
        cid, text = curse_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (cid, text))
            continue
        with open(os.path.join(OUT_DIR, cid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(cid)
        art = os.path.join(IMG_DIR, dsl._clean(row.get("Image")) + ".png")
        if dsl._clean(row.get("Image")) and not os.path.exists(art):
            print("  ! %s: no art at %s%s.png" % (cid, IMG_RES_PREFIX,
                                                  dsl._clean(row.get("Image"))))
    if not args.list:
        print("Wrote %d curse card .tres to %s" % (len(written), OUT_DIR))
        for c in written:
            print("  -", c)


if __name__ == "__main__":
    main()

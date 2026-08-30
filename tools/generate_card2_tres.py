#!/usr/bin/env python3
"""Generate Godot CardData .tres for the games-first (2.0) cards, from the
`cards` sheet of tools/Roguelikes.xlsx into data/cards2.0/.

Cards are the FOURTH loot consumable (docs/cards-design.md), and the only one
that is not a gamble: one use, one effect, printed on the face. So this generator
parses ONE effect column and no Preference — there is nothing to hint at.

  cards: Name | Rarity | Description | Effect | Image | Icon Image

`Image` is the card's FACE, drawn once it is in the pack; `Icon Image` is its
BACK, drawn while it is lying on the floor, and shared by every card of a set.
The back is also where the credit comes from: the five icon files spell out the
game and the deck ("Isaac_Major_Arcana"), so `source_game` and `set_name` are
read off it rather than authored twice.

Effect token DSL (semicolons separate clauses, as in every other sheet):

    gain_hp <n>                 -> {op:gain_hp, value:n}
    gain_hp <lo>-<hi>           -> {op:gain_hp, min:lo, max:hi}
    gain_stat <stat> <n>        -> {op:gain_stat, stat, value:n}
    double_stat <what> [floor=<n>]
                                -> {op:double_stat, stat, floor?}
    gain_loot <kind> <n>        -> {op:gain_loot, kind, count:n}
    teleport_type <game_type>   -> {op:teleport_type, game_type}
    teleport_hub                -> {op:teleport_hub}
    teleport_start              -> {op:teleport_start}
    spawn_object <object_id>    -> {op:spawn_object, object}
    copy_item                   -> {op:copy_item}
    bank_shields_next           -> {op:bank_shields_next}
    none                        -> nothing

`floor=` is the "if you have none, gain this instead" clause the two doubling
pickup cards author and the doubling Health card does not — see docs/cards-design.md
§5 for why 2 of Hearts has no floor.

An EMPTY effect is an authoring hole here, unlike on a potion: a card's whole
pitch is that you can read what it does before spending it, so a blank Effect
raises rather than writing a card that fizzles.

  python3 tools/generate_card2_tres.py            # regenerate every card
  python3 tools/generate_card2_tres.py --list     # print, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "cards2.0")

# The games the icon files are named for, longest first so the split below never
# stops at the wrong underscore. Same shape as PotionSystem.SOURCES, and here for
# the same reason: the file name is content, not just a path.
ICON_SOURCES = [
    ("Slay_the_Spire", "Slay the Spire"),
    ("Balatro", "Balatro"),
    ("Isaac", "The Binding of Isaac"),
]


def slugify(name: str) -> str:
    # `?` IS SPELLED OUT, not stripped. "? Card" is a real row and the ordinary
    # rule — drop everything that is not a letter or a digit — turns it into the
    # id `card`, which is both meaningless and the one id most likely to collide
    # with something added later. The art file already spells it (QuestionMarkCard),
    # so the id follows the art.
    s = str(name).strip().lower().replace("'", "").replace("?", " question mark ")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v):
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def icon_credit(icon: str) -> tuple:
    """"Isaac_Major_Arcana" -> ("The Binding of Isaac", "Major Arcana")."""
    if not icon:
        return "", ""
    for prefix, game in ICON_SOURCES:
        if icon == prefix:
            return game, ""
        if icon.startswith(prefix + "_"):
            return game, icon[len(prefix) + 1:].replace("_", " ")
    return "", icon.replace("_", " ")


def _kv(tokens):
    """`floor=2` -> {'floor': '2'}, ignoring bare words."""
    out = {}
    for t in tokens:
        if "=" in t:
            k, _, v = t.partition("=")
            out[k.strip().lower()] = v.strip()
    return out


# What `double_stat` may name. Spelled out rather than passed through, because a
# typo here would double a field that does not exist and do nothing at all —
# silently, at the moment the player spends a Rare.
DOUBLE_STATS = ("gold", "bombs", "keys", "hp")

RANGE_RE = re.compile(r"^(\d+)\s*-\s*(\d+)$")


def parse_clause(s: str) -> list:
    parts = s.split()
    verb = parts[0].lower()
    rest = parts[1:]
    kv = _kv(rest)
    bare = [t for t in rest if "=" not in t]

    if verb == "none":
        return []

    if verb == "gain_hp":
        if not bare:
            raise ValueError("card effect DSL: gain_hp needs an amount in %r" % s)
        m = RANGE_RE.match(bare[0])
        if m:
            lo, hi = int(m.group(1)), int(m.group(2))
            if lo > hi:
                raise ValueError("card effect DSL: gain_hp range %r is backwards" % bare[0])
            return [{"op": "gain_hp", "min": lo, "max": hi}]
        return [{"op": "gain_hp", "value": int(bare[0])}]

    if verb == "gain_stat":
        if len(bare) < 2:
            raise ValueError("card effect DSL: gain_stat needs a stat and an amount in %r" % s)
        return [{"op": "gain_stat", "stat": bare[0], "value": int(bare[1])}]

    if verb == "double_stat":
        if not bare:
            raise ValueError("card effect DSL: double_stat needs something to double in %r" % s)
        stat = bare[0].lower()
        if stat not in DOUBLE_STATS:
            raise ValueError("card effect DSL: cannot double %r (want one of %s)"
                             % (stat, ", ".join(DOUBLE_STATS)))
        op = {"op": "double_stat", "stat": stat}
        if "floor" in kv:
            op["floor"] = int(kv["floor"])
        return [op]

    if verb == "gain_loot":
        if len(bare) < 2:
            raise ValueError("card effect DSL: gain_loot needs a kind and a count in %r" % s)
        return [{"op": "gain_loot", "kind": bare[0].lower(), "count": int(bare[1])}]

    if verb == "teleport_type":
        if not bare:
            raise ValueError("card effect DSL: teleport_type needs a game type in %r" % s)
        return [{"op": "teleport_type", "game_type": bare[0].lower()}]

    if verb in ("teleport_hub", "teleport_start", "copy_item", "bank_shields_next"):
        return [{"op": verb}]

    if verb == "spawn_object":
        if not bare:
            raise ValueError("card effect DSL: spawn_object needs an object id in %r" % s)
        return [{"op": "spawn_object", "object": bare[0]}]

    raise ValueError("card effect DSL: unknown verb %r in %r" % (verb, s))


def parse_effect(raw, name: str) -> list:
    text = _clean(raw)
    if not text:
        raise ValueError("card %r has no Effect authored — every card prints what it does"
                         % name)
    out = []
    for clause in text.split(";"):
        clause = clause.strip()
        if clause:
            out.extend(parse_clause(clause))
    return out


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


def card_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    cid = slugify(name)
    rarity = _clean(row.get("Rarity")) or "Common"
    description = _clean(row.get("Description"))
    effect = parse_effect(row.get("Effect"), name)
    file = _clean(row.get("Image"))
    icon = _clean(row.get("Icon Image"))
    source_game, set_name = icon_credit(icon)

    lines = []
    lines.append('[gd_resource type="Resource" script_class="CardData" load_steps=2 '
                 'format=3 uid="uid://card2_%s"]' % cid)
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/CardData.gd" id="1_card"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_card")')
    lines.append('id = &"%s"' % cid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('rarity = "%s"' % gd_str(rarity))
    lines.append('source_game = "%s"' % gd_str(source_game))
    lines.append('set_name = "%s"' % gd_str(set_name))
    lines.append('description = "%s"' % gd_str(description))
    lines.append("effect = %s" % gd_value(effect))
    lines.append('file = "%s"' % gd_str(file))
    lines.append('icon = "%s"' % gd_str(icon))
    return cid, "\n".join(lines) + "\n"


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
    for row in rows(wb["cards"]):
        cid, text = card_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (cid, text))
            continue
        with open(os.path.join(OUT_DIR, cid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(cid)
    if not args.list:
        print("Wrote %d card2.0 .tres to %s" % (len(written), OUT_DIR))
        for c in written:
            print("  -", c)


if __name__ == "__main__":
    main()

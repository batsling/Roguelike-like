#!/usr/bin/env python3
"""Generate Godot CardData .tres for the games-first (2.0) cards, from the
`cards` sheet of tools/Roguelikes.xlsx into data/cards2.0/.

Cards are the FOURTH loot consumable (docs/cards-design.md), and the only one
that is not a gamble: one use, one effect, printed on the face. So this generator
parses ONE effect column and no Preference — there is nothing to hint at.

  cards: Name | Rarity | Type | Description | Effect | Game | Image | Icon Image

`Image` is the card's FACE, drawn once it is in the pack; `Icon Image` is its
BACK, drawn while it is lying on the floor, and shared by every card of a set.
The back is also where the DECK comes from: the icon files spell out the game and
the deck ("Isaac_Major_Arcana"), so `set_name` is read off it. `source_game` is the
sheet's `Game` column when it is filled (it can say "Rebirth" where the icon can
only say "Isaac") and the icon's game when it is not.

PASSIVE CARDS (docs/loot-passives.md). A row whose `Type` is `Passive` is
a card that is never spent — it works from its pack slot, like a Balatro joker —
and its Effect is written in the RELIC grammar rather than this one, compiled by
generate_item_tres.parse_loot_passive into the same four fields a trinket carries.
`Type` is the switch, and it is shown on the card as a chip, which is why the
Description no longer opens "Passive:" — the chip says it once, and the line is
left to say what the card does. A Type other than Usable or Passive is refused.

Effect token DSL (semicolons separate clauses, as in every other sheet):

    gain_hp <n>                 -> {op:gain_hp, value:n}
    gain_hp <lo>-<hi>           -> {op:gain_hp, min:lo, max:hi}
    gain_stat <stat> <n>        -> {op:gain_stat, stat, value:n}
    double_stat <what> [floor=<n>]
                                -> {op:double_stat, stat, floor?}
    gain_loot <kind> <n> [identify]
                                -> {op:gain_loot, kind, count:n, identify?}
                                   `identify` teaches what was rolled (Alchemize)
    teleport_type <game_type>   -> {op:teleport_type, game_type}
    teleport_shop               -> {op:teleport_shop}
    teleport_start              -> {op:teleport_start}
    spawn_object <object_id>    -> {op:spawn_object, object}
    spawn_boss                  -> {op:spawn_boss}
    copy_item                   -> {op:copy_item}
    lose_hp <n>                 -> {op:lose_hp, value:n}       Health as a price
    stun <n> [area=row|board]   -> {op:stun, value:n, area?}
    apply_status <id> <n> [area=row|board]
                                -> {op:apply_status, status, value:n, area?}
    destroy_row                 -> {op:destroy_row}    every OTHER piece in its pack row
    destroy_pick <n>            -> {op:destroy_pick, value:n}  the player picks n
    charge_pick <n>             -> {op:charge_pick, value:n}   n charges into one thing
    exhume                      -> {op:exhume}         a destroyed piece back
    none                        -> nothing

WHERE A STUN OR STATUS LANDS is its `area`: none is the one body the card is
aimed at, `row` the lane of the square it is aimed at, `board` every body with no
aiming. A card with either of the first two asks for a square before it plays
(CardData.aim).

`per=<count>` on gain_hp, gain_stat, stun or apply_status repeats the clause that
many times, counted off the play so far: `destroyed` (pieces an earlier clause of
this card destroyed), `hit` (bodies an earlier clause covered), `cards_used`
(OTHER cards used this game). A count of 0 does nothing.

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
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_item_tres as items  # noqa: E402

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
    # Case-blind: the Slay the Spire icons on disk are spelled both
    # "Slay_the_Spire_…" and "Slay_The_Spire_…".
    for prefix, game in ICON_SOURCES:
        if icon.lower() == prefix.lower():
            return game, ""
        if icon.lower().startswith(prefix.lower() + "_"):
            return game, icon[len(prefix) + 1:].replace("_", " ")
    return "", icon.replace("_", " ")


def _png_stems(folder: str) -> dict:
    """Lowercased stem -> on-disk stem for the PNGs in images2.0/<folder>/."""
    d = os.path.join(PROJECT_ROOT, "images2.0", folder)
    out = {}
    if os.path.isdir(d):
        for fn in os.listdir(d):
            if fn.lower().endswith(".png"):
                out[fn[:-4].lower()] = fn[:-4]
    return out


_ART = {}


def on_disk(folder: str, stem: str) -> str:
    """The art name AS IT IS ON DISK. The game loads res:// paths, which are
    case-sensitive on every exported build, so a sheet cell that spells the file
    with different capitals ("Slay_The_Spire_Ironclad_Rare" for
    "Slay_the_Spire_Ironclad_Rare") would draw nothing. A name with no file is
    passed through as written."""
    if not stem:
        return stem
    if folder not in _ART:
        _ART[folder] = _png_stems(folder)
    return _ART[folder].get(stem.lower(), stem)


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

PER_COUNTS = ("destroyed", "hit", "cards_used")
AREAS = ("row", "board")


def _with_per(op: dict, kv: dict, s: str) -> dict:
    if "per" in kv:
        if kv["per"] not in PER_COUNTS:
            raise ValueError("card effect DSL: per=%r is not one of %s in %r"
                             % (kv["per"], ", ".join(PER_COUNTS), s))
        op["per"] = kv["per"]
    return op


def _with_area(op: dict, kv: dict, s: str) -> dict:
    if "area" in kv:
        if kv["area"] not in AREAS:
            raise ValueError("card effect DSL: area=%r is not one of %s in %r"
                             % (kv["area"], ", ".join(AREAS), s))
        op["area"] = kv["area"]
    return op


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
        return [_with_per({"op": "gain_hp", "value": int(bare[0])}, kv, s)]

    if verb == "gain_stat":
        if len(bare) < 2:
            raise ValueError("card effect DSL: gain_stat needs a stat and an amount in %r" % s)
        return [_with_per({"op": "gain_stat", "stat": bare[0], "value": int(bare[1])}, kv, s)]

    if verb in ("lose_hp", "destroy_pick", "charge_pick"):
        if not bare:
            raise ValueError("card effect DSL: %s needs an amount in %r" % (verb, s))
        return [{"op": verb, "value": int(bare[0])}]

    if verb == "stun":
        if not bare:
            raise ValueError("card effect DSL: stun needs an amount in %r" % s)
        op = {"op": "stun", "value": int(bare[0])}
        return [_with_per(_with_area(op, kv, s), kv, s)]

    if verb == "apply_status":
        if len(bare) < 2:
            raise ValueError("card effect DSL: apply_status needs a status and an amount in %r" % s)
        op = {"op": "apply_status", "status": bare[0].lower(), "value": int(bare[1])}
        return [_with_per(_with_area(op, kv, s), kv, s)]

    if verb in ("destroy_row", "exhume"):
        return [{"op": verb}]

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
        op = {"op": "gain_loot", "kind": bare[0].lower(), "count": int(bare[1])}
        # Alchemize: the piece rolled is identified before it is offered, so the
        # player picks up a potion they can already read.
        if len(bare) > 2:
            if [b.lower() for b in bare[2:]] != ["identify"]:
                raise ValueError("card effect DSL: gain_loot takes only `identify` "
                                 "after the count in %r" % s)
            op["identify"] = True
        return [op]

    if verb == "teleport_type":
        if not bare:
            raise ValueError("card effect DSL: teleport_type needs a game type in %r" % s)
        return [{"op": "teleport_type", "game_type": bare[0].lower()}]

    # IV - The Emperor: a random boss of the current game type and difficulty tier
    # walks onto the board (GameLoop2.summon_boss).
    if verb in ("teleport_shop", "teleport_start", "copy_item", "spawn_boss"):
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
    passive = None
    loot_type = _clean(row.get("Type")) or "Usable"
    if loot_type not in ("Usable", "Passive"):
        raise ValueError("card %r: Type %r is not Usable or Passive" % (name, loot_type))
    if loot_type == "Passive":
        passive = items.parse_loot_passive(name, _clean(row.get("Effect")))
        effect = []
    else:
        effect = parse_effect(row.get("Effect"), name)
    file = on_disk("cards", _clean(row.get("Image")))
    icon = on_disk("cards_icons", _clean(row.get("Icon Image")))
    source_game, set_name = icon_credit(icon)
    source_game = _clean(row.get("Game")) or source_game

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
    lines.append('loot_type = "%s"' % gd_str(loot_type))
    # The sheet's `Tags` (joker, tarot, playing_card) — what a "random joker card"
    # in a starting loadout draws from.
    tags = [t.strip().lower() for t in _clean(row.get("Tags")).split(",") if t.strip()]
    if tags:
        lines.append("tags = PackedStringArray(%s)" % ", ".join('"%s"' % gd_str(t) for t in tags))
    if passive is not None:
        lines.append("passive = true")
        lines.append("triggers = %s" % gd_value(passive["triggers"]))
        lines.append("stat_bonuses = %s" % gd_value(passive["stat_bonuses"]))
        lines.append("status_bonuses = %s" % gd_value(passive["status_bonuses"]))
        if passive["copy_neighbour"]:
            lines.append('copy_neighbour = "%s"' % gd_str(passive["copy_neighbour"]))
        if passive["bank_shields"]:
            lines.append("bank_shields = true")
        if passive["echo_first_loot"]:
            lines.append("echo_first_loot = %d" % passive["echo_first_loot"])
        if passive["harmless_statuses"]:
            raise ValueError("card %r: harmless_status is a trinket's rule "
                             "(docs/loot-passives.md §17)" % name)
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

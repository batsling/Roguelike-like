#!/usr/bin/env python3
"""Generate Godot WandData .tres for the games-first (2.0) wands, from the
`wands` sheet of tools/Roguelikes.xlsx into data/wands2.0/.

Wands are the FIFTH loot consumable (docs/wands-design.md), and the first one
that is not spent in a single use: every row authors a CHARGE COUNT, and what the
Effect column describes is what ONE of those charges buys.

  wands: Name | Rarity | Game | Preference | Aim | Charges | Description |
         Effect | Tags | File

`Aim` (the column was `Type` until the October 2026 sheet, and is still read
under that name) says what the wand wants pointed at it, in THE WEAPONS' WORDS
(generate_weapon_tres.parse_aim) — one vocabulary for both kinds of aimed loot:

  Ray[, Bounce N]  -> "ray"     a line from you (the left of the board) through
                                any square you click, Ball x Pit's ball: it stops
                                at the first enemy or wall it meets, bouncing N
                                times first, and the Effect lands on EVERY enemy
                                it struck (RayAim.gd). Nearly the whole roster.
  Non-Directional  -> "none"    nothing; it fires where it stands. (`none` is
                                the weapons' own word and reads the same.)
  Random           -> "random"  no click: the zap lands on a random enemy
                                standing on the board. Wand of Nothing is the
                                only row that authors it.
  Any / Front / Back / Column N / Enemy
                   -> the square clicked, fenced as a weapon's Aim is.

An UNIDENTIFIED wand still asks for a square whatever its Aim (WandSystem.
needs_target), so the click itself never says which kind a mystery stick is.

Effect token DSL (semicolons separate clauses, as in every other sheet). Every
clause takes an optional `area=`, resolved RELATIVE TO THE AIMED CELL at runtime
by GameLoop2.area_cells — cell (the default), row, col, 3x3, 5x5, board:

    nothing                          -> [] (see below)
    obtain_item [pool]               -> {op:obtain_item, pool}
    apply_tile <tile> [area=…]       -> {op:apply_tile, tile, area}
    apply_status <status> <n> [target=enemy|player] [area=…] [games=<n>]
                                     -> {op:apply_status, status, value, target,
                                         area, games?}
    deal_damage <n> [area=…]         -> {op:deal_damage, value, area}
    spawn_enemy <current|n> [tag=…]  -> {op:spawn_enemy, tier, value, tag?}
    gain_loot <kind> <n>             -> {op:gain_loot, kind, count}

  …and six that aim at a UNIT — an enemy, a boss, or one of the player's own
  bodies (spec §17). Each runs once per unit the area covers:

    kill [area=…]                    -> {op:kill, area}
    cancel_abilities [area=…]        -> {op:cancel_abilities, area}
    split [area=…]                   -> {op:split, area}
    polymorph [area=…]               -> {op:polymorph, area}
    teleport [area=…]                -> {op:teleport, area}
    grant_ability <id> [n] [area=…]  -> {op:grant_ability, ability, value, area}

`nothing` IS A VERB, and every OTHER empty Effect cell is refused. Wand of
Nothing is the roster's deliberate blank and an empty cell cannot be told apart
from a row somebody has not filled in yet — so the sheet says the nothing out
loud. (The potions generator takes the opposite line and reads a blank as
authored, which is why a Potion of Uselessness typo would ship silently.)

`games=` is the timed-status clock (§5.1 of the potions design), written ONLY when
non-zero, so every apply_status without one means "permanent" — which is what
every apply_status authored anywhere in this project already means.

Art: File -> res://images2.0/wands/<File>.png. NO ROW HAS ONE and none is waiting
for one (§6.3): an identified wand keeps showing the material the run dealt it,
so a blank (or `N/A`) File is expected and correct.

  python3 tools/generate_wand2_tres.py            # regenerate every wand
  python3 tools/generate_wand2_tres.py --list     # print, write nothing
"""

import argparse
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_weapon_tres as weapons  # noqa: E402

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "wands2.0")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v):
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


# The shapes an `area=` token may name, resolved against the aimed cell by
# GameLoop2.area_cells at runtime. Clipped to the board, never wrapped.
AREAS = ("cell", "row", "col", "3x3", "5x5", "board")

# The Aim words a wand may NOT take from the weapons' list: none so far — every
# weapon aim means something for a zap. Non-Directional is the wand sheet's own
# spelling of `none`.
NON_DIRECTIONAL = ("non-directional", "non directional", "nondirectional")

# Who an apply_status lands on. A wand can burn the body on the square it hit or
# the hand holding it, and the two are the same verb pointed differently.
STATUS_TARGETS = ("enemy", "player")


def _kv(tokens):
    """`area=3x3 games=1` -> {'area': '3x3', 'games': '1'}, ignoring bare words."""
    out = {}
    for t in tokens:
        if "=" in t:
            k, _, v = t.partition("=")
            out[k.strip().lower()] = v.strip()
    return out


def _area(tokens, where) -> str:
    area = _kv(tokens).get("area", "cell").lower()
    if area not in AREAS:
        raise ValueError("wands %s: unknown area %r (want one of %s)"
                         % (where, area, ", ".join(AREAS)))
    return area


def _games(tokens) -> int:
    raw = _kv(tokens).get("games")
    return int(raw) if raw is not None else 0


def _nums(tokens):
    return [int(t) for t in tokens if re.fullmatch(r"-?\d+", t)]


def parse_effect(raw, where):
    """Parse one Effect cell into the list of op dicts one charge runs."""
    s = _clean(raw)
    if not s:
        raise ValueError(
            "wands %s: the Effect column is empty. A wand that does nothing is "
            "content — write `nothing` — and a wand that does nothing by accident "
            "is a slot the player carries for no reason." % where)
    if s.strip().lower() == "nothing":
        return []
    out = []
    for clause in [c.strip() for c in s.split(";") if c.strip()]:
        out.extend(parse_clause(clause, where))
    return out


def parse_clause(s: str, where: str):
    toks = s.split()
    verb = toks[0].lower()
    rest = toks[1:]
    nums = _nums(rest)
    kv = _kv(rest)
    bare = [t for t in rest if "=" not in t]

    if verb == "obtain_item":
        # The wand's whole payload is a PICKER, fulfilled by the overworld. `pool`
        # is which items it may offer; `any` is the only one the roster uses and
        # the only one the relic it replaces ever used.
        return [{"op": "obtain_item", "pool": (bare[0].lower() if bare else "any")}]

    if verb == "apply_tile":
        if not bare:
            raise ValueError("wands %s: apply_tile needs a tile in %r" % (where, s))
        return [{"op": "apply_tile", "tile": bare[0].lower(),
                 "area": _area(rest, where)}]

    if verb == "apply_status":
        if not bare:
            raise ValueError("wands %s: apply_status needs a status in %r" % (where, s))
        target = kv.get("target", "enemy").lower()
        if target not in STATUS_TARGETS:
            raise ValueError("wands %s: unknown status target %r (want %s)"
                             % (where, target, " or ".join(STATUS_TARGETS)))
        op = {"op": "apply_status", "status": bare[0].lower(),
              "value": nums[0] if nums else 1, "target": target,
              "area": _area(rest, where)}
        games = _games(rest)
        if games:
            op["games"] = games
        return [op]

    if verb == "deal_damage":
        return [{"op": "deal_damage", "value": nums[0] if nums else 1,
                 "area": _area(rest, where)}]

    if verb == "spawn_enemy":
        # `current` is the run's own difficulty, which is Scroll of Create
        # Monster's wording and the only tier the roster asks for. A bare number is
        # HOW MANY bodies, not which tier — the two are told apart by the word.
        tier = "current"
        count = 1
        for t in bare:
            if re.fullmatch(r"-?\d+", t):
                count = int(t)
            else:
                tier = t.lower()
        op = {"op": "spawn_enemy", "tier": tier, "value": max(1, count)}
        if "tag" in kv:
            op["tag"] = kv["tag"].lower()
        return [op]

    if verb == "gain_loot":
        kind = bare[0].lower() if bare else "loot"
        return [{"op": "gain_loot", "kind": kind, "count": nums[0] if nums else 1}]

    # --- the six that aim at a UNIT -------------------------------------------
    #
    # A UNIT is anything standing on the square: an enemy, a boss, or one of the
    # player's own bodies (spec §17). All six take an `area=` like every other
    # clause and none takes anything else, because what they do to a unit is the
    # whole of what they do — WandSystem resolves the aimed cell to the units on
    # it and runs the verb once per unit found.
    if verb in ("kill", "cancel_abilities", "split", "polymorph", "teleport"):
        return [{"op": verb, "area": _area(rest, where)}]

    if verb == "grant_ability":
        # Hang an ability on the unit. `amount` is the ability's own argument
        # (Ranged's range, Split's count); the roster's one row grants
        # `invisibility`, which takes none, so it is written without a number.
        if not bare:
            raise ValueError("wands %s: grant_ability needs an ability in %r"
                             % (where, s))
        return [{"op": "grant_ability", "ability": bare[0].lower(),
                 "value": nums[0] if nums else 0, "area": _area(rest, where)}]

    raise ValueError("wands %s: unknown verb %r in %r" % (where, verb, s))


def parse_aim(raw, where) -> tuple:
    """(aim, aim_column, bounce), in the weapons' vocabulary."""
    text = (_clean(raw) or "none").strip()
    head, sep, rest = text.partition(",")
    if head.strip().lower() in NON_DIRECTIONAL + ("none",):
        # Answered here: Non-Directional is the wand sheet's own word for it.
        if rest.strip():
            raise ValueError("wands %s: Aim %r — a Non-Directional wand does not "
                             "bounce" % (where, raw))
        return "none", 0, 0
    try:
        aim, col, bounce = weapons.parse_aim(text, where)
    except ValueError as e:
        raise ValueError("wands %s: %s" % (where, str(e).split(": ", 1)[-1]))
    if bounce and aim != "ray":
        raise ValueError("wands %s: Bounce %d on Aim %r — only a Ray bounces"
                         % (where, bounce, aim))
    return aim, col, bounce or 0


def parse_charges(raw, where) -> int:
    s = _clean(raw)
    if not s:
        raise ValueError("wands %s: the Charges column is empty — how many times "
                         "a wand can be zapped is what a wand IS" % where)
    try:
        n = int(float(s))
    except ValueError:
        raise ValueError("wands %s: cannot read Charges %r as a number" % (where, s))
    if n < 1:
        raise ValueError("wands %s: %d charges is a wand that cannot be used"
                         % (where, n))
    return n


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
        return "{" + ", ".join('"%s": %s' % (gd_str(k), gd_value(val))
                               for k, val in v.items()) + "}"
    raise TypeError(type(v))


def wand_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    wid = slugify(name)
    rarity = _clean(row.get("Rarity")) or "Common"
    preference = _clean(row.get("Preference")) or "Neutral"
    aim, aim_col, bounce = parse_aim(
        row.get("Aim") if "Aim" in row else row.get("Type"), name)
    charges = parse_charges(row.get("Charges"), name)
    description = _clean(row.get("Description"))
    effect = parse_effect(row.get("Effect"), name)
    file = _clean(row.get("File"))

    lines = []
    lines.append('[gd_resource type="Resource" script_class="WandData" load_steps=2 '
                 'format=3 uid="uid://wand2_%s"]' % wid)
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/WandData.gd" id="1_wand"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_wand")')
    lines.append('id = &"%s"' % wid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('rarity = "%s"' % gd_str(rarity))
    lines.append('preference = "%s"' % gd_str(preference))
    lines.append('reference = "%s"' % gd_str(_clean(row.get("Game"))))
    lines.append('description = "%s"' % gd_str(description))
    lines.append("charges = %d" % charges)
    lines.append('aim = "%s"' % gd_str(aim))
    lines.append("aim_column = %d" % aim_col)
    lines.append("bounce = %d" % bounce)
    lines.append("effect = %s" % gd_value(effect))
    lines.append('file = "%s"' % gd_str(file))
    # The sheet's `Tags` column (lower-cased): what a tag-reading rule matches
    # on, the way a trinket's `Tag` is — an evolution's "with \"heat\"" or a
    # food's tag. Blank is no tags.
    lines.append("tags = PackedStringArray(%s)" % ", ".join(
        '"%s"' % gd_str(t.strip().lower())
        for t in str(row.get("Tags") or "").split(",") if t.strip()))
    return wid, "\n".join(lines) + "\n"


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
    for row in rows(wb["wands"]):
        wid, text = wand_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (wid, text))
            continue
        with open(os.path.join(OUT_DIR, wid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(wid)
    if not args.list:
        print("Wrote %d wand2.0 .tres to %s" % (len(written), OUT_DIR))
        for w in written:
            print("  -", w)


if __name__ == "__main__":
    main()

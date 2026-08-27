#!/usr/bin/env python3
"""Generate Godot PotionData .tres for the games-first (2.0) potions, from the
`potions2.0` sheet of tools/Roguelikes.xlsx into data/potions2.0/.

Potions are the THIRD loot consumable (docs/potions-design.md), and the first one
that is two effects in one piece: every row authors an `On Player` side and an
`On Tile` side, and the player chooses which they are buying when they spend it —
QUAFF or THROW. So this generator parses TWO effect columns, in two dialects of
one DSL, and writes them to PotionData.quaff and PotionData.throw.

  potions2.0: Name | Rarity | Preference | On Player | On Player Effect |
              On Tile | On Tile Effect | Reference | File

The prose columns (`On Player`, `On Tile`) are what the player reads on an
identified bottle's card; the Effect columns beside them are what the game runs.
Both are carried, because an identified potion shows BOTH sides at once (§6.5) and
prose the ops cannot reproduce is prose worth keeping.

Effect token DSL (semicolons separate clauses, as in every other sheet).

  ON PLAYER (quaff):
    take_damage <n>                  -> {op:take_damage, value:n}
    gain_hp <n> / gain_max_hp <n>    -> {op:…, value:n}
    gain_stat <stat> <n>             -> {op:gain_stat, stat, value:n}
    gain_level <n>                   -> {op:gain_level, value:n}
    apply_status <status> <n> [player] [games=<n>]
                                     -> {op:apply_status, status, value, target,
                                         games?}
    none                             -> nothing

  ON TILE (throw), where every clause takes an optional `area=`:
    apply_tile <tile> [area=…]       -> {op:apply_tile, tile, area}
    deal_damage <n> [area=…]         -> {op:deal_damage, value, area}
    grant_shield <n> [area=…]        -> {op:grant_shield, value, area}
    grant_health <n> [area=…]        -> {op:grant_health, value, area}
    grant_max_health <n> [area=…]    -> {op:grant_max_health, value, area}
    apply_status <status> <n> [area=…] [games=<n>]
                                     -> {op:apply_status, status, value, area,
                                         games?}
    none                             -> nothing

`area=` is resolved RELATIVE TO THE AIMED CELL at runtime (§4.3): cell (default),
row, col, 3x3, board. `games=` is the timed-status clock (§5.1) — it is written
ONLY when non-zero, so every op without one means "permanent", which is what every
pre-existing apply_status in the project already means.

An empty effect list is authored rather than missing: Uselessness does nothing in
both directions and Raise Level has no throw. Both fizzle out loud at runtime
(§4.5), so neither is an authoring hole to warn about here.

Art: File -> res://images2.0/potions_identified/<File>.png. SIX ROWS HAVE NO FILE
AND ARE NOT WAITING FOR ONE (§6.3) — an identified potion with no art of its own
keeps showing the run's own bottle, so a blank File is expected and correct.

  python3 tools/generate_potion2_tres.py            # regenerate every potion
  python3 tools/generate_potion2_tres.py --list     # print, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "potions2.0")


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
# GameLoop2.area_cells at runtime (§4.3). Clipped to the board, never wrapped.
AREAS = ("cell", "row", "col", "3x3", "5x5", "board")

# The one target word the quaff side uses. A potion drunk lands on the drinker and
# nowhere else — the board words belong to the throw side, where `area=` says it
# better than a target ever could.
PLAYER_TARGET = "player"


def _kv(tokens):
    """`area=3x3 games=1` -> {'area': '3x3', 'games': '1'}, ignoring bare words."""
    out = {}
    for t in tokens:
        if "=" in t:
            k, _, v = t.partition("=")
            out[k.strip().lower()] = v.strip()
    return out


def _area(tokens) -> str:
    area = _kv(tokens).get("area", "cell").lower()
    if area not in AREAS:
        raise ValueError("potion effect DSL: unknown area %r (want one of %s)"
                         % (area, ", ".join(AREAS)))
    return area


def _games(tokens) -> int:
    raw = _kv(tokens).get("games")
    return int(raw) if raw is not None else 0


def _nums(tokens):
    return [int(t) for t in tokens if re.fullmatch(r"-?\d+", t)]


def parse_effect(raw, side: str):
    """Parse one Effect cell into the list of op dicts that side runs (or [])."""
    s = _clean(raw)
    if not s:
        return []
    out = []
    for clause in [c.strip() for c in s.split(";") if c.strip()]:
        out.extend(parse_clause(clause, side))
    return out


def parse_clause(s: str, side: str):
    """One clause of the Effect DSL -> a list holding its op dict (or [])."""
    toks = s.split()
    verb = toks[0].lower()
    rest = toks[1:]
    nums = _nums(rest)
    throwing = side == "throw"

    if verb == "none":
        # Authored nothing, and that is content: Uselessness is the roster's joke
        # and Raise Level simply has no tile side. Both are fizzles at runtime,
        # not holes here.
        return []

    if verb in ("take_damage", "gain_hp", "gain_max_hp", "gain_level"):
        if throwing:
            raise ValueError("potion effect DSL: %r is a quaff verb, in a throw "
                             "cell (%r)" % (verb, s))
        return [{"op": verb, "value": nums[0] if nums else 1}]

    if verb == "gain_stat":
        if throwing:
            raise ValueError("potion effect DSL: gain_stat is a quaff verb, in a "
                             "throw cell (%r)" % s)
        if not rest:
            raise ValueError("potion effect DSL: gain_stat needs a stat in %r" % s)
        return [{"op": "gain_stat", "stat": rest[0].lower(),
                 "value": nums[0] if nums else 1}]

    if verb in ("deal_damage", "grant_shield", "grant_health", "grant_max_health"):
        if not throwing:
            raise ValueError("potion effect DSL: %r is a throw verb, in a quaff "
                             "cell (%r)" % (verb, s))
        return [{"op": verb, "value": nums[0] if nums else 1, "area": _area(rest)}]

    if verb == "apply_tile":
        if not throwing:
            raise ValueError("potion effect DSL: apply_tile is a throw verb, in a "
                             "quaff cell (%r)" % s)
        if not rest:
            raise ValueError("potion effect DSL: apply_tile needs a tile in %r" % s)
        return [{"op": "apply_tile", "tile": rest[0].lower(), "area": _area(rest)}]

    if verb == "apply_status":
        # The one verb both sides speak, and the two sides target differently: a
        # quaffed status lands on the drinker, a thrown one on every body the area
        # covers. So the quaff side carries a `target` and the throw side carries
        # an `area`, and neither carries the other's word.
        if not rest:
            raise ValueError("potion effect DSL: apply_status needs a status in %r" % s)
        op = {"op": "apply_status", "status": rest[0].lower(),
              "value": nums[0] if nums else 1}
        if throwing:
            op["area"] = _area(rest)
        else:
            op["target"] = PLAYER_TARGET
        # Written only when it is a clock. Everything without one is permanent,
        # which is what every apply_status authored before potions already meant.
        games = _games(rest)
        if games:
            op["games"] = games
        return [op]

    raise ValueError("potion effect DSL: unknown verb %r in %r" % (verb, s))


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


def potion_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    pid = slugify(name)
    rarity = _clean(row.get("Rarity")) or "Common"
    preference = _clean(row.get("Preference")) or "Neutral"
    quaff_text = _clean(row.get("On Player"))
    throw_text = _clean(row.get("On Tile"))
    quaff = parse_effect(row.get("On Player Effect"), "quaff")
    throw = parse_effect(row.get("On Tile Effect"), "throw")
    file = _clean(row.get("File"))

    lines = []
    lines.append('[gd_resource type="Resource" script_class="PotionData" load_steps=2 '
                 'format=3 uid="uid://potion2_%s"]' % pid)
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/PotionData.gd" id="1_potion"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_potion")')
    lines.append('id = &"%s"' % pid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('rarity = "%s"' % gd_str(rarity))
    lines.append('preference = "%s"' % gd_str(preference))
    lines.append('reference = "%s"' % gd_str(_clean(row.get("Reference"))))
    lines.append('quaff_text = "%s"' % gd_str(quaff_text))
    lines.append('throw_text = "%s"' % gd_str(throw_text))
    lines.append("quaff = %s" % gd_value(quaff))
    lines.append("throw = %s" % gd_value(throw))
    lines.append('file = "%s"' % gd_str(file))
    return pid, "\n".join(lines) + "\n"


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
    for row in rows(wb["potions"]):
        pid, text = potion_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (pid, text))
            continue
        with open(os.path.join(OUT_DIR, pid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(pid)
    if not args.list:
        print("Wrote %d potion2.0 .tres to %s" % (len(written), OUT_DIR))
        for p in written:
            print("  -", p)


if __name__ == "__main__":
    main()

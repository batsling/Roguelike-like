#!/usr/bin/env python3
"""
Generate Godot TileEffectData .tres for the games-first redesign's TILE EFFECTS, from
the `tiles2.0` sheet of tools/Roguelikes.xlsx into data/tiles2.0/.

A tile effect (docs/games-first-redesign.md §17) sits on ONE CELL of the
battlefield and acts on whatever stands in it. It is not a status — a status rides
a body and travels with it, a tile effect stays where it was put — and it is not a
unit either, though the two share this file's DSL: a unit is a body standing on a
cell, a tile effect is something done to the ground under it, and they layer.

  tiles2.0: Name | Description | Effect | Interactions | Decay | Img

EFFECT DSL — semicolon-separated clauses, each either a TRIGGER header or one
effect belonging to the trigger before it, exactly like the item sheet's:

  enemy_enters: <effect>[; <effect>]      a body's footprint newly covered the cell
  enemy_turn_start: <effect>[; …]         a body was already standing here when an
                                          enemy turn began
  damaged: <effect>[; …]                  the thing on the cell has taken enough
                                          damage to spend its Health

  <effect> is one of:
    apply_status <status> <n>   -> {op: apply_status, status, value}
    detonate                    -> {op: detonate}   (units; see generate_unit_tres)

The first two cover "walked into it" and "stayed in it", which is what a tile
effect has to be able to say to be worth putting down: a cell that only bit on
entry would be free to park on, and one that only bit at turn start would be free
to walk through.

`damaged` is the third and it belongs to things with a Health (docs/potions-design.md
§4.7). The Landmine authors `damaged: detonate`, so a mine caught in a thrown
Ampoule's row — or in a bomb blast, or in anything else that ever damages ground —
goes up, instead of only ever going off under somebody who stepped on it. A unit
with a Health that nothing can damage is carrying a number for decoration.

It is a TRIGGER rather than a rule hardcoded to "0 Health runs your detonate"
because the next unit will want to react to damage differently: a barrel that
simply breaks, a totem that fires something off when shot. The trigger says WHAT
happens; the Health column says HOW MUCH IT TAKES.

INTERACTIONS DSL — semicolon-separated, one pairing per `<kind> <id>:` header:

  unit landmine: detonate_unit; remove_tile

  detonate_unit  the unit standing on the cell goes off where it is
  remove_tile    the tile effect on the cell is cleared

Parsed into {"unit:landmine": ["detonate_unit", "remove_tile"]}. EITHER SIDE of a
pairing may author it and the runtime UNIONS the two lists, so an interaction
written on one sheet only still resolves from both directions.

Which side to write it on is a WORDING decision, not a mechanical one: every
authored pairing becomes a line on that thing's hover card. The Fire/Landmine
pairing lives on the Landmine alone for exactly that reason — a mine is worth
explaining to whoever is holding one, and a burning square is not the place to
teach a player about a unit they may never own.

DECAY is read in GAMES ("3 Games"), never in turns. How many turns a game buys is
read off the distance to the Amulet (§7.4), so a tile authored in turns would burn
for three games out in the wilds and less than one on the Amulet's doorstep — the
same content, worth most where it is needed least. "N/A" (or blank) is a tile
effect that never goes out on its own. A cell written in TURNS is refused rather
than silently reinterpreted.

Art: Img -> res://images2.0/tiles/<Img>.png, referenced eagerly — there is a
handful of these, unlike the 854 game covers that forced GameData's lazy path.

  python3 tools/generate_tile_tres.py           # regenerate every tile effect
  python3 tools/generate_tile_tres.py --list    # print the parse, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "tiles2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "tiles")
IMG_RES_PREFIX = "res://images2.0/tiles/"

# The triggers a tile effect or a unit may hang an effect on. Shared with
# generate_unit_tres.py, which imports this module rather than restating them.
TRIGGERS = ("enemy_enters", "enemy_turn_start", "damaged")

# The outcome tokens an `Interactions` cell may name.
INTERACTION_OUTCOMES = ("detonate_unit", "remove_tile", "remove_unit")

# The kinds a pairing may be against.
INTERACTION_KINDS = ("tile", "unit")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v) -> str:
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


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


# --- the Effect column ----------------------------------------------------

def parse_effect(cell, what: str) -> dict:
    """`Effect` -> {trigger: [effect dict, …]}.

    Clauses are semicolon-separated. One carrying a `trigger:` header opens that
    trigger and its payload is the first effect on it; a bare clause afterwards
    belongs to the trigger still open, so `enemy_enters: a; b` hangs both on
    enemy_enters. A bare clause with no trigger open is refused — a tile effect
    that does not say WHEN is a tile effect nobody can reason about.
    """
    raw = _clean(cell)
    out = {}
    if not raw:
        return out
    current = None
    for clause in [c.strip() for c in raw.split(";") if c.strip()]:
        head, sep, payload = clause.partition(":")
        if sep and head.strip().lower() in TRIGGERS:
            current = head.strip().lower()
            out.setdefault(current, [])
            clause = payload.strip()
            if not clause:
                continue
        if current is None:
            raise ValueError(
                "%s: %r has no trigger — write `enemy_enters: …`, "
                "`enemy_turn_start: …` or `damaged: …`" % (what, clause))
        out[current].append(parse_one_effect(clause, what))
    for trigger, effects in out.items():
        if not effects:
            raise ValueError("%s: trigger %r has no effect after it" % (what, trigger))
    return out


def parse_one_effect(clause: str, what: str) -> dict:
    """One effect clause -> its effect dict."""
    low = clause.strip().lower()
    if low == "detonate":
        return {"op": "detonate"}
    m = re.match(r"^apply_status\s+([a-z_]+)(?:\s+(\d+))?$", low)
    if m:
        return {"op": "apply_status", "status": m.group(1), "value": int(m.group(2) or 1)}
    raise ValueError("%s: unknown effect %r" % (what, clause))


# --- the Interactions column ----------------------------------------------

def parse_interactions(cell, what: str) -> dict:
    """`Interactions` -> {"<kind>:<id>": [outcome, …]}.

    Same shape as the Effect column: a `<kind> <id>:` header opens a pairing and
    everything after it, until the next header, is one of that pairing's outcomes.
    """
    raw = _clean(cell)
    out = {}
    if not raw:
        return out
    current = None
    for clause in [c.strip() for c in raw.split(";") if c.strip()]:
        head, sep, payload = clause.partition(":")
        m = re.match(r"^\s*(%s)\s+([a-z_]+)\s*$" % "|".join(INTERACTION_KINDS),
                     head.lower()) if sep else None
        if m:
            current = "%s:%s" % (m.group(1), m.group(2))
            out.setdefault(current, [])
            clause = payload.strip()
            if not clause:
                continue
        if current is None:
            raise ValueError(
                "%s: %r has no pairing — write `unit landmine: …` or "
                "`tile fire: …`" % (what, clause))
        token = clause.lower()
        if token not in INTERACTION_OUTCOMES:
            raise ValueError("%s: unknown interaction outcome %r (know %s)"
                             % (what, clause, ", ".join(INTERACTION_OUTCOMES)))
        if token not in out[current]:
            out[current].append(token)
    for pairing, outcomes in out.items():
        if not outcomes:
            raise ValueError("%s: pairing %r has no outcome after it" % (what, pairing))
    return out


# --- the Decay column -----------------------------------------------------

def parse_decay(cell, what: str):
    """`Decay` -> (games, one_shot, prose). Blank / N/A never goes out."""
    raw = _clean(cell)
    if not raw:
        return 0, False, ""
    # UNTIL TRIGGERED is a clock measured in BITES rather than in games: the tile
    # goes out the moment it does its thing. Web is the roster's first, and it is
    # what makes a web a web rather than a second fire — you walk into it once.
    # It is not "1 Game" with different words: a web nobody steps in is still there
    # three games later, and a fire nobody steps in is not.
    if raw.strip().lower() in ("until triggered", "on trigger", "once"):
        return 0, True, raw.strip()
    m = re.match(r"^(\d+)\s*(game|games|turn|turns)?$", raw.strip().lower())
    if not m:
        raise ValueError("%s: cannot read Decay %r — write `3 Games` or "
                         "`Until Triggered`" % (what, raw))
    unit = m.group(2) or "games"
    if unit.startswith("turn"):
        raise ValueError(
            "%s: Decay %r is written in TURNS. How many turns a game buys is read "
            "off the distance to the Amulet, so a tile authored in turns is worth "
            "three times as much out in the wilds as it is on the doorstep. Write "
            "it in games." % (what, raw))
    return int(m.group(1)), False, raw.strip()


# --- emitting -------------------------------------------------------------

def image_path(file: str, img_dir: str, prefix: str) -> str:
    if not file:
        return ""
    for ext in (".png", ".jpg", ".jpeg", ".webp"):
        if os.path.exists(os.path.join(img_dir, file + ext)):
            return prefix + file + ext
    return ""


def tile_tres(row: dict):
    name = str(row.get("Name") or "").strip()
    tid = slugify(name)
    what = "tiles2.0 %s" % name
    triggers = parse_effect(row.get("Effect"), what)
    if not triggers:
        raise ValueError("%s: the Effect column is empty — a tile effect that "
                         "does nothing is not content" % what)
    interactions = parse_interactions(row.get("Interactions"), what)
    decay_games, decay_once, decay_text = parse_decay(row.get("Decay"), what)
    file = _clean(row.get("Img"))
    img = image_path(file, IMG_DIR, IMG_RES_PREFIX)

    steps = 3 if img else 2
    lines = []
    lines.append('[gd_resource type="Resource" script_class="TileEffectData" load_steps=%d '
                 'format=3 uid="uid://tile2_%s"]' % (steps, tid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/TileEffectData.gd" id="1_tile"]')
    if img:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_tile")')
    lines.append('id = &"%s"' % tid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('description = "%s"' % gd_str(_clean(row.get("Description"))))
    lines.append("decay_games = %d" % decay_games)
    lines.append("decay_on_trigger = %s" % ("true" if decay_once else "false"))
    lines.append('decay_text = "%s"' % gd_str(decay_text))
    lines.append("triggers = %s" % gd_value(triggers))
    lines.append("interactions = %s" % gd_value(interactions))
    lines.append('file = "%s"' % gd_str(file))
    if img:
        lines.append('image = ExtResource("2_img")')
    return tid, "\n".join(lines) + "\n"


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if not r or r[0] is None:
            continue
        yield dict(zip(headers, r))


def generate(sheet_name: str, out_dir: str, required: tuple, build, label: str) -> None:
    """Shared driver: read one sheet, emit one .tres per row. Units use it too."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    sheet = wb[sheet_name]
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for needed in required:
        if needed not in headers:
            raise SystemExit("%s has no %r column — run "
                             "tools/_tiles2_units2_setup.py first."
                             % (sheet_name, needed))

    os.makedirs(out_dir, exist_ok=True)
    written = []
    for row in rows(sheet):
        rid, text = build(row)
        if args.list:
            print("=== %s ===\n%s" % (rid, text))
            continue
        with open(os.path.join(out_dir, rid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(rid)
    if not args.list:
        print("Wrote %d %s .tres to %s" % (len(written), label, out_dir))
        for s in written:
            print("  -", s)


def main():
    generate("tiles", OUT_DIR,
             ("Name", "Description", "Effect", "Interactions", "Decay", "Img"),
             tile_tres, "tiles2.0")


if __name__ == "__main__":
    main()

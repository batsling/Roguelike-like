#!/usr/bin/env python3
"""
Generate Godot PillData .tres for the games-first redesign (2.0) pills, from the
`pills2.0` sheet of tools/Roguelikes.xlsx into data/pills2.0/.

Pills are the second loot consumable (docs/games-first-redesign.md §4.3): the
scroll's identification minigame held by a COLOUR instead of by a type, with an
oversized HORSE dose behind a 5% roll at drop time. One sheet row is one pill and
BOTH its doses, so this generator parses two effect columns into two op lists on
one resource.

  pills2.0: Name | Preference | Description | Effect |
            Horse Description | Horse Effect | Notes

There is no rarity and no art column, and both absences are deliberate. Rarity:
a pill is not rolled off a ladder, it is one of the ten the run dealt. Art: the
capsule belongs to the RUN's colour deal (PillSystem), not to the pill, which is
what stops a colour from meaning the same thing twice in a row.

Effect token DSL (semicolons separate clauses, as in every other sheet's Effect
column). Most verbs are EffectSystem's own, spelled identically, so a pill and an
item reaching for the same effect are reaching for the same word:

  gain_stat <stat> N                 -> {op:gain_stat, stat, value}
  lose_stat <stat> N                 -> {op:lose_stat, stat, value}
  gain_max_hp N / lose_max_hp N      -> {op:…, value}
  gain_hp N                          -> {op:gain_hp, value}
  lose_hp N [lethal=heal_full]       -> {op:lose_hp, value, lethal}
  heal_full                          -> {op:heal_full}
  add_curse random|<id>              -> {op:add_curse, curse}
  forget loot|scroll|pill N|all      -> {op:forget, kind, count}   (all = -1)
  teleport same|closer|farther N     -> {op:teleport, dir, spread}
  teleport amulet MIN MAX            -> {op:teleport, dir:amulet, min, max}
  charge random N [full]             -> {op:charge, mode, count, full}

Three of those are new vocabulary and are described where they are parsed below:
`gain_stat bonus_shields` (the pool that does not expire), `charge`, and
`lose_hp`'s `lethal=` (Bad Trip's safety net).

  python3 tools/generate_pill2_tres.py            # regenerate every 2.0 pill
  python3 tools/generate_pill2_tres.py --list     # print, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "pills2.0")


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


# Which `teleport` words take a SPREAD (± this far from where the pill was taken)
# and which take a BAND (this far from the Amulet, full stop). Telepills is the
# first; its horse dose is the second, and it is the only movement in the game
# that can drop you next to the goal — so it is spelled differently on purpose
# rather than as a `same` with a big number.
SPREAD_DIRS = ("same", "closer", "farther")


def parse_effect(raw):
    """Parse an Effect / Horse Effect cell into the op list the dose runs."""
    s = _clean(raw)
    if not s:
        return []
    out = []
    for clause in [c.strip() for c in s.split(";") if c.strip()]:
        out.extend(parse_clause(clause))
    return out


def parse_clause(s):
    """One clause of the pill Effect DSL -> a list holding its op dict."""
    toks = s.split()
    verb = toks[0].lower()
    rest = toks[1:]
    words = [t.lower() for t in rest if not re.match(r"^-?\d+$", t) and "=" not in t]
    nums = [int(t) for t in rest if re.match(r"^-?\d+$", t)]
    kv = dict(t.split("=", 1) for t in rest if "=" in t)

    if verb in ("gain_stat", "lose_stat"):
        # `gain_stat bonus_shields 2` is the pill vocabulary's one new STAT: the
        # shields gained off the board (§4.3), which sit beside Health rather than
        # in the per-game pool and do not expire with the game in play. Every other
        # stat here is the run stat of the same name.
        if not words:
            raise ValueError("pill effect DSL: %s needs a stat in %r" % (verb, s))
        return [{"op": verb, "stat": words[0], "value": nums[0] if nums else 1}]
    if verb in ("gain_max_hp", "lose_max_hp", "gain_hp"):
        return [{"op": verb, "value": nums[0] if nums else 1}]
    if verb == "lose_hp":
        # `lethal=heal_full` is Bad Trip's safety net (§4.3): a dose that would take
        # the last Health heals to full instead, and the pill NAMES ITSELF from that
        # — an identified Bad Trip reads "Full Health" while you are in death range.
        # It rides the op rather than being hardcoded in the handler so the horse
        # dose's bigger number moves the threshold with it.
        op = {"op": "lose_hp", "value": nums[0] if nums else 1}
        if "lethal" in kv:
            op["lethal"] = kv["lethal"].lower()
        return [op]
    if verb == "heal_full":
        return [{"op": "heal_full"}]
    if verb == "add_curse":
        return [{"op": "add_curse", "curse": words[0] if words else "random"}]
    if verb == "forget":
        # `all` is stored as -1, which is the count the scroll's forget path already
        # reads as "everything" (ScrollSystem._forget_from).
        kind = words[0] if words else "loot"
        count = -1 if "all" in words else (nums[0] if nums else 1)
        return [{"op": "forget", "kind": kind, "count": count}]
    if verb == "teleport":
        direction = words[0] if words else "same"
        if direction in SPREAD_DIRS:
            return [{"op": "teleport", "dir": direction, "spread": nums[0] if nums else 1}]
        if direction == "amulet":
            if len(nums) < 2:
                raise ValueError("pill effect DSL: teleport amulet needs MIN MAX in %r" % s)
            return [{"op": "teleport", "dir": "amulet",
                     "min": min(nums[0], nums[1]), "max": max(nums[0], nums[1])}]
        raise ValueError("pill effect DSL: unknown teleport direction %r in %r" % (direction, s))
    if verb == "charge":
        # 48 Hour Energy. Three SEPARATE charges, each landing on a random chargeable
        # relic (so two can land on the same one), or — the horse dose — three relics
        # topped all the way up. `full` is the only thing that separates them, which
        # is why it is a flag on one op rather than a second verb.
        mode = words[0] if words and words[0] != "full" else "random"
        return [{"op": "charge", "mode": mode,
                 "count": nums[0] if nums else 1,
                 "full": "full" in words}]

    raise ValueError("pill effect DSL: unknown verb %r in %r" % (verb, s))


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


def pill_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    pid = slugify(name)

    lines = []
    lines.append('[gd_resource type="Resource" script_class="PillData" load_steps=2 '
                 'format=3 uid="uid://pill2_%s"]' % pid)
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/PillData.gd" id="1_pill"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_pill")')
    lines.append('id = &"%s"' % pid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('preference = "%s"' % gd_str(_clean(row.get("Preference")) or "Neutral"))
    lines.append('description = "%s"' % gd_str(_clean(row.get("Description"))))
    lines.append('horse_description = "%s"' % gd_str(_clean(row.get("Horse Description"))))
    lines.append("effect = %s" % gd_value(parse_effect(row.get("Effect"))))
    lines.append("horse_effect = %s" % gd_value(parse_effect(row.get("Horse Effect"))))
    lines.append('notes = "%s"' % gd_str(_clean(row.get("Notes"))))
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
    for row in rows(wb["pills2.0"]):
        pid, text = pill_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (pid, text))
            continue
        with open(os.path.join(OUT_DIR, pid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(pid)
    if not args.list:
        print("Wrote %d pill2.0 .tres to %s" % (len(written), OUT_DIR))
        for p in written:
            print("  -", p)


if __name__ == "__main__":
    main()

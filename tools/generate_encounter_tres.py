#!/usr/bin/env python3
"""
Generate Godot EncounterData .tres files from the `encounters` sheet of
tools/Roguelikes.xlsx.

Mirrors generate_scroll_tres.py: the spreadsheet is the source of truth and the
.tres are produced by this tool. The player-facing PROSE lives in the Description
/ Requirements columns; the structured ops the runtime applies are parsed from the
Effect column, and the gating predicate from the Requirement Effect column.
Adding/editing an encounter is a pure sheet edit (write the prose + the effect
string, rerun) — no generator change unless a new Effect verb is introduced.

  python3 tools/generate_encounter_tres.py            # regenerate every encounter
  python3 tools/generate_encounter_tres.py --list     # print the parse, write nothing

Encounter Effect DSL (one cell = zero or more clauses separated by ';'):
  offer_items <tag> <count> any|one    -> {op:offer_items, tag, count, pick}
  per_item <inner clause>              -> {op:per_item, effect:<parsed inner>}
  lose_hp_pct by_rarity                -> {op:lose_hp_pct, by_rarity:[10,15,20,25,30]}
  lose_hp_pct <N>                      -> {op:lose_hp_pct, value:N}
  add_curse <N>                        -> {op:add_curse, count:N}
  gain_gold <N>                        -> {op:gain_gold, value:N}
  gain_chest [rarity]                  -> {op:gain_chest, rarity?}
  shop <tag> [<tag> ...] [discount=N]  -> {op:shop, pools:[...], discount:N}
  combat <engine> elite                -> {op:combat, engine, elite:true}
  teleport <dir>                       -> {op:teleport, dir}
  teleport choose <dir> <dir> [...]    -> {op:teleport, choose:[dirs]}
  challenge <engine> unconnected attempts=N
                                       -> {op:challenge, engine, pool:"unconnected", attempts:N}
  reward <inner clause>                -> {op:reward, effect:<parsed inner>}
                                          (granted up front when the player
                                           commits to the challenge)
  fail <inner clause>                  -> {op:fail, effect:<parsed inner>}
                                          (applied if the challenge is failed)

Requirement Effect DSL (AND-joined comparisons; empty = no gate):
  <field> <cmp> <int> [and <field> <cmp> <int> ...]
    cmp in >= <= > < == !=            -> [{field, cmp, value}, ...]

A clause/predicate the grammar can't parse aborts that encounter with a loud
warning (no .tres written), so a typo is caught rather than silently dropped.
"""

import argparse
import os
import re
import sys

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "ENCOUNTERS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "encounters")
IMG_DIR = os.path.join(PROJECT_ROOT, "images", "encounters")

ENGINES = ("action", "strategy", "deckbuilder")
TELEPORT_DIRS = ("nearby", "previous", "random", "closer", "farther", "same")
CMPS = (">=", "<=", "==", "!=", ">", "<")
# Deal with the Devil: % of max HP lost per taken item, indexed by item rarity
# (Common / Uncommon / Rare / Epic / Legendary).
BY_RARITY_HP_PCT = [10, 15, 20, 25, 30]


# --------------------------------------------------------------------------
# Effect DSL parser
# --------------------------------------------------------------------------

def parse_effects(text):
    """Parse the Effect cell into a list of effect dicts. Returns None on any
    failure (caller skips the encounter and warns). Empty string yields []."""
    raw = (text or "").strip()
    if raw == "" or raw.lower() == "nothing":
        return []
    effects = []
    for clause in (c.strip() for c in raw.split(";")):
        if not clause:
            continue
        eff = _parse_clause(clause)
        if eff is None:
            return None
        effects.append(eff)
    return effects


def _parse_clause(clause):
    toks = clause.strip().split()
    if not toks:
        return None
    op = toks[0].lower()
    rest = toks[1:]

    if op == "offer_items":
        # offer_items <tag> <count> any|one
        if len(rest) != 3 or not rest[1].isdigit() or rest[2] not in ("any", "one"):
            return None
        return {"op": "offer_items", "tag": rest[0], "count": int(rest[1]), "pick": rest[2]}

    if op == "per_item":
        # per_item <inner clause>
        inner = _parse_clause(" ".join(rest))
        if inner is None:
            return None
        return {"op": "per_item", "effect": inner}

    if op in ("reward", "fail"):
        # reward|fail <inner clause> — challenge buckets. `reward` is granted up
        # front when the player commits to play; `fail` applies on a failed run.
        inner = _parse_clause(" ".join(rest))
        if inner is None:
            return None
        return {"op": op, "effect": inner}

    if op == "lose_hp_pct":
        # lose_hp_pct by_rarity | lose_hp_pct N
        if len(rest) == 1 and rest[0].lower() == "by_rarity":
            return {"op": "lose_hp_pct", "by_rarity": list(BY_RARITY_HP_PCT)}
        if len(rest) == 1 and rest[0].isdigit():
            return {"op": "lose_hp_pct", "value": int(rest[0])}
        return None

    if op == "add_curse":
        if len(rest) != 1 or not rest[0].isdigit():
            return None
        return {"op": "add_curse", "count": int(rest[0])}

    if op == "gain_gold":
        if len(rest) != 1 or not rest[0].isdigit():
            return None
        return {"op": "gain_gold", "value": int(rest[0])}

    if op == "gain_chest":
        # gain_chest [rarity]
        eff = {"op": "gain_chest"}
        if len(rest) == 1:
            eff["rarity"] = rest[0]
        elif len(rest) > 1:
            return None
        return eff

    if op == "shop":
        # shop <tag> [<tag> ...] [discount=N]
        pools = []
        discount = 0
        for t in rest:
            m = re.match(r"^discount=(\d+)$", t)
            if m:
                discount = int(m.group(1))
            elif re.match(r"^[a-z0-9_]+$", t):
                pools.append(t)
            else:
                return None
        if not pools:
            return None
        return {"op": "shop", "pools": pools, "discount": discount}

    if op == "combat":
        # combat <engine> elite
        if len(rest) != 2 or rest[0] not in ENGINES or rest[1] != "elite":
            return None
        return {"op": "combat", "engine": rest[0], "elite": True}

    if op == "teleport":
        # teleport <dir> | teleport choose <dir> <dir> [...]
        if not rest:
            return None
        if rest[0] == "choose":
            dirs = rest[1:]
            if len(dirs) < 2 or any(d not in TELEPORT_DIRS for d in dirs):
                return None
            return {"op": "teleport", "choose": dirs}
        if len(rest) == 1 and rest[0] in TELEPORT_DIRS:
            return {"op": "teleport", "dir": rest[0]}
        return None

    if op == "challenge":
        # challenge <engine> unconnected attempts=N
        if len(rest) != 3 or rest[0] not in ENGINES or rest[1] != "unconnected":
            return None
        m = re.match(r"^attempts=(\d+)$", rest[2])
        if not m:
            return None
        return {"op": "challenge", "engine": rest[0], "pool": "unconnected",
                "attempts": int(m.group(1))}

    return None


# --------------------------------------------------------------------------
# Requirement Effect predicate parser
# --------------------------------------------------------------------------

def parse_requirement(text):
    """Parse the Requirement Effect cell into an AND-list of comparison dicts.
    Returns None on failure; empty string yields []."""
    raw = (text or "").strip()
    if raw == "" or raw.lower() in ("none", "n/a"):
        return []
    conds = []
    for part in re.split(r"\s+and\s+", raw, flags=re.IGNORECASE):
        part = part.strip()
        if not part:
            continue
        cmp = next((c for c in CMPS if c in part), None)
        if cmp is None:
            return None
        lhs, rhs = part.split(cmp, 1)
        field = lhs.strip()
        rhs = rhs.strip()
        if not field or not re.match(r"^-?\d+$", rhs):
            return None
        conds.append({"field": field, "cmp": cmp, "value": int(rhs)})
    return conds


# --------------------------------------------------------------------------
# .tres emission (helpers mirror generate_scroll_tres.py)
# --------------------------------------------------------------------------

def slugify(name: str) -> str:
    s = name.strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


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


def split_tags(raw):
    if not raw:
        return []
    return [t.strip() for t in str(raw).replace(";", ",").split(",") if t.strip()]


def read_rows():
    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    ws = wb["encounters"]
    rows = list(ws.iter_rows(values_only=True))
    header = [str(c).strip() if c is not None else "" for c in rows[0]]
    out = []
    for raw in rows[1:]:
        if raw is None or all(c is None for c in raw):
            continue
        row = {header[i]: raw[i] for i in range(len(header))}
        if not str(row.get("Name") or "").strip():
            continue
        out.append(row)
    return out


def encounter_tres(row):
    name = str(row["Name"]).strip()
    iid = slugify(name)
    etype = str(row.get("Type") or "").strip()
    rarity = str(row.get("Rarity") or "Common").strip()
    description = str(row.get("Description") or "").strip()
    npc = str(row.get("npc") or "").strip()
    reference = str(row.get("Reference") or "").strip()
    requirement = str(row.get("Requirements") or "").strip()
    tags = split_tags(row.get("Tags"))
    img_file = str(row.get("Img") or "").strip() or iid.replace("_", "-")

    effects = parse_effects(row.get("Effect"))
    if effects is None:
        print("  ! could not parse Effect for '%s': %r — skipping" % (
            name, row.get("Effect")), file=sys.stderr)
        return None
    req_effect = parse_requirement(row.get("Requirement Effect"))
    if req_effect is None:
        print("  ! could not parse Requirement Effect for '%s': %r — skipping" % (
            name, row.get("Requirement Effect")), file=sys.stderr)
        return None

    img_res = None
    if os.path.exists(os.path.join(IMG_DIR, img_file + ".png")):
        img_res = "res://images/encounters/%s.png" % img_file

    lines = []
    load_steps = 3 if img_res else 2
    lines.append('[gd_resource type="Resource" script_class="EncounterData" load_steps=%d '
                 'format=3 uid="uid://encounter_%s"]' % (load_steps, iid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/EncounterData.gd" id="1_enc"]')
    if img_res:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img_res)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_enc")')
    lines.append('id = &"%s"' % iid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('type = "%s"' % gd_str(etype))
    lines.append('rarity = "%s"' % gd_str(rarity))
    lines.append('description = "%s"' % gd_str(description))
    lines.append('npc = "%s"' % gd_str(npc))
    lines.append('reference = "%s"' % gd_str(reference))
    if tags:
        lines.append("tags = PackedStringArray(%s)" % ", ".join(gd_value(t) for t in tags))
    lines.append('img = "%s"' % gd_str(img_file))
    if img_res:
        lines.append('image = ExtResource("2_img")')
    lines.append("effects = %s" % gd_value(effects))
    lines.append('requirement = "%s"' % gd_str(requirement))
    lines.append("requirement_effect = %s" % gd_value(req_effect))
    return iid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print the parse, write nothing")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in read_rows():
        res = encounter_tres(row)
        if res is None:
            continue
        iid, text = res
        if args.list:
            print("=== %s ===" % iid)
            print(text)
            continue
        with open(os.path.join(OUT_DIR, iid + ".tres"), "w", encoding="utf-8") as fh:
            fh.write(text)
        written.append(iid)
    if not args.list:
        print("Wrote %d encounter .tres to %s" % (len(written), OUT_DIR))


if __name__ == "__main__":
    main()

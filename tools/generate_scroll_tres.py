#!/usr/bin/env python3
"""
Generate Godot ScrollData .tres files from the `scrolls` sheet of
tools/Roguelikes.xlsx.

Mirrors generate_potion_tres.py: the spreadsheet is the source of truth and the
.tres are produced by this tool. Each scroll has four outcome tiers (Critical
Success / Success / Fail / Critical Fail). The player-facing PROSE lives in the
four original outcome columns; the structured effects the engine applies are
parsed from the four matching "<Tier> Effect" columns. Adding/editing a scroll
is a pure sheet edit (write the prose + the effect string, rerun) — no generator
change.

  python3 tools/generate_scroll_tres.py            # regenerate every scroll
  python3 tools/generate_scroll_tres.py --list     # print the parse, write nothing

ScrollEffect DSL (one outcome = zero or more clauses separated by ';'):
  nothing                                   -> []  (Blank Scroll)
  buff_enemies power N [defense M]          -> {op:buff_enemies, power:N, defense?:M}
  spawn_enemies N weight W                  -> {op:spawn_enemies, count:N, max_weight:W}
  stun_enemies all|choose N|random N        -> {op:stun_enemies, mode, count?}
  identify_scrolls all|choose N|random N    -> {op:identify_scrolls, mode, count?}
  teleport closer N|same|farther N|random   -> {op:teleport, dir, max_steps?:N}
  enchant_weapon choose|random [dmg N] [retain]
                                            -> {op:enchant_weapon, target, dmg?:N, retain?:true}
  vorpalize_weapon choose|random [dmg N]    -> {op:vorpalize_weapon, target, dmg?:N}
  self_damage N [element]                   -> {op:self_damage, value:N, element?}
  damage_enemies N [element]                -> {op:damage_enemies_next, value:N, element?}
  destroy item|scroll|potion N              -> {op:destroy, kind, count:N}
  heal N                                    -> {op:heal, value:N}
  ambush                                    -> {op:ambush}
  gain_status <status> N                    -> {op:gain_status, status, stacks:N}
  forget scroll|potion|spell N|all          -> {op:forget, kind, count:N}  (all -> -1)
  create_food choose N|random N [rarity uncommon+|common]
                                            -> {op:create_food, mode, count:N, rarity?}

A clause the grammar can't parse aborts that scroll with a loud warning (no
.tres written), so a typo is caught rather than silently dropped.
"""

import argparse
import os
import re
import sys

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "SCROLLS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "scrolls")
SCROLL_IMG_DIR = os.path.join(PROJECT_ROOT, "images", "scrolls")

# Maps a sheet outcome column (and its "<col> Effect" sibling) to the engine tier.
TIERS = [
    ("Critical Success", "crit_good"),
    ("Success", "good"),
    ("Fail", "bad"),
    ("Critical Fail", "crit_bad"),
]

DAMAGE_ELEMENTS = {"fire", "ice", "lightning", "poison", "magic", "physical"}


# --------------------------------------------------------------------------
# ScrollEffect DSL parser
# --------------------------------------------------------------------------

def parse_effects(text):
    """Parse an outcome's effect string into a list of effect dicts.

    Returns None if any clause fails (caller skips the scroll and warns). An
    empty/'nothing' string yields []."""
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
    low = clause.strip().lower()
    toks = low.split()
    if not toks:
        return None
    op = toks[0]
    rest = toks[1:]

    if op == "buff_enemies":
        # buff_enemies power N [defense M]
        eff = {"op": "buff_enemies"}
        kv = _keyword_ints(rest, ("power", "defense"))
        if kv is None or "power" not in kv:
            return None
        eff["power"] = kv["power"]
        if "defense" in kv:
            eff["defense"] = kv["defense"]
        return eff

    if op == "spawn_enemies":
        # spawn_enemies N weight W
        m = re.match(r"^spawn_enemies\s+(\d+)\s+weight\s+(\d+)$", low)
        if not m:
            return None
        return {"op": "spawn_enemies", "count": int(m.group(1)),
                "max_weight": int(m.group(2))}

    if op in ("stun_enemies", "identify_scrolls"):
        # <op> all | choose N | random N
        return _parse_mode_count(op, rest)

    if op == "teleport":
        # teleport closer N | same | farther N | random
        if not rest:
            return None
        direction = rest[0]
        if direction not in ("closer", "same", "farther", "random"):
            return None
        eff = {"op": "teleport", "dir": direction}
        if len(rest) >= 2 and rest[1].isdigit():
            eff["max_steps"] = int(rest[1])
        return eff

    if op in ("enchant_weapon", "vorpalize_weapon"):
        # <op> choose|random [dmg N] [retain]
        if not rest or rest[0] not in ("choose", "random"):
            return None
        eff = {"op": op, "target": rest[0]}
        kv = _keyword_ints(rest[1:], ("dmg",), flags=("retain",))
        if kv is None:
            return None
        if "dmg" in kv:
            eff["dmg"] = kv["dmg"]
        if op == "enchant_weapon" and kv.get("retain"):
            eff["retain"] = True
        return eff

    if op in ("self_damage", "damage_enemies"):
        # <op> N [element]
        if not rest or not rest[0].isdigit():
            return None
        out_op = "self_damage" if op == "self_damage" else "damage_enemies_next"
        eff = {"op": out_op, "value": int(rest[0])}
        if len(rest) >= 2:
            if rest[1] not in DAMAGE_ELEMENTS:
                print("  ? element '%s' not in known set — verify." % rest[1],
                      file=sys.stderr)
            eff["element"] = rest[1]
        return eff

    if op == "destroy":
        # destroy item|scroll|potion N
        m = re.match(r"^destroy\s+(item|scroll|potion)\s+(\d+)$", low)
        if not m:
            return None
        return {"op": "destroy", "kind": m.group(1), "count": int(m.group(2))}

    if op == "heal":
        if len(rest) != 1 or not rest[0].isdigit():
            return None
        return {"op": "heal", "value": int(rest[0])}

    if op == "ambush":
        return {"op": "ambush"}

    if op == "gain_status":
        # gain_status <status> N
        if len(rest) != 2 or not rest[1].isdigit():
            return None
        return {"op": "gain_status", "status": rest[0], "stacks": int(rest[1])}

    if op == "forget":
        # forget scroll|potion|spell N|all
        if len(rest) != 2 or rest[0] not in ("scroll", "potion", "spell"):
            return None
        count = -1 if rest[1] == "all" else (int(rest[1]) if rest[1].isdigit() else None)
        if count is None:
            return None
        return {"op": "forget", "kind": rest[0], "count": count}

    if op == "create_food":
        # create_food choose N | random N [rarity uncommon+|common]
        if len(rest) < 2 or rest[0] not in ("choose", "random") or not rest[1].isdigit():
            return None
        eff = {"op": "create_food", "mode": rest[0], "count": int(rest[1])}
        if "rarity" in rest:
            ri = rest.index("rarity")
            if ri + 1 < len(rest):
                eff["rarity"] = rest[ri + 1]
        return eff

    return None


def _parse_mode_count(op, rest):
    """all | choose N | random N -> {op, mode, count?}."""
    if not rest:
        return None
    mode = rest[0]
    if mode == "all":
        return {"op": op, "mode": "all"}
    if mode in ("choose", "random"):
        eff = {"op": op, "mode": mode}
        if len(rest) >= 2 and rest[1].isdigit():
            eff["count"] = int(rest[1])
        return eff
    return None


def _keyword_ints(tokens, int_keys, flags=()):
    """Parse a flat 'key N key N flag' token list into a dict. Ints for int_keys,
    True for bare flags. Returns None on malformed input."""
    out = {}
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in int_keys:
            if i + 1 >= len(tokens) or not tokens[i + 1].isdigit():
                return None
            out[t] = int(tokens[i + 1])
            i += 2
        elif t in flags:
            out[t] = True
            i += 1
        else:
            return None
    return out


# --------------------------------------------------------------------------
# .tres emission (helpers mirror generate_potion_tres.py)
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


def read_rows():
    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    ws = wb["scrolls"]
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


def scroll_tres(row):
    name = str(row["Name"]).strip()
    iid = slugify(name)
    rarity = str(row.get("Rarity") or "Common").strip()
    reference = str(row.get("Reference") or "").strip()
    preference = str(row.get("Preference") or "Neutral").strip()
    img_file = str(row.get("File") or "").strip() or name.replace(" ", "").replace("'", "")

    outcomes = {}
    for prose_col, tier_key in TIERS:
        desc = str(row.get(prose_col) or "").strip()
        effects = parse_effects(row.get(prose_col + " Effect"))
        if effects is None:
            print("  ! could not parse %s Effect for '%s': %r — skipping" % (
                prose_col, name, row.get(prose_col + " Effect")), file=sys.stderr)
            return None
        outcomes[tier_key] = {"description": desc, "effects": effects}

    img_res = None
    if os.path.exists(os.path.join(SCROLL_IMG_DIR, img_file + ".png")):
        img_res = "res://images/scrolls/%s.png" % img_file

    lines = []
    load_steps = 3 if img_res else 2
    lines.append('[gd_resource type="Resource" script_class="ScrollData" load_steps=%d '
                 'format=3 uid="uid://scroll_%s"]' % (load_steps, iid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/ScrollData.gd" id="1_scroll"]')
    if img_res:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img_res)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_scroll")')
    lines.append('id = &"%s"' % iid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('rarity = "%s"' % gd_str(rarity))
    lines.append('reference = "%s"' % gd_str(reference))
    lines.append('preference = "%s"' % gd_str(preference))
    lines.append('file = "%s"' % gd_str(img_file))
    lines.append("outcomes = %s" % gd_value(outcomes))
    return iid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print the parse, write nothing")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in read_rows():
        res = scroll_tres(row)
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
        print("Wrote %d scroll .tres to %s" % (len(written), OUT_DIR))


if __name__ == "__main__":
    main()

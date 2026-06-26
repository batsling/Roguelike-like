#!/usr/bin/env python3
"""
Generate Godot PotionData .tres files from the `potions` sheet of
tools/Roguelikes.xlsx.

Mirrors generate_item_tres.py: the spreadsheet is the source of truth and the
.tres are produced by this tool. The structured `effects` array that the engine
applies is parsed directly from the sheet's prose **Effect** column, so adding a
potion is a pure sheet edit (add a row, rerun) — no generator code change.

  python3 tools/generate_potion_tres.py            # regenerate every potion
  python3 tools/generate_potion_tres.py --list     # print the parse, write nothing

Effect grammar (one potion = one or more clauses separated by ';'):
  Deal N [Magic|Melee|Ranged|True] Dmg [Element] [Cleave]
                                          -> {op:damage, value:N, damage_type, element?}
                                             "Cleave" sets the potion's cleave flag
  Gain +N Block                           -> {op:block, value:N}
  Gain +N Energy                          -> {op:energy, value:N}
  Gain +N Max Health[ and Health]         -> {op:maxhp, value:N}   (raises max AND heals)
  Gain +N <Status> [for M turns]          -> {op:status, status, stacks:N, temporary:M?}
  Inflict N <Status>                       -> {op:status, status, stacks:N}

<Status> is lower-cased to the engine's status id (Power->power, Defense->defense,
Weak->weak, Vulnerable->vulnerable, Thorns->thorns, …). damage_type defaults to
"magic" so damage potions scale with Arcane (Intelligence) like a magic card —
see Stats.resolve_damage. A clause the grammar can't parse aborts that potion
with a loud warning (no .tres written), so a typo is caught rather than guessed.
"""

import argparse
import os
import re
import sys

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "POTIONS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "potions")
POTION_IMG_DIR = os.path.join(PROJECT_ROOT, "images", "potions")

DAMAGE_TYPES = {"magic", "melee", "ranged", "true"}
# Status words the engine understands today (lower-cased). Unknown words still
# emit a status effect but print a review warning so typos surface.
KNOWN_STATUSES = {
    "weak", "vulnerable", "power", "defense", "thorns", "frail", "dodge",
    "bruise", "brace", "poison", "burn", "regeneration", "fear", "stun",
    "buffer", "plated_armor", "blind",
}


# --------------------------------------------------------------------------
# Effect-string parser (the sheet's prose Effect column -> structured effects)
# --------------------------------------------------------------------------

def parse_effects(text):
    """Parse a potion's Effect string into (effects_list, cleave_bool).

    Returns (None, cleave) if any clause fails to parse, so the caller can skip
    the potion and warn rather than emit half-built behaviour.
    """
    raw = (text or "").strip()
    cleave = bool(re.search(r"\bcleave\b", raw, re.I))
    effects = []
    for clause in (c.strip() for c in raw.split(";")):
        if not clause:
            continue
        eff = _parse_clause(clause)
        if eff is None:
            return None, cleave
        effects.append(eff)
    if not effects:
        return None, cleave
    return effects, cleave


def _parse_clause(clause):
    # Strip a trailing area keyword so it doesn't pollute the element capture;
    # the cleave flag is read from the whole string in parse_effects.
    c = re.sub(r"\b(cleave|aoe)\b", "", clause, flags=re.I).strip()
    low = c.lower()

    # Damage: "Deal N [Type] Dmg [Element]"
    m = re.match(r"^deals?\s+(\d+)\s+(?:(\w+)\s+)?(?:dmg|damage)\s*(\w+)?\s*$", low)
    if m and (m.group(2) is None or m.group(2) in DAMAGE_TYPES):
        eff = {"op": "damage", "value": int(m.group(1)),
               "damage_type": m.group(2) or "magic"}
        if m.group(3):
            eff["element"] = m.group(3)
        return eff

    # Specific 'Gain +N <noun>' resources before the generic status rule.
    m = re.match(r"^gain\s+\+?(\d+)\s+block\b", low)
    if m:
        return {"op": "block", "value": int(m.group(1))}
    m = re.match(r"^gain\s+\+?(\d+)\s+energy\b", low)
    if m:
        return {"op": "energy", "value": int(m.group(1))}
    m = re.match(r"^gain\s+\+?(\d+)\s+max\s+health\b", low)
    if m:
        return {"op": "maxhp", "value": int(m.group(1))}

    # Status gain: "Gain +N <Status> [for M turns]" (M defaults to 1).
    m = re.match(r"^gain\s+\+?(\d+)\s+([a-z_]+)(?:\s+for\s+(\d+)?\s*turns?)?\s*$", low)
    if m:
        eff = {"op": "status", "status": _status_id(m.group(2)), "stacks": int(m.group(1))}
        if m.group(3) is not None:
            eff["temporary"] = int(m.group(3))
        elif "for" in low and "turn" in low:
            eff["temporary"] = 1
        return eff

    # Status inflict: "Inflict N <Status>"
    m = re.match(r"^inflict\s+(\d+)\s+([a-z_]+)\s*$", low)
    if m:
        return {"op": "status", "status": _status_id(m.group(2)), "stacks": int(m.group(1))}

    return None


def _status_id(word):
    sid = word.strip().lower()
    if sid not in KNOWN_STATUSES:
        print("  ? status '%s' is not in KNOWN_STATUSES — verify the engine "
              "handles it." % sid, file=sys.stderr)
    return sid


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
    ws = wb["potions"]
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


def potion_tres(row):
    name = str(row["Name"]).strip()
    iid = slugify(name)
    rarity = str(row.get("Rarity") or "Common").strip()
    reference = str(row.get("Reference") or "").strip()
    effect_text = str(row.get("Effect") or "").strip()
    img_file = str(row.get("File") or "").strip() or name.replace(" ", "").replace("'", "")

    effects, cleave = parse_effects(effect_text)
    if effects is None:
        print("  ! could not parse Effect for '%s': %r — skipping (see grammar "
              "in the file header)" % (name, effect_text), file=sys.stderr)
        return None

    img_res = None
    if os.path.exists(os.path.join(POTION_IMG_DIR, img_file + ".png")):
        img_res = "res://images/potions/%s.png" % img_file

    lines = []
    load_steps = 3 if img_res else 2
    lines.append('[gd_resource type="Resource" script_class="PotionData" load_steps=%d '
                 'format=3 uid="uid://potion_%s"]' % (load_steps, iid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/PotionData.gd" id="1_potion"]')
    if img_res:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img_res)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_potion")')
    lines.append('id = &"%s"' % iid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('rarity = "%s"' % gd_str(rarity))
    lines.append('reference = "%s"' % gd_str(reference))
    lines.append('file = "%s"' % gd_str(img_file))
    lines.append('effect_text = "%s"' % gd_str(effect_text))
    lines.append("effects = %s" % gd_value(effects))
    if cleave:
        lines.append("cleave = true")
    return iid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print the parse, write nothing")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in read_rows():
        res = potion_tres(row)
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
        print("Wrote %d potion .tres to %s" % (len(written), OUT_DIR))


if __name__ == "__main__":
    main()

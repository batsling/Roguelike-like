#!/usr/bin/env python3
"""Throwaway parity harness: parse the items sheet -> ItemData in memory,
parse each hand-authored data/items/*.tres, and diff field-by-field.

Splits diffs into gameplay-critical (must be 0 before flip) vs cosmetic.
Run: python3 tools/_item_parity.py [--show id1,id2] [--field triggers]
"""
import argparse, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import openpyxl
import generate_item_tres as G

ROOT = G.PROJECT_ROOT
TDIR = G.OUT_DIR

# ---- parse a hand-authored .tres into a normalized field dict ----

def _gd_to_py(s):
    """Convert a Godot value literal to Python via a JSON-ish massage."""
    s = s.strip()
    if s.startswith("&"):
        s = s[1:]
    if s.startswith("PackedStringArray(") and s.endswith(")"):
        inner = s[len("PackedStringArray("):-1].strip()
        return [x.strip().strip('"') for x in re.findall(r'"[^"]*"', inner)]
    if s in ("true", "false"):
        return s == "true"
    if re.match(r"^-?\d+$", s):
        return int(s)
    if re.match(r"^-?\d+\.\d+$", s):
        return float(s)
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1]
    if s.startswith("[") or s.startswith("{"):
        try:
            return json.loads(s)
        except Exception:
            return s
    return s


def parse_tres(path):
    txt = open(path).read()
    body = txt.split("[resource]", 1)[1]
    fields = {}
    lines = body.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^([a-z_]+) = (.*)$", lines[i])
        if m:
            key, val = m.group(1), m.group(2)
            while val.count("[") + val.count("{") > val.count("]") + val.count("}"):
                i += 1
                val += " " + lines[i].strip()
            fields[key] = _gd_to_py(val)
        i += 1
    fields.pop("script", None)
    fields.pop("image", None)
    return fields


# ---- normalization so semantic equals compare equal ----

DEFAULT_TARGET = "enemy"

def norm_effect(e):
    if not isinstance(e, dict):
        return e
    out = {}
    for k, v in e.items():
        if k == "target" and v == DEFAULT_TARGET:
            continue  # default target omitted
        if k == "notify":
            continue  # cosmetic log string
        if k == "label":
            continue  # cosmetic log string
        if k == "silent":
            continue  # log suppression, not gameplay
        if isinstance(v, dict):
            out[k] = norm_effect(v)
        elif isinstance(v, list):
            out[k] = [norm_effect(x) for x in v]
        else:
            out[k] = v
    return out


def norm_trigger(t):
    out = {}
    for k, v in t.items():
        if k == "silent":
            continue
        if k == "effects":
            out[k] = [norm_effect(x) for x in v]
        else:
            out[k] = v
    return out


def norm_field(key, val):
    if key in ("triggers",):
        return [norm_trigger(t) for t in val]
    if key in ("card_grants",):
        res = []
        for g in val:
            gg = {}
            for k, v in g.items():
                if k in ("effects", "boost"):
                    gg[k] = [norm_effect(x) for x in v]
                else:
                    gg[k] = v
            res.append(gg)
        return res
    if key in ("verification_effects", "perfect_effects"):
        return [norm_effect(x) for x in val]
    if key == "tags":
        return sorted(val) if isinstance(val, list) else val
    return val


# fields that don't affect gameplay parity
COSMETIC_FIELDS = {"description", "source_game", "tags", "display_name",
                   "starts_charged", "current_charge"}
# default values -> treat absent == default
DEFAULTS = {
    "triggers": [], "card_grants": [], "stat_bonuses": {}, "scaling": [],
    "status_amplify": {}, "upgrade_card_types": [], "attack_damage_bonus": {},
    "carries_leftover_energy": False, "lower_hp_damage_mult": 1.0,
    "gold_spend_stat_per": 0, "stat_mirror": {}, "stat_floor": [],
    "negate_lethal": False, "stat_gain_bonus": {}, "reroll_low_rarity": False,
    "charge_cost": 0, "weapon_card_id": "", "verification_question": "",
    "verification_effects": [], "perfect_aware": False, "perfect_effects": [],
    "perfect_save_chance": 0.0, "bonus_level_up_chance": 0.0, "starter": False,
    "max_uses": -1, "kind": 0, "rarity": 0,
}


def get(d, k):
    return d.get(k, DEFAULTS.get(k))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", default="")
    ap.add_argument("--field", default="")
    args = ap.parse_args()
    show = set(x for x in args.show.split(",") if x)

    wb = openpyxl.load_workbook(G.XLSX_PATH, data_only=True)
    sheet = wb["items"]
    existing = {f[:-5] for f in os.listdir(TDIR) if f.endswith(".tres")}
    by_id = {}
    for row in G.rows(sheet):
        iid = G.slugify(str(row["Name"]).strip())
        if iid in existing:
            by_id[iid] = row

    crit_items, cosm_items = 0, 0
    crit_total = 0
    missing = sorted(existing - set(by_id))
    if missing:
        print("NO SHEET ROW for:", missing)

    allkeys = set(DEFAULTS) | COSMETIC_FIELDS | {"id"}
    for iid in sorted(by_id):
        hand = parse_tres(os.path.join(TDIR, iid + ".tres"))
        gen = G.parse_item(by_id[iid])
        # build comparable dicts
        crit = []
        cosm = []
        for key in sorted(allkeys):
            if key == "id":
                continue
            hv = norm_field(key, get(hand, key))
            gv = norm_field(key, get(gen, key))
            if json.dumps(hv, sort_keys=True) == json.dumps(gv, sort_keys=True):
                continue
            (cosm if key in COSMETIC_FIELDS else crit).append((key, hv, gv))
        if crit:
            crit_items += 1
            crit_total += len(crit)
        if cosm:
            cosm_items += 1
        if (show and iid in show) or (crit and not show) or (args.field and any(k == args.field for k, _, _ in crit + cosm)):
            if args.field:
                rows_ = [(k, h, g) for k, h, g in crit + cosm if k == args.field]
            else:
                rows_ = crit
            if rows_:
                print("\n### %s" % iid)
                for k, h, g in rows_:
                    print("  [%s] %s" % ("CRIT" if k not in COSMETIC_FIELDS else "cosm", k))
                    print("    hand: %s" % json.dumps(h, sort_keys=True))
                    print("    gen : %s" % json.dumps(g, sort_keys=True))

    print("\n==== %d items | %d with CRITICAL diffs (%d total) | %d with only cosmetic ====" %
          (len(by_id), crit_items, crit_total, cosm_items))


if __name__ == "__main__":
    main()

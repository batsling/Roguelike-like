#!/usr/bin/env python3
"""
Generate Godot CardData .tres files from the `cardsnew` sheet of
tools/Roguelikes.xlsx.

Mirrors generate_game_tres.py / generate_event_tres.py: the spreadsheet is the
source of truth, the .tres are generated. Parses the colon/semicolon Effects
DSL into the structured `effects` array Godot's EffectSystem consumes, the
Keywords column into the CardData bool flags + addon names, and the curse
trigger tokens (eot:/on_action:/lifecycle:) into CardData.triggers /
destroy_after_games.

Scope: by default only CURSE-type rows are emitted (the curse-cards-first
rollout). Pass --all to attempt every row (the full-catalogue path, which would
overwrite the 34 hand-authored .tres — use with care).

  python3 tools/generate_card_tres.py          # curses only
  python3 tools/generate_card_tres.py --all     # whole sheet

Effects DSL (one card = `clause; clause; ...`):
  on-play (no prefix):  dmg:8:melee | gain:block:5 | inflict:vulnerable:2
  triggered:            eot: inflict:weak:1:self | on_action: lose_hp:1
  lifecycle:            lifecycle: destroy_after:3:games_beaten
Target token `self` (vs default enemy) works on dmg/inflict; the damage-type
tokens (melee/ranged/cleave) are a separate vocabulary so the parser tells them
apart.
"""

import argparse
import json
import os
import re
import sys

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)  # repo root
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "cards")
CARD_IMG_DIR = os.path.join(PROJECT_ROOT, "images", "cards")

# CardData.CardType enum order.
CARD_TYPE = {
    "attack": 0, "skill": 1, "power": 2, "dice": 3,
    "status": 4, "curse": 5, "training": 6,
}
# CardData.Rarity enum order. "None" (curses) has no real tier -> STARTER.
RARITY = {
    "none": 0, "starter": 0, "common": 1, "uncommon": 2, "rare": 3, "legendary": 4,
}

# Keywords column tokens that map onto a CardData bool flag (rest -> addons[]).
FLAG_KEYWORDS = {"exhaust", "ethereal", "innate", "retain", "unplayable", "eternal"}
# Tokens that name a damage type (vs a target) in a dmg clause.
DAMAGE_TYPES = {"melee", "ranged", "cleave"}
TRIGGERS = {"eot", "on_action", "lifecycle"}


def slugify(name: str) -> str:
    s = name.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def parse_cost(raw) -> int:
    s = str(raw).strip().lower()
    if s in ("", "no", "n/a", "none", "x"):
        return -1 if s == "x" else 0
    try:
        return int(float(s))
    except ValueError:
        return 0


def parse_keywords(raw):
    flags = {k: False for k in FLAG_KEYWORDS}
    addons = []
    if not raw:
        return flags, addons
    for tok in str(raw).split(","):
        t = tok.strip()
        if not t:
            continue
        key = t.lower()
        if key in FLAG_KEYWORDS:
            flags[key] = True
        else:
            addons.append(t)
    return flags, addons


def _effect_from_tokens(tokens):
    """verb:arg:arg... -> structured effect dict, or ('destroy_after', n)."""
    if not tokens:
        return None
    verb = tokens[0]
    args = tokens[1:]

    if verb == "inflict":
        status = args[0] if len(args) > 0 else ""
        stacks = int(args[1]) if len(args) > 1 and args[1].isdigit() else 1
        target = "self" if "self" in args[2:] else "enemy"
        return {"type": "status", "status": status, "stacks": stacks, "target": target}

    if verb == "dmg":
        value = int(args[0]) if args and args[0].lstrip("-").isdigit() else 0
        eff = {"type": "dmg", "value": value, "target": "enemy"}
        for a in args[1:]:
            if a == "self":
                eff["target"] = "self"
            elif a in DAMAGE_TYPES:
                eff["damage_type"] = a
        return eff

    if verb == "lose_hp":
        value = int(args[0]) if args and args[0].isdigit() else 1
        eff = {"type": "lose_hp", "value": value}
        if "per_action" in args[1:]:
            eff["per"] = "action"
        elif "per_card_in_hand" in args[1:]:
            eff["per"] = "card_in_hand"
        return eff

    if verb == "conjure":
        card_id = args[0] if len(args) > 0 else "self"
        dest = args[1] if len(args) > 1 else "discard"
        return {"type": "conjure", "card_id": card_id, "destination": dest}

    if verb == "destroy_after":
        n = int(args[0]) if args and args[0].isdigit() else -1
        return ("destroy_after", n)

    # Generic passthrough for simple on-play verbs (block/draw/gain etc.) so the
    # --all path has a fighting chance; refine as the full catalogue is ported.
    if verb == "gain" and len(args) >= 2:
        return {"type": args[0], "value": int(args[1]) if args[1].isdigit() else 0,
                "target": "self"}
    if verb in ("draw", "block", "heal") and args:
        return {"type": verb, "value": int(args[0]) if args[0].isdigit() else 0}

    # Unknown verb -> keep raw so it's visible in the .tres rather than dropped.
    return {"type": verb, "raw": ":".join(tokens)}


def parse_effects(raw):
    """Return (on_play_effects, triggers, destroy_after_games)."""
    on_play = []
    triggers = []
    destroy_after = -1
    if not raw or str(raw).strip().upper() in ("", "N/A", "NONE"):
        return on_play, triggers, destroy_after

    for clause in str(raw).split(";"):
        clause = clause.strip()
        if not clause:
            continue
        trig = None
        # Triggers are authored in DECKBUILDER vocabulary (eot / on_play_other).
        # The action/strategy translators remap them at runtime — the .tres keeps
        # the deckbuilder token so the sheet stays the single source of truth.
        m = re.match(r"^(eot|on_play_other|lifecycle)\s*:\s*(.+)$", clause)
        if m:
            trig, clause = m.group(1), m.group(2).strip()
        eff = _effect_from_tokens([t.strip() for t in clause.split(":") if t.strip()])
        if eff is None:
            continue
        if isinstance(eff, tuple) and eff[0] == "destroy_after":
            destroy_after = eff[1]
            continue
        if trig in ("eot", "on_play_other"):
            triggers.append({"on": trig, "effects": [eff]})
        else:
            on_play.append(eff)
    return on_play, triggers, destroy_after


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def packed_string_array(items) -> str:
    inner = ", ".join('"%s"' % gd_str(i) for i in items)
    return "PackedStringArray(%s)" % inner


def card_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    cid = slugify(name)
    ctype = CARD_TYPE.get(str(row.get("Type", "")).strip().lower(), 0)
    rarity = RARITY.get(str(row.get("Rarity", "")).strip().lower(), 1)
    cost = parse_cost(row.get("Cost"))
    desc = str(row.get("Description") or "").strip()
    tags = [t.strip() for t in str(row.get("Tags") or "").split(",") if t.strip()]
    source = str(row.get("Game") or "").strip()
    if source.upper() in ("", "N/A"):
        source = ""

    # Image: use the Img column when set, else auto-resolve by card name from
    # godot/images/cards/<Name>.png. Curse cards leave Img blank, so most resolve
    # by name (Doubt.png, Decay.png, …); Pride/Greed have no art and stay blank.
    img_raw = str(row.get("Img") or "").strip()
    img_name = img_raw if img_raw and img_raw.upper() != "N/A" else name
    img_res = None
    if os.path.exists(os.path.join(CARD_IMG_DIR, img_name + ".png")):
        img_res = "res://images/cards/%s.png" % img_name

    on_play, triggers, destroy_after = parse_effects(row.get("Effects"))
    flags, addons = parse_keywords(row.get("Keywords"))

    lines = []
    load_steps = 3 if img_res else 2
    lines.append(
        '[gd_resource type="Resource" script_class="CardData" load_steps=%d '
        'format=3 uid="uid://card_%s"]' % (load_steps, cid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/CardData.gd" id="1_card"]')
    if img_res:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img_res)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_card")')
    lines.append("id = &\"%s\"" % cid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append("type = %d" % ctype)
    lines.append("rarity = %d" % rarity)
    lines.append("cost = %d" % cost)
    lines.append('description = "%s"' % gd_str(desc))
    lines.append("effects = %s" % json.dumps(on_play))
    if triggers:
        lines.append("triggers = %s" % json.dumps(triggers))
    if destroy_after >= 0:
        lines.append("destroy_after_games = %d" % destroy_after)
    lines.append("tags = %s" % packed_string_array(tags))
    if source:
        lines.append('source_game = "%s"' % gd_str(source))
    lines.append("can_upgrade = false")
    if img_res:
        lines.append('image = ExtResource("2_img")')
    for flag in sorted(FLAG_KEYWORDS):
        if flags[flag]:
            lines.append("%s = true" % flag)
    if addons:
        lines.append("addons = %s" % packed_string_array(addons))
    return cid, "\n".join(lines) + "\n"


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if not r or r[0] is None:
            continue
        yield dict(zip(headers, r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true",
                    help="emit every row (default: CURSE rows only)")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if "cardsnew" not in wb.sheetnames:
        print("ERROR: 'cardsnew' sheet missing", file=sys.stderr)
        sys.exit(1)
    sheet = wb["cardsnew"]

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in rows(sheet):
        is_curse = str(row.get("Type", "")).strip().lower() == "curse"
        if not args.all and not is_curse:
            continue
        cid, text = card_tres(row)
        with open(os.path.join(OUT_DIR, cid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(cid)

    print("Wrote %d card .tres to %s" % (len(written), OUT_DIR))
    for c in written:
        print("  -", c)


if __name__ == "__main__":
    main()

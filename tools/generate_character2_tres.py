#!/usr/bin/env python3
"""
Generate Godot CharacterData .tres for the games-first redesign (2.0) roster,
from the `characters2.0` sheet of tools/Roguelikes.xlsx into data/characters2.0/.

The 2.0 roster reuses the existing CharacterData resource (extended in place with
the small start_* verb fields) and the project's level-up mechanic
(docs/games-first-redesign.md §3.1). The columns left of `Level Up` are the
character's STARTING loadout; `Level Up` is the per-game honour-system challenge
and `Reward` is what meeting it grants (parsed into level_up_stats +
level_up_reward_type here).

  characters2.0: Name | Game | Health | Gold | Bash | Dash | Push | Transmute |
                 Scramble | Bombs | Keys | Random | Level Up | Reward |
                 Description | Starting items | File

Health -> base_max_hp (a 2.0 run's tiny Health/Max Health reuse hp/max_hp).
Gold -> start_gold, the run's starting purse (§14). It sits beside Health rather
        than inside the verb block on purpose: START_VERBS below and
        GameState.START_RANDOM_POOL both walk Bash..Keys as a contiguous range.
Bash/Dash/Push/Transmute/Scramble/Bombs/Keys -> start_* fields.
Random -> start_random: points of loadout the character does NOT bring fixed,
          rolled across the verb pool at run start (GameState.roll_start_random).
Reward -> level_up_stats (verb / max_hp gains) + level_up_reward_type
          (a sized Chest -> item, with level_up_reward_chest_choices set from
          the size — Small 1 / Medium 2 / Large 3 / Huge 5; Random Sized Chest
          -> random_sized_chest; Scroll -> scroll).
Starting items -> slugged item ids (resolved against data/items2.0/).

Art resolves from the File column (§10.1, matching the enemy/item sheets): the
full portrait from images2.0/characters/Full/<File>.png and the round in-world
icon from images2.0/characters/Icon/<File>.png (case-insensitive). File falls
back to the de-spaced Name for rows that leave it blank. Missing art just leaves
that field unset (placeholder later).

  python3 tools/generate_character2_tres.py            # regenerate the 2.0 roster
  python3 tools/generate_character2_tres.py --list      # print, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "characters2.0")
# Portrait art lives in images2.0/characters/Full/, the round in-world token in
# images2.0/characters/Icon/ (both keyed by the character Name).
CHAR_FULL_DIR = os.path.join(PROJECT_ROOT, "images2.0", "characters", "Full")
CHAR_ICON_DIR = os.path.join(PROJECT_ROOT, "images2.0", "characters", "Icon")


def _png_map(dir_path):
    """Lowercased stem -> actual on-disk PNG stem, so a Name resolves to its art
    case-insensitively (matching the item/enemy generators)."""
    out = {}
    if os.path.isdir(dir_path):
        for fn in os.listdir(dir_path):
            if fn.lower().endswith(".png"):
                out[fn[:-4].lower()] = fn[:-4]
    return out

# start_* verb columns on the sheet -> CharacterData field suffix.
START_VERBS = ["Bash", "Dash", "Push", "Transmute", "Scramble", "Bombs", "Keys"]
# Verbs the level-up Reward may grant, mapped to their GameState/level-up stat key.
REWARD_VERBS = {
    "dash": "dash", "bash": "bash", "push": "push", "transmute": "transmute",
    "scramble": "scramble", "bombs": "bombs", "keys": "keys",
}
# A named chest SIZE -> how many items it offers to choose one from. Mirrors
# Data.CHEST_SIZE_CHOICES; keep the two in step. Ordered biggest-word-first so
# "Large Chest" can't be read as a bare "Chest".
CHEST_SIZE_CHOICES = {"Small": 1, "Medium": 2, "Large": 3, "Huge": 5}


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _int(v, default=0):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def _clean(v):
    """Trim a cell; treat blank / N/A as empty."""
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def _find_amt(s, label):
    """First '+N <label>' amount in the reward string (0 if absent)."""
    m = re.search(r"\+\s*(\d+)\s+" + label, s, re.I)
    return int(m.group(1)) if m else 0


def parse_reward(raw):
    """characters2.0 Reward -> (level_up_stats, reward_type, amount, chest_choices).

    Max Health / verb gains go into level_up_stats (applied by
    GameState.apply_level_up_stats — max_hp both raises the cap and heals). A
    Chest -> the &"item" reward flow, carrying how many items it offers when the
    cell names a SIZE (CHEST_SIZE_CHOICES below, mirroring Data.CHEST_SIZE_CHOICES
    — Small = 1, Large = 3 for Zagreus); a Random Sized Chest -> the
    &"random_sized_chest" flow (the Vampire Survivors characters — the chest's
    SIZE is rolled at runtime, see Data.roll_chest_size_choices); a Scroll -> a
    &"scroll" reward.
    A character whose whole reward is a stat gain has reward_type &"none".
    """
    s = ("" if raw is None else str(raw)).strip()
    stats = {}
    max_hp = _find_amt(s, r"Max Health")
    if max_hp:
        stats["max_hp"] = max_hp
    for verb, key in REWARD_VERBS.items():
        n = _find_amt(s, verb + r"\b")
        if n:
            stats[key] = n
    random_chest = _find_amt(s, r"Random Sized Chest")
    if random_chest:
        return stats, "random_sized_chest", random_chest, 0
    for size, choices in CHEST_SIZE_CHOICES.items():
        n = _find_amt(s, size + r"\s+Chest")
        if n:
            return stats, "item", n, choices
    chest = _find_amt(s, r"Chest")
    if chest:
        return stats, "item", chest, 0
    scroll = _find_amt(s, r"Scroll")
    if scroll:
        return stats, "scroll", scroll, 0
    return stats, "none", 0, 0


def string_name_array(ids) -> str:
    inner = ", ".join('&"%s"' % gd_str(i) for i in ids)
    return "Array[StringName]([%s])" % inner


def character_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    cid = slugify(name)

    items_raw = ("" if row.get("Starting items") is None
                 else str(row.get("Starting items"))).strip()
    items = ([] if not items_raw or items_raw.upper() == "N/A"
             else [slugify(t) for t in items_raw.split(",") if t.strip()])

    level_up_stats, reward_type, reward_amount, chest_choices = parse_reward(
        row.get("Reward"))

    # Art keys off the File column; a blank File falls back to the de-spaced Name
    # (which is what every pre-File row resolved by anyway).
    file = _clean(row.get("File")) or name.replace(" ", "").replace("'", "")
    full_stem = _png_map(CHAR_FULL_DIR).get(file.lower())
    icon_stem = _png_map(CHAR_ICON_DIR).get(file.lower())
    portrait = ("res://images2.0/characters/Full/%s.png" % full_stem) if full_stem else None
    icon = ("res://images2.0/characters/Icon/%s.png" % icon_stem) if icon_stem else None

    ext = ['[ext_resource type="Script" '
           'path="res://scripts/resources/CharacterData.gd" id="1_char"]']
    if portrait:
        ext.append('[ext_resource type="Texture2D" path="%s" id="2_portrait"]' % portrait)
    if icon:
        ext.append('[ext_resource type="Texture2D" path="%s" id="3_icon"]' % icon)

    lines = []
    lines.append(
        '[gd_resource type="Resource" script_class="CharacterData" '
        'load_steps=%d format=3 uid="uid://char2_%s"]' % (len(ext) + 1, cid))
    lines.append("")
    lines.extend(ext)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_char")')
    lines.append('id = &"%s"' % cid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('description = "%s"' % gd_str(row.get("Description")))
    lines.append('source_game = "%s"' % gd_str(row.get("Game")))
    # Health / Max Health reuse hp / max_hp; the 2.0 Health column is both.
    lines.append("base_max_hp = %d" % _int(row.get("Health"), 5))
    # The run's starting purse. Gold is run-scope (never carried between runs),
    # so this column is all a run opens with.
    lines.append("start_gold = %d" % _int(row.get("Gold")))
    # Games-first starting verb loadout.
    lines.append("start_bash = %d" % _int(row.get("Bash")))
    lines.append("start_dash = %d" % _int(row.get("Dash")))
    lines.append("start_push = %d" % _int(row.get("Push")))
    lines.append("start_transmute = %d" % _int(row.get("Transmute")))
    lines.append("start_scramble = %d" % _int(row.get("Scramble")))
    lines.append("start_bombs = %d" % _int(row.get("Bombs")))
    lines.append("start_keys = %d" % _int(row.get("Keys")))
    # Unrolled loadout — spent across the verb pool at run start, not here, so
    # every run of the character opens differently.
    lines.append("start_random = %d" % _int(row.get("Random")))
    lines.append("starting_items = %s" % string_name_array(items))
    lines.append('starting_weapon = &""')
    lines.append('level_up_condition = "%s"' % gd_str(row.get("Level Up")))
    lines.append('level_up_reward = "%s"' % gd_str(row.get("Reward")))
    stat_lines = ",\n".join('"%s": %d' % (k, level_up_stats[k])
                            for k in sorted(level_up_stats))
    if stat_lines:
        lines.append("level_up_stats = {\n%s\n}" % stat_lines)
    else:
        lines.append("level_up_stats = {}")
    lines.append('level_up_reward_type = &"%s"' % reward_type)
    lines.append("level_up_reward_amount = %d" % reward_amount)
    if chest_choices:
        lines.append("level_up_reward_chest_choices = %d" % chest_choices)
    lines.append('file = "%s"' % gd_str(file))
    if portrait:
        lines.append('portrait = ExtResource("2_portrait")')
    if icon:
        lines.append('icon = ExtResource("3_icon")')
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
    for row in rows(wb["characters2.0"]):
        cid, text = character_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (cid, text))
            continue
        with open(os.path.join(OUT_DIR, cid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(cid)
    if not args.list:
        print("Wrote %d character2.0 .tres to %s" % (len(written), OUT_DIR))
        for c in written:
            print("  -", c)


if __name__ == "__main__":
    main()

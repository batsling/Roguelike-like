#!/usr/bin/env python3
"""
Generate Godot GoalEnemyData .tres from the `enemies2.0` sheet of
tools/Roguelikes.xlsx into data/enemies2.0/.

The games-first redesign's goal-enemies (docs/games-first-redesign.md §7) are a
distinct resource from the combat EnemyData — one enemy per game, carrying a
single GOAL (not a stat block). This generator is a pure sheet -> .tres pass.

  enemies2.0: Name | Type | Difficulty | Game | Health | Damage | Goal Type |
              Goal | Ability | File | Tag

Art resolves from File -> res://images2.0/enemies/<File>.png (§10.1); a missing
PNG just leaves the image unset (a placeholder is used at runtime).

  python3 tools/generate_goal_enemy_tres.py            # regenerate every enemy
  python3 tools/generate_goal_enemy_tres.py --list      # print, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
# Source sheet / output / art are module-level so the boss variant
# (tools/generate_boss_tres.py) can reuse this whole generator by repointing them
# and flipping IS_BOSS before calling main().
SHEET_NAME = "enemies2.0"
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "enemies2.0")
ENEMY_IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "enemies")
IMG_RES_PREFIX = "res://images2.0/enemies/"
UID_PREFIX = "goalenemy"
IS_BOSS = False

# GoalEnemyData.Difficulty enum order (LOW, MEDIUM, HIGH, INSANE).
DIFFICULTY = {"low": 0, "medium": 1, "high": 2, "insane": 3}


def _difficulty(raw) -> int:
    """Map a Difficulty cell to the enum int.

    Accepts both the bare label ("High") and the tiered form the sheet now
    uses ("3-High") — the numeric prefix is stripped before lookup.
    """
    s = _clean(raw).lower()
    if "-" in s:
        s = s.split("-", 1)[1].strip()
    return DIFFICULTY.get(s, 0)


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


def _enemy_image_map():
    cache = _enemy_image_map.__dict__.setdefault("cache", None)
    if cache is None:
        cache = {}
        if os.path.isdir(ENEMY_IMG_DIR):
            for fn in os.listdir(ENEMY_IMG_DIR):
                if fn.lower().endswith(".png"):
                    cache[fn[:-4].lower()] = fn[:-4]
        _enemy_image_map.cache = cache
    return cache


def enemy_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    eid = slugify(name)
    file = _clean(row.get("File")) or name.replace(" ", "").replace("'", "")

    img_res = None
    stem = _enemy_image_map().get(file.lower())
    if stem is not None:
        img_res = "%s%s.png" % (IMG_RES_PREFIX, stem)

    ext = ['[ext_resource type="Script" '
           'path="res://scripts/resources/GoalEnemyData.gd" id="1_enemy"]']
    if img_res:
        ext.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img_res)

    lines = []
    lines.append(
        '[gd_resource type="Resource" script_class="GoalEnemyData" '
        'load_steps=%d format=3 uid="uid://%s_%s"]' % (len(ext) + 1, UID_PREFIX, eid))
    lines.append("")
    lines.extend(ext)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_enemy")')
    lines.append('id = &"%s"' % eid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('game_type = &"%s"' % _clean(row.get("Type")).lower())
    lines.append("difficulty = %d" % _difficulty(row.get("Difficulty")))
    if IS_BOSS:
        lines.append("boss = true")
    lines.append('source_game = "%s"' % gd_str(_clean(row.get("Game"))))
    lines.append("health = %d" % _int(row.get("Health"), 1))
    lines.append("damage = %d" % _int(row.get("Damage"), 1))
    lines.append('goal_type = &"%s"' % _clean(row.get("Goal Type")).lower())
    lines.append('goal = "%s"' % gd_str(_clean(row.get("Goal"))))
    ability = _clean(row.get("Ability"))
    if ability:
        lines.append('ability = &"%s"' % slugify(ability))
    tag = _clean(row.get("Tag"))
    if tag:
        lines.append('tag = &"%s"' % tag.lower())
    lines.append('file = "%s"' % gd_str(file))
    if img_res:
        lines.append('image = ExtResource("2_img")')
    return eid, "\n".join(lines) + "\n"


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
    for row in rows(wb[SHEET_NAME]):
        eid, text = enemy_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (eid, text))
            continue
        with open(os.path.join(OUT_DIR, eid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(eid)
    if not args.list:
        print("Wrote %d %s .tres to %s" % (
            len(written), "boss" if IS_BOSS else "goal-enemy", OUT_DIR))
        for e in written:
            print("  -", e)


if __name__ == "__main__":
    main()

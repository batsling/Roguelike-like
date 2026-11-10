#!/usr/bin/env python3
"""
Generate Godot AchievementData .tres from the `achievements` sheet of
tools/Roguelikes.xlsx into data/achievements/ (docs/achievements.md).

  achievements: Tab | Unlocks | Description | Counted | Condition | Goal

  Tab          the tab of the Achievements screen the row is filed under
               (`Characters`). A new name is a new tab.
  Unlocks      what finishing it unlocks. Under `Characters`: a character, by
               name or id, as in the `characters` sheet. Required, and one row
               per character at most.
  Description  the sentence the player reads: what to do.
  Counted      `one run`   it has to happen inside a single run; the best run
                           is remembered
               `all runs`  it adds up across every run
  Condition    what is counted, in the grammar below.
  Goal         how many it takes. A whole number, 1 or more.

CONDITION GRAMMAR — one clause:

  hold <tag>           how many DIFFERENT items and pieces of loot carrying
                       <tag> the run holds at once. `one run` only.
  perfect games        how many games have been perfected. `all runs` only.
  beat games [<type>]  how many DIFFERENT games have been beaten; with a type
                       (action, strategy, deckbuilder, traditional) only games
                       of that type. `all runs` only.

Rows are listed on the screen in sheet order. The output folder is REWRITTEN,
not added to: a row deleted from the sheet takes its achievement with it. Its
README.md is left alone.

  python3 tools/generate_achievement_tres.py          # write data/achievements/*.tres
  python3 tools/generate_achievement_tres.py --list   # print the parse, write nothing
"""

import argparse
import glob
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_tile_tres as base  # noqa: E402  (slugify, gd_str, _clean)

PROJECT_ROOT = base.PROJECT_ROOT
XLSX_PATH = base.XLSX_PATH
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "achievements")
CHARACTERS_DIR = os.path.join(PROJECT_ROOT, "data", "characters2.0")
SHEET = "achievements"

HEADERS = ("Tab", "Unlocks", "Description", "Counted", "Condition", "Goal")

SCOPES = {"one run": "run", "all runs": "lifetime"}
# GameData.GameType, by the name the `games` sheet uses.
GAME_TYPES = ("action", "strategy", "deckbuilder", "traditional")
# metric -> the only way it can be counted.
METRIC_SCOPE = {"tagged_held": "run", "perfects": "lifetime", "games_beaten": "lifetime"}


def _clean(v) -> str:
    return base._clean(v)


def character_ids() -> dict:
    """lower-cased display name AND id -> id for every character."""
    out = {}
    for path in glob.glob(os.path.join(CHARACTERS_DIR, "*.tres")):
        with open(path, encoding="utf-8") as f:
            head = f.read(2048)
        rid = re.search(r'^id = &"([^"]+)"', head, re.M)
        nm = re.search(r'^display_name = "((?:[^"\\]|\\.)*)"', head, re.M)
        if rid:
            out[rid.group(1).lower()] = rid.group(1)
            if nm:
                out[nm.group(1).lower()] = rid.group(1)
    return out


def parse_condition(raw, who: str) -> dict:
    """{"metric", "tag", "game_type"} for a Condition cell, or refused by name."""
    words = _clean(raw).lower().split()
    if len(words) == 2 and words[0] == "hold":
        return {"metric": "tagged_held", "tag": words[1], "game_type": ""}
    if words == ["perfect", "games"]:
        return {"metric": "perfects", "tag": "", "game_type": ""}
    if words[:2] == ["beat", "games"] and len(words) <= 3:
        gtype = words[2] if len(words) == 3 else ""
        if gtype and gtype not in GAME_TYPES:
            raise ValueError("achievements %s: Condition %r — %r is not a game type (%s)"
                             % (who, raw, gtype, ", ".join(GAME_TYPES)))
        return {"metric": "games_beaten", "tag": "", "game_type": gtype}
    raise ValueError("achievements %s: Condition %r must be `hold <tag>`, "
                     "`perfect games` or `beat games [<type>]`" % (who, raw))


def achievement_tres(row: dict, order: int, characters: dict) -> tuple:
    who = _clean(row.get("Unlocks"))
    if not who:
        raise ValueError("achievements: a row has no Unlocks")
    tab = _clean(row.get("Tab")) or "Characters"
    character = ""
    if tab.lower() == "characters":
        character = characters.get(who.lower(), "")
        if not character:
            raise ValueError("achievements %s: no character by that name or id in "
                             "data/characters2.0" % who)
    aid = character or base.slugify(who)
    description = _clean(row.get("Description"))
    if not description:
        raise ValueError("achievements %s: no Description — it is what the player reads" % who)
    counted = _clean(row.get("Counted")).lower()
    if counted not in SCOPES:
        raise ValueError("achievements %s: Counted %r must be `one run` or `all runs`"
                         % (who, row.get("Counted")))
    cond = parse_condition(row.get("Condition"), who)
    if METRIC_SCOPE[cond["metric"]] != SCOPES[counted]:
        raise ValueError("achievements %s: Condition %r can only be counted `%s`"
                         % (who, _clean(row.get("Condition")),
                            "one run" if METRIC_SCOPE[cond["metric"]] == "run" else "all runs"))
    try:
        goal = int(float(_clean(row.get("Goal"))))
    except ValueError:
        raise ValueError("achievements %s: Goal %r is not a number" % (who, row.get("Goal")))
    if goal < 1:
        raise ValueError("achievements %s: Goal must be 1 or more" % who)
    lines = [
        '[gd_resource type="Resource" script_class="AchievementData" load_steps=2 '
        'format=3 uid="uid://ach_%s"]' % aid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/AchievementData.gd" id="1_ach"]',
        "",
        "[resource]",
        'script = ExtResource("1_ach")',
        'id = &"%s"' % aid,
        'tab = "%s"' % base.gd_str(tab),
        "order = %d" % order,
        'unlocks_character = &"%s"' % character,
        'description = "%s"' % base.gd_str(description),
        'scope = "%s"' % SCOPES[counted],
        'metric = "%s"' % cond["metric"],
        'tag = "%s"' % base.gd_str(cond["tag"]),
        'game_type = "%s"' % cond["game_type"],
        "goal = %d" % goal,
    ]
    return aid, "\n".join(lines) + "\n"


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if not r or all(v is None or str(v).strip() == "" for v in r):
            continue
        yield dict(zip(headers, r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run tools/oneshots/_achievements_sheet_setup.py"
                         % (XLSX_PATH, SHEET))
    header = [str(c.value).strip() if c.value is not None else "" for c in wb[SHEET][1]]
    missing = [h for h in HEADERS if h not in header]
    if missing:
        raise SystemExit("achievements: the sheet is missing %s (the columns are %s)"
                         % (" and ".join(missing), " | ".join(HEADERS)))
    characters = character_ids()
    out = {}
    for i, row in enumerate(rows(wb[SHEET])):
        aid, text = achievement_tres(row, (i + 1) * 10, characters)
        if aid in out:
            raise ValueError("achievements: two rows unlock %r — one row each" % aid)
        out[aid] = text

    if args.list:
        for aid, text in out.items():
            print("=== %s ===\n%s" % (aid, text))
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    for stale in glob.glob(os.path.join(OUT_DIR, "*.tres")):
        if os.path.splitext(os.path.basename(stale))[0] not in out:
            os.remove(stale)
    for aid, text in out.items():
        with open(os.path.join(OUT_DIR, aid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
    print("Wrote %d achievements to %s" % (len(out), OUT_DIR))
    for aid in out:
        print("  -", aid)


if __name__ == "__main__":
    main()

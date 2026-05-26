#!/usr/bin/env python3
"""Generate Godot GameData .tres files from the curated JS subgraph.

Reads data/games-data.js, filters to the curated subset below, and writes
one .tres per game into godot/data/games/. Each .tres references the
matching cover image already copied to godot/assets/games/.

Re-run after changing the subset or adding new connections in the JS data.
The output files overwrite existing ones; review the diff after running.
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
JS_PATH = os.path.join(ROOT, "..", "data", "games-data.js")
OUT_DIR = os.path.join(ROOT, "data", "games")
COVER_DIR_REL = "res://assets/games/"
COVER_DIR_FS = os.path.join(ROOT, "assets", "games")

# Curated Phase 1b subgraph: Slay the Spire (start) -> Hades (Amulet)
# via a deckbuilder cluster, action cluster, and bridge games. Order
# here is just for readability; the graph itself is built from the JS
# data's gamesInfluenced field, filtered to this set.
SUBSET = [
    "Slay the Spire", "Inscryption", "Cobalt Core", "Backpack Hero",
    "Dicefolk", "Dungeon Clawler", "Zet Zillions",
    "Astral Ascent", "Spiritfall", "Ember Knights",
    "Cult of the Lamb", "Tiny Rogues", "Death Must Die",
    "Hades II", "Hades",
]

# JS type string -> Godot GameType enum int.
# Enum order in GameData.gd: ACTION=0, STRATEGY=1, DECKBUILDER=2, TRADITIONAL=3
TYPE_MAP = {
    "Action": 0,
    "Strategy": 1,
    "Deckbuilding": 2,
    "Traditional": 3,
    "Roguelike": 1,   # treat Roguelike as Strategy-tagged for now
}

# Cover-image filename per game (lower-kebab matches the existing JS asset).
def slug(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[':\[\]]", "", s)
    s = s.replace(" ", "-")
    return s

# Godot id slug (snake_case; safe for StringName)
def godot_id(name: str) -> str:
    s = name.lower()
    s = re.sub(r"[':\[\]]", "", s)
    s = re.sub(r"\s+", "_", s)
    return s


def load_games():
    with open(JS_PATH) as f:
        text = f.read()
    m = re.search(r"GAMES_DATA\s*=\s*(\[.*\]);", text, re.DOTALL)
    if not m:
        raise SystemExit("Could not locate GAMES_DATA in JS")
    return json.loads(m.group(1))


def emit_tres(game: dict, subset: set, idx: int) -> str:
    name = game["name"]
    gid = godot_id(name)
    cover_filename = f"{slug(name)}.jpg"
    cover_path = os.path.join(COVER_DIR_FS, cover_filename)
    if not os.path.exists(cover_path):
        raise SystemExit(f"Missing cover for {name}: expected {cover_path}")

    influences = [godot_id(x) for x in (game.get("gamesInfluenced") or []) if x in subset]
    influences_literal = (
        "Array[StringName]([" +
        ", ".join(f"&\"{x}\"" for x in influences) +
        "])"
    )

    tags_literal = (
        "PackedStringArray("
        + ", ".join(f'"{t}"' for t in (game.get("tags") or []))
        + ")"
    )

    type_int = TYPE_MAP.get(game.get("type", ""), 2)

    return (
        f'[gd_resource type="Resource" script_class="GameData" load_steps=3 format=3 uid="uid://game_{gid}"]\n'
        f"\n"
        f'[ext_resource type="Script" path="res://scripts/resources/GameData.gd" id="1_game"]\n'
        f'[ext_resource type="Texture2D" path="{COVER_DIR_REL}{cover_filename}" id="2_cover"]\n'
        f"\n"
        f"[resource]\n"
        f'script = ExtResource("1_game")\n'
        f'id = &"{gid}"\n'
        f'display_name = "{name}"\n'
        f'year = {game.get("year", 0)}\n'
        f"type = {type_int}\n"
        f"games_influenced = {influences_literal}\n"
        f"tags = {tags_literal}\n"
        f"enemy_pool = Array[StringName]([])\n"
        f"item_pool = Array[StringName]([])\n"
        f"special_effects = PackedStringArray()\n"
        f'cover_image = ExtResource("2_cover")\n'
    )


def main():
    subset = set(SUBSET)
    games = {g["name"]: g for g in load_games()}
    missing = subset - set(games)
    if missing:
        raise SystemExit(f"Missing from JS data: {missing}")
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for idx, name in enumerate(SUBSET):
        contents = emit_tres(games[name], subset, idx)
        out_path = os.path.join(OUT_DIR, f"{godot_id(name)}.tres")
        with open(out_path, "w") as f:
            f.write(contents)
        written.append(out_path)
    print(f"Wrote {len(written)} GameData .tres files to {OUT_DIR}")
    for p in written:
        print(f"  {os.path.basename(p)}")


if __name__ == "__main__":
    main()

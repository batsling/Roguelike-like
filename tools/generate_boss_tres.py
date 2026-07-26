#!/usr/bin/env python3
"""
Generate Godot GoalEnemyData .tres for the games-first BOSSES, from the
`bosses2.0` sheet of tools/Roguelikes.xlsx into data/bosses2.0/.

Bosses reuse the GoalEnemyData resource (with boss=true) and the exact same
sheet schema as enemies2.0 (docs/games-first-redesign.md §7.1) — they're just a
heavier pool that appears on a difficulty-tier change, deals more damage, and is
bomb-immune. So this is a THIN wrapper over generate_goal_enemy_tres.py: repoint
the sheet, output folder, art folder (images2.0/bosses), and flip IS_BOSS.

  python3 tools/generate_boss_tres.py            # regenerate every boss
  python3 tools/generate_boss_tres.py --list      # print, write nothing
"""

import os

import generate_goal_enemy_tres as base

PROJECT_ROOT = base.PROJECT_ROOT

base.SHEET_NAME = "bosses2.0"
base.OUT_DIR = os.path.join(PROJECT_ROOT, "data", "bosses2.0")
base.ENEMY_IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "bosses")
base.IMG_RES_PREFIX = "res://images2.0/bosses/"
base.UID_PREFIX = "boss"
base.IS_BOSS = True

if __name__ == "__main__":
    base.main()

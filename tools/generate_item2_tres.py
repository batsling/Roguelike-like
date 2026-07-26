#!/usr/bin/env python3
"""
Generate Godot ItemData .tres for the games-first redesign (2.0) items, from the
`items2.0` sheet of tools/Roguelikes.xlsx into data/items2.0/.

This is a THIN wrapper over generate_item_tres.py: the 2.0 items reuse the exact
same Effect-column DSL and ItemData schema (docs/games-first-redesign.md §8.1 —
"reuse the existing item grammar"). We only repoint the source sheet, output
folder, and art folder before delegating to the base generator's emit logic, so
there is a single item-DSL implementation to maintain.

  python3 tools/generate_item2_tres.py          # regenerate every items2.0 row
  python3 tools/generate_item2_tres.py --list    # print the parse, write nothing
"""

import os
import sys

import generate_item_tres as base

PROJECT_ROOT = base.PROJECT_ROOT

# Repoint the base generator at the 2.0 content + parallel data/images folders.
base.SHEET_NAME = "items2.0"
base.OUT_DIR = os.path.join(PROJECT_ROOT, "data", "items2.0")
base.ITEM_IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "items")
base.IMG_RES_PREFIX = "res://images2.0/items/"


def main():
    # The 2.0 sheet is authored fresh, so default to emitting every row (there
    # are no pre-existing .tres to gate on) unless --list is passed.
    if "--all" not in sys.argv and "--list" not in sys.argv:
        sys.argv.append("--all")
    base.main()


if __name__ == "__main__":
    main()

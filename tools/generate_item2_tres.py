#!/usr/bin/env python3
"""
Generate Godot ItemData .tres for the games-first redesign (2.0) items, from the
`items2.0` sheet of tools/Roguelikes.xlsx into data/items2.0/.

A thin wrapper over item_dsl.py, which holds the Effect-column DSL and the
ItemData writer (docs/games-first-redesign.md §8.1 — "reuse the existing item
grammar"), so there is a single item-DSL implementation to maintain.

  python3 tools/generate_item2_tres.py          # regenerate every items2.0 row
  python3 tools/generate_item2_tres.py --list    # print the parse, write nothing
"""

import sys

import item_dsl as base


def main():
    # The 2.0 sheet is authored fresh, so default to emitting every row (there
    # are no pre-existing .tres to gate on) unless --list is passed.
    if "--all" not in sys.argv and "--list" not in sys.argv:
        sys.argv.append("--all")
    base.main()


if __name__ == "__main__":
    main()

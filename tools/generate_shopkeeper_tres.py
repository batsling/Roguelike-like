#!/usr/bin/env python3
"""
Generate Godot ShopkeeperData .tres from the `shopkeepers` sheet of
tools/Roguelikes.xlsx into data/shopkeepers/ (§14.6 of
docs/games-first-redesign.md).

  shopkeepers: Name | Game | Description | Image | Pool | Loot Kinds | Currency |
               Sale | Effect | Item Slots | Loot Slots

  Name         the keeper's name, shown as the shop's title. Required.
  Game         the game they come from (its display name or id), or blank for
               one of this game's own.
  Description  the line under the name in the pop-up.
  Image        portrait base name under images2.0/shopkeepers/ (no extension).
               Blank, or a name with no file yet, shows no portrait.
  Pool         comma-separated item pools or tags the items row draws from
               (`shop`, `food`, `blood`…). Blank: the whole catalog. Each must be
               a pool or tag at least one item carries, or nothing could be drawn.
  Loot Kinds   comma-separated loot kinds the loot row draws from (scroll, pill,
               potion, card, wand, trinket, bag, weapon). Blank: the drop mix.
  Currency     `gold` (blank) or `health`.
  Sale         comma-separated clauses, `<amount> <target>`: amount is -N, +N,
               `half` or `free`; target is `all`, `items`, `loot`, a rarity, a
               loot kind, or an item pool/tag. "-1 loot, half rare". A bare amount
               means `all`.
  Effect       comma-separated free-form rule tokens for rules not built yet.
               Kept as written; nothing reads them until a rule asks.
  Item Slots   how many items on the shelf (blank: 3).
  Loot Slots   how many pieces of loot (blank: 3).

The output folder is REWRITTEN, not added to: a row deleted from the sheet takes
its keeper with it. The folder's README.md is left alone (it is what keeps the
folder in git while the roster is empty).

  python3 tools/generate_shopkeeper_tres.py           # write data/shopkeepers/*.tres
  python3 tools/generate_shopkeeper_tres.py --list    # print the parse, write nothing
"""

import argparse
import glob
import os
import re
import sys

import openpyxl

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_status_tres as dsl  # noqa: E402  (slugify, gd_str, rows)
from generate_song_tres import game_index  # noqa: E402

PROJECT_ROOT = dsl.PROJECT_ROOT
XLSX_PATH = dsl.XLSX_PATH
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "shopkeepers")
ITEMS_DIR = os.path.join(PROJECT_ROOT, "data", "items2.0")
SHEET = "shopkeepers"

HEADERS = ("Name", "Game", "Description", "Image", "Pool", "Loot Kinds",
           "Currency", "Sale", "Effect", "Item Slots", "Loot Slots")

# GameState.LOOT_KINDS, and the rarities loot and items share.
LOOT_KINDS = ("scroll", "pill", "potion", "card", "wand", "trinket", "bag", "weapon")
RARITIES = ("common", "uncommon", "rare", "legendary")
CURRENCIES = ("gold", "health")
DEFAULT_SLOTS = 3


def _clean(v) -> str:
    return dsl._clean(v)


def _list(v) -> list:
    return [t.strip().lower() for t in _clean(v).split(",") if t.strip()]


def item_tags() -> set:
    """Every pool and tag an item carries, read off data/items2.0/*.tres."""
    out = set()
    for path in glob.glob(os.path.join(ITEMS_DIR, "*.tres")):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for m in re.finditer(r'^(?:pools|tags) = PackedStringArray\((.*)\)$', text, re.M):
            out.update(t.lower() for t in re.findall(r'"([^"]+)"', m.group(1)))
    return out


def _slots(raw, what: str, name: str) -> int:
    s = _clean(raw)
    if not s:
        return DEFAULT_SLOTS
    try:
        n = int(float(s))
    except ValueError:
        raise ValueError("shopkeepers %s: %s %r is not a number" % (name, what, raw))
    if n < 0 or n > 9:
        raise ValueError("shopkeepers %s: %s %d is outside 0-9" % (name, what, n))
    return n


def _sale(raw, name: str, tags: set) -> list:
    """Each clause normalised to "<amount> <target>", or refused by name."""
    out = []
    for clause in _list(raw):
        parts = clause.split()
        amount = parts[0]
        target = " ".join(parts[1:]) or "all"
        if not (amount in ("half", "free") or re.fullmatch(r"[+-]\d+", amount)):
            raise ValueError("shopkeepers %s: sale %r — the amount must be -N, +N, "
                             "half or free" % (name, clause))
        known = ("all", "items", "loot") + RARITIES + LOOT_KINDS
        if target not in known and target not in tags:
            raise ValueError("shopkeepers %s: sale %r — %r is not all, items, loot, "
                             "a rarity, a loot kind or an item pool/tag"
                             % (name, clause, target))
        out.append("%s %s" % (amount, target))
    return out


def _packed(values) -> str:
    return "PackedStringArray(%s)" % ", ".join('"%s"' % dsl.gd_str(v) for v in values)


def keeper_tres(row, games: dict, tags: set) -> tuple:
    name = _clean(row.get("Name"))
    if not name:
        raise ValueError("shopkeepers: a row has no Name")
    kid = dsl.slugify(name)

    game_raw = _clean(row.get("Game"))
    game_id = games.get(game_raw.lower(), "") if game_raw else ""
    if game_raw and not game_id:
        raise ValueError("shopkeepers %s: Game %r is not a game in the catalog "
                         "(use its name as the games sheet spells it, or its id)"
                         % (name, game_raw))

    pools = _list(row.get("Pool"))
    for p in pools:
        if p not in tags:
            raise ValueError("shopkeepers %s: Pool %r is no item's pool or tag, so the "
                             "shelf could never stock it" % (name, p))
    kinds = _list(row.get("Loot Kinds"))
    for k in kinds:
        if k not in LOOT_KINDS:
            raise ValueError("shopkeepers %s: Loot Kind %r must be one of %s"
                             % (name, k, ", ".join(LOOT_KINDS)))
    currency = _clean(row.get("Currency")).lower() or "gold"
    if currency not in CURRENCIES:
        raise ValueError("shopkeepers %s: Currency %r must be gold or health"
                         % (name, currency))

    lines = [
        '[gd_resource type="Resource" script_class="ShopkeeperData" load_steps=2 '
        'format=3 uid="uid://shopkeeper_%s"]' % kid,
        "",
        '[ext_resource type="Script" path="res://scripts/resources/ShopkeeperData.gd" '
        'id="1_keeper"]',
        "",
        "[resource]",
        'script = ExtResource("1_keeper")',
        'id = &"%s"' % kid,
        'display_name = "%s"' % dsl.gd_str(name),
        'game_id = &"%s"' % game_id,
        'description = "%s"' % dsl.gd_str(_clean(row.get("Description"))),
        'image = "%s"' % dsl.gd_str(_clean(row.get("Image"))),
        "pools = %s" % _packed(pools),
        "loot_kinds = %s" % _packed(kinds),
        'currency = &"%s"' % currency,
        "sale = %s" % _packed(_sale(row.get("Sale"), name, tags)),
        "effect = %s" % _packed(_list(row.get("Effect"))),
        "item_slots = %d" % _slots(row.get("Item Slots"), "Item Slots", name),
        "loot_slots = %d" % _slots(row.get("Loot Slots"), "Loot Slots", name),
    ]
    return kid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run tools/_shopkeepers_sheet_setup.py"
                         % (XLSX_PATH, SHEET))
    header = [str(c.value).strip() if c.value is not None else "" for c in wb[SHEET][1]]
    missing = [h for h in HEADERS if h not in header]
    if missing:
        raise SystemExit("shopkeepers: the sheet is missing %s (the columns are %s)"
                         % (" and ".join(missing), " | ".join(HEADERS)))
    games = game_index()
    tags = item_tags()
    keepers = {}
    for row in dsl.rows(wb[SHEET]):
        kid, text = keeper_tres(row, games, tags)
        if kid in keepers:
            raise ValueError("shopkeepers: two rows make the id %r — give them "
                             "different names" % kid)
        keepers[kid] = text

    if args.list:
        for kid, text in keepers.items():
            print("=== %s ===\n%s" % (kid, text))
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    for stale in glob.glob(os.path.join(OUT_DIR, "*.tres")):
        if os.path.splitext(os.path.basename(stale))[0] not in keepers:
            os.remove(stale)
    for kid, text in keepers.items():
        with open(os.path.join(OUT_DIR, kid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
    print("Wrote %d shopkeepers to %s" % (len(keepers), OUT_DIR))
    for kid in keepers:
        print("  -", kid)


if __name__ == "__main__":
    main()

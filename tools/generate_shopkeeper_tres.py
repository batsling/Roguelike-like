#!/usr/bin/env python3
"""
Generate Godot ShopkeeperData .tres from the `shopkeepers` sheet of
tools/Roguelikes.xlsx into data/shopkeepers/ (§14.6 of
docs/games-first-redesign.md).

  shopkeepers: Name | Game | Description | Image | Pool | Loot Kinds | Currency |
               Sale | Effect | Item Slots | Loot Slots | Rarity | Boss | Loot Tag |
               Pack Slots

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
  Sale         comma-separated clauses, `[N%] <amount> <target>`: amount is -N,
               +N, `half` or `free`; target is `all`, `items`, `loot`, `packs`, a
               rarity, a loot kind, or an item pool/tag. "-1 loot, half rare". A
               bare amount means `all`. A leading N% makes it a chance per slot,
               rolled on the shelf's first roll only ("10% half").
  Effect       comma-separated rules, from EFFECTS below.
  Item Slots   how many items on the shelf (blank: 3).
  Loot Slots   how many pieces of loot (blank: 3).
  Rarity       Common (blank), Uncommon, Rare or Legendary: the keeper's weight in
               the run's deal (75/20/4/1).
  Boss         the boss a `steal` puts on the board (a bosses2.0 id or name).
  Loot Tag     the tag every piece of loot must carry (`joker`); needs Loot Kinds.
  Pack Slots   card packs on the shelf (blank: 0).

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
           "Currency", "Sale", "Effect", "Item Slots", "Loot Slots", "Rarity",
           "Boss", "Loot Tag", "Pack Slots")

# The rules a keeper's Effect can name (ShopSystem reads each), and whether the
# token takes a number.
EFFECTS = {
    "steal": True,          # steal N gold, once; puts the Boss on the board
    "beaten_sale": True,    # the Boss beaten: every price -N% for the run
    "bombable": False,      # a bomb: nothing / 1-5 gold / a spider / Steam Sale
    "donation_shelf": False,  # shelf size from the Donation Machine's best bank
    "gold_reroll": False,   # rerolls cost 1 gold, +1 each time, not a Scramble
}
BOSSES_DIR = os.path.join(PROJECT_ROOT, "data", "bosses2.0")
CARDS_DIR = os.path.join(PROJECT_ROOT, "data", "cards2.0")

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
    """Each clause normalised to "[N%] <amount> <target>", or refused by name."""
    out = []
    for clause in _list(raw):
        parts = clause.split()
        chance = ""
        if re.fullmatch(r"\d+%", parts[0]):
            chance = parts.pop(0) + " "
            if not parts:
                raise ValueError("shopkeepers %s: sale %r has a chance and no amount"
                                 % (name, clause))
        amount = parts[0]
        target = " ".join(parts[1:]) or "all"
        if not (amount in ("half", "free") or re.fullmatch(r"[+-]\d+", amount)):
            raise ValueError("shopkeepers %s: sale %r — the amount must be -N, +N, "
                             "half or free" % (name, clause))
        known = ("all", "items", "loot", "packs") + RARITIES + LOOT_KINDS
        if target not in known and target not in tags:
            raise ValueError("shopkeepers %s: sale %r — %r is not all, items, loot, "
                             "a rarity, a loot kind or an item pool/tag"
                             % (name, clause, target))
        out.append("%s%s %s" % (chance, amount, target))
    return out


def _effects(raw, name: str) -> list:
    out = []
    for tok in _list(raw):
        parts = tok.split()
        if parts[0] not in EFFECTS:
            raise ValueError("shopkeepers %s: Effect %r must be one of %s"
                             % (name, tok, ", ".join(EFFECTS)))
        if EFFECTS[parts[0]] != (len(parts) == 2 and parts[1].isdigit()):
            raise ValueError("shopkeepers %s: Effect %r %s" % (name, tok,
                             "needs a number" if EFFECTS[parts[0]] else "takes no number"))
        out.append(" ".join(parts))
    return out


def _ids_in(folder: str) -> dict:
    """lower-cased display name AND id -> id for every .tres in `folder`."""
    out = {}
    for path in glob.glob(os.path.join(folder, "*.tres")):
        with open(path, encoding="utf-8") as f:
            head = f.read(2048)
        rid = re.search(r'^id = &"([^"]+)"', head, re.M)
        nm = re.search(r'^display_name = "((?:[^"\\]|\\.)*)"', head, re.M)
        if rid:
            out[rid.group(1).lower()] = rid.group(1)
            if nm:
                out[nm.group(1).lower()] = rid.group(1)
    return out


def card_tags() -> set:
    out = set()
    for path in glob.glob(os.path.join(CARDS_DIR, "*.tres")):
        with open(path, encoding="utf-8") as f:
            m = re.search(r'^tags = PackedStringArray\((.*)\)$', f.read(), re.M)
        if m:
            out.update(t.lower() for t in re.findall(r'"([^"]+)"', m.group(1)))
    return out


def _packed(values) -> str:
    return "PackedStringArray(%s)" % ", ".join('"%s"' % dsl.gd_str(v) for v in values)


def keeper_tres(row, games: dict, tags: set, bosses: dict = None,
                ctags: set = None) -> tuple:
    bosses = bosses if bosses is not None else _ids_in(BOSSES_DIR)
    ctags = ctags if ctags is not None else card_tags()
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

    rarity = (_clean(row.get("Rarity")) or "Common").capitalize()
    if rarity.lower() not in RARITIES:
        raise ValueError("shopkeepers %s: Rarity %r must be one of %s"
                         % (name, rarity, ", ".join(r.capitalize() for r in RARITIES)))
    boss_raw = _clean(row.get("Boss"))
    boss = bosses.get(boss_raw.lower(), "") if boss_raw else ""
    if boss_raw and not boss:
        raise ValueError("shopkeepers %s: Boss %r is not a boss" % (name, boss_raw))
    effects = _effects(row.get("Effect"), name)
    if any(e.split()[0] in ("steal", "beaten_sale") for e in effects) and not boss:
        raise ValueError("shopkeepers %s: steal and beaten_sale need a Boss" % name)
    loot_tag = _clean(row.get("Loot Tag")).lower()
    if loot_tag:
        if kinds != ["card"]:
            raise ValueError("shopkeepers %s: Loot Tag needs Loot Kinds to be card "
                             "(only cards are rolled by tag)" % name)
        if loot_tag not in ctags:
            raise ValueError("shopkeepers %s: no card carries the tag %r" % (name, loot_tag))

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
        "effect = %s" % _packed(effects),
        "item_slots = %d" % _slots(row.get("Item Slots"), "Item Slots", name),
        "loot_slots = %d" % _slots(row.get("Loot Slots"), "Loot Slots", name),
        'rarity = "%s"' % rarity,
        'boss = &"%s"' % boss,
        'loot_tag = "%s"' % dsl.gd_str(loot_tag),
        "pack_slots = %d" % _slots(row.get("Pack Slots") or 0, "Pack Slots", name),
    ]
    return kid, "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit("%s has no %r sheet — run tools/oneshots/_shopkeepers_sheet_setup.py"
                         % (XLSX_PATH, SHEET))
    header = [str(c.value).strip() if c.value is not None else "" for c in wb[SHEET][1]]
    missing = [h for h in HEADERS if h not in header]
    if missing:
        raise SystemExit("shopkeepers: the sheet is missing %s (the columns are %s)"
                         % (" and ".join(missing), " | ".join(HEADERS)))
    games = game_index()
    tags = item_tags()
    bosses = _ids_in(BOSSES_DIR)
    ctags = card_tags()
    keepers = {}
    for row in dsl.rows(wb[SHEET]):
        kid, text = keeper_tres(row, games, tags, bosses, ctags)
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

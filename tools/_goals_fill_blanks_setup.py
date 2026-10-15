#!/usr/bin/env python3
"""One-shot: the `goals` sheet gets the goals and the cells it was missing.

Three gaps, all from the day `goals` was promoted from a view to the source:

1. TWELVE GOALS WERE NOT IN IT. The view had carried the two `locations` goals
   (Burning Basement, Dross); the promotion dropped them because the push had
   nowhere to write them back. The ten `amulets` `Obtain Goals` were never in it
   at all (the view was built while that column was empty). Both are appended
   here, and tools/apply_goals_sheet.py now pushes them like every other owner.
   An amulet row has no name, so its Owner is part + tier ("Body 1-Low").

2. `Type` AND `Difficulty` WERE BLANK on the 33 rows whose owner sheet never
   authored one: every character, status and curse goal (no Difficulty or Goal
   Type column of their own), and the Difficulty of every weapon goal. Filled
   with the five types the bodies already use, judged against the body that asks
   for the same thing where there is one (Erratic Deck = Snecko's Restriction
   2-Medium; Bleed = The Head's 2-Medium; Speed at X=1 is a 3-hour clock, one
   tier under Time Eater's 2 hours). A status's tier is its X=1 tier — it climbs
   with intensity, which the goal text already says.

3. `Tags` WAS BLANK EVERYWHERE. Each goal now carries the theme(s) it is about,
   lowercase and comma-joined like the owner sheets' `Tag`, reusing that
   vocabulary (bug, fire, skeleton, slime, wood, ...) wherever a word already
   existed. Nothing reads them yet; they are what a goal would be matched on.

Only BLANK cells are written, so a value the owner has typed is never replaced
and a second run does nothing.

Run once, then:  python3 tools/apply_goals_sheet.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import openpyxl  # noqa: E402

from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
SHEET, TABLE = "goals", "Table53"

# (Goal, Type, Difficulty, Owner Sheet, Owner, Owner Detail, Relation, Ticked,
#  Count, Tags) — the sheet's own column order.
NEW_ROWS = [
    ("Set 10+ enemies on fire", "Feat", "1-Low", "location", "Burning Basement",
     None, "has", "any time", None, "fire"),
    ("Defeat a stinky enemy", "Bounty", "1-Low", "location", "Dross",
     None, "has", "any time", None, "stinky"),
    ("Get damaged by enemies a lot", "Feat", "1-Low", "amulet", "Body 1-Low",
     None, "has", "game beaten", None, "damage"),
    ("Only take 10 or less damage from enemies", "Restriction", "2-Medium", "amulet",
     "Body 2-Medium", None, "has", "game beaten", None, "damage"),
    ("Take no damage from enemies", "Restriction", "3-High", "amulet", "Body 3-High",
     None, "has", "game beaten", None, "damage"),
    ("End a run with 10 or less items", "Restriction", "1-Low", "amulet", "Cord 1-Low",
     None, "has", "game beaten", None, "item"),
    ("End a run with 11 - 20 items", "Fetch", "2-Medium", "amulet", "Cord 2-Medium",
     None, "has", "game beaten", None, "item"),
    ("End a run with over 20 items", "Fetch", "3-High", "amulet", "Cord 3-High",
     None, "has", "game beaten", None, "item"),
    ("Beat a low tier boss", "Bounty", "1-Low", "amulet", "Decoration 1-Low",
     None, "has", "game beaten", None, "boss"),
    ("Beat a medium tier boss", "Bounty", "2-Medium", "amulet", "Decoration 2-Medium",
     None, "has", "game beaten", None, "boss"),
    ("Beat a high tier boss", "Bounty", "3-High", "amulet", "Decoration 3-High",
     None, "has", "game beaten", None, "boss"),
    ("Beat an insane tier boss", "Bounty", "4-Insane", "amulet", "Decoration 4-Insane",
     None, "has", "game beaten", None, "boss"),
]

# (Owner Sheet, Owner, Owner Detail) -> (Type, Difficulty) for the rows that had
# neither, or only a Type.
TYPE_DIFFICULTY = {
    ("character", "Antonio Belpaese", ""): ("Bounty", "2-Medium"),
    ("character", "Erratic Deck", ""): ("Restriction", "2-Medium"),
    ("character", "Ironclad", ""): ("Feat", "2-Medium"),
    ("character", "Isaac", ""): ("Feat", "2-Medium"),
    ("character", "Manager", ""): ("Fetch", "1-Low"),
    ("character", "Minä", ""): ("Feat", "1-Low"),
    ("character", "Poe Ratcho", ""): ("Feat", "2-Medium"),
    ("character", "Regent", ""): ("Feat", "1-Low"),
    ("character", "Rodney", ""): ("Restriction", "3-High"),
    ("character", "The Makeshift Sisyphus", ""): ("Feat", "2-Medium"),
    ("character", "Zagreus", ""): ("Feat", "2-Medium"),
    ("character", "Zoe", ""): ("Restriction", "3-High"),
    ("status", "Bleed", "on player"): ("Restriction", "2-Medium"),
    ("status", "Burn", "on player"): ("Restriction", "1-Low"),
    ("status", "Marked", "on player"): ("Feat", "1-Low"),
    ("status", "Speed", "on player"): ("Restriction", "2-Medium"),
    ("status", "Strength", "on player"): ("Feat", "2-Medium"),
    ("status", "Dexterity", "on player"): ("Feat", "3-High"),
    ("curse", "Curse of the Bell", ""): ("Feat", "2-Medium"),
    ("curse", "Injury", ""): ("Restriction", "2-Medium"),
    ("curse", "Poor Sleep", ""): ("Restriction", "1-Low"),
    ("weapon", "Earthquake", ""): ("Feat", "2-Medium"),
    ("weapon", "Hero Sword", ""): ("Feat", "1-Low"),
    ("weapon", "Hero Longsword", ""): ("Feat", "1-Low"),
    ("weapon", "Stankus' Toothpick", ""): ("Feat", "1-Low"),
    ("weapon", "Wooden Sword", ""): ("Bounty", "2-Medium"),
    ("weapon", "Lil' Bomber", ""): ("Feat", "2-Medium"),
    ("weapon", "King Bomber", ""): ("Feat", "2-Medium"),
    ("weapon", "Lightning Ring", ""): ("Bounty", "2-Medium"),
    ("weapon", "Thunder Loop", ""): ("Bounty", "2-Medium"),
    ("weapon", "Whip", ""): ("Bounty", "2-Medium"),
    ("weapon", "Bloody Tear", ""): ("Bounty", "2-Medium"),
}

# Owner -> Tags. Keyed by owner (with the phase for Guillatina) because the goal
# text repeats across families (Hero Sword / Hero Longsword) on purpose.
TAGS = {
    ("weapon", "Earthquake"): "rock, ball",
    ("boss", "Steven"): "time",
    ("character", "The Makeshift Sisyphus"): "rock",
    ("character", "Rodney"): "meta progression",
    ("boss", "Resourceful Rat"): "minigame",
    ("status", "Bleed"): "heal",
    ("status", "Burn"): "item",
    ("boss", "Time Eater"): "time",
    ("status", "Marked"): "achievement",
    ("boss", "Lord Bunga"): "cannibal, eat",
    ("enemy", "Stalker"): "stealth",
    ("enemy", "Jabberwock"): "head",
    ("enemy", "Sharky"): "blood",
    ("boss", "Royal Phalanx"): "element, block",
    ("enemy", "Bishop"): "block, ally",
    ("enemy", "Revola"): "body",
    ("boss", "Mom's Heart"): "heart",
    ("enemy", "Spiked Cat"): "glass",
    ("character", "Manager"): "currency",
    ("boss", "The Insatiable"): "eat",
    ("character", "Minä"): "craft, magic",
    ("enemy", "The Obscura"): "illusion",
    ("boss", "Megaera"): "romance",
    ("enemy", "Attack Fly"): "bug",
    ("enemy", "Goblin"): "goblin",
    ("enemy", "Bony"): "undead, skeleton",
    ("enemy", "Spider"): "bug, spider",
    ("boss", "Baby Plum"): "pacifist",
    ("boss", "Giant Spider"): "bug, spider",
    ("enemy", "Child"): "child",
    ("boss", "Trigger Fingers"): "fascist",
    ("enemy", "Pacer"): "head",
    ("enemy", "Gigantic Vermin"): "rodent",
    ("boss", "Lich"): "magic, gun",
    ("enemy", "Atomic Kitten"): "radiation",
    ("enemy", "Robo-Cat"): "robot, animal",
    ("boss", "Guillatina", "phase 3 of 3"): "rot",
    ("enemy", "Skeleton Cat"): "undead, skeleton, animal",
    ("enemy", "Skeleton Warrior"): "undead, skeleton, ball",
    ("enemy", "Skeletal Brute"): "undead, skeleton, ball",
    ("enemy", "Skeletal Bastion"): "undead, skeleton, ball",
    ("boss", "The Beast"): "boss, health",
    ("enemy", "Numbskull"): "body part",
    ("enemy", "Wisp"): "fire",
    ("boss", "Big Chunk"): "rock",
    ("enemy", "Stem Cat"): "clone",
    ("enemy", "Baby Alien"): "alien",
    ("enemy", "Monkey"): "grab",
    ("enemy", "Shelled Parasite"): "food",
    ("enemy", "Spike Slime (L)"): "slime, split",
    ("enemy", "Flaming Hopper"): "fire",
    ("enemy", "Maggot"): "rot",
    ("boss", "Mega Fatty"): "fat",
    ("boss", "Isaac"): "self",
    ("enemy", "Cop Bot"): "police",
    ("enemy", "Doomvas"): "art",
    ("enemy", "Mysterious Tree"): "plant, tree, wood",
    ("boss", "Wallmonger"): "wall",
    ("enemy", "Lil Dave"): "wood",
    ("enemy", "Carcass"): "spawner",
    ("boss", "The Club"): "map",
    ("boss", "The Head"): "heal",
    ("boss", "The Window"): "currency",
    ("boss", "The Goad"): "weapon",
    ("enemy", "Chosen"): "magic",
    ("enemy", "Floating Eye"): "melee",
    ("enemy", "Rust Monster"): "metal, armor",
    ("boss", "Famine"): "food",
    ("boss", "Guillatina", "phase 1 of 3"): "eat",
    ("boss", "Chubs & Nubs"): "stinky, eat",
    ("boss", "Slime Boss"): "slime",
    ("boss", "The One Who Waits"): "religion",
    ("enemy", "Fetus"): "child",
    ("enemy", "Tornado"): "wind",
    ("boss", "Flushmaster"): "water",
    ("enemy", "Ice Slime"): "ice",
    ("enemy", "Chrome Pyramid"): "achievement",
    ("boss", "Trampy"): "alcohol",
    ("character", "Zagreus"): "god",
    ("enemy", "Fungi Beast"): "mushroom, infection",
    ("enemy", "Giggling Minister"): "theft",
    ("boss", "Corrupt Heart"): "ending, difficulty",
    ("boss", "The Man in the Moon"): "moon",
    ("boss", "Lagavulin"): "sleep",
    ("enemy", "Wringer"): "grab",
    ("boss", "Marshmallow"): "infighting",
    ("enemy", "Nemean Chariot"): "vehicle",
    ("status", "Speed"): "time",
    ("status", "Strength"): "difficulty",
    ("status", "Dexterity"): "boss, dodge",
    ("boss", "The Creator"): "god",
    ("character", "Antonio Belpaese"): "vampire",
    ("boss", "Hickory"): "fire, liquid",
    ("character", "Ironclad"): "demon, bargain",
    ("character", "Regent"): "friend",
    ("boss", "Banshee"): "sound",
    ("boss", "Green Banshee"): "sound",
    ("enemy", "Mung"): "fish",
    ("enemy", "Keybullet Kin"): "key",
    ("boss", "Beholster"): "gun",
    ("boss", "Mobius"): "fish",
    ("boss", "The Needle"): "hand",
    ("character", "Zoe"): "perfect",
    ("enemy", "Cultist"): "religion",
    ("boss", "Scylla"): "music",
    ("boss", "Khidr"): "eye",
    ("enemy", "Punch Construct"): "robot, punch",
    ("enemy", "Flaming Fatty"): "fire, push",
    ("boss", "Morana"): "undead",
    ("character", "Erratic Deck"): "random",
    ("enemy", "Host"): "projectile, reflect",
    ("enemy", "Leprechaun"): "theft, currency",
    ("enemy", "Coal Spider"): "rock, fire",
    ("enemy", "Fungun"): "mushroom, gun",
    ("enemy", "Bullat"): "flying",
    ("enemy", "King Bullat"): "flying",
    ("enemy", "Shrinker Beetle"): "size",
    ("boss", "Dragon"): "dragon",
    ("boss", "Throbbing King"): "body part, theft",
    ("enemy", "Gatekeeper"): "soul, theft",
    ("boss", "Charon"): "shop, theft",
    ("character", "Poe Ratcho"): "stinky",
    ("boss", "The Rainmaker"): "water",
    ("boss", "Gremlin Nob"): "taunt",
    ("boss", "Guillatina", "phase 2 of 3"): "body part",
    ("enemy", "Lava Slime"): "lava",
    ("enemy", "Spider Kitten"): "trap",
    ("enemy", "Psychic Horf"): "homing",
    ("boss", "Vantom"): "multi-hit",
    ("character", "Isaac"): "pain, self",
    ("enemy", "Stumpy Stump"): "block",
    ("enemy", "Love Bot"): "robot, heal",
    ("boss", "Cerulean Bell"): "reward",
    ("enemy", "Caveman Woman"): "birth",
    ("boss", "Colossus"): "structure",
    ("enemy", "Transient"): "death",
    ("curse", "Curse of the Bell"): "bell",
    ("curse", "Injury"): "health",
    ("enemy", "Snecko"): "random",
    ("curse", "Poor Sleep"): "rest, heal",
    ("weapon", "Hero Sword"): "hero",
    ("weapon", "Hero Longsword"): "hero",
    ("weapon", "Stankus' Toothpick"): "food",
    ("weapon", "Wooden Sword"): "wood",
    ("weapon", "Lil' Bomber"): "cannon, explosion",
    ("weapon", "King Bomber"): "cannon, explosion",
    ("weapon", "Lightning Ring"): "lightning",
    ("weapon", "Thunder Loop"): "lightning",
    ("weapon", "Whip"): "vampire",
    ("weapon", "Bloody Tear"): "vampire, blood",
}

COLS = "ABCDEFGHIJ"


def s(v):
    return "" if v is None else str(v).strip()


def main() -> int:
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    rows = list(wb[SHEET].iter_rows(values_only=True))
    header = [s(h) for h in rows[0]]
    if header != ["Goal", "Type", "Difficulty", "Owner Sheet", "Owner",
                  "Owner Detail", "Relation", "Ticked", "Count", "Tags"]:
        raise SystemExit("`goals` header moved: %r" % header)

    edits = {}
    have = set()
    last = 1
    for n, row in enumerate(rows[1:], start=2):
        row = list(row) + [None] * (10 - len(row))
        if not s(row[0]):
            continue
        last = n
        sheet, owner, detail = s(row[3]), s(row[4]), s(row[5])
        have.add((sheet, owner))
        td = TYPE_DIFFICULTY.get((sheet, owner, detail))
        if td:
            for col, value in zip("BC", td):
                if not s(row[COLS.index(col)]):
                    edits["%s%d" % (col, n)] = value
        tags = TAGS.get((sheet, owner, detail)) or TAGS.get((sheet, owner))
        if not s(row[9]):
            if tags is None:
                raise SystemExit("goals!%d (%s / %s) has no Tags here — add it"
                                 % (n, sheet, owner))
            edits["J%d" % n] = tags
        if not s(row[1]) and not td:
            raise SystemExit("goals!%d (%s / %s) has no Type and none here" % (n, sheet, owner))

    n = last
    added = 0
    for new in NEW_ROWS:
        if (new[3], new[4]) in have:
            continue
        n += 1
        added += 1
        for col, value in zip(COLS, new):
            if value is not None:
                edits["%s%d" % (col, n)] = value

    if not edits:
        print("`goals` already has everything — skipping")
        return 0
    with Workbook(XLSX) as book:
        book.set_cells(SHEET, edits)
        book.resize_table(TABLE, "A1:J%d" % n)
    print("goals: %d cell(s), %d new row(s), table -> A1:J%d" % (len(edits), added, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())

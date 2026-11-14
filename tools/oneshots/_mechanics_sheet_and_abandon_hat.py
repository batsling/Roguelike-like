#!/usr/bin/env python3
"""One-shot sheet editor: create the `mechanics` sheet, and the Abandon Hat's
achievement row.

MECHANICS (the owner, 14 Nov 2026: "add mechanics sheet that links with the
player mechanics; some players might have a mix"). A player's `Mechanics` cell
on the `players` sheet is a comma list of NAMES from this sheet, any mix of
them; what each one says to the player is its Description here, which used to
be a string in PlayerData.gd. tools/generate_mechanic_tres.py writes the sheet
out, and generate_player_tres.py refuses a player naming a mechanic that has no
row here.

THE ABANDON HAT (docs/customization.md §7) was earned by a rule that lived only
in code. It is a row of `achievements` now, under a new `Hats` tab, so it is
listed, counted and shown like every other achievement.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/oneshots/_mechanics_sheet_and_abandon_hat.py
"""

import os
import re
import sys

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

MECHANICS = [
    ["Name", "Description"],
    ["Hunger",
     "Start with 3 Hunger (at most 5). Each game you finish costs 1. Drink a "
     "potion or eat food for +1. Finish a game or lose a run already at 0 and "
     "lose 2 Health."],
    ["Unidentified Weapons",
     "Weapons you find roll -2 to +2 Stun, unknown until the first swing. A "
     "minus is CURSED: stuck where it sits in the pack until the curse is lifted."],
]
ACHIEVEMENT = ["Hats", "Abandon Hat", "Escape 5 games in a row in one run.",
               "one run", "escape games in a row", 5]


def move_after(wb, name: str, after: str) -> None:
    """Move sheet `name`'s tab to sit right after `after`. add_sheet appends, and
    a tab at the far end of sixty is a tab nobody finds. The workbook has no
    defined names (which count sheets by position), so the only thing that
    counts tabs is the view's activeTab, kept on the sheet it was on."""
    xml = wb._by_name["xl/workbook.xml"].decode("utf-8")
    tabs = re.findall(r"<sheet [^>]*/>", xml)
    names = [re.search(r'name="([^"]*)"', t).group(1) for t in tabs]
    active = re.search(r'activeTab="(\d+)"', xml)
    active_name = names[int(active.group(1))] if active else None
    moved = tabs.pop(names.index(name))
    names.remove(name)
    tabs.insert(names.index(after) + 1, moved)
    names.insert(names.index(after) + 1, name)
    xml = re.sub(r"<sheets>.*?</sheets>", lambda _m: "<sheets>%s</sheets>" % "".join(tabs),
                 xml, count=1, flags=re.S)
    if active_name:
        xml = re.sub(r'activeTab="\d+"', 'activeTab="%d"' % names.index(active_name), xml)
    wb._dirty["xl/workbook.xml"] = wb._by_name["xl/workbook.xml"] = xml.encode("utf-8")


def main():
    with Workbook(XLSX) as wb:
        wb.add_sheet("mechanics")
        wb.write_grid("mechanics", MECHANICS)
        move_after(wb, "mechanics", "players")
        grid = wb.read_grid("achievements")
        if any(r and str(r[1]).strip() == ACHIEVEMENT[1] for r in grid[1:]):
            print("achievements: the Abandon Hat already has a row")
        else:
            rows = [r for r in grid if r and any(str(v).strip() for v in r)]
            wb.write_grid("achievements", rows + [ACHIEVEMENT])
    print("mechanics: created with %d rows; achievements: Abandon Hat added"
          % (len(MECHANICS) - 1))


if __name__ == "__main__":
    main()

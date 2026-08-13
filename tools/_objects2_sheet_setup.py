#!/usr/bin/env python3
"""One-shot sheet editor: give `objects2.0` its schema, and retune the two sheets
that changed shape alongside it (`events2.0`, `items2.0`).

An OBJECT is a machine you stand in front of. It is the same authored shape as an
EVENT — a prompt, a handful of choices, each choice a `;`-separated Effect cell in
the shared reward DSL — with three differences that are the whole point of the
split:

  * an event is a ROOM you are in and then are done with; an object PERSISTS for
    as long as you stand on the game, and ends when you travel on;
  * an event arrives on its own, an object is SPAWNED — by an event (Arcade Room
    puts 2-3 arcade machines in front of you) or by anything else that wants one,
    and several can be in front of you at once;
  * an object is STATEFUL. It can jam, it can be blown up, and the Donation
    Machine's bank outlives the run entirely.

WHAT THIS SCRIPT WRITES

`objects2.0` — widened from the four-column index it was authored as
(`Name | Game | Tag | Image`) to the full event-shaped schema, and the two Isaac
machines authored into it.

`events2.0` — the `Limit` column is DELETED (events no longer cap per run; the
shuffle bag in EventSystem is what stops one repeating), every `Where` value is
BLANKED (events now fire after every game rather than at dead ends — the column
stays for the per-location work later), and the Arcade Room row is completed.

`items2.0` — Effect cells for the three rows authored without one (IV Bag, Blood
Bag, Clover), IV Bag's Type corrected to `Usable, 0` (unlimited uses) and Clover
moved to Uncommon.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run: python3 tools/_objects2_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

MAX_CHOICES = 6

# The schema, in sheet order. Everything up to `Chance Lost` is one cell per
# object; after it come six `Choice N | Repeat N | Result N | Effect N` groups,
# read left to right until a blank `Choice N` — the same rule events2.0 follows.
OBJECT_HEADERS = [
    "Name", "Game", "Tag", "Image",
    # Which pool the object is drawn from when something asks for one by tag,
    # and how many may stand in front of you at once.
    "Rarity", "Limit", "Unique",
    # Reserved: an object placed on the map in its own right, rather than
    # spawned, will gate on these the way an event does. Nothing reads them yet.
    "Where", "Requirement", "Trigger",
    "Prompt", "Chance Won", "Chance Lost",
]
for _n in range(1, MAX_CHOICES + 1):
    OBJECT_HEADERS += ["Choice %d" % _n, "Repeat %d" % _n,
                       "Result %d" % _n, "Effect %d" % _n]


def _row(**cells) -> list:
    """An objects2.0 row from named cells; everything unnamed stays blank."""
    unknown = set(cells) - set(OBJECT_HEADERS)
    if unknown:
        raise KeyError("not objects2.0 columns: %s" % ", ".join(sorted(unknown)))
    return [cells.get(h, "") for h in OBJECT_HEADERS]


# --- the two machines -------------------------------------------------------

# Isaac's blood donation machine, and it keeps Isaac's silence: no prompt, just
# the thing and two buttons. `Give Blood` is the whole object — a health-for-gold
# trade you may take as often as you can pay for it, with a 6.7% chance on each
# press that the machine bursts and pays a relic instead of the coin. That roll is
# the reason to keep pressing, so the odds are on the button (EventSystem's
# `chance` renders both sides of an `else`).
#
# `needs hp 2` rather than `needs hp 1`: at 1 Health the trade is a death, and
# dying to a vending machine on the honour system is not a decision anyone wants
# to have made.
BLOOD_DONATION_MACHINE = _row(
    **{
        "Name": "Blood Donation Machine",
        "Game": "The Binding of Isaac",
        "Tag": "arcade",
        "Image": "BloodDonationMachine",
        "Rarity": "Common",
        "Chance Won": "The machine exploded, and {ITEM} appeared.",
        "Choice 1": "Give Blood",
        "Repeat 1": "Again",
        "Effect 1": ("needs hp 2; lose_hp 1; chance 6.7% -> "
                     "gain_item_of blood_bag|iv_bag; destroy_object "
                     "else gain_gold 1"),
        "Choice 2": "Bomb",
        "Effect 2": ("needs bombs 1; spend_bomb 1; gain_pickups 2-4 hp|gold; "
                     "destroy_object"),
    }
)

# The donation machine banks gold you will never see again — the count is
# PERSISTENT across runs (GameStats), which is the only number in this build that
# outlives a run on purpose. Two rolls ride every coin and they are independent,
# which is why they are `roll` clauses rather than the one headline `chance`:
#
#   5%      the machine thanks you with a point of Luck
#   {1+X}%  it jams, and a jammed machine is jammed for the rest of the run
#
# X is how many coins have already gone in THIS VISIT, so the jam chance climbs
# 1%, 2%, 3%… while you stand there and resets the moment you travel on. Bombing
# pays out of the bank — you can only take what is in it — and takes every
# donation machine off the run, which is the trade: the bank, or the run's
# donation machines.
DONATION_MACHINE = _row(
    **{
        "Name": "Donation Machine",
        "Game": "The Binding of Isaac: Rebirth",
        "Tag": "arcade",
        "Image": "DonationMachine",
        "Rarity": "Common",
        "Unique": "Yes",
        "Choice 1": "Give Gold",
        "Repeat 1": "Again",
        "Effect 1": ("needs gold 1; needs not_jammed; needs bank_space; "
                     "donate_gold 1; roll 5% gain_stat luck 1; "
                     "roll {1+X}% jam_object"),
        "Choice 2": "Bomb",
        "Effect 2": ("needs bombs 1; spend_bomb 1; bank_payout 2-5; "
                     "destroy_object run"),
    }
)

OBJECT_ROWS = [BLOOD_DONATION_MACHINE, DONATION_MACHINE]


# --- the Arcade Room --------------------------------------------------------

# Authored as a stub on the sheet (name, game, tier, requirement) and completed
# here. Entering costs the gold the Requirement checks for, which is what keeps
# it from being a free room: the machines inside want more.
ARCADE_ROOM = {
    "Where": "",
    "Trigger": "After",
    "Rarity": "Common",
    "Image": "ArcadeRoom",
    "Prompt": ("A door you would have walked past stands open on a low room lit "
               "the colour of a bruise. Cabinets line it, humming, most of them "
               "dark. The two that aren't are taking coins."),
    "Choice 1": "Enter",
    "Repeat 1": "Stay",
    "Result 1": ("The coin goes into the slot by the door and the room takes it "
                 "without comment. The machines are yours for as long as you "
                 "care to stand here."),
    "Effect 1": "lose_gold 1; spawn_object tag=arcade 2-3",
    "Choice 2": "Leave",
    "Result 2": "You let the door swing shut behind you.",
    "Effect 2": "nothing",
}


# --- the three items authored without an Effect -----------------------------

# Keyed by the Name cell. `Type` and `Rating` are corrected in the same pass
# where the row needs it.
ITEM_EDITS = {
    "IV Bag": {
        # `Usable, 0` is unlimited — the bag is never used up, which is the whole
        # difference between it and Ride the Bus (`Usable, 1`).
        "Type": "Usable, 0",
        "Effect": "item_used: lose_hp 1; gain_gold 1",
    },
    "Blood Bag": {
        # +2 Max Health and +8 Health. `gain_max_hp` heals by what it adds, so
        # the 8 is authored on top of the 2 the container arrives full with.
        "Effect": "item_acquired: gain_max_hp 2; gain_hp 8",
    },
    "Clover": {
        # Uncommon, not Common: Luck rerolls EVERY roll in the run, so a stacked
        # pair is three rolls at everything and it does not belong on the bottom
        # rung of the ladder.
        "Rating": "Uncommon",
        # A passive bonus rather than `gain_stat luck 1` — the point is that the
        # Luck goes away with the Clover.
        "Effect": "passive: +1 luck",
    },
}


# --- doing it ---------------------------------------------------------------

def _index(headers: list, name: str) -> int:
    try:
        return headers.index(name)
    except ValueError:
        raise KeyError("no %r column (have: %s)" % (name, ", ".join(map(str, headers))))


def write_objects(wb: Workbook) -> None:
    grid = wb.read_grid("objects2.0")
    headers = [str(c) for c in grid[0]]
    # The four columns it was authored with have to survive verbatim — the rows
    # under them are the author's, and this script only widens the sheet.
    for col in ("Name", "Game", "Tag", "Image"):
        _index(headers, col)
    authored = {str(r[_index(headers, "Name")]).strip(): r for r in grid[1:]
                if str(r[_index(headers, "Name")]).strip()}
    rows = []
    for row in OBJECT_ROWS:
        name = row[OBJECT_HEADERS.index("Name")]
        if name not in authored:
            raise KeyError("objects2.0 has no row named %r to widen" % name)
        rows.append(row)
    extra = sorted(set(authored) - {r[OBJECT_HEADERS.index("Name")] for r in rows})
    if extra:
        raise KeyError("objects2.0 rows this script does not author: %s"
                       % ", ".join(extra))
    wb.write_grid("objects2.0", [OBJECT_HEADERS] + rows)
    print("objects2.0: %d columns, %d objects" % (len(OBJECT_HEADERS), len(rows)))


def write_events(wb: Workbook) -> None:
    grid = wb.read_grid("events2.0")
    headers = [str(c) for c in grid[0]]
    limit_at = _index(headers, "Limit")
    where_at = _index(headers, "Where")
    name_at = _index(headers, "Event")

    for row in grid[1:]:
        if not str(row[name_at]).strip():
            continue
        row[where_at] = ""
        if str(row[name_at]).strip() == "Arcade Room":
            for col, value in ARCADE_ROOM.items():
                row[_index(headers, col)] = value

    # Drop `Limit` last, so the lookups above are against the sheet as read.
    out = [[c for i, c in enumerate(r) if i != limit_at] for r in grid]
    wb.write_grid("events2.0", out)
    print("events2.0: dropped Limit, blanked Where, completed Arcade Room")


def write_items(wb: Workbook) -> None:
    grid = wb.read_grid("items2.0")
    headers = [str(c) for c in grid[0]]
    name_at = _index(headers, "Name")
    seen = set()
    for row in grid[1:]:
        name = str(row[name_at]).strip()
        edits = ITEM_EDITS.get(name)
        if edits is None:
            continue
        seen.add(name)
        for col, value in edits.items():
            row[_index(headers, col)] = value
    missing = sorted(set(ITEM_EDITS) - seen)
    if missing:
        raise KeyError("items2.0 has no row for: %s" % ", ".join(missing))
    wb.write_grid("items2.0", grid)
    print("items2.0: %s" % ", ".join(sorted(seen)))


def main() -> None:
    with Workbook(XLSX) as wb:
        write_objects(wb)
        write_events(wb)
        write_items(wb)
    print("wrote %s" % XLSX)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""One-shot: author the `cards` sheet's machine column, and fix two art names.

The `cards` sheet has shipped with Name / Rarity / Description / Effect / Image /
Icon Image since it was written, and the Effect column has been empty on every
row — the prose in Description is what a human reads, and this is what
generate_card2_tres.py reads. Every cell below is docs/cards-design.md §5, which
is the first pass the design reserved for a build session.

Three things it settles, because they are the roster's argument:

  - A CARD IS ONE USE AND NEEDS NO IDENTIFYING (§2), so there is no Preference
    column and nothing here is hidden behind a gamble. What the card does is
    printed on it; the only thing the run withholds is WHICH card a face-down one
    on the floor is, and that is the icon's job rather than an op's.
  - THE THREE DOUBLERS SHARE ONE VERB. 2 of Clubs, 2 of Diamonds and 2 of Hearts
    are the same op three times over — `double_stat <what> [floor=<n>]` — and the
    `floor=` is what "if you have none, gain 2 instead" means. 2 of Hearts
    authors no floor: a run at 0 Health is not a run that gets to read a card.
  - `spawn_object` NAMES THE MACHINE. Temperance is the only card that puts
    something on the page rather than a number in the run, and it asks for the
    Blood Donation Machine by id rather than by tag — an arcade rolls a cabinet,
    a tarot card is a promise about which one you get.

Two Image cells are also corrected, because both name a file that is not on disk
and a card whose art cannot be found is a card that draws nothing:

    V - The Hierophant   VITheHierophant -> VTheHierophant   (VI is The Lovers)
    ? Card               ?Card           -> QuestionMarkCard (a `?` is not a
                                          legal leading character for the art
                                          pipeline, so the file spells it out)

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops the charts on `Map Analysis` (see that module's docstring).
Afterwards, regenerate: python3 tools/generate_card2_tres.py

    python3 tools/_cards_effect_cells.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "cards"
NAME_COL = "Name"
EFFECT_COL = "Effect"
IMAGE_COL = "Image"

# name -> Effect cell, from docs/cards-design.md §5.
EFFECTS = {
    # The one-shot half of the relic that used to carry this rule as a passive.
    "Barricade": "bank_shields_next",
    # Unchanged from the item it replaces — the same op, spent once.
    "Ride the Bus": "teleport_type deckbuilder",
    "V - The Hierophant": "gain_stat bonus_shields 2",
    "VI - The Lovers": "gain_hp 2",
    "IX - The Hermit": "teleport_hub",
    "XIV - Temperance": "spawn_object blood_donation_machine",
    "0 - The Fool": "teleport_start",
    "2 of Clubs": "double_stat bombs floor=2",
    "2 of Diamonds": "double_stat gold floor=2",
    "2 of Hearts": "double_stat hp",
    "Queen of Hearts": "gain_hp 1-20",
    "Ancient Recall": "gain_loot card 3",
    "? Card": "copy_item",
}

# name -> corrected Image cell.
IMAGES = {
    "V - The Hierophant": "VTheHierophant",
    "? Card": "QuestionMarkCard",
}


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(c).strip() for c in grid[0]]
        name_i = headers.index(NAME_COL)
        effect_i = headers.index(EFFECT_COL)
        image_i = headers.index(IMAGE_COL)

        seen = set()
        for row in grid[1:]:
            name = str(row[name_i]).strip()
            if not name:
                continue
            if name not in EFFECTS:
                raise SystemExit("cards row %r has no effect authored here" % name)
            row[effect_i] = EFFECTS[name]
            if name in IMAGES:
                row[image_i] = IMAGES[name]
            seen.add(name)

        missing = sorted(set(EFFECTS) - seen)
        if missing:
            raise SystemExit("authored effects for rows the sheet does not have: %s"
                             % ", ".join(missing))

        wb.write_grid(SHEET, grid)
        print("Wrote %d Effect cells and %d Image fixes to `%s`."
              % (len(seen), len(IMAGES), SHEET))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

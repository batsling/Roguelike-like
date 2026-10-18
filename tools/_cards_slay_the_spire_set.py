#!/usr/bin/env python3
"""One-shot: the machine column for the owner's fifteen Slay the Spire cards
(uploaded 18 Oct 2026), and Trading Card's new wording.

The owner wrote Name / Rarity / Type / Description / Tags / Game / Image / Icon
Image for each card and left Effect blank, as with every card before them; this
writes the Effect cells, in the card grammar (tools/generate_card2_tres.py) for
the fourteen Usables and the relic grammar for After Image, the one Passive.

The rulings the owner gave while these were authored (18 Oct 2026):

  - "This row" (Fiend Fire, Second Wind) is the card's row in the PACK, and a
    card played off the floor has none, so it destroys nothing.
  - Cleave's "a row" is a lane of the BOARD, and the player picks it.
  - Destroying loot TRASHES it: it goes on the run's destroyed pile and a
    destroyed card pays Trading Card — so Trading Card says "destroying" now.
  - Exhume brings back ANY destroyed piece, and the player picks it.
  - Prepared: the player picks the two, and it can be played with fewer.
  - Bloodletting and Offering's Health CAN be the Health that ends the run.
  - A charge fills a bar to its top and no further.
  - Finisher and Stack count each OTHER card used this game, copies included,
    so their lines say "other" now.
  - Bullseye's Marked is the existing status.

Three typos in the owner's prose are fixed on the way: "Destory" (Prepared) and
"Chargabe" (Bloodletting, Offering).

Through _xlsx_surgery rather than openpyxl: a round-trip of this workbook
silently drops its charts (see that module's docstring). Afterwards, regenerate:
python3 tools/generate_card2_tres.py

    python3 tools/_cards_slay_the_spire_set.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "cards"

# name -> {column: value}
EDITS = {
    "After Image": {"Effect": "card_used: gain_stat shields 1"},
    "Alchemize": {"Effect": "gain_loot potion 1"},
    "Bloodletting": {
        "Description": "Lose 2 Health and Give 4 Charges to a Chargeable Item or Loot",
        "Effect": "lose_hp 2; charge_pick 4",
    },
    "Bullseye": {"Effect": "stun 1; apply_status marked 1"},
    "Cleave": {"Effect": "stun 1 area=row"},
    "Exhume": {"Effect": "exhume"},
    "Fiend Fire": {"Effect": "destroy_row; stun 1 per=destroyed"},
    "Finisher": {
        "Description": "Apply Stun 1 for each other Card used during this game",
        "Effect": "stun 1 per=cards_used",
    },
    "Offering": {
        "Description": "Lose 6 Health, Give 4 Charges to a Chargeable Item or Loot, and Gain +3 Random Cards",
        "Effect": "lose_hp 6; charge_pick 4; gain_loot card 3",
    },
    "Pommel Strike": {"Effect": "stun 1; gain_loot card 1"},
    "Prepared": {
        "Description": "Destroy 2 Loot and Gain +2 Random Cards",
        "Effect": "destroy_pick 2; gain_loot card 2",
    },
    "Reaper": {"Effect": "stun 1 area=board; gain_hp 1 per=hit"},
    "Second Wind": {"Effect": "destroy_row; gain_stat shields 2 per=destroyed"},
    "Shrug it Off": {"Effect": "gain_stat shields 1; gain_loot card 1"},
    "Stack": {
        "Description": "Gain +1 Temporary Shield for each other Card used this game",
        "Effect": "gain_stat shields 1 per=cards_used",
    },
    "Trading Card": {
        "Description": "Once per game, Gain +2 Gold when destroying a card",
    },
}


def main() -> int:
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        headers = [str(c).strip() for c in grid[0]]
        name_i = headers.index("Name")
        seen = set()
        for row in grid[1:]:
            name = str(row[0] if row else "").strip()
            if name not in EDITS:
                continue
            while len(row) < len(headers):
                row.append("")
            for column, value in EDITS[name].items():
                row[headers.index(column)] = value
            seen.add(name)
            assert row[name_i] == name
        missing = sorted(set(EDITS) - seen)
        if missing:
            raise SystemExit("not on the cards sheet: %s" % ", ".join(missing))
        wb.write_grid(SHEET, grid)
        print("Wrote %d rows of `%s`." % (len(seen), SHEET))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

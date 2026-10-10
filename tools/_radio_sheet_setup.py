#!/usr/bin/env python3
"""One-shot sheet editor: create the `radio` sheet for ROGUELIKE RADIO
(docs/roguelike-radio.md).

One row per song. The audio itself is the owner's own music and NEVER lives in
the repo: `File` is the name of the file in the player's radio folder on their
own PC (`user://radio/`), and a row whose file is not there simply shows as
"file not found" in game. Everything else about the song — what it is called,
what it unlocks on, its art — is authored here, like every other piece of
content.

Columns:

    Name     the song's title
    Artist   who made it
    Album    optional
    Year     optional
    Game     the game it is tied to and unlocks on (its display name, or its id)
    Unlock   `goals` — goal-enemies beaten at that game, or
             `wins`  — times that game has been reported beaten.
             Blank keeps the song LOCKED (owner's rule, not a default to "free")
    Count    how many of them it takes
    File     the exact file name in the radio folder (.mp3, .ogg or .wav)
    Image    album art base name under images2.0/radio/ (blank = the game's cover)
    Tags     comma-separated; each tag is a station the radio can be tuned to

One example row is written so the sheet is not blank; delete it freely.

WHY XML SURGERY AND NOT openpyxl: see tools/_xlsx_surgery.py.

Run once: python3 tools/_radio_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "radio"

HEADERS = ["Name", "Artist", "Album", "Year", "Game", "Unlock", "Count",
           "File", "Image", "Tags"]

EXAMPLE = ["No Escape", "Darren Korb", "Hades Original Soundtrack", 2020,
           "Hades", "wins", 1, "Hades - No Escape.mp3", "", "boss, intense"]


def main():
    with Workbook(XLSX) as wb:
        wb.add_sheet(SHEET)
        wb.write_grid(SHEET, [HEADERS, EXAMPLE])
    print("radio: created with %d columns and one example row" % len(HEADERS))


if __name__ == "__main__":
    main()

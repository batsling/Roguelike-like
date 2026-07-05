#!/usr/bin/env python3
"""
Add the Barricade / Envenom / Evolve / Feel No Pain / Fire Breathing /
Well-Laid Plans Power cards to `cardsnew` and their backing statuses to
`statusesnew` in tools/Roguelikes.xlsx.

The card descriptions are reworded from the legacy `cards` sheet's
"Gain Barricade." style to say what the power actually does — the wording
comes from the legacy `statuses` sheet, which kept the mechanical text.
Powers are NOT statuses in the sheet: the mechanical text lives in the
card's Description and the Effects column is ordinary parsable DSL —
`on_<event>:<inner>` triggers (Envenom, Evolve, Feel No Pain, Fire
Breathing, Well-Laid Plans) or the bare `keep_block` verb (Barricade),
consumed generically by the scenes' power_triggers. In combat a played
power still badges on the status strip with icons from
images/powericons/<Img>Power.png (same Img as the card art) and the card
description as its tooltip — that's presentation, not a statusesnew row,
so this script also REMOVES any legacy power rows from statusesnew.

Idempotent: any existing cardsnew row with a matching Name is replaced in
place, and the statusesnew removals are skipped when already gone. Extends
each sheet's Excel Table range to cover appended rows. Re-run
tools/generate_card_tres.py and tools/import-reference-godot.py afterwards.
"""

import os
import openpyxl
from openpyxl.styles import Alignment

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
XLSX_PATH = os.path.join(SCRIPT_DIR, "Roguelikes.xlsx")

# cardsnew columns: Name, Rarity, Type, Cost, Description, Effects,
# ↑ Description, ↑ Effects, ↑ Cost, Attack, Img, Game, Keywords, Element, Tags
CARD_ROWS = {
    "Barricade": [
        "Barricade", "Rare", "Power", 3,
        "Block is not removed at the start of your turn.",
        "keep_block",
        "Block is not removed at the start of your turn.",
        "keep_block",
        2, "N/A", "Barricade", "Slay the Spire", "N/A", "N/A",
        "ironclad, defense, block",
    ],
    "Envenom": [
        "Envenom", "Rare", "Power", 2,
        "Whenever you deal unblocked Attack Dmg, Inflict 1 Poison.",
        "on_unblocked_attack:inflict:poison:1",
        "Whenever you deal unblocked Attack Dmg, Inflict 1 Poison.",
        "on_unblocked_attack:inflict:poison:1",
        1, "N/A", "Envenom", "Slay the Spire", "N/A", "N/A",
        "silent, poison, offense",
    ],
    "Evolve": [
        "Evolve", "Uncommon", "Power", 1,
        "Whenever you Draw a Status Card, Draw 1 Card.",
        "on_status_drawn:draw:1",
        "Whenever you Draw a Status Card, Draw 2 Cards.",
        "on_status_drawn:draw:2",
        1, "N/A", "Evolve", "Slay the Spire", "N/A", "N/A",
        "ironclad, draw, status",
    ],
    "Feel No Pain": [
        "Feel No Pain", "Uncommon", "Power", 1,
        "Whenever a Card is Exhausted, Gain 3 Block.",
        "on_card_exhausted:gain:block:3",
        "Whenever a Card is Exhausted, Gain 4 Block.",
        "on_card_exhausted:gain:block:4",
        1, "N/A", "FeelNoPain", "Slay the Spire", "N/A", "N/A",
        "ironclad, defense, exhaust",
    ],
    "Fire Breathing": [
        "Fire Breathing", "Uncommon", "Power", 1,
        "Whenever you Draw a Status or Curse Card, Deal 6 Magic Dmg to ALL Enemies.",
        "on_status_or_curse_drawn:dmg:6:magic:cleave",
        "Whenever you Draw a Status or Curse Card, Deal 10 Magic Dmg to ALL Enemies.",
        "on_status_or_curse_drawn:dmg:10:magic:cleave",
        1, "N/A", "FireBreathing", "Slay the Spire", "N/A", "N/A",
        "ironclad, offense, aoe, status",
    ],
    "Well-Laid Plans": [
        "Well-Laid Plans", "Uncommon", "Power", 1,
        "At the end of your turn, choose up to 1 Card in your hand to Retain.",
        "on_turn_ended:retain:1",
        "At the end of your turn, choose up to 2 Cards in your hand to Retain.",
        "on_turn_ended:retain:2",
        1, "N/A", "Well-LaidPlans", "Slay the Spire", "N/A", "N/A",
        "silent, draw, retain",
    ],
}

# Powers must NOT sit in statusesnew — they're cards, not statuses. An earlier
# pass of this script added rows for them; strip any that are present.
STATUS_ROWS_TO_REMOVE = [
    "Barricade", "Envenom", "Evolve",
    "Feel No Pain", "Fire Breathing", "Well-Laid Plans",
]


def _name_to_row(ws):
    out = {}
    for r in range(2, ws.max_row + 1):
        v = ws.cell(row=r, column=1).value
        if v is not None and str(v).strip() != "":
            out[str(v).strip()] = r
    return out


def _bump_table_ref(ws, new_max_row):
    for name in ws.tables:
        t = ws.tables[name]
        start, end = t.ref.split(":")
        end_col = "".join(c for c in end if c.isalpha())
        t.ref = f"{start}:{end_col}{new_max_row}"


def upsert(ws, rows: dict, wrap_cols: set):
    existing = _name_to_row(ws)
    for name, values in rows.items():
        target = existing.get(name, ws.max_row + 1)
        for ci, val in enumerate(values, start=1):
            cell = ws.cell(row=target, column=ci, value=val)
            if ci in wrap_cols:
                cell.alignment = Alignment(vertical="top", wrap_text=True)
        action = "updated" if name in existing else "added"
        print(f"  {action}: {ws.title}!{name} (row {target})")
    _bump_table_ref(ws, ws.max_row)


def remove_rows(ws, names: list) -> None:
    existing = _name_to_row(ws)
    doomed = sorted([existing[n] for n in names if n in existing], reverse=True)
    for r in doomed:
        ws.delete_rows(r)
    for n in names:
        if n in existing:
            print(f"  removed: {ws.title}!{n}")
    if doomed:
        _bump_table_ref(ws, ws.max_row)


def main() -> int:
    wb = openpyxl.load_workbook(XLSX_PATH)  # keep formulas/tables
    upsert(wb["cardsnew"], CARD_ROWS, wrap_cols={5, 7})
    remove_rows(wb["statusesnew"], STATUS_ROWS_TO_REMOVE)
    wb.save(XLSX_PATH)
    print("[add_power_rows] saved; re-run generate_card_tres.py --all and "
          "import-reference-godot.py next")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

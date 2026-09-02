#!/usr/bin/env python3
"""One-shot: settle the `chart` sheet's System vocabulary, and trim its cells.

The System column had grown four singular/plural pairs — `Bomb`/`Bombs`,
`Tile`/`Tiles`, `Object`/`Objects`, `Pill`/`Pills`. A group-by over that column
**does not error** on them; it silently renders each as two systems, splits
their inbound arrows between the halves, and drops both out of the supersystem
view because neither half joins the Groups tree cleanly. See
`docs/systems-graph.md` §6.

Plural wins, for two reasons: it is already the majority (Enemies, Statuses,
Goals, Shields, Potions, Cards, Stats), and the Groups tree — stored as three
named Excel Tables on column W — spells every leaf plural (`Items`, `Pills`,
`Bombs`, `Cards`, `Potions`, `Scrolls`, `Wands`). Normalising the System column
to plural is what makes those two vocabularies join.

`Item` -> `Items` is included even though it never collided *within* the System
column, because it is the same bug across the two vocabularies: the tree says
`Items` and the column said `Item`, so the Collectables branch could never have
matched it.

**`Node Type` is deliberately left singular.** It is a different vocabulary
answering a different question — "this row IS an Item" versus "this arrow points
AT the Items system" — and `Otainable`'s qualified refs (`Item: Landmines`) key
off Node Type, not off the System column.

Also trims leading/trailing whitespace from every cell on the sheet, and renames
the one Event node `Arcade` -> `Arcade Room`. The `events` sheet
has always called it Arcade Room, and the `Otainable` references were updated to
`Event: Arcade Room` in the last revision — leaving the node row behind, so all
three references dangled.

Uses `replace_cells`, not `write_grid`: the chart sheet carries five tables and
`write_grid` resizes only the first one it finds. See that method's docstring.

    python3 tools/_chart_system_vocabulary.py [--dry-run]

Idempotent — a second run reports nothing to do.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook, col_name  # noqa: E402

BOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "chart"

# 0-based indices of the four `System n` columns (D, H, L, P).
SYSTEM_COLUMNS = [3, 7, 11, 15]

PLURAL = {
    "Bomb": "Bombs",
    "Tile": "Tiles",
    "Object": "Objects",
    "Pill": "Pills",
    "Item": "Items",
}

# (0-based column, old, new) one-off cell renames.
RENAMES = [(0, "Arcade", "Arcade Room")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="report the edits without writing the workbook")
    args = ap.parse_args()

    with Workbook(BOOK) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(v).strip() for v in grid[0]]
        for i in SYSTEM_COLUMNS:
            if not header[i].startswith("System"):
                raise SystemExit(
                    "column %s is %r, not a System column — the sheet's shape "
                    "changed and this script's column map is stale"
                    % (col_name(i), header[i]))

        edits = {}
        for r, row in enumerate(grid[1:], start=2):
            for i in SYSTEM_COLUMNS:
                value = str(row[i]).strip() if i < len(row) else ""
                if value in PLURAL:
                    edits["%s%d" % (col_name(i), r)] = PLURAL[value]
            for i, old, new in RENAMES:
                if i < len(row) and str(row[i]).strip() == old:
                    edits["%s%d" % (col_name(i), r)] = new
            # Trim stray padding everywhere on the sheet. `Teleport Start Game `
            # carried a trailing space in BOTH the arrow (E3) and the Good Dir
            # lookup (U50), so the join worked and nothing complained — but
            # tidying either cell on its own would have silently uncoloured the
            # arrow. Fixing both together is the only safe order, which is why
            # this is one pass over the whole grid rather than a manual edit.
            for i, value in enumerate(row):
                text = str(value)
                if text and text != text.strip():
                    edits.setdefault("%s%d" % (col_name(i), r), text.strip())

        if not edits:
            print("nothing to do — the vocabulary is already settled")
            return 0

        for ref, value in sorted(edits.items(), key=lambda kv: (kv[0][0], int(kv[0][1:]))):
            print("  %-5s -> %s" % (ref, value))
        print("%d cell(s)" % len(edits))

        if args.dry_run:
            # Nothing was marked dirty, and __exit__ only rewrites the zip when
            # something is — so returning here leaves the workbook untouched.
            print("dry run — workbook not written")
            return 0
        wb.replace_cells(SHEET, edits)
    print("written to %s" % BOOK)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

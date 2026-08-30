#!/usr/bin/env python3
"""One-shot sheet editor: drop the redundant "+1 Health" from Rodney's level-up
reward.

His cell read "Gain +1 Max Health, +1 Health, and +1 Loot", which listed the same
point of Health twice: `GameState.apply_level_up_stats` heals a max_hp gain by the
amount it granted (`change_max_hp` then `change_hp`), so raising the cap already
hands over the Health. The second clause promised a second point that was never
paid, and it is the only reward line on the roster that spells the heal out.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once, then regenerate:

    python3 tools/_characters_rodney_maxhealth_setup.py
    python3 tools/generate_character2_tres.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

EDITS = {
    "characters": ("Name", {
        "Rodney": {"Reward": "Gain +1 Max Health and +1 Loot"},
    }),
}

REQUIRED = {"characters": ["Reward"]}


def main() -> None:
    written = []
    with Workbook(XLSX) as wb:
        for sheet, (key_col, rows) in EDITS.items():
            grid = wb.read_grid(sheet)
            headers = [str(h).strip() for h in grid[0]]
            for col in REQUIRED[sheet] + [key_col]:
                if col not in headers:
                    raise SystemExit("%s has no %r column." % (sheet, col))
            key_at = headers.index(key_col)
            seen = set()
            for row in grid[1:]:
                if not row or key_at >= len(row) or row[key_at] is None:
                    continue
                name = str(row[key_at]).strip()
                if name not in rows:
                    continue
                for col, value in rows[name].items():
                    at = headers.index(col)
                    while len(row) <= at:
                        row.append("")
                    row[at] = value
                    written.append((sheet, name, col, value))
                seen.add(name)
            missing = set(rows) - seen
            if missing:
                raise SystemExit("%s: no row named %s"
                                 % (sheet, ", ".join(sorted(missing))))
            wb.write_grid(sheet, grid)

    for sheet, name, col, value in written:
        print("%-12s %-8s %-8s %s" % (sheet, name, col, value))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Fill the `Proof` column on the `connections` sheet from images2.0/proof/.

The game reads a connection's proof off disk, as
`images2.0/proof/<influencer id>---<influenced id>.png`, so the sheet on its own
never said which rows had one. This writes that file name into column F of each
row that has one and leaves the cell blank on each row that doesn't — so
filtering `Proof` for blanks gives the same list as `docs/proof-missing.md`.

The column is a VIEW of the folder, not an input: nothing reads it back
(`import-games-godot.py` stops at Source, column E), so typing into it does
nothing and the next run overwrites it. Re-run after adding proofs:

    python3 tools/proof_column.py           # rewrite the column
    python3 tools/proof_column.py --check   # exit 1 if it is out of date

A row whose name doesn't resolve to a game in data/games/ is left blank and
reported (the same names `import-games-godot.py` skips).

Through `_xlsx_surgery.set_cells` rather than openpyxl, which drops the
workbook's charts, and rather than `write_grid`, which regenerates every cell:
only column F is touched.
"""

import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
GAMES = os.path.join(ROOT, "data", "games")
PROOF = os.path.join(ROOT, "images2.0", "proof")

SHEET = "connections"
HEADERS = ["Influencer", "Influencee", "Influencer Time", "Dev/Series Relation",
           "Source", "Proof"]
COL = "F"
WIDTH = 60


def _game_ids():
    """display_name -> id, exact and lower-cased, the way the importer resolves."""
    exact, lower = {}, {}
    for path in glob.glob(os.path.join(GAMES, "*.tres")):
        with open(path, encoding="utf-8") as f:
            m = re.search(r'^display_name = "((?:[^"\\]|\\.)*)"', f.read(), re.M)
        if not m:
            continue
        name = m.group(1).replace('\\"', '"').replace("\\\\", "\\")
        gid = os.path.splitext(os.path.basename(path))[0]
        exact[name] = gid
        lower.setdefault(name.lower(), gid)
    return exact, lower


def main():
    check = "--check" in sys.argv[1:]
    exact, lower = _game_ids()
    proofs = {f for f in os.listdir(PROOF) if f.endswith(".png")}

    def resolve(name):
        name = str(name or "").strip()
        return exact.get(name) or lower.get(name.lower())

    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        if header[:5] != HEADERS[:5]:
            raise SystemExit("connections headers are %r, expected %r — the sheet's "
                             "shape moved; update this script" % (header, HEADERS[:5]))

        edits, unresolved, have = {}, set(), 0
        if (header[5] if len(header) > 5 else "") != "Proof":
            edits["%s1" % COL] = "Proof"
        for r, row in enumerate(grid[1:], start=2):
            row = list(row) + [""] * (6 - len(row))
            a, b = str(row[0] or "").strip(), str(row[1] or "").strip()
            want = ""
            if a and b:
                a_id, b_id = resolve(a), resolve(b)
                if a_id is None or b_id is None:
                    unresolved.add(a if a_id is None else b)
                else:
                    name = "%s---%s.png" % (a_id, b_id)
                    if name in proofs:
                        want, have = name, have + 1
            if str(row[5] or "").strip() != want:
                edits["%s%d" % (COL, r)] = want

        total = sum(1 for row in grid[1:] if str(row[0] or "").strip())
        print("connections: %d of %d rows have a proof; %d cell(s) %s"
              % (have, total, len(edits), "out of date" if check else "written"))
        for name in sorted(unresolved):
            print("  not a game in data/games/: %r" % name)

        if check:
            wb._dirty.clear()
            raise SystemExit(1 if edits else 0)
        if not edits:
            return

        wb.set_cells(SHEET, edits)
        last = len(grid)
        wb.grow_table(SHEET, HEADERS, "%s%d" % (COL, last))
        # Give the new column a readable width; E is 189 wide and F would
        # otherwise open at the sheet default of ~9.
        part, _ = wb.sheet_parts(SHEET)
        xml = wb._dirty[part].decode("utf-8")
        if '<col min="6"' not in xml:
            xml = xml.replace("</cols>", '<col min="6" max="6" width="%d" customWidth="1"/></cols>'
                              % WIDTH, 1)
        xml = re.sub(r'spans="1:5"', 'spans="1:6"', xml)
        wb._dirty[part] = xml.encode("utf-8")


if __name__ == "__main__":
    main()

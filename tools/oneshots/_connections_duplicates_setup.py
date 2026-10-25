#!/usr/bin/env python3
"""One-shot: delete the four connection rows that are exact copies of the row above.

Balatro -> Driving Rogue, Balatro -> Insider Trading, Baroque -> Kernel Hearts
and Balatro -> Lexispell came in once on 18 Sep 2026 (d532ab3e) and a second
time in the 23 Sep upload (5d73bbf9), every cell the same. The importer and
RunGraph already count each pair once, so the game never saw them twice; the
sheet's own figures (Connections, Average degree, the four games' Degree) did.

The sheet has per-cell styles and 1006 hyperlinks, so `write_grid` (which
rewrites cells from values) would strip both. This deletes the rows in the
XML instead: each later row, its cells and its hyperlink move up, a deleted
row's own hyperlink and its relationship go, and Table2's ranges shrink.
Every other sheet reads `connections` by whole column or by its header row
(`tools/map_calc.py`), so nothing outside it needs moving.

It refuses to run unless every row it deletes is cell for cell the row above
it (apart from the row number), so a rerun, or a sheet that has moved since,
changes nothing.

    python3 tools/oneshots/_connections_duplicates_setup.py
"""

# Moved to tools/oneshots/ on 25 Oct 2026. Resolve paths as if this still sat in
# tools/ (where it was written and run), with both folders importable.
import os as _os, sys as _sys
_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
__file__ = _os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),
                         _os.path.basename(__file__))

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "connections"
# The second of each pair, as the sheet stood after the 22 Oct 2026 upload.
DUPLICATES = {427: "Balatro -> Driving Rogue", 687: "Balatro -> Insider Trading",
              714: "Baroque -> Kernel Hearts", 753: "Balatro -> Lexispell"}

ROW = re.compile(r'<row r="(\d+)"([^>]*)>(.*?)</row>', re.S)


def cells_without_refs(body):
    return re.sub(r'(<c r=")[A-Z]+\d+(")', r"\1\2", body)


def new_number(n):
    """Where row n lands once the duplicates are gone (None for a duplicate)."""
    if n in DUPLICATES:
        return None
    return n - sum(1 for d in DUPLICATES if d < n)


def main():
    with Workbook(XLSX) as wb:
        part, tables = wb.sheet_parts(SHEET)
        xml = wb._by_name[part].decode("utf-8")
        rows = {int(n): (a, b) for n, a, b in ROW.findall(xml)}
        for n, what in DUPLICATES.items():
            if n not in rows or n - 1 not in rows or \
                    cells_without_refs(rows[n][1]) != cells_without_refs(rows[n - 1][1]):
                wb._dirty.clear()
                sys.exit("row %d is not a copy of row %d (%s): nothing changed" % (n, n - 1, what))
        last = max(rows)

        def move_row(m):
            n = int(m.group(1))
            to = new_number(n)
            if to is None:
                return ""
            body = re.sub(r'(<c r="[A-Z]+)\d+(")', lambda c: "%s%d%s" % (c.group(1), to, c.group(2)),
                          m.group(3))
            return '<row r="%d"%s>%s</row>' % (to, m.group(2), body)

        xml = ROW.sub(move_row, xml)

        # Hyperlinks: a deleted row's goes with its relationship; the rest move up.
        gone = []

        def move_link(m):
            col, n = m.group(2), int(m.group(3))
            to = new_number(n)
            if to is None:
                gone.append(re.search(r'r:id="([^"]+)"', m.group(0)).group(1))
                return ""
            return "%s%s%d%s" % (m.group(1), col, to, m.group(4))

        xml = re.sub(r'(<hyperlink ref=")([A-Z]+)(\d+)("[^>]*/>)', move_link, xml)
        new_last = new_number(last)
        xml = re.sub(r'<dimension ref="A1:([A-Z]+)\d+"/>',
                     lambda m: '<dimension ref="A1:%s%d"/>' % (m.group(1), new_last), xml)
        # The saved view pointed at the old bottom rows; open at the top instead.
        xml = re.sub(r' topLeftCell="[A-Z]+\d+"', "", xml)
        xml = re.sub(r'<selection [^>]*/>', '<selection activeCell="A2" sqref="A2"/>', xml)
        wb._dirty[part] = xml.encode("utf-8")

        rels = part.replace("worksheets/", "worksheets/_rels/") + ".rels"
        rx = wb._by_name[rels].decode("utf-8")
        for rid in gone:
            rx = re.sub(r'<Relationship Id="%s"[^>]*/>' % re.escape(rid), "", rx)
        wb._dirty[rels] = rx.encode("utf-8")

        for t in ([tables] if isinstance(tables, str) else tables or []):
            tx = wb._by_name[t].decode("utf-8")
            tx = re.sub(r'(ref="[A-Z]+\d+:[A-Z]+)%d"' % last, r"\g<1>%d" % new_last + '"', tx)
            wb._dirty[t] = tx.encode("utf-8")
    print("deleted %d duplicate rows (%s); %d hyperlink(s) with them; the sheet now ends at row %d"
          % (len(DUPLICATES), ", ".join(DUPLICATES.values()), len(gone), new_last))


if __name__ == "__main__":
    main()

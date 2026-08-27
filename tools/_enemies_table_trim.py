#!/usr/bin/env python3
"""One-shot: trim the `enemies` table off the empty column it claims.

Excel has been reporting "Repaired Records: Table from /xl/tables/table5.xml"
on every open of Roguelikes.xlsx. That part is Table34, the `enemies` table, and
it has been wrong since long before the table it sits next to was touched — it is
not fallout from _xlsx_surgery, whose damage was table12 on `scrolls`.

WHAT IS WRONG: the table declares `ref="A1:M51"` and thirteen columns, the
thirteenth of which is `name=""`. A tableColumn name must be non-empty, so Excel
repairs the part (silently renaming that column) every time the file is opened
and reports it as damage.

WHY TRIM RATHER THAN NAME IT: column M of `enemies` is empty — no header, and
`<c r="M…">` appears nowhere in the sheet. The table is simply one column wider
than the data it wraps. Naming the phantom would satisfy the validator and leave
a column called "Column13" in the authoring UI forever; taking the table back to
A1:L51 is what the sheet actually means. `read_grid` measures the same 12 columns
off the cells, so after this the module and the workbook agree — before it, a
future `write_grid("enemies", …)` would have silently resized the table anyway.

Nothing references Table34: no formula, defined name or chart in the workbook
mentions it, so there are no structured references to break.

The autoFilter is resized with the table (Excel keeps the two identical); the
sortState was already `A2:L51` and is left alone.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run once: python3 tools/_enemies_table_trim.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook, audit  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "enemies"
WAS, NOW = "A1:M51", "A1:L51"


def main() -> None:
    with Workbook(XLSX) as wb:
        _part, tables = wb.sheet_parts(SHEET)
        if len(tables) != 1:
            raise SystemExit("%s carries %d tables; this one-shot expects one."
                             % (SHEET, len(tables)))
        table = tables[0]
        xml = wb.part(table)

        # Guarded on the exact shape being fixed, so a workbook that has since been
        # repaired by hand is left alone rather than trimmed a second time.
        if 'ref="%s"' % WAS not in xml:
            raise SystemExit("%s is not at %s any more — already fixed?"
                             % (os.path.basename(table), WAS))
        last = re.search(r'<tableColumn id="13" name="([^"]*)"/>', xml)
        if last is None or last.group(1) != "":
            raise SystemExit("column 13 is not the unnamed one this fixes.")

        xml = xml.replace('ref="%s"' % WAS, 'ref="%s"' % NOW)
        xml = xml.replace('<tableColumn id="13" name=""/>', "")
        xml = xml.replace('<tableColumns count="13">', '<tableColumns count="12">')
        wb.set_part(table, xml)
        print("%s: %s -> %s, 13 columns -> 12" % (os.path.basename(table), WAS, NOW))

    left = audit(XLSX)
    for line in left:
        print(line)
    print("%d table problem(s) left" % len(left))


if __name__ == "__main__":
    main()

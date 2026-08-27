#!/usr/bin/env python3
"""Edit one sheet of tools/Roguelikes.xlsx without destroying the rest of it.

openpyxl cannot round-trip this workbook: loading and saving it silently drops
the eight charts on `Map Analysis` and anything else openpyxl does not model. So
the sheet-editing one-shots here read the .xlsx as the zip it is, rewrite only
the parts that describe one sheet (`xl/worksheets/sheetN.xml` and, where the
sheet has exactly one, its `xl/tables/tableN.xml`), and copy every other entry
through byte-for-byte.

Usable ONLY on sheets that are plain value grids — no formulas, no per-cell
styles — because `write_grid` regenerates the whole `<sheetData>` from values.
`read_grid` refuses a sheet with formulas so that stays honest rather than
becoming a silent data loss the next time someone points this at `Map Calc`.

    from _xlsx_surgery import Workbook
    with Workbook("tools/Roguelikes.xlsx") as wb:
        grid = wb.read_grid("items")
        grid.append(["Oddly Smooth Stone", "Common", ...])
        wb.write_grid("items", grid)

Nothing is written until the context manager exits cleanly, so a parse error
part-way through leaves the workbook untouched.

A SHEET CAN CARRY MORE THAN ONE TABLE, and `scrolls` does — three, in three
column blocks. Resizing is only meaningful when one table spans the sheet, so a
multi-table sheet keeps every table exactly as it is and refuses a grid that
would change its shape. `audit()` (also `python3 tools/_xlsx_surgery.py`) checks
every table in a workbook against the rules Excel enforces on open; run it after
a one-shot, because Excel reports a broken table as "Removed Part" days later
and names only a tableN.xml.
"""

import os
import re
import shutil
import zipfile

_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

# Stands in for a `name=` match that isn't there, so a malformed tableColumn reads
# as unnamed (and gets a name) rather than raising out of a list comprehension.
_BLANK = re.match(r"()", "")


def col_name(idx: int) -> str:
    """0-based column index -> spreadsheet letter (0 -> A, 26 -> AA)."""
    name = ""
    idx += 1
    while idx:
        idx, rem = divmod(idx - 1, 26)
        name = chr(ord("A") + rem) + name
    return name


def _esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Workbook:
    def __init__(self, path: str):
        self.path = path
        self._entries = []      # [(ZipInfo, bytes)] in original order
        self._by_name = {}
        self._dirty = {}        # filename -> new bytes
        self._shared = []

    # --- lifecycle --------------------------------------------------------

    def __enter__(self):
        with zipfile.ZipFile(self.path) as zf:
            for info in zf.infolist():
                data = zf.read(info.filename)
                self._entries.append((info, data))
                self._by_name[info.filename] = data
        self._shared = self._read_shared_strings()
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None or not self._dirty:
            return False
        tmp = self.path + ".tmp"
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
            for info, data in self._entries:
                out.writestr(info, self._dirty.get(info.filename, data))
        shutil.move(tmp, self.path)
        return False

    def _read_shared_strings(self) -> list:
        raw = self._by_name.get("xl/sharedStrings.xml")
        if raw is None:
            return []
        text = raw.decode("utf-8")
        out = []
        for si in re.findall(r"<si>(.*?)</si>", text, re.S):
            out.append(_unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S))))
        return out

    # --- parts -------------------------------------------------------------

    def part(self, name: str) -> str:
        """One zip entry's text, for a part this module has no verb for."""
        return self._by_name[name].decode("utf-8")

    def set_part(self, name: str, text: str) -> None:
        """Replace one zip entry's text; everything else still copies through.

        The escape hatch, for the parts `write_grid` does not model — a table's
        `ref`, a sortState, a style. It is deliberately blunt: the caller owns the
        XML it hands over, and `audit()` is what checks the result. Use a verb
        above where one exists.
        """
        if name not in self._by_name:
            raise KeyError("no part named %r in %s" % (name, self.path))
        data = text.encode("utf-8")
        self._dirty[name] = data
        self._by_name[name] = data

    # --- locating a sheet -------------------------------------------------

    def sheet_parts(self, sheet_name: str):
        """(worksheet part, [table parts]) for a sheet, resolved BY NAME.

        The rId in workbook.xml is not the number in the sheetN.xml filename —
        `items` is rId4 but lives in sheet4.xml only by coincidence, and
        guessing that mapping is how you edit the wrong sheet. Always resolve
        through the rels.

        ALL of the sheet's tables, not the first one. A sheet may carry several
        side-by-side — `scrolls` has three (the roster at A1:H9, the whole-name
        bag at J1:K37, the syllables at M1:N40) — and taking `re.search`'s first
        match gave whichever the rels happened to list first, which is how one
        edit to the roster resized the SYLLABLE table to span the whole sheet and
        handed Excel a table with three columns called "Game" and two called
        nothing. Excel deletes a table part it cannot repair, so the damage does
        not show up until someone opens the workbook.
        """
        wb = self._by_name["xl/workbook.xml"].decode("utf-8")
        m = re.search(r'<sheet name="%s"[^>]*r:id="(rId\d+)"' % re.escape(sheet_name), wb)
        if not m:
            raise KeyError("no sheet named %r in %s" % (sheet_name, self.path))
        rels = self._by_name["xl/_rels/workbook.xml.rels"].decode("utf-8")
        target = dict(re.findall(r'Id="(rId\d+)"[^>]*Target="([^"]+)"', rels))[m.group(1)]
        part = "xl/" + target.lstrip("/")
        tables = []
        rel_path = "xl/worksheets/_rels/%s.rels" % os.path.basename(part)
        if rel_path in self._by_name:
            raw = self._by_name[rel_path].decode("utf-8")
            for tm in re.findall(r'Target="([^"]*tables/[^"]+)"', raw):
                tables.append("xl/" + os.path.normpath(
                    os.path.join("worksheets", tm)).replace(os.sep, "/"))
        return part, sorted(tables)

    # --- creating a sheet -------------------------------------------------

    _BLANK_SHEET = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<worksheet xmlns="%s" xmlns:r="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships"><dimension ref="A1"/><sheetViews>'
        '<sheetView workbookViewId="0"/></sheetViews>'
        '<sheetFormatPr defaultRowHeight="15"/><sheetData/>'
        '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" '
        'header="0.3" footer="0.3"/></worksheet>' % _NS
    )

    def add_sheet(self, sheet_name: str) -> str:
        """Append an empty worksheet named `sheet_name`; return its part path.

        Four things have to agree or Excel calls the file corrupt: the part
        itself, its `<sheet>` entry in workbook.xml, its Relationship in
        workbook.xml.rels, and its Override in [Content_Types].xml. Miss the
        last one and the workbook opens with the sheet silently absent.

        The new sheet is empty; fill it with `write_grid` afterwards. Existing
        names are refused rather than merged onto.
        """
        wb = self._by_name["xl/workbook.xml"].decode("utf-8")
        if re.search(r'<sheet name="%s"[ /]' % re.escape(sheet_name), wb):
            raise ValueError("%s already has a sheet named %r"
                             % (self.path, sheet_name))

        n = 1
        while "xl/worksheets/sheet%d.xml" % n in self._by_name:
            n += 1
        part = "xl/worksheets/sheet%d.xml" % n

        rels = self._by_name["xl/_rels/workbook.xml.rels"].decode("utf-8")
        used = set(re.findall(r'Id="(rId\d+)"', rels))
        k = 1
        while "rId%d" % k in used:
            k += 1
        rid = "rId%d" % k
        # sheetId is workbook-scoped and unrelated to both the rId and the
        # filename; take one past the highest so nothing collides.
        ids = [int(x) for x in re.findall(r'sheetId="(\d+)"', wb)]
        sheet_id = (max(ids) + 1) if ids else 1

        wb = wb.replace("</sheets>", '<sheet name="%s" sheetId="%d" r:id="%s"/></sheets>'
                        % (_esc(sheet_name), sheet_id, rid), 1)
        self._dirty["xl/workbook.xml"] = wb.encode("utf-8")
        self._by_name["xl/workbook.xml"] = self._dirty["xl/workbook.xml"]

        rels = rels.replace("</Relationships>",
                            '<Relationship Id="%s" Type="http://schemas.openxmlformats.org/'
                            'officeDocument/2006/relationships/worksheet" Target="%s"/>'
                            "</Relationships>"
                            % (rid, part[len("xl/"):]), 1)
        self._dirty["xl/_rels/workbook.xml.rels"] = rels.encode("utf-8")
        self._by_name["xl/_rels/workbook.xml.rels"] = self._dirty["xl/_rels/workbook.xml.rels"]

        ct_name = "[Content_Types].xml"
        ct = self._by_name[ct_name].decode("utf-8")
        ct = ct.replace("</Types>",
                        '<Override PartName="/%s" ContentType="application/vnd.'
                        'openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                        "</Types>" % part, 1)
        self._dirty[ct_name] = ct.encode("utf-8")
        self._by_name[ct_name] = self._dirty[ct_name]

        data = self._BLANK_SHEET.encode("utf-8")
        self._by_name[part] = data
        # __exit__ writes from _entries in order, so a brand-new part has to be
        # appended there too — putting it only in _dirty would drop it.
        info = zipfile.ZipInfo(part, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        self._entries.append((info, data))
        return part

    # --- reading ----------------------------------------------------------

    def read_grid(self, sheet_name: str) -> list:
        """The sheet as a list of row lists, header row first. Values are str,
        int or float; blank cells are ''. Refuses a sheet containing formulas."""
        part, _tables = self.sheet_parts(sheet_name)
        xml = self._by_name[part].decode("utf-8")
        if "<f>" in xml or "<f " in xml:
            raise ValueError(
                "%s contains formulas — _xlsx_surgery regenerates cell data from "
                "values and would destroy them" % sheet_name)
        rows = {}
        width = 0
        for rm in re.finditer(r'<row r="(\d+)"[^>]*>(.*?)</row>', xml, re.S):
            r = int(rm.group(1))
            cells = {}
            for cm in re.finditer(
                    r'<c r="([A-Z]+)(\d+)"([^>]*?)(?:/>|>(.*?)</c>)', rm.group(2), re.S):
                col, attrs, body = cm.group(1), cm.group(3), cm.group(4) or ""
                cells[_col_index(col)] = _cell_value(attrs, body, self._shared)
                width = max(width, _col_index(col) + 1)
            rows[r] = cells
        if not rows:
            return []
        grid = []
        for r in range(1, max(rows) + 1):
            cells = rows.get(r, {})
            grid.append([cells.get(c, "") for c in range(width)])
        return grid

    # --- writing ----------------------------------------------------------

    def write_grid(self, sheet_name: str, grid: list) -> None:
        """Replace the sheet's cell data with `grid` (header row first).

        Strings are written as inline strings, so nothing has to be appended to
        sharedStrings and no other sheet's indices can shift. The `<dimension>`,
        each row's `spans`, and — on a sheet with exactly ONE table — that table
        (its ref, autofilter and column list) are all resized to match.

        A SHEET WITH SEVERAL TABLES KEEPS ALL OF THEM EXACTLY AS THEY ARE, and a
        grid that would change such a sheet's shape is refused outright. `last`
        below is computed from the whole grid, which is the right answer only when
        one table spans the sheet; on `scrolls`, where three tables sit side by
        side in three column blocks, there is no way to tell from a grid of values
        which block gained a row. So a value edit (the common case, and all this
        module is for) goes through untouched, and anything structural stops here
        with a message rather than silently rewriting one table over the top of
        the other two.
        """
        part, tables = self.sheet_parts(sheet_name)
        xml = self._by_name[part].decode("utf-8")
        rows = len(grid)
        cols = max((len(r) for r in grid), default=0)
        if rows == 0 or cols == 0:
            raise ValueError("refusing to write an empty grid to %s" % sheet_name)
        last = "%s%d" % (col_name(cols - 1), rows)
        if len(tables) > 1:
            was = re.search(r'<dimension ref="A1:([A-Z]+\d+)"/>', xml)
            if was is None or was.group(1) != last:
                raise ValueError(
                    "%s carries %d tables in separate column blocks, so this module "
                    "cannot resize them (A1:%s -> A1:%s). Edit values only here, or "
                    "fix the table refs by hand in Excel."
                    % (sheet_name, len(tables), was.group(1) if was else "?", last))

        body = []
        for i, row in enumerate(grid, start=1):
            cells = []
            for c in range(cols):
                value = row[c] if c < len(row) else ""
                cell = _cell_xml("%s%d" % (col_name(c), i), value)
                if cell:
                    cells.append(cell)
            body.append('<row r="%d" spans="1:%d">%s</row>' % (i, cols, "".join(cells)))
        # A sheet that has never held a row writes its sheetData SELF-CLOSING
        # (`<sheetData/>`), so match both forms — matching only the paired one
        # left a brand-new sheet with its dimension resized and no rows in it.
        xml, hits = re.subn(r"<sheetData\s*/>|<sheetData(?:\s[^>]*)?>.*?</sheetData>",
                            lambda _m: "<sheetData>%s</sheetData>" % "".join(body),
                            xml, count=1, flags=re.S)
        if hits != 1:
            raise ValueError("no <sheetData> element in %s (%s)" % (sheet_name, part))
        xml = re.sub(r'<dimension ref="[^"]*"/>', '<dimension ref="A1:%s"/>' % last, xml)
        self._dirty[part] = xml.encode("utf-8")

        if len(tables) == 1:
            self._write_table(tables[0], grid[0], last)

    def _write_table(self, table_part: str, headers: list, last_ref: str) -> None:
        xml = self._by_name[table_part].decode("utf-8")
        elements = re.findall(r"<tableColumn\b[^>]*/>", xml)
        old = [(re.search(r'\bname="([^"]*)"', e) or _BLANK).group(1) for e in elements]
        xml = re.sub(r'(<table[^>]*\sref=")[^"]*(")', r"\g<1>A1:%s\g<2>" % last_ref, xml)
        xml = re.sub(r'(<autoFilter[^>]*\sref=")[^"]*(")', r"\g<1>A1:%s\g<2>" % last_ref, xml)
        # Rebuilt, but not from scratch: a renamed or added column has to keep the
        # ids contiguous, and Excel rejects a tableColumns count that disagrees
        # with its children. A column whose name has NOT changed is copied through
        # as the element it already was, so its xr3:uid and any dataDxfId survive —
        # this module's whole promise is that it changes what you asked for and
        # nothing else, and re-running a one-shot on an unchanged sheet should come
        # out byte-identical rather than quietly shedding attributes each pass.
        names = _table_column_names(headers, old)
        parts = []
        for i, n in enumerate(names):
            if i < len(elements) and old[i] == n:
                parts.append(re.sub(r'\bid="\d+"', 'id="%d"' % (i + 1), elements[i], count=1))
            else:
                parts.append('<tableColumn id="%d" name="%s"/>' % (i + 1, _esc(n)))
        columns = "".join(parts)
        xml = re.sub(r"<tableColumns[^>]*>.*?</tableColumns>",
                     lambda _m: '<tableColumns count="%d">%s</tableColumns>' % (
                         len(names), columns),
                     xml, flags=re.S)
        self._dirty[table_part] = xml.encode("utf-8")


def audit(path: str) -> list:
    """Every table part in `path` that Excel would refuse to open cleanly.

    Excel reports a broken table only as "Removed Part" / "Repaired Records" the
    next time somebody opens the file, which is days after the edit that did it
    and names an `xl/tables/tableN.xml` nobody can map back to a sheet. This says
    the same thing in the same breath as the edit, and names the sheet.

    The three rules it knows are the three a `tableColumns` block has to keep:
    every name non-empty, every name unique within its table (case-insensitively),
    and the declared `count` equal to the number of children.

    Run it after any one-shot: `python3 tools/_xlsx_surgery.py tools/Roguelikes.xlsx`
    """
    problems = []
    with Workbook(path) as wb:
        wbx = wb._by_name["xl/workbook.xml"].decode("utf-8")
        for sm in re.finditer(r'<sheet name="([^"]+)"', wbx):
            sheet = _unescape(sm.group(1))
            try:
                _part, tables = wb.sheet_parts(sheet)
            except KeyError:
                continue
            for t in tables:
                xml = wb._by_name[t].decode("utf-8")
                names = re.findall(r'<tableColumn\b[^>]*\bname="([^"]*)"', xml)
                count = re.search(r'<tableColumns[^>]*\bcount="(\d+)"', xml)
                ref = re.search(r'<table\b[^>]*\sref="([^"]*)"', xml)
                where = "%s / %s (%s)" % (sheet, os.path.basename(t),
                                          ref.group(1) if ref else "?")
                seen = {}
                for i, n in enumerate(names):
                    if not n.strip():
                        problems.append("%s: column %d has no name" % (where, i + 1))
                    key = n.strip().lower()
                    if key and key in seen:
                        problems.append("%s: columns %d and %d are both named %r"
                                        % (where, seen[key] + 1, i + 1, n))
                    seen.setdefault(key, i)
                if count and int(count.group(1)) != len(names):
                    problems.append("%s: count=%s but %d columns"
                                    % (where, count.group(1), len(names)))
    return problems


def _table_column_names(headers: list, old: list) -> list:
    """Header row -> table column names Excel will actually accept.

    A `tableColumn` name must be NON-EMPTY and UNIQUE within its table; Excel
    deletes a table that breaks either rule and tells you so on open, long after
    the edit that did it. A header row is under no such obligation — it is only
    text in cells — so the two cannot be copied across verbatim.

    Renames still follow the header, because that is what the rebuild is for. A
    blank header keeps whatever the workbook already called that column and falls
    back to Excel's own "ColumnN"; a duplicate gets Excel's own suffix ("Game",
    "Game2", "Game3"). Compared case-insensitively, which is the comparison Excel
    itself makes.
    """
    used = set()
    out = []
    for i, h in enumerate(headers):
        base = str(h).strip()
        if not base:
            base = str(old[i]).strip() if i < len(old) and str(old[i]).strip() \
                else "Column%d" % (i + 1)
        name = base
        n = 1
        while name.lower() in used:
            n += 1
            name = "%s%d" % (base, n)
        used.add(name.lower())
        out.append(name)
    return out


def _col_index(letters: str) -> int:
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - ord("A") + 1)
    return n - 1


def _unescape(s: str) -> str:
    return (s.replace("&lt;", "<").replace("&gt;", ">")
             .replace("&quot;", '"').replace("&apos;", "'").replace("&amp;", "&"))


def _cell_value(attrs: str, body: str, shared: list):
    vm = re.search(r"<v>(.*?)</v>", body, re.S)
    if 't="inlineStr"' in attrs:
        tm = re.search(r"<t[^>]*>(.*?)</t>", body, re.S)
        return _unescape(tm.group(1)) if tm else ""
    if not vm:
        return ""
    raw = vm.group(1)
    if 't="s"' in attrs:
        idx = int(raw)
        return shared[idx] if idx < len(shared) else ""
    if 't="b"' in attrs:
        return raw == "1"
    try:
        return int(raw) if re.fullmatch(r"-?\d+", raw) else float(raw)
    except ValueError:
        return _unescape(raw)


def _cell_xml(ref: str, value) -> str:
    if value is None or value == "":
        return ""
    if isinstance(value, bool):
        return '<c r="%s" t="b"><v>%d</v></c>' % (ref, 1 if value else 0)
    if isinstance(value, (int, float)):
        return '<c r="%s"><v>%s</v></c>' % (ref, value)
    return '<c r="%s" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % (
        ref, _esc(str(value)))


if __name__ == "__main__":
    import sys
    target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
    found = audit(target)
    for line in found:
        print(line)
    print("%s: %d table problem(s)" % (os.path.basename(target), len(found)))
    sys.exit(1 if found else 0)

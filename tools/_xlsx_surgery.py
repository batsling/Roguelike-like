#!/usr/bin/env python3
"""Edit one sheet of tools/Roguelikes.xlsx without destroying the rest of it.

openpyxl cannot round-trip this workbook: loading and saving it silently drops
the seven charts on `Map Analysis` and anything else openpyxl does not model. So
the sheet-editing one-shots here read the .xlsx as the zip it is, rewrite only
the two parts that describe one sheet (`xl/worksheets/sheetN.xml` and its
`xl/tables/tableN.xml`), and copy every other entry through byte-for-byte.

Usable ONLY on sheets that are plain value grids — no formulas, no per-cell
styles — because `write_grid` regenerates the whole `<sheetData>` from values.
`read_grid` refuses a sheet with formulas so that stays honest rather than
becoming a silent data loss the next time someone points this at `Map Calc`.

    from _xlsx_surgery import Workbook
    with Workbook("tools/Roguelikes.xlsx") as wb:
        grid = wb.read_grid("items2.0")
        grid.append(["Oddly Smooth Stone", "Common", ...])
        wb.write_grid("items2.0", grid)

Nothing is written until the context manager exits cleanly, so a parse error
part-way through leaves the workbook untouched.
"""

import os
import re
import shutil
import zipfile

_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"


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

    # --- locating a sheet -------------------------------------------------

    def sheet_parts(self, sheet_name: str):
        """(worksheet part, table part or None) for a sheet, resolved BY NAME.

        The rId in workbook.xml is not the number in the sheetN.xml filename —
        `items2.0` is rId4 but lives in sheet4.xml only by coincidence, and
        guessing that mapping is how you edit the wrong sheet. Always resolve
        through the rels.
        """
        wb = self._by_name["xl/workbook.xml"].decode("utf-8")
        m = re.search(r'<sheet name="%s"[^>]*r:id="(rId\d+)"' % re.escape(sheet_name), wb)
        if not m:
            raise KeyError("no sheet named %r in %s" % (sheet_name, self.path))
        rels = self._by_name["xl/_rels/workbook.xml.rels"].decode("utf-8")
        target = dict(re.findall(r'Id="(rId\d+)"[^>]*Target="([^"]+)"', rels))[m.group(1)]
        part = "xl/" + target.lstrip("/")
        table = None
        rel_path = "xl/worksheets/_rels/%s.rels" % os.path.basename(part)
        if rel_path in self._by_name:
            raw = self._by_name[rel_path].decode("utf-8")
            tm = re.search(r'Target="([^"]*tables/[^"]+)"', raw)
            if tm:
                table = "xl/" + os.path.normpath(
                    os.path.join("worksheets", tm.group(1))).replace(os.sep, "/")
        return part, table

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
        part, _ = self.sheet_parts(sheet_name)
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
        each row's `spans`, and the sheet's table (its ref, autofilter and column
        list) are all resized to match.
        """
        part, table = self.sheet_parts(sheet_name)
        xml = self._by_name[part].decode("utf-8")
        rows = len(grid)
        cols = max((len(r) for r in grid), default=0)
        if rows == 0 or cols == 0:
            raise ValueError("refusing to write an empty grid to %s" % sheet_name)
        last = "%s%d" % (col_name(cols - 1), rows)

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

        if table is not None:
            self._write_table(table, grid[0], last)

    def replace_cells(self, sheet_name: str, edits: dict) -> int:
        """Rewrite the VALUES of named cells in place; touch nothing else.

        `edits` maps a cell ref to its new value: `{"D17": "Bombs"}`. Every
        other attribute of the cell survives, as do the sheet's dimension, its
        tables, and any formulas elsewhere on it.

        This is the complement to `write_grid`, and on a lot of sheets it is the
        only safe option. `write_grid` regenerates the whole `<sheetData>` and
        resizes THE FIRST table it finds — but `sheet_parts` returns only one
        table, and a sheet can carry several. `chart` carries five: the main
        A1:S table, the U:V Good Dir lookup, and one per branch of the Groups
        tree. Pointing `write_grid` at it would resize the Good Dir lookup to
        span the whole sheet and rebuild it with a blank-named column, which
        Excel rejects as corrupt. Use this for a value edit; keep `write_grid`
        for a plain single-table value grid you are regenerating wholesale.

        Returns the number of cells changed. A ref that is not already present
        in the sheet is an error rather than an insert — this edits, it does not
        author, and a typo'd ref should not silently become a new cell.
        """
        part, _ = self.sheet_parts(sheet_name)
        xml = self._by_name[part].decode("utf-8")
        remaining = dict(edits)

        def sub(m):
            ref, attrs = m.group(1), m.group(2)
            if ref not in remaining:
                return m.group(0)
            value = remaining.pop(ref)
            keep = re.search(r'\ss="(\d+)"', attrs or "")
            style = ' s="%s"' % keep.group(1) if keep else ""
            if value is None or value == "":
                return '<c r="%s"%s/>' % (ref, style)
            if isinstance(value, bool):
                return '<c r="%s"%s t="b"><v>%d</v></c>' % (ref, style, 1 if value else 0)
            if isinstance(value, (int, float)):
                return '<c r="%s"%s><v>%s</v></c>' % (ref, style, value)
            return ('<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s'
                    "</t></is></c>" % (ref, style, _esc(str(value))))

        xml = re.sub(r'<c r="([A-Z]+\d+)"([^>]*?)(?:/>|>(.*?)</c>)', sub, xml, flags=re.S)
        if remaining:
            raise KeyError("%s has no cell(s) %s"
                           % (sheet_name, ", ".join(sorted(remaining))))
        self._dirty[part] = xml.encode("utf-8")
        return len(edits)

    def set_cells(self, sheet_name: str, edits: dict) -> int:
        """Like `replace_cells`, but ALSO creates cells and rows that are absent.

        `replace_cells` refuses an unknown ref on purpose, so a typo cannot
        quietly become a new cell. This is the version for when you really are
        authoring: filling a blank cell in an existing row, or appending rows
        past the end of the sheet.

        Existing cells you do not name are copied through verbatim — their
        style, type and value are untouched — so this is still far safer than
        `write_grid`, which regenerates every cell from values and resizes the
        first table it finds. It does NOT touch any table's ref: growing a
        sheet past its table means calling `resize_table` afterwards, which the
        caller has to do deliberately because only the caller knows which of
        several tables the new rows belong to.

        Setting a cell to "" or None empties it.
        """
        part, _ = self.sheet_parts(sheet_name)
        xml = self._by_name[part].decode("utf-8")

        m = re.search(r"<sheetData\s*/>|<sheetData(?:\s[^>]*)?>(.*?)</sheetData>",
                      xml, re.S)
        if not m:
            raise ValueError("no <sheetData> element in %s (%s)" % (sheet_name, part))

        rows = {}          # row number -> (row open tag, {col letter: cell xml})
        for rm in re.finditer(r'<row r="(\d+)"([^>]*)>(.*?)</row>', m.group(1) or "", re.S):
            cells = {}
            for cm in re.finditer(r'<c r="([A-Z]+)\d+"[^>]*?(?:/>|>.*?</c>)',
                                  rm.group(3), re.S):
                cells[cm.group(1)] = cm.group(0)
            rows[int(rm.group(1))] = [rm.group(2), cells]

        width = max((_col_index(c) + 1 for _, cs in rows.values() for c in cs), default=0)
        for ref, value in edits.items():
            rm = re.fullmatch(r"([A-Z]+)(\d+)", ref)
            if not rm:
                raise ValueError("not a cell reference: %r" % ref)
            col, r = rm.group(1), int(rm.group(2))
            rows.setdefault(r, ['  spans="1:%d"' % max(width, 1), {}])
            if value is None or value == "":
                rows[r][1].pop(col, None)
            else:
                rows[r][1][col] = _cell_xml(ref, value)
            width = max(width, _col_index(col) + 1)

        body = []
        for r in sorted(rows):
            attrs, cells = rows[r]
            ordered = sorted(cells, key=_col_index)
            body.append('<row r="%d"%s>%s</row>'
                        % (r, attrs, "".join(cells[c] for c in ordered)))

        xml = (xml[:m.start()] + "<sheetData>" + "".join(body) + "</sheetData>"
               + xml[m.end():])
        last = "%s%d" % (col_name(width - 1), max(rows) if rows else 1)
        xml = re.sub(r'<dimension ref="[^"]*"/>', '<dimension ref="A1:%s"/>' % last, xml)
        self._dirty[part] = xml.encode("utf-8")
        return len(edits)

    def resize_table(self, display_name: str, ref: str) -> None:
        """Point one table (found by its displayName) at a new range.

        Its `<autoFilter>` moves with it. The column list is left ALONE — this
        grows a table over more rows, it does not re-author its columns, which
        is the part `write_grid` gets wrong on a multi-table sheet.
        """
        for part in [n for n in self._by_name if n.startswith("xl/tables/")]:
            xml = self._by_name[part].decode("utf-8")
            if 'displayName="%s"' % display_name not in xml:
                continue
            xml = re.sub(r'(<table[^>]*\sref=")[^"]*(")', r"\g<1>%s\g<2>" % ref, xml, count=1)
            xml = re.sub(r'(<autoFilter[^>]*\sref=")[^"]*(")', r"\g<1>%s\g<2>" % ref, xml)
            self._dirty[part] = xml.encode("utf-8")
            self._by_name[part] = self._dirty[part]
            return
        raise KeyError("no table named %r in %s" % (display_name, self.path))

    def _write_table(self, table_part: str, headers: list, last_ref: str) -> None:
        xml = self._by_name[table_part].decode("utf-8")
        xml = re.sub(r'(<table[^>]*\sref=")[^"]*(")', r"\g<1>A1:%s\g<2>" % last_ref, xml)
        xml = re.sub(r'(<autoFilter[^>]*\sref=")[^"]*(")', r"\g<1>A1:%s\g<2>" % last_ref, xml)
        # Rebuilt wholesale: a renamed or added column has to keep the ids
        # contiguous, and Excel rejects a tableColumns count that disagrees with
        # its children. The xr3:uid attributes are optional and dropped.
        columns = "".join('<tableColumn id="%d" name="%s"/>' % (i + 1, _esc(str(h)))
                          for i, h in enumerate(headers))
        xml = re.sub(r"<tableColumns[^>]*>.*?</tableColumns>",
                     lambda _m: '<tableColumns count="%d">%s</tableColumns>' % (
                         len(headers), columns),
                     xml, flags=re.S)
        self._dirty[table_part] = xml.encode("utf-8")


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

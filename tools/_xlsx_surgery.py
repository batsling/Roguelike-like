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
        xml = re.sub(r"<sheetData>.*?</sheetData>",
                     lambda _m: "<sheetData>%s</sheetData>" % "".join(body), xml, flags=re.S)
        xml = re.sub(r'<dimension ref="[^"]*"/>', '<dimension ref="A1:%s"/>' % last, xml)
        self._dirty[part] = xml.encode("utf-8")

        if table is not None:
            self._write_table(table, grid[0], last)

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

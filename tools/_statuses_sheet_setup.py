#!/usr/bin/env python3
"""One-shot sheet editor: add the two machine-readable columns Statuses 2.0 needs
to the `statuses2.0` sheet — `Condition` and `Reward`.

The sheet keeps its four PROSE quadrant columns (On Player / On Enemy) as the
player-facing wording. What the engine actually needs out of a status is much
smaller, because all four quadrants are the SAME two pieces rearranged:

    Condition   the challenge clause, e.g. "you get {X} achievements"
    Reward      what completing it pays, e.g. "gain_chest small {X}"

    buff  on player  ->  extra goal: "If <condition>, gain <reward>"
    buff  on enemy   ->  its goal gains "and <condition>"          (required)
    debuff on player ->  EVERY enemy's goal gains "and <condition>" (required, ticks)
    debuff on enemy  ->  a bonus row: "and if <condition>, gain <reward>"

So two authored columns cover the whole table, and a new status is still a pure
sheet edit: write the prose, write the condition + reward, rerun
tools/generate_status_tres.py.

`{...}` holds an arithmetic expression over X (the stack count), so a status can
scale however it likes — Dexterity's window tightens on {1+(1/2)^(X-2)} while
Strength's count is a flat {X}. The generator normalises `^` to pow() and the
runtime evaluates it with Godot's Expression.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries 7 charts and a dozen
table parts that an openpyxl load/save round-trip silently drops. This edits the
two parts that actually change (worksheets/sheet8.xml + tables/table8.xml) and
copies every other zip entry through byte-for-byte.

Run once: python3 tools/_statuses_sheet_setup.py
"""

import os
import re
import shutil
import zipfile

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

# statuses2.0 is rId8 in xl/_rels/workbook.xml.rels -> worksheets/sheet8.xml,
# whose single tablePart is tables/table8.xml.
SHEET_PART = "xl/worksheets/sheet8.xml"
TABLE_PART = "xl/tables/table8.xml"

NEW_COLS = ["Condition", "Reward"]

# Row name -> (Condition, Reward). Transcribed from the sheet's own prose:
#   Strength  "If the difficuly is increased X times, Gain +X Small Chests and X Bashes"
#   Dexterity "If beaten in (1+(1/2)^X-2)) hours or less, Gain +X Small Chests and X Dashes"
#   Marked    "and you must get X achivements" / "Gain +X Small Chests"
# The Dexterity exponent is written with balanced parens here; the sheet's prose
# has a stray one.
VALUES = {
    "Strength": (
        "the difficulty is increased {X} times",
        "gain_chest small {X}; gain_stat bash {X}",
    ),
    "Dexterity": (
        "beaten in {1+(1/2)^(X-2)} hours or less",
        "gain_chest small {X}; gain_stat dash {X}",
    ),
    "Marked": (
        "you get {X} achievements",
        "gain_chest small {X}",
    ),
}


def _esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def _cell(ref: str, text: str) -> str:
    """An inline-string cell, so nothing has to be appended to sharedStrings."""
    return '<c r="%s" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % (
        ref, _esc(text))


def _row_name(row_xml: str, shared: list) -> str:
    """The Name (column A) of one <row>, resolved through sharedStrings."""
    m = re.search(r'<c r="A\d+"([^>]*)>(.*?)</c>', row_xml, re.S)
    if not m:
        return ""
    attrs, body = m.group(1), m.group(2)
    v = re.search(r"<v>(.*?)</v>", body, re.S)
    if not v:
        return ""
    if 't="s"' in attrs:
        idx = int(v.group(1))
        return shared[idx] if idx < len(shared) else ""
    return v.group(1)


def _shared_strings(zf: zipfile.ZipFile) -> list:
    try:
        raw = zf.read("xl/sharedStrings.xml").decode("utf-8")
    except KeyError:
        return []
    out = []
    for si in re.findall(r"<si>(.*?)</si>", raw, re.S):
        out.append("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S)))
    return out


def patch_sheet(xml: str, shared: list) -> str:
    if ">Condition<" in xml:
        raise SystemExit("statuses2.0 already has the Condition column — nothing to do.")

    # Widen the used range and the per-row span hints (G=7 -> I=9).
    xml = xml.replace('<dimension ref="A1:G4"/>', '<dimension ref="A1:I4"/>')
    xml = xml.replace('spans="1:7"', 'spans="1:9"')
    # Readable widths for the two new columns, matching the prose columns beside them.
    xml = xml.replace(
        '<col min="7" max="7" width="9.28515625" bestFit="1" customWidth="1"/>',
        '<col min="7" max="7" width="9.28515625" bestFit="1" customWidth="1"/>'
        '<col min="8" max="8" width="46.0" customWidth="1"/>'
        '<col min="9" max="9" width="42.0" customWidth="1"/>')

    def fill(m):
        row_xml = m.group(0)
        r = m.group(1)
        if r == "1":
            cells = [_cell("H1", NEW_COLS[0]), _cell("I1", NEW_COLS[1])]
        else:
            name = _row_name(row_xml, shared)
            if name not in VALUES:
                raise SystemExit(
                    "statuses2.0 row %s (%r) has no authored Condition/Reward — "
                    "add it to VALUES in this script." % (r, name))
            cond, reward = VALUES[name]
            cells = [_cell("H%s" % r, cond), _cell("I%s" % r, reward)]
        return row_xml.replace("</row>", "".join(cells) + "</row>")

    return re.sub(r'<row r="(\d+)".*?</row>', fill, xml, flags=re.S)


def patch_table(xml: str) -> str:
    xml = xml.replace('ref="A1:G4"', 'ref="A1:I4"')
    xml = xml.replace('<tableColumns count="7">', '<tableColumns count="9">')
    added = "".join('<tableColumn id="%d" name="%s"/>' % (8 + i, name)
                    for i, name in enumerate(NEW_COLS))
    return xml.replace("</tableColumns>", added + "</tableColumns>")


def main() -> None:
    backup = XLSX + ".bak"
    shutil.copy2(XLSX, backup)
    with zipfile.ZipFile(backup) as zf:
        shared = _shared_strings(zf)
        entries = [(i, zf.read(i.filename)) for i in zf.infolist()]

    with zipfile.ZipFile(XLSX, "w", zipfile.ZIP_DEFLATED) as out:
        for info, data in entries:
            if info.filename == SHEET_PART:
                data = patch_sheet(data.decode("utf-8"), shared).encode("utf-8")
            elif info.filename == TABLE_PART:
                data = patch_table(data.decode("utf-8")).encode("utf-8")
            out.writestr(info, data)

    os.remove(backup)
    print("statuses2.0: added columns %s" % ", ".join(NEW_COLS))
    for name, (cond, reward) in VALUES.items():
        print("  %-10s %-42s %s" % (name, cond, reward))


if __name__ == "__main__":
    main()

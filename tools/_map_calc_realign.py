#!/usr/bin/env python3
"""One-shot: put `Map Calc` back on its own rows, and give it room to grow.

The owner found `Map Analysis` wrong "in some areas". The cause was `Map Calc`'s
per-connection block (T/U/V: influencer year, influencee year, span):

  - a row deleted from `connections` left T429/U429 reading `connections!#REF!`,
    and Excel moved every reference below it up by one, so from row 430 down
    each row read the connection ABOVE its own (T430 -> connections!$A429).
    The span histogram, the median span and the "influencee older than its
    influencer" count were all computed over that.
  - the block stopped at row 1400 while `connections` runs to row 1526, so the
    last 126 connections were never counted at all.
  - the games block (A:Q, to row 950) had 26 rows of headroom left over 923
    games, and the degree COUNTIFs had none over the connections sheet.

`build_map_charts.py` writes the sheet, but through openpyxl, which a
round-trip of this workbook cannot survive (CLAUDE.md). So this rewrites
`Map Calc`'s formula cells straight into the sheet XML from the same formulas,
each on its own row, over the wider ranges below; widens the same ranges on
`Map Analysis` and in the timeline chart; drops the stale calcChain (it names
formula cells by address, and the set changed); and asks Excel to recalculate
everything on open, since every cached value on both sheets predates the fix.

    python3 tools/_map_calc_realign.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook, _esc  # noqa: E402
from build_map_charts import CONNS, GAMES, LANE, TYPES  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
OLD_GAMES, OLD_CONNS = ("950",), ("1400", "1526")


def game_cells(r):
    f = {
        "A": 'IF(games!$A{0}="","",games!$A{0})',
        "B": 'IF($A{0}="","",games!$B{0})',
        "C": 'IF($A{0}="","",games!$C{0})',
        "D": ('IF($A{0}="","",COUNTIF(connections!$A$2:$A${1},$A{0})'
              '+COUNTIF(connections!$B$2:$B${1},$A{0}))'),
        "E": 'IF($A{0}="","",IFERROR(MATCH($C{0},$R$2:$R$5,0),0))',
        "F": 'IF($A{0}="","",MOD(ROW(),34))',
    }
    for i, t in enumerate(TYPES):
        f["GIKM"[i]] = 'IF($A{0}="",NA(),IF($C{0}="%s",$B{0},NA()))' % t
        f["HJLN"[i]] = 'IF($A{0}="",NA(),IF($C{0}="%s",%d+$F{0}*0.023,NA()))' % (t, LANE[t])
    f["O"] = 'IF($A{0}="","",$D{0}+ROW()/1000000)'
    f["P"] = 'IF(OR($A{0}="",games!$H{0}=""),"",games!$H{0})'
    f["Q"] = 'IF(OR($A{0}="",$P{0}<>"Yes"),"",$D{0}+ROW()/1000000)'
    return {c: s.format(r, CONNS) for c, s in f.items()}


def conn_cells(r):
    look = ('IF(connections!$A{0}="","",IFERROR(INDEX(games!$B$2:$B${1},'
            'MATCH(connections!${2}{0},games!$A$2:$A${1},0)),""))')
    return {
        "T": look.format(r, GAMES, "A"),
        "U": look.format(r, GAMES, "B"),
        "V": 'IF(OR($T{0}="",$U{0}=""),"",$U{0}-$T{0})'.format(r),
    }


def widen(formula_xml):
    """Move every range end that stopped at an old limit to the new one."""
    for old in OLD_GAMES:
        formula_xml = re.sub(r"\$%s(?!\d)" % old, "$%d" % GAMES, formula_xml)
    for old in OLD_CONNS:
        formula_xml = re.sub(r"\$%s(?!\d)" % old, "$%d" % CONNS, formula_xml)
    return formula_xml


def main():
    with Workbook(XLSX) as wb:
        # ---- Map Calc: every formula cell rewritten on its own row ----------
        part, _ = wb.sheet_parts("Map Calc")
        xml = wb._by_name[part].decode("utf-8")
        head, data, tail = re.match(r"(.*<sheetData>)(.*)(</sheetData>.*)", xml, re.S).groups()
        rows = dict((int(n), body) for n, body in
                    re.findall(r'<row r="(\d+)"[^>]*>(.*?)</row>', data, re.S))
        row1 = re.search(r'<row r="1"[^>]*>.*?</row>', data, re.S).group(0)
        out = [row1]
        for r in range(2, max(GAMES, CONNS) + 1):
            cells = {}
            if r <= GAMES:
                cells.update(game_cells(r))
            if r <= CONNS:
                cells.update(conn_cells(r))
            xs = ['<c r="%s%d"%s><f>%s</f></c>' % (c, r, ' t="str"' if c in "ACPT" else "",
                                                  _esc(f)) for c, f in cells.items()]
            # The genre lookup table (R2:R5) is a value, kept as it was.
            for keep in re.findall(r'<c r="R%d"[^>]*?(?:/>|>.*?</c>)' % r, rows.get(r, ""), re.S):
                xs.append(keep)
            xs.sort(key=lambda c: len(re.match(r'<c r="([A-Z]+)', c).group(1)) * 100
                    + ord(re.match(r'<c r="([A-Z]+)', c).group(1)[-1]))
            out.append('<row r="%d">%s</row>' % (r, "".join(xs)))
        head = re.sub(r'<dimension ref="[^"]*"/>',
                      '<dimension ref="A1:V%d"/>' % max(GAMES, CONNS), head)
        head = re.sub(r'(<pane [^>]*topLeftCell=")[A-Z]+\d+', r"\1A2", head)
        head = re.sub(r'(<selection [^>]*activeCell=")[^"]*(" sqref=")[^"]*', r"\1A2\2A2", head)
        wb._dirty[part] = (head + "".join(out) + tail).encode("utf-8")

        # ---- Map Analysis: same ranges, wider; no stale error values -------
        part, _ = wb.sheet_parts("Map Analysis")
        xml = wb._by_name[part].decode("utf-8")
        xml = re.sub(r"<f>(.*?)</f>", lambda m: "<f>%s</f>" % widen(m.group(1)), xml, flags=re.S)
        xml = re.sub(r'(<c r="[A-Z]+\d+"[^>]*?) t="e"([^>]*>)(<f>.*?</f>)<v>[^<]*</v>',
                     r"\1\2\3", xml, flags=re.S)
        wb._dirty[part] = xml.encode("utf-8")

        # ---- the timeline scatter reads Map Calc's games block directly ----
        for name in list(wb._by_name):
            if re.match(r"xl/charts/chart\d+\.xml$", name):
                x = wb._by_name[name].decode("utf-8")
                y = re.sub(r"<c:f>(.*?)</c:f>", lambda m: "<c:f>%s</c:f>" % widen(m.group(1)), x)
                if y != x:
                    wb._dirty[name] = y.encode("utf-8")

        # ---- recalculate on open; the calc chain no longer matches ---------
        wbx = wb._by_name["xl/workbook.xml"].decode("utf-8")
        wbx = re.sub(r'<calcPr([^>]*?)\s*/>',
                     lambda m: '<calcPr%s fullCalcOnLoad="1"/>' % m.group(1).replace(' fullCalcOnLoad="1"', ""),
                     wbx, count=1)
        wb._dirty["xl/workbook.xml"] = wbx.encode("utf-8")
        if "xl/calcChain.xml" in wb._by_name:
            wb._entries = [(i, d) for i, d in wb._entries if i.filename != "xl/calcChain.xml"]
            rels = wb._by_name["xl/_rels/workbook.xml.rels"].decode("utf-8")
            wb._dirty["xl/_rels/workbook.xml.rels"] = re.sub(
                r'<Relationship [^>]*Target="calcChain\.xml"/>', "", rels).encode("utf-8")
            ct = wb._by_name["[Content_Types].xml"].decode("utf-8")
            wb._dirty["[Content_Types].xml"] = re.sub(
                r'<Override PartName="/xl/calcChain\.xml"[^>]*/>', "", ct).encode("utf-8")
    print("Map Calc rebuilt to %d game rows and %d connection rows" % (GAMES, CONNS))


if __name__ == "__main__":
    main()

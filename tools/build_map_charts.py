#!/usr/bin/env python3
"""Add a live graph-analysis dashboard to tools/Roguelikes.xlsx.

Everything is written as formulas over the `games` and `connections` sheets, so
adding a game or a connection and reopening the file updates every number and
every chart. Nothing is a baked-in constant.
"""
import openpyxl
from openpyxl.chart import BarChart, ScatterChart, Reference, Series
from openpyxl.chart.marker import Marker
from openpyxl.drawing.line import LineProperties
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

SRC = "/home/user/Roguelike-like/tools/Roguelikes.xlsx"
CALC = "Map Calc"
DASH = "Map Analysis"

GAMES = 820      # ranges run past the data so new rows are picked up
CONNS = 1060
YEAR0, YEAR1 = 1978, 2026
TYPES = ["Action", "Strategy", "Deckbuilder", "Traditional"]
LANE = {t: i + 1 for i, t in enumerate(TYPES)}
ACCENT = "C0392B"
INK = "1D1812"
HEADFILL = PatternFill("solid", fgColor="EDE3D0")
BOXFILL = PatternFill("solid", fgColor="F7F2E8")
THIN = Side(style="thin", color="BFAE8C")
BOX = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
FONT = "Arial"


def title(ws, cell, text, size=14):
    ws[cell] = text
    ws[cell].font = Font(name=FONT, size=size, bold=True, color=INK)


def head(ws, cell, text):
    ws[cell] = text
    ws[cell].font = Font(name=FONT, size=10, bold=True, color=INK)
    ws[cell].fill = HEADFILL
    ws[cell].border = BOX
    ws[cell].alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)


def build_calc(wb):
    if CALC in wb.sheetnames:
        del wb[CALC]
    ws = wb.create_sheet(CALC)
    ws.sheet_state = "visible"

    # ---- per-game block: year, type, degree, and the scatter columns --------
    for c, h in enumerate(
        ["Game", "Year", "Type", "Degree", "Lane", "Stack",
         "Action X", "Action Y", "Strategy X", "Strategy Y",
         "Deckbuilder X", "Deckbuilder Y", "Traditional X", "Traditional Y",
         "Rank key"], 1):
        head(ws, "%s1" % get_column_letter(c), h)

    for r in range(2, GAMES + 1):
        g = "games!$A%d" % r
        ws["A%d" % r] = "=IF(%s=\"\",\"\",%s)" % (g, g)
        ws["B%d" % r] = "=IF($A%d=\"\",\"\",games!$B%d)" % (r, r)
        ws["C%d" % r] = "=IF($A%d=\"\",\"\",games!$C%d)" % (r, r)
        # Degree counts the game on either end of a connection.
        ws["D%d" % r] = ("=IF($A{0}=\"\",\"\","
                         "COUNTIF(connections!$A$2:$A${1},$A{0})"
                         "+COUNTIF(connections!$B$2:$B${1},$A{0}))").format(r, CONNS)
        ws["E%d" % r] = "=IF($A{0}=\"\",\"\",IFERROR(MATCH($C{0},$R$2:$R$5,0),0))".format(r)
        # Spread points inside their lane so a busy year does not collapse to a
        # single dot. Counting same-year siblings with an expanding COUNTIFS is
        # the accurate way and is O(n^2) — it alone pushed a full recalc past
        # 13 minutes. Row position is uncorrelated with year here (the sheet is
        # alphabetical), so it scatters just as well for free.
        ws["F%d" % r] = "=IF($A{0}=\"\",\"\",MOD(ROW(),34))".format(r)
        for i, t in enumerate(TYPES):
            xc, yc = get_column_letter(7 + i * 2), get_column_letter(8 + i * 2)
            ws["%s%d" % (xc, r)] = ("=IF($A{0}=\"\",NA(),IF($C{0}=\"{1}\",$B{0},NA()))"
                                    ).format(r, t)
            ws["%s%d" % (yc, r)] = ("=IF($A{0}=\"\",NA(),IF($C{0}=\"{1}\",{2}+$F{0}*0.023,NA()))"
                                    ).format(r, t, LANE[t])
        # Tie-break so LARGE/MATCH cannot pick the same hub twice.
        ws["O%d" % r] = "=IF($A{0}=\"\",\"\",$D{0}+ROW()/1000000)".format(r)

    # ---- lookup table the lane formula matches against ---------------------
    head(ws, "R1", "Genre")
    for i, t in enumerate(TYPES):
        ws["R%d" % (2 + i)] = t
        ws["R%d" % (2 + i)].font = Font(name=FONT, size=10)

    # ---- per-connection block: the two years and the gap between them ------
    for c, h in enumerate(["Influencer yr", "Influencee yr", "Span (yrs)"], 20):
        head(ws, "%s1" % get_column_letter(c), h)
    for r in range(2, CONNS + 1):
        src = "connections!$A%d" % r
        ws["T%d" % r] = ("=IF({0}=\"\",\"\",IFERROR(INDEX(games!$B$2:$B${1},"
                         "MATCH({0},games!$A$2:$A${1},0)),\"\"))").format(src, GAMES)
        ws["U%d" % r] = ("=IF({0}=\"\",\"\",IFERROR(INDEX(games!$B$2:$B${1},"
                         "MATCH(connections!$B{2},games!$A$2:$A${1},0)),\"\"))"
                         ).format(src, GAMES, r)
        ws["V%d" % r] = ("=IF(OR($T{0}=\"\",$U{0}=\"\"),\"\",$U{0}-$T{0})").format(r)

    ws.column_dimensions["A"].width = 34
    for col in "BCDEFOTUV":
        ws.column_dimensions[col].width = 12
    ws.freeze_panes = "A2"
    return ws


def build_dash(wb):
    if DASH in wb.sheetnames:
        del wb[DASH]
    ws = wb.create_sheet(DASH, 0)

    title(ws, "A1", "Influence Graph — live analysis", 16)
    ws["A2"] = ("Every figure is a formula over the games and connections sheets. "
                "Add a row to either and these update on open.")
    ws["A2"].font = Font(name=FONT, size=10, italic=True, color="5F5340")

    # ---- headline metrics --------------------------------------------------
    head(ws, "A4", "Measure")
    head(ws, "B4", "Value")
    head(ws, "C4", "What it means")
    rows = [
        ("Games", "=COUNTA(games!$A$2:$A${})".format(GAMES),
         "Nodes in the graph"),
        ("Connections", "=COUNTA(connections!$A$2:$A${})".format(CONNS),
         "Authored influence edges"),
        ("Average degree", "=IF(B5=0,0,2*B6/B5)",
         "Connections per game — under 3 means a sparse graph"),
        ("Median degree", "=MEDIAN('{}'!$D$2:$D${})".format(CALC, GAMES),
         "Half of all games sit at or below this"),
        ("Largest hub", "=MAX('{}'!$D$2:$D${})".format(CALC, GAMES),
         "Degree of the single most connected game"),
        ("Leaves (degree 1)", "=COUNTIF('{}'!$D$2:$D${},1)".format(CALC, GAMES),
         "Dead ends — one way in, the same way out"),
        ("Isolated (degree 0)", "=COUNTIF('{}'!$D$2:$D${},0)".format(CALC, GAMES),
         "Unreachable; can never appear on a route"),
        ("Leaves + isolated", "=B10+B11",
         "Share of the map that carries no routing information"),
        ("Backward in time", "=SUMPRODUCT(('{0}'!$V$2:$V${1}<>\"\")*('{0}'!$V$2:$V${1}<0))"
         .format(CALC, CONNS),
         "MUST BE 0 — an influence cannot point at an older game"),
        ("Same year", "=SUMPRODUCT(('{0}'!$V$2:$V${1}<>\"\")*('{0}'!$V$2:$V${1}=0))"
         .format(CALC, CONNS),
         "Legal: a demo influencing something shipped the same year"),
        ("Median edge span", "=MEDIAN('{}'!$V$2:$V${})".format(CALC, CONNS),
         "Years between an influencer and what it influenced"),
        ("Dev/Series flagged", "=COUNTIF(connections!$D$2:$D${},\"Yes\")".format(CONNS),
         "Sequel / same-devs links, distinct from plain influence"),
        ("With a source", "=COUNTA(connections!$E$2:$E${})".format(CONNS),
         "Connections carrying a URL or note as evidence"),
    ]
    for i, (label, formula, note) in enumerate(rows):
        r = 5 + i
        ws["A%d" % r] = label
        ws["A%d" % r].font = Font(name=FONT, size=10, bold=True)
        ws["B%d" % r] = formula
        ws["B%d" % r].font = Font(name=FONT, size=10)
        ws["B%d" % r].fill = BOXFILL
        ws["C%d" % r] = note
        ws["C%d" % r].font = Font(name=FONT, size=10, color="5F5340")
        for c in "ABC":
            ws["%s%d" % (c, r)].border = BOX
    ws["B7"].number_format = "0.00"
    ws["B15"].number_format = "0.0"
    # The temporal invariant is the one that must never drift.
    ws["B13"].font = Font(name=FONT, size=10, bold=True, color=ACCENT)

    # ---- distribution tables the charts read ------------------------------
    head(ws, "E4", "Degree")
    head(ws, "F4", "Games")
    bands = [("0", "=COUNTIF('{}'!$D$2:$D${},0)"), ("1", "=COUNTIF('{}'!$D$2:$D${},1)"),
             ("2", "=COUNTIF('{}'!$D$2:$D${},2)"), ("3", "=COUNTIF('{}'!$D$2:$D${},3)"),
             ("4", "=COUNTIF('{}'!$D$2:$D${},4)"), ("5", "=COUNTIF('{}'!$D$2:$D${},5)")]
    for i, (lab, f) in enumerate(bands):
        ws["E%d" % (5 + i)] = lab
        ws["F%d" % (5 + i)] = f.format(CALC, GAMES)
    ws["E11"] = "6-9"
    ws["F11"] = "=COUNTIFS('{0}'!$D$2:$D${1},\">=6\",'{0}'!$D$2:$D${1},\"<=9\")".format(CALC, GAMES)
    ws["E12"] = "10-24"
    ws["F12"] = "=COUNTIFS('{0}'!$D$2:$D${1},\">=10\",'{0}'!$D$2:$D${1},\"<=24\")".format(CALC, GAMES)
    ws["E13"] = "25+"
    ws["F13"] = "=COUNTIF('{}'!$D$2:$D${},\">=25\")".format(CALC, GAMES)

    head(ws, "H4", "Genre")
    head(ws, "I4", "Games")
    for i, t in enumerate(TYPES):
        ws["H%d" % (5 + i)] = t
        ws["I%d" % (5 + i)] = "=COUNTIF(games!$C$2:$C${},$H{})".format(GAMES, 5 + i)

    head(ws, "K4", "Rank")
    head(ws, "L4", "Game")
    head(ws, "M4", "Degree")
    for i in range(15):
        r = 5 + i
        ws["K%d" % r] = i + 1
        ws["L%d" % r] = ("=IFERROR(INDEX('{0}'!$A$2:$A${1},"
                         "MATCH(LARGE('{0}'!$O$2:$O${1},{2}),'{0}'!$O$2:$O${1},0)),\"\")"
                         ).format(CALC, GAMES, i + 1)
        ws["M%d" % r] = ("=IFERROR(INDEX('{0}'!$D$2:$D${1},"
                         "MATCH(LARGE('{0}'!$O$2:$O${1},{2}),'{0}'!$O$2:$O${1},0)),\"\")"
                         ).format(CALC, GAMES, i + 1)

    head(ws, "O4", "Year")
    head(ws, "P4", "Games")
    head(ws, "Q4", "Connections")
    for i, yr in enumerate(range(YEAR0, YEAR1 + 1)):
        r = 5 + i
        ws["O%d" % r] = yr
        ws["P%d" % r] = "=COUNTIF(games!$B$2:$B${},$O{})".format(GAMES, r)
        ws["Q%d" % r] = "=COUNTIF('{}'!$T$2:$T${},$O{})".format(CALC, CONNS, r)

    head(ws, "S4", "Edge span")
    head(ws, "T4", "Connections")
    for i in range(11):
        r = 5 + i
        ws["S%d" % r] = i
        ws["T%d" % r] = "=COUNTIF('{}'!$V$2:$V${},$S{})".format(CALC, CONNS, r)
    ws["S16"] = "11-20"
    ws["T16"] = "=COUNTIFS('{0}'!$V$2:$V${1},\">=11\",'{0}'!$V$2:$V${1},\"<=20\")".format(CALC, CONNS)
    ws["S17"] = "21+"
    ws["T17"] = "=COUNTIF('{}'!$V$2:$V${},\">=21\")".format(CALC, CONNS)

    for col, w in (("A", 22), ("B", 12), ("C", 52), ("E", 10), ("F", 9), ("H", 14),
                   ("I", 9), ("K", 7), ("L", 32), ("M", 9), ("O", 8), ("P", 9),
                   ("Q", 13), ("S", 11), ("T", 13)):
        ws.column_dimensions[col].width = w
    return ws


def add_charts(ws):
    def style(ch, t, w, h):
        ch.title = t
        ch.width, ch.height = w, h
        ch.style = 2

    # 1. Games per release year
    c1 = BarChart()
    style(c1, "Games per release year", 26, 9)
    c1.type = "col"
    c1.add_data(Reference(ws, min_col=16, min_row=4, max_row=4 + (YEAR1 - YEAR0 + 1)), titles_from_data=True)
    c1.set_categories(Reference(ws, min_col=15, min_row=5, max_row=4 + (YEAR1 - YEAR0 + 1)))
    c1.y_axis.title = "Games"
    c1.gapWidth = 40
    ws.add_chart(c1, "A21")

    # 2. Connections created per year
    c2 = BarChart()
    style(c2, "Connections by influencer's year", 26, 9)
    c2.type = "col"
    c2.add_data(Reference(ws, min_col=17, min_row=4, max_row=4 + (YEAR1 - YEAR0 + 1)), titles_from_data=True)
    c2.set_categories(Reference(ws, min_col=15, min_row=5, max_row=4 + (YEAR1 - YEAR0 + 1)))
    c2.y_axis.title = "Connections"
    c2.gapWidth = 40
    ws.add_chart(c2, "A40")

    # 3. Degree distribution
    c3 = BarChart()
    style(c3, "Degree distribution — how connected is a typical game?", 16, 9)
    c3.type = "col"
    c3.add_data(Reference(ws, min_col=6, min_row=4, max_row=13), titles_from_data=True)
    c3.set_categories(Reference(ws, min_col=5, min_row=5, max_row=13))
    c3.y_axis.title = "Games"
    c3.x_axis.title = "Connections"
    ws.add_chart(c3, "R21")

    # 4. Top hubs
    c4 = BarChart()
    style(c4, "The 15 biggest hubs", 16, 9)
    c4.type = "bar"
    c4.add_data(Reference(ws, min_col=13, min_row=4, max_row=19), titles_from_data=True)
    c4.set_categories(Reference(ws, min_col=12, min_row=5, max_row=19))
    ws.add_chart(c4, "R40")

    # 5. Genre split
    c5 = BarChart()
    style(c5, "Games by genre", 12, 7)
    c5.type = "col"
    c5.add_data(Reference(ws, min_col=9, min_row=4, max_row=8), titles_from_data=True)
    c5.set_categories(Reference(ws, min_col=8, min_row=5, max_row=8))
    ws.add_chart(c5, "AC21")

    # 6. Edge span
    c6 = BarChart()
    style(c6, "Years between an influence and its influencee", 12, 7)
    c6.type = "col"
    c6.add_data(Reference(ws, min_col=20, min_row=4, max_row=17), titles_from_data=True)
    c6.set_categories(Reference(ws, min_col=19, min_row=5, max_row=17))
    ws.add_chart(c6, "AC36")

    # The timeline-lanes scatter is added separately: its data lives on the
    # calc sheet, so its references must be built against that worksheet.
    return None


def main():
    wb = openpyxl.load_workbook(SRC)
    calc = build_calc(wb)
    dash = build_dash(wb)
    add_charts(dash)
    # The scatter reads the calc sheet, so build its refs against that sheet.
    sc2 = ScatterChart()
    sc2.title = "Timeline lanes — every game by release year and genre"
    sc2.width, sc2.height = 34, 13
    sc2.style = 2
    sc2.x_axis.title = "Release year"
    sc2.y_axis.title = "1 Action   2 Strategy   3 Deckbuilder   4 Traditional"
    for i in range(4):
        xr = Reference(calc, min_col=7 + i * 2, min_row=2, max_row=GAMES)
        yr = Reference(calc, min_col=8 + i * 2, min_row=1, max_row=GAMES)
        s = Series(yr, xr, title=TYPES[i])
        s.marker = Marker(symbol="circle", size=4)
        s.graphicalProperties.line = LineProperties(noFill=True)
        sc2.series.append(s)
    dash.add_chart(sc2, "A59")
    wb.save(SRC)
    print("saved", SRC)


if __name__ == "__main__":
    main()

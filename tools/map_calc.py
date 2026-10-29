#!/usr/bin/env python3
"""Write `Map Calc` and `Map Analysis`'s formulas, or check that they are sound.

    python3 tools/map_calc.py           # rewrite both sheets' formulas in place
    python3 tools/map_calc.py --check   # CI: fail if they are broken or outgrown

**Why this exists.** `Map Calc` used to read the games sheet row by row
(`games!$A933`). Every row the owner deleted, cut or sorted in `games` or
`connections` made Excel rewrite those references: the deleted row's became
`games!#REF!`, and every one below it moved to read the row above its own. A
single `#REF!` in the degree column is enough to make every MEDIAN, MAX and
LARGE over it fail, so the dashboard went to `#REF!` and empty hub tables.
That happened three times (CHANGELOG: the 12 Oct upload, the realign, and the
22 Oct upload), and each fix was a one-shot that put the rows back until the
next edit.

So nothing here names a row of another sheet any more:

  - a per-row read is `INDEX(games!$A:$A,ROW())`. A whole-column reference is
    one Excel never rewrites, whatever happens to the rows inside it, so a
    delete, an insert or a sort leaves every formula reading its own row;
  - the connection names are mirrored into `Map Calc` (W, X) the same way, and
    every COUNTIF, MATCH and SUMIFS runs over `Map Calc`'s own columns. Two
    ranges on different sheets in one COUNTIFS were the other trap: deleting a
    row shrinks one of them, and a size mismatch is a #VALUE!;
  - `Map Analysis` reads only `Map Calc`, or a whole column of `connections`.

What can still go wrong is OUTGROWING the blocks (rows of formulas are laid
down in advance) and the year table (one row per year). `--check` fails before
either happens, and rerunning this script lays them down again larger.

**On the map.** A default run walks the owned games in the largest connected
piece of the owned-only graph (`RunGraph._prune_to_main_component`). A
spreadsheet cannot find connected components, so the sheet uses: owned, with
at least one owned neighbour, and not one half of a two-game island (a pair
that only connect to each other: sequel pairs, mostly). That is exact while
every island is a pair, as all five were on 22 Oct 2026. `--check` computes
the real component and says when an island of three or more appears.

**Influence (Katz centrality).** A game's score counts every game it
influenced as 1, every game those influenced as α, the generation after as α²,
and so on over every path: Katz (1953), the standard "reach, discounted by
distance" measure from network science. Spreadsheets cannot recurse without a
circular reference, so `Map Calc` lays it out one generation per column
(Gen 1..GENS): a game's generation k+1 is the sum of generation k over the
games it influenced, read through the connections block. The score is
SUMPRODUCT(gens, α^{0..GENS-1}), with α read from `Map Analysis`!AP2, which the
owner can change and a rerun never resets. The top 20 sit at AN:AT there (the
score, then what it is made of: direct, 2nd and 3rd generation, the rest), with
a stacked bar of the same under the table (`influence_chart`, made on the first
run and rewritten in place after).
`--check` fails if the longest chain outgrows GENS or influence ever runs in a
circle. On 28 Oct 2026 the longest chain is 13 games, and the formulas match a
direct recursion exactly.

**Games to buy.** The table at AD:AH ranks the unowned games by how many owned
games they connect to, and names those games (`Connects to`, a TEXTJOIN array
formula). `Adds to the map` is how many games a run's map would gain by buying
it: none unless it touches a game already on the map, and otherwise itself,
plus every owned game off the map it touches, plus each of those one's own
owned neighbours (a two-game island comes on whole; a loner on its own). That
reads one step past each neighbour, so a longer chain of off-map games counts
short, and touching both halves of one island counts it twice. It sat at AD:AF
until 28 Oct 2026; the hub and influence tables moved two columns right to make
room, and `write` carries an old layout's cells (the owner's α included) across.

Cached values are dropped from every cell written and Excel is asked to
recalculate on open (`fullCalcOnLoad`), the same as `_map_calc_realign.py`
did. Sheet XML is edited directly: openpyxl cannot round-trip this workbook
(CLAUDE.md).
"""

import math
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook, _cell_value, _esc  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
CALC, DASH = "Map Calc", "Map Analysis"
TYPES = ["Action", "Strategy", "Deckbuilder", "Traditional"]
LANE = {t: i + 1 for i, t in enumerate(TYPES)}
FIRST_YEAR = 1978
# Rows of formulas laid down past the data. --check fails when less than the
# MIN is left; a rerun lays down the BLOCK multiple above data + HEADROOM.
HEADROOM, MIN_HEADROOM, BLOCK = 500, 100, 500
HUB_RANKS = 20
# The first chart row (1-based) once the measure table's on-map section is in.
CHARTS_FROM_ROW = 40

# Influence (Katz centrality): every game a game influenced counts 1, every game
# THOSE influenced counts ALPHA, the next generation ALPHA^2, and so on, over
# every path. A spreadsheet cannot recurse without a circular reference, so each
# generation is its own column: generation k+1 of a game is the sum of
# generation k over the games it influenced. GENS has to cover the longest
# influence chain on the sheet (13 on 28 Oct 2026); --check fails when it does
# not. ALPHA is only the starting value: the cell on Map Analysis is the live one.
GENS = 16
ALPHA = 0.5
ALPHA_CELL = "'%s'!$AP$2" % "Map Analysis"


def _col(n):
    s = ""
    while n:
        n, rem = divmod(n - 1, 26)
        s = chr(65 + rem) + s
    return s


def _num(c):
    n = 0
    for ch in c:
        n = n * 26 + ord(ch) - 64
    return n


# Map Calc: influence and its rank key, then generations 1..GENS on the games
# block, then each connection's influencee at generations 1..GENS-1.
K_SCORE, K_KEY = "AM", "AN"
K_GEN = [_col(_num("AO") + i) for i in range(GENS)]
K_DOWN = [_col(_num(K_GEN[-1]) + 2 + i) for i in range(GENS - 1)]
# What buying a game would add to the map: on the games block, an off-map owned
# game's group (itself and its owned neighbours), how many map games a game
# touches, and the sum; on the connections block, both ends' reads of those.
_B0 = _num(K_DOWN[-1]) + 2
B_GROUP, B_MAPNB, B_ADDS, B_ON_A, B_ON_B, B_GRP_A, B_GRP_B = (_col(_B0 + i) for i in range(7))

# Styles already in the workbook (cellXfs indices), read off the cells that
# build_map_charts.py styled: header, measure label, value, note, 0.00, 0%.
S_HEAD, S_LABEL, S_VALUE, S_NOTE, S_DEC, S_PCT, S_SPAN = 14, 15, 16, 17, 20, 18, 24


# ── Map Calc ────────────────────────────────────────────────────────────────

def calc_cells(r, G, C):
    """Every formula on `Map Calc` row r, for a games block to row G and a
    connections block to row C."""
    rg = lambda col: "$%s$2:$%s$%d" % (col, col, G)    # noqa: E731
    rc = lambda col: "$%s$2:$%s$%d" % (col, col, C)    # noqa: E731
    row = lambda sheet, col: "INDEX(%s!$%s:$%s,ROW())" % (sheet, col, col)  # noqa: E731
    f = {}
    if r <= G:
        name = "TRIM(%s)" % row("games", "A")
        f["A"] = 'IF(%s="","",%s)' % (name, name)
        # A blank cell read through INDEX is a 0, and a 0 year is a span of 2000.
        for col in "BC":
            f[col] = 'IF(OR($A{0}="",%s=""),"",%s)' % (row("games", col), row("games", col))
        f["D"] = 'IF($A{0}="","",COUNTIF(%s,$A{0})+COUNTIF(%s,$A{0}))' % (rc("W"), rc("X"))
        f["E"] = 'IF($A{0}="","",IFERROR(MATCH($C{0},$R$2:$R$5,0),0))'
        # Row position is uncorrelated with year (the sheet is alphabetical), so
        # it spreads a busy year's dots for free; an expanding COUNTIFS of
        # same-year siblings was the accurate way and took 13 minutes.
        f["F"] = 'IF($A{0}="","",MOD(ROW(),34))'
        for i, t in enumerate(TYPES):
            f["GIKM"[i]] = 'IF($A{0}="",NA(),IF($C{0}="%s",$B{0},NA()))' % t
            f["HJLN"[i]] = 'IF($A{0}="",NA(),IF($C{0}="%s",%d+$F{0}*0.023,NA()))' % (t, LANE[t])
        # Tie-break so LARGE/MATCH cannot pick the same hub twice.
        f["O"] = 'IF($A{0}="","",$D{0}+ROW()/1000000)'
        own = row("games", "H")
        f["P"] = 'IF(OR($A{0}="",%s=""),"",%s)' % (own, own)
        f["Q"] = 'IF(OR($A{0}="",$P{0}<>"Yes"),"",$D{0}+ROW()/1000000)'
        # Owned neighbours: for an owned game its degree inside the owned graph,
        # for an unowned one how many owned games buying it would join.
        f["AG"] = ('IF($A{0}="","",COUNTIFS(%s,$A{0},%s,"Yes")+COUNTIFS(%s,$A{0},%s,"Yes"))'
                   % (rc("W"), rc("AB"), rc("X"), rc("AA")))
        f["AH"] = ('IF(OR($P{0}<>"Yes",N($AG{0})=0),"",IF(AND($AG{0}=1,'
                   'COUNTIFS(%s,$A{0},%s,1)+COUNTIFS(%s,$A{0},%s,1)>0),"","Yes"))'
                   % (rc("W"), rc("AE"), rc("X"), rc("AE")))
        f["AI"] = 'IF($AH{0}="Yes",$AG{0},"")'
        f["AJ"] = 'IF($AI{0}="","",$AI{0}+ROW()/1000000)'
        f["AK"] = 'IF(OR($A{0}="",$P{0}="Yes",N($AG{0})=0),"",$AG{0}+ROW()/1000000)'
        f["AL"] = 'IF($A{0}="","",%s&"")' % row("games", "J")
        # Influence: generation 1 is the games this one influenced directly;
        # generation k+1 sums generation k over them (via the connections block).
        f[K_GEN[0]] = 'IF($A{0}="","",COUNTIF(%s,$A{0}))' % rc("W")
        for k in range(1, GENS):
            f[K_GEN[k]] = 'IF($A{0}="","",SUMIFS(%s,%s,$A{0}))' % (rc(K_DOWN[k - 1]), rc("W"))
        powers = ",".join(str(k) for k in range(GENS))
        f[K_SCORE] = ('IF($A{0}="","",SUMPRODUCT($%s{0}:$%s{0},%s^{%s}))'
                      % (K_GEN[0], K_GEN[-1], ALPHA_CELL, powers))
        f[K_KEY] = 'IF($A{0}="","",$%s{0}+ROW()/10000000)' % K_SCORE
        # Buying: an owned game off the map comes on with its own owned
        # neighbours (all off the map too, or it would be on it).
        f[B_GROUP] = 'IF(OR($A{0}="",$P{0}<>"Yes",$AH{0}="Yes"),"",1+N($AG{0}))'
        f[B_MAPNB] = ('IF($A{0}="","",COUNTIFS(%s,$A{0},%s,"Yes")+COUNTIFS(%s,$A{0},%s,"Yes"))'
                      % (rc("W"), rc(B_ON_B), rc("X"), rc(B_ON_A)))
        f[B_ADDS] = ('IF(OR($A{0}="",$P{0}="Yes"),"",IF(N($%s{0})=0,0,1+SUMIFS(%s,%s,$A{0})+SUMIFS(%s,%s,$A{0})))'
                     % (B_MAPNB, rc(B_GRP_B), rc("W"), rc(B_GRP_A), rc("X")))
    if r <= C:
        name = "TRIM(%s)" % row("connections", "A")
        f["W"] = 'IF(%s="","",%s)' % (name, name)
        f["X"] = 'IF($W{0}="","",TRIM(%s))' % row("connections", "B")
        f["Y"] = 'IF($W{0}="","",IFERROR(MATCH($W{0},%s,0),""))' % rg("A")
        f["Z"] = 'IF($X{0}="","",IFERROR(MATCH($X{0},%s,0),""))' % rg("A")
        f["T"] = 'IF($Y{0}="","",INDEX(%s,$Y{0}))' % rg("B")
        f["U"] = 'IF($Z{0}="","",INDEX(%s,$Z{0}))' % rg("B")
        f["V"] = 'IF(OR($T{0}="",$U{0}=""),"",$U{0}-$T{0})'
        f["AA"] = 'IF($Y{0}="","",INDEX(%s,$Y{0}))' % rg("P")
        f["AB"] = 'IF($Z{0}="","",INDEX(%s,$Z{0}))' % rg("P")
        f["AC"] = 'IF(AND($AA{0}="Yes",$AB{0}="Yes"),1,"")'
        f["AD"] = ('IF(OR($Y{0}="",$Z{0}=""),"",IF(INDEX(%s,$Y{0})=INDEX(%s,$Z{0}),0,1))'
                   % (rg("C"), rg("C")))
        # Both ends owned and each with no other owned neighbour: a two-game
        # island, which no route from the mainland reaches.
        f["AE"] = ('IF($AC{0}<>1,"",IF(AND(INDEX(%s,$Y{0})=1,INDEX(%s,$Z{0})=1),1,""))'
                   % (rg("AG"), rg("AG")))
        # The influencee's own generations, for its influencer's next one.
        for k in range(GENS - 1):
            f[K_DOWN[k]] = 'IF($Z{0}="","",INDEX(%s,$Z{0}))' % rg(K_GEN[k])
        f[B_ON_A] = 'IF($Y{0}="","",INDEX(%s,$Y{0})&"")' % rg("AH")
        f[B_ON_B] = 'IF($Z{0}="","",INDEX(%s,$Z{0})&"")' % rg("AH")
        f[B_GRP_A] = 'IF($Y{0}="","",INDEX(%s,$Y{0}))' % rg(B_GROUP)
        f[B_GRP_B] = 'IF($Z{0}="","",INDEX(%s,$Z{0}))' % rg(B_GROUP)
    return {c: s.replace("{0}", str(r)) for c, s in f.items()}


CALC_HEADERS = {
    "A": "Game", "B": "Year", "C": "Type", "D": "Degree", "E": "Lane", "F": "Stack",
    "G": "Action X", "H": "Action Y", "I": "Strategy X", "J": "Strategy Y",
    "K": "Deckbuilder X", "L": "Deckbuilder Y", "M": "Traditional X", "N": "Traditional Y",
    "O": "Rank key", "P": "Owned", "Q": "Owned rank key", "R": "Genre",
    "T": "Influencer yr", "U": "Influencee yr", "V": "Span (yrs)",
    "W": "Influencer", "X": "Influencee", "Y": "Influencer row", "Z": "Influencee row",
    "AA": "Influencer owned", "AB": "Influencee owned", "AC": "Both owned",
    "AD": "Cross-genre", "AE": "Island pair",
    "AG": "Owned neighbours", "AH": "On map", "AI": "Map degree",
    "AJ": "Map rank key", "AK": "Buy rank key", "AL": "Steam page",
    K_SCORE: "Influence (Katz)", K_KEY: "Influence rank key",
}
CALC_HEADERS.update({c: "Gen %d" % (k + 1) for k, c in enumerate(K_GEN)})
CALC_HEADERS.update({c: "Influencee gen %d" % (k + 1) for k, c in enumerate(K_DOWN)})
CALC_HEADERS.update({B_GROUP: "Off-map group", B_MAPNB: "Map neighbours", B_ADDS: "Adds to the map",
                     B_ON_A: "Influencer on map", B_ON_B: "Influencee on map",
                     B_GRP_A: "Influencer off-map group", B_GRP_B: "Influencee off-map group"})
CALC_LAST = B_GRP_B
STR_COLS = {"A", "C", "P", "W", "X", "AA", "AB", "AH", "AL", B_ON_A, B_ON_B}


# ── Map Analysis ────────────────────────────────────────────────────────────

def measures(G, C):
    """(label, formula, note, style) for the measure table, in order from row 5.
    Formulas name the measures they build on as {Label}, never as a cell."""
    m = lambda col, last=G: "'%s'!$%s$2:$%s$%d" % (CALC, col, col, last)  # noqa: E731
    span = m("V", C)
    return [
        ("Games", '=SUMPRODUCT(--(%s<>""))' % m("A"), "Nodes in the graph", S_VALUE),
        ("Games owned", '=COUNTIF(%s,"Yes")' % m("P"),
         "Marked Owned — the catalog a default run draws from", S_VALUE),
        ("Owned share", "=IF({Games}=0,0,{Games owned}/{Games})",
         "How much of the sheet a run can actually be sent to", S_PCT),
        ("Connections", '=SUMPRODUCT(--(%s<>""))' % m("W", C), "Authored influence edges", S_VALUE),
        ("Average degree", "=IF({Games}=0,0,2*{Connections}/{Games})",
         "Connections per game — under 3 means a sparse graph", S_DEC),
        ("Average degree (owned)", '=IFERROR(SUMIFS(%s,%s,"Yes")/{Games owned},0)' % (m("D"), m("P")),
         "Over the owned games, but still counting their links to games you don't own", S_DEC),
        ("Median degree", "=MEDIAN(%s)" % m("D"), "Half of all games sit at or below this", S_VALUE),
        ("Largest hub", "=MAX(%s)" % m("D"), "Degree of the single most connected game", S_VALUE),
        ("Leaves (degree 1)", "=COUNTIF(%s,1)" % m("D"), "Dead ends — one way in, the same way out", S_VALUE),
        ("Isolated (degree 0)", "=COUNTIF(%s,0)" % m("D"),
         "No connection at all; only a rift or Transmute ever puts one in a run", S_VALUE),
        ("Leaves + isolated", "={Leaves (degree 1)}+{Isolated (degree 0)}",
         "Share of the map that carries no routing information", S_VALUE),
        ("Owned & routable", '=COUNTIFS(%s,"Yes",%s,">1")' % (m("P"), m("D")),
         "Owned games with more than one way out — real junctions on a route", S_VALUE),
        ("Owned dead ends", '=COUNTIFS(%s,"Yes",%s,"<=1")' % (m("P"), m("D")),
         "Owned games the run can only reach and turn around in", S_VALUE),
        ("Backward in time", '=SUMPRODUCT((%s<>"")*(%s<0))' % (span, span),
         "MUST BE 0 — an influence cannot point at an older game", S_VALUE),
        ("Same year", '=SUMPRODUCT((%s<>"")*(%s=0))' % (span, span),
         "Legal: a demo influencing something shipped the same year", S_VALUE),
        ("Median edge span", "=MEDIAN(%s)" % span,
         "Years between an influencer and what it influenced", S_SPAN),
        ("Dev/Series flagged", '=COUNTIF(connections!$D:$D,"Yes")',
         "Sequel / same-devs links, distinct from plain influence", S_VALUE),
        ("With a source", "=COUNTA(connections!$E:$E)-COUNTA(connections!$E$1)",
         "Connections carrying a URL or note as evidence", S_VALUE),
        ("Owned, no Steam page", '=COUNTIFS(%s,"Yes",%s,"")' % (m("P"), m("AL")),
         "Owned rows with nothing to link to — a gap in the sheet, not the graph", S_VALUE),
        None,   # the "On the map" heading row
        ("Games on the map", '=COUNTIF(%s,"Yes")' % m("AH"),
         "Owned games in the main group: every game a default run's routes can reach", S_VALUE),
        ("Owned, off the map", "={Games owned}-{Games on the map}",
         "Owned games no route reaches (islands and loners). Transmute's pool", S_VALUE),
        ("Rift pool", '=COUNTIFS(%s,"Yes",%s,0)' % (m("P"), m("AG")),
         "Owned games with no owned connection at all: what a rift can pull onto the map", S_VALUE),
        ("Connections on the map", "=SUM(%s)/2" % m("AI"),
         "Influences with both ends on the map: the roads a run can walk", S_VALUE),
        ("Share of connections on the map", "=IF({Connections}=0,0,{Connections on the map}/{Connections})",
         "The rest touch a game you don't own, or an island", S_PCT),
        ("Average degree on the map", "=IFERROR(SUM(%s)/{Games on the map},0)" % m("AI"),
         "Roads out of a map game, counting only roads to other map games — what a player on the map sees", S_DEC),
        ("Median degree on the map", "=MEDIAN(%s)" % m("AI"),
         "Half of the map's games have this many roads or fewer", S_VALUE),
        ("Largest hub on the map", "=MAX(%s)" % m("AI"),
         "The most roads out of any one map game (see the table under AJ)", S_VALUE),
        ("Dead ends on the map", "=COUNTIF(%s,1)" % m("AI"),
         "One road in and out. Two off the same hub are where a rift usually goes", S_VALUE),
        ("Dead-end share on the map", "=IF({Games on the map}=0,0,{Dead ends on the map}/{Games on the map})",
         "How much of the map is a cul-de-sac", S_PCT),
        ("Unowned games touching the map", '=COUNTIF(%s,">0")' % m("AK"),
         "Games you don't own with a connection to one you do (best buys under AD)", S_VALUE),
        ("Cross-genre connections", "=IFERROR(SUM({0})/COUNT({0}),0)".replace("{0}", m("AD", C)),
         "Influences that cross from one genre to another", S_PCT),
    ]


def dash_cells(G, C, last_year):
    """{address: (kind, value, style)} for every cell this script owns on
    `Map Analysis`. kind is 'f' (formula), 'a' (array formula), 's' (text)
    or 'n' (number)."""
    m = lambda col, last=G: "'%s'!$%s$2:$%s$%d" % (CALC, col, col, last)  # noqa: E731
    out = {}

    def put(addr, kind, value, style=None):
        out[addr] = (kind, value, style)

    rows = measures(G, C)
    at = {}
    for i, row in enumerate(rows):
        if row:
            at[row[0]] = "B%d" % (5 + i)
    for i, row in enumerate(rows):
        r = 5 + i
        if row is None:
            for col, text in zip("ABC", ("On the map", "Value", "What it means")):
                put("%s%d" % (col, r), "s", text, S_HEAD)
            continue
        label, formula, note, style = row
        put("A%d" % r, "s", label, S_LABEL)
        put("B%d" % r, "f", re.sub(r"\{([^}]+)\}", lambda mm: at[mm.group(1)], formula)[1:], style)
        put("C%d" % r, "s", note, S_NOTE)

    # Degree distribution: every game, the owned ones, and the map's own degree.
    put("H4", "s", "On the map", S_HEAD)
    bands = [(str(n), "%d" % n, None) for n in range(6)] + [
        ("6-9", '">=6"', '"<=9"'), ("10-24", '">=10"', '"<=24"'), ("25+", '">=25"', None)]
    for i, (lab, lo, hi) in enumerate(bands):
        r = 5 + i
        put("E%d" % r, "s", lab)
        crit = lambda col: "%s,%s" % (m(col), lo) + (",%s,%s" % (m(col), hi) if hi else "")  # noqa: E731
        put("F%d" % r, "f", "COUNTIFS(%s)" % crit("D"))
        put("G%d" % r, "f", 'COUNTIFS(%s,%s,"Yes")' % (crit("D"), m("P")))
        put("H%d" % r, "f", "COUNTIFS(%s)" % crit("AI"))

    for i, t in enumerate(TYPES):
        r = 5 + i
        put("J%d" % r, "f", "COUNTIF(%s,$I%d)" % (m("C"), r))
        put("K%d" % r, "f", 'COUNTIFS(%s,$I%d,%s,"Yes")' % (m("C"), r, m("P")))

    def ranked(rank_col, name_col, val_col, key, val, r, k):
        look = "IFERROR(INDEX(%s,MATCH(LARGE(%s,%d),%s,0)),\"\")"
        put("%s%d" % (rank_col, r), "n", k)
        put("%s%d" % (name_col, r), "f", look % (m("A"), m(key), k, m(key)))
        put("%s%d" % (val_col, r), "f", look % (m(val), m(key), k, m(key)))

    for col, label in (("AD", "Rank"), ("AE", "Game to buy"), ("AF", "Owned games it joins"),
                       ("AG", "Connects to"), ("AH", "Adds to the map"),
                       ("AJ", "Rank"), ("AK", "Hub on the map"), ("AL", "Map degree")):
        put("%s4" % col, "s", label, S_HEAD)
    calc = lambda col: "'%s'!$%s$2:$%s$%d" % (CALC, col, col, C)  # noqa: E731
    for k in range(1, HUB_RANKS + 1):
        r = 4 + k
        ranked("N", "O", "P", "O", "D", r, k)
        ranked("R", "S", "T", "Q", "D", r, k)
        ranked("AD", "AE", "AF", "AK", "AG", r, k)
        # The owned games it connects to, by name: an array formula, since
        # TEXTJOIN joins an IF over the whole connections block.
        put("AG%d" % r, "a", 'IF($AE{0}="","",_xlfn.TEXTJOIN(", ",TRUE,'
            'IF((%s=$AE{0})*(%s="Yes"),%s,""),IF((%s=$AE{0})*(%s="Yes"),%s,"")))'.replace("{0}", str(r))
            % (calc("W"), calc("AB"), calc("X"), calc("X"), calc("AA"), calc("W")))
        put("AH%d" % r, "f", "IFERROR(INDEX(%s,MATCH(LARGE(%s,%d),%s,0)),\"\")"
            % (m(B_ADDS), m("AK"), k, m("AK")))
        ranked("AJ", "AK", "AL", "AJ", "AI", r, k)
        ranked("AN", "AO", "AP", K_KEY, K_SCORE, r, k)
        put("AQ%d" % r, "f", "IFERROR(INDEX(%s,MATCH(LARGE(%s,%d),%s,0)),\"\")"
            % (m(K_GEN[0]), m(K_KEY), k, m(K_KEY)))
        # What the score is made of, for the stacked chart: generations 2 and
        # 3 weighted by the decay, and everything further down as one rest.
        for col, gen in (("AR", 1), ("AS", 2)):
            put("%s%d" % (col, r), "f", "IFERROR(%s^%d*INDEX(%s,MATCH(LARGE(%s,%d),%s,0)),\"\")"
                % (ALPHA_CELL, gen, m(K_GEN[gen]), m(K_KEY), k, m(K_KEY)))
        put("AT%d" % r, "f", 'IF($AP{0}="","",$AP{0}-$AQ{0}-$AR{0}-$AS{0})'.replace("{0}", str(r)))

    # Influence: the decay is the owner's to tune, so write() keeps a value
    # already in its cell; this one is only the first.
    put("AO2", "s", "Decay α: each generation further down counts α times the one above", S_NOTE)
    put("AP2", "n", ALPHA, S_DEC)
    for col, label in (("AN", "Rank"), ("AO", "Most influential (Katz)"), ("AP", "Influence"),
                       ("AQ", "Directly influenced"), ("AR", "2nd generation"),
                       ("AS", "3rd generation"), ("AT", "4th and beyond")):
        put("%s4" % col, "s", label, S_HEAD)

    for i, yr in enumerate(range(FIRST_YEAR, last_year + 1)):
        r = 5 + i
        put("V%d" % r, "n", yr)
        put("W%d" % r, "f", "COUNTIF(%s,$V%d)" % (m("B"), r))
        put("X%d" % r, "f", 'COUNTIFS(%s,$V%d,%s,"Yes")' % (m("B"), r, m("P")))
        put("Y%d" % r, "f", "COUNTIF(%s,$V%d)" % (m("T", C), r))

    for i in range(11):
        put("AB%d" % (5 + i), "f", "COUNTIF(%s,$AA%d)" % (m("V", C), 5 + i))
    put("AB16", "f", 'COUNTIFS(%s,">=11",%s,"<=20")' % (m("V", C), m("V", C)))
    put("AB17", "f", 'COUNTIF(%s,">=21")' % m("V", C))
    return out


# ── sheet XML ───────────────────────────────────────────────────────────────

CELL = re.compile(r'<c r="([A-Z]+)(\d+)"([^>]*?)(?:/>|>(.*?)</c>)', re.S)


def col_index(letters):
    n = 0
    for ch in letters:
        n = n * 26 + ord(ch) - 64
    return n


def letters(n):
    s = ""
    while n:
        n, rem = divmod(n - 1, 26)
        s = chr(65 + rem) + s
    return s


def cell_xml(addr, kind, value, style):
    s = ' s="%d"' % style if style is not None else ""
    if kind == "n":
        return '<c r="%s"%s><v>%s</v></c>' % (addr, s, value)
    if kind == "s":
        return '<c r="%s"%s t="inlineStr"><is><t>%s</t></is></c>' % (addr, s, _esc(value))
    if kind == "a":
        return '<c r="%s"%s t="str"><f t="array" ref="%s">%s</f></c>' % (addr, s, addr, _esc(value))
    t = ' t="str"' if kind == "fs" else ""
    return '<c r="%s"%s%s><f>%s</f></c>' % (addr, s, t, _esc(value))


def split_sheet(xml):
    head, data, tail = re.match(r"(.*<sheetData>)(.*)(</sheetData>.*)", xml, re.S).groups()
    rows = {}
    for n, attrs, body in re.findall(r'<row r="(\d+)"([^>]*)>(.*?)</row>', data, re.S):
        cells = {}
        for col, r, a, b in CELL.findall(body):
            cells[col] = (a, b)
        # spans is a hint Excel trusts; a row given new columns must not keep it.
        rows[int(n)] = (re.sub(r'\s*spans="[^"]*"', "", attrs), cells)
    return head, rows, tail


def formulas_in(xml):
    """{address: formula text} for every cell with a written (unshared) formula."""
    out = {}
    for col, r, a, b in CELL.findall(xml):
        f = re.search(r"<f[^>]*>(.*?)</f>", b or "", re.S)
        if f:
            out["%s%s" % (col, r)] = f.group(1)
    return out


def _unesc(s):
    return s.replace("&quot;", '"').replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


# ── the sheets' own data, for sizing and for the exact check ───────────────

def values(wb, sheet):
    """The sheet's cached values as row lists. Read-only, so unlike
    Workbook.read_grid it does not mind the formula columns `games` carries."""
    xml = wb._by_name[wb.sheet_parts(sheet)[0]].decode("utf-8")
    grid = []
    for body in re.findall(r'<row r="\d+"[^>]*>(.*?)</row>', xml, re.S):
        row = {}
        for col, r, a, b in CELL.findall(body):
            row[col_index(col) - 1] = _cell_value(a, b or "", wb._shared)
        grid.append([row.get(i, "") for i in range(max(row, default=-1) + 1)])
    return grid


def read_data(wb):
    games = values(wb, "games")
    conns = values(wb, "connections")
    g = [r for r in games[1:] if r and str(r[0] or "").strip()]
    c = [r for r in conns[1:] if r and str(r[0] or "").strip()]
    return g, c


def bounds(n_games, n_conns):
    up = lambda n: max(BLOCK * math.ceil((n + 1 + HEADROOM) / BLOCK), 2 * BLOCK)  # noqa: E731
    return up(n_games), up(n_conns)


def main_component(games, conns):
    """The exact map: owned games in the largest piece of the owned-only graph,
    ties to the lowest name, as RunGraph lays it."""
    key = lambda s: str(s).strip().lower()   # noqa: E731
    owned = {key(r[0]) for r in games if len(r) > 7 and str(r[7] or "").strip().lower() == "yes"}
    adj = defaultdict(set)
    for r in conns:
        a, b = key(r[0]), key(r[1] if len(r) > 1 else "")
        if a in owned and b in owned and a != b:
            adj[a].add(b)
            adj[b].add(a)
    seen, comps = set(), []
    for s in sorted(owned):
        if s in seen:
            continue
        comp, stack = [], [s]
        seen.add(s)
        while stack:
            x = stack.pop()
            comp.append(x)
            for y in adj[x] - seen:
                seen.add(y)
                stack.append(y)
        comps.append(comp)
    comps.sort(key=lambda c: (-len(c), min(c)))
    main = set(comps[0]) if comps else set()
    islands = [c for c in comps[1:] if len(c) > 2]
    return owned, adj, main, islands


def influence_depth(games, conns):
    """The most generations any game's influence reaches (a game that influenced
    nothing is 0), or None if influence runs in a circle."""
    names = {str(r[0]).strip() for r in games}
    out = defaultdict(set)
    for r in conns:
        a, b = str(r[0]).strip(), str(r[1] if len(r) > 1 else "").strip()
        if a in names and b in names:
            out[a].add(b)
    depth, busy = {}, set()

    def walk(n):
        if n in depth:
            return depth[n]
        if n in busy:
            raise ValueError
        busy.add(n)
        depth[n] = max((walk(x) + 1 for x in out[n]), default=0)
        busy.discard(n)
        return depth[n]

    sys.setrecursionlimit(10000)
    try:
        return max((walk(n) for n in names), default=0)
    except ValueError:
        return None


# ── write ───────────────────────────────────────────────────────────────────

def write(wb):
    games, conns = read_data(wb)
    G, C = bounds(len(games) + 1, len(conns) + 1)
    years = [int(r[1]) for r in games if len(r) > 1 and str(r[1] or "").strip().isdigit()]
    last_year = max(years + [FIRST_YEAR])

    # Map Calc: the whole sheet is formulas, so it is rewritten whole.
    part, _ = wb.sheet_parts(CALC)
    xml = wb._by_name[part].decode("utf-8")
    head, rows, tail = split_sheet(xml)
    a1 = rows.get(1, ("", {}))[1].get("A")
    a1 = re.search(r'\ss="(\d+)"', a1[0]) if a1 else None
    hs = int(a1.group(1)) if a1 else S_HEAD
    genre = {n: rows[n][1]["R"] for n in range(2, 6) if n in rows and "R" in rows[n][1]}
    new = {1: ("", {c: cell_xml("%s1" % c, "s", h, hs) for c, h in CALC_HEADERS.items()})}
    for r in range(2, max(G, C) + 1):
        cells = {c: cell_xml("%s%d" % (c, r), "fs" if c in STR_COLS else "f", f, None)
                 for c, f in calc_cells(r, G, C).items()}
        if r in genre:
            cells["R"] = genre[r]
        new[r] = ("", cells)
    for n in range(2, 6):
        if n not in genre:
            new[n][1]["R"] = cell_xml("R%d" % n, "s", TYPES[n - 2], None)
    head = re.sub(r'<dimension ref="[^"]*"/>', '<dimension ref="A1:%s%d"/>' % (CALC_LAST, max(G, C)), head)
    head = re.sub(r"<cols>.*?</cols>", "<cols>%s</cols>" % "".join(
        '<col min="%d" max="%d" width="%d" customWidth="1"/>' % (col_index(c), col_index(c), w)
        for c, w in (("A", 34), ("W", 30), ("X", 30), ("AL", 30))), head, flags=re.S)
    wb._dirty[part] = (head + join_rows_raw(new) + tail).encode("utf-8")

    # How many cell styles the workbook has, so a fixed S_* can be checked.
    n_styles = int(re.search(r'<cellXfs count="(\d+)"',
                             wb._by_name["xl/styles.xml"].decode("utf-8")).group(1))
    if hs >= n_styles:
        hs = None

    # Map Analysis: only the cells this script owns are touched.
    part, _ = wb.sheet_parts(DASH)
    xml = wb._by_name[part].decode("utf-8")
    head, rows, tail = split_sheet(xml)
    head = migrate_dash(wb, head, rows)
    # The old year table may have run longer; its tail goes before the new one.
    for n, (attrs, cells) in rows.items():
        if n >= 5:
            for c in ("V", "W", "X", "Y"):
                cells.pop(c, None)
    for addr, (kind, value, style) in dash_cells(G, C, last_year).items():
        col, n = re.match(r"([A-Z]+)(\d+)", addr).groups()
        n = int(n)
        attrs, cells = rows.setdefault(n, ("", {}))
        if addr == "AP2" and col in cells and isinstance(cells[col], tuple) and "<v>" in (cells[col][1] or ""):
            continue   # the owner's decay, whatever they set it to
        if col in cells:
            # Keep the formatting the cell already has. The fixed S_* numbers are
            # only right for the workbook build_map_charts.py styled: Excel
            # renumbers `cellXfs` whenever it saves (the 23 Oct upload took the
            # list from 26 entries to 23), so an S_* written over a styled cell
            # can point at a different style or past the end of the list, which
            # openpyxl then refuses to load at all.
            m = re.search(r'\ss="(\d+)"', cells[col][0] if isinstance(cells[col], tuple) else cells[col])
            if m:
                style = int(m.group(1))
        if style is not None and style >= n_styles:
            style = None
        if kind == "f" and value.startswith(("IFERROR(INDEX('%s'!$A$" % CALC,)):
            kind = "fs"
        cells[col] = cell_xml(addr, kind, value, style)
    last_row = max(rows)
    head = re.sub(r'<dimension ref="[^"]*"/>', '<dimension ref="A1:AT%d"/>' % last_row, head)
    widths = {"AD": 7, "AE": 32, "AF": 12, "AG": 60, "AH": 12, "AJ": 7, "AK": 32, "AL": 11, "H": 10,
              "AN": 7, "AO": 32, "AP": 11, "AQ": 11, "AR": 11, "AS": 11, "AT": 11}
    cols = re.search(r"<cols>(.*?)</cols>", head, re.S)
    if cols:
        have = cols.group(1)
        for c, w in widths.items():
            i = col_index(c)
            if not re.search(r'<col min="%d" max="%d"' % (i, i), have):
                have += '<col min="%d" max="%d" width="%d" customWidth="1"/>' % (i, i, w)
        have = "".join(sorted(re.findall(r"<col [^>]*/>", have),
                              key=lambda x: int(re.search(r'min="(\d+)"', x).group(1))))
        head = head[:cols.start(1)] + have + head[cols.end(1):]
    wb._dirty[part] = (head + join_rows_raw(rows) + tail).encode("utf-8")

    # Charts: below the measure table, and over the year table's real length.
    years_last = 4 + last_year - FIRST_YEAR + 1
    for name in list(wb._by_name):
        if re.match(r"xl/drawings/drawing\d+\.xml$", name) and _drawing_is_dash(wb, name):
            x = wb._by_name[name].decode("utf-8")
            # The influence chart sits beside its table (far right), not in the
            # chart block under the measure table, so it never sets the shift.
            starts = [int(n) for c, n in re.findall(r"<xdr:from><xdr:col>(\d+)</xdr:col><xdr:colOff>-?\d+"
                                                     r"</xdr:colOff><xdr:row>(\d+)</xdr:row>", x)
                      if int(c) < INFLUENCE_CHART_COL]
            shift = max(0, CHARTS_FROM_ROW - 1 - min(starts)) if starts else 0
            if shift:
                x = re.sub(r"(<xdr:(?:from|to)><xdr:col>\d+</xdr:col><xdr:colOff>-?\d+</xdr:colOff>"
                           r"<xdr:row>)(\d+)", lambda mm: mm.group(1) + str(int(mm.group(2)) + shift), x)
                wb._dirty[name] = x.encode("utf-8")
        if re.match(r"xl/charts/chart\d+\.xml$", name):
            x = wb._by_name[name].decode("utf-8")
            y = re.sub(r"('Map Calc'!\$[A-Z]+\$\d+:\$[A-Z]+\$)\d+", lambda mm: mm.group(1) + str(G), x)
            y = re.sub(r"('Map Analysis'!\$[VWXY]\$5:\$[VWXY]\$)\d+",
                       lambda mm: mm.group(1) + str(years_last), y)
            if y != x:
                wb._dirty[name] = y.encode("utf-8")

    influence_chart(wb)
    recalc_on_open(wb)
    return G, C, last_year


# Before 28 Oct 2026 the buy table was three columns (AD:AF) and the hub and
# influence tables sat at AH:AJ and AL:AR. They move two columns right; the
# cells go with their formatting, and the owner's α with them (AN2 -> AP2).
OLD_RIGHT = (col_index("AH"), col_index("AR"))
MOVE = 2


def migrate_dash(wb, head, rows):
    """Move an old layout's right-hand tables across, in place. Returns head
    with the column widths moved too. A no-op on the new layout."""
    cell = rows.get(4, ("", {}))[1].get("AI")
    if not cell or _cell_value(cell[0], cell[1] or "", wb._shared) != "Hub on the map":
        return head
    lo, hi = OLD_RIGHT
    for n, (attrs, cells) in rows.items():
        moved = {}
        for c in [c for c in cells if lo <= col_index(c) <= hi]:
            moved[letters(col_index(c) + MOVE)] = cells.pop(c)
        for c, raw in moved.items():
            if isinstance(raw, tuple) and "<f" in (raw[1] or ""):
                raw = (raw[0], "")      # rewritten below; a stale formula would name the old columns
            cells[c] = raw
        # The cell addresses inside each raw tuple are rebuilt by join_rows_raw.
    cols = re.search(r"<cols>(.*?)</cols>", head, re.S)
    if cols:
        out = []
        for el in re.findall(r"<col [^>]*/>", cols.group(1)):
            a, b = (int(x) for x in re.search(r'min="(\d+)" max="(\d+)"', el).groups())
            if lo <= a and b <= hi:
                el = re.sub(r'min="\d+" max="\d+"', 'min="%d" max="%d"' % (a + MOVE, b + MOVE), el)
            elif a <= hi and b >= lo:
                continue        # straddles the moved block: let write() set it afresh
            if el not in out:
                out.append(el)
        head = head[:cols.start(1)] + "".join(out) + head[cols.end(1):]
    return head


# ── the influence chart ─────────────────────────────────────────────────────

INFLUENCE_TITLE = "Influence by generation — the top 20"
INFLUENCE_CHART_COL = 38          # AM, 0-based: left edge of the chart, under AN
INFLUENCE_CHART_ROW = 25          # row 26, under the top-20 table
# One hue, dark to light: direct, then each generation further downstream
# (passes the dataviz ordinal check on a light surface).
INFLUENCE_FILLS = ("0D366B", "1C5CAB", "3987E5", "86B6EF")
C_NS = "http://schemas.openxmlformats.org/drawingml/2006/chart"
R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"


def _rich(text, size=None, bold=None):
    rpr = '<a:rPr lang="en-US"%s%s/>' % (' sz="%d"' % size if size else "",
                                         ' b="%d"' % bold if bold is not None else "")
    return ('<c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr><a:r>%s'
            '<a:t>%s</a:t></a:r></a:p></c:rich></c:tx>' % (rpr, _esc(text)))


def influence_chart_xml():
    """A stacked horizontal bar of the top 20, one segment per generation."""
    dash = "'%s'" % DASH
    sers = []
    for i, (col, fill) in enumerate(zip(("AQ", "AR", "AS", "AT"), INFLUENCE_FILLS)):
        sers.append(
            '<c:ser><c:idx val="%d"/><c:order val="%d"/>'
            '<c:tx><c:strRef><c:f>%s!$%s$4</c:f></c:strRef></c:tx>'
            '<c:spPr><a:solidFill><a:srgbClr val="%s"/></a:solidFill>'
            '<a:ln w="19050"><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill></a:ln></c:spPr>'
            '<c:invertIfNegative val="0"/>'
            '<c:cat><c:strRef><c:f>%s!$AO$5:$AO$%d</c:f></c:strRef></c:cat>'
            '<c:val><c:numRef><c:f>%s!$%s$5:$%s$%d</c:f></c:numRef></c:val></c:ser>'
            % (i, i, dash, col, fill, dash, 4 + HUB_RANKS, dash, col, col, 4 + HUB_RANKS))
    axis_text = ('<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="900">'
                 '<a:solidFill><a:srgbClr val="404040"/></a:solidFill></a:defRPr></a:pPr>'
                 '<a:endParaRPr lang="en-US"/></a:p></c:txPr>')
    quiet = '<c:spPr><a:ln><a:solidFill><a:srgbClr val="D9D9D9"/></a:solidFill></a:ln></c:spPr>'
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<c:chartSpace xmlns:c="%s" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="%s"><c:date1904 val="0"/><c:lang val="en-US"/><c:roundedCorners val="0"/>'
        '<c:chart><c:title>%s<c:overlay val="0"/></c:title><c:autoTitleDeleted val="0"/>'
        '<c:plotArea><c:layout/><c:barChart><c:barDir val="bar"/><c:grouping val="stacked"/>'
        '<c:varyColors val="0"/>%s<c:gapWidth val="40"/><c:overlap val="100"/>'
        '<c:axId val="2010"/><c:axId val="2020"/></c:barChart>'
        # Rank 1 at the top: categories run max-to-min, values cross at the top.
        '<c:catAx><c:axId val="2010"/><c:scaling><c:orientation val="maxMin"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="l"/><c:numFmt formatCode="General" sourceLinked="0"/>'
        '<c:majorTickMark val="none"/><c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>'
        '%s%s<c:crossAx val="2020"/><c:crosses val="autoZero"/><c:auto val="1"/>'
        '<c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:tickLblSkip val="1"/>'
        '<c:noMultiLvlLbl val="1"/></c:catAx>'
        '<c:valAx><c:axId val="2020"/><c:scaling><c:orientation val="minMax"/></c:scaling>'
        '<c:delete val="0"/><c:axPos val="t"/><c:majorGridlines>%s</c:majorGridlines>'
        '<c:title>%s<c:overlay val="0"/></c:title>'
        '<c:numFmt formatCode="0" sourceLinked="0"/><c:majorTickMark val="none"/>'
        '<c:minorTickMark val="none"/><c:tickLblPos val="nextTo"/>%s%s'
        '<c:crossAx val="2010"/><c:crosses val="max"/><c:crossBetween val="between"/></c:valAx>'
        '</c:plotArea><c:legend><c:legendPos val="b"/><c:overlay val="0"/>%s</c:legend>'
        '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>'
        % (C_NS, R_NS, _rich(INFLUENCE_TITLE, 1200, 1), "".join(sers), quiet, axis_text,
           quiet, _rich("Influence (each generation worth α times the one above)", 900, 0),
           quiet, axis_text, axis_text))


def influence_chart(wb):
    """Write the chart, or rewrite it in place if an earlier run made it."""
    part, _ = wb.sheet_parts(DASH)
    rels_name = part.replace("worksheets/", "worksheets/_rels/") + ".rels"
    rels = wb._by_name.get(rels_name, b"").decode("utf-8")
    m = re.search(r'Target="\.\./drawings/(drawing\d+\.xml)"', rels)
    if not m:
        return   # the dashboard has no drawing to hang it on
    drawing = "xl/drawings/" + m.group(1)
    xml = influence_chart_xml().encode("utf-8")
    for name in wb._by_name:
        if re.match(r"xl/charts/chart\d+\.xml$", name) and INFLUENCE_TITLE.encode("utf-8") in wb._by_name[name]:
            if wb._by_name[name] != xml:
                wb._dirty[name] = xml
            return
    n = 1 + max(int(x) for x in re.findall(r"xl/charts/chart(\d+)\.xml$", "\n".join(wb._by_name), re.M) or [0])
    chart = "xl/charts/chart%d.xml" % n
    _new_part(wb, chart, xml)

    drels_name = drawing.replace("drawings/", "drawings/_rels/") + ".rels"
    drels = wb._by_name[drels_name].decode("utf-8")
    rid = "rId%d" % (1 + max([int(x) for x in re.findall(r'Id="rId(\d+)"', drels)] or [0]))
    drels = drels.replace("</Relationships>", '<Relationship Id="%s" Type="%s/chart" Target="../charts/chart%d.xml"/>'
                          "</Relationships>" % (rid, R_NS, n))
    wb._dirty[drels_name] = wb._by_name[drels_name] = drels.encode("utf-8")

    d = wb._by_name[drawing].decode("utf-8")
    shape_id = 1 + max([int(x) for x in re.findall(r'<xdr:cNvPr id="(\d+)"', d)] or [1])
    anchor = ('<xdr:oneCellAnchor><xdr:from><xdr:col>%d</xdr:col><xdr:colOff>0</xdr:colOff>'
              '<xdr:row>%d</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
              '<xdr:ext cx="10800000" cy="6840000"/><xdr:graphicFrame macro="">'
              '<xdr:nvGraphicFramePr><xdr:cNvPr id="%d" name="Influence chart"/><xdr:cNvGraphicFramePr/>'
              '</xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
              '<a:graphic><a:graphicData uri="%s"><c:chart xmlns:c="%s" xmlns:r="%s" r:id="%s"/>'
              '</a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:oneCellAnchor>'
              % (INFLUENCE_CHART_COL + 1, INFLUENCE_CHART_ROW, shape_id, C_NS, C_NS, R_NS, rid))
    d = d.replace("</xdr:wsDr>", anchor + "</xdr:wsDr>")
    wb._dirty[drawing] = wb._by_name[drawing] = d.encode("utf-8")

    ct = wb._by_name["[Content_Types].xml"].decode("utf-8")
    ct = ct.replace("</Types>", '<Override PartName="/%s" ContentType="application/vnd.openxmlformats-'
                    'officedocument.drawingml.chart+xml"/></Types>' % chart)
    wb._dirty["[Content_Types].xml"] = wb._by_name["[Content_Types].xml"] = ct.encode("utf-8")


def _new_part(wb, name, data):
    # __exit__ writes from _entries in order, so a new part is appended there.
    import zipfile
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    wb._entries.append((info, data))
    wb._by_name[name] = data


def join_rows_raw(rows):
    out = []
    for n in sorted(rows):
        attrs, cells = rows[n]
        parts = []
        for c in sorted(cells, key=col_index):
            raw = cells[c]
            if isinstance(raw, tuple):
                a, b = raw
                raw = '<c r="%s%d"%s/>' % (c, n, a) if not b else '<c r="%s%d"%s>%s</c>' % (c, n, a, b)
            parts.append(raw)
        out.append('<row r="%d"%s>%s</row>' % (n, attrs, "".join(parts)))
    return "".join(out)


def _drawing_is_dash(wb, drawing):
    part, _ = wb.sheet_parts(DASH)
    rels = part.replace("worksheets/", "worksheets/_rels/") + ".rels"
    x = wb._by_name.get(rels, b"").decode("utf-8")
    return os.path.basename(drawing) in x


def recalc_on_open(wb):
    wbx = wb._by_name["xl/workbook.xml"].decode("utf-8")
    wbx = re.sub(r'<calcPr([^>]*?)\s*/>',
                 lambda m: '<calcPr%s fullCalcOnLoad="1"/>' % m.group(1).replace(' fullCalcOnLoad="1"', ""),
                 wbx, count=1)
    wb._dirty["xl/workbook.xml"] = wbx.encode("utf-8")
    # The calc chain names formula cells by address, and the set has changed.
    if "xl/calcChain.xml" in wb._by_name:
        wb._entries = [(i, d) for i, d in wb._entries if i.filename != "xl/calcChain.xml"]
        rels = wb._by_name["xl/_rels/workbook.xml.rels"].decode("utf-8")
        wb._dirty["xl/_rels/workbook.xml.rels"] = re.sub(
            r'<Relationship [^>]*Target="calcChain\.xml"/>', "", rels).encode("utf-8")
        ct = wb._by_name["[Content_Types].xml"].decode("utf-8")
        wb._dirty["[Content_Types].xml"] = re.sub(
            r'<Override PartName="/xl/calcChain\.xml"[^>]*/>', "", ct).encode("utf-8")


# ── check ───────────────────────────────────────────────────────────────────

def check(wb):
    games, conns = read_data(wb)
    problems, notes = [], []
    calc = wb._by_name[wb.sheet_parts(CALC)[0]].decode("utf-8")
    dash = wb._by_name[wb.sheet_parts(DASH)[0]].decode("utf-8")
    fc, fd = formulas_in(calc), formulas_in(dash)

    for sheet, fs in ((CALC, fc), (DASH, fd)):
        bad = sorted((a for a, f in fs.items() if "#REF!" in f), key=lambda a: (len(a), a))
        if bad:
            problems.append("%s: %d formula(s) read #REF! (%s)" % (sheet, len(bad), ", ".join(bad[:8])))

    g_rows = [int(a[1:]) for a in fc if re.match(r"A\d+$", a)]
    c_rows = [int(a[1:]) for a in fc if re.match(r"W\d+$", a)]
    G, C = max(g_rows, default=0), max(c_rows, default=0)
    if not g_rows or not c_rows:
        problems.append("%s has no games or connections block: run python3 tools/map_calc.py" % CALC)
    else:
        want = {}
        for r in range(2, max(G, C) + 1):
            for c, f in calc_cells(r, G, C).items():
                want["%s%d" % (c, r)] = f
        drift = [a for a, f in want.items() if _unesc(fc.get(a, "")) != f]
        if drift:
            drift.sort(key=lambda a: (int(re.sub(r"[A-Z]", "", a)), col_index(re.sub(r"\d", "", a))))
            problems.append("%s: %d formula(s) are not what map_calc.py writes (first: %s)"
                            % (CALC, len(drift), ", ".join(drift[:6])))
        if len(games) + 1 > G - MIN_HEADROOM:
            problems.append("%s's games block ends at row %d with %d games on the sheet"
                            % (CALC, G, len(games)))
        if len(conns) + 1 > C - MIN_HEADROOM:
            problems.append("%s's connections block ends at row %d with %d connections"
                            % (CALC, C, len(conns)))
    years = [int(r[1]) for r in games if len(r) > 1 and str(r[1] or "").strip().isdigit()]
    year_rows = [a for a, f in fd.items() if re.match(r"W\d+$", a) and int(a[1:]) >= 5]
    if years and 4 + max(years) - FIRST_YEAR + 1 > max([int(a[1:]) for a in year_rows] or [0]):
        problems.append("%s's year table stops before %d" % (DASH, max(years)))

    if not any(re.match(r"xl/charts/chart\d+\.xml$", n) and INFLUENCE_TITLE.encode("utf-8") in d
               for n, d in wb._by_name.items()):
        problems.append("%s has no influence chart" % DASH)

    depth = influence_depth(games, conns)
    if depth is None:
        problems.append("the influence graph has a cycle, so Influence (Katz) depends on where "
                        "its %d generations stop; find the pair that points both ways" % GENS)
    elif depth > GENS:
        problems.append("the longest influence chain is %d games deep and Map Calc counts %d "
                        "generations: raise GENS in map_calc.py and rerun it" % (depth, GENS))

    owned, adj, main, islands = main_component(games, conns)
    pairs = {x for x in owned if len(adj[x]) == 1 and len(adj[next(iter(adj[x]))]) == 1}
    live = {x for x in owned if adj[x]} - pairs
    if live != main:
        notes.append("the sheet's 'on the map' counts %d games, the game's map has %d: %d island(s) "
                     "of three or more (%s), which a formula cannot see"
                     % (len(live), len(main), len(islands),
                        "; ".join(", ".join(sorted(c)[:3]) for c in islands[:3])))
    names = {str(r[0]).strip().lower() for r in games}
    stray = sorted({str(n) for r in conns for n in r[:2] if str(n or "").strip().lower() not in names})
    if stray:
        notes.append("connections naming no game row (the sheet's degrees skip them): " + ", ".join(stray))
    return problems, notes, (len(main), sum(len(adj[x] & main) for x in main) / max(1, len(main)))


def main():
    if "--check" in sys.argv:
        with Workbook(XLSX) as wb:
            problems, notes, (n_map, avg) = check(wb)
            wb._dirty.clear()
        for n in notes:
            print("note: " + n)
        if problems:
            print("Map Calc / Map Analysis are broken or outgrown:")
            for p in problems:
                print("  - " + p)
            print("Fix: python3 tools/map_calc.py (it rewrites both sheets' formulas), then commit the workbook.")
            sys.exit(1)
        print("ok — Map Calc and Map Analysis are sound (%d games on the map, average degree %.2f there)"
              % (n_map, avg))
        return
    with Workbook(XLSX) as wb:
        G, C, last_year = write(wb)
    print("Map Calc written: games block to row %d, connections to row %d; years %d-%d"
          % (G, C, FIRST_YEAR, last_year))


if __name__ == "__main__":
    main()

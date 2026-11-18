#!/usr/bin/env python3
"""One-shot: bring tools/Roguelikes.drawio level with the sheet (18 Nov 2026).

After the owner's 18 Nov redraw (the seven new games drawn in), check_map_sync.py
still listed what had drifted before it:

  * five games on the sheet and not on the map — Grail, Lucky Hunter, Moonsigil
    Atlas, Teleglitch, Thysiastery — and so the three connections into two of
    them (Luck be a Landlord and Slay the Spire -> Lucky Hunter, Spelunky
    Classic -> Teleglitch);
  * a plain line Rogue (1980) -> Beneath Apple Manor (1978) that the sheet has no
    row for. The owner: delete it;
  * Fatal Labyrinth -> Dragon Crystal drawn plain where the sheet says
    Dev/Series. The owner: the sheet is right, so the line goes blue (the four
    disagreements the other way were fixed on the sheet,
    `_connections_dev_series_from_map.py`);
  * five lines drawn to a bare coordinate beside their node rather than snapped
    onto it, which the checker resolves by position. Snapped here, so the file
    says what it means without the checker's guess.

Every change is a surgical text edit on one cell (or new cells inserted before
`</root>`), never a reserialisation: draw.io round-trips this file and a
rewrite would churn 1 MB of XML. A new node lands on its year row (the row's
y, as the map's own year labels place it) in the nearest free gap to where it
belongs: next to its influencers' mean x, or, for a game with no connection,
at the right-hand end of that year's orphan column, where the map keeps them.

    python3 tools/oneshots/_map_sync_18nov.py
    python3 tools/check_map_sync.py tools/Roguelikes.drawio
"""

import os
import re
import sys
import xml.etree.ElementTree as ET
from html import escape

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
import check_map_sync as C  # noqa: E402

DRAWIO = os.path.join(TOOLS, "Roguelikes.drawio")
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")

NODE_STYLE = "rounded=0;whiteSpace=wrap;html=1;fontSize=10;"
EDGE_STYLE = ("endArrow=classic;html=1;rounded=0;entryX=0.5;entryY=0;entryDx=0;"
              "entryDy=0;exitX=0.5;exitY=1;exitDx=0;exitDy=0;")
BLUE = "strokeColor=#0000FF;"
NEW_GAMES = ["Grail", "Lucky Hunter", "Moonsigil Atlas", "Teleglitch", "Thysiastery"]
# Orphans (no connection) live in the column at the map's right edge.
ORPHAN_X = 12500
GAP = 12


# A sideways nudge off the spot the gap search picks, from
# `map_declutter.py --move <game>`: Teleglitch's first spot sat under a line
# running straight through it, and 180 px right is the nearest column with half
# as many lines clipping a box.
NUDGE = {"Teleglitch": 180}


def node_size(label):
    """A box the size the map uses for a name this long (10 px font): one line
    up to 12 characters, two lines (split at a space) past that."""
    if len(label) <= 12 or " " not in label:
        return (max(36, round(5.6 * len(label)) + 8), 24)
    longest = max(len(w) for w in label.split(" "))
    return (max(36, round(5.6 * max(longest, len(label) // 2 + 1)) + 8), 30)


def main():
    text = open(DRAWIO, encoding="utf-8").read()
    root = C.load_model(DRAWIO)
    cells = root.findall(".//mxCell")
    by_id = {c.get("id"): c for c in cells}
    label = {c.get("id"): C.strip_markup(c.get("value")) for c in cells if c.get("vertex") == "1"}
    boxes = {}
    for c in cells:
        g = c.find("mxGeometry")
        if c.get("vertex") == "1" and g is not None and label.get(c.get("id")) \
                and not (c.get("style") or "").startswith("text;"):
            boxes[c.get("id")] = tuple(float(g.get(k) or 0) for k in ("x", "y", "width", "height"))
    id_of = {C.norm(label[i]): i for i in boxes}
    sheet = C.load_sheet(XLSX)
    years = {y: py for py, y in C.parse_map(DRAWIO)["year_axis"]}

    def cell_span(cid):
        m = re.search(r'<mxCell id="%s"[^>]*?(?:/>|>.*?</mxCell>)' % re.escape(cid), text, re.S)
        if not m:
            raise SystemExit("cell %s not found as text" % cid)
        return m

    def edge_between(a, b):
        ia, ib = id_of[C.norm(a)], id_of[C.norm(b)]
        hits = [c for c in cells if c.get("edge") == "1"
                and {c.get("source"), c.get("target")} == {ia, ib}]
        if len(hits) != 1:
            raise SystemExit("expected one %s -> %s line, found %d" % (a, b, len(hits)))
        return hits[0]

    # 1. Rogue -> Beneath Apple Manor: deleted, with the whitespace before it.
    e = edge_between("Rogue", "Beneath Apple Manor")
    m = cell_span(e.get("id"))
    start = text.rfind("\n", 0, m.start())
    text = text[:start] + text[m.end():]
    print("deleted Rogue -> Beneath Apple Manor (%s)" % e.get("id"))

    # 2. Fatal Labyrinth -> Dragon Crystal goes blue.
    e = edge_between("Fatal Labyrinth", "Dragon Crystal")
    m = cell_span(e.get("id"))
    old = m.group(0)
    new = old.replace('style="%s' % e.get("style"), 'style="%s%s' % (e.get("style"), BLUE), 1) \
        if "strokeColor" not in e.get("style") else old
    if new == old:
        raise SystemExit("could not recolour Fatal Labyrinth -> Dragon Crystal")
    text = text.replace(old, new, 1)
    print("Fatal Labyrinth -> Dragon Crystal drawn blue (Dev/Series)")

    # 3. Snap loose endpoints the checker resolves by position.
    snapped = 0
    for c in cells:
        if c.get("edge") != "1":
            continue
        g = c.find("mxGeometry")
        for role, attr in (("sourcePoint", "source"), ("targetPoint", "target")):
            if c.get(attr) is not None:
                continue
            pt = C._point(g, role)
            if pt is None:
                continue
            px, py = pt
            ranked = sorted(((max(x - px, 0, px - x - w) ** 2 + max(y - py, 0, py - y - h) ** 2) ** .5, i)
                            for i, (x, y, w, h) in boxes.items())
            if ranked[0][0] > C.SNAP_CAP or ranked[1][0] - ranked[0][0] < C.SNAP_MARGIN:
                continue
            m = cell_span(c.get("id"))
            old = m.group(0)
            new = old.replace('<mxCell id="%s"' % c.get("id"),
                              '<mxCell id="%s" %s="%s"' % (c.get("id"), attr, ranked[0][1]), 1)
            text = text.replace(old, new, 1)
            snapped += 1
            print("snapped %s of %s onto %s" % (attr, c.get("id"), label[ranked[0][1]]))
    print("%d loose endpoint(s) snapped" % snapped)

    # 4. The five undrawn games and their connections.
    taken = dict(boxes)
    adds = []
    for n, name in enumerate(NEW_GAMES, 1):
        key = C.norm(name)
        if key in id_of:
            print("already drawn: %s" % name)
            continue
        year = sheet["games"][key]["year"]
        row_y = years[year]
        parents = [id_of[C.norm(v["a"])] for k, v in sheet["connections"].items()
                   if C.norm(v["b"]) == key and C.norm(v["a"]) in id_of]
        w, h = node_size(name)
        y = row_y + 4
        row = sorted((x, x + bw) for (x, by, bw, bh) in taken.values()
                     if by < y + h + GAP and by + bh + GAP > y)
        if parents:
            want = sum(taken[p][0] + taken[p][2] / 2 for p in parents) / len(parents) - w / 2
        else:
            want = max([ORPHAN_X] + [b for a, b in row if a >= ORPHAN_X]) + GAP
        # Nearest free x to `want`: scan outward both ways.
        def free(x):
            return all(x + w + GAP <= a or x >= b + GAP for a, b in row)
        x = next(want + s * d for d in range(0, 20000, 4) for s in (1, -1) if free(want + s * d))
        if name in NUDGE:
            x += NUDGE[name]
            if not free(x):
                raise SystemExit("%s's nudge lands on another box" % name)
        cid = "claude-map-18nov-%d" % n
        taken[cid] = (x, y, w, h)
        id_of[key] = cid
        adds.append('        <mxCell id="%s" parent="1" style="%s" value="%s" vertex="1">\n'
                    '          <mxGeometry height="%d" width="%d" x="%d" y="%d" as="geometry" />\n'
                    '        </mxCell>' % (cid, NODE_STYLE, escape(name, quote=True), h, w, round(x), round(y)))
        print("drew %s (%d) at x=%d y=%d%s" % (name, year, x, y,
              "" if parents else " (orphan column)"))
        for p in parents:
            px, py, pw, ph = taken[p]
            dev = sheet["connections"][frozenset((C.norm(label[p]), key))]["dev"]
            adds.append('        <mxCell id="%s-e%s" edge="1" parent="1" source="%s" style="%s" target="%s" value="">\n'
                        '          <mxGeometry height="50" relative="1" width="50" as="geometry">\n'
                        '            <mxPoint x="%d" y="%d" as="sourcePoint" />\n'
                        '            <mxPoint x="%d" y="%d" as="targetPoint" />\n'
                        '          </mxGeometry>\n'
                        '        </mxCell>' % (cid, p, p, EDGE_STYLE + (BLUE if dev else ""), cid,
                                               px + pw / 2, py + ph, x + w / 2, y))
            print("  line %s -> %s" % (label[p], name))
    if adds:
        i = text.rindex("      </root>")
        text = text[:i] + "\n".join(adds) + "\n" + text[i:]
    ET.fromstring(text)  # still well-formed
    open(DRAWIO, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    main()

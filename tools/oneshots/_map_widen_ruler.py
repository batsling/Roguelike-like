#!/usr/bin/env python3
"""One-shot: give the map room on both sides (the owner, 19 Nov 2026).

Moves the year labels and the era captions ("2010s Indie Resurgence", "2020's
Popularity Boom") LEFT by SHIFT, and redraws each year's grey ruler line as ONE
straight, unattached line at the height it already had, from its label's right
edge to PAD past the rightmost game box. Nothing else moves: no game box, no
connection, the legend at the top neither.

Why one line per year: the ruler had grown pieces. 2021 was two lines, 2024
three, two of them ATTACHED to the RollScape box (so moving RollScape bent the
ruler), and 1978's was attached to its own label. Every other row was already a
single line; they are all the same shape now.

Surgical text edits, like every other map one-shot: the file is not
reserialised.

    python3 tools/oneshots/_map_widen_ruler.py [path/to/Roguelikes.drawio] [--shift N]

Run on 19 Nov 2026 with the default (1,000), then again with --shift 2000 when
the owner asked for more room on the left: 3,000 px in all. A rerun only adds
its shift; the ruler's right end is recomputed and stays PAD past the last box.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, TOOLS)
import check_map_sync as C  # noqa: E402

SHIFT = 1000   # labels and captions move this far left
PAD = 1000     # the ruler runs this far past the rightmost game box
ERA = ("2010s Indie Resurgence", "2020's Popularity Boom")
LINE_STYLE = ("endArrow=none;html=1;rounded=0;strokeColor=#C8C8C8;strokeWidth=1;"
              "shadow=0;flowAnimation=0;curved=0;")


def main():
    args = sys.argv[1:]
    shift = SHIFT
    if "--shift" in args:
        i = args.index("--shift")
        shift = float(args[i + 1])
        del args[i:i + 2]
    path = args[0] if args else os.path.join(TOOLS, "Roguelikes.drawio")
    text = open(path, encoding="utf-8").read()
    root = C.load_model(path)
    cells = root.findall(".//mxCell")
    f = lambda v: float(v or 0)

    def span(cid):
        m = re.search(r'\n[ \t]*<mxCell id="%s"[^>]*?(?:/>|>.*?</mxCell>)' % re.escape(cid), text, re.S)
        if not m:
            raise SystemExit("cell %s not found" % cid)
        return m

    years, captions, right = {}, [], -1e9
    for c in cells:
        if c.get("vertex") != "1" or c.find("mxGeometry") is None:
            continue
        g = c.find("mxGeometry")
        label = C.strip_markup(c.get("value"))
        style = c.get("style") or ""
        if re.fullmatch(r"(19|20)\d{2}", label):
            years[c.get("id")] = (int(label), f(g.get("x")), f(g.get("y")), f(g.get("width")), f(g.get("height")))
        elif label in ERA:
            captions.append(c.get("id"))
        elif label and not style.startswith("text;"):
            right = max(right, f(g.get("x")) + f(g.get("width")))
    if len(years) < 40 or len(captions) != len(ERA):
        raise SystemExit("expected the year column and both era captions, found %d / %d"
                         % (len(years), len(captions)))

    # Ruler lines, by the year row they sit on.
    rows = {}
    for c in cells:
        if c.get("edge") != "1" or "C8C8C8" not in (c.get("style") or "").upper():
            continue
        pts = [(f(p.get("x")), f(p.get("y"))) for p in c.find("mxGeometry").iter("mxPoint") if p.get("as")]
        if not pts:
            continue
        y = sum(p[1] for p in pts) / len(pts)
        year = min(years.values(), key=lambda v: abs(v[2] + v[4] / 2 - y))
        if abs(year[2] + year[4] / 2 - y) > 40:
            continue  # a grey line that is not on a year row (a legend sample)
        rows.setdefault(year[0], []).append((c.get("id"), y, min(p[0] for p in pts)))

    # 1. Labels and captions left by SHIFT.
    for cid in list(years) + captions:
        m = span(cid)
        old = m.group(0)
        new = re.sub(r'(<mxGeometry\b[^>]*?\bx=")(-?[\d.]+)(")',
                     lambda g: "%s%g%s" % (g.group(1), float(g.group(2)) - shift, g.group(3)), old, count=1)
        text = text.replace(old, new, 1)

    # 2. One line per year row, from the moved label's right edge to `right + PAD`.
    label_right = {v[0]: v[1] - shift + v[3] for v in years.values()}
    end = right + PAD
    for year, lines in sorted(rows.items()):
        lines.sort(key=lambda l: l[2])     # keep the leftmost piece's id and height
        keep, y, _ = lines[0]
        for cid, _, _ in lines[1:]:
            m = span(cid)
            text = text[:m.start()] + text[m.end():]
        m = span(keep)
        indent = re.match(r"\n([ \t]*)", m.group(0)).group(1)
        new = ('\n%s<mxCell id="%s" edge="1" parent="1" style="%s" value="">\n'
               '%s  <mxGeometry height="50" relative="1" width="50" as="geometry">\n'
               '%s    <mxPoint x="%g" y="%g" as="sourcePoint" />\n'
               '%s    <mxPoint x="%g" y="%g" as="targetPoint" />\n'
               '%s  </mxGeometry>\n%s</mxCell>'
               % (indent, keep, LINE_STYLE, indent, indent, label_right[year], round(y, 2),
                  indent, end, round(y, 2), indent, indent))
        text = text[:m.start()] + new + text[m.end():]
    missing = sorted(set(v[0] for v in years.values()) - set(rows))
    ET.fromstring(text)
    open(path, "w", encoding="utf-8").write(text)
    print("moved %d year labels and %d captions %d left; %d ruler rows redrawn from x=%g to x=%g"
          % (len(years), len(captions), shift, len(rows), min(label_right.values()), end))
    if missing:
        print("year rows with no ruler line: %s" % missing)


if __name__ == "__main__":
    main()

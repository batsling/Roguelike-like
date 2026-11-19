#!/usr/bin/env python3
"""Bake the owner's hand-drawn map (tools/Roguelikes.drawio) into the game.

Writes `data/atlas_layout_map.tres`: an `AtlasLayout` whose stars sit EXACTLY
where the owner drew each game's box, at the size they drew it, with every line
as drawn (its colour and the points it leaves and enters its boxes at) and the
year ruler down the left. `AtlasView` draws it during a run (the owner, 19 Nov
2026: "a map that is shaped exactly as this is"); the Collection keeps the
baked constellations and the Tree.

Nothing here lays anything out. The drawio is the layout, so the shape is the
owner's to change: redraw, upload the .drawio, rerun this.

Like the sheet is upstream of `data/`, the drawio is upstream of this file, and
a box or a line the sheet doesn't have is refused rather than baked (a typo in a
label, a line the sheet never recorded): the game must not draw a connection
that a run cannot travel. The other direction only WARNS. A game or a connection
added to the sheet before it is drawn is normal (the owner draws in either
order), so it is simply not on the in-game map until the drawio has it, and the
bake says so, and so is a line that runs through a box other than its own two
(the owner wants none; the game draws lines under the boxes as draw.io does,
but a line passing behind a box looks like it joins it). `check_map_sync.py`
is the full report. A game the map has but
`data/games/` lacks means the import hasn't run.

Coordinates are draw.io's own (y grows down, as in Godot). A star's position is
its box's CENTRE, so everything that reads `xs`/`ys` (the run's roads, picking,
framing) lands in the middle of the box; `box_w`/`box_h` give the rectangle.

Each line keeps the draw.io anchors it was drawn with (`exitX/exitY` on the box
it leaves, `entryX/entryY` on the box it enters, as fractions of the box). 1,636
of the 1,657 lines leave the bottom middle and enter the top middle; the rest
name their own. A line with no anchor is drawn the way draw.io draws one: from
centre towards centre, cut at each box's border (stored as -1).

    python3 tools/bake_drawio_map.py            # write data/atlas_layout_map.tres
    python3 tools/bake_drawio_map.py --check    # CI: exit 1 if it is out of date
"""
import importlib
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import check_map_sync as C  # noqa: E402

DRAWIO = os.path.join(TOOLS, "Roguelikes.drawio")
XLSX = os.path.join(TOOLS, "Roguelikes.xlsx")
OUT = os.path.join(ROOT, "data", "atlas_layout_map.tres")
GAMES_DIR = os.path.join(ROOT, "data", "games")
PAD = 40.0  # margin around everything, in drawio units, for framing


def _f(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def _style(s):
    return dict(kv.split("=", 1) for kv in (s or "").split(";") if "=" in kv)


def _ends(box, a, b, anchors):
    """Where the line from box `a` to box `b` leaves and enters, as AtlasLayout
    .edge_ends draws it: draw.io's anchor, else the centre line cut at the border."""
    def border(r, tx, ty):
        cx, cy = r[0] + r[2] / 2, r[1] + r[3] / 2
        dx, dy = tx - cx, ty - cy
        if dx == 0 and dy == 0:
            return cx, cy
        k = min(r[2] / 2 / abs(dx) if dx else 1e18, r[3] / 2 / abs(dy) if dy else 1e18, 1.0)
        return cx + dx * k, cy + dy * k
    ra, rb = box[a], box[b]
    ex, ey, nx, ny = anchors
    p = (ra[0] + ex * ra[2], ra[1] + ey * ra[3]) if ex >= 0 else \
        border(ra, rb[0] + rb[2] / 2, rb[1] + rb[3] / 2)
    q = (rb[0] + nx * rb[2], rb[1] + ny * rb[3]) if nx >= 0 else \
        border(rb, ra[0] + ra[2] / 2, ra[1] + ra[3] / 2)
    return p, q


def _hits(p, q, r):
    """Does segment p-q pass through rectangle r (x, y, w, h)? Liang-Barsky."""
    x0, y0 = p
    dx, dy = q[0] - x0, q[1] - y0
    t0, t1 = 0.0, 1.0
    for pp, qq in ((-dx, x0 - r[0]), (dx, r[0] + r[2] - x0),
                   (-dy, y0 - r[1]), (dy, r[1] + r[3] - y0)):
        if pp == 0:
            if qq < 0:
                return False
        else:
            t = qq / pp
            if pp < 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
            if t0 > t1:
                return False
    return True


def crossings(rects, lines):
    """Lines that pass through a box other than their own two, as (a, b, [boxes]).
    The owner wants none (19 Nov 2026), and the bake lists them on every run.
    Boxes are shrunk 1 unit so a line merely grazing a border doesn't count."""
    out = []
    for a, b, anchors in lines:
        p, q = _ends(rects, a, b, anchors)
        lo_x, hi_x = sorted((p[0], q[0]))
        lo_y, hi_y = sorted((p[1], q[1]))
        over = [k for k, r in rects.items() if k not in (a, b)
                and r[0] + r[2] >= lo_x and r[0] <= hi_x and r[1] + r[3] >= lo_y and r[1] <= hi_y
                and _hits(p, q, (r[0] + 1, r[1] + 1, r[2] - 2, r[3] - 2))]
        if over:
            out.append((a, b, over))
    return out


def bake(drawio=DRAWIO):
    root = C.load_model(drawio)
    cells = root.findall(".//mxCell")
    sheet = C.load_sheet(XLSX)
    id_for = importlib.import_module("import-games-godot").id_for
    shipped = {os.path.splitext(f)[0] for f in os.listdir(GAMES_DIR) if f.endswith(".tres")}

    problems = []   # refusals: the map says something the catalog doesn't
    waiting = []    # the sheet has something the map hasn't drawn yet
    boxes = {}     # cell id -> (game id, x, y, w, h)
    years = []     # (year, label x, label y, label w, label h)
    for c in cells:
        g = c.find("mxGeometry")
        if c.get("vertex") != "1" or g is None:
            continue
        label = C.strip_markup(c.get("value"))
        rect = (_f(g.get("x")), _f(g.get("y")), _f(g.get("width")), _f(g.get("height")))
        if re.fullmatch(r"(19|20)\d{2}", label):
            years.append((int(label),) + rect)
            continue
        if not label or (c.get("style") or "").startswith("text;"):
            continue
        row = sheet["games"].get(C.norm(label))
        if row is None:
            problems.append("a box on the map is no game on the sheet: %r" % label)
            continue
        gid = id_for(row["name"])
        if gid not in shipped:
            problems.append("%s is on the map and the sheet but not in data/games/ "
                            "(run import-games-godot.py)" % row["name"])
            continue
        boxes[c.get("id")] = (gid,) + rect
    drawn = {b[0] for b in boxes.values()}
    for key, row in sheet["games"].items():
        if id_for(row["name"]) not in drawn:
            waiting.append("%s is on the sheet and not on the map" % row["name"])
    if len(drawn) != len(boxes):
        problems.append("a game is drawn more than once")

    # Ruler lines: the grey rules, by the year label they run through.
    ruler = {}
    for c in cells:
        if c.get("edge") != "1" or "C8C8C8" not in (c.get("style") or "").upper():
            continue
        pts = [(_f(p.get("x")), _f(p.get("y"))) for p in c.find("mxGeometry").iter("mxPoint")
               if p.get("as")]
        if not pts or not years:
            continue
        y = sum(p[1] for p in pts) / len(pts)
        near = min(years, key=lambda v: abs(v[2] + v[4] / 2 - y))
        if abs(near[2] + near[4] / 2 - y) <= 40:
            xs = [p[0] for p in pts]
            lo, hi, _ = ruler.get(near[0], (min(xs), max(xs), y))
            ruler[near[0]] = (min(lo, min(xs)), max(hi, max(xs)), y)

    # Lines between games, with their anchors. A loose end is resolved the way the
    # checker resolves it (nearest box, if unambiguous).
    # parse_map walks the edge cells in file order, as the loop below does, so
    # the two zip together; it is what resolves a loose end to a box name.
    parsed = C.parse_map(drawio)
    by_name = {}
    for c in cells:
        if c.get("id") in boxes:
            by_name[C.strip_markup(c.get("value"))] = c.get("id")
    lines, seen = [], set()
    edge_cells = [c for c in cells if c.get("edge") == "1"]
    assert len(edge_cells) == len(parsed["edges"])
    for c, e in zip(edge_cells, parsed["edges"]):
        if e["kind"] not in (C.KIND_INFLUENCE, C.KIND_DEV):
            continue
        a = c.get("source") if c.get("source") in boxes else by_name.get(e["source"])
        b = c.get("target") if c.get("target") in boxes else by_name.get(e["target"])
        if a is None or b is None:
            problems.append("a line on the map has a loose end nothing can resolve (%s)" % c.get("id"))
            continue
        pair = frozenset((boxes[a][0], boxes[b][0]))
        if pair in seen:
            problems.append("two lines join %s and %s" % tuple(sorted(pair)))
            continue
        seen.add(pair)
        st = _style(c.get("style"))
        lines.append((a, b, e["kind"] == C.KIND_DEV,
                      _f(st.get("exitX"), -1), _f(st.get("exitY"), -1),
                      _f(st.get("entryX"), -1), _f(st.get("entryY"), -1)))
    id_name = {}
    for row in sheet["games"].values():
        id_name[id_for(row["name"])] = row["name"]
    for k, row in sheet["connections"].items():
        pair = frozenset(id_for(n) for n in (row["a"], row["b"]))
        if pair not in seen:
            waiting.append("%s -> %s is on the sheet and not drawn" % (row["a"], row["b"]))
    for pair in seen:
        names = frozenset(C.norm(id_name.get(g, g)) for g in pair)
        if names not in sheet["connections"]:
            problems.append("%s is drawn and not on the sheet" % " -- ".join(sorted(pair)))
    if problems:
        raise SystemExit("the drawio and the sheet disagree, so nothing was baked:\n  - "
                         + "\n  - ".join(sorted(problems)[:40])
                         + "\n(python3 tools/check_map_sync.py tools/Roguelikes.drawio says more)")

    order = sorted(boxes, key=lambda cid: boxes[cid][0])
    index = {cid: i for i, cid in enumerate(order)}
    ids = [boxes[cid][0] for cid in order]
    cx = [boxes[cid][1] + boxes[cid][3] / 2 for cid in order]
    cy = [boxes[cid][2] + boxes[cid][4] / 2 for cid in order]
    bw = [boxes[cid][3] for cid in order]
    bh = [boxes[cid][4] for cid in order]
    lines.sort(key=lambda l: (index[l[0]], index[l[1]]))
    edges, dev, anchors = [], [], []
    for a, b, is_dev, ex, ey, nx, ny in lines:
        edges += [index[a], index[b]]
        dev.append(1 if is_dev else 0)
        anchors += [ex, ey, nx, ny]

    years.sort()
    # A year with no grey rule still gets one, through its label's middle.
    ry = [ruler[t[0]][2] if t[0] in ruler else t[2] + t[4] / 2 for t in years]
    x0 = min((r[0] for r in ruler.values()), default=min(t[1] + t[3] for t in years))
    x1 = max((r[1] for r in ruler.values()), default=max(x + w for x, w in zip(cx, bw)))
    lx = min(t[1] for t in years)
    lw = max(t[3] for t in years)
    lh = max(t[4] for t in years)
    minx = min(lx, min(x - w / 2 for x, w in zip(cx, bw))) - PAD
    maxx = max(x1, max(x + w / 2 for x, w in zip(cx, bw))) + PAD
    miny = min(min(t[2] for t in years), min(y - h / 2 for y, h in zip(cy, bh))) - PAD
    maxy = max(max(t[2] + t[4] for t in years), max(y + h / 2 for y, h in zip(cy, bh))) + PAD

    def fl(v):
        return ", ".join(("%.3f" % x).rstrip("0").rstrip(".") if x != int(x) else str(int(x)) for x in v)

    body = f"""[gd_resource type="Resource" script_class="AtlasLayout" load_steps=2 format=3 uid="uid://atlas_layout_map"]

[ext_resource type="Script" path="res://scripts/resources/AtlasLayout.gd" id="1_atlas"]

[resource]
script = ExtResource("1_atlas")
source_filter = "drawn"
game_ids = PackedStringArray({", ".join('"%s"' % g for g in ids)})
xs = PackedFloat32Array({fl(cx)})
ys = PackedFloat32Array({fl(cy)})
region = PackedInt32Array({", ".join("-1" for _ in ids)})
hops = PackedInt32Array({", ".join("-1" for _ in ids)})
edges = PackedInt32Array({", ".join(str(v) for v in edges)})
box_w = PackedFloat32Array({fl(bw)})
box_h = PackedFloat32Array({fl(bh)})
edge_dev = PackedByteArray({", ".join(str(v) for v in dev)})
edge_anchors = PackedFloat32Array({fl(anchors)})
ruler_years = PackedInt32Array({", ".join(str(t[0]) for t in years)})
ruler_ys = PackedFloat32Array({fl(ry)})
ruler_label_ys = PackedFloat32Array({fl([t[2] for t in years])})
ruler_label_rect = Rect2({lx:g}, 0, {lw:g}, {lh:g})
ruler_x = Vector2({x0:g}, {x1:g})
bounds = Rect2({minx:g}, {miny:g}, {maxx - minx:g}, {maxy - miny:g})
"""
    rects = {boxes[c][0]: boxes[c][1:] for c in boxes}
    for a, b, over in crossings(rects, [(boxes[l[0]][0], boxes[l[1]][0], l[3:7]) for l in lines]):
        waiting.append("the line %s -> %s crosses %s" % (id_name.get(a, a), id_name.get(b, b),
                                                         ", ".join(id_name.get(o, o) for o in over)))
    return body, len(ids), len(lines), len(years), waiting


def main():
    body, n, e, y, waiting = bake()
    for w in waiting:
        print("to fix in the drawio: " + w)
    if "--check" in sys.argv:
        current = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if current != body:
            print("data/atlas_layout_map.tres is out of date with tools/Roguelikes.drawio.\n"
                  "Fix: python3 tools/bake_drawio_map.py, then commit it.")
            sys.exit(1)
        print("ok — the drawn map is current (%d games, %d lines, %d years)" % (n, e, y))
        return
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(body)
    print("wrote data/atlas_layout_map.tres: %d games, %d lines, %d years" % (n, e, y))


if __name__ == "__main__":
    main()

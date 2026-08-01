#!/usr/bin/env python3
"""Generate a layered redraw of the influence map with no edge crossing a box.

PROTOTYPE — proposes a layout, it does not modify tools/Roguelikes.drawio.

Release year is already a valid layering (no edge points backwards in time), so
the expensive part of layered graph drawing is free. Rows are years; games are
ordered within a row by the mean position of their neighbours so families cluster;
and every edge that crosses a row is nudged sideways into the nearest FREE GAP
between that row's boxes.

Sharing gaps is the point. Giving each edge its own reserved corridor also
guarantees no box is crossed, but needs 5,744 corridors and reads as a curtain of
hatching beside every row. Edges are allowed to overlap each other — they are only
forbidden from crossing a box — so one gap can carry many.

`verify()` checks the result by sampling every routed segment against every box;
it returns the offending (edge, row) pairs and should always be empty.

Usage:
    python3 tools/map_layout.py out.svg              # whole map
    python3 tools/map_layout.py out.svg --around "Slay the Spire" --zoom 1
"""
import argparse
import collections
import html
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_map_sync as C

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
DRAWIO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.drawio")

NODE_H = 30.0
ROW_H = 150.0
CHAR_W = 6.6
PAD_X = 14.0
MIN_GAP = 26.0     # horizontal gap between boxes; also the shared edge highway
CLEAR = 5.0        # how far an edge stays off a box


def load():
    sheet = C.load_sheet(XLSX)
    year = {k: g["year"] for k, g in sheet["games"].items() if g["year"]}
    name = {k: g["name"] for k, g in sheet["games"].items()}
    edges = []
    for link in sheet["connections"].values():
        a, b = C.norm(link["a"]), C.norm(link["b"])
        if a in year and b in year and year[a] < year[b]:
            edges.append((a, b, link["dev"]))
    return name, year, edges


def hand_x():
    """Seed order from the hand-drawn map so the redraw stays recognisable."""
    return {C.norm(n["label"]): n["x"] for n in C.parse_map(DRAWIO)["nodes"].values()}


def genres():
    import openpyxl
    wb = openpyxl.load_workbook(XLSX, read_only=True)
    rows = wb["games"].iter_rows(values_only=True)
    next(rows)
    tmap = {"action": 0, "strategy": 1, "deckbuilder": 2, "deckbuilding": 2, "traditional": 3}
    return {C.norm(str(r[0])): tmap.get(str(r[2]).strip().lower() if r[2] else "", 1)
            for r in rows if r and r[0]}


def build(name, year, edges, seed_x, per_row=1):
    years = sorted(set(year.values()))
    layer_of = {y: i // per_row for i, y in enumerate(years)}
    n = max(layer_of.values()) + 1
    row_years = [[] for _ in range(n)]
    for y in years:
        row_years[layer_of[y]].append(y)
    layers = [[] for _ in range(n)]
    for g, y in year.items():
        layers[layer_of[y]].append(g)

    width = {g: max(90.0, min(210.0, len(name[g]) * CHAR_W + PAD_X * 2)) for g in year}
    nbr = collections.defaultdict(list)
    for a, b, _dev in edges:
        nbr[a].append(b)
        nbr[b].append(a)

    x = {g: seed_x.get(g, 0.0) for g in year}
    for row in layers:
        row.sort(key=lambda g: x[g])

    # Order rows by the mean x of each game's neighbours, then repack. Repeating
    # this pulls families of related games into the same horizontal region.
    for _ in range(12):
        for row in layers:
            row.sort(key=lambda g: (sum(x[o] for o in nbr[g]) / len(nbr[g])) if nbr[g] else x[g])
        for row in layers:
            cur = 0.0
            for g in row:
                x[g] = cur + width[g] / 2.0
                cur += width[g] + MIN_GAP
        widest = max((max(x[g] + width[g] / 2 for g in r) if r else 0) for r in layers) or 1.0
        for row in layers:
            if not row:
                continue
            hi = max(x[g] + width[g] / 2 for g in row)
            shift = (widest - hi) / 2.0
            for g in row:
                x[g] += shift

    # Straighten inside the slack, bounded by row neighbours so nothing spreads.
    for _ in range(40):
        for row in layers:
            for i, g in enumerate(row):
                if not nbr[g]:
                    continue
                t = sorted(x[o] for o in nbr[g])
                m = len(t) // 2
                d = t[m] if len(t) % 2 else (t[m - 1] + t[m]) / 2.0
                lo = -1e18 if not i else x[row[i - 1]] + width[row[i - 1]] / 2 + MIN_GAP + width[g] / 2
                hi = 1e18 if i == len(row) - 1 else x[row[i + 1]] - width[row[i + 1]] / 2 - MIN_GAP - width[g] / 2
                if lo <= hi:
                    x[g] = min(max(d, lo), hi)

    # Free gaps per row: the complement of the boxes, as (from, to) intervals.
    gaps = []
    for row in layers:
        occ = sorted((x[g] - width[g] / 2, x[g] + width[g] / 2) for g in row)
        free, prev = [], -1e9
        for a, b in occ:
            if a - prev > 2 * CLEAR:
                free.append((prev + CLEAR, a - CLEAR))
            prev = max(prev, b)
        free.append((prev + CLEAR, 1e9))
        gaps.append(free)

    def clear_x(li, want):
        """Nearest point in row li that is not inside a box."""
        best, bd = want, 1e18
        for a, b in gaps[li]:
            if a <= want <= b:
                return want
            d = a - want if want < a else want - b
            if d < bd:
                bd, best = d, a if want < a else b
        return best

    y = {g: layer_of[year[g]] * ROW_H for g in year}
    routes, intra = [], []
    for a, b, dev in edges:
        la, lb = layer_of[year[a]], layer_of[year[b]]
        if la >= lb:
            intra.append({"a": a, "b": b, "dev": dev})
            continue
        pts = [(x[a], y[a] + NODE_H / 2)]
        for li in range(la + 1, lb):
            t = (li - la) / float(lb - la)
            want = x[a] + (x[b] - x[a]) * t
            cx = clear_x(li, want)
            # Two points at the SAME x, bracketing the row band: the line must be
            # vertical while it is level with the boxes, or it clips one on the
            # way in even though the waypoint itself is in a gap.
            band = NODE_H / 2 + CLEAR
            pts.append((cx, li * ROW_H - band))
            pts.append((cx, li * ROW_H + band))
        pts.append((x[b], y[b] - NODE_H / 2))
        routes.append({"pts": pts, "dev": dev, "a": a, "b": b})
    return {"layers": layers, "x": x, "y": y, "w": width, "routes": routes,
            "intra": intra, "row_years": row_years, "years": years,
            "per_row": per_row}


def verify(L):
    """Assert no routed segment passes through a box. Samples along each leg."""
    boxes = collections.defaultdict(list)
    for row in L["layers"]:
        for g in row:
            boxes[round(L["y"][g])].append((L["x"][g] - L["w"][g] / 2, L["x"][g] + L["w"][g] / 2))
    bad = []
    for r in L["routes"]:
        pts = r["pts"]
        # The edge legitimately starts and ends ON a box, so skip its own rows.
        own = {round(L["y"][r["a"]]), round(L["y"][r["b"]])}
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            for rowy, spans in boxes.items():
                if rowy in own:
                    continue
                top, bot = rowy - NODE_H / 2, rowy + NODE_H / 2
                if not (min(y0, y1) < bot and max(y0, y1) > top):
                    continue
                for frac in range(11):
                    yy = top + (bot - top) * frac / 10.0
                    if not (min(y0, y1) <= yy <= max(y0, y1)):
                        continue
                    t = 0.0 if y1 == y0 else (yy - y0) / (y1 - y0)
                    xx = x0 + (x1 - x0) * t
                    if any(a < xx < b for a, b in spans):
                        bad.append((r["a"], r["b"], rowy))
                        break
                else:
                    continue
                break
    return bad


BG = "#14100c"
INK = "#e6d5b8"
FAINT = "#6d6151"
RULE = "#2b241b"
TYPE_FILL = ["#3a1f1a", "#16283a", "#2a1a3d", "#1b2f1a"]
TYPE_LINE = ["#ed6b52", "#75b3f2", "#b373ff", "#8ccc80"]
EDGE = "#5d5344"
EDGE_DEV = "#3f6ea8"


def esc(s):
    return html.escape(s, quote=True)


def render(name, year, L, gmap, path, view=None, scale=1.0, labels=True, title=""):
    X, Y, W = L["x"], L["y"], L["w"]
    full_w = max(X[v] + W[v] / 2 for r in L["layers"] for v in r) + 120
    full_h = len(L["layers"]) * (ROW_H) + 120
    ROW = ROW_H
    vx, vy, vw, vh = view if view else (0, 0, full_w, full_h)
    out = []
    out.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
               'viewBox="%.1f %.1f %.1f %.1f">' % (vw * scale, vh * scale, vx, vy, vw, vh))
    out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>'
               % (vx, vy, vw, vh, BG))

    # year rows
    for li, ys in enumerate(L["row_years"]):
        if not ys:
            continue
        yy = li * ROW
        if yy < vy - ROW or yy > vy + vh + ROW:
            continue
        out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1"/>'
                   % (vx, yy - NODE_H, vx + vw, yy - NODE_H, RULE))
        lbl = str(ys[0]) if len(ys) == 1 else "%d-%d" % (ys[0], ys[-1])
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-family="monospace" '
                   'font-size="%.0f">%s</text>'
                   % (vx + 6, yy + 4, FAINT, min(34, 13 / max(scale, .04)), lbl))

    # edges first
    chains = L["routes"]
    for ch in chains:
        pts = ch["pts"]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        if max(xs) < vx or min(xs) > vx + vw or max(ys) < vy or min(ys) > vy + vh:
            continue
        d = "M " + " L ".join("%.1f %.1f" % p for p in pts)
        out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%.2f" '
                   'opacity="%.2f"/>' % (d, EDGE_DEV if ch["dev"] else EDGE,
                                        max(0.55, 1.15 / max(scale, 0.25) ** 0.5),
                                        0.75 if len(pts) <= 4 else 0.42))

    # same-row edges arc through the gutter above the row, so they still enter
    # their target from the top like every other edge and never touch a box.
    for e in L.get("intra", []):
        xa, xb = X[e["a"]], X[e["b"]]
        yr = Y[e["a"]]
        top = yr - NODE_H / 2
        lift = min(ROW * 0.42, 40 + abs(xb - xa) * 0.05)
        d = ("M %.1f %.1f C %.1f %.1f %.1f %.1f %.1f %.1f"
             % (xa, top, xa, top - lift, xb, top - lift, xb, top))
        out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%.2f" opacity="0.8"/>'
                   % (d, EDGE_DEV if e["dev"] else EDGE,
                      max(0.8, 1.4 / max(scale, 0.25) ** 0.5)))

    # nodes
    for row in L["layers"]:
        for v in row:
            if isinstance(v, tuple):
                continue
            w, x, y = W[v], X[v], Y[v]
            if x + w < vx or x - w > vx + vw or y < vy - 40 or y > vy + vh + 40:
                continue
            g = gmap.get(v, 1)
            out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="3" '
                       'fill="%s" stroke="%s" stroke-width="1.2"/>'
                       % (x - w / 2, y - NODE_H / 2, w, NODE_H,
                          TYPE_FILL[g], TYPE_LINE[g]))
            if labels:
                t = name[v]
                maxc = int((w - 8) / CHAR_W)
                if len(t) > maxc:
                    t = t[:max(1, maxc - 1)] + "…"
                out.append('<text x="%.1f" y="%.1f" fill="%s" font-family="monospace" '
                           'font-size="11" text-anchor="middle">%s</text>'
                           % (x, y + 4, INK, esc(t)))
    if title:
        out.append('<text x="%.1f" y="%.1f" fill="%s" font-family="monospace" '
                   'font-size="%.0f">%s</text>'
                   % (vx + 10, vy + 30 / max(scale, .05), INK,
                      min(40, 15 / max(scale, .04)), esc(title)))
    out.append("</svg>")
    open(path, "w").write("\n".join(out))
    return full_w, full_h


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="path to write the SVG")
    ap.add_argument("--around", help="centre the view on this game")
    ap.add_argument("--zoom", type=float, default=0.105)
    ap.add_argument("--span", type=float, default=2800.0, help="view width when using --around")
    args = ap.parse_args()

    name, year, edges = load()
    L = build(name, year, edges, hand_x())
    bad = verify(L)
    view = None
    if args.around:
        k = C.norm(args.around)
        if k not in L["x"]:
            sys.exit("no such game on the map: %s" % args.around)
        view = (L["x"][k] - args.span / 2, L["y"][k] - args.span / 8,
                args.span, args.span * 0.42)
    w, h = render(name, year, L, genres(), args.out, view=view, scale=args.zoom,
                  labels=bool(args.around))
    print("%d games, %d edges" % (len(L["x"]), len(L["routes"])))
    print("canvas %.0f x %.0f px" % (w, h))
    print("segments crossing a box: %d %s" % (len(bad), "" if not bad else bad[:5]))
    print("wrote %s" % args.out)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

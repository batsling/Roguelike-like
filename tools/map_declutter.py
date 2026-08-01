#!/usr/bin/env python3
"""Reduce the number of straight edges that clip a box, starting from YOUR layout.

The hand map draws every edge as a single straight segment (1,044 rendered paths,
two vertices each — draw.io draws a direct line when `edgeStyle` is absent). There
is therefore nowhere to route around an obstacle: the only free variable is where
the boxes sit, and a line clips a box or it does not.

Laying the map out from scratch loses badly to hand placement, because the thing
that actually matters is SLOPE. A line crossing a box row sweeps sideways by
dx * band/dy, so a shallow line covers a wide interval and is nearly impossible to
fit between boxes; a steep one barely moves. Placing a child near its parent's
column — what the hand map does, and what a dense re-pack destroys — is what keeps
lines steep.

So this starts from the existing coordinates and only nudges. Release years (y)
are never touched; a box may only slide sideways, never past its neighbours'
spacing, and never further than --budget from where you put it.

    python3 tools/map_declutter.py                      # report current clips
    python3 tools/map_declutter.py --fix                # search for improvements
    python3 tools/map_declutter.py --move "Slay the Spire"   # where should a hub go?
    python3 tools/map_declutter.py --fix --write out.drawio  # save the result
"""
import argparse
import bisect
import collections
import html
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_map_sync as C

HERE = os.path.dirname(os.path.abspath(__file__))
DRAWIO = os.path.join(HERE, "Roguelikes.drawio")

CLEAR = 0.0        # extra margin a line must leave around a box (0 = touching counts)
MIN_GAP = 12.0     # keep at least this much air between two boxes in a row
BUDGET = 900.0     # how far a box may drift from its hand-placed x


def load_boxes(path):
    """Every game box with full geometry, plus the row it sits on."""
    root = C.load_model(path)
    boxes, order = {}, []
    for cell in root.findall(".//mxCell"):
        if cell.get("vertex") != "1":
            continue
        geom = cell.find("mxGeometry")
        label = C.strip_markup(cell.get("value"))
        if geom is None or not label or (cell.get("style") or "").startswith("text;"):
            continue
        if not all(geom.get(k) for k in ("x", "y", "width", "height")):
            continue
        key = C.norm(label)
        boxes[key] = {
            "id": cell.get("id"), "label": label,
            "cx": float(geom.get("x")) + float(geom.get("width")) / 2.0,
            "cy": float(geom.get("y")) + float(geom.get("height")) / 2.0,
            "w": float(geom.get("width")), "h": float(geom.get("height")),
            "x0": float(geom.get("x")), "y0": float(geom.get("y")),
        }
        order.append(key)
    return boxes, order


def load_edges(path, boxes):
    """Attached, non-convergent edges as (source, target) with source older."""
    root = C.load_model(path)
    label = {c.get("id"): C.strip_markup(c.get("value"))
             for c in root.findall(".//mxCell") if c.get("vertex") == "1"}
    out, seen = [], set()
    for cell in root.findall(".//mxCell"):
        if cell.get("edge") != "1":
            continue
        if C.edge_kind(cell.get("style")) in (C.KIND_CONVERGENT,):
            continue
        s, t = cell.get("source"), cell.get("target")
        if s not in label or t not in label:
            continue
        a, b = C.norm(label[s]), C.norm(label[t])
        if a not in boxes or b not in boxes or a == b:
            continue
        if boxes[a]["cy"] == boxes[b]["cy"]:
            continue
        if boxes[a]["cy"] > boxes[b]["cy"]:
            a, b = b, a
        if (a, b) in seen:
            continue
        seen.add((a, b))
        out.append((a, b))
    return out


class Map:
    """Boxes grouped into rows, with an index for fast segment queries."""

    def __init__(self, boxes, edges):
        self.b = boxes
        self.edges = edges
        self.rows = collections.defaultdict(list)
        for k, v in boxes.items():
            self.rows[round(v["cy"])].append(k)
        self.rowkeys = sorted(self.rows)
        self.incident = collections.defaultdict(list)
        for a, b in edges:
            self.incident[a].append((a, b))
            self.incident[b].append((a, b))
        # Which lines pass over each row, precomputed. Deriving this per query
        # made every candidate evaluation O(E) and the search unusable.
        self.crossing = collections.defaultdict(list)
        for a, b in edges:
            ya, yb = boxes[a]["cy"], boxes[b]["cy"]
            lo, hi = (ya, yb) if ya < yb else (yb, ya)
            for rk in self.rowkeys:
                if lo < rk < hi:
                    self.crossing[rk].append((a, b))
        for rk in self.rowkeys:
            self._sort(rk)

    def _sort(self, rk):
        self.rows[rk].sort(key=lambda k: self.b[k]["cx"])

    def row_of(self, k):
        return round(self.b[k]["cy"])

    def clipped_by(self, a, b, first_only=True):
        """Boxes the straight a->b segment passes through."""
        A, B = self.b[a], self.b[b]
        x1, y1, x2, y2 = A["cx"], A["cy"], B["cx"], B["cy"]
        lo_y, hi_y = min(y1, y2), max(y1, y2)
        hit = []
        for rk in self.rowkeys:
            if not (lo_y < rk < hi_y):
                continue
            row = self.rows[rk]
            xs = [self.b[k]["cx"] for k in row]
            # widest sideways sweep across this row's tallest box
            band = max(self.b[k]["h"] for k in row) / 2.0 + CLEAR
            t0 = (rk - band - y1) / (y2 - y1)
            t1 = (rk + band - y1) / (y2 - y1)
            sl = x1 + (x2 - x1) * max(0.0, min(1.0, t0))
            sh = x1 + (x2 - x1) * max(0.0, min(1.0, t1))
            if sl > sh:
                sl, sh = sh, sl
            i = bisect.bisect_left(xs, sl - 260)
            j = bisect.bisect_right(xs, sh + 260)
            for k in row[i:j]:
                if k == a or k == b:
                    continue
                if _segment_hits_box(x1, y1, x2, y2, self.b[k]):
                    hit.append(k)
                    if first_only:
                        return hit
        return hit

    def clips(self, subset=None):
        """Edges whose line clips at least one box."""
        return [(a, b) for a, b in (subset if subset is not None else self.edges)
                if self.clipped_by(a, b)]

    def edges_near(self, key, reach=400.0):
        """Edges moving `key` could affect: its own, plus lines crossing its row
        CLOSE ENOUGH to matter. A line crossing the row a thousand pixels away
        can neither be helped nor hurt by this box, and including it made every
        candidate evaluation scan hundreds of irrelevant edges."""
        rk = self.row_of(key)
        me = self.b[key]
        out = list(self.incident[key])
        limit = reach + me["w"] / 2.0 + 40.0
        for a, b in self.crossing[rk]:
            A, B = self.b[a], self.b[b]
            t = (rk - A["cy"]) / (B["cy"] - A["cy"])
            xs = A["cx"] + (B["cx"] - A["cx"]) * t
            if abs(xs - me["cx"]) <= limit:
                out.append((a, b))
        return list(dict.fromkeys(out))

    def overlaps(self, key):
        rk = self.row_of(key)
        me = self.b[key]
        for k in self.rows[rk]:
            if k == key:
                continue
            o = self.b[k]
            if abs(o["cx"] - me["cx"]) < (o["w"] + me["w"]) / 2.0 + MIN_GAP:
                return True
        return False

    def move(self, key, cx):
        self.b[key]["cx"] = cx
        self._sort(self.row_of(key))


def _segment_hits_box(x1, y1, x2, y2, box):
    """Exact segment/AABB overlap by the slab method, with a clearance margin."""
    rx0 = box["cx"] - box["w"] / 2.0 - CLEAR
    rx1 = box["cx"] + box["w"] / 2.0 + CLEAR
    ry0 = box["cy"] - box["h"] / 2.0 - CLEAR
    ry1 = box["cy"] + box["h"] / 2.0 + CLEAR
    dx, dy = x2 - x1, y2 - y1
    t0, t1 = 0.0, 1.0
    for p, q0, q1, o in ((dx, rx0, rx1, x1), (dy, ry0, ry1, y1)):
        if abs(p) < 1e-9:
            if o < q0 or o > q1:
                return False
            continue
        a, b = (q0 - o) / p, (q1 - o) / p
        if a > b:
            a, b = b, a
        t0, t1 = max(t0, a), min(t1, b)
        if t0 > t1:
            return False
    return True


# --------------------------------------------------------------------------

def candidates(M, key, budget):
    """Slots worth trying for `key`: just clear of each line crossing its row."""
    rk = M.row_of(key)
    me = M.b[key]
    home = me["cx"]
    out = [home]
    for a, b in M.edges_near(key):
        if key in (a, b):
            continue
        A, B = M.b[a], M.b[b]
        if not (min(A["cy"], B["cy"]) < rk < max(A["cy"], B["cy"])):
            continue
        band = me["h"] / 2.0 + CLEAR
        for edge_y in (rk - band, rk + band):
            t = (edge_y - A["cy"]) / (B["cy"] - A["cy"])
            xs = A["cx"] + (B["cx"] - A["cx"]) * t
            out.append(xs - me["w"] / 2.0 - CLEAR - 2)
            out.append(xs + me["w"] / 2.0 + CLEAR + 2)
    for d in (-4, -3, -2, -1, 1, 2, 3, 4):
        out.append(home + d * (me["w"] + MIN_GAP))
    seen, keep = set(), []
    for c in out:
        r = round(c, 1)
        if r in seen or abs(c - home) > budget:
            continue
        seen.add(r)
        keep.append(c)
    keep.sort(key=lambda c: abs(c - home))
    return keep


def improve(M, budget, passes, verbose=True):
    total = len(M.clips())
    for p in range(passes):
        # Only boxes implicated in a clip are worth moving.
        guilty = collections.Counter()
        for a, b in M.edges:
            for k in M.clipped_by(a, b, first_only=False):
                guilty[k] += 1
        if not guilty:
            break
        moved = 0
        for key, _n in guilty.most_common():
            scope = M.edges_near(key, budget)
            before = len(M.clips(scope))
            if not before:
                continue
            home = M.b[key]["cx"]
            best, best_n = home, before
            for c in candidates(M, key, budget)[:20]:
                M.move(key, c)
                if M.overlaps(key):
                    continue
                n = len(M.clips(scope))
                if n < best_n:
                    best, best_n = c, n
            M.move(key, best)
            if best != home:
                moved += 1
        now = len(M.clips())
        if verbose:
            print("  pass %d: %d clipping edges (moved %d boxes)" % (p + 1, now, moved))
        if now >= total and not moved:
            break
        total = now
    return total


def sweep(M, key, budget, step=40.0):
    """Clip count as a function of where one game sits — for the hubs."""
    scope = M.edges_near(key, budget)
    home = M.b[key]["cx"]
    rows = []
    c = home - budget
    while c <= home + budget:
        M.move(key, c)
        rows.append((c, None if M.overlaps(key) else len(M.clips(scope))))
        c += step
    M.move(key, home)
    return home, len(M.clips(scope)), rows


def write_drawio(src, dst, M):
    """Copy the .drawio through, rewriting only the x of boxes that moved."""
    with open(src, encoding="utf-8") as fh:
        text = fh.read()
    changed = 0
    for key, box in M.b.items():
        new_x = box["cx"] - box["w"] / 2.0
        if abs(new_x - box["x0"]) < 0.5:
            continue
        anchor = text.find('id="%s"' % box["id"])
        if anchor < 0:
            continue
        g = text.find("<mxGeometry", anchor)
        end = text.find(">", g)
        block = text[g:end]
        fixed, n = re.subn(r'x="[-0-9.]+"', 'x="%s"' % _fmt(new_x), block, count=1)
        if n:
            text = text[:g] + fixed + text[end:]
            changed += 1
    with open(dst, "w", encoding="utf-8") as fh:
        fh.write(text)
    return changed


def _fmt(v):
    return str(int(v)) if float(v).is_integer() else ("%g" % v)


def main():
    global CLEAR
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map", default=DRAWIO)
    ap.add_argument("--fix", action="store_true", help="search for a better placement")
    ap.add_argument("--move", help="report the best column for one game")
    ap.add_argument("--budget", type=float, default=BUDGET,
                    help="how far a box may drift from its hand-placed x")
    ap.add_argument("--passes", type=int, default=6)
    ap.add_argument("--write", help="write the improved layout to a new .drawio")
    ap.add_argument("--clear", type=float, default=CLEAR,
                    help="margin a line must leave around a box (default 0)")
    ap.add_argument("--list", action="store_true", help="list every clipping edge")
    args = ap.parse_args()
    CLEAR = args.clear

    boxes, _order = load_boxes(args.map)
    edges = load_edges(args.map, boxes)
    M = Map(boxes, edges)
    bad = M.clips()
    print("%d boxes, %d straight edges" % (len(boxes), len(edges)))
    print("clipping a box: %d (%.1f%%)" % (len(bad), 100.0 * len(bad) / max(1, len(edges))))

    if args.list:
        for a, b in bad:
            hit = M.clipped_by(a, b, first_only=False)
            print("    %-34s -> %-34s clips %s"
                  % (boxes[a]["label"][:32], boxes[b]["label"][:32],
                     ", ".join(boxes[h]["label"] for h in hit[:3])))

    if args.move:
        key = C.norm(args.move)
        if key not in boxes:
            sys.exit("no such game on the map: %s" % args.move)
        home, now, rows = sweep(M, key, args.budget)
        ok = [(c, n) for c, n in rows if n is not None]
        print("\n%s sits at x=%.0f, and %d nearby edge(s) clip a box there."
              % (boxes[key]["label"], home, now))
        if not ok:
            print("  every alternative column within the budget overlaps a neighbour.")
        else:
            best = min(ok, key=lambda t: t[1])
            print("  best column within +/-%.0f: x=%.0f -> %d clipping (%+d)"
                  % (args.budget, best[0], best[1], best[1] - now))
            print("  profile (column: clipping edges, '-' = overlaps a neighbour):")
            for c, n in rows[::max(1, len(rows) // 24)]:
                bar = "-" if n is None else "#" * n
                print("    %+8.0f  %s" % (c - home, bar if bar else "0"))

    if args.fix:
        print("\nimproving (budget %.0f px per box)..." % args.budget)
        final = improve(M, args.budget, args.passes)
        print("result: %d clipping edges (%.1f%%), was %d"
              % (final, 100.0 * final / max(1, len(edges)), len(bad)))
        if args.write:
            n = write_drawio(args.map, args.write, M)
            print("wrote %s (%d boxes moved)" % (args.write, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())

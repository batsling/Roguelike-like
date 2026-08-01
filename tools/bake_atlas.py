#!/usr/bin/env python3
"""Bake the constellation atlas layout from the authored catalog.

Reads every `data/games/*.tres` and writes `data/atlas_layout.tres` — the star
positions the Atlas screen draws. Re-run it after `import-games-godot.py`; the
layout is a pure function of the catalog, so adding a game or a connection and
re-baking is the whole update procedure.

The layout, in three stages:

1. CAPITALS + REGIONS. The `--capitals` highest-degree games become capitals.
   Every other game joins whichever capital it reaches in fewest hops (ties go
   to the higher-degree capital). Games no capital can reach are "drifting" and
   are laid out as their own small components.

2. CLUSTERS. Inside a region, a BFS spanning tree is rooted at the capital and
   laid out bottom-up: each node's child subtrees are packed as discs AROUND the
   parent star, densest-first. A subtree's radius is MEASURED from its realised
   point cloud rather than bounded from its children's discs — the nested bound
   doubles at every level and throws deep chains into the void.

3. PACKING. Regions and drifting components are packed as discs, largest first,
   each dropped at the valid tangent position nearest the origin. Region size
   therefore drives the sky's shape instead of being forced onto an even circle.

Nothing here is random: same catalog in, same sky out.

Usage:
    python3 tools/bake_atlas.py                    # 8 capitals -> data/atlas_layout.tres
    python3 tools/bake_atlas.py --capitals 6
    python3 tools/bake_atlas.py --stats            # report without writing
"""
import argparse
import collections
import glob
import math
import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES_DIR = os.path.join(PROJECT_ROOT, "data", "games")
OUT_PATH = os.path.join(PROJECT_ROOT, "data", "atlas_layout.tres")

DEFAULT_CAPITALS = 8
PAD = 3.0                 # clear space kept between any two stars
GAP_SAMPLES = 72          # directions tried when looking for a cluster's exit


def star_radius(degree: int) -> float:
    """Drawn size of a star. Must match AtlasView.star_radius()."""
    return 1.5 + math.sqrt(degree) * 0.95


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

def load_games() -> list[dict]:
    games = []
    for path in sorted(glob.glob(os.path.join(GAMES_DIR, "*.tres"))):
        src = open(path, encoding="utf-8").read()

        def field(pattern, default=None):
            m = re.search(pattern, src, re.M)
            return m.group(1) if m else default

        gid = field(r'^id = &"([^"]+)"')
        if not gid:
            continue
        influenced = field(r"^games_influenced = Array\[StringName\]\(\[(.*?)\]\)", "")
        games.append({
            "id": gid,
            "name": (field(r'^display_name = "((?:[^"\\]|\\.)*)"', gid) or gid).replace('\\"', '"'),
            "year": int(field(r"^year = (-?\d+)", "0")),
            "type": int(field(r"^type = (\d+)", "1")),
            "out": re.findall(r'&"([^"]+)"', influenced or ""),
        })
    return games


def build_graph(games: list[dict]):
    index = {g["id"]: i for i, g in enumerate(games)}
    adj = [[] for _ in games]
    edges, seen = [], set()
    for g in games:
        a = index[g["id"]]
        for other in g["out"]:
            b = index.get(other)
            if b is None or b == a:
                continue
            key = (min(a, b), max(a, b))
            if key in seen:
                continue
            seen.add(key)
            edges.append(key)
            adj[a].append(b)
            adj[b].append(a)
    return adj, edges


def bfs(adj, src: int) -> list[int]:
    dist = [-1] * len(adj)
    dist[src] = 0
    queue = collections.deque([src])
    while queue:
        v = queue.popleft()
        for w in adj[v]:
            if dist[w] < 0:
                dist[w] = dist[v] + 1
                queue.append(w)
    return dist


# ---------------------------------------------------------------------------
# Disc packing
# ---------------------------------------------------------------------------

def pack_around(seed_radius: float, radii: list[float]) -> list[tuple[float, float]]:
    """Pack discs around a fixed seed disc at the origin.

    Each disc lands at the valid position tangent to two already-placed discs
    that sits nearest the origin, so the cluster grows dense from the middle
    out instead of leaving a hollow ring.
    """
    placed = [(0.0, 0.0, seed_radius)]
    out: list[tuple[float, float]] = [(0.0, 0.0)] * len(radii)
    order = sorted(range(len(radii)), key=lambda i: (-radii[i], i))

    def fits(x, y, r):
        for px, py, pr in placed:
            dx, dy = x - px, y - py
            if dx * dx + dy * dy < (r + pr) * (r + pr) - 1e-7:
                return False
        return True

    for idx in order:
        r = radii[idx]
        best = None
        best_score = None
        for i in range(len(placed)):
            ax, ay, ar = placed[i]
            ra = ar + r
            for j in range(i + 1, len(placed)):
                bx, by, br = placed[j]
                rb = br + r
                dx, dy = bx - ax, by - ay
                d2 = dx * dx + dy * dy
                if d2 > (ra + rb) * (ra + rb) or d2 == 0.0:
                    continue
                d = math.sqrt(d2)
                if d < abs(ra - rb):
                    continue
                a = (ra * ra - rb * rb + d2) / (2.0 * d)
                h2 = ra * ra - a * a
                if h2 < 0.0:
                    continue
                h = math.sqrt(h2)
                mx, my = ax + a * dx / d, ay + a * dy / d
                for sign in (1.0, -1.0):
                    x = mx + sign * h * dy / d
                    y = my - sign * h * dx / d
                    score = x * x + y * y
                    if best_score is not None and score >= best_score:
                        continue
                    if not fits(x, y, r):
                        continue
                    best, best_score = (x, y), score
        if best is None:
            # First child, or a genuinely blocked spot: walk out on a spiral.
            rr, t = seed_radius + r, 0
            while t < 3000:
                a = t * 0.618 * math.tau
                x, y = math.cos(a) * rr, math.sin(a) * rr
                if fits(x, y, r):
                    best = (x, y)
                    break
                t += 1
                if t % 12 == 0:
                    rr += r * 0.35
            if best is None:
                best = (seed_radius + r, 0.0)
        out[idx] = best
        placed.append((best[0], best[1], r))
    return out


def pack_discs(radii: list[float]) -> list[tuple[float, float]]:
    """Pack free-floating discs, largest first, each as close to the origin as it fits."""
    out: list[tuple[float, float]] = [(0.0, 0.0)] * len(radii)
    order = sorted(range(len(radii)), key=lambda i: (-radii[i], i))
    placed: list[tuple[float, float, float]] = []

    def fits(x, y, r):
        for px, py, pr in placed:
            dx, dy = x - px, y - py
            if dx * dx + dy * dy < (r + pr) * (r + pr) - 1e-6:
                return False
        return True

    for n, idx in enumerate(order):
        r = radii[idx]
        if n == 0:
            pos = (0.0, 0.0)
        elif n == 1:
            pos = (placed[0][2] + r, 0.0)
        else:
            best, best_score = None, None
            for i in range(len(placed)):
                ax, ay, ar = placed[i]
                ra = ar + r
                for j in range(i + 1, len(placed)):
                    bx, by, br = placed[j]
                    rb = br + r
                    dx, dy = bx - ax, by - ay
                    d2 = dx * dx + dy * dy
                    if d2 > (ra + rb) * (ra + rb) or d2 == 0.0:
                        continue
                    d = math.sqrt(d2)
                    if d < abs(ra - rb):
                        continue
                    a = (ra * ra - rb * rb + d2) / (2.0 * d)
                    h2 = ra * ra - a * a
                    if h2 < 0.0:
                        continue
                    h = math.sqrt(h2)
                    mx, my = ax + a * dx / d, ay + a * dy / d
                    for sign in (1.0, -1.0):
                        x = mx + sign * h * dy / d
                        y = my - sign * h * dx / d
                        score = x * x + y * y
                        if best_score is not None and score >= best_score:
                            continue
                        if not fits(x, y, r):
                            continue
                        best, best_score = (x, y), score
            if best is None:
                rr, t = placed[0][2] + r, 0
                while t < 4000:
                    a = t * 0.5
                    x, y = math.cos(a) * rr, math.sin(a) * rr
                    if fits(x, y, r):
                        best = (x, y)
                        break
                    t += 1
                    rr += r * 0.12
                best = best or (0.0, 0.0)
            pos = best
        out[idx] = pos
        placed.append((pos[0], pos[1], r))
    return out


# ---------------------------------------------------------------------------
# Cluster layout
# ---------------------------------------------------------------------------

def best_gap(points: list[tuple[int, float, float]], radius_of) -> float:
    """Bearing with the most clear space — where the link to the parent exits."""
    best_angle, best_clear = 0.0, -1.0
    for k in range(GAP_SAMPLES):
        a = k / GAP_SAMPLES * math.tau
        ux, uy = math.cos(a), math.sin(a)
        clear = 1e9
        for node, px, py in points:
            t = px * ux + py * uy
            if t <= 1e-9:
                continue
            r = radius_of(node) + PAD
            qx, qy = px - t * ux, py - t * uy
            d2 = qx * qx + qy * qy
            if d2 >= r * r:
                continue
            clear = min(clear, t - math.sqrt(r * r - d2))
        if clear > best_clear:
            best_clear, best_angle = clear, a
    return best_angle


def cluster_layout(root: int, children: dict, radius_of):
    """Lay a spanning tree out bottom-up, returning (enclosing_radius, point cloud)."""
    order, stack = [], [root]
    while stack:
        v = stack.pop()
        order.append(v)
        stack.extend(children.get(v, ()))

    radius: dict[int, float] = {}
    cloud: dict[int, list[tuple[int, float, float]]] = {}
    gap: dict[int, float] = {}

    for v in reversed(order):
        kids = children.get(v, [])
        points = [(v, 0.0, 0.0)]
        if kids:
            radii = [radius[c] + PAD * 0.5 for c in kids]
            slots = pack_around(radius_of(v) + PAD * 0.5, radii)
            for c, (ox, oy) in zip(kids, slots):
                # Turn the child's cluster so its emptiest bearing points back at v.
                rot = (math.atan2(oy, ox) + math.pi) - gap[c]
                ca, sa = math.cos(rot), math.sin(rot)
                for node, px, py in cloud.pop(c):
                    points.append((node, ox + px * ca - py * sa, oy + px * sa + py * ca))
        radius[v] = max(math.hypot(px, py) + radius_of(node) for node, px, py in points)
        cloud[v] = points
        gap[v] = best_gap(points, radius_of)

    return radius[root], cloud[root]


def span_tree(root: int, adj, hop, owner, owner_id, degree) -> dict:
    """BFS spanning tree over one region: a node's parent is its best-connected
    neighbour one hop closer to the capital."""
    children = {root: []}
    queue = collections.deque([root])
    seen = {root}
    while queue:
        v = queue.popleft()
        nxt = [w for w in adj[v]
               if owner[w] == owner_id and w not in seen and hop[w] == hop[v] + 1]
        nxt.sort(key=lambda w: (-degree[w], w))
        for w in nxt:
            seen.add(w)
            children[v].append(w)
            children[w] = []
            queue.append(w)
    return children


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

def build_layout(games, adj, num_capitals: int):
    n = len(games)
    degree = [len(a) for a in adj]
    radius_of = lambda i: star_radius(degree[i])

    capitals = sorted(range(n), key=lambda i: (-degree[i], games[i]["name"]))[:num_capitals]

    owner = [-1] * n
    hop = [1 << 30] * n
    for ci, cap in enumerate(capitals):
        dist = bfs(adj, cap)
        for i in range(n):
            d = dist[i]
            if d < 0:
                continue
            if d < hop[i] or (d == hop[i] and owner[i] >= 0
                              and degree[cap] > degree[capitals[owner[i]]]):
                hop[i], owner[i] = d, ci

    groups = []   # {"root", "region", "members", "radius", "cloud"}
    for ci, cap in enumerate(capitals):
        children = span_tree(cap, adj, hop, owner, ci, degree)
        rad, cloud = cluster_layout(cap, children, radius_of)
        groups.append({"root": cap, "region": ci, "members": list(children),
                       "radius": rad, "cloud": cloud, "pad": 0.0})

    # Components no capital can reach — the drifting stars.
    visited = [False] * n
    for i in range(n):
        if owner[i] >= 0 or visited[i]:
            continue
        comp, queue, visited[i] = [], collections.deque([i]), True
        while queue:
            v = queue.popleft()
            comp.append(v)
            for w in adj[v]:
                if not visited[w] and owner[w] < 0:
                    visited[w], _ = True, queue.append(w)
        root = min(comp, key=lambda v: (-degree[v], v))
        local_dist = bfs(adj, root)
        local_owner = [-1] * n
        local_hop = [1 << 30] * n
        for v in comp:
            local_owner[v], local_hop[v] = 0, local_dist[v]
        children = span_tree(root, adj, local_hop, local_owner, 0, degree)
        rad, cloud = cluster_layout(root, children, radius_of)
        groups.append({"root": root, "region": -1, "members": comp,
                       "radius": rad, "cloud": cloud, "pad": 9.0})

    centres = pack_discs([g["radius"] + g["pad"] for g in groups])
    xs, ys = [0.0] * n, [0.0] * n
    for group, (cx, cy) in zip(groups, centres):
        group["x"], group["y"] = cx, cy
        for node, px, py in group["cloud"]:
            xs[node], ys[node] = cx + px, cy + py

    return {"capitals": capitals, "owner": owner, "hop": hop,
            "degree": degree, "xs": xs, "ys": ys, "groups": groups}


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def fmt_floats(values) -> str:
    return ", ".join(f"{v:.3f}" for v in values)


def write_resource(games, edges, layout, path: str) -> None:
    xs, ys = layout["xs"], layout["ys"]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    pad = 12.0

    flat_edges = []
    for a, b in edges:
        flat_edges.extend((a, b))

    # Where each constellation actually sits. The packer knows this exactly — the
    # cluster was built around its capital — so the view never has to guess it
    # from a centroid, which lands off-centre on a lopsided region.
    region_cx, region_cy, region_r = [], [], []
    for group in layout["groups"]:
        if group["region"] < 0:
            continue
        region_cx.append(xs[group["root"]])
        region_cy.append(ys[group["root"]])
        region_r.append(group["radius"])

    body = f"""[gd_resource type="Resource" script_class="AtlasLayout" load_steps=2 format=3 uid="uid://atlas_layout"]

[ext_resource type="Script" path="res://scripts/resources/AtlasLayout.gd" id="1_atlas"]

[resource]
script = ExtResource("1_atlas")
game_ids = PackedStringArray({", ".join('"%s"' % g["id"] for g in games)})
xs = PackedFloat32Array({fmt_floats(xs)})
ys = PackedFloat32Array({fmt_floats(ys)})
region = PackedInt32Array({", ".join(str(v) for v in layout["owner"])})
hops = PackedInt32Array({", ".join(str(v if v < (1 << 29) else -1) for v in layout["hop"])})
edges = PackedInt32Array({", ".join(str(v) for v in flat_edges)})
capitals = PackedInt32Array({", ".join(str(v) for v in layout["capitals"])})
region_cx = PackedFloat32Array({fmt_floats(region_cx)})
region_cy = PackedFloat32Array({fmt_floats(region_cy)})
region_radius = PackedFloat32Array({fmt_floats(region_r)})
bounds = Rect2({minx - pad:.3f}, {miny - pad:.3f}, {maxx - minx + pad * 2:.3f}, {maxy - miny + pad * 2:.3f})
"""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)


def report(games, edges, layout, num_capitals: int) -> None:
    owner, degree = layout["owner"], layout["degree"]
    sizes = collections.Counter(o for o in owner if o >= 0)
    cross = sum(1 for a, b in edges if owner[a] != owner[b])
    drift = sum(1 for o in owner if o < 0)
    xs, ys = layout["xs"], layout["ys"]

    print(f"[bake_atlas] {len(games)} games, {len(edges)} edges, {num_capitals} capitals")
    for ci, cap in enumerate(layout["capitals"]):
        print(f"[bake_atlas]   {games[cap]['name']:<28} {sizes.get(ci, 0):>4} games  "
              f"deg {degree[cap]:>3}")
    print(f"[bake_atlas] cross-region links {cross} ({cross / max(1, len(edges)) * 100:.1f}%)")
    print(f"[bake_atlas] drifting {drift}")
    print(f"[bake_atlas] sky {max(xs) - min(xs):.0f} x {max(ys) - min(ys):.0f}")


def verify(layout) -> int:
    """Every pair of stars must clear each other. Returns the overlap count."""
    xs, ys, degree = layout["xs"], layout["ys"], layout["degree"]
    cell = 48.0
    grid = collections.defaultdict(list)
    for i in range(len(xs)):
        grid[(int(xs[i] // cell), int(ys[i] // cell))].append(i)
    bad = 0
    for i in range(len(xs)):
        gx, gy = int(xs[i] // cell), int(ys[i] // cell)
        for ax in (-1, 0, 1):
            for ay in (-1, 0, 1):
                for j in grid.get((gx + ax, gy + ay), ()):
                    if j <= i:
                        continue
                    need = star_radius(degree[i]) + star_radius(degree[j])
                    if math.hypot(xs[i] - xs[j], ys[i] - ys[j]) < need - 1e-6:
                        bad += 1
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--capitals", type=int, default=DEFAULT_CAPITALS,
                    help=f"how many hubs become capitals (default {DEFAULT_CAPITALS})")
    ap.add_argument("--out", default=OUT_PATH, help="where to write the layout resource")
    ap.add_argument("--stats", action="store_true", help="report only, write nothing")
    args = ap.parse_args()

    games = load_games()
    if not games:
        print(f"[bake_atlas] no games found in {GAMES_DIR}", file=sys.stderr)
        return 1
    adj, edges = build_graph(games)
    layout = build_layout(games, adj, max(1, min(args.capitals, len(games))))

    report(games, edges, layout, args.capitals)
    overlaps = verify(layout)
    if overlaps:
        print(f"[bake_atlas] {overlaps} overlapping star pairs — layout is wrong", file=sys.stderr)
        return 1
    print("[bake_atlas] no overlapping stars")

    if args.stats:
        return 0
    write_resource(games, edges, layout, args.out)
    print(f"[bake_atlas] wrote {os.path.relpath(args.out, PROJECT_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

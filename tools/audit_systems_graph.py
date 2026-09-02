#!/usr/bin/env python3
"""Audit the `chart` sheet of tools/Roguelikes.xlsx — the systems graph.

Read-only. Nothing is written back to the workbook, so this is safe to run at
any time and needs no `_xlsx_surgery` write pass.

It does three jobs, in the order the design doc (`docs/systems-graph.md`) says
they matter:

1. **Hygiene.** Subsystems with no Good Direction (§4.1 calls this a hard
   error), singular/plural collisions in the System vocabulary, Dir values
   outside {Up, Down}, `Otainable` references that resolve to no row.
2. **Coverage.** Which content sheets have node rows and which do not, so the
   "the chart flatters the game" problem in §7.5 is a number rather than a
   worry.
3. **Structure.** Collapses every row through the trigger -> emitting-system
   lookup (§4.2) into a signed system -> system graph, then reports the cycles,
   the self-loops, and — most usefully — the SINKS: systems that receive edges
   and emit none. A sink is where a cycle was going to close and didn't.

    python3 tools/audit_systems_graph.py [--edges] [--cycles]
"""

import argparse
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

BOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "chart"

# Column letters of the repeating four-column arrow blocks (§3).
BLOCKS = [("D", "E", "F", "G"), ("H", "I", "J", "K"),
          ("L", "M", "N", "O"), ("P", "Q", "R", "S")]

# The System column mixes singular and plural for the same system. Until the
# sheet picks one, fold them here so the group-by does not silently split a
# system in half (§6, "Singular/plural join failure").
CANON = {
    "Bomb": "Bombs", "Tile": "Tiles", "Object": "Objects", "Item": "Items",
    "Pill": "Pills", "Potion": "Potions", "Card": "Cards", "Shield": "Shields",
    "Enemy": "Enemies", "Goal": "Goals", "Status": "Statuses", "Scroll": "Scrolls",
    "Wand": "Wands",
}

# §4.2's missing lookup, authored. Maps a trigger to the system that FIRES it,
# which is what turns each row from a one-hop arrow into the two-hop path that
# closes loops. `Passive` is deliberately None: an ungated arrow's source is
# wherever the content entered the run, which `Otainable` already says.
EMITTED_BY = {
    "Item Pickup": "Loot", "Loot Use": "Loot", "Shop Purchase": "Stats",
    "Card Use": "Cards", "Pill Use": "Pills", "Scroll Use": "Scrolls",
    "Wand Use": "Wands", "Item Use": "Items",
    "Potion Quaff": "Potions", "Potion Throw": "Potions",
    "Bomb Use": "Bombs", "Object Use": "Objects", "Gold Use": "Stats",
    "Combat Start": "Enemies", "Combat End": "Enemies", "Enemy Defeat": "Enemies",
    "Damage Taken": "Enemies", "Enemy Spawn": "Enemies", "Enemy Movement": "Enemies",
    "Health Lost": "Health", "On Level Up": "Goals", "On Transmute Gain": "Stats",
    "Game Completion": "Goals", "Game Loss": "Goals",
    "Passive": None,
}

# `Otainable` place names, mapped to the system that supplies them, for the
# Passive case above.
OBTAINED_FROM = {
    "Chest": "Loot", "Boss Chest": "Loot", "Starter": "Goals",
    "Enemy Defeat": "Enemies", "Game Completion": "Goals",
}

# Content sheets that ought to have node rows, and the column holding the name.
CONTENT = [
    ("Item", "items", "Name"), ("Card", "cards", "Name"), ("Pill", "pills", "Name"),
    ("Potion", "potions", "Name"), ("Scroll", "scrolls", "Scrolls"),
    ("Wand", "wands", "Name"), ("Object", "objects", "Name"),
    ("Event", "events", "Event"), ("Unit", "units", "Name"),
    ("Enemy", "enemies", "Name"), ("Boss", "bosses", "Name"),
    ("Ability", "abilities", "Name"), ("Status", "statuses", "Name"),
    ("Curse", "curses", "Curse"), ("Tile", "tiles", "Name"),
    ("Amulet", "amulets", "Type"), ("Character", "characters", "Name"),
    ("Location", "locations", "Name"),
]


def split_cell(text):
    """Semicolons separate references; commas separate names inside one.

    `Item: Blood Bombs, Hot Bombs; Character Start: Isaac` is two references,
    the first naming two items. Splitting on commas universally — which §4.5
    proposed before the sheet grew qualified refs — would shred that.
    """
    return [p.strip() for p in (text or "").split(";") if p.strip()]


class Row:
    def __init__(self, n, cells, header):
        self.n = n
        get = lambda c: (cells.get(c) or "").strip()  # noqa: E731
        self.name = get("A")
        self.obtainable = get("B")
        self.type = get("C")
        self.edges = []
        for sys_c, sub_c, trig_c, dir_c in BLOCKS:
            system, sub = get(sys_c), get(sub_c)
            if not system or system == "N/A":
                continue
            self.edges.append((system, sub, get(trig_c), get(dir_c)))


def load():
    with Workbook(BOOK) as wb:
        grid = wb.read_grid(SHEET)
    header = {}
    for i, v in enumerate(grid[0]):
        header[chr(ord("A") + i) if i < 26 else "?"] = str(v)
    rows, good_dir, groups = [], {}, []
    for n, raw in enumerate(grid[1:], start=2):
        cells = {}
        for i, v in enumerate(raw):
            if i < 26 and v not in ("", None):
                cells[chr(ord("A") + i)] = str(v)
        if cells.get("U"):
            good_dir[cells["U"].strip()] = (cells.get("V") or "").strip()
        if cells.get("W"):
            groups.append((n, cells["W"].strip()))
        if cells.get("A"):
            rows.append(Row(n, cells, header))
    return rows, good_dir, groups


def colour(direction, sub, good_dir):
    """§4.1: colour is Dir x Good Direction, never hand-entered."""
    good = good_dir.get(sub)
    if not good:
        return None
    return "green" if direction == good else "red"


def sources_for(row, trigger):
    """The systems an arrow departs FROM, per §4.2."""
    if trigger != "Passive":
        emitter = EMITTED_BY.get(trigger, "?")
        return [] if emitter in (None, "?") else [emitter]
    out = set()
    for ref in split_cell(row.obtainable):
        if ":" in ref:
            out.add(CANON.get(ref.split(":", 1)[0].strip(), ref.split(":", 1)[0].strip()))
        else:
            for place in (p.strip() for p in ref.split(",")):
                if place in OBTAINED_FROM:
                    out.add(OBTAINED_FROM[place])
    return sorted(out)


def build(rows, good_dir):
    edges = Counter()
    uncoloured, unknown_triggers = [], Counter()
    for row in rows:
        for system, sub, trig, direction in row.edges:
            c = colour(direction, sub, good_dir)
            if c is None:
                uncoloured.append((row.name, system, sub))
            for t in (x.strip() for x in trig.replace(";", ",").split(",") if x.strip()):
                if t not in EMITTED_BY:
                    unknown_triggers[t] += 1
                for src in sources_for(row, t):
                    edges[(src, CANON.get(system, system), c or "uncoloured")] += 1
    return edges, uncoloured, unknown_triggers


def find_cycles(edges, limit=4):
    adj = defaultdict(set)
    for src, dst, _ in edges:
        if src != dst:
            adj[src].add(dst)
    found = set()

    def walk(start, cur, path, seen):
        if len(path) > limit:
            return
        for nxt in adj.get(cur, ()):
            if nxt == start and len(path) >= 2:
                i = path.index(min(path))
                found.add(tuple(path[i:] + path[:i]))
            elif nxt not in seen:
                walk(start, nxt, path + [nxt], seen | {nxt})

    for node in sorted(adj):
        walk(node, node, [node], {node})
    return sorted(found, key=lambda c: (len(c), c))


def content_names(sheet, column):
    try:
        with Workbook(BOOK) as wb:
            grid = wb.read_grid(sheet)
    except Exception:
        return None
    if not grid:
        return set()
    header = [str(v).strip() for v in grid[0]]
    if column not in header:
        return None
    i = header.index(column)
    return {str(r[i]).strip() for r in grid[1:] if i < len(r) and str(r[i]).strip()}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--edges", action="store_true", help="list every system->system edge")
    ap.add_argument("--cycles", action="store_true", help="list the cycles")
    args = ap.parse_args()

    rows, good_dir, groups = load()
    edges, uncoloured, unknown_triggers = build(rows, good_dir)
    arrows = sum(len(r.edges) for r in rows)

    print(f"{len(rows)} node rows, {arrows} arrows, {len(good_dir)} Good Direction entries")
    print(f"node types: {dict(Counter(r.type for r in rows))}\n")

    print("== 1. hygiene ==")
    if uncoloured:
        print(f"  {len(uncoloured)} arrow(s) CANNOT BE COLOURED (no Good Direction):")
        for name, system, sub in uncoloured:
            print(f"     {name} -> {system} . {sub}")
    else:
        print("  every arrow has a Good Direction")

    used_subs = {sub for r in rows for _, sub, _, _ in r.edges if sub}
    stale = sorted(k for k in good_dir if k not in used_subs)
    if stale:
        print(f"  {len(stale)} Good Direction entr(ies) no row uses: {', '.join(stale)}")

    systems = {s for r in rows for s, _, _, _ in r.edges}
    collisions = sorted(s for s in systems if s in CANON and CANON[s] in systems)
    if collisions:
        print("  singular/plural collisions in the System column: "
              + ", ".join(f"{s}/{CANON[s]}" for s in collisions))

    dirs = Counter(d for r in rows for _, _, _, d in r.edges)
    odd = {d: n for d, n in dirs.items() if d not in ("Up", "Down")}
    if odd:
        print(f"  Dir values outside Up/Down: {odd}")

    multi = defaultdict(set)
    for r in rows:
        for system, sub, _, _ in r.edges:
            if sub:
                multi[sub].add(system)
    split_subs = {k: sorted(v) for k, v in multi.items() if len(v) > 1}
    if split_subs:
        print("  subsystem filed under more than one system:")
        for k, v in sorted(split_subs.items()):
            print(f"     {k}: {' / '.join(v)}")

    if unknown_triggers:
        print(f"  triggers with no emitting system in EMITTED_BY: {dict(unknown_triggers)}")

    by_type = defaultdict(set)
    for r in rows:
        by_type[r.type].add(r.name)
    all_nodes = {n for v in by_type.values() for n in v}
    dangling, tangled = [], []
    for r in rows:
        for ref in split_cell(r.obtainable):
            if ":" not in ref:
                continue
            kind, value = (x.strip() for x in ref.split(":", 1))
            if ":" in value:
                # A second qualifier inside one semicolon-delimited reference:
                # the comma is doing two jobs at once and cannot be parsed.
                tangled.append((r.name, ref))
                continue
            for target in (v.strip() for v in value.split(",")):
                pool = by_type.get(kind, set()) if kind != "Loot" else all_nodes
                if kind in by_type or kind == "Loot":
                    if target not in pool:
                        dangling.append((r.name, f"{kind}: {target}"))
    if tangled:
        print(f"  {len(tangled)} Otainable cell(s) packing two qualified refs into one "
              "comma list — separate them with ';':")
        for name, ref in tangled:
            print(f"     {name} -> {ref!r}")
    if dangling:
        print(f"  {len(dangling)} Otainable reference(s) resolving to no node row:")
        for name, ref in dangling:
            print(f"     {name} -> {ref}")

    print("\n== 2. coverage ==")
    for label, sheet, column in CONTENT:
        have = by_type.get(label, set())
        src = content_names(sheet, column)
        if src is None:
            print(f"  {label:10s} sheet unreadable; {len(have)} node row(s)")
            continue
        gap = sorted(src - have)
        orphan = sorted(have - src)
        flag = "" if not gap else f"  MISSING {len(gap)}"
        print(f"  {label:10s} {len(have):3d}/{len(src):3d} node rows{flag}")
        if gap and len(gap) <= 12:
            print(f"             {', '.join(gap)}")
        if orphan:
            print(f"             node row(s) matching no {sheet} row: {', '.join(orphan)}")

    print("\n== 3. structure ==")
    tally = Counter()
    for (_, _, c), n in edges.items():
        tally[c] += n
    print(f"  {sum(tally.values())} system->system edges "
          f"({tally['green']} green, {tally['red']} red, {tally['uncoloured']} uncoloured)")

    srcs = {a for a, _, _ in edges}
    dsts = {b for _, b, _ in edges}
    inbound = Counter()
    for (_, b, _), n in edges.items():
        inbound[b] += n
    sinks = sorted(dsts - srcs, key=lambda s: -inbound[s])
    print(f"\n  SINKS — receive arrows, emit none ({len(sinks)}). "
          "Each is a cycle that did not close:")
    for s in sinks:
        print(f"     {inbound[s]:3d} in, 0 out   {s}")

    cycles = find_cycles(edges)
    print(f"\n  {len(cycles)} cycle(s) of length 2-4")
    if args.cycles or True:
        for c in cycles:
            print("     " + " -> ".join(c) + f" -> {c[0]}")

    if args.edges:
        print("\n  every edge:")
        for (a, b, c), n in sorted(edges.items(), key=lambda x: -x[1]):
            tag = "  [SELF]" if a == b else ""
            print(f"     {n:3d}  {a:10s} -> {b:12s} {c}{tag}")

    return 1 if uncoloured else 0


if __name__ == "__main__":
    raise SystemExit(main())

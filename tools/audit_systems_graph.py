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
from _xlsx_surgery import Workbook, col_name  # noqa: E402

BOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")
SHEET = "chart"

# Column letters of the repeating four-column arrow blocks (§3).
BLOCKS = [("D", "E", "F", "G"), ("H", "I", "J", "K"),
          ("L", "M", "N", "O"), ("P", "Q", "R", "S")]

# The sheet settled on plural (see tools/_chart_system_vocabulary.py), so this
# is now a REGRESSION DETECTOR rather than a fixer: the collapse still folds a
# singular so one stray cell cannot skew the graph, but the hygiene pass reports
# it and main() exits non-zero. That is the whole point — a singular/plural
# split does not error on its own, it just quietly renders one system as two.
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
    "Item Pickup": "Loot", "Loot Use": "Loot",
    "Card Use": "Cards", "Pill Use": "Pills", "Scroll Use": "Scrolls",
    "Wand Use": "Wands", "Item Use": "Items",
    "Potion Quaff": "Potions", "Potion Throw": "Potions",
    "Bomb Use": "Bombs", "Object Use": "Objects",
    # Gold moved out of Stats into its own system with the ability rows — named
    # `Economy` off the review, because `Resource` was already a Node Type and
    # the root of the Groups tree. The two triggers that SPEND gold move with
    # it, or the new system is a sink.
    "Gold Use": "Economy", "Shop Purchase": "Economy",
    "Combat Start": "Enemies", "Combat End": "Enemies", "Enemy Defeat": "Enemies",
    "Damage Taken": "Enemies", "Enemy Spawn": "Enemies", "Enemy Movement": "Enemies",
    "Health Lost": "Health", "On Level Up": "Goals", "On Transmute Gain": "Stats",
    "Game Completion": "Goals", "Game Loss": "Goals",
    "Passive": None,
    # Added with the 30 Enemy Ability rows, and renamed off the §6A review.
    "Enemy Passive": "Enemies",  # true while it stands — an aura
    "Enemy Turn": "Enemies",     # it spends its turn on this (Enemy Clog folded in)
    "Enemy Attack": "Enemies",   # its swing landed
    # Two exceptions, and they are what stop Statuses and Shields being sinks.
    # Predatory Scent is gated on the PLAYER carrying an unmet status goal, so a
    # status fires it; Shield Absorption is the shield eating a hit, so the
    # shield fires it.
    "On Player Debuff": "Statuses",
    "Shield Absorb": "Shields",
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
    rows, good_dir_rows, groups = [], {}, []
    for n, raw in enumerate(grid[1:], start=2):
        cells = {}
        for i, v in enumerate(raw):
            if i < 26 and v not in ("", None):
                cells[chr(ord("A") + i)] = str(v)
        if cells.get("U"):
            # Collect EVERY row, not just the last. A repeated key silently
            # overwrote its earlier entry, which is how `Loot Amount` sat in the
            # table twice — Up on U29 and Down on U58 — with the reader's
            # iteration order quietly deciding the colour of every loot arrow.
            good_dir_rows.setdefault(cells["U"].strip(), []).append(
                (n, (cells.get("V") or "").strip()))
        if cells.get("W"):
            groups.append((n, cells["W"].strip()))
        if cells.get("A"):
            rows.append(Row(n, cells, header))
    good_dir = {k: v[-1][1] for k, v in good_dir_rows.items()}
    return rows, good_dir, good_dir_rows, groups, grid


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

    rows, good_dir, good_dir_rows, groups, grid = load()
    edges, uncoloured, unknown_triggers = build(rows, good_dir)
    arrows = sum(len(r.edges) for r in rows)
    # Faults that are silently wrong rather than loudly wrong: they produce a
    # plausible graph with the wrong shape. Each one makes the exit non-zero.
    errors = 0

    print(f"{len(rows)} node rows, {arrows} arrows, {len(good_dir)} Good Direction entries")
    print(f"node types: {dict(Counter(r.type for r in rows))}\n")

    print("== 1. hygiene ==")
    if uncoloured:
        errors += len(uncoloured)
        print(f"  {len(uncoloured)} arrow(s) CANNOT BE COLOURED (no Good Direction):")
        for name, system, sub in uncoloured:
            print(f"     {name} -> {system} . {sub}")
    else:
        print("  every arrow has a Good Direction")

    used_subs = {sub for r in rows for _, sub, _, _ in r.edges if sub}
    contradictory = {k: v for k, v in good_dir_rows.items()
                     if len({d for _, d in v}) > 1}
    if contradictory:
        errors += len(contradictory)
        print(f"  {len(contradictory)} Good Direction key(s) listed TWICE with "
              "different directions — the colour of every arrow into them is "
              "decided by iteration order:")
        for k, v in sorted(contradictory.items()):
            print("     %s: %s" % (k, ", ".join("U%d=%s" % (n, d) for n, d in v)))

    stale = sorted(k for k in good_dir if k not in used_subs)
    if stale:
        print(f"  {len(stale)} Good Direction entr(ies) no row uses: {', '.join(stale)}")

    systems = {s for r in rows for s, _, _, _ in r.edges}
    collisions = sorted(s for s in systems if s in CANON and CANON[s] in systems)
    if collisions:
        errors += len(collisions)
        print("  singular/plural collisions in the System column: "
              + ", ".join(f"{s}/{CANON[s]}" for s in collisions))

    dirs = Counter(d for r in rows for _, _, _, d in r.edges)
    odd = {d: n for d, n in dirs.items() if d not in ("Up", "Down")}
    if odd:
        errors += len(odd)
        print(f"  Dir values outside Up/Down: {odd}")

    multi = defaultdict(set)
    for r in rows:
        for system, sub, _, _ in r.edges:
            if sub:
                multi[sub].add(system)
    split_subs = {k: sorted(v) for k, v in multi.items() if len(v) > 1}
    if split_subs:
        errors += len(split_subs)
        print("  subsystem filed under more than one system:")
        for k, v in sorted(split_subs.items()):
            print(f"     {k}: {' / '.join(v)}")

    if unknown_triggers:
        errors += len(unknown_triggers)
        print(f"  triggers with no emitting system in EMITTED_BY: {dict(unknown_triggers)}")

    # Leading/trailing space is the nastiest fault on this sheet because it can
    # be INVISIBLY CORRECT: `Teleport Start Game ` carries a trailing space in
    # both the arrow (E3) and the Good Dir lookup (U50), so the join works — and
    # tidying up either one alone silently uncolours the arrow. Every other check
    # here strips before comparing (Row and load() both do), which is why this one
    # reads the raw grid instead.
    headings = [str(h).strip() for h in grid[0]]
    padded = []
    for r, raw in enumerate(grid[1:], start=2):
        for i, value in enumerate(raw):
            text = str(value)
            if text and text != text.strip():
                label = headings[i] if i < len(headings) and headings[i] else "?"
                padded.append(("%s%d" % (col_name(i), r), label, text))
    if padded:
        errors += len(padded)
        print(f"  {len(padded)} cell(s) with leading/trailing whitespace — "
              "these join by luck, and tidying one side alone breaks the join:")
        for ref, label, value in padded:
            print(f"     {ref} ({label}): {value!r}")

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
        errors += len(tangled)
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

    if errors:
        print(f"\n{errors} fault(s) that would silently misshape the graph — "
              "see docs/systems-graph.md §6")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

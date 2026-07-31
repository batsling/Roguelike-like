#!/usr/bin/env python3
"""
Compare the hand-drawn draw.io map against tools/Roguelikes.xlsx.

The giant map (tools/Roguelikes.drawio6.svg) and the spreadsheet are maintained
by hand and drift apart in BOTH directions: games get drawn on the map before
they reach the sheet, and games get added to the sheet without being drawn. This
script reports that drift so the two can be reconciled.

Reads either a draw.io-exported .svg (the XML model is embedded in the `content`
attribute) or a raw .drawio / .xml file.

Usage:
    python3 tools/check_map_sync.py                        # uses the checked-in svg
    python3 tools/check_map_sync.py path/to/Roguelikes.svg # a newer export
    python3 tools/check_map_sync.py --full                 # list every entry

What it checks:
  * games on the map but not in the `games` sheet, and vice versa
  * connections on the map but not in the `connections` sheet, and vice versa
  * each node's Y position against the sheet's Year column (the map's Y axis is
    a chronological scale — see the year labels running down the left edge)
  * the three edge types the map draws, by stroke colour

Edge types on the map (per its own legend):
    default stroke  -> "Inspired / Was Iterated Upon By"   (plain influence)
    #0000FF blue    -> "Sequel / Same Devs & Inspired"     (Dev/Series Relation)
    #C8C8C8 grey    -> "Neither creators knew about the other"
The grey ones are explicitly NOT influence and must never reach the
`connections` sheet — RunGraph would treat them as traversable edges.
"""

import argparse
import collections
import html
import os
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_SVG = os.path.join(SCRIPT_DIR, "Roguelikes.drawio6.svg")
XLSX_PATH = os.path.join(SCRIPT_DIR, "Roguelikes.xlsx")

BLUE = "#0000FF"
GREY = "#C8C8C8"
KIND_DEV = "dev/series"
KIND_CONVERGENT = "convergent"
KIND_INFLUENCE = "influence"

# A node whose Y implies a year this far from the sheet's Year is reported.
YEAR_TOLERANCE = 0.75


# --------------------------------------------------------------------------
# draw.io parsing
# --------------------------------------------------------------------------

def load_model(path: str) -> ET.Element:
    """Return the mxGraphModel root for a .svg export or a raw .drawio file."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    if raw.lstrip().startswith("<?xml") and "<mxfile" in raw[:4000]:
        return ET.fromstring(raw)
    marker = ' content="'
    start = raw.find(marker)
    if start < 0:
        # A .drawio file is already the model.
        return ET.fromstring(raw)
    end = raw.find('">', start)
    # Exactly one unescape: attribute values legitimately contain escaped HTML
    # (labels like "<font>Rogue</font>"), and unescaping twice corrupts them.
    return ET.fromstring(html.unescape(raw[start + len(marker):end]))


def strip_markup(value: str) -> str:
    if not value:
        return ""
    value = re.sub(r"<br[^>]*>", " ", value)
    value = re.sub(r"<[^>]+>", "", value)
    return re.sub(r"\s+", " ", html.unescape(value)).strip()


def norm(name: str) -> str:
    """Match key: accent-folded, article-stripped, alphanumerics only."""
    name = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    name = re.sub(r"\b(the|a|an)\b", "", name.lower())
    return re.sub(r"[^a-z0-9]+", "", name)


def edge_kind(style: str) -> str:
    match = re.search(r"strokeColor=(#[0-9A-Fa-f]{6})", style or "")
    colour = match.group(1).upper() if match else ""
    if colour == BLUE:
        return KIND_DEV
    if colour == GREY:
        return KIND_CONVERGENT
    return KIND_INFLUENCE


def parse_map(path: str) -> dict:
    root = load_model(path)
    cells = root.findall(".//mxCell")

    labels, nodes, year_axis = {}, {}, []
    for cell in cells:
        if cell.get("vertex") != "1":
            continue
        label = strip_markup(cell.get("value"))
        if not label:
            continue
        labels[cell.get("id")] = label
        geom = cell.find("mxGeometry")
        if geom is None:
            continue
        try:
            x, y = float(geom.get("x") or 0), float(geom.get("y") or 0)
        except ValueError:
            continue
        if re.fullmatch(r"(19|20)\d{2}", label):
            year_axis.append((y, int(label)))
        else:
            nodes[cell.get("id")] = {"label": label, "x": x, "y": y}

    edges = []
    for cell in cells:
        if cell.get("edge") != "1":
            continue
        edges.append({
            "kind": edge_kind(cell.get("style")),
            "source": labels.get(cell.get("source")),
            "target": labels.get(cell.get("target")),
        })
    return {"nodes": nodes, "edges": edges, "year_axis": year_axis}


def fit_year_axis(year_axis):
    """Least-squares y -> year over the map's year-label column."""
    if len(year_axis) < 3:
        return None
    ys = [p[0] for p in year_axis]
    yrs = [p[1] for p in year_axis]
    n = len(ys)
    my, mr = sum(ys) / n, sum(yrs) / n
    denom = sum((v - my) ** 2 for v in ys)
    if denom == 0:
        return None
    slope = sum((ys[i] - my) * (yrs[i] - mr) for i in range(n)) / denom
    return slope, mr - slope * my


# --------------------------------------------------------------------------
# spreadsheet
# --------------------------------------------------------------------------

def load_sheet(path: str) -> dict:
    try:
        import openpyxl
    except ImportError:
        sys.exit("openpyxl is required:  pip install openpyxl")
    book = openpyxl.load_workbook(path, read_only=True, data_only=False)

    games = {}
    rows = book["games"].iter_rows(values_only=True)
    next(rows)
    for row in rows:
        if not row or not row[0]:
            continue
        name = str(row[0]).strip()
        year = row[1] if isinstance(row[1], int) else None
        games[norm(name)] = {"name": name, "year": year}

    connections, dev_flags, sourced, total = {}, 0, 0, 0
    rows = book["connections"].iter_rows(values_only=True)
    next(rows)
    for row in rows:
        if not row or not row[0] or not row[1]:
            continue
        total += 1
        a, b = str(row[0]).strip(), str(row[1]).strip()
        relation = str(row[3]).strip().lower() if row[3] is not None else ""
        if relation == "yes":
            dev_flags += 1
        if row[4]:
            sourced += 1
        connections[frozenset((norm(a), norm(b)))] = {
            "a": a, "b": b, "dev": relation == "yes", "source": bool(row[4]),
        }
    return {"games": games, "connections": connections,
            "dev_flags": dev_flags, "sourced": sourced, "total": total}


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------

def head(title):
    print("\n" + title)
    print("-" * len(title))


def listing(items, full, limit=15):
    items = sorted(items)
    for item in items[:len(items) if full else limit]:
        print("    %s" % item)
    if not full and len(items) > limit:
        print("    ... and %d more (--full to list)" % (len(items) - limit))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("svg", nargs="?", default=DEFAULT_SVG,
                    help="draw.io .svg export or .drawio file (default: the checked-in map)")
    ap.add_argument("--xlsx", default=XLSX_PATH)
    ap.add_argument("--full", action="store_true", help="list every entry, not just a sample")
    args = ap.parse_args()

    if not os.path.exists(args.svg):
        sys.exit("no such map file: %s" % args.svg)
    dmap = parse_map(args.svg)
    sheet = load_sheet(args.xlsx)

    print("map   : %s" % os.path.relpath(args.svg, PROJECT_ROOT))
    print("sheet : %s" % os.path.relpath(args.xlsx, PROJECT_ROOT))
    print("\n%d nodes and %d edges on the map | %d games and %d connections in the sheet"
          % (len(dmap["nodes"]), len(dmap["edges"]), len(sheet["games"]), len(sheet["connections"])))

    # ---- games ----
    map_games = {norm(n["label"]): n for n in dmap["nodes"].values()}
    # Legend / annotation text boxes are vertices too; they simply won't match.
    on_map_only = {n["label"] for k, n in map_games.items() if k not in sheet["games"]}
    in_sheet_only = {g["name"] for k, g in sheet["games"].items() if k not in map_games}
    matched = [(k, n) for k, n in map_games.items() if k in sheet["games"]]

    head("GAMES")
    print("  matched by name          : %d" % len(matched))
    print("  on the map, not in sheet : %d   (includes legend/annotation text boxes)" % len(on_map_only))
    listing(on_map_only, args.full)
    print("  in sheet, not on the map : %d" % len(in_sheet_only))
    listing(in_sheet_only, args.full)

    # ---- year axis ----
    fit = fit_year_axis(dmap["year_axis"])
    head("YEAR AXIS")
    if not fit:
        print("  no year-label column found — skipping the chronology check")
    else:
        slope, intercept = fit
        print("  %d year labels, %.0f px per year, spanning %d-%d"
              % (len(dmap["year_axis"]), 1 / slope if slope else 0,
                 min(y for _, y in dmap["year_axis"]), max(y for _, y in dmap["year_axis"])))
        off = []
        for key, node in matched:
            year = sheet["games"][key]["year"]
            if not year:
                continue
            implied = slope * node["y"] + intercept
            if abs(implied - year) > YEAR_TOLERANCE:
                off.append("%-44s drawn at ~%d, sheet says %d"
                           % (node["label"][:42], round(implied), year))
        print("  nodes whose Y disagrees with the sheet's Year: %d" % len(off))
        listing(off, args.full)

    # ---- edges ----
    head("CONNECTIONS")
    counts = collections.Counter(e["kind"] for e in dmap["edges"])
    print("  on the map by type: influence %d | dev/series %d | convergent %d"
          % (counts[KIND_INFLUENCE], counts[KIND_DEV], counts[KIND_CONVERGENT]))
    print("  in the sheet      : %d total, %d flagged Dev/Series, %d with a Source (%.0f%%)"
          % (sheet["total"], sheet["dev_flags"], sheet["sourced"],
             100.0 * sheet["sourced"] / max(1, sheet["total"])))

    unresolved = collections.Counter()
    seen, map_only, leaked = set(), [], []
    for e in dmap["edges"]:
        if not e["source"] or not e["target"]:
            unresolved[e["kind"]] += 1
            continue
        key = frozenset((norm(e["source"]), norm(e["target"])))
        if e["source"] == e["target"]:
            map_only.append("[self-loop] %s" % e["source"])
            continue
        seen.add(key)
        if e["kind"] == KIND_CONVERGENT:
            if key in sheet["connections"]:
                leaked.append("%s  ~  %s" % (e["source"], e["target"]))
        elif key not in sheet["connections"]:
            map_only.append("[%s] %s -> %s" % (e["kind"], e["source"], e["target"]))

    if unresolved:
        print("  edges drawn without attached endpoints (free connectors): %s"
              % ", ".join("%s %d" % (k, v) for k, v in sorted(unresolved.items())))
    print("\n  drawn on the map, missing from the sheet: %d" % len(map_only))
    listing(map_only, args.full)

    sheet_only = [
        "%s -> %s" % (v["a"], v["b"])
        for k, v in sheet["connections"].items() if k not in seen
    ]
    print("  in the sheet, not drawn on the map: %d" % len(sheet_only))
    listing(sheet_only, args.full)

    head("INTEGRITY")
    if leaked:
        print("  !! %d 'neither creators knew about the other' link(s) are in the" % len(leaked))
        print("     connections sheet. RunGraph will treat these as traversable")
        print("     influence edges. Remove them from the sheet:")
        listing(leaked, True)
    else:
        print("  OK  no 'convergent evolution' links have leaked into the sheet")

    dropped = sheet["dev_flags"], sheet["sourced"]
    print("  note: the sheet's Dev/Series Relation (%d rows) and Source (%d rows)"
          % dropped)
    print("        columns are not carried into GameData by import-games-godot.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

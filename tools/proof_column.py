#!/usr/bin/env python3
"""Fill the `Proof` and `Needs Proof` columns on the `connections` sheet.

The game reads a connection's proof off disk, as
`images2.0/proof/<influencer id>---<influenced id>.png` (or `.ogv` for a clip, see
tools/convert_proof_videos.py), so the sheet on its own never said which rows
had one. This writes two columns:

  F  Proof        the file name that row's proof has or would have, without the
                  extension (`slay_the_spire---tic_tactic`), on EVERY row whose
                  two games resolve, so a new proof can be saved under a name
                  copied straight out of the cell. Rows whose Source is the SAME
                  video or podcast episode into the same game (a developer naming
                  five influences in one interview) share ONE name, the
                  influencers joined by a hyphen
                  (`boneraiser_minions-necrosmith---be_my_horde`): one clip
                  proves them all, rather than one copy each. A row that already
                  has a proof shows that file's name, whatever it is.
  G  Needs Proof  `Yes` when the row has no proof in the folder and isn't a
                  Dev/Series Relation row; `No` otherwise. Dev/Series rows never
                  need one (the relation is the source), though one can be added
                  anyway. Filtering G for `Yes` gives the influence rows of
                  `docs/proof-missing.md` (which lists Dev/Series rows too).

Both columns are a VIEW of the folder, not an input: nothing reads them back
(`import-games-godot.py` stops at Source, column E), so typing into them does
nothing and the next run overwrites them. Re-run after adding proofs:

    python3 tools/proof_column.py           # rewrite the columns
    python3 tools/proof_column.py --check   # exit 1 if they are out of date

A row whose name doesn't resolve to a game in data/games/ is left blank in both
and reported (the same names `import-games-godot.py` skips).

Through `_xlsx_surgery.set_cells` rather than openpyxl, which drops the
workbook's charts, and rather than `write_grid`, which regenerates every cell:
only columns F and G are touched.
"""

import glob
import os
import re
import sys
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _proof_names as names  # noqa: E402
from _xlsx_surgery import Workbook  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
GAMES = os.path.join(ROOT, "data", "games")

SHEET = "connections"
HEADERS = ["Influencer", "Influencee", "Influencer Time", "Dev/Series Relation",
           "Source", "Proof", "Needs Proof"]
COL, NEED_COL = "F", "G"
WIDTH, NEED_WIDTH = 60, 13


def _game_ids():
    """display_name -> id, exact and lower-cased, the way the importer resolves."""
    exact, lower = {}, {}
    for path in glob.glob(os.path.join(GAMES, "*.tres")):
        with open(path, encoding="utf-8") as f:
            m = re.search(r'^display_name = "((?:[^"\\]|\\.)*)"', f.read(), re.M)
        if not m:
            continue
        name = m.group(1).replace('\\"', '"').replace("\\\\", "\\")
        gid = os.path.splitext(os.path.basename(path))[0]
        exact[name] = gid
        lower.setdefault(name.lower(), gid)
    return exact, lower


def clip_source(url):
    """The video or podcast episode a Source link points at, or None for any
    other link. YouTube's many link shapes and Spotify's two paths to one episode
    come out the same; a YouTube start time (`t=`) is part of it, since two
    moments of one video are two clips."""
    p = urlparse(str(url or "").strip())
    host = p.netloc.lower()
    for prefix in ("www.", "m."):
        host = host[len(prefix):] if host.startswith(prefix) else host
    query = parse_qs(p.query)
    if host == "youtu.be":
        video = p.path.strip("/").split("/")[0]
    elif host.endswith("youtube.com"):
        m = re.match(r"/(?:shorts|live|embed)/([^/?#]+)", p.path)
        video = query.get("v", [""])[0] if p.path == "/watch" else (m.group(1) if m else "")
    elif host.endswith("spotify.com"):
        m = re.search(r"/episodes?/([^/?#]+)", p.path)
        return ("spotify", m.group(1)) if m else None
    else:
        return None
    return ("youtube", video, query.get("t", [""])[0]) if video else None


def main():
    check = "--check" in sys.argv[1:]
    exact, lower = _game_ids()
    # A screenshot, or a clip (the .ogv the game plays, or an upload still
    # waiting for tools/convert_proof_videos.py), by the connections its name
    # says it proves.
    proofs = names.proofs((".png", ".ogv", ".mp4"))

    def resolve(name):
        name = str(name or "").strip()
        return exact.get(name) or lower.get(name.lower())

    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        header = [str(c).strip() for c in grid[0]]
        if header[:5] != HEADERS[:5]:
            raise SystemExit("connections headers are %r, expected %r — the sheet's "
                             "shape moved; update this script" % (header, HEADERS[:5]))

        edits, unresolved, have, need = {}, set(), 0, 0
        for col, title, i in ((COL, "Proof", 5), (NEED_COL, "Needs Proof", 6)):
            if (header[i] if len(header) > i else "") != title:
                edits["%s1" % col] = title
        rows = []
        for row in grid[1:]:
            row = list(row) + [""] * (7 - len(row))
            a, b = str(row[0] or "").strip(), str(row[1] or "").strip()
            pair = None
            if a and b:
                a_id, b_id = resolve(a), resolve(b)
                if a_id is None or b_id is None:
                    unresolved.add(a if a_id is None else b)
                else:
                    pair = (a_id, b_id)
            rows.append((row, pair))
        # The connections still waiting for a proof, by the clip that would prove
        # them: one clip for every row sharing a video into the same game.
        clips = {}
        for row, pair in rows:
            if pair and pair not in proofs and clip_source(row[4]):
                clips.setdefault((clip_source(row[4]), pair[1]), set()).add(pair[0])

        for r, (row, pair) in enumerate(rows, start=2):
            name = needs = ""
            if pair:
                group = clips.get((clip_source(row[4]), pair[1]), ()) if pair not in proofs else ()
                shared = names.name(group, pair[1]) if len(group) > 1 else ""
                if pair in proofs:
                    name = os.path.splitext(proofs[pair])[0]
                elif shared and len(shared) <= names.MAX_STEM:
                    name = shared
                else:
                    name = names.name([pair[0]], pair[1])
                dev = bool(str(row[3] or "").strip())
                if pair in proofs:
                    have += 1
                needs = "No" if dev or pair in proofs else "Yes"
                need += needs == "Yes"
            for col, i, want in ((COL, 5, name), (NEED_COL, 6, needs)):
                if str(row[i] or "").strip() != want:
                    edits["%s%d" % (col, r)] = want

        total = sum(1 for row in grid[1:] if str(row[0] or "").strip())
        print("connections: %d of %d rows have a proof, %d need one; %d cell(s) %s"
              % (have, total, need, len(edits), "out of date" if check else "written"))
        for name in sorted(unresolved):
            print("  not a game in data/games/: %r" % name)

        if check:
            wb._dirty.clear()
            raise SystemExit(1 if edits else 0)
        if not edits:
            return

        wb.set_cells(SHEET, edits)
        last = len(grid)
        wb.grow_table(SHEET, HEADERS, "%s%d" % (NEED_COL, last))
        # Give the columns a readable width; E is 189 wide and F and G would
        # otherwise open at the sheet default of ~9.
        part, _ = wb.sheet_parts(SHEET)
        xml = wb._dirty[part].decode("utf-8")
        for n, width in ((6, WIDTH), (7, NEED_WIDTH)):
            if '<col min="%d"' % n not in xml:
                xml = xml.replace("</cols>", '<col min="%d" max="%d" width="%d" customWidth="1"/></cols>'
                                  % (n, n, width), 1)
        xml = re.sub(r'spans="1:[56]"', 'spans="1:7"', xml)
        wb._dirty[part] = xml.encode("utf-8")

if __name__ == "__main__":
    main()

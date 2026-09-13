#!/usr/bin/env python3
"""`docs/goal-candidates.csv` and the workbook's enemy sheets should agree.

WHY THIS EXISTS. The candidate file is a paste QUEUE for the `enemies` and
`bosses` sheets of tools/Roguelikes.xlsx, and every rule it has to keep is one
that nothing checks at paste time: a Damage that does not match the tier is a
row that ships wrong, a `File` that collides with a shipped one silently steals
its picture, a duplicate `Goal` is two enemies asking for the same thing on the
same board, and a `Game` spelled a way the catalog does not spell it is a
`source_game` that matches no game in `data/games/`. The audit that produced the
file checked all of this by hand and said so in prose; this is the same audit as
a script, so the NEXT pass does not have to take the last one's word for it.

It checks the file against three things:

  1. ITSELF        — column order, the enum columns, the Health/Damage
                     conventions, the Size grammar (parsed with the REAL
                     generator, not a copy of it), and no duplicate Name, File
                     or Goal.
  2. THE SHEET     — every row is either SHIPPED or PENDING, and they get
                     opposite checks. A shipped row (its id is on the sheet)
                     must still match its sheet row cell for cell, which is what
                     catches the file and the workbook drifting apart in either
                     direction. A pending row must not collide with anything
                     already live, on Name, File, Goal or slugified id.
  3. data/games/   — every `Game` names a game the catalog actually has, and of
                     the `Type` the row claims.

  python3 tools/check_goal_candidates.py           # report
  python3 tools/check_goal_candidates.py --stats   # + the distribution tables
                                                     the doc quotes

Exit 0 = clean, 1 = findings. A finding is a row to fix, not a rule to relax:
the one deliberate exception (`Health` is 1 everywhere, so a 0 or a 2 is a typo
rather than a design choice) is spelled out where it is checked.
"""

import argparse
import collections
import csv
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_goal_enemy_tres as gen  # noqa: E402  (slugify + the Size grammar)

import openpyxl  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
CSV_PATH = os.path.join(ROOT, "docs", "goal-candidates.csv")
XLSX_PATH = os.path.join(ROOT, "tools", "Roguelikes.xlsx")
GAMES_DIR = os.path.join(ROOT, "data", "games")

COLUMNS = ["Sheet", "Name", "Type", "Difficulty", "Size", "Game", "Health",
           "Damage", "Goal Type", "Goal", "Ability", "File", "Tag", "Phases",
           "Confidence", "Why this pairing"]

SHEETS = {"enemies", "bosses"}
TYPES = {"Action", "Deckbuilder", "Strategy", "Traditional"}
DIFFICULTIES = ["1-Low", "2-Medium", "3-High", "4-Insane"]
GOAL_TYPES = {"Bounty", "Feat", "Fetch", "Restriction", "Discovery"}
# Damage tracks the tier: the difficulty index for an ordinary goal-enemy, and
# the boss band for a boss. Both mappings are the live sheet's, not this file's.
ENEMY_DAMAGE = {"1-Low": 1, "2-Medium": 2, "3-High": 3, "4-Insane": 4}
BOSS_DAMAGE = {"1-Low": 3, "2-Medium": 5, "3-High": 7, "4-Insane": 9}


def norm(s: str) -> str:
    """A goal compared the way a reader compares two goals: case and spacing."""
    return re.sub(r"\s+", " ", (s or "").strip().lower()).rstrip(".")


def sheet_rows(wb, name):
    rows = list(wb[name].iter_rows(values_only=True))
    hdr = [str(c).strip() if c is not None else "" for c in rows[0]]
    for r in rows[1:]:
        if r and r[0]:
            yield {hdr[i]: r[i] for i in range(len(hdr))}


# GameData.GameType, in the enum's own order — `type = 2` in a .tres is a
# Deckbuilder. The candidate's Type column has to agree with it: a goal is rolled
# from the pool of the game TYPE it is filed under, so a Caves of Qud body typed
# Action would be offered on games its goal was never written for.
GAME_TYPES = ["Action", "Strategy", "Deckbuilder", "Traditional"]


def catalog_games():
    """{display_name: Type} over data/games/, which is what `Game` has to spell."""
    out = {}
    for path in glob.glob(os.path.join(GAMES_DIR, "*.tres")):
        name, typ = None, 1
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("display_name = "):
                    name = line.split("=", 1)[1].strip().strip('"')
                elif line.startswith("type = "):
                    typ = int(line.split("=", 1)[1].strip())
        if name:
            out[name] = GAME_TYPES[typ] if 0 <= typ < len(GAME_TYPES) else "?"
    return out


def pascal(name: str) -> str:
    """The File the sheet spells for a Name: every word capitalised, run together.

    "Chubs 'n' Nubs" -> ChubsNNubs, "Mi-go" -> MiGo, "Xak'olchir" -> XakOlchir.
    Parentheses survive because the live sheet's `SpikeSlime(L)` keeps them.
    """
    parts = re.split(r"[^A-Za-z0-9()]+", name)
    return "".join(p[:1].upper() + p[1:] for p in parts if p)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stats", action="store_true",
                    help="also print the distribution tables the doc quotes")
    args = ap.parse_args()

    with open(CSV_PATH, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames
        rows = list(reader)

    bad = []

    def flag(row_no, name, msg):
        bad.append("  line %-4d %-24s %s" % (row_no, name[:24], msg))

    if header != COLUMNS:
        bad.append("  header is %r, expected %r" % (header, COLUMNS))
        print("\n".join(bad))
        return 1

    wb = openpyxl.load_workbook(XLSX_PATH, read_only=True, data_only=True)
    # A candidate row is either SHIPPED (its id is on the sheet, put there by
    # tools/_candidates_to_sheet.py) or PENDING. The two get opposite checks:
    # a shipped row must still MATCH its sheet row cell for cell — that is what
    # catches the file and the workbook drifting apart, in either direction —
    # and a pending row must not collide with anything already live.
    live_rows = {}                                   # (sheet, id) -> sheet row
    live_names, live_files, live_goals, live_ids = {}, {}, {}, {}
    for sheet in ("enemies", "bosses"):
        for r in sheet_rows(wb, sheet):
            nm = str(r["Name"]).strip()
            live_rows[(sheet, gen.slugify(nm))] = r
            live_names[nm.lower()] = sheet
            live_ids[gen.slugify(nm)] = sheet
            if r.get("File"):
                for f in str(r["File"]).split(","):
                    live_files[f.strip().lower()] = sheet
            for g in str(r.get("Goal") or "").split("/"):
                if norm(g):
                    live_goals[norm(g)] = sheet
    games = catalog_games()
    # The columns a sheet actually has; `Phases` only on bosses, and the two
    # staging columns on neither.
    SHARED = ["Name", "Type", "Difficulty", "Size", "Game", "Health", "Damage",
              "Goal Type", "Goal", "Ability", "File", "Tag"]
    shipped = 0

    seen_name, seen_file, seen_goal, seen_id = {}, {}, {}, {}
    for i, row in enumerate(rows, start=2):
        name = (row["Name"] or "").strip()
        sheet = (row["Sheet"] or "").strip()
        if sheet not in SHEETS:
            flag(i, name, "Sheet %r is not enemies/bosses" % sheet)
        if (row["Type"] or "").strip() not in TYPES:
            flag(i, name, "Type %r" % row["Type"])
        diff = (row["Difficulty"] or "").strip()
        if diff not in DIFFICULTIES:
            flag(i, name, "Difficulty %r" % diff)
        if (row["Goal Type"] or "").strip() not in GOAL_TYPES:
            flag(i, name, "Goal Type %r" % row["Goal Type"])
        # Health is 1 on every live row, so anything else here is a typo rather
        # than a design decision — the sheet has no concept of a tougher body.
        if (row["Health"] or "").strip() != "1":
            flag(i, name, "Health %r (every live row is 1)" % row["Health"])
        if diff in DIFFICULTIES:
            want = (BOSS_DAMAGE if sheet == "bosses" else ENEMY_DAMAGE)[diff]
            if (row["Damage"] or "").strip() != str(want):
                flag(i, name, "Damage %r, expected %d for a %s %s"
                     % (row["Damage"], want, diff, sheet[:-1] if sheet else "?"))
        if not norm(row["Goal"]):
            flag(i, name, "empty Goal")
        if (row["Ability"] or "").strip() != "N/A":
            flag(i, name, "Ability %r — this file leaves abilities to their own pass"
                 % row["Ability"])
        if (row["Confidence"] or "").strip() not in ("ok", "?"):
            flag(i, name, "Confidence %r" % row["Confidence"])
        if not (row["Why this pairing"] or "").strip():
            flag(i, name, "no 'Why this pairing' note")
        if sheet == "enemies" and (row["Phases"] or "").strip():
            flag(i, name, "Phases is a bosses-only column")

        # Size has to parse with the generator's own grammar, and come back as
        # the box the row declared — a silent fallback to 1x1 is a Size that
        # means nothing.
        size = (row["Size"] or "").strip() or "1x1"
        m = re.match(r"^(\d+)x(\d+)(?:\s|$)", size)
        r_, c_, _mask = gen.parse_size(size, name)
        if not m or (r_, c_) != (int(m.group(1)), int(m.group(2))):
            flag(i, name, "Size %r does not parse to the box it declares" % size)

        f = (row["File"] or "").strip()
        if not f:
            flag(i, name, "no File")
        elif f != pascal(name):
            # A File is looked up in the art folder by name, so a stray one is how
            # a row ends up pointing at nothing. Deliberate ones exist (a picture
            # can be uploaded under a shorter name) — this says which they are.
            flag(i, name, "File %r, expected %r from the Name" % (f, pascal(name)))

        game = (row["Game"] or "").strip()
        if game not in games:
            flag(i, name, "Game %r is not a display_name in data/games/" % game)
        elif games[game] != (row["Type"] or "").strip():
            flag(i, name, "Type %s but %s is a %s game in the catalog"
                 % (row["Type"], game, games[game]))

        for key, seen, what in ((name.lower(), seen_name, "Name"),
                                (f.lower(), seen_file, "File"),
                                (norm(row["Goal"]), seen_goal, "Goal"),
                                (gen.slugify(name), seen_id, "id")):
            if key and key in seen:
                flag(i, name, "duplicate %s, first seen line %d" % (what, seen[key]))
            elif key:
                seen[key] = i
        live = live_rows.get((sheet, gen.slugify(name)))
        if live is not None:
            # SHIPPED: the sheet row and this row are the same row, so every
            # column the sheet has must still say what the file says. A
            # difference is drift, and which side is right is a question for
            # whoever made the edit — not something to guess at here.
            shipped += 1
            for col in SHARED:
                mine = (row.get(col) or "").strip()
                theirs = "" if live.get(col) is None else str(live[col]).strip()
                if mine != theirs:
                    flag(i, name, "%s: file says %r, the %s sheet says %r"
                         % (col, mine, sheet, theirs))
        else:
            # PENDING: nothing live may already be using this row's identity.
            for key, table, what in ((name.lower(), live_names, "Name"),
                                     (f.lower(), live_files, "File"),
                                     (norm(row["Goal"]), live_goals, "Goal"),
                                     (gen.slugify(name), live_ids, "id")):
                if key and key in table:
                    flag(i, name, "%s already taken on the %s sheet by another row"
                         % (what, table[key]))

    print("goal-candidates.csv: %d rows, %d games — %d shipped to the sheet, %d pending"
          % (len(rows), len({r["Game"] for r in rows}), shipped, len(rows) - shipped))
    if bad:
        print("\n%d finding(s):" % len(bad))
        print("\n".join(bad))
    else:
        print("ok — enums, Health/Damage, Size and File all hold; every shipped row "
              "still matches its sheet row cell for cell; every pending row is "
              "pasteable without a Name / File / Goal / id collision; and every "
              "Game names a real catalog entry of the right type")

    if args.stats:
        print("\nBy sheet: %s" % dict(collections.Counter(r["Sheet"] for r in rows)))
        print("By type:  %s" % dict(collections.Counter(r["Type"] for r in rows)))
        tier = collections.Counter(r["Difficulty"] for r in rows)
        total = sum(tier.values()) or 1
        print("By tier:  %s" % "  ".join(
            "%s %d (%d%%)" % (d, tier[d], round(100 * tier[d] / total))
            for d in DIFFICULTIES))
        print("Unconfirmed (Confidence '?'): %d"
              % sum(1 for r in rows if (r["Confidence"] or "").strip() == "?"))
        per_game = collections.Counter(r["Game"] for r in rows)
        worst = [g for g, n in per_game.items()
                 if sum(1 for r in rows if r["Game"] == g and r["Sheet"] == "bosses") > 3]
        print("Games over the 3-boss budget: %s" % (worst or "none"))

    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())

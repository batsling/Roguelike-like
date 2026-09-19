#!/usr/bin/env python3
"""Push the workbook's `goals` sheet OUT into the sheets that own each goal.

WHY THIS EXISTS, AND WHY IT RUNS THE OTHER WAY FROM ITS PREDECESSOR.
`generate_goals_sheet.py` built `goals` as a read-only VIEW: six owning sheets
in five column shapes, gathered into one place so the roster could be counted
and compared. Its docstring said, in caps, that anything typed into the view was
lost on the next run.

That has now been inverted deliberately. `goals` is the SOURCE: goal wording is
authored there, in one list, where duplicates and near-duplicates are visible
side by side — which is exactly how the pass that produced the current sheet
could rewrite 34 goals into a consistent voice ("Do not use magic" ->
"Beat a game without using magic") and give the counting goals honest numbers
("Defeat 5+ bugs" -> "Defeat 3 bugs", Count 3). You cannot do that pass in six
sheets at once, which is why the view existed and why it earned the promotion.

So the rule is now the reverse of the old one:

    EDIT `goals`. EVERY OTHER SHEET'S GOAL CELLS ARE WRITTEN FROM IT.
    Anything typed into an owner sheet's goal column is lost on the next run.

The owner sheets remain the GENERATORS' input — nothing under tools/ had to
learn a new place to read from, and `check_data_sync.py` keeps working unchanged
— so this script is the one seam between the authored list and the pipeline that
already exists.

    python3 tools/apply_goals_sheet.py           # write the owner sheets
    python3 tools/apply_goals_sheet.py --check   # report drift, write nothing
    python3 tools/apply_goals_sheet.py --dry-run # print the edits it would make

Exit 0 = clean/written, 1 = findings (--check) or a sheet that cannot be pushed.

WHAT GOES WHERE. Five owner sheets, and they do not all take the same fields,
because the goal fields only travel as far as something downstream reads them:

  enemies, bosses  Goal, Goal Type, Difficulty, AND the two new columns `Ticked`
                   and `Count`. These are the bodies that stand on the board, so
                   they are the rows where Ticked decides which half of the
                   checklist a goal lives in and Count turns a tick box into a
                   counter. Both columns are created by this script the first
                   time it runs (and the sheet's table widened to match).
  characters       `Level Up` only. A level-up is already a winning-run row in
                   ReportChecklist, so `game beaten` is what it always was and a
                   column saying so would be a column nothing reads.
  curses           `Condition` only, for the same reason.
  statuses         the goal spliced back into the `On Player` prose (see
                   `status_prose_with`). A status MODIFIES the goal you carry
                   rather than having one, so it has no tick row of its own.

Because those three carry no Ticked/Count column, authoring one there would be a
silent no-op. So it is a hard error instead: a character, curse or status row
that is not `game beaten`, or that carries a Count, stops the run and names
itself. Widen this script and the owner sheet together if that day comes.

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries eight charts that an
openpyxl load/save round-trip silently drops. See tools/_xlsx_surgery.py. Note
this uses `set_cells` rather than `write_grid` — `statuses` carries a formula
(the Speed row) and several of these sheets carry per-cell styling, and
`write_grid` regenerates every cell from values.
"""

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from _xlsx_surgery import Workbook, col_name  # noqa: E402

import openpyxl  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
XLSX = os.path.join(ROOT, "tools", "Roguelikes.xlsx")

SHEET = "goals"

# The `Owner Sheet` value -> the workbook sheet it names. `goals` says "enemy"
# where the workbook says "enemies", because a row reads as one thing.
OWNER_SHEETS = {
    "enemy": "enemies",
    "boss": "bosses",
    "character": "characters",
    "curse": "curses",
    "status": "statuses",
}

# The two values `Ticked` may take, and what each one means downstream:
#
#   any time      the goal can be ticked at any point while the game is in play,
#                 and the tick resolves on the spot (ReportChecklist's `Enemies`
#                 section). The overwhelming majority — 99 rows.
#   game beaten   the goal is only settled by finishing the real video game, so
#                 its tick lives in the review inside the "Completed Game"
#                 confirm, beside the status and level-up rows.
#
# There is no third value on purpose. The sheet briefly carried one `run`, which
# was a typo for `any time` (tools/_goals_ticked_run_fix.py).
ANY_TIME, GAME_BEATEN = "any time", "game beaten"
TICKED_VALUES = (ANY_TIME, GAME_BEATEN)

# A Count turns a tick box into a "+" counter that has to be pressed that many
# times (docs/games-first-redesign.md §7.7). 1 would be a counter that is already
# finished and 0 one that can never be, so the floor is 2 — and a goal with no
# number to count is simply blank, which is 127 of the 134 rows.
MIN_COUNT = 2

# A multi-phase boss authors its phases as a `/`-joined list in `Goal Type` and
# `Goal` — the shape `generate_goal_enemy_tres.py` already parses.
PHASE_SEP = "/"
PHASE_RE = re.compile(r"^phase\s+(\d+)\s+of\s+(\d+)$", re.I)

# The three columns this script ADDS to `enemies` and `bosses` if they are not
# there, in this order, after whatever the sheet already ends with.
NEW_COLUMNS = ["Ticked", "Count"]

# --- statuses: splicing a goal back into its prose -------------------------
#
# A status's `On Player` cell is a whole sentence with the consequence baked in:
#
#   Gain "You must beat a game while not healing intentionally or take 3 Damage."
#
# `goals` holds only the goal out of the middle of that, so pushing back means
# putting the new wording where the old wording was and leaving the wrapper, the
# "You must", the consequence and the full stop exactly as they were. These are
# the same three shapes the consequence takes that the view script read.
GAIN_WRAPPER = re.compile(r'^Gain\s+"(.*)"$', re.S)
LEADING_MUST = re.compile(r"^(You must\s+)", re.I)
CONSEQUENCE = [" or take ", ", Gain a ", ". This lasts for "]


class Finding(Exception):
    """A row that cannot be pushed. Named, never half-applied."""


def cell(row, i):
    if i is None or i >= len(row) or row[i] is None:
        return ""
    return str(row[i]).strip()


def read_sheet(wb, name):
    """(header list, [(row number, values)]) — row numbers are 1-based as Excel
    counts them, because they become cell references."""
    ws = wb[name]
    rows = list(ws.iter_rows(values_only=True))
    header = [str(h).strip() if h is not None else "" for h in rows[0]]
    out = []
    for n, row in enumerate(rows[1:], start=2):
        if not row or row[0] is None or str(row[0]).strip() == "":
            continue
        out.append((n, row))
    return header, out


def read_goals(wb):
    header, rows = read_sheet(wb, SHEET)
    idx = {h: i for i, h in enumerate(header)}
    for need in ("Goal", "Type", "Difficulty", "Owner Sheet", "Owner",
                 "Owner Detail", "Relation", "Ticked", "Count"):
        if need not in idx:
            raise Finding("`%s` has no `%s` column — the sheet's shape moved"
                          % (SHEET, need))
    out = []
    for n, row in rows:
        g = {h: cell(row, idx[h]) for h in idx}
        g["_row"] = n
        owner_sheet = g["Owner Sheet"]
        if owner_sheet not in OWNER_SHEETS:
            raise Finding("%s!%d: Owner Sheet %r is not one of %s"
                          % (SHEET, n, owner_sheet, ", ".join(sorted(OWNER_SHEETS))))
        if g["Ticked"] not in TICKED_VALUES:
            raise Finding("%s!%d (%s / %s): Ticked is %r — it must be %s"
                          % (SHEET, n, owner_sheet, g["Owner"], g["Ticked"],
                             " or ".join(repr(v) for v in TICKED_VALUES)))
        if g["Count"]:
            if not re.fullmatch(r"\d+", g["Count"]):
                raise Finding("%s!%d (%s / %s): Count is %r — a whole number or blank"
                              % (SHEET, n, owner_sheet, g["Owner"], g["Count"]))
            if int(g["Count"]) < MIN_COUNT:
                raise Finding(
                    "%s!%d (%s / %s): Count is %s. A counter goal counts to at "
                    "least %d — 1 is a goal that starts finished, 0 one that "
                    "never can. Leave it blank for a plain tick box."
                    % (SHEET, n, owner_sheet, g["Owner"], g["Count"], MIN_COUNT))
        out.append(g)
    return out


def phase_of(detail: str):
    """(phase number, phase count) out of an `Owner Detail`, or None."""
    m = PHASE_RE.match(detail.strip()) if detail else None
    return (int(m.group(1)), int(m.group(2))) if m else None


def group_by_owner(goals):
    """{(owner sheet, owner): [goal rows]}, phase rows sorted into phase order.

    The sheet is sorted by goal text, so Guillatina's three phases sit at 3, 1, 2
    — and the `/`-joined cell this writes is read positionally by the generator.
    Sorting here is what keeps phase 1 phase 1.
    """
    by = {}
    for g in goals:
        by.setdefault((g["Owner Sheet"], g["Owner"]), []).append(g)
    for key, rows in by.items():
        if len(rows) == 1:
            continue
        phases = [phase_of(r["Owner Detail"]) for r in rows]
        if any(p is None for p in phases):
            raise Finding(
                "%s / %s has %d goal rows but not all of them say which phase "
                "they are (`Owner Detail` reads `phase N of M`). Two goals on "
                "one owner with no phase to tell them apart cannot be written "
                "back." % (key[0], key[1], len(rows)))
        counts = {p[1] for p in phases}
        if len(counts) != 1 or sorted(p[0] for p in phases) != list(range(1, len(rows) + 1)):
            raise Finding(
                "%s / %s: phases are %s — they must be 1..N of the same N"
                % (key[0], key[1], ", ".join(r["Owner Detail"] for r in rows)))
        rows.sort(key=lambda r: phase_of(r["Owner Detail"])[0])
    return by


def one_value(rows, field, owner):
    """The single value of `field` across an owner's phases.

    Goal and Goal Type are per-phase and get `/`-joined. Difficulty, Ticked and
    Count are properties of the BODY — it stands on the board once, at one tier,
    ticking one way — so every phase has to agree and disagreement is a finding
    rather than a silently-dropped cell.
    """
    values = {r[field] for r in rows}
    if len(values) > 1:
        raise Finding(
            "%s / %s: phases disagree on %s (%s). It is one column on the owner "
            "sheet because it describes the body, not the phase — make the "
            "phases agree, or widen this script and the sheet together."
            % (owner[0], owner[1], field,
               ", ".join(sorted(repr(v) for v in values))))
    return rows[0][field]


def status_prose_with(prose: str, goal: str, name: str) -> str:
    """`prose` with its goal replaced by `goal`, everything else untouched."""
    m = GAIN_WRAPPER.match(prose.strip())
    if not m:
        raise Finding(
            'statuses / %s: `On Player` is not the `Gain "..."` shape this '
            "splices into:\n  %r\nTeach this script the new shape rather than "
            "letting it write a half-formed sentence." % (name, prose))
    text = m.group(1).strip()
    cuts = [c for c in (text.find(marker) for marker in CONSEQUENCE) if c > 0]
    head, tail = (text[:min(cuts)], text[min(cuts):]) if cuts else (text, "")
    must = LEADING_MUST.match(head)
    prefix = must.group(1) if must else ""
    # The full stop belongs to the sentence, not to the goal, so it is preserved
    # off the ORIGINAL head and re-hung on the new one.
    dot = "." if head.rstrip().endswith(".") else ""
    return 'Gain "%s%s%s%s"' % (prefix, goal, dot, tail)


# --- the per-sheet pushes ---------------------------------------------------

def edits_for_enemy_sheet(wb, sheet_name, owner_key, by_owner, header):
    """Cell edits for `enemies` / `bosses`, and the columns to add first."""
    idx = {h: i for i, h in enumerate(header)}
    for need in ("Goal", "Goal Type", "Difficulty"):
        if need not in idx:
            raise Finding("`%s` has no `%s` column" % (sheet_name, need))
    # The two new columns land at the end, in NEW_COLUMNS order, and only the
    # ones that are not there already — so a second run adds nothing.
    added = [c for c in NEW_COLUMNS if c not in idx]
    width = len(header)
    for i, name in enumerate(added):
        idx[name] = width + i
    _, rows = read_sheet(wb, sheet_name)

    edits = {}
    seen = set()
    for n, row in rows:
        owner = cell(row, 0)
        key = (owner_key, owner)
        if key not in by_owner:
            raise Finding(
                "%s!%d: %r has no row in `%s`. Every body's goal is authored "
                "there now — add it, or this sheet keeps a goal nothing owns."
                % (sheet_name, n, owner, SHEET))
        seen.add(key)
        goals = by_owner[key]
        want = {
            "Goal": PHASE_SEP.join(g["Goal"] for g in goals),
            "Goal Type": PHASE_SEP.join(g["Type"] for g in goals),
            "Difficulty": one_value(goals, "Difficulty", key),
            "Ticked": one_value(goals, "Ticked", key),
            "Count": one_value(goals, "Count", key),
        }
        # A boss's `Phases` has to agree with how many goal rows it has, or the
        # `/`-joined cell this writes is read into the wrong number of slots.
        if "Phases" in idx:
            phases = cell(row, idx["Phases"])
            authored = int(phases) if phases.isdigit() else 1
            if authored != len(goals):
                raise Finding(
                    "%s!%d (%s): the sheet says %d phase(s) but `%s` holds %d "
                    "goal row(s) for it."
                    % (sheet_name, n, owner, authored, SHEET, len(goals)))
        for field, value in want.items():
            ref = "%s%d" % (col_name(idx[field]), n)
            if cell(row, idx[field]) != value:
                edits[ref] = value
    missing = sorted(k[1] for k in by_owner if k[0] == owner_key and k not in seen)
    if missing:
        raise Finding("`%s` names %s under Owner Sheet %r, and `%s` has no such "
                      "row(s)." % (SHEET, ", ".join(missing), owner_key, sheet_name))
    # The header cells for whatever was added.
    for name in added:
        edits["%s1" % col_name(idx[name])] = name
    return edits, added, idx


def edits_for_simple_sheet(wb, sheet_name, owner_key, column, by_owner):
    """Cell edits for a sheet that takes the goal TEXT and nothing else.

    `characters` (`Level Up`) and `curses` (`Condition`). Neither carries a
    Ticked or a Count column, so a row that authors one would be authoring into
    a void — hence the check.
    """
    header, rows = read_sheet(wb, sheet_name)
    if column not in header:
        raise Finding("`%s` has no `%s` column" % (sheet_name, column))
    col = header.index(column)
    edits = {}
    seen = set()
    for n, row in rows:
        owner = cell(row, 0)
        key = (owner_key, owner)
        if key not in by_owner:
            raise Finding("%s!%d: %r has no row in `%s`."
                          % (sheet_name, n, owner, SHEET))
        seen.add(key)
        goals = by_owner[key]
        if len(goals) != 1:
            raise Finding("%s / %s has %d goal rows; this sheet holds one."
                          % (owner_key, owner, len(goals)))
        g = goals[0]
        _refuse_unreadable(sheet_name, owner_key, g)
        ref = "%s%d" % (col_name(col), n)
        if cell(row, col) != g["Goal"]:
            edits[ref] = g["Goal"]
    missing = sorted(k[1] for k in by_owner if k[0] == owner_key and k not in seen)
    if missing:
        raise Finding("`%s` names %s under Owner Sheet %r, and `%s` has no such "
                      "row(s)." % (SHEET, ", ".join(missing), owner_key, sheet_name))
    return edits


def edits_for_statuses(wb, by_owner):
    header, rows = read_sheet(wb, "statuses")
    if "On Player" not in header:
        raise Finding("`statuses` has no `On Player` column")
    col = header.index("On Player")
    edits = {}
    seen = set()
    for n, row in rows:
        owner = cell(row, 0)
        key = ("status", owner)
        if key not in by_owner:
            raise Finding("statuses!%d: %r has no row in `%s`." % (n, owner, SHEET))
        seen.add(key)
        g = by_owner[key][0]
        _refuse_unreadable("statuses", "status", g)
        prose = cell(row, col)
        want = status_prose_with(prose, g["Goal"], owner)
        if prose != want:
            edits["%s%d" % (col_name(col), n)] = want
    missing = sorted(k[1] for k in by_owner if k[0] == "status" and k not in seen)
    if missing:
        raise Finding("`%s` names %s under Owner Sheet 'status', and `statuses` "
                      "has no such row(s)." % (SHEET, ", ".join(missing)))
    return edits


def _refuse_unreadable(sheet_name, owner_key, g):
    """A Ticked/Count authored where nothing downstream can read it.

    Silence is the danger here: these three sheets have no column to put it in,
    so the value would be dropped on the way through and the goal would keep
    behaving the way it always did, with the sheet saying otherwise.
    """
    if g["Ticked"] != GAME_BEATEN:
        raise Finding(
            "%s!%d (%s / %s): Ticked is %r. `%s` has no Ticked column — a %s's "
            "goal is settled by the run being won and is already a winning-run "
            "row, so only %r can be honoured here. Widen this script and the "
            "sheet together to change that."
            % (SHEET, g["_row"], owner_key, g["Owner"], g["Ticked"], sheet_name,
               owner_key, GAME_BEATEN))
    if g["Count"]:
        raise Finding(
            "%s!%d (%s / %s): Count is %s. `%s` has no Count column, so this "
            "counter would never reach the game. Widen this script and the "
            "sheet together, or drop the number."
            % (SHEET, g["_row"], owner_key, g["Owner"], g["Count"], sheet_name))


# --- driver -----------------------------------------------------------------

def build_edits():
    """{sheet name: (edits, added columns, last row)} for the whole push."""
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    goals = read_goals(wb)
    by_owner = group_by_owner(goals)

    plan = {}
    for owner_key, sheet_name in (("enemy", "enemies"), ("boss", "bosses")):
        header, rows = read_sheet(wb, sheet_name)
        edits, added, _ = edits_for_enemy_sheet(
            wb, sheet_name, owner_key, by_owner, header)
        plan[sheet_name] = (edits, added, header + added,
                            max(n for n, _ in rows))
    for owner_key, sheet_name, column in (("character", "characters", "Level Up"),
                                          ("curse", "curses", "Condition")):
        plan[sheet_name] = (edits_for_simple_sheet(
            wb, sheet_name, owner_key, column, by_owner), [], [], 0)
    plan["statuses"] = (edits_for_statuses(wb, by_owner), [], [], 0)
    return goals, plan


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report drift and exit 1; write nothing")
    ap.add_argument("--dry-run", action="store_true",
                    help="print every edit it would make; write nothing")
    args = ap.parse_args()

    try:
        goals, plan = build_edits()
    except Finding as f:
        print("FINDING: %s" % f)
        return 1

    total = sum(len(e) for e, _, _, _ in plan.values())
    added_any = {s: a for s, (_, a, _, _) in plan.items() if a}

    if args.check:
        if not total:
            print("`%s` and its %d owner sheets agree (%d goals)."
                  % (SHEET, len(plan), len(goals)))
            return 0
        print("%d cell(s) differ from `%s` — run tools/apply_goals_sheet.py:"
              % (total, SHEET))
        for sheet in sorted(plan):
            edits = plan[sheet][0]
            if edits:
                print("  %s: %d" % (sheet, len(edits)))
                for ref in sorted(edits)[:8]:
                    print("      %s = %r" % (ref, edits[ref]))
                if len(edits) > 8:
                    print("      ... and %d more" % (len(edits) - 8))
        return 1

    if args.dry_run:
        for sheet in sorted(plan):
            edits, added, _, _ = plan[sheet]
            if added:
                print("%s: + column(s) %s" % (sheet, ", ".join(added)))
            for ref in sorted(edits):
                print("  %s!%s = %r" % (sheet, ref, edits[ref]))
        print("%d cell(s) across %d sheet(s)" % (total, len(plan)))
        return 0

    if not total:
        print("Nothing to do — `%s` and its owner sheets already agree." % SHEET)
        return 0

    with Workbook(XLSX) as wb:
        for sheet in sorted(plan):
            edits, added, headers, last_row = plan[sheet]
            if not edits:
                continue
            wb.set_cells(sheet, edits)
            # A sheet that grew past its table has to have the TABLE grown too —
            # ref and column list together, or Excel calls the file corrupt for
            # spanning more columns than the table has names for.
            if added:
                wb.grow_table(sheet, headers,
                              "%s%d" % (col_name(len(headers) - 1), last_row))

    print("`%s` -> %d cell(s) across %d sheet(s)" % (SHEET, total, len(plan)))
    for sheet in sorted(plan):
        edits, added, _, _ = plan[sheet]
        if edits:
            print("  %s: %d%s" % (sheet, len(edits),
                                  ("  (+%s)" % ", ".join(added)) if added else ""))
    if added_any:
        print("New column(s) added — regenerate data/ "
              "(tools/generate_goal_enemy_tres.py) and re-run check_data_sync.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""One-shot: move the research that predates `tools/research.py` into `research/`.

Three things lived in three formats before there was one system:

  docs/goal-candidates.csv      316 goal-enemy rows      -> research/goals.csv
  docs/influence-candidates.md  every connection line    -> research/connections.csv
  tools/influence_researched.json  the connections ledger -> research/ledger.json

The candidates doc is prose laid out by what the owner does next, so this reads
its layout: the `## N.` section says the Status, `### Strong` / `### Weaker` the
Strength, and every bold `**A → B**` before a line's ` — ` is a pair (one row per
pair, each carrying the whole line as Text, so a three-pair quote can be ticked
pair by pair). A line naming no pair keeps its text and its section. Nothing is
summarised: every line of sections 1–7 is a row, word for word. Section 8, the
research log, is prose about how the work went and is appended to
docs/influence-research.md.

The goal games are marked researched for `goals` with the note that they were
written from search summaries, before the wikis were reachable, so a later
pass knows those 80 can be revisited with the wikis open.

Run once; it refuses to overwrite a research/ file that already exists.
"""

import csv
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import research  # noqa: E402

ROOT = research.ROOT
OLD_GOALS = os.path.join(ROOT, "docs", "goal-candidates.csv")
OLD_DOC = os.path.join(ROOT, "docs", "influence-candidates.md")
OLD_LEDGER = os.path.join(ROOT, "tools", "influence_researched.json")
METHOD_DOC = os.path.join(ROOT, "docs", "influence-research.md")

PAIR = re.compile(r"\*\*([^*→←]+?) (→|←) ([^*]+?)\*\*")
LINK = re.compile(r"\]\((https?://[^)\s]+)\)|(?<![(\[])\b(https?://[^\s)\]]+)")
SECTION_STATUS = {"1": "to review", "2": "waiting for game row", "3": "not an influence",
                  "4": "source check", "5": "lead", "6": "nothing found", "7": "on sheet"}
# The sentence under a heading that explains the doc's own layout, which the
# workbook's `about` sheet and docs/research.md now explain instead.
LAYOUT_NOTES = ("Sorted by the game", "From your own list of games", "Listed so they aren't searched",
                "Lines that are rows in the sheet now")


def migrate_goals():
    rows = []
    with open(OLD_GOALS, newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            r.update({"Ticked": "", "Count": "", "Source": "", "Status": "to review", "Owner": "",
                      "Owner Notes": "", "ID": ""})
            rows.append(r)
    research.assign_ids("goals", rows)
    research.write_rows("goals", rows)
    return rows


def migrate_connections(names):
    rows, section, sub, context, log = [], "", "", "", []
    for line in open(OLD_DOC, encoding="utf8").read().split("\n"):
        if line.startswith("## "):
            section, sub, context = line[3:].split(".", 1)[0], "", ""
            continue
        if line.startswith("### "):
            sub, context = line[4:].strip(), ""
            continue
        if not section or not line.strip() or line.strip() == "---":
            continue
        if section == "8":
            log.append(line)
            continue
        text = re.sub(r"^- (\[[ x]\] )?", "", line).replace(" ✓ *on the chart*", "")
        if not line.startswith("- "):
            if text.startswith(LAYOUT_NOTES):
                continue
            if text.rstrip().endswith(":"):
                context = text.rstrip(": ")
                continue
        status = SECTION_STATUS[section]
        if section == "2" and sub.startswith("Leads"):
            status = "lead"
        strength = sub if sub in ("Strong", "Weaker") else ""
        head = text.split(" — ", 1)[0]
        pairs = []
        for a, arrow, b in PAIR.findall(head):
            a, b = a.strip(), b.strip()
            if arrow == "←":
                a, b = b, a
            # Off the review sections, a bold pair is often a gloss ("Juicy
            # Realm ← Isaac / Nuclear Throne / Gungeon"), not one row; keep it
            # as a pair only when both ends are games the sheet has.
            if status in ("to review", "waiting for game row", "on sheet") or (a in names and b in names):
                pairs.append((a, b))
        sources = "\n".join(dict.fromkeys(m[0] or m[1] for m in LINK.findall(text)))
        game = ""
        if not pairs:
            bold = re.findall(r"\*\*([^*]+?)\*\*", head)
            game = next((b for b in bold if b in names), "")
        base = {"Game": game, "Dev/Series": "yes" if "Dev/Series Relation" in head else "",
                "Strength": strength, "Text": text, "Source": sources,
                "Heading": " / ".join(x for x in (sub, context) if x), "Status": status,
                "Owner": "", "Owner Notes": "", "ID": ""}
        for a, b in pairs or [("", "")]:
            rows.append(dict(base, Influencer=a, Influencee=b))
    research.assign_ids("connections", rows)
    research.write_rows("connections", rows)
    return rows, log


def main():
    for kind in ("goals", "connections"):
        if os.path.exists(research.csv_path(kind)):
            sys.exit(f"{research.csv_path(kind)} exists already; this one-shot has run")
    names = set(research.catalog())
    goals = migrate_goals()
    conns, log = migrate_connections(names)

    ledger = research.load_ledger()
    for g, when in json.load(open(OLD_LEDGER, encoding="utf8")).items():
        ledger.setdefault(g, {})["connections"] = when
    for g in sorted({r["Game"] for r in goals}):
        ledger.setdefault(g, {})["goals"] = ("before 2026-10-09: from search summaries, before the wikis were "
                                             "reachable (docs/goal-enemy-candidates.md)")
    research.save_json(research.LEDGER, ledger)

    doc = open(METHOD_DOC, encoding="utf8").read().rstrip()
    if "## Research log" not in doc:
        doc += ("\n\n## Research log\n\nWhat each pass covered, moved here from the old candidates doc when the "
                "candidates moved to `research/connections.csv`.\n\n" + "\n".join(log) + "\n")
        open(METHOD_DOC, "w", encoding="utf8").write(doc)

    for path in (OLD_GOALS, OLD_DOC, OLD_LEDGER):
        os.remove(path)
    by = {}
    for r in conns:
        by[r["Status"]] = by.get(r["Status"], 0) + 1
    print(f"goals: {len(goals)} rows; connections: {len(conns)} rows {by}; ledger: {len(ledger)} games")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""The table of contents of a GDScript file: its `# --- section ---` headers with
line ranges, and the functions, signals, consts and vars under each.

The big scripts here run to 8,000 lines and about 45% of them are comments, so
reading one to find a function is slow, and grepping one finds a name without
saying what part of the file it sits in. This prints the shape in one go:

    python3 tools/outline.py scripts/redesign2/Overworld2.gd
    python3 tools/outline.py scripts/autoload/GameLoop2.gd --grep stun
    python3 tools/outline.py scripts/redesign2/BattlefieldView.gd --funcs-only

`--grep` keeps the sections whose header or members match (case-insensitive),
which turns "where does the board handle a stun" into a few lines with numbers
to Read from. Members are listed without their comments; the line numbers are
what to open.
"""
import argparse
import re
import sys

SECTION = re.compile(r"^# ---+\s*(.*?)\s*-*\s*$")
MEMBER = re.compile(r"^(static func|func|signal|const|var|enum|class)\s+([A-Za-z_]\w*)")


def outline(path):
    sections = [{"title": "(top of file)", "line": 1, "members": []}]
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for i, line in enumerate(lines, 1):
        m = SECTION.match(line)
        if m and m.group(1):
            sections.append({"title": m.group(1), "line": i, "members": []})
            continue
        m = MEMBER.match(line)
        if m:
            kind = "func" if "func" in m.group(1) else m.group(1)
            sections[-1]["members"].append((i, kind, m.group(2)))
    for k, s in enumerate(sections):
        s["end"] = sections[k + 1]["line"] - 1 if k + 1 < len(sections) else len(lines)
    return [s for s in sections if s["members"] or s["title"] != "(top of file)"], len(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("files", nargs="+")
    ap.add_argument("--grep", help="keep only sections whose header or members match")
    ap.add_argument("--funcs-only", action="store_true", help="list functions only")
    args = ap.parse_args()
    pat = re.compile(args.grep, re.I) if args.grep else None
    for path in args.files:
        sections, total = outline(path)
        print(f"{path}  ({total} lines, {len(sections)} sections)")
        for s in sections:
            members = s["members"]
            if args.funcs_only:
                members = [m for m in members if m[1] == "func"]
            if pat:
                if pat.search(s["title"]):
                    pass
                else:
                    members = [m for m in members if pat.search(m[2])]
                    if not members:
                        continue
            print(f"  {s['line']:>5}-{s['end']:<5} {s['title']}")
            for line, kind, name in members:
                tag = "" if kind == "func" else f"{kind} "
                print(f"         {line:>5}  {tag}{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

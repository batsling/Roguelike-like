#!/usr/bin/env python3
"""The order `docs/turn-order.md` describes is the order the code runs.

WHY THIS EXISTS. The turn-order codex answers "what fires first" — the ground or
the swing, the kill's gold or its `enemy_killed`, `game_beaten` or the game's own
loot — and an answer to that question is only worth having if it is still true.
Prose cannot tell when a call moves eleven lines up, so the doc pins itself to the
code: after each section sits an ```order block naming one function and, one per
line, snippets of source that must appear in its body IN THAT ORDER.

    ```order
    scripts/autoload/GameLoop2.gd :: log_attempt
    _attempt_snapshots.append(_run_snapshot())
    attempt_turn()
    TriggerBus.run_lost.emit(
    ```

A snippet that is missing (renamed, deleted) or found only BEFORE the one above it
(reordered) fails the check, naming the block. The fix is never to loosen the
snippet until it passes: it is to read what changed, correct the section's prose
and its block together, and — if the change was a mistake — the code.

Comment lines are dropped before matching, because this file's comments routinely
name the calls they sit above, and a match on the comment would pin nothing.

    python3 tools/check_turn_order.py        # exits non-zero on drift
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "turn-order.md")

BLOCK = re.compile(r"^```order\n(.*?)^```", re.S | re.M)
TOP_LEVEL_FUNC = re.compile(r"^(static\s+)?func\s")


def function_body(path, name):
    """The function's lines, comment lines dropped, or None if it isn't there."""
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        lines = f.read().split("\n")
    start = re.compile(r"^(static\s+)?func\s+%s\s*\(" % re.escape(name))
    for i, line in enumerate(lines):
        if start.match(line):
            body = []
            for line2 in lines[i:]:
                if body and TOP_LEVEL_FUNC.match(line2):
                    break
                if not line2.strip().startswith("#"):
                    body.append(line2)
            return "\n".join(body)
    return None


def check():
    with open(DOC, encoding="utf-8") as f:
        doc = f.read()
    blocks = BLOCK.findall(doc)
    if not blocks:
        return ["docs/turn-order.md has no ```order blocks — the check pins nothing"]
    problems = []
    for raw in blocks:
        rows = [r.strip() for r in raw.strip().split("\n") if r.strip()]
        head, anchors = rows[0], rows[1:]
        if "::" not in head:
            problems.append("block header %r is not `path :: function`" % head)
            continue
        path, name = [p.strip() for p in head.split("::", 1)]
        if not os.path.exists(os.path.join(ROOT, path)):
            problems.append("%s: no such file" % head)
            continue
        body = function_body(path, name)
        if body is None:
            problems.append("%s: no function `%s` in %s" % (head, name, path))
            continue
        pos = 0
        prev = "(start of the function)"
        for anchor in anchors:
            at = body.find(anchor, pos)
            if at < 0:
                if anchor in body:
                    problems.append("%s: `%s` now comes BEFORE `%s`" % (head, anchor, prev))
                else:
                    problems.append("%s: `%s` is no longer in the function" % (head, anchor))
                break
            pos = at + len(anchor)
            prev = anchor
    return problems


def main():
    problems = check()
    if problems:
        print("The turn order in the code no longer matches docs/turn-order.md:\n")
        for p in problems:
            print("  - " + p)
        print("\nRead what changed, then update the section's prose AND its ```order"
              "\nblock together (or put the code back, if the move was a mistake).")
        return 1
    n = len(BLOCK.findall(open(DOC, encoding="utf-8").read()))
    print("turn order: %d blocks, all in the order docs/turn-order.md says" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())

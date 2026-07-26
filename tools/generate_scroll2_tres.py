#!/usr/bin/env python3
"""
Generate Godot ScrollData .tres for the games-first redesign (2.0) scrolls, from
the `scrolls2.0` sheet of tools/Roguelikes.xlsx into data/scrolls2.0/.

The 2.0 scrolls (docs/games-first-redesign.md §4.1) replace the combat four-tier
INT-check model with a single effect + a Preference (Positive / Negative /
Neutral) plus the identification minigame. They reuse the ScrollData resource,
extended (not forked) with an `effect` list, so this is a NEW generator that
writes only the 2.0 fields; the legacy generate_scroll_tres.py + data/scrolls
stay intact for the still-present combat scroll code until the ScrollSystem
rewrite + combat cut land together.

  scrolls2.0: Scrolls | Game | Preference | Description | File | Effect

Effect token DSL (one scroll = one clause):
  buff_enemies damage N games M      -> {op:buff_enemies, damage:N, games:M}
  forget scroll|potion|spell N       -> {op:forget, kind, count:N}
  spawn_enemy current|low|medium|high-> {op:spawn_enemy, difficulty}
  identify_scrolls choose|random|all N -> {op:identify_scrolls, mode, count:N}
  stun_enemies choose|random|all N   -> {op:stun_enemies, mode, count:N}
  teleport same|closer|farther N     -> {op:teleport, dir, spread:N}

Art: File -> res://images2.0/scrolls/<File>.png (identified art). Unidentified
scrolls — and identified scrolls with missing art — fall back to the shared
Unidentified.png at runtime (ScrollSystem), so a blank File is expected.

  python3 tools/generate_scroll2_tres.py            # regenerate every 2.0 scroll
  python3 tools/generate_scroll2_tres.py --list      # print, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "scrolls2.0")


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v):
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


def parse_effect(raw):
    """Parse the Effect token DSL into a list with a single op dict (or [])."""
    s = _clean(raw)
    if not s:
        return []
    toks = s.split()
    verb = toks[0].lower()
    rest = toks[1:]
    nums = [int(t) for t in rest if re.match(r"^\d+$", t)]

    if verb == "buff_enemies":
        kv = _pairs(rest)
        return [{"op": "buff_enemies",
                 "damage": int(kv.get("damage", 1)),
                 "games": int(kv.get("games", 1))}]
    if verb == "forget":
        kind = rest[0].lower() if rest and not rest[0].isdigit() else "scroll"
        return [{"op": "forget", "kind": kind, "count": nums[0] if nums else 1}]
    if verb == "spawn_enemy":
        diff = rest[0].lower() if rest else "current"
        return [{"op": "spawn_enemy", "difficulty": diff}]
    if verb in ("identify_scrolls", "stun_enemies"):
        mode = rest[0].lower() if rest and not rest[0].isdigit() else "choose"
        return [{"op": verb, "mode": mode, "count": nums[0] if nums else 1}]
    if verb == "teleport":
        direction = rest[0].lower() if rest and not rest[0].isdigit() else "same"
        return [{"op": "teleport", "dir": direction, "spread": nums[0] if nums else 1}]

    raise ValueError("scroll effect DSL: unknown verb %r in %r" % (verb, s))


def _pairs(tokens):
    """['damage','1','games','1'] -> {'damage':'1','games':'1'}."""
    out = {}
    i = 0
    while i + 1 < len(tokens):
        out[tokens[i].lower()] = tokens[i + 1]
        i += 2
    return out


def gd_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return '"%s"' % gd_str(v)
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (gd_str(k), gd_value(val)) for k, val in v.items()) + "}"
    raise TypeError(type(v))


def scroll_tres(row) -> tuple:
    name = str(row["Scrolls"]).strip()
    sid = slugify(name)
    preference = _clean(row.get("Preference")) or "Neutral"
    file = _clean(row.get("File"))
    effect = parse_effect(row.get("Effect"))

    lines = []
    lines.append('[gd_resource type="Resource" script_class="ScrollData" load_steps=2 '
                 'format=3 uid="uid://scroll2_%s"]' % sid)
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/ScrollData.gd" id="1_scroll"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_scroll")')
    lines.append('id = &"%s"' % sid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('reference = "%s"' % gd_str(_clean(row.get("Game"))))
    lines.append('preference = "%s"' % gd_str(preference))
    lines.append('file = "%s"' % gd_str(file))
    lines.append("effect = %s" % gd_value(effect))
    return sid, "\n".join(lines) + "\n"


def rows(sheet):
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for r in sheet.iter_rows(min_row=2, values_only=True):
        if not r or r[0] is None:
            continue
        yield dict(zip(headers, r))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print, do not write")
    args = ap.parse_args()

    wb = openpyxl.load_workbook(XLSX_PATH, data_only=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in rows(wb["scrolls2.0"]):
        sid, text = scroll_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (sid, text))
            continue
        with open(os.path.join(OUT_DIR, sid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(sid)
    if not args.list:
        print("Wrote %d scroll2.0 .tres to %s" % (len(written), OUT_DIR))
        for s in written:
            print("  -", s)


if __name__ == "__main__":
    main()

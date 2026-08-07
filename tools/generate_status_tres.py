#!/usr/bin/env python3
"""
Generate Godot StatusData .tres for the games-first redesign (2.0) statuses, from
the `statuses2.0` sheet of tools/Roguelikes.xlsx into data/statuses2.0/.

A status (docs/games-first-redesign.md §13) is a clause bolted onto the run's
goals. The sheet's four prose quadrants are carried through verbatim for tooltips,
but everything the engine runs on comes out of two authored columns:

  statuses2.0: Name | Type | Game | On Player | On Enemy | Stackable | Image
                    | Condition | Reward

  Condition   the challenge clause, with {expr} holes over X (the stack count):
              "you get {X} achievements"
              "beaten in {1+(1/2)^(X-2)} hours or less"
  Reward      semicolon-separated effect tokens, same {expr} holes:
              "gain_chest small {X}; gain_stat bash {X}"

Reward token DSL (one clause per effect):
  gain_chest [small|medium|large|huge] <n>   -> {type: gain_chest, value, choices}
  gain_stat  <stat> <n>                      -> {type: gain_stat, stat, value}
  gain_hp     <n>                            -> {type: gain_hp, value}
  gain_max_hp <n>                            -> {type: gain_max_hp, value}
  gain_gold   <n>                            -> {type: gain_gold, value}

Any <n> may be a literal or a {expr}. Literals are emitted straight onto the
effect; expressions land in a `scaled` sub-dict (field -> expression) that
StatusData.reward_effects evaluates at apply time, since X isn't known until the
status is actually on something. `^` is rewritten to pow() on the way out, so the
sheet can keep writing exponents the way a person does.

Decay follows the type, per the design call in §13: a DEBUFF loses a stack each
time its condition is completed (Marked's own sheet cell says so), a BUFF persists
for the run — it is the reward, not a timer.

Art: Image -> res://images2.0/statuses/<Image>.png, referenced eagerly (three
files, unlike the 818 game covers that forced GameData's lazy path).

  python3 tools/generate_status_tres.py           # regenerate every status
  python3 tools/generate_status_tres.py --list    # print the parse, write nothing
"""

import argparse
import os
import re

import openpyxl

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
XLSX_PATH = os.environ.get(
    "CARDS_XLSX", os.path.join(PROJECT_ROOT, "tools", "Roguelikes.xlsx"))
OUT_DIR = os.path.join(PROJECT_ROOT, "data", "statuses2.0")
IMG_DIR = os.path.join(PROJECT_ROOT, "images2.0", "statuses")
IMG_RES_PREFIX = "res://images2.0/statuses/"

# Chest size -> how many items it offers, mirroring Data.CHEST_SIZE_CHOICES
# (§8.2). A sizeless `gain_chest N` leaves choices 0 and takes the reward screen's
# own default, exactly like an unsized level-up chest.
CHEST_CHOICES = {"small": 1, "medium": 2, "large": 3, "huge": 5}

# How each reward verb reads back to the player, for the generated reward_text —
# singular and plural, because the verbs do not all take a bare -s ("2 Bashes",
# not "2 Bashs") and a status is read on a checklist row where that shows.
STAT_LABELS = {
    "bash": ("Bash", "Bashes"),
    "dash": ("Dash", "Dashes"),
    "transmute": ("Transmute", "Transmutes"),
    "scramble": ("Scramble", "Scrambles"),
    "bombs": ("Bomb", "Bombs"),
    "keys": ("Key", "Keys"),
    "shields": ("Shield", "Shields"),
    "block": ("Block", "Block"),
    "push": ("Push", "Pushes"),
    "game_choices": ("Game Choice", "Game Choices"),
}


def slugify(name: str) -> str:
    s = str(name).strip().lower().replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def gd_str(s) -> str:
    s = "" if s is None else str(s)
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ").replace("\r", " ")


def _clean(v) -> str:
    s = ("" if v is None else str(v)).strip()
    return "" if s.upper() in ("", "N/A", "NONE") else s


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


# --- the {expr} holes -----------------------------------------------------

def to_godot_expr(expr: str) -> str:
    """Rewrite the sheet's arithmetic into something Godot's Expression parses.

    Two rewrites:

    1. Integer literals become FLOAT literals. Godot's Expression does integer
       division on `1/2` — it evaluates to 0, and `1+(1/2)^(X-2)` then reads as
       `pow(0, -1)`, i.e. Dexterity's window at one stack came out as INT64_MIN
       hours. Every number in a status expression is a quantity, not a count of
       array slots, so they are all floats. (X itself stays an int: it is bound at
       runtime, and the arithmetic around it promotes.)
    2. `a^b` -> `pow(a, b)`, right-associative and binding tighter than +-*/ , so
       `1+(1/2)^(X-2)` ends up `1.0+pow((1.0/2.0), (X-2.0))`. The operands are
       whatever sits immediately either side — a parenthesised group, a number, or
       a bare name.
    """
    expr = expr.strip()
    # A bare run of digits that isn't already part of a decimal or an identifier.
    expr = re.sub(r"(?<![\d.\w])(\d+)(?![\d.])", r"\1.0", expr)
    while "^" in expr:
        # Rightmost ^ first, so a^b^c resolves as a^(b^c).
        i = expr.rfind("^")
        left, l_start = _operand_before(expr, i)
        right, r_end = _operand_after(expr, i)
        if left is None or right is None:
            raise ValueError("status reward/condition: dangling '^' in %r" % expr)
        expr = expr[:l_start] + "pow(%s, %s)" % (left, right) + expr[r_end:]
    return expr


def _operand_before(s: str, i: int):
    """The operand ending just before index i, as (text, start_index)."""
    j = i - 1
    while j >= 0 and s[j].isspace():
        j -= 1
    if j < 0:
        return None, i
    if s[j] == ")":
        depth = 0
        while j >= 0:
            if s[j] == ")":
                depth += 1
            elif s[j] == "(":
                depth -= 1
                if depth == 0:
                    break
            j -= 1
        if j < 0:
            return None, i
        return s[j:i].strip(), j
    k = j
    while k >= 0 and (s[k].isalnum() or s[k] in "._"):
        k -= 1
    if k == j:
        return None, i
    return s[k + 1:i].strip(), k + 1


def _operand_after(s: str, i: int):
    """The operand starting just after index i, as (text, end_index)."""
    j = i + 1
    while j < len(s) and s[j].isspace():
        j += 1
    if j >= len(s):
        return None, i
    start = j
    if s[j] in "+-":  # a unary sign on the exponent
        j += 1
        while j < len(s) and s[j].isspace():
            j += 1
    if j < len(s) and s[j] == "(":
        depth = 0
        while j < len(s):
            if s[j] == "(":
                depth += 1
            elif s[j] == ")":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        return s[start:j].strip(), j
    k = j
    while k < len(s) and (s[k].isalnum() or s[k] in "._"):
        k += 1
    if k == j:
        return None, i
    return s[start:k].strip(), k


HOLE = re.compile(r"\{([^{}]*)\}")


def normalise_holes(text: str) -> str:
    """Rewrite every {expr} hole's arithmetic, leaving the surrounding prose alone."""
    return HOLE.sub(lambda m: "{%s}" % to_godot_expr(m.group(1)), text)


def _amount(tok: str):
    """A reward amount: ('literal', int) or ('expr', 'X') for a {expr} hole."""
    tok = tok.strip()
    m = HOLE.fullmatch(tok)
    if m:
        return "expr", to_godot_expr(m.group(1))
    if re.fullmatch(r"-?\d+", tok):
        return "literal", int(tok)
    raise ValueError("status reward: %r is not a number or a {expr}" % tok)


# --- the Reward column ----------------------------------------------------

def parse_reward(raw):
    """Parse the Reward column -> (effects list, human-readable text)."""
    s = _clean(raw)
    if not s:
        return [], ""
    effects, words = [], []
    for clause in [c.strip() for c in s.split(";") if c.strip()]:
        eff, word = parse_reward_clause(clause)
        effects.append(eff)
        words.append(word)
    return effects, ", ".join(words)


def parse_reward_clause(clause):
    toks = clause.split()
    verb = toks[0].lower()
    rest = toks[1:]

    def put(eff, field, tok):
        kind, val = _amount(tok)
        if kind == "literal":
            eff[field] = val
        else:
            eff.setdefault("scaled", {})[field] = val

    if verb == "gain_chest":
        size = rest[0].lower() if rest and not _is_amount(rest[0]) else ""
        amount = rest[1] if size else (rest[0] if rest else "1")
        eff = {"type": "gain_chest"}
        put(eff, "value", amount)
        if size:
            if size not in CHEST_CHOICES:
                raise ValueError("status reward: unknown chest size %r" % size)
            eff["choices"] = CHEST_CHOICES[size]
        one = ("%s Chest" % size.capitalize()) if size else "Chest"
        return eff, "+%s %s" % (_amount_word(amount), _plural(amount, one, one + "s"))

    if verb == "gain_stat":
        if len(rest) < 2:
            raise ValueError("status reward: gain_stat needs <stat> <n> in %r" % clause)
        stat = rest[0].lower()
        eff = {"type": "gain_stat", "stat": stat}
        put(eff, "value", rest[1])
        fallback = stat.replace("_", " ").title()
        one, many = STAT_LABELS.get(stat, (fallback, fallback + "s"))
        return eff, "+%s %s" % (_amount_word(rest[1]), _plural(rest[1], one, many))

    if verb in ("gain_hp", "gain_max_hp", "gain_gold"):
        if not rest:
            raise ValueError("status reward: %s needs an amount in %r" % (verb, clause))
        eff = {"type": verb}
        put(eff, "value", rest[0])
        label = {"gain_hp": "Health", "gain_max_hp": "Max Health", "gain_gold": "Gold"}[verb]
        return eff, "+%s %s" % (_amount_word(rest[0]), label)

    raise ValueError("status reward DSL: unknown verb %r in %r" % (verb, clause))


def _is_amount(tok: str) -> bool:
    return bool(HOLE.fullmatch(tok.strip()) or re.fullmatch(r"-?\d+", tok.strip()))


def _amount_word(tok: str) -> str:
    """How an amount reads inside reward_text: a literal stays a literal, a hole
    stays a hole so StatusData can substitute it at the live stack count."""
    m = HOLE.fullmatch(tok.strip())
    return "{%s}" % to_godot_expr(m.group(1)) if m else tok.strip()


def _plural(tok: str, one: str, many: str) -> str:
    """The noun for an amount, agreeing in number.

    A literal amount is settled here. An {expr} amount is NOT — the same status
    reads "+1 Small Chest" at one stack and "+3 Small Chests" at three — so it
    emits the pair as `[singular|plural]` and StatusData.resolve picks between
    them once X is known. Spelling both out (rather than a bare "(s)" suffix) is
    what lets an irregular like Bash/Bashes agree too.
    """
    t = tok.strip()
    if re.fullmatch(r"-?\d+", t):
        return one if t == "1" else many
    return "[%s|%s]" % (one, many)


# --- emit -----------------------------------------------------------------

def _image_path(file: str) -> str:
    if not file:
        return ""
    for ext in (".png", ".jpg"):
        if os.path.exists(os.path.join(IMG_DIR, file + ext)):
            return IMG_RES_PREFIX + file + ext
    return ""


def status_tres(row) -> tuple:
    name = str(row["Name"]).strip()
    sid = slugify(name)
    kind = (_clean(row.get("Type")) or "Buff").lower()
    if kind not in ("buff", "debuff"):
        raise ValueError("statuses2.0 %s: Type must be Buff or Debuff, got %r" % (name, kind))
    condition = normalise_holes(_clean(row.get("Condition")))
    reward, reward_text = parse_reward(row.get("Reward"))
    file = _clean(row.get("Image"))
    img = _image_path(file)

    steps = 3 if img else 2
    lines = []
    lines.append('[gd_resource type="Resource" script_class="StatusData" load_steps=%d '
                 'format=3 uid="uid://status2_%s"]' % (steps, sid))
    lines.append("")
    lines.append('[ext_resource type="Script" '
                 'path="res://scripts/resources/StatusData.gd" id="1_status"]')
    if img:
        lines.append('[ext_resource type="Texture2D" path="%s" id="2_img"]' % img)
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_status")')
    lines.append('id = &"%s"' % sid)
    lines.append('display_name = "%s"' % gd_str(name))
    lines.append('kind = &"%s"' % kind)
    lines.append('source_game = "%s"' % gd_str(_clean(row.get("Game"))))
    lines.append('on_player_text = "%s"' % gd_str(_clean(row.get("On Player"))))
    lines.append('on_enemy_text = "%s"' % gd_str(_clean(row.get("On Enemy"))))
    lines.append('stackable = "%s"' % gd_str(_clean(row.get("Stackable")) or "Intensity"))
    lines.append('condition = "%s"' % gd_str(condition))
    lines.append("reward = %s" % gd_value(reward))
    lines.append('reward_text = "%s"' % gd_str(reward_text))
    # Buffs persist for the run; debuffs shed a stack per completion (§13).
    lines.append("decays_on_complete = %s" % ("true" if kind == "debuff" else "false"))
    lines.append('file = "%s"' % gd_str(file))
    if img:
        lines.append('image = ExtResource("2_img")')
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
    sheet = wb["statuses2.0"]
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for needed in ("Condition", "Reward"):
        if needed not in headers:
            raise SystemExit(
                "statuses2.0 has no %r column — run tools/_statuses_sheet_setup.py first."
                % needed)

    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for row in rows(sheet):
        sid, text = status_tres(row)
        if args.list:
            print("=== %s ===\n%s" % (sid, text))
            continue
        with open(os.path.join(OUT_DIR, sid + ".tres"), "w", encoding="utf-8") as f:
            f.write(text)
        written.append(sid)
    if not args.list:
        print("Wrote %d statuses2.0 .tres to %s" % (len(written), OUT_DIR))
        for s in written:
            print("  -", s)


if __name__ == "__main__":
    main()

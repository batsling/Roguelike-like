#!/usr/bin/env python3
"""
Generate Godot StatusData .tres for the games-first redesign (2.0) statuses, from
the `statuses2.0` sheet of tools/Roguelikes.xlsx into data/statuses2.0/.

A status (docs/games-first-redesign.md §13) is a clause bolted onto the run's
goals. The sheet's PROSE columns are carried through verbatim for tooltips; what
the engine runs on is the two effect columns, one per side, authored
independently so a status's two halves can do different things:

  statuses2.0: Name | Type | Game | On Player | On Enemy | Stackable | Image
                    | On Player Effect | On Enemy Effect

Side effect DSL — one clause per cell:

  <verb> "<condition>" [decay] [-> <reward>; <reward>; …]

  goal    a standing objective of the holder's own: "If <condition>, gain
          <reward>". On the player, an extra checklist row offered every game.
  clause  ANDed onto goals and REQUIRED — the goal is not met until you did both.
          On an enemy it tightens that enemy's goal; on the player it tightens
          EVERY enemy's goal.
  bonus   an OPTIONAL objective — "and if <condition>, gain <reward>" — claimable
          for its reward, free to skip.
  decay   completing it sheds one stack.

Because the verb says what the side DOES, Buff/Debuff drives no mechanic: it is
the HUD tint and the collection filter, nothing more.

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

An {expr} hole may carry a FORMAT after a colon — `{1+(1/2)^(X-2):hours}` renders
as a duration ("1 hour 30 minutes") rather than a bare number, so a fractional
window reads as a time instead of as "1.5".

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

# Formats an {expr} hole may ask for after a colon. `hours` is what makes a
# fractional window read as "1 hour 30 minutes" instead of "1.5".
FORMATS = ("hours",)


def _split_hole(body: str):
    """'1+(1/2)^(X-2):hours' -> ('1+(1/2)^(X-2)', 'hours'); no colon -> fmt ''."""
    if ":" not in body:
        return body, ""
    expr, _, fmt = body.rpartition(":")
    fmt = fmt.strip().lower()
    if fmt not in FORMATS:
        raise ValueError("status {expr} hole: unknown format %r (known: %s)"
                         % (fmt, ", ".join(FORMATS)))
    return expr, fmt


def normalise_holes(text: str) -> str:
    """Rewrite every {expr} hole's arithmetic, leaving the surrounding prose alone
    and preserving any `:format` suffix for the runtime to act on."""
    def one(m):
        expr, fmt = _split_hole(m.group(1))
        return "{%s%s}" % (to_godot_expr(expr), (":" + fmt) if fmt else "")
    return HOLE.sub(one, text)


def _amount(tok: str):
    """A reward amount: ('literal', int) or ('expr', 'X') for a {expr} hole.

    A reward is a count of things granted, so a `:format` on it would be
    meaningless — only the CONDITION text formats.
    """
    tok = tok.strip()
    m = HOLE.fullmatch(tok)
    if m:
        expr, fmt = _split_hole(m.group(1))
        if fmt:
            raise ValueError("status reward: amounts take no :format (%r)" % tok)
        return "expr", to_godot_expr(expr)
    if re.fullmatch(r"-?\d+", tok):
        return "literal", int(tok)
    raise ValueError("status reward: %r is not a number or a {expr}" % tok)


# --- a side's effect cell -------------------------------------------------

MODES = ("goal", "clause", "bonus")
SIDE_RE = re.compile(
    r'^\s*(?P<verb>[a-z_]+)\s+"(?P<condition>[^"]*)"\s*(?P<flags>[^-]*?)\s*'
    r'(?:->\s*(?P<reward>.*))?$', re.S)


def parse_side(raw, where):
    """Parse one `On Player Effect` / `On Enemy Effect` cell.

    Returns {} for an empty cell — a status is allowed to do nothing on one side,
    and an empty dict is what the runtime reads as "this side is inert".
    """
    s = _clean(raw)
    if not s:
        return {}
    m = SIDE_RE.match(s)
    if not m:
        raise ValueError('statuses2.0 %s: cannot parse %r — expected '
                         '<verb> "<condition>" [decay] [-> <reward>]' % (where, s))
    mode = m.group("verb").lower()
    if mode not in MODES:
        raise ValueError("statuses2.0 %s: unknown verb %r (known: %s)"
                         % (where, mode, ", ".join(MODES)))
    flags = m.group("flags").split()
    unknown = [f for f in flags if f.lower() != "decay"]
    if unknown:
        raise ValueError("statuses2.0 %s: unknown flag(s) %s" % (where, unknown))
    reward, reward_text = parse_reward(m.group("reward"))
    if mode == "clause" and reward:
        raise ValueError("statuses2.0 %s: a `clause` is a requirement, not a "
                         "payout — move the reward to a `bonus` or a `goal`" % where)
    return {
        "mode": mode,
        "condition": normalise_holes(m.group("condition")),
        "reward": reward,
        "reward_text": reward_text,
        "decay": any(f.lower() == "decay" for f in flags),
    }


# --- the Reward half of a side clause -------------------------------------

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
    on_player = parse_side(row.get("On Player Effect"), "%s / On Player Effect" % name)
    on_enemy = parse_side(row.get("On Enemy Effect"), "%s / On Enemy Effect" % name)
    if not on_player and not on_enemy:
        raise ValueError("statuses2.0 %s: neither side does anything" % name)
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
    lines.append("on_player = %s" % gd_value(on_player))
    lines.append("on_enemy = %s" % gd_value(on_enemy))
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
    for needed in ("On Player Effect", "On Enemy Effect"):
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

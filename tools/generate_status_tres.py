#!/usr/bin/env python3
"""
Generate Godot StatusData .tres for the games-first redesign (2.0) statuses, from
the `statuses2.0` sheet of tools/Roguelikes.xlsx into data/statuses2.0/.

A status (docs/games-first-redesign.md §13) is a clause bolted onto the run's
goals. The sheet's PROSE columns are carried through verbatim for tooltips; what
the engine runs on is the two effect columns, one per side, authored
independently so a status's two halves can do different things:

  statuses2.0: Name | Type | Game | On Player | On Player Effect | On Enemy
                    | On Enemy Effect | Combat | Decrease | EnemyOnly
                    | Enemy Combat Effect | Stackable | Image

A status has a third side beside its two goal sides: a COMBAT side, which is the
one place it touches a number on the board rather than a goal. `Combat` is the
prose, `Enemy Combat Effect` the machine-readable counterpart, and `EnemyOnly`
says whether it is felt on enemies alone (every buff) or on whoever is carrying
it, the player included (every debuff). See parse_combat below.

Side effect DSL — one clause per cell:

  <verb> "<condition>" [decay] [-> <reward>; …] [else -> <penalty>; …]

  goal     a standing objective of the holder's own: "If <condition>, gain
           <reward>". On the player, an extra checklist row offered every game.
  clause   ANDed onto goals and REQUIRED — the goal is not met until you did both.
           On an enemy it tightens that enemy's goal; on the player it tightens
           EVERY enemy's goal.
  bonus    an OPTIONAL objective — "and if <condition>, gain <reward>" — claimable
           for its reward, free to skip.
  demand   an obligation of the holder's own with a PRICE for missing it: "you
           must <condition>, or <penalty>". The one verb whose payload is what
           you pay rather than what you earn, so it is written after `else ->`.
           Burn's player side.
  instead  an ALTERNATIVE way to satisfy the goal it hangs off — "<goal> or
           instead <condition>". The goal counts as cleared without its own
           condition ever being set, so the engine banks no record of the beat.
           Burn's enemy side.
  decay    completing it sheds one stack. Authored in the `Decrease` COLUMN now
           (see below); the flag is still read, and must agree with it.

Because the verb says what the side DOES, Buff/Debuff drives no mechanic: it is
the HUD tint and the collection filter, nothing more.

`Decrease` says how a status DEPLETES, for the player and for the code at once:

  N/A            never.
  On Completion  a stack goes each game a SIDE of it is completed. It is the truth
                 the sides' `decay` flags are checked against, so a status cannot
                 say one thing in its own column and another inside a cell.
  On Trigger     a stack goes when the body ATTACKS — Bleed. Not when its roll
                 bites: swinging is the trigger, and a Bleed that only wore off on
                 a successful coin flip would last twice as long as it reads.
  Each Turn      a stack goes at the end of every turn the body takes — Stun, which
                 is what "lasts for X turns" means.

The last two are facts about the COMBAT side rather than the goal side, so they set
`wear` instead of the sides' `decay`. ON THE PLAYER BOTH MEAN "PER GAME": the player
does not attack and does not take turns, the game is their turn, and that is what
"This lasts for X games" on Bleed's and Stun's player sides is saying.

`Stackable` says how a second application combines — `Intensity` raises X — and
may carry a CAP: `Max: 3` is a status that stops climbing at three stacks. Burn
needs one because its condition gets EASIER per stack (4-X), so an uncapped Burn
would eventually cost nothing at all.

Reward token DSL (one clause per effect):
  gain_chest [small|medium|large|huge] <n>   -> {type: gain_chest, value, choices}
  gain_chest reward <n>                      -> {type: chest_reward, value}
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
window reads as a time instead of as "1.5", and `{X:chests}` renders a count of
chest POINTS as the chests it buys ("1 Huge Chest and 1 Small Chest").

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
# fractional window read as "1 hour 30 minutes" instead of "1.5"; `chests` turns
# a count of chest POINTS into the chests it buys (§8.2).
FORMATS = ("hours", "chests")


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

MODES = ("goal", "clause", "bonus", "demand", "instead")
# The verbs that name a REQUIREMENT rather than an offer: nothing is handed over
# for meeting one, so a `-> reward` on either is an authoring mistake rather than
# a payout to be silently dropped.
UNPAID_MODES = ("clause", "instead")
SIDE_RE = re.compile(
    r'^\s*(?P<verb>[a-z_]+)\s+"(?P<condition>[^"]*)"\s*'
    r'(?P<flags>(?:[a-z_]+\s*)*?)\s*'
    r'(?:(?P<arrow>else\s*->|->)\s*(?P<payload>.*))?$', re.S)


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
                         '<verb> "<condition>" [decay] [-> <reward>] '
                         '[else -> <penalty>]' % (where, s))
    mode = m.group("verb").lower()
    if mode not in MODES:
        raise ValueError("statuses2.0 %s: unknown verb %r (known: %s)"
                         % (where, mode, ", ".join(MODES)))
    flags = m.group("flags").split()
    unknown = [f for f in flags if f.lower() != "decay"]
    if unknown:
        raise ValueError("statuses2.0 %s: unknown flag(s) %s" % (where, unknown))
    # ONE arrow per cell, and which arrow it is says whether the payload is earned
    # or owed. A side that both pays and charges is not a shape any status wants,
    # and allowing it would make "what happens when I meet this" ambiguous.
    pays = (m.group("arrow") or "").startswith("else")
    reward, reward_text = parse_reward(None if pays else m.group("payload"))
    penalty, penalty_text = parse_reward(m.group("payload") if pays else None)
    if mode in UNPAID_MODES and reward:
        raise ValueError("statuses2.0 %s: a `%s` is a requirement, not a "
                         "payout — move the reward to a `bonus` or a `goal`"
                         % (where, mode))
    if penalty and mode != "demand":
        raise ValueError("statuses2.0 %s: only a `demand` charges for being "
                         "missed — a `%s` has no `else ->`" % (where, mode))
    if mode == "demand" and not penalty:
        raise ValueError("statuses2.0 %s: a `demand` is an obligation with a "
                         "price — write what missing it costs after `else ->`"
                         % where)
    return {
        "mode": mode,
        "condition": normalise_holes(m.group("condition")),
        "reward": reward,
        "reward_text": reward_text,
        "penalty": penalty,
        "penalty_text": penalty_text,
        "decay": any(f.lower() == "decay" for f in flags),
    }


# --- how a status depletes (the `Decrease` column) -------------------------
#
# One column, two readers: it is the sentence the player is shown ("Loses a stack
# each game you complete it") and the rule the engine runs. Every value it can
# take maps to a DECAY answer per side, and an unknown one is refused rather than
# read as "never" — a typo that silently made a status permanent is exactly the
# kind of content bug a generator is here to catch.
# Each value maps to (on_completion, wear) where:
#
#   on_completion  completing a SIDE sheds a stack — the `decay` flag the sides
#                  carry, and the only mode that existed before Bleed and Stun.
#   wear           how a stack is worn away by the BOARD instead, one of
#                  "" (never), "attack" or "turn". See StatusData.wear.
#
# The two are not alternatives dressed up as one column, and the split is the
# whole reason this is a table rather than a bool. `On Completion` is a fact about
# the GOAL side: answer the row on the report and a stack goes. `On Trigger` and
# `Each Turn` are facts about the COMBAT side: the body attacks, or the body takes
# a turn, and a stack goes whether or not any goal was ever answered.
#
# ON THE PLAYER BOTH OF THE NEW MODES MEAN "PER GAME", because the player does not
# attack and does not take turns — the game is their turn. That is what "This lasts
# for X games" on Bleed's and Stun's player sides is saying, and it is why one
# column can carry a rule for each end of the board.
DECREASE_RULES = {
    "": (False, ""),
    "n/a": (False, ""),
    "none": (False, ""),
    "never": (False, ""),
    "on completion": (True, ""),
    "on trigger": (False, "attack"),
    "each turn": (False, "turn"),
}


def parse_decrease(raw, name):
    """('On Completion', 'Burn') -> (prose, decays: bool, wear: str)."""
    prose = _clean(raw) or "N/A"
    key = prose.strip().lower()
    if key not in DECREASE_RULES:
        raise ValueError("statuses2.0 %s: unknown Decrease %r (known: %s)"
                         % (name, prose, ", ".join(sorted(
                             k for k in DECREASE_RULES if k))))
    decays, wear = DECREASE_RULES[key]
    return prose, decays, wear


# `Max: 3` anywhere in the Stackable cell caps the climb. Written as a search
# rather than a match so `Intensity, Max: 3` reads the same as a bare `Max: 3`:
# the cap and the way stacks combine are two facts, and the sheet may say both.
MAX_RE = re.compile(r"max\s*:?\s*(\d+)", re.I)


def parse_max_stacks(raw, name):
    """The stack ceiling the Stackable cell authors, or 0 for no ceiling."""
    s = _clean(raw)
    if not s:
        return 0
    m = MAX_RE.search(s)
    if not m:
        return 0
    cap = int(m.group(1))
    if cap <= 0:
        raise ValueError("statuses2.0 %s: a Max of %d is a status that cannot "
                         "exist" % (name, cap))
    return cap


# --- the COMBAT side ------------------------------------------------------
#
# A status used to be goals and nothing else: it never touched a number on the
# board. It touches four of them now, and the `Enemy Combat Effect` cell is where
# each one is authored. One clause per number, semicolons between:
#
#     <field> +<amount>   an ADDITIVE bonus, scaling with the stack count
#     <field> x<factor>   a flat MULTIPLIER, the same at every stack
#     <flag>              a bare rule with no number behind it
#
# The additive amounts may be literals or {expr} holes over X and are stored as
# EXPRESSIONS either way, evaluated at the live stack count by StatusData. The
# multipliers are plain floats and deliberately do NOT scale: Marked doubles
# damage at one stack and at four, because a doubling that compounds per stack
# turns a 1-damage hit economy into a 16-damage one on the fourth application.

# field -> whether it takes `+` (additive, per stack) or `x` (multiplier, flat).
COMBAT_ADD_FIELDS = {
    # What this thing's own hits land for. Strength on an enemy is the hit it
    # makes on the player each turn it spends in the front column.
    "damage_dealt",
    # What hits AIMED AT this thing land for, before any multiplier.
    "damage_taken",
    # Shield points granted when the status lands. Spent absorbing damage and not
    # refilled — the shield is what the status GAVE you, not what it is.
    "shield",
    # Extra columns closed per step. Speed 2 walks three columns a turn.
    "tile_move",
    # WHAT THIS THING DOES TO ITSELF WHEN IT SWINGS — Bleed's "50% chance to take 1
    # Damage when attacking". The amount is PER ROLL and the roll happens ONCE PER
    # STACK, which is why it is authored as a flat `+1` rather than as `+{X}`: three
    # Bleed is three coin flips for 1 each, not one flip for 3. That makes it the
    # one additive field whose stack count is not in the expression, and the reason
    # is the curve — a single roll for X damage is a status that does nothing four
    # times and then takes your run, where three rolls for 1 is a steady tax.
    "recoil",
}
COMBAT_MULT_FIELDS = {"damage_taken", "damage_dealt"}
# `key=value` options a clause may carry after its amount. One today.
COMBAT_OPTIONS = {
    # The percentage chance ONE roll of `recoil` actually bites. Absent means
    # certain, which is what every other combat number already means.
    "chance",
}
# Bare flags: a rule, not a number.
COMBAT_FLAGS = {
    # Damage aimed at this thing ignores shields outright — it does not spend
    # them, it goes past them. Marked's second half.
    "pierce_shields",
    # This thing does not act on its turn: no step, no swing. Stun's whole combat
    # side, and the same effect the ad-hoc `entry["stun"]` counter has had since
    # Scroll of Scare Monster shipped — see StatusData.skips_turn.
    "skip_turn",
}


def parse_combat(raw, where):
    """Parse one `Enemy Combat Effect` cell into the dict StatusData runs on.

    {} for an empty cell: most statuses will never have a combat side, and a
    blank cell has to read as "this one does nothing on the board" rather than as
    an authoring mistake.
    """
    s = _clean(raw)
    if not s:
        return {}
    out = {}
    for clause in [c.strip() for c in s.split(";") if c.strip()]:
        toks = clause.split()
        field = toks[0].lower()
        # `key=value` options are split off first, so a clause carrying one still
        # reads as `<field> <amount>` below rather than as a three-token error.
        options = {}
        rest = []
        for t in toks[1:]:
            if "=" in t:
                k, _, v = t.partition("=")
                k = k.strip().lower()
                if k not in COMBAT_OPTIONS:
                    raise ValueError("statuses2.0 %s: unknown combat option %r "
                                     "(known: %s)"
                                     % (where, k, ", ".join(sorted(COMBAT_OPTIONS))))
                options[k] = v.strip()
            else:
                rest.append(t)
        toks = [field] + rest
        if len(toks) == 1:
            if field not in COMBAT_FLAGS:
                raise ValueError(
                    "statuses2.0 %s: %r takes an amount, or is not a known combat "
                    "flag (known flags: %s)"
                    % (where, clause, ", ".join(sorted(COMBAT_FLAGS))))
            out[field] = True
            continue
        if len(toks) != 2:
            raise ValueError("statuses2.0 %s: cannot parse combat clause %r — "
                             "expected `<field> +<n>`, `<field> x<n>` or a flag"
                             % (where, clause))
        for k, v in options.items():
            try:
                out["%s_%s" % (field, k)] = int(v)
            except ValueError:
                raise ValueError("statuses2.0 %s: %s=%r is not a whole number (%r)"
                                 % (where, k, v, clause))
        amount = toks[1]
        if amount.startswith("x"):
            if field not in COMBAT_MULT_FIELDS:
                raise ValueError("statuses2.0 %s: %r takes no xN multiplier "
                                 "(known: %s)"
                                 % (where, field, ", ".join(sorted(COMBAT_MULT_FIELDS))))
            try:
                out[field + "_mult"] = float(amount[1:])
            except ValueError:
                raise ValueError("statuses2.0 %s: %r is not a multiplier (%r)"
                                 % (where, amount, clause))
            continue
        if not amount.startswith("+"):
            raise ValueError("statuses2.0 %s: combat amount %r needs a leading + "
                             "or x (%r)" % (where, amount, clause))
        if field not in COMBAT_ADD_FIELDS:
            raise ValueError("statuses2.0 %s: unknown combat field %r (known: %s)"
                             % (where, field, ", ".join(sorted(COMBAT_ADD_FIELDS))))
        kind, val = _amount(amount[1:])
        # Literal or hole, it is stored as an expression string: one evaluator at
        # runtime rather than two code paths that have to agree.
        out[field] = str(val)
    return out


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
        # `gain_chest reward <n>` is the sheet's [chest reward] (§8.2): <n> chest
        # POINTS spent on the size ladder, not <n> chests of one size. It is a
        # different effect with a different handler, so it forks here rather than
        # becoming a fifth entry in CHEST_CHOICES.
        if size == "reward":
            eff = {"type": "chest_reward"}
            put(eff, "value", amount)
            # The words are the equation's, not this generator's: `:chests` hands
            # the point count to Data.chest_reward_text at the live stack count,
            # so "+1 Large Chest" and "+1 Huge Chest and 1 Small Chest" are the
            # same authored string read at three stacks and at five.
            return eff, "+%s" % _formatted_word(amount, "chests")
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

    # `gain_max_hp` raises the cap AND heals by the same amount, because that is
    # what "+2 Max Health" means to everyone who has played a roguelike: the new
    # container comes full. `gain_empty_max_hp` is the other half of the split —
    # the container without the Health to fill it — so an item that wants the
    # bare cap says so rather than the healing being the thing you opt out of.
    if verb in ("gain_hp", "gain_max_hp", "gain_empty_max_hp", "gain_gold"):
        if not rest:
            raise ValueError("status reward: %s needs an amount in %r" % (verb, clause))
        eff = {"type": verb}
        put(eff, "value", rest[0])
        label = {"gain_hp": "Health", "gain_max_hp": "Max Health",
                 "gain_empty_max_hp": "empty Max Health", "gain_gold": "Gold"}[verb]
        return eff, "+%s %s" % (_amount_word(rest[0]), label)

    # --- costs: the same amounts pointed the other way -------------------
    # Events need to charge for things (docs/event-sheet-authoring.md §5) and a
    # curse is nothing BUT a cost, so the payout vocabulary grows a mirror rather
    # than a second parser. Statuses are free to use these too; none do yet.
    if verb in ("lose_hp", "lose_max_hp", "lose_gold"):
        if not rest:
            raise ValueError("reward DSL: %s needs an amount in %r" % (verb, clause))
        label = {"lose_hp": "Health", "lose_max_hp": "Max Health",
                 "lose_gold": "Gold"}[verb]
        # `all` is a cost that names a POOL rather than a number — the price is
        # whatever the player is holding when the choice is taken, which no
        # literal and no {X} hole can say, since both are settled at generation
        # time. Only Gold takes it: an event that charges everything you have is
        # a real trade, whereas `lose_hp all` is just a death with extra steps.
        if rest[0].strip().lower() == "all":
            if verb != "lose_gold":
                raise ValueError("reward DSL: `all` is a lose_gold amount only, "
                                 "not %s (%r)" % (verb, clause))
            return {"type": verb, "all": True}, "-All %s" % label
        eff = {"type": verb}
        put(eff, "value", rest[0])
        return eff, "-%s %s" % (_amount_word(rest[0]), label)

    # DAMAGE, as opposed to `lose_hp`'s bill. The difference is the path it takes:
    # damage is resolved on the battlefield, so the tries (§3) absorb it and the
    # player's own statuses scale it, where `lose_hp` comes straight off Health
    # whatever is standing in front of it. Burn's "or take 3 Damage" is the first
    # cell to want the former — a burn is felt in combat, at the end of it.
    if verb == "take_damage":
        if not rest:
            raise ValueError("reward DSL: take_damage needs an amount in %r" % clause)
        eff = {"type": "take_damage"}
        put(eff, "value", rest[0])
        return eff, "take %s Damage" % _amount_word(rest[0])

    if verb == "lose_stat":
        if len(rest) < 2:
            raise ValueError("reward DSL: lose_stat needs <stat> <n> in %r" % clause)
        stat = rest[0].lower()
        eff = {"type": "lose_stat", "stat": stat}
        put(eff, "value", rest[1])
        fallback = stat.replace("_", " ").title()
        one, many = STAT_LABELS.get(stat, (fallback, fallback + "s"))
        return eff, "-%s %s" % (_amount_word(rest[1]), _plural(rest[1], one, many))

    # --- the rest of the 2.0 noun vocabulary -----------------------------
    if verb == "heal_full":
        return {"type": "heal_full"}, "Heal to full"

    # `gain_loot` is a CATEGORY, not a synonym for gain_scroll: it resolves to
    # whatever loot types exist — three alphabets now — and rolls per unit.
    # Authoring it means an event row widens on its own as more are added (§5).
    #
    # THE THREE NAMED KINDS ARE ITS SIBLINGS, not its subsets: `gain_scroll`,
    # `gain_pill` and `gain_potion` each pay in one alphabet and nothing else.
    # EffectSystem has registered all three since potions landed; only this parser
    # was still scroll-and-category, so a sheet cell asking for a potion raised
    # "unknown reward verb" for a payout the runtime could already make.
    LOOT_KINDS = {
        "gain_loot": ("Loot", "Loot"),
        "gain_scroll": ("Scroll", "Scrolls"),
        "gain_pill": ("Pill", "Pills"),
        "gain_potion": ("Potion", "Potions"),
    }
    if verb in LOOT_KINDS:
        amount = rest[0] if rest else "1"
        eff = {"type": verb}
        put(eff, "value", amount)
        one, many = LOOT_KINDS[verb]
        return eff, "+%s %s" % (_amount_word(amount), _plural(amount, one, many))

    if verb == "obtain_item":
        return {"type": "obtain_item"}, "+1 Item"

    # A NAMED items2.0 relic, handed straight over. The one reward verb that says
    # WHICH item, for the events built around a specific one (Golden Idol).
    if verb == "gain_item":
        if not rest:
            raise ValueError("reward DSL: gain_item needs an item id in %r" % clause)
        iid = rest[0].strip().lower()
        return {"type": "gain_item", "item": iid}, "+%s" % _title(iid)

    # What every CURSE costs (docs/event-sheet-authoring.md §6): a fresh enemy at
    # the run's current difficulty, straight onto the following stack. A curse's
    # bill is a body on the board rather than a number off a bar, so there is one
    # verb for it and every curse in the sheet writes it.
    if verb == "spawn_enemy":
        # An optional `tag=<synergy tag>` narrows the roll to the enemies carrying
        # that tag (Punch Off's robots), in whichever order the cell writes the two
        # — `spawn_enemy tag=robot 1` and `spawn_enemy 1 tag=robot` are the same
        # clause. Without it the roll is the plain "anything at this difficulty"
        # every curse writes.
        tag = ""
        counts = []
        for tok in rest:
            if tok.lower().startswith("tag="):
                tag = tok.split("=", 1)[1].strip().lower()
            else:
                counts.append(tok)
        amount = counts[0] if counts else "1"
        eff = {"type": "spawn_enemy"}
        put(eff, "value", amount)
        if tag:
            eff["tag"] = tag
        one = "a random %s enemy" % tag if tag else "a random enemy"
        many = "%s random %senemies" % (_amount_word(amount), tag + " " if tag else "")
        return eff, "Spawn %s" % _plural(amount, one, many)

    # The Relic Trader's swap (§5). The pairing — which of YOUR relics for which of
    # HIS — is rolled when the event opens and lives on EventSystem; the sheet only
    # says which of the three offers this button is, and writes the sentence with
    # <give> / <get> holes for the names to land in.
    if verb == "trade_relic":
        slot = int(rest[0]) if rest and re.fullmatch(r"\d+", rest[0]) else 1
        return {"type": "trade_relic", "slot": slot}, "Trade <give> for <get>"

    # A relic off the rollable pool, handed straight over — the sibling of
    # `gain_item` for the payout that names no relic at all. NOT `gain_chest
    # small`, which banks a chest the reward screen opens after the event: Ranwid
    # eats what you gave him and presses the relic into your hand there and then,
    # and the difference between the two is a screen and a delay.
    #
    # Writes what it rolled into the {ITEM} hole, so the prose can name it.
    if verb == "gain_random_item":
        amount = rest[0] if rest else "1"
        eff = {"type": "gain_random_item"}
        put(eff, "value", amount)
        return eff, "+%s random %s" % (_amount_word(amount),
                                       _plural(amount, "Relic", "Relics"))

    # The two costs paid in KIND rather than in numbers: one potion out of the
    # pack, one tradeable relic out of it. Which one is rolled when the event
    # opens and held on EventSystem — the same shape the Relic Trader's pairing
    # has, and for the same reason: the button has to be able to name what it is
    # about to take before it is pressed. The <potion> / <relic> holes are where
    # the name lands.
    if verb == "lose_potion":
        return {"type": "lose_potion"}, "-<potion>"

    if verb == "lose_relic":
        return {"type": "lose_relic"}, "-<relic>"

    if verb == "random_item_choice":
        amount = rest[0] if rest else "3"
        eff = {"type": "random_item_choice"}
        put(eff, "count", amount)
        return eff, "+1 of %s Items" % _amount_word(amount)

    if verb == "apply_status":
        if not rest:
            raise ValueError("reward DSL: apply_status needs a status in %r" % clause)
        eff = {"type": "apply_status", "status": rest[0].lower()}
        put(eff, "value", rest[1] if len(rest) > 1 else "1")
        return eff, "+%s %s" % (_amount_word(rest[1] if len(rest) > 1 else "1"),
                                rest[0].replace("_", " ").title())

    # --- the OBJECT vocabulary (docs/object-sheet-authoring.md) ----------
    #
    # An object is a machine you stand in front of, and the six verbs below are
    # the things a machine does that a room cannot: it pays in loose change, it
    # picks which relic fell out, it holds a bank, it jams, it blows up. They
    # live here with the rest of the reward DSL rather than in the object
    # generator so an event can reach for them too — Arcade Room's
    # `spawn_object` is written in an events2.0 cell.

    # `gain_pickups 2-4 hp|gold` — N loose pickups, each one independently
    # rolled from the listed kinds. NOT "2-4 Health and 2-4 Gold" and not a
    # chest: the Blood Donation Machine bursting should read like Isaac's floor
    # after a bomb, a scatter of hearts and coins in no particular ratio, and a
    # count with a menu attached is the only shape that says that.
    if verb == "gain_pickups":
        if len(rest) < 2:
            raise ValueError("reward DSL: gain_pickups needs <lo>-<hi> "
                             "<kind>|<kind> in %r" % clause)
        lo, hi = _range(rest[0], clause)
        kinds = [k.strip().lower() for k in rest[1].split("|") if k.strip()]
        unknown = [k for k in kinds if k not in PICKUP_KINDS]
        if unknown:
            raise ValueError("reward DSL: unknown pickup kind(s) %s in %r "
                             "(known: %s)"
                             % (unknown, clause, ", ".join(sorted(PICKUP_KINDS))))
        eff = {"type": "gain_pickups", "min": lo, "max": hi, "kinds": kinds}
        return eff, "+%s %s" % (_span(lo, hi),
                                " or ".join(PICKUP_KINDS[k] for k in kinds))

    # `gain_item_of blood_bag|iv_bag` — ONE named relic, chosen at random from
    # the list. The sibling of `gain_item`, for the payout that is a specific
    # small set rather than a specific thing.
    if verb == "gain_item_of":
        ids = [i.strip().lower() for i in " ".join(rest).split("|") if i.strip()]
        if len(ids) < 2:
            raise ValueError("reward DSL: gain_item_of needs at least two "
                             "`|`-separated item ids in %r (use gain_item for "
                             "one)" % clause)
        return ({"type": "gain_item_of", "items": ids},
                "+%s" % " or ".join(_title(i) for i in ids))

    # Gold into the Donation Machine's bank — which is the one number in this
    # build that outlives the run. Both halves live in the verb because they are
    # one act: the purse pays and the bank fills, and a cell that wrote them as
    # `lose_gold 1; bank_gold 1` could get them out of step.
    if verb == "donate_gold":
        amount = rest[0] if rest else "1"
        eff = {"type": "donate_gold"}
        put(eff, "value", amount)
        return eff, "Donate %s Gold" % _amount_word(amount)

    # The other direction, and the reason to bomb one: gold back OUT of the
    # bank. Capped at what the bank actually holds — you can only take what is
    # in it — which is settled at runtime, so the words quote the roll.
    if verb == "bank_payout":
        if not rest:
            raise ValueError("reward DSL: bank_payout needs <lo>-<hi> in %r" % clause)
        lo, hi = _range(rest[0], clause)
        return ({"type": "bank_payout", "min": lo, "max": hi},
                "+%s Gold from the machine" % _span(lo, hi))

    # A jammed machine still stands there; it just will not take another coin
    # for the rest of the run.
    if verb == "jam_object":
        return {"type": "jam_object"}, "the machine jams"

    # Gone. Bare = this machine only (another Blood Donation Machine may still
    # turn up); `run` = every object of this kind is off the run, which is what
    # bombing the Donation Machine buys.
    if verb == "destroy_object":
        scope = rest[0].lower() if rest else ""
        if scope not in ("", "run"):
            raise ValueError("reward DSL: destroy_object takes `run` or nothing, "
                             "not %r (%r)" % (scope, clause))
        eff = {"type": "destroy_object"}
        if scope:
            eff["scope"] = "run"
        return eff, ("no more this run" if scope else "the machine is destroyed")

    # Spending a Bomb OFF the battlefield. `lose_stat bombs 1` would take the
    # bomb without ever telling anything it was used, and Blood Bombs says "when
    # using a Bomb" — so this fires the same bomb_used trigger the board does,
    # with no enemy behind it.
    if verb == "spend_bomb":
        amount = rest[0] if rest else "1"
        eff = {"type": "spend_bomb"}
        put(eff, "value", amount)
        return eff, "-%s %s" % (_amount_word(amount), _plural(amount, "Bomb", "Bombs"))

    # `spawn_object tag=arcade 2-3` — put objects in front of the player. Each
    # slot rolls rarity and then draws from that rarity's bucket of the tag,
    # falling down the ladder when a bucket is empty, so the same roll an item
    # reward walks decides what is in the room.
    if verb == "spawn_object":
        tag = ""
        counts = []
        for tok in rest:
            if tok.lower().startswith("tag="):
                tag = tok.split("=", 1)[1].strip().lower()
            else:
                counts.append(tok)
        if not tag:
            raise ValueError("reward DSL: spawn_object needs tag=<tag> in %r" % clause)
        lo, hi = _range(counts[0], clause) if counts else (1, 1)
        return ({"type": "spawn_object", "tag": tag, "min": lo, "max": hi},
                "%s %s %s" % (_span(lo, hi), tag,
                              "machine" if hi == 1 else "machines"))

    # An explicit no-op, so "this choice does nothing" can be authored rather
    # than left blank and read as unfinished.
    if verb == "nothing":
        return {"type": "none"}, "Nothing"

    raise ValueError("reward DSL: unknown verb %r in %r" % (verb, clause))


# What a loose pickup can be, and what it is called on a button. A closed list
# for the same reason GATE_STATS is one: a typo'd kind would roll nothing and
# say nothing about it.
PICKUP_KINDS = {"hp": "Health", "gold": "Gold"}


def _range(tok: str, clause: str):
    """`2-4` -> (2, 4); a bare `3` -> (3, 3). Literals only.

    Deliberately not {expr}-aware. A range is a spread the player is quoted
    up front ("+2-4 Health or Gold"), and a spread whose ends move per press is
    a number nobody can read off a button.
    """
    tok = tok.strip()
    m = re.fullmatch(r"(\d+)\s*-\s*(\d+)", tok)
    if m:
        lo, hi = int(m.group(1)), int(m.group(2))
        if lo > hi:
            raise ValueError("reward DSL: range %r counts down (%r)" % (tok, clause))
        return lo, hi
    if re.fullmatch(r"\d+", tok):
        return int(tok), int(tok)
    raise ValueError("reward DSL: %r is not <n> or <lo>-<hi> (%r)" % (tok, clause))


def _span(lo: int, hi: int) -> str:
    return str(lo) if lo == hi else "%d-%d" % (lo, hi)


# id -> the Name cell it was slugified from, populated by the generators before
# they parse (see generate_event2_tres.cross_sheet_ids). Title-casing a slug is a
# guess, and it guesses wrong the moment a name is not word-per-word capitalised:
# `iv_bag` came out as "Iv Bag". The sheet already knows the answer, so ask it,
# and keep the guess only for the ids no sheet claims.
ITEM_NAMES = {}


def _title(slug: str) -> str:
    """`golden_idol` -> `Golden Idol`, `iv_bag` -> `IV Bag`. How a reward line
    names an item the sheet referred to by id, so the button reads as the thing
    rather than as the slug."""
    known = ITEM_NAMES.get(slug)
    if known:
        return known
    return " ".join(w.capitalize() for w in slug.split("_") if w)


def _is_amount(tok: str) -> bool:
    return bool(HOLE.fullmatch(tok.strip()) or re.fullmatch(r"-?\d+", tok.strip()))


def _amount_word(tok: str) -> str:
    """How an amount reads inside reward_text: a literal stays a literal, a hole
    stays a hole so StatusData can substitute it at the live stack count."""
    m = HOLE.fullmatch(tok.strip())
    return "{%s}" % to_godot_expr(m.group(1)) if m else tok.strip()


def _formatted_word(tok: str, fmt: str) -> str:
    """Like _amount_word, but the amount always lands as a `:fmt` hole — even a
    literal one, since the FORMAT is what does the reading. A chest reward of 5
    is not the word "5", it is "1 Huge Chest and 1 Small Chest", and only
    StatusData.resolve knows how to say that."""
    m = HOLE.fullmatch(tok.strip())
    return "{%s:%s}" % (to_godot_expr(m.group(1)) if m else tok.strip(), fmt)


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
    combat = parse_combat(row.get("Enemy Combat Effect"), "%s / Enemy Combat Effect" % name)
    if not on_player and not on_enemy and not combat:
        raise ValueError("statuses2.0 %s: neither side does anything" % name)
    # The Decrease column is the truth about depletion, and the sides' `decay`
    # flags are checked against it rather than trusted alongside it. A cell that
    # asks to decay under an `N/A` column is a contradiction, and the older cells
    # that carry the flag (Marked's two) simply agree with their column.
    decrease, decays, wear = parse_decrease(row.get("Decrease"), name)
    for which, side in (("On Player Effect", on_player), ("On Enemy Effect", on_enemy)):
        if side.get("decay") and not decays:
            raise ValueError(
                "statuses2.0 %s / %s: the cell says `decay` but Decrease says "
                "%r — say it once, in the column" % (name, which, decrease))
        # A side that can be COMPLETED sheds a stack when the column says so. A
        # `clause` on the player counts: completing the goal it rides is what
        # completes it (§13). An INERT side stays the empty dict the runtime reads
        # as "this side does nothing" — there is nothing there to complete.
        if decays and side:
            side["decay"] = True
    max_stacks = parse_max_stacks(row.get("Stackable"), name)
    # EnemyOnly gates the COMBAT side alone — the goal sides are already authored
    # one per side and say for themselves who they land on. Blank reads as Yes,
    # which is the conservative half: a status nobody thought about does not
    # start taxing the player's own Health.
    enemy_only = (_clean(row.get("EnemyOnly")) or "Yes").strip().lower() \
        not in ("no", "false", "0")
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
    lines.append("max_stacks = %d" % max_stacks)
    lines.append('decrease = "%s"' % gd_str(decrease))
    lines.append('wear = "%s"' % gd_str(wear))
    lines.append('combat_text = "%s"' % gd_str(_clean(row.get("Combat"))))
    lines.append("enemy_only = %s" % gd_value(enemy_only))
    lines.append("on_player = %s" % gd_value(on_player))
    lines.append("on_enemy = %s" % gd_value(on_enemy))
    lines.append("combat = %s" % gd_value(combat))
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
    sheet = wb["statuses"]
    headers = [str(c.value).strip() if c.value is not None else "" for c in sheet[1]]
    for needed, setup in (("On Player Effect", "_statuses_sheet_setup.py"),
                          ("On Enemy Effect", "_statuses_sheet_setup.py"),
                          ("Combat", "_statuses2_combat_setup.py"),
                          ("Decrease", "_statuses2_burn_setup.py"),
                          ("EnemyOnly", "_statuses2_combat_setup.py"),
                          ("Enemy Combat Effect", "_statuses2_combat_setup.py")):
        if needed not in headers:
            raise SystemExit(
                "statuses2.0 has no %r column — run tools/%s first." % (needed, setup))

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

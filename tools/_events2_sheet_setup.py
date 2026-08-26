#!/usr/bin/env python3
"""One-shot sheet editor: lay down the `events2.0` schema and its authored events.

An EVENT is the payoff for walking into a corner of the map. 40% of the graph's
games are leaves — one connection, so visiting one costs two games (there and
back) and pays one game's reward. Hanging an event off those nodes is what makes
the detour a choice instead of a mistake (docs/event-sheet-authoring.md).

THE SHAPE OF THE SHEET: one row per EVENT, with the choices in numbered column
groups — `Choice 1 | Repeat 1 | Result 1 | Effect 1`, then the same four for 2, 3
and 4. Every piece of prose gets a cell of its own (which is the thing that
matters — the old `events` sheet failed because its choices could not fit in the
sheet at all and ended up hard-coded in a Python dict), and one event is one row,
so the sheet sorts and filters like every other `*2.0` sheet.

Four groups is a soft cap chosen to fit the real events; a fifth is four more
columns and one more turn of the generator's loop, not a redesign. The generator
reads groups until it meets a blank `Choice N`.

The `Effect` cells speak the SAME reward-token DSL as `statuses2.0`
(`gain_chest small 1`, `gain_stat bash 1`, `gain_hp 2`, …), so a chest an event
pays is the chest an item pays. `{X}` holes work as they do there — inside an
event, X is THE NUMBER OF TIMES THIS CHOICE HAS ALREADY BEEN TAKEN, which is what
lets one authored group escalate. Two event-only forms carry the rest:

    needs <Choice> <op> <n>                     gate a choice on the event's own
                                                state, which is how a two-stage
                                                event fits on one row
    add_goal "<cond>" for <n> games -> <reward> hand the player an objective that
                                                outlives the modal
    add_curse <curse> [for <n> games]           the same, inverted: an objective
                                                you want to NOT meet. Authored in
                                                `curses2.0` and referenced by id,
                                                the way apply_status references
                                                statuses2.0
    play_game tag=<tag> -> <reward>             send the player off to a game that
                                                isn't on their route, and pay when
                                                they beat it
    chance <p>% -> <reward>                     a gamble: roll p percent, pay the
                                                reward on a win and nothing on a
                                                loss. `{X}` in the percent climbs
                                                it per press, exactly as it climbs
                                                a cost

WHY XML SURGERY AND NOT openpyxl: Roguelikes.xlsx carries seven charts and a
dozen table parts that an openpyxl load/save round-trip silently drops. See
tools/_xlsx_surgery.py.

Run: python3 tools/_events2_sheet_setup.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _xlsx_surgery import Workbook  # noqa: E402

XLSX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Roguelikes.xlsx")

SHEET = "events2.0"
MAX_CHOICES = 4
# Rung separator inside a Result cell — a choice that can be pressed again says
# one rung per press. The reader is parse_result_cell() in
# tools/generate_event2_tres.py; keep the two in step.
RESULT_SEP = " || "

EVENT_COLS = [
    "Event",        # display name, and the id everything else keys off
    "Game",         # the real game this is lifted from (flavour credit)
    "Tier",         # All, or a comma list of Low / Medium / High / Insane
    "Where",        # Dead End (default) | Any | Game
    # The state gate, beside Tier's ladder gate and Where's map gate: a condition
    # on the RUN that has to hold before the event may appear at all. Unrest Site
    # is the reason it exists — in Slay the Spire 2 it only shows up at 70% HP or
    # below, and nothing else in this sheet could say so. `<stat> <op> <value>`,
    # with a trailing % reading against the maximum. Blank = always eligible.
    "Requirement",  # e.g. hp <= 70%
    "Trigger",      # After (default, once the game is beaten) | Before
    "Rarity",       # Common | Uncommon | Rare
    "Limit",        # times per run: a number, or None for no limit
    "Image",        # art base name under images2.0/events/
    "Prompt",       # the prose at the top of the modal
    # An event that hands out a goal (`add_goal`) resolves LATER, on the
    # checklist, so its two endings can't live in a choice's Result. They are
    # event-level because they belong to the event's voice, not to which option
    # was picked — the Dummy congratulates and insults you in the same words
    # whichever setting you chose. Blank on events that grant no goal.
    #
    # "Met" always means THE CONDITION HAPPENED, never "it went well" — on a
    # curse goal (`add_curse`) meeting the condition is the bad outcome and the
    # payload is a penalty. The sign lives in the token, not in these two names.
    "Goal Met",     # printed when the goal's condition is met
    "Goal Missed",  # printed when its window closes unmet
    # The two endings of a `chance` gamble, and event-level for the same reason
    # Goal Met / Goal Missed are: they belong to the event's voice rather than to
    # which button was pressed. Scrap Ooze is the proof — [Reach Inside] and
    # [Deeper] are two rows of the sheet and one hand in the ooze, and Slay the
    # Spire prints the same two strings for both. Blank on events with no gamble.
    "Chance Won",   # printed when a `chance` roll lands
    "Chance Lost",  # printed when it doesn't
]
# Per choice: the label, what picking it does to the event, the prose it prints,
# and the payload. Blank `Choice N` ends the event's choice list.
CHOICE_COLS = ["Choice", "Repeat", "Result", "Effect"]

HEADERS = EVENT_COLS + [
    "%s %d" % (col, n)
    for n in range(1, MAX_CHOICES + 1)
    for col in CHOICE_COLS
]


# --- Abyssal Baths ----------------------------------------------------------
#
# Slay the Spire 2, the Underdocks. Prompt and the two sourced Result strings are
# the game's own text, verbatim. The event is really TWO STAGES, and modelling it
# honestly is what exercises the Repeat column and the `needs` gate:
#
#   stage 1   [Immerse] first dip.            [Abstain] don't get in, heal.
#   stage 2+  [Linger]  keep going, +1 each.  [Exit Baths] get out.
#
# So Immerse is `Stay` (the event stays open and Immerse is spent, which is what
# makes it a first dip rather than the loop), Linger is `Again` with `{4+X}` for
# the +1-per-Linger climb, and the two exits are gated against each other on
# whether you got in: Abstain's heal is available ONLY to someone who never
# bathed. That gate is load-bearing — without it the line is "bathe until nearly
# dead, then heal", which is exactly what Slay the Spire 2 refuses to allow.
#
# NUMBERS: the GAINS are tuned to this game (Health is 5-10, not 75) — +1 Max
# Health a dip rather than +2, and Abstain heals 3 rather than 10. The COSTS are
# still Slay the Spire 2's (3, then 4, 5, 6…) and have not been rescaled with
# them, which currently makes the water a poor trade at this Health pool. That is
# the next cell to look at if the event plays badly.
BATHS_PROMPT = (
    "You discover a secluded chamber. Steam rises from bubbling pools of hot "
    "liquid that shifts colors with hypnotic rhythm. Barnacled growths hang from "
    "the ceiling, dripping viscous fluid that hisses and writhes when it touches "
    "the surface. The air feels heavy, laden with salt and something unmistakably "
    "organic. As you approach the edge of the largest pool, the liquid ripples. "
    "The waters bubble more intensely as if anticipating your entry."
)

BATHS_IMMERSE = (
    "The liquid burns against your skin, simultaneously freezing and scalding. "
    "Beneath the surface, something brushes against your legs—tendrils? Currents "
    "with purpose? But when the pain subsides, you feel... denser somehow. More "
    "substantial."
)

BATHS_ABSTAIN = (
    "You decline the temptation of the waters, instead gathering crystalline "
    "salts that have formed along the edges. As you apply them to your skin, the "
    "pools churn and froth agitatedly."
)

# Linger's prose is a LADDER — Slay the Spire 2 answers each [Linger] with a
# hotter line rather than repeating one, and the last of them is the warning that
# the next dip kills you. One rung per press, joined with `||` into the single
# Result cell; the last rung stands for every press after it, which is the right
# behaviour for an unbounded ladder (the warning keeps warning).
#
# This is the prose half of `{4+X}`: the numbers already escalated from one
# authored group, and now the voice escalates with them.
#
# PROVENANCE: unlike the Prompt / Immerse / Abstain strings above, these were not
# read off the game or a page — every site carrying them is blocked from this
# environment, so they were reconstructed from search-engine summaries of the
# untapped.gg and wiki.gg event pages. The wording is consistent across several
# independent queries; the ORDER of the first two rungs is the least certain part.
# Check them against the game before treating them as quotation.
BATHS_LINGER = [
    "The temperature keeps rising! How long can you endure before the steam "
    "cooks you from within?",
    "It keeps getting hotter! The pool's bubbling sounds like laughter. IT'S SO "
    "HOT!",
    "You wonder if this is what it's like to live in the Village of Demons? You "
    "have bathed so long you have lost track of time and your mind... It's nice "
    "in here. Really fantastic.",
    "If you bathe any longer you will die.",
]

BATHS_EXIT = "The heat finally gets to you, and you hop out of the bath."


# --- Battleworn Dummy -------------------------------------------------------
#
# Slay the Spire 2, Glory. All four dialogue strings are the game's own, verbatim.
# The MECHANIC is an abstraction rather than a port, because the thing it asks for
# — three turns of combat against a dummy with a chosen HP total — is exactly what
# this game does not simulate. What survives is its actual shape: PICK YOUR OWN
# DIFFICULTY, then go and prove it, on a clock.
#
#   Slay the Spire 2                     here
#   ────────────────────────────────     ──────────────────────────────────────
#   a 75 / 150 / 300 HP dummy            beat a game in 5 / 3 / 1 attempt(s)
#   3 turns to do it                     3 games to do it (`for 3 games`)
#   potion / upgrades / relic            scroll / small chest / large chest
#   fail = no reward                     the goal expires, and pays nothing
#
# `attempts` is the run's existing currency for this (§3.2 — shields ARE the
# tries, and GameLoop2.attempts() already counts them), so "beat a game in 1
# attempt" needs no new bookkeeping, only a checklist row to hang it on.
#
# This is the event that motivates `add_goal … for N games`: the reward is not
# handed over in the modal, it is handed over by the CHECKLIST, up to three games
# later. Hence the Goal Met / Goal Missed columns — the Dummy has to have the last
# word, and the modal is long closed by the time it gets to say it.
DUMMY_PROMPT = (
    "As you approach, it begins to rumble and fizzle and lights up brilliantly! "
    "\"BZZZT! TIME TO TRAIN!!! YOU HAVE 3 TURNS TO DEFEAT ME! CHOOSE A SETTING OR "
    "FACE LETHAL HUMILIATION.\""
)

DUMMY_MET = (
    "\"YOU PASS THE TRAINING! YOU ARE NOW EQUIPPED TO DEFEND THIS FACTORY AGAINST "
    "INTRUDERS!! BE SURE TO HYDRATE AFTER TRAINING SESSIONS!\""
)

DUMMY_MISSED = (
    "\"YOU ARE WEAK!! HUMILIATION HAS BEEN ADMINISTERED!\" The dummy is silent for "
    "a moment and— \"Choose a lower setting next time.\""
)


# --- Unrest Site ------------------------------------------------------------
#
# Slay the Spire 2, the Overgrowth. Prompt and both Result strings verbatim.
#
# This is the event that adds the THIRD kind of goal. An enemy goal is a debt —
# miss it and it follows you and hits. An event goal is a bonus — miss it and it
# simply expires. A CURSE goal is neither: it is a standing objective you want to
# NOT meet, and meeting it costs you. It is the first thing in the run that
# punishes you for doing something rather than for failing to.
#
#   Rest Anyways   heal to full, and carry "if you use a rest site to replenish
#                  health, take 2 damage" for the rest of the run
#   Kill the Trees lose 2 Max Health, take a small chest
#
# `add_curse` is what marks it — the token carries the kind, so the sheet needs
# no "what sort of goal is this" column and the checklist knows to render this
# one purple and in its own section. The curse itself (condition, penalty, how
# long it lasts) is authored once in `curses2.0` and referenced here by id, the
# way an item references a status.
#
# Note this is NOT the shelved `CurseData` / `data/curses` system
# (games-first-redesign.md §5). Same word, different thing: a curse goal is a row
# on the checklist, not a card.
#
# Slay the Spire 2 names its curse "Poor Sleep" and the curse is a card; here it
# is a row on the checklist that expires after 3 games (its `Timer` in
# `curses2.0`), so it is a weight on the next stretch of run rather than a
# permanent tax.
#
# CHANGES FROM THE ORIGINAL, both requested: Max Health lost drops 8 -> 2, and
# the random Relic becomes a small chest — which the outcome text was already
# describing, since the byrd spirits "drop a small box at your feet". At this
# game's 5-10 Max Health, losing 2 is a much steeper cut than 8-of-75 was (20-40%
# against 11%), so it is the sharper of the two options rather than the safe one.
UNREST_PROMPT = (
    "You find a secluded Rest Site and start a fire to get some rest. Once the "
    "fire is started, it begins to swell, reaching not upwards but sideways "
    "towards a grove of oil-seeping trees."
)

UNREST_REST = (
    "All this adventuring has left you exhausted, and despite the oddities, you "
    "decide to sleep. You toss and turn as the fire roars and crackles through "
    "the night. The disgusting trees give off a wretched scent from their "
    "pitch-black sap."
)

UNREST_KILL = (
    "These trees are clearly malicious so you decide to get rid of them. Days "
    "later, you're covered in ash and oily goop. A massive flock of little byrd "
    "spirits rise from the slain trees and drop a small box at your feet. \"Thank "
    "you for freeing us from those trees... cheep cheep!\""
)


# --- Punch Off --------------------------------------------------------------
#
# Slay the Spire 2, the Underdocks. Prompt and both Result strings verbatim.
#
# The new capability here is `play_game`: an event that doesn't hand you a reward
# or a goal but SENDS YOU SOMEWHERE. "I Can Take Them" drops the player into a
# random game tagged `mecha` — a real tag on the games sheet, 14 games carry it —
# which spawns its enemy and is played under the ordinary rules. Beating the
# robots IS beating the game; the loot pays on the far side of it, which is what
# the `->` says.
#
# Afterwards the player CHOOSES: stay at the mecha game if it is connected on the
# map, or return to the node they came from. That is a round trip you are allowed
# to decline, and it rhymes nicely with §1 — events exist because a dead end
# forces a round trip on you, and this is the one that hands the choice back.
#
# The two options are the same bargain the original strikes, in this game's
# currency: take the treasure and wear the Injury, or do the work and take
# everything. Relic -> small chest; relic + potion + combat reward -> 2 small
# chests + 1 loot.
PUNCH_PROMPT = (
    "Two Punch Constructs are duking it out and you see some treasure in between "
    "them... Should you try to nab it?"
)

PUNCH_NAB = (
    "You successfully nab the relic! ...or so you thought. A right-hook clocks "
    "you in the face."
)

PUNCH_FIGHT = "The Constructs turn to you menacingly!"


# --- Scrap Ooze -------------------------------------------------------------
#
# Slay the Spire (the FIRST one — every other event here is from Slay the Spire
# 2). All four strings are the game's own, verbatim, with its inline colour
# markup (#r, #y, @…@) stripped and its NL line breaks flattened.
#
# The new capability is `chance`: a choice that ROLLS. Nothing in the sheet could
# gamble before — an event could charge you, gate you, or hand you an objective,
# but every payout was certain the moment you pressed the button. Scrap Ooze is
# nothing but the gamble, so it could not be authored at all without the token.
#
#   [Reach Inside]  lose 1 Health, 25% for a relic     Stay
#   [Deeper]        lose 2, 3, 4…    35%, 45%, 55%…    Again
#   [Leave]         walk away                          End
#
# WHY TWO CHOICES FOR ONE HAND IN THE OOZE: because Slay the Spire renames the
# button after the first reach, and the sheet already has the shape for that —
# `Stay` spends [Reach Inside] and reveals [Deeper], the same staging Abyssal
# Baths uses for Immerse -> Linger. X counts Deepers already taken, so one
# authored group is the whole ladder.
#
# THE DAMAGE IS THIS GAME'S, THE ODDS ARE THE ORIGINAL'S. Slay the Spire opens at
# 3 HP and climbs by one per attempt against a 75 HP pool — 4% of a character for
# the first grab. Health here is 5-10 (docs/games-first-redesign.md §3), where 3
# is 30-60%, which nobody pays for a 25% shot. So the ladder starts at 1 and
# climbs by one per FAILED reach — 1, 2, 3, 4. The odds are untouched (25%, +10
# per failure), which puts the cost of reaching until it lands at about 6 Health
# over about 2.7 reaches: more than a whole character at the low end of the pool.
#
# A relic is a SMALL CHEST, which is the mapping Punch Off and Unrest Site
# already use — small is one item offered, so it reads as the random relic Slay
# the Spire hands over rather than as a pick. `obtain_item` would have been the
# wrong token: that is Wand of Wishing's any-item-in-the-game picker.
#
# The gamble can kill you, and that is intended — the ladder is unbounded and
# `Again` never stops offering. That is the Abyssal Baths rule (§7): an event
# with a way to die in it belongs at a Dead End, somewhere you had to choose to
# walk toward.
OOZE_PROMPT = (
    "As you walk into the room you hear a gurgling and the grinding of metals. "
    "Before you is a slime-like creature that ate too much scrap for its own "
    "good. From the center of the creature you see glints of strange light, "
    "perhaps something magical? It looks like you can get some treasure if you "
    "just reach inside its... opening. However, the acid and sharp objects may "
    "hurt."
)

OOZE_WON = (
    "Success! After rummaging through the metal and burning acid, you finally "
    "grab hold of a relic and yank it out. You pull your way out of the ooze "
    "damaged but rewarded."
)

OOZE_LOST = (
    "Ouch! All you find is corroded metal and a bit of burning pain. However, "
    "you're still convinced there's a relic..."
)

OOZE_LEAVE = (
    "You decide to leave the area. The slime pays no attention, content with "
    "its meal."
)


EVENTS = [
    {
        "Event": "Abyssal Baths",
        "Game": "Slay the Spire 2",
        "Tier": "All",
        "Where": "Dead End",
        "Requirement": "",
        "Trigger": "After",
        "Rarity": "Common",
        "Limit": "1",
        "Image": "AbyssalBaths",
        "Prompt": BATHS_PROMPT,
        "Goal Met": "",
        "Goal Missed": "",
        "choices": [
            # The first dip. `Stay` keeps the event open and spends the choice,
            # so what's on offer afterwards is Linger, never Immerse again.
            ("Immerse", "Stay", BATHS_IMMERSE, "gain_max_hp 1; lose_hp 3"),
            # The loop. X counts Lingers already taken: 4, then 5, then 6, …
            # and the Result is a ladder climbing beside it, one rung per press.
            ("Linger", "Again", RESULT_SEP.join(BATHS_LINGER),
             "needs Immerse > 0; gain_max_hp 1; lose_hp {4+X}"),
            # The heal, and only for someone who stayed out of the water.
            ("Abstain", "", BATHS_ABSTAIN, "needs Immerse = 0; gain_hp 3"),
            # The way out once you're in.
            ("Exit Baths", "", BATHS_EXIT, "needs Immerse > 0; nothing"),
        ],
    },
    {
        "Event": "Battleworn Dummy",
        "Game": "Slay the Spire 2",
        "Tier": "All",
        "Where": "Dead End",
        "Requirement": "",
        "Trigger": "After",
        "Rarity": "Common",
        "Limit": "1",
        "Image": "BattlewornDummy",
        "Prompt": DUMMY_PROMPT,
        "Goal Met": DUMMY_MET,
        "Goal Missed": DUMMY_MISSED,
        # The settings keep their in-game names. The rest of each in-game label
        # ("Fight a 75 HP dummy. Procure 1 random Potion.") is Slay the Spire 2's
        # MECHANICAL line, not its dialogue, and the modal renders ours off the
        # Effect instead — "Beat a game in 5 attempts or fewer. Gain 1 Potion."
        # Result cells are blank because picking a setting there starts a fight
        # rather than printing prose; here it hands over the goal and the
        # checklist takes it from there.
        #
        # SETTING 1 PAYS A POTION, and that is the source game's own payout: the
        # dummy's easiest rung procures a potion in Slay the Spire 2. It was a
        # scroll here only because scrolls were the sole alphabet when this row was
        # written; potions exist now, so the rung says what it always meant.
        "choices": [
            ("Setting 1", "", "",
             'add_goal "beat a game in 5 attempts or fewer" for 3 games'
             ' -> gain_potion 1'),
            ("Setting 2", "", "",
             'add_goal "beat a game in 3 attempts or fewer" for 3 games'
             ' -> gain_chest small 1'),
            ("Setting 3", "", "",
             'add_goal "beat a game in 1 attempt" for 3 games'
             ' -> gain_chest large 1'),
        ],
    },
    {
        "Event": "Unrest Site",
        "Game": "Slay the Spire 2",
        "Tier": "All",
        "Where": "Dead End",
        # The whole event is a bargain about being hurt, so it only shows up to
        # someone who is. Without this gate "heal to full" is a free top-up and
        # the curse buys nothing.
        "Requirement": "hp <= 70%",
        "Trigger": "After",
        "Rarity": "Common",
        "Limit": "1",
        "Image": "UnrestSite",
        "Prompt": UNREST_PROMPT,
        # A curse goal has no endings to print: it never expires, and every time
        # its condition is met the penalty simply lands.
        "Goal Met": "",
        "Goal Missed": "",
        "choices": [
            ("Rest Anyways", "", UNREST_REST, "heal_full; add_curse poor_sleep"),
            ("Kill the Trees", "", UNREST_KILL,
             "lose_max_hp 2; gain_chest small 1"),
        ],
    },
    {
        "Event": "Punch Off",
        "Game": "Slay the Spire 2",
        "Tier": "All",
        "Where": "Dead End",
        # "Only appears at Floor 6 or later" — depth, which this run measures in
        # games played rather than floors.
        "Requirement": "games >= 6",
        "Trigger": "After",
        "Rarity": "Common",
        "Limit": "1",
        "Image": "PunchOff",
        "Prompt": PUNCH_PROMPT,
        "Goal Met": "",
        "Goal Missed": "",
        "choices": [
            ("Nab", "", PUNCH_NAB, "add_curse injury; gain_chest small 1"),
            ("I Can Take Them", "", PUNCH_FIGHT,
             "play_game tag=mecha -> gain_loot 1; gain_chest small 2"),
        ],
    },
    {
        "Event": "Scrap Ooze",
        "Game": "Slay the Spire",
        "Tier": "All",
        "Where": "Dead End",
        # An Act 1 event in the original, and Act 1 is where you can least
        # afford the Health — but this run has no acts, and the escalating
        # ladder already prices itself. No gate.
        "Requirement": "",
        "Trigger": "After",
        "Rarity": "Common",
        "Limit": "1",
        "Image": "ScrapOoze",
        "Prompt": OOZE_PROMPT,
        "Goal Met": "",
        "Goal Missed": "",
        "Chance Won": OOZE_WON,
        "Chance Lost": OOZE_LOST,
        # Result cells are blank on the two reaches: what the ooze says depends
        # on the ROLL, not on which button produced it, so both outcomes live in
        # Chance Won / Chance Lost above. Leave keeps its own prose, because
        # walking away doesn't roll for anything.
        "choices": [
            ("Reach Inside", "Stay", "", "lose_hp 1; chance 25% -> gain_chest small 1"),
            ("Deeper", "Again", "",
             "needs Reach Inside > 0; lose_hp {2+X}; "
             "chance {35+10*X}% -> gain_chest small 1"),
            ("Leave", "", OOZE_LEAVE, "nothing"),
        ],
    },
]


def build_rows() -> list:
    rows = []
    for ev in EVENTS:
        choices = ev["choices"]
        if len(choices) > MAX_CHOICES:
            raise SystemExit(
                "%r has %d choices; the sheet holds %d. Widen MAX_CHOICES (and "
                "the generator's loop) or cut one."
                % (ev["Event"], len(choices), MAX_CHOICES))
        row = [ev.get(col, "") for col in EVENT_COLS]
        for n in range(MAX_CHOICES):
            row += list(choices[n]) if n < len(choices) else [""] * len(CHOICE_COLS)
        rows.append(row)
    return rows


def main() -> None:
    rows = build_rows()
    authored = {ev["Event"] for ev in EVENTS}
    with Workbook(XLSX) as wb:
        grid = wb.read_grid(SHEET)
        strays = [str(r[0]).strip() for r in grid[1:]
                  if r and str(r[0]).strip() and str(r[0]).strip() not in authored]
        if strays:
            raise SystemExit(
                "%s holds event(s) this script doesn't author (%s) — it rewrites "
                "the sheet wholesale and would drop them. Edit the sheet directly."
                % (SHEET, ", ".join(sorted(set(strays)))))
        wb.write_grid(SHEET, [HEADERS] + rows)

    print("%s: %d columns, %d event(s)" % (SHEET, len(HEADERS), len(rows)))
    for ev in EVENTS:
        print("  %s" % ev["Event"])
        for label, repeat, _result, effect in ev["choices"]:
            print("    %-11s %-6s %s" % (label, repeat or "End", effect))


if __name__ == "__main__":
    main()

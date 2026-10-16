class_name Fracture
extends RefCounted

# FRACTURES (docs/fracture-design.md): ten difficulty levels above an ordinary
# run, unlocked per character. Fracture 0 is the game as it always was; each
# level carries every level below it.
#
# This is the one place that answers "what level is this run at", so every rule
# that turns on a Fracture asks `at_least(n)` rather than reading the number and
# comparing it itself.
#
# The RECORD (who has unlocked what, which level each win was at) lives in
# GameStats beside the rest of the profile's history; the run's own level is
# GameState.fracture, saved with the run.

const MAX := 10

# +10% of the base repeat win (GameRanks.XP_REPEAT_WIN, 50) per level, so a
# repeat win at Fracture 10 is worth 100 (§5). The first win, the Amulet and the
# perfect bonuses do not move.
const XP_PER_LEVEL := 5

# The level the run in progress is being played at.
static func level() -> int:
	return clampi(GameState.fracture, 0, MAX)

static func at_least(n: int) -> bool:
	return level() >= n

# --- the ladder (§2) -----------------------------------------------------------
#
# WHERE EACH CHANGE SITS, in one place, so reordering the ladder (the owner has
# done it once already) is an edit here and nowhere else. Each level carries
# every level below it, so every rule reads `at_least(<its level>)`.
const SHIELD_CUT_LEVELS := [1, 3, 5]   # -1 shield per game at each
const DAMAGE_LEVELS := [2, 9]          # x1.5, rounded up, at each
const EXTRA_BODY_LEVEL := 4            # one more body on every arrival and capstone
const FASTER_TIER_LEVEL := 6           # the tier steps every 3rd spawn, not 4th
const EXTRA_ROW_LEVEL := 7             # the board starts a row taller
const EXTRA_TURN_LEVEL := 8            # the board takes a turn after a won/escaped game

# A normal game never grants fewer than this, however many cuts: a game with no
# armour at all is not a harder game, it is a different one (§3).
const MIN_SHIELDS := 1

# The per-game shield grant `base` after this run's cuts.
static func shields(base: int) -> int:
	var cuts: int = 0
	for lv in SHIELD_CUT_LEVELS:
		if at_least(lv):
			cuts += 1
	return maxi(base - cuts, MIN_SHIELDS)

# An enemy's AUTHORED damage after this run's damage steps: x1.5 rounded up, once
# per step reached, each step on the last one's result. Statuses (Strength and
# the rest) add on top of what this returns and do not grow with the level (§3).
static func damage(base: int) -> int:
	var d: int = base
	for lv in DAMAGE_LEVELS:
		if at_least(lv):
			@warning_ignore("integer_division")
			d = (d * 3 + 1) / 2
	return d

# How many more bodies every arrival and every capstone boss brings (§3).
static func extra_bodies() -> int:
	return 1 if at_least(EXTRA_BODY_LEVEL) else 0

# Whether this run's tier steps faster (§3). RunDifficulty owns the number.
static func faster_tier() -> bool:
	return at_least(FASTER_TIER_LEVEL)

# Rows the board gains on top of everything else (§3).
static func extra_rows() -> int:
	return 1 if at_least(EXTRA_ROW_LEVEL) else 0

static func extra_turn() -> bool:
	return at_least(EXTRA_TURN_LEVEL)

# --- how a Fracture is shown (§6) ---------------------------------------------

# THE SHARD, the mark a Fracture wears wherever it is drawn: the header, the
# picker, a trophy's number, a save and a history row. One glyph, defined once.
const GLYPH := "⟡"

# The colour of all of it: a cold violet, apart from the gold of the trophies and
# the level and the red of danger, so a Fracture never reads as either.
const COLOR := Color(0.72, 0.58, 1.0)

# "⟡7", or "" for Fracture 0, which is the ordinary game and wears nothing.
static func tag(level: int) -> String:
	return "" if level <= 0 else "%s%d" % [GLYPH, level]

# What each level ADDS, in the ladder's order, for the picker's hover and the
# how-to-play page. Kept beside the table above so the two cannot drift: a level
# moved there has its line moved here.
static func change_text(level: int) -> String:
	if level in SHIELD_CUT_LEVELS:
		return "Every game grants 1 fewer shield (never below 1)."
	if level in DAMAGE_LEVELS:
		return "Enemies hit harder: their damage x1.5, rounded up."
	match level:
		EXTRA_BODY_LEVEL:
			return "Every arrival brings one more body, bosses included."
		FASTER_TIER_LEVEL:
			return "Difficulty rises a spawn sooner: a boss every 3rd spawn."
		EXTRA_ROW_LEVEL:
			return "The board starts a row taller: more enemies abreast."
		EXTRA_TURN_LEVEL:
			return "Enemies take an extra turn after every game beaten or escaped."
		MAX:
			return "The Collapse: beat the Amulet, then carry it back to the start."
	return ""

# Everything a run at `level` is playing with, one line per level from 1 up.
static func ladder_text(level: int) -> String:
	if level <= 0:
		return "Fracture 0: the game as it is."
	var lines: Array = []
	for lv in range(1, mini(level, MAX) + 1):
		lines.append("%s  %s" % [tag(lv), change_text(lv)])
	return "\n".join(lines)

# Whether this run's wins count towards unlocks and trophies (§5). A CUSTOM run
# (RunConfig) is practice: it still pays XP, and nothing it does unlocks the next
# level or puts a number on a trophy.
static func run_counts() -> bool:
	return not RunConfig.enabled

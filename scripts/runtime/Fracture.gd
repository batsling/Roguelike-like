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

# Whether this run's wins count towards unlocks and trophies (§5). A CUSTOM run
# (RunConfig) is practice: it still pays XP, and nothing it does unlocks the next
# level or puts a number on a trophy.
static func run_counts() -> bool:
	return not RunConfig.enabled

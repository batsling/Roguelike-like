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

# Whether this run's wins count towards unlocks and trophies (§5). A CUSTOM run
# (RunConfig) is practice: it still pays XP, and nothing it does unlocks the next
# level or puts a number on a trophy.
static func run_counts() -> bool:
	return not RunConfig.enabled

class_name RunDifficulty
extends RefCounted

# NOTE: named RunDifficulty (not Difficulty) on purpose. EnemyData and
# ActionEnemyData each declare an inner `enum Difficulty`; a global
# class_name of the same word shadows those, breaking their
# `@export var difficulty: Difficulty` fields and cascading compile
# failures through everything that depends on them.
#
# Pure, scene-free difficulty model. The run's difficulty tier steps up
# every GAMES_PER_TIER games the player *plays* (see GameState.games_played).
#
# This mirrors the HTML build's tier ladder (Easy/Medium/Hard/Insane) but:
#   * advances on games PLAYED rather than beaten, and
#   * steps every 3 games instead of 4.
#
# The tier feeds the goal-enemy / boss roll, the action-floor room count (see
# IsaacFloorGenerator), and — as of the amulet-pressure pass — the SIZE OF THE
# BATTLEFIELD: every tier step adds a column and a row (grid_growth_for).
#
# This file also owns the run's OTHER difficulty axis, which is not a tier at all:
# how many turns the enemies take per game, read off how close the player is to
# the Amulet (turns_for_hops). The two are deliberately kept together — they are
# the whole difficulty model, and every screen that draws one draws the other.
#
# Everything here is static + side-effect free so it can be unit tested
# without a running tree.

enum Tier { LOW, MEDIUM, HIGH, INSANE }

# Number of games played before the tier advances by one.
const GAMES_PER_TIER := 3

# Highest tier index (Tier enum size - 1). Difficulty is capped here.
const MAX_TIER := Tier.INSANE

# Tier -> the multiplier value plugged into difficulty-scaled formulas
# (e.g. IsaacFloorGenerator's room count = 3.33 * value + 3..4).
# Low = 1 ... Insane = 4.
static func tier_value(tier: int) -> int:
	return clampi(tier, Tier.LOW, MAX_TIER) + 1

# Maps a games-played count to a tier. Clamped at MAX_TIER so an
# arbitrarily long run can't exceed Insane.
static func tier_for(games_played: int) -> int:
	if games_played < 0:
		games_played = 0
	@warning_ignore("integer_division")
	var tier: int = games_played / GAMES_PER_TIER
	return mini(tier, MAX_TIER)

# --- the battlefield grows with the tier (§7.3) -----------------------------
#
# Every tier step widens the board by one COLUMN and one ROW. Low is the base
# 4x4, Medium 5x5, High 6x6, Insane 7x7 — and there it stops, because the tier
# itself stops. A wider board is not a kindness: it is what keeps the amulet-
# pressure ladder below from turning into an instant loss, since three turns a
# game across a 7-wide board is still a couple of games of warning, and it comes
# with the tier's heavier enemies. Mine-r Construction stacks on top of this
# (GameLoop2.grid_cols / grid_rows add both).
static func grid_growth_for(tier: int) -> int:
	return clampi(tier, Tier.LOW, MAX_TIER)

# Convenience: the current run's board growth, read straight off GameState.
static func current_grid_growth() -> int:
	return grid_growth_for(current_tier())

# --- amulet pressure: how many turns the enemies take per game --------------
#
# The run's SECOND difficulty axis, and unlike the tier ladder this one is
# steered by the player. Enemies act ONCE per game out in the wilds and THREE
# times per game on the Amulet's doorstep, so the same stack is a slow problem on
# a long, careful route and a fast one on a bum rush. A turn is a single action:
# an enemy in the front column ATTACKS with it, and everything behind the front
# MOVES one column with it (see GameLoop2.beat_game).
#
# The ladder, in hops from the Amulet over the run graph:
#     5 or more  -> 1 turn      the wilds; the stack closes in at walking pace
#     3 or 4     -> 2 turns     they have your scent
#     2 or fewer -> 3 turns     the Amulet's doorstep
#
# The consequence is the point: taking the long way round means fighting slow
# enemies for more games, and diving straight at the Amulet means fighting fast
# ones for fewer. Neither is free, so "how hard do I rush?" becomes a real choice
# rather than a dominant strategy.
const TURNS_FAR := 1
const TURNS_MID := 2
const TURNS_NEAR := 3

# Hops-to-Amulet at or above which enemies get only TURNS_FAR.
const FAR_HOPS := 5
# ... and at or above which they get TURNS_MID. Below it, TURNS_NEAR.
const MID_HOPS := 3

# Turns per game for a position `hops` from the Amulet. A negative `hops` means
# "no route to the Amulet" (an unreachable node, or a run with no amulet picked
# yet, which is what every headless test starts from): nothing is closing in on
# a goal that isn't there, so it reads as the calmest band.
static func turns_for_hops(hops: int) -> int:
	if hops < 0 or hops >= FAR_HOPS:
		return TURNS_FAR
	if hops >= MID_HOPS:
		return TURNS_MID
	return TURNS_NEAR

# The band's name, for anything that has to SAY which rung of the ladder the run
# is standing on. One source of words so the board, the cards and the log agree.
static func turns_band_name(turns: int) -> String:
	match clampi(turns, TURNS_FAR, TURNS_NEAR):
		TURNS_FAR: return "Distant"
		TURNS_MID: return "Closing"
		_: return "Doorstep"

# The band's colour, on the same green -> amber -> red run the board's threat
# colours use. Lives beside the numbers for the same reason the names do: three
# separate screens read this ladder and none of them may disagree about it.
static func turns_band_color(turns: int) -> Color:
	match clampi(turns, TURNS_FAR, TURNS_NEAR):
		TURNS_FAR: return Color(0.45, 0.82, 0.52)
		TURNS_MID: return Color(1.0, 0.68, 0.28)
		_: return Color(0.94, 0.36, 0.34)

# One line describing the whole ladder, for tooltips. Marks the rung `turns` is
# on so a player reading it can see both where they stand and what moving costs.
static func turns_ladder_text(turns: int) -> String:
	var rungs: Array = [
		["%d+ hops away" % FAR_HOPS, TURNS_FAR],
		["%d-%d hops away" % [MID_HOPS, FAR_HOPS - 1], TURNS_MID],
		["%d-0 hops away" % (MID_HOPS - 1), TURNS_NEAR],
	]
	var lines: Array = []
	for r in rungs:
		var mark: String = "▸ " if int(r[1]) == turns else "   "
		lines.append("%s%s: enemies take %d turn%s per game" % [
			mark, r[0], int(r[1]), "" if int(r[1]) == 1 else "s"])
	return "\n".join(lines)

static func tier_name(tier: int) -> String:
	match clampi(tier, Tier.LOW, MAX_TIER):
		Tier.LOW: return "Low"
		Tier.MEDIUM: return "Medium"
		Tier.HIGH: return "High"
		Tier.INSANE: return "Insane"
		_: return "?"

# Convenience: the current run's tier, read straight off GameState.
static func current_tier() -> int:
	return tier_for(GameState.games_played)

# Convenience: the current run's tier value (1..4).
static func current_tier_value() -> int:
	return tier_value(current_tier())

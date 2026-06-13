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
# For now the tier only feeds the action-floor room count (see
# IsaacFloorGenerator). Enemy generation, curse levels, and event
# difficulty will read the same tier as those systems get ported.
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

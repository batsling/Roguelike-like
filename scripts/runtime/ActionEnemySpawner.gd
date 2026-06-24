class_name ActionEnemySpawner

# Weighted per-room encounter builder for ACTION combat. Reuses the deckbuilder
# weighted-pick core (EnemySpawner.pick_group) but with its own per-room spend
# budget and battlefield cap. Each normal room is one encounter: the run's
# difficulty tier sets a BUDGET, every enemy's `weight` is its COST, and the room
# is filled with weighted picks until the budget or the enemy cap runs out.
# (e.g. a Horf costs 2, so the Low-tier budget of 8 fields up to four of them.)

# Per-room spend budget by RunDifficulty.Tier (LOW, MEDIUM, HIGH, INSANE).
const TIER_BUDGET := [8, 10, 12, 15]
# Boss rooms spend more (ActionFloor also bumps their HP).
const BOSS_BUDGET_MULT := 1.5
# Most enemies a single action room will field, regardless of leftover budget.
const MAX_ENEMIES := 8


# Per-room budget for the given tier (clamped into range).
static func budget_for(tier: int) -> int:
	return TIER_BUDGET[clampi(tier, 0, TIER_BUDGET.size() - 1)]


# Highest action-enemy difficulty allowed at a tier. Maps tier 1:1 onto
# difficulty but caps at HIGH so Boss enemies never roll into a random room.
static func max_difficulty_for(tier: int) -> int:
	return mini(maxi(0, tier), ActionEnemyData.Difficulty.HIGH)


# {id, weight} candidate dicts from the action roster within the difficulty band;
# falls back to the full weight>0 roster if the band gate empties the pool.
static func _candidates(max_diff: int) -> Array:
	var out: Array = []
	for e in Data.all_action_enemies():
		if e is ActionEnemyData and e.weight > 0 and e.difficulty <= max_diff:
			out.append({"id": e.id, "weight": e.weight})
	if out.is_empty():
		for e in Data.all_action_enemies():
			if e is ActionEnemyData and e.weight > 0:
				out.append({"id": e.id, "weight": e.weight})
	return out


# Build one room's enemy id list. `budget_override` (> 0) replaces the tier
# budget (used for boss rooms). Always returns at least one enemy when the roster
# is non-empty, so a room is never accidentally empty.
static func build_room(rng: RandomNumberGenerator, budget_override: int = -1) -> Array:
	var tier: int = RunDifficulty.current_tier()
	var budget: int = budget_override if budget_override > 0 else budget_for(tier)
	var candidates: Array = _candidates(max_difficulty_for(tier))
	if candidates.is_empty():
		return []
	var group: Array = EnemySpawner.pick_group(candidates, budget, MAX_ENEMIES, rng)
	if group.is_empty():
		# Budget too small for anything that survived the filter — field the
		# cheapest candidate so the room still has a fight.
		var cheapest: Dictionary = candidates[0]
		for c in candidates:
			if int(c.weight) < int(cheapest.weight):
				cheapest = c
		group = [StringName(cheapest.id)]
	return group

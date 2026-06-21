class_name EnemySpawner

# Weighted enemy-encounter builder for deckbuilder combat. Ports the legacy
# preGenerateEnemiesForGame() budget/tier "weight" system:
#
#   * The run's difficulty tier (RunDifficulty, from games played) sets a spend
#     BUDGET. The very first combat of a run uses a gentler opening budget.
#   * Each enemy's `weight` is its COST. We repeatedly pick an enemy that still
#     fits the remaining budget — rolling a target weight in 1..maxFitting and
#     preferring enemies at exactly that cost, so pricier enemies (there are few)
#     stay individually likely — then subtract its cost. Stop at budget 0 or the
#     battlefield cap.
#   * The candidate pool is gated by tier (Low tier → Low enemies only, …) and
#     Boss-difficulty enemies are reserved for boss encounters (never random).
#
# The pure `pick_group` core takes plain dictionaries so it unit-tests without a
# scene; `build_for_game` wires it to Data / GameState / RunDifficulty.

# Spend budget per RunDifficulty.Tier (LOW, MEDIUM, HIGH, INSANE).
const TIER_BUDGET := [4, 6, 9, 12]
# The first combat of a run (no combats completed yet) gets this gentler budget.
const FIRST_COMBAT_BUDGET := 2


# Budget for the given tier, easing the opening fight when none are completed.
static func budget_for(tier: int, combats_completed: int) -> int:
	if combats_completed <= 0:
		return FIRST_COMBAT_BUDGET
	return TIER_BUDGET[clampi(tier, 0, TIER_BUDGET.size() - 1)]


# Highest enemy difficulty (EnemyData.Difficulty) allowed at a run tier. Maps the
# tier 1:1 onto enemy difficulty but caps at HIGH so Boss enemies never roll into
# a random encounter (they are reserved for the planned boss fight).
static func max_difficulty_for(tier: int) -> int:
	return mini(maxi(0, tier), EnemyData.Difficulty.HIGH)


# Pure weighted-group picker. `candidates` is an Array of dicts with at least
# `id` (StringName/String) and `weight` (int > 0). Returns an Array[StringName]
# of chosen enemy ids (length 1..max_enemies), or [] when nothing fits.
static func pick_group(candidates: Array, budget: int, max_enemies: int,
		rng: RandomNumberGenerator) -> Array:
	var selected: Array = []
	var remaining: int = budget
	while remaining > 0 and selected.size() < max_enemies:
		var fitting: Array = []
		var max_w: int = 0
		for c in candidates:
			var w: int = int(c.get("weight", 0))
			if w > 0 and w <= remaining:
				fitting.append(c)
				max_w = maxi(max_w, w)
		if fitting.is_empty():
			break
		var target_w: int = rng.randi_range(1, max_w)
		var bucket: Array = []
		for c in fitting:
			if int(c.get("weight", 0)) == target_w:
				bucket.append(c)
		if bucket.is_empty():
			bucket = fitting
		var chosen: Dictionary = bucket[rng.randi() % bucket.size()]
		selected.append(StringName(chosen.get("id")))
		remaining -= int(chosen.get("weight", 0))
	return selected


# Convenience: build the encounter for a game node, reading the live tier, the
# combats-completed count, and the enemy roster. Falls back gracefully so a fight
# always has at least one enemy. `max_enemies` is the battlefield cap.
static func build_for_game(game_id: StringName, rng: RandomNumberGenerator,
		max_enemies: int) -> Array:
	var tier: int = RunDifficulty.current_tier()
	var budget: int = budget_for(tier, GameState.total_combats_completed)
	var max_diff: int = max_difficulty_for(tier)

	# Source pool: a game's explicit enemy_pool if set, else the full roster.
	var pool: Array = []
	var g: GameData = Data.get_game(game_id)
	if g != null and not g.enemy_pool.is_empty():
		for eid in g.enemy_pool:
			var e := Data.get_enemy(eid)
			if e != null:
				pool.append(e)
	else:
		for e in Data.all_enemies():
			if e is EnemyData:
				pool.append(e)

	# Spawnable (weight > 0) and within the tier's difficulty band.
	var candidates: Array = []
	for e in pool:
		if e.weight > 0 and e.difficulty <= max_diff:
			candidates.append({"id": e.id, "weight": e.weight})
	# If the difficulty gate emptied the pool, drop it (keep weight > 0).
	if candidates.is_empty():
		for e in pool:
			if e.weight > 0:
				candidates.append({"id": e.id, "weight": e.weight})
	if candidates.is_empty():
		return []

	var group: Array = pick_group(candidates, budget, max_enemies, rng)
	if group.is_empty():
		# Budget too small for anything that survived the filter — field the
		# cheapest candidate so the encounter is never empty.
		var cheapest: Dictionary = candidates[0]
		for c in candidates:
			if int(c.weight) < int(cheapest.weight):
				cheapest = c
		group = [StringName(cheapest.id)]
	return group

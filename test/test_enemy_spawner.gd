extends GutTest

# Unit tests for the weighted enemy-encounter builder (EnemySpawner). Covers the
# pure budget/tier math and the weighted pick loop; build_for_game (which reads
# Data/GameState) is exercised in-engine, not here.

# --- budget_for -----------------------------------------------------------

func test_first_combat_uses_opening_budget() -> void:
	# combats_completed == 0 → the gentle opening budget regardless of tier.
	assert_eq(EnemySpawner.budget_for(RunDifficulty.Tier.HIGH, 0),
		EnemySpawner.FIRST_COMBAT_BUDGET)
	assert_eq(EnemySpawner.budget_for(RunDifficulty.Tier.LOW, 0), 2)

func test_budget_per_tier() -> void:
	assert_eq(EnemySpawner.budget_for(RunDifficulty.Tier.LOW, 1), 4)
	assert_eq(EnemySpawner.budget_for(RunDifficulty.Tier.MEDIUM, 1), 6)
	assert_eq(EnemySpawner.budget_for(RunDifficulty.Tier.HIGH, 1), 9)
	assert_eq(EnemySpawner.budget_for(RunDifficulty.Tier.INSANE, 1), 12)

func test_budget_clamps_out_of_range_tier() -> void:
	assert_eq(EnemySpawner.budget_for(99, 1), 12, "Over-max tier clamps to Insane")
	assert_eq(EnemySpawner.budget_for(-5, 1), 4, "Negative tier clamps to Low")

# --- max_difficulty_for ---------------------------------------------------

func test_difficulty_band_caps_below_boss() -> void:
	assert_eq(EnemySpawner.max_difficulty_for(RunDifficulty.Tier.LOW),
		EnemyData.Difficulty.LOW)
	assert_eq(EnemySpawner.max_difficulty_for(RunDifficulty.Tier.MEDIUM),
		EnemyData.Difficulty.MEDIUM)
	assert_eq(EnemySpawner.max_difficulty_for(RunDifficulty.Tier.HIGH),
		EnemyData.Difficulty.HIGH)
	# Insane still caps at High — Boss is never random.
	assert_eq(EnemySpawner.max_difficulty_for(RunDifficulty.Tier.INSANE),
		EnemyData.Difficulty.HIGH)

# --- pick_group -----------------------------------------------------------

func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r

func _weight_of(ids: Array, candidates: Array) -> int:
	var by_id := {}
	for c in candidates:
		by_id[String(c.id)] = int(c.weight)
	var total := 0
	for id in ids:
		total += int(by_id.get(String(id), 0))
	return total

func test_empty_candidates_returns_empty() -> void:
	assert_eq(EnemySpawner.pick_group([], 10, 5, _rng(1)), [])

func test_group_never_exceeds_budget() -> void:
	var cands := [{"id": "louse", "weight": 1}, {"id": "slime_m", "weight": 2},
		{"id": "slime_l", "weight": 4}]
	for s in range(20):
		var group: Array = EnemySpawner.pick_group(cands, 6, 5, _rng(s))
		assert_lte(_weight_of(group, cands), 6,
			"Total weight must stay within budget (seed %d)" % s)
		for id in group:
			assert_true(["louse", "slime_m", "slime_l"].has(String(id)),
				"Only picks from candidates")

func test_group_respects_enemy_cap() -> void:
	var cands := [{"id": "louse", "weight": 1}]
	# Budget 100 but cap 5 of a weight-1 enemy → exactly 5.
	var group: Array = EnemySpawner.pick_group(cands, 100, 5, _rng(7))
	assert_eq(group.size(), 5)

func test_nothing_fits_returns_empty() -> void:
	# Only an expensive enemy, tiny budget → it can't be afforded.
	var cands := [{"id": "transient", "weight": 9}]
	assert_eq(EnemySpawner.pick_group(cands, 2, 5, _rng(3)), [])

func test_group_is_non_empty_when_something_fits() -> void:
	var cands := [{"id": "louse", "weight": 1}, {"id": "transient", "weight": 9}]
	var group: Array = EnemySpawner.pick_group(cands, 4, 5, _rng(11))
	assert_gt(group.size(), 0, "A fitting cheap enemy is always pickable")
	assert_lte(_weight_of(group, cands), 4)

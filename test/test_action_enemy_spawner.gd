extends GutTest

# Unit tests for the action-combat weighted encounter builder
# (ActionEnemySpawner). Covers the per-room budget table and the weighted pick
# loop it shares with the deckbuilder (EnemySpawner.pick_group). build_room,
# which reads Data/RunDifficulty, is exercised in-engine, not here.

func test_budget_per_tier() -> void:
	assert_eq(ActionEnemySpawner.budget_for(RunDifficulty.Tier.LOW), 8)
	assert_eq(ActionEnemySpawner.budget_for(RunDifficulty.Tier.MEDIUM), 10)
	assert_eq(ActionEnemySpawner.budget_for(RunDifficulty.Tier.HIGH), 12)
	assert_eq(ActionEnemySpawner.budget_for(RunDifficulty.Tier.INSANE), 15)

func test_budget_clamps_out_of_range_tier() -> void:
	assert_eq(ActionEnemySpawner.budget_for(99), 15, "Over-max tier clamps to Insane")
	assert_eq(ActionEnemySpawner.budget_for(-3), 8, "Negative tier clamps to Low")

func test_difficulty_band_caps_below_boss() -> void:
	assert_eq(ActionEnemySpawner.max_difficulty_for(RunDifficulty.Tier.LOW),
		ActionEnemyData.Difficulty.LOW)
	# Insane still caps at High — Boss enemies are never random.
	assert_eq(ActionEnemySpawner.max_difficulty_for(RunDifficulty.Tier.INSANE),
		ActionEnemyData.Difficulty.HIGH)

func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r

func test_four_horfs_fit_the_low_budget() -> void:
	# A weight-2 enemy in the Low-tier budget of 8 -> exactly four fit.
	var cands := [{"id": &"horf", "weight": 2}]
	var group := EnemySpawner.pick_group(cands, 8, ActionEnemySpawner.MAX_ENEMIES, _rng(1))
	assert_eq(group.size(), 4, "budget 8 / weight 2 = 4 enemies")
	for id in group:
		assert_eq(id, &"horf")

func test_group_never_exceeds_enemy_cap() -> void:
	# Huge budget + cheap enemy is bounded by MAX_ENEMIES, not the budget.
	var cands := [{"id": &"cheap", "weight": 1}]
	var group := EnemySpawner.pick_group(cands, 999, ActionEnemySpawner.MAX_ENEMIES, _rng(2))
	assert_eq(group.size(), ActionEnemySpawner.MAX_ENEMIES)

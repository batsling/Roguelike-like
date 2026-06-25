extends GutTest

# Strategy-mode combat weight budget: each room combat spends a difficulty-based
# weight budget (Low 6 / Medium 8 / Hard 10 / Insane 12) on enemies, where every
# enemy costs its 1-5 weight CLASS (StrategyEnemyData.weight). These tests pin the
# budget table and verify a rolled encounter never overspends it.

const StrategyMapScript := preload("res://scripts/strategy_prototype/Map.gd")

func after_each() -> void:
	GameState.games_played = 0

# --- Budget table -------------------------------------------------------------

func test_budget_table_matches_difficulty() -> void:
	assert_eq(StrategyMapScript.combat_weight_budget(RunDifficulty.Tier.LOW), 6, "Low = 6")
	assert_eq(StrategyMapScript.combat_weight_budget(RunDifficulty.Tier.MEDIUM), 8, "Medium = 8")
	assert_eq(StrategyMapScript.combat_weight_budget(RunDifficulty.Tier.HIGH), 10, "Hard = 10")
	assert_eq(StrategyMapScript.combat_weight_budget(RunDifficulty.Tier.INSANE), 12, "Insane = 12")

func test_budget_clamps_out_of_range_tiers() -> void:
	assert_eq(StrategyMapScript.combat_weight_budget(-5), 6, "below Low clamps to Low")
	assert_eq(StrategyMapScript.combat_weight_budget(99), 12, "above Insane clamps to Insane")

# --- Encounter respects the budget --------------------------------------------

# Total weight CLASS of an encounter (sum of each kind's 1-5 weight).
func _encounter_weight(encounter: Array) -> int:
	var total := 0
	for kind in encounter:
		var d: StrategyEnemyData = Data.get_strategy_enemy(StringName(kind))
		total += int(d.weight) if d != null else 1
	return total

func test_rolled_encounter_never_exceeds_budget() -> void:
	var rng := RandomNumberGenerator.new()
	var m: StrategyMap = StrategyMapScript.new()
	# Sweep every tier; run many rolls so the random fill is exercised.
	for tier in [RunDifficulty.Tier.LOW, RunDifficulty.Tier.MEDIUM,
			RunDifficulty.Tier.HIGH, RunDifficulty.Tier.INSANE]:
		GameState.games_played = int(tier) * RunDifficulty.GAMES_PER_TIER
		var budget: int = StrategyMapScript.combat_weight_budget(tier)
		for seed in range(60):
			rng.seed = seed
			var enc: Array = m._roll_encounter(rng, 5)
			assert_false(enc.is_empty(), "encounter is never empty (tier %d)" % tier)
			assert_true(_encounter_weight(enc) <= budget,
				"weight %d <= budget %d (tier %d)" % [_encounter_weight(enc), budget, tier])

func test_higher_difficulty_buys_more_on_average() -> void:
	var rng := RandomNumberGenerator.new()
	var m: StrategyMap = StrategyMapScript.new()
	var low_total := 0
	var insane_total := 0
	for seed in range(80):
		GameState.games_played = 0  # Low
		rng.seed = seed
		low_total += _encounter_weight(m._roll_encounter(rng, 5))
		GameState.games_played = RunDifficulty.Tier.INSANE * RunDifficulty.GAMES_PER_TIER
		rng.seed = seed
		insane_total += _encounter_weight(m._roll_encounter(rng, 5))
	assert_true(insane_total > low_total,
		"Insane combats spend more weight than Low on average (%d > %d)" % [insane_total, low_total])

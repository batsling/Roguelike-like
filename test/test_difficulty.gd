extends GutTest

# Unit tests for the difficulty tier model (RunDifficulty.gd). Pure static
# helpers, so no scene setup is required.

func test_tier_for_starts_low() -> void:
	assert_eq(RunDifficulty.tier_for(0), RunDifficulty.Tier.LOW)
	assert_eq(RunDifficulty.tier_for(1), RunDifficulty.Tier.LOW)
	assert_eq(RunDifficulty.tier_for(2), RunDifficulty.Tier.LOW)

func test_tier_advances_every_three_games() -> void:
	# Steps up every GAMES_PER_TIER (3) games played.
	assert_eq(RunDifficulty.tier_for(3), RunDifficulty.Tier.MEDIUM)
	assert_eq(RunDifficulty.tier_for(5), RunDifficulty.Tier.MEDIUM)
	assert_eq(RunDifficulty.tier_for(6), RunDifficulty.Tier.HIGH)
	assert_eq(RunDifficulty.tier_for(8), RunDifficulty.Tier.HIGH)
	assert_eq(RunDifficulty.tier_for(9), RunDifficulty.Tier.INSANE)

func test_tier_caps_at_insane() -> void:
	assert_eq(RunDifficulty.tier_for(12), RunDifficulty.Tier.INSANE)
	assert_eq(RunDifficulty.tier_for(100), RunDifficulty.Tier.INSANE)

func test_negative_games_clamped_low() -> void:
	assert_eq(RunDifficulty.tier_for(-5), RunDifficulty.Tier.LOW)

func test_tier_value_is_one_through_four() -> void:
	assert_eq(RunDifficulty.tier_value(RunDifficulty.Tier.LOW), 1)
	assert_eq(RunDifficulty.tier_value(RunDifficulty.Tier.MEDIUM), 2)
	assert_eq(RunDifficulty.tier_value(RunDifficulty.Tier.HIGH), 3)
	assert_eq(RunDifficulty.tier_value(RunDifficulty.Tier.INSANE), 4)

func test_tier_value_clamps_out_of_range() -> void:
	assert_eq(RunDifficulty.tier_value(-1), 1)
	assert_eq(RunDifficulty.tier_value(99), 4)

func test_tier_names() -> void:
	assert_eq(RunDifficulty.tier_name(RunDifficulty.Tier.LOW), "Low")
	assert_eq(RunDifficulty.tier_name(RunDifficulty.Tier.MEDIUM), "Medium")
	assert_eq(RunDifficulty.tier_name(RunDifficulty.Tier.HIGH), "High")
	assert_eq(RunDifficulty.tier_name(RunDifficulty.Tier.INSANE), "Insane")

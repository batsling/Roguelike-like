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

# --- where the bosses stand in the ladder (§7.1) ----------------------------

# THE BOSS CLOSES ITS BAND. Two ordinary games at a tier, then the boss, then the
# next tier — so `is_boss_game` is true on the last game of every band and the
# ladder reads Low, Low, LOW BOSS | Medium, Medium, MEDIUM BOSS | …
func test_the_last_game_of_every_tier_band_is_a_boss() -> void:
	for gp in range(15):
		assert_eq(RunDifficulty.is_boss_game(gp),
			gp % RunDifficulty.GAMES_PER_TIER == RunDifficulty.GAMES_PER_TIER - 1,
			"games_played %d" % gp)

# Spelled out per encounter, because the off-by-one between "games already
# played" and "the encounter about to be chosen" is the whole of this rule: the
# offering for encounter N asks with N - 1, so every THIRD encounter is a boss.
func test_every_third_encounter_is_the_boss() -> void:
	var bosses: Array = []
	for encounter in range(1, 16):
		if RunDifficulty.is_boss_game(encounter - 1):
			bosses.append(encounter)
	assert_eq(bosses, [3, 6, 9, 12, 15],
		"bosses land on every third encounter, the first on the 3rd")

# A boss is at its band's OWN tier — it is inside the band, not on the crossing,
# so nothing has to walk the tier back a game to place it.
func test_a_boss_is_at_the_tier_of_the_band_it_closes() -> void:
	var T := RunDifficulty.Tier
	assert_eq(RunDifficulty.tier_for(2), T.LOW, "the 3rd encounter is the Low boss")
	assert_eq(RunDifficulty.tier_for(5), T.MEDIUM, "the 6th is the Medium boss")
	assert_eq(RunDifficulty.tier_for(8), T.HIGH, "the 9th is the High boss")
	assert_eq(RunDifficulty.tier_for(11), T.INSANE, "the 12th is the Insane boss")

func test_a_negative_games_played_is_not_a_boss_game() -> void:
	assert_false(RunDifficulty.is_boss_game(-1))
	assert_false(RunDifficulty.is_boss_game(-5))

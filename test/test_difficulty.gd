extends GutTest

# Unit tests for the difficulty tier model (RunDifficulty.gd). Pure static
# helpers, so no scene setup is required.

func test_tier_for_starts_low() -> void:
	assert_eq(RunDifficulty.tier_for(0), RunDifficulty.Tier.LOW)
	assert_eq(RunDifficulty.tier_for(1), RunDifficulty.Tier.LOW)
	assert_eq(RunDifficulty.tier_for(2), RunDifficulty.Tier.LOW)

func test_tier_advances_every_four_spawns() -> void:
	# Steps up every GAMES_PER_TIER (4) spawn events.
	assert_eq(RunDifficulty.tier_for(3), RunDifficulty.Tier.LOW)
	assert_eq(RunDifficulty.tier_for(4), RunDifficulty.Tier.MEDIUM)
	assert_eq(RunDifficulty.tier_for(7), RunDifficulty.Tier.MEDIUM)
	assert_eq(RunDifficulty.tier_for(8), RunDifficulty.Tier.HIGH)
	assert_eq(RunDifficulty.tier_for(11), RunDifficulty.Tier.HIGH)
	assert_eq(RunDifficulty.tier_for(12), RunDifficulty.Tier.INSANE)

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

# THE CAPSTONE CLOSES ITS BAND (§19.6). Every third SPAWN EVENT puts a boss on
# the board on top of whatever else was spawning — so this reads the count
# INCLUDING the event just taken, and answers "did that spawn close a band".
#
# It replaced `is_boss_game`, which counted games and put the boss on the
# offering as a card's own enemy. The band width did not change; what it counts
# did, and an Event or a Shop node spawns nothing and so brings it no closer.
func test_every_fourth_spawn_event_closes_the_band() -> void:
	for n in range(16):
		assert_eq(RunDifficulty.is_boss_spawn(n),
			n > 0 and n % RunDifficulty.GAMES_PER_TIER == 0,
			"spawn_events %d" % n)

# Spelled out, because "every fourth" has an off-by-one in it either way you read
# it: the count includes the spawn just taken, so the 4th spawn closes the first
# band rather than the 5th opening the second.
func test_the_capstone_lands_on_every_fourth_spawn() -> void:
	var bands: Array = []
	for n in range(1, 17):
		if RunDifficulty.is_boss_spawn(n):
			bands.append(n)
	assert_eq(bands, [4, 8, 12, 16],
		"a boss closes every fourth spawn event, the first on the 4th")

# Nothing is owed before the run has spawned anything — a run that has not put a
# body down yet must not open on a capstone.
func test_no_spawns_yet_is_not_a_capstone() -> void:
	assert_false(RunDifficulty.is_boss_spawn(0), "a run that has spawned nothing")
	assert_false(RunDifficulty.is_boss_spawn(-1), "and a count that cannot happen")

# A boss is at its band's OWN tier — it is inside the band, not on the crossing,
# so nothing has to walk the tier back a game to place it.
# A capstone is at the tier of the band it CLOSES, not the one it opens. The
# 4th spawn is rolled at Low — the spawn reads the tier before it counts itself —
# so the boss that ends the Low band is a Low boss, and the tier the run climbs
# into arrives with the next ordinary spawn.
func test_a_capstone_is_at_the_tier_of_the_band_it_closes() -> void:
	var T := RunDifficulty.Tier
	for pair in [[4, T.LOW], [8, T.MEDIUM], [12, T.HIGH], [16, T.INSANE]]:
		var at: int = int(pair[0])
		assert_true(RunDifficulty.is_boss_spawn(at), "spawn %d closes a band" % at)
		assert_eq(RunDifficulty.tier_for(at - 1), int(pair[1]),
			"and it closes it at %s" % RunDifficulty.tier_name(int(pair[1])))

func test_a_negative_spawn_count_is_not_a_capstone() -> void:
	assert_false(RunDifficulty.is_boss_spawn(-1))
	assert_false(RunDifficulty.is_boss_spawn(-5))

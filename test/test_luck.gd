extends GutTest

# LUCK — every point is a 50% chance of a reroll, keep the better result.
#
# Before this it was a GUARANTEED reroll per point, and before that a
# 10%-per-point chance of ADVANTAGE, which at a single point did nothing at all
# nine times in ten. These tests pin what makes the current one right — that
# each point is a coin, that the direction is declared rather than assumed, and
# that the number quoted to the player is the number that gets rolled.

var _luck: int
var _rng: RandomNumberGenerator


func before_each() -> void:
	_luck = GameState.luck
	_rng = RandomNumberGenerator.new()
	_rng.seed = 424242


func after_each() -> void:
	GameState.luck = _luck


# --- the model ---------------------------------------------------------------

func test_no_luck_is_one_roll() -> void:
	GameState.luck = 0
	assert_eq(Stats.luck_points(), 0, "no coins to flip")
	assert_eq(Stats.luck_rerolls(_rng), 0, "so no extra rolls")
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 25.0, 0.01,
		"and the odds are the authored odds")


func test_each_point_is_a_coin_for_one_more_roll() -> void:
	# 3 Luck is 0-3 rerolls, 1.5 on average, and every count happens.
	GameState.luck = 3
	var seen: Dictionary = {}
	var total: int = 0
	for _i in range(4000):
		var n: int = Stats.luck_rerolls(_rng)
		assert_between(n, 0, 3)
		seen[n] = true
		total += n
	assert_eq(seen.size(), 4, "none, one, two and three rerolls all happen")
	assert_almost_eq(float(total) / 4000.0, 1.5, 0.08, "half a reroll per point")


func test_luck_compounds_rather_than_adding() -> void:
	# 1 - (1-p)(1-p/2)^L. At 1 Luck a 25% is 34.375%, not 37.5%.
	GameState.luck = 1
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 34.375, 0.01)
	GameState.luck = 3
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 49.756, 0.01)


func test_negative_luck_takes_the_worse_result() -> void:
	GameState.luck = -2
	# p * ((1+p)/2)^2 = 0.25 * 0.625^2.
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 9.766, 0.01)


func test_the_quoted_odds_are_the_rolled_odds() -> void:
	# The closed form averages over the coins; this is the coins.
	GameState.luck = 2
	var hits: int = _hits(20000, 25.0, Stats.Favour.HIGH)
	assert_almost_eq(float(hits) / 200.0, Stats.effective_chance(25.0, Stats.Favour.HIGH),
		1.5, "what the button says is what 20000 rolls land at")


func test_a_roll_with_no_better_side_is_left_alone() -> void:
	# Favour.NONE: which of the twelve Commons you drew, which bag burst out of
	# the machine. Luck deciding those would be Luck deciding what you need.
	GameState.luck = 5
	assert_almost_eq(Stats.effective_chance(50.0, Stats.Favour.NONE), 50.0, 0.01)


func test_an_unwanted_outcome_is_rolled_away_from() -> void:
	# Favour.LOW — the Donation Machine's jam. Luck steers you AWAY, so the
	# chance of it landing falls rather than rises.
	GameState.luck = 2
	var jam: float = Stats.effective_chance(10.0, Stats.Favour.LOW)
	assert_lt(jam, 10.0, "Luck should make a jam less likely, not more")
	assert_almost_eq(jam, 3.025, 0.01, "0.10 * 0.55^2")


# --- it actually fires -------------------------------------------------------

func test_luck_really_raises_the_hit_rate() -> void:
	# The model above is arithmetic; this is the roll. 2000 trials at a 20%
	# chance: ~400 without Luck, ~704 with 2 (1 - 0.8 * 0.9^2).
	GameState.luck = 0
	var plain: int = _hits(2000, 20.0, Stats.Favour.HIGH)
	GameState.luck = 2
	var lucky: int = _hits(2000, 20.0, Stats.Favour.HIGH)
	assert_gt(lucky, plain + 150,
		"a coin per point has to be visible in 2000 rolls")


func test_luck_really_lowers_an_unwanted_hit_rate() -> void:
	GameState.luck = 0
	var plain: int = _hits(2000, 50.0, Stats.Favour.LOW)
	GameState.luck = 2
	var lucky: int = _hits(2000, 50.0, Stats.Favour.LOW)
	assert_lt(lucky, plain - 150, "Luck rolls away from the bad side")


func _hits(trials: int, percent: float, favour: int) -> int:
	var n: int = 0
	for _i in range(trials):
		if Stats.roll_chance(_rng, percent, favour):
			n += 1
	return n


func test_a_range_rolls_high_with_luck() -> void:
	GameState.luck = 0
	var plain: int = _range_total(400, 2, 5)
	GameState.luck = 3
	var lucky: int = _range_total(400, 2, 5)
	assert_gt(lucky, plain, "more pickups, more gold out of the bank")


func _range_total(trials: int, lo: int, hi: int) -> int:
	var total: int = 0
	for _i in range(trials):
		total += Stats.roll_range(_rng, lo, hi, Stats.Favour.HIGH)
	return total


# --- it reaches the ladder ---------------------------------------------------

func test_luck_reaches_every_rarity_roll_through_the_ladder() -> void:
	# The point of putting Luck on Data.roll_item_rarity rather than at the call
	# sites: item rewards, chest sizes, scrolls, shop stock and the object pools
	# all walk this one function, so all of them inherit the reroll.
	GameState.luck = 0
	var plain: int = _rarity_total(600)
	GameState.luck = 4
	var lucky: int = _rarity_total(600)
	assert_gt(lucky, plain, "a lucky run rolls rarer things")


func _rarity_total(trials: int) -> int:
	var total: int = 0
	for _i in range(trials):
		total += Data.roll_item_rarity(_rng)
	return total


func test_a_caller_supplying_its_own_roll_is_not_second_guessed() -> void:
	# roll01 means "I have already decided the draw" — a Luck reroll on top would
	# be applying it twice.
	GameState.luck = 5
	assert_eq(Data.roll_item_rarity(_rng, 0.0), int(Data.RarityStep.COMMON),
		"an explicit low roll stays a Common")


# --- the clover --------------------------------------------------------------

func test_the_clover_grants_luck_and_takes_it_away_again() -> void:
	var clover: ItemData = Data.get_item2(&"clover")
	assert_not_null(clover, "items2.0 carries the Clover")
	assert_eq(int(clover.stat_bonuses.get("luck", 0)), 1,
		"a passive bonus, so the Luck goes with the item")
	var before: int = Stats.get_value(&"luck")
	var inst: ItemData = GameState.add_item(clover)
	assert_eq(Stats.get_value(&"luck"), before + 1, "held: +1 Luck")
	GameState.remove_item(inst)
	assert_eq(Stats.get_value(&"luck"), before, "lost: the Luck goes with it")


func test_the_clover_is_uncommon() -> void:
	# Every roll reaches for a reroll per point, and that compounds — so it does
	# not belong on the bottom rung of the ladder.
	assert_eq(int(Data.get_item2(&"clover").rarity), int(ItemData.Rarity.UNCOMMON))

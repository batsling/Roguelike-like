extends GutTest

# LUCK — one guaranteed reroll per point, keep the better result.
#
# This replaced a 10%-per-point chance of ADVANTAGE, which at a single point did
# nothing at all nine times in ten. The difference is not a tuning change: the
# old Luck was a stat you could hold and never see. These tests pin the three
# things that make the new one a real stat — that the reroll ALWAYS happens, that
# the direction is declared rather than assumed, and that the number quoted to
# the player is the number that gets rolled.

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
	assert_eq(Stats.luck_rerolls(), 0, "no extra rolls")
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 25.0, 0.01,
		"and the odds are the authored odds")


func test_each_point_buys_exactly_one_more_roll() -> void:
	for n in range(4):
		GameState.luck = n
		assert_eq(Stats.luck_rerolls(), n, "%d Luck = %d extra rolls" % [n, n])


func test_luck_compounds_rather_than_adding() -> void:
	# 1 - (1-p)^tries, not p * tries. At 1 Luck a 25% is 43.75%, not 50%.
	GameState.luck = 1
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 43.75, 0.01)
	GameState.luck = 3
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 68.359, 0.01)


func test_negative_luck_takes_the_worse_result() -> void:
	GameState.luck = -2
	# Three rolls, all of which must hit: 0.25^3.
	assert_almost_eq(Stats.effective_chance(25.0, Stats.Favour.HIGH), 1.5625, 0.01)


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
	assert_almost_eq(jam, 0.1, 0.01, "0.10^3")


# --- it actually fires -------------------------------------------------------

func test_luck_really_raises_the_hit_rate() -> void:
	# The model above is arithmetic; this is the roll. 2000 trials at a 20%
	# chance: ~400 without Luck, ~1180 with 2.
	GameState.luck = 0
	var plain: int = _hits(2000, 20.0, Stats.Favour.HIGH)
	GameState.luck = 2
	var lucky: int = _hits(2000, 20.0, Stats.Favour.HIGH)
	assert_gt(lucky, plain + 300,
		"a guaranteed reroll per point has to be visible in 2000 rolls")


func test_luck_really_lowers_an_unwanted_hit_rate() -> void:
	GameState.luck = 0
	var plain: int = _hits(2000, 50.0, Stats.Favour.LOW)
	GameState.luck = 2
	var lucky: int = _hits(2000, 50.0, Stats.Favour.LOW)
	assert_lt(lucky, plain - 300, "Luck rolls away from the bad side")


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
	# Every roll rerolled per point compounds hard — two Clovers is three rolls at
	# everything — so it does not belong on the bottom rung of the ladder.
	assert_eq(int(Data.get_item2(&"clover").rarity), int(ItemData.Rarity.UNCOMMON))

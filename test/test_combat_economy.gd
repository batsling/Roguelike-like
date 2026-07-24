extends GutTest

# Unit tests for CombatEconomy — the single source of truth for the run's gold
# economy (combat rewards, section rewards, unified shop prices). Pure math, no
# scene needed.

# --- Deckbuilder combat gold ----------------------------------------------

func test_deckbuilder_gold_scales_with_tier() -> void:
	for tier in range(4):
		assert_eq(CombatEconomy.deckbuilder_combat_gold(tier, false),
			int(CombatEconomy.DECKBUILDER_COMBAT_GOLD_BY_TIER[tier]))
	# Out-of-range tiers clamp to the nearest end.
	assert_eq(CombatEconomy.deckbuilder_combat_gold(-2, false),
		int(CombatEconomy.DECKBUILDER_COMBAT_GOLD_BY_TIER[0]))
	assert_eq(CombatEconomy.deckbuilder_combat_gold(99, false),
		int(CombatEconomy.DECKBUILDER_COMBAT_GOLD_BY_TIER[-1]))

func test_deckbuilder_elite_multiplier() -> void:
	# Elite pays 1.5x the tier purse (int-truncated).
	assert_eq(CombatEconomy.deckbuilder_combat_gold(0, true), 19)   # 13 * 1.5 = 19.5 -> 19
	assert_eq(CombatEconomy.deckbuilder_combat_gold(1, true), 27)   # 18 * 1.5
	assert_eq(CombatEconomy.deckbuilder_combat_gold(3, true), 37)   # 25 * 1.5 = 37.5 -> 37

# --- Section reward -------------------------------------------------------

func test_section_reward_by_tier() -> void:
	assert_eq(CombatEconomy.section_reward_gold(RunDifficulty.Tier.LOW), 10)
	assert_eq(CombatEconomy.section_reward_gold(RunDifficulty.Tier.MEDIUM), 15)
	assert_eq(CombatEconomy.section_reward_gold(RunDifficulty.Tier.HIGH), 25)
	assert_eq(CombatEconomy.section_reward_gold(RunDifficulty.Tier.INSANE), 35)

func test_section_reward_clamps_out_of_range() -> void:
	assert_eq(CombatEconomy.section_reward_gold(-5), 10)
	assert_eq(CombatEconomy.section_reward_gold(99), 35)

# --- Action per-room gold drop --------------------------------------------

func test_action_gold_zero_or_within_flat_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lo: int = CombatEconomy.ACTION_GOLD_MIN
	var hi: int = CombatEconomy.ACTION_GOLD_MAX
	# The coin is flat (tier-independent), so any tier rolls the same range.
	for tier in range(4):
		for _i in range(300):
			var g: int = CombatEconomy.roll_action_combat_gold(tier, rng)
			assert_true(g == 0 or (g >= lo and g <= hi),
				"tier %d roll %d must be 0 or within [%d,%d]" % [tier, g, lo, hi])

func test_action_gold_can_drop_and_can_miss() -> void:
	# Over many rolls at a 50% chance we see both a zero and a non-zero.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var saw_zero := false
	var saw_gold := false
	for _i in range(200):
		if CombatEconomy.roll_action_combat_gold(1, rng) == 0:
			saw_zero = true
		else:
			saw_gold = true
	assert_true(saw_zero, "some rolls should miss")
	assert_true(saw_gold, "some rolls should drop gold")

func test_action_gold_ignores_tier() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# The flat coin is tier-independent: any tier (even out of range) rolls the
	# same range instead of erroring.
	for _i in range(50):
		var g: int = CombatEconomy.roll_action_combat_gold(99, rng)
		assert_true(g == 0 or (g >= CombatEconomy.ACTION_GOLD_MIN
			and g <= CombatEconomy.ACTION_GOLD_MAX))

# --- Unified shop prices --------------------------------------------------

func test_shop_price_by_rarity() -> void:
	# Every rarity maps onto the one shared scale.
	for r in range(CombatEconomy.SHOP_ITEM_PRICE_BY_RARITY.size()):
		assert_eq(CombatEconomy.shop_item_price(r),
			int(CombatEconomy.SHOP_ITEM_PRICE_BY_RARITY[r]))

func test_shop_price_is_monotonic() -> void:
	# Rarer items never cost less than commoner ones — a coherent scale.
	var prices: Array = CombatEconomy.SHOP_ITEM_PRICE_BY_RARITY
	for i in range(1, prices.size()):
		assert_gt(int(prices[i]), int(prices[i - 1]),
			"rarity %d should cost more than rarity %d" % [i, i - 1])

func test_shop_price_clamps_out_of_range() -> void:
	assert_eq(CombatEconomy.shop_item_price(-3),
		int(CombatEconomy.SHOP_ITEM_PRICE_BY_RARITY[0]))
	assert_eq(CombatEconomy.shop_item_price(99),
		int(CombatEconomy.SHOP_ITEM_PRICE_BY_RARITY[-1]))

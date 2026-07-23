extends GutTest

# Unit tests for CombatEconomy — the single source of truth for the run's gold
# economy (combat rewards, section rewards, unified shop prices). Pure math, no
# scene needed.

# --- Deckbuilder combat gold ----------------------------------------------

func test_deckbuilder_gold_steps_up_with_progress() -> void:
	assert_eq(CombatEconomy.deckbuilder_combat_gold(0, false), 20)
	assert_eq(CombatEconomy.deckbuilder_combat_gold(4, false), 20)
	assert_eq(CombatEconomy.deckbuilder_combat_gold(5, false), 35)
	assert_eq(CombatEconomy.deckbuilder_combat_gold(9, false), 35)
	assert_eq(CombatEconomy.deckbuilder_combat_gold(10, false), 55)
	assert_eq(CombatEconomy.deckbuilder_combat_gold(50, false), 55)

func test_deckbuilder_elite_multiplier() -> void:
	# Elite pays 1.5x the tier purse (int-truncated).
	assert_eq(CombatEconomy.deckbuilder_combat_gold(0, true), 30)   # 20 * 1.5
	assert_eq(CombatEconomy.deckbuilder_combat_gold(5, true), 52)   # 35 * 1.5 = 52.5 -> 52
	assert_eq(CombatEconomy.deckbuilder_combat_gold(10, true), 82)  # 55 * 1.5 = 82.5 -> 82

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

func test_action_gold_zero_or_within_tier_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for tier in range(4):
		var lo: int = int(CombatEconomy.ACTION_GOLD_MIN_BY_TIER[tier])
		var hi: int = int(CombatEconomy.ACTION_GOLD_MAX_BY_TIER[tier])
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

func test_action_gold_tier_clamps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Out-of-range tiers clamp to the nearest end instead of erroring.
	for _i in range(50):
		var g: int = CombatEconomy.roll_action_combat_gold(99, rng)
		assert_true(g == 0 or (g >= int(CombatEconomy.ACTION_GOLD_MIN_BY_TIER[-1])
			and g <= int(CombatEconomy.ACTION_GOLD_MAX_BY_TIER[-1])))

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

# --- Strategy enemy gold drops --------------------------------------------

func test_strategy_gold_table_known_kind() -> void:
	# A known fallback kind returns a chance+range (data may override, but the
	# table is never empty for these).
	var t: Dictionary = CombatEconomy.strategy_enemy_gold_table("snake")
	assert_true(t.has("gold_chance"), "snake has a gold table")
	assert_gt(int(t.get("gold_max", 0)), 0, "snake can drop gold")

func test_strategy_gold_table_unknown_kind_is_empty() -> void:
	assert_true(CombatEconomy.strategy_enemy_gold_table("not_a_real_kind").is_empty())

func test_roll_strategy_gold_within_range_or_zero() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t: Dictionary = CombatEconomy.strategy_enemy_gold_table("troll")
	var lo: int = int(t.get("gold_min", 0))
	var hi: int = int(t.get("gold_max", 0))
	for _i in range(200):
		var g: int = CombatEconomy.roll_strategy_enemy_gold("troll", rng)
		# Either the drop failed (0) or it lands within the table's range.
		assert_true(g == 0 or (g >= lo and g <= hi),
			"roll %d must be 0 or within [%d,%d]" % [g, lo, hi])

func test_roll_unknown_kind_is_zero() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(CombatEconomy.roll_strategy_enemy_gold("not_a_real_kind", rng), 0)

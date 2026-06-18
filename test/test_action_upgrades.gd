extends GutTest

# Upgraded cards in action mode. Action flattens the deck to CardData and keys
# per-card state (cooldowns, use caps) by CardData identity, so an upgraded copy
# must resolve to a cached duplicate carrying its upgraded effects/cost — and
# every upgraded copy of an id must share that one resource.

func before_each() -> void:
	GameState.reset_run()

func _mk(id: StringName, upgraded: bool = false) -> CardInstance:
	return CardInstance.from_data(Data.get_card(id), upgraded)

func test_effective_action_card_upgrades_effects_and_cost() -> void:
	var base: CardData = Data.get_card(&"strike_ironclad")
	var up: CardData = GameState.effective_action_card_data(base, true)
	assert_eq(int(up.effects[0]["value"]), 9, "Strike+ deals 9 in action, not the base 6")
	assert_eq(up.cost, base.get_effective_cost(true), "cost tracks the upgraded cost")
	assert_true(up.display_name.ends_with("+"), "upgraded form shows a + suffix")
	assert_false(up.can_upgrade, "an already-upgraded form can't upgrade again")

func test_building_upgraded_form_does_not_mutate_base() -> void:
	var base: CardData = Data.get_card(&"strike_ironclad")
	var _up: CardData = GameState.effective_action_card_data(base, true)
	assert_eq(int(base.effects[0]["value"]), 6, "the shared base resource stays at 6")
	assert_true(base.can_upgrade, "base resource still upgradeable")

func test_non_upgraded_returns_the_shared_base() -> void:
	var base: CardData = Data.get_card(&"strike_ironclad")
	assert_eq(GameState.effective_action_card_data(base, false), base,
		"base instances reuse the shared Data resource (so their state groups)")

func test_upgraded_form_is_cached_one_per_id() -> void:
	var base: CardData = Data.get_card(&"strike_ironclad")
	var a: CardData = GameState.effective_action_card_data(base, true)
	var b: CardData = GameState.effective_action_card_data(base, true)
	assert_eq(a, b, "every upgraded copy of an id shares one cached CardData")

func test_loadout_fires_upgraded_numbers() -> void:
	GameState.deck = [_mk(&"strike_ironclad", true), _mk(&"bash")]
	var loadout: Dictionary = GameState.get_action_loadout()
	var strike: CardData = null
	for c in [loadout.left, loadout.right] + loadout.auto:
		if c != null and c.id == &"strike_ironclad":
			strike = c
			break
	assert_not_null(strike, "the upgraded Strike is somewhere in the loadout")
	assert_eq(int(strike.effects[0]["value"]), 9, "and it carries its upgraded 9 damage")

func test_mixed_base_and_upgraded_copies_stay_distinct() -> void:
	# Two Bashes: one upgraded, one not. The pool must contain both a 10-dmg
	# (base) and a 12-dmg (upgraded) Bash rather than collapsing to one.
	GameState.deck = [_mk(&"strike_ironclad"), _mk(&"bash"), _mk(&"bash", true)]
	var loadout: Dictionary = GameState.get_action_loadout()
	var values: Array = []
	for c in loadout.auto:
		if c != null and c.id == &"bash":
			values.append(int(c.effects[0]["value"]))
	values.sort()
	assert_eq(values, [8, 10], "base Bash (8) and Bash+ (10) both present, distinct")

extends GutTest

# Upgraded cards in strategy mode. BattleView resolves CardData directly and used
# to read base effects off card.data, ignoring the playing instance's `upgraded`
# flag — so an upgraded Strike fired its base 6 damage. _effective_card_effects
# now threads the flag through CardData.get_effective_effects.

const BattleViewScript = preload("res://scripts/strategy/combat/BattleView.gd")

func before_each() -> void:
	GameState.reset_run()

func test_effective_card_effects_honors_upgrade_flag() -> void:
	# Bare instance — _effective_card_effects only uses CardMods + the CardData
	# getters, so it doesn't need the battle scene wired up.
	var bv = BattleViewScript.new()
	var card: CardData = Data.get_card(&"strike_ironclad")
	var base_eff: Array = bv._effective_card_effects(card, false)
	var up_eff: Array = bv._effective_card_effects(card, true)
	assert_eq(int(base_eff[0]["value"]), 6, "base Strike resolves 6")
	assert_eq(int(up_eff[0]["value"]), 9, "Strike+ resolves its upgraded 9")
	bv.free()

func test_effective_card_effects_defaults_to_base() -> void:
	# Spells and basics call the helper without an upgrade flag — must stay base.
	var bv = BattleViewScript.new()
	var card: CardData = Data.get_card(&"bash")
	var eff: Array = bv._effective_card_effects(card)
	assert_eq(int(eff[0]["value"]), 8, "no flag -> base numbers")
	bv.free()

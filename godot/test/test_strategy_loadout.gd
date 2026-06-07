extends GutTest

# Strategy loadout: duplicate copies of a card are independent slots, each with
# its own uses. Regression for "I had two Bludgeons but only one showed up".

const CombatLoadoutScript = preload("res://scripts/strategy/combat/CombatLoadout.gd")

func before_each() -> void:
	GameState.reset_run()

func _mk(id: StringName) -> CardInstance:
	return CardInstance.from_data(Data.get_card(id))

func test_duplicate_cards_are_separate_slots() -> void:
	var b1 := _mk(&"bludgeon")
	var b2 := _mk(&"bludgeon")
	GameState.deck = [b1, b2, _mk(&"strike"), _mk(&"defend")]
	var pool: Array = CombatLoadoutScript.available_from_deck(GameState.deck)
	assert_eq(pool.size(), 2, "both Bludgeons appear; Strike/Defend basics excluded")
	assert_true(pool.has(b1) and pool.has(b2), "the pool holds the two distinct instances")

func test_per_instance_uses_are_independent() -> void:
	var b1 := _mk(&"bludgeon")
	var b2 := _mk(&"bludgeon")
	var maxu: int = GameState.card_uses_max(b1)
	assert_gt(maxu, 0, "a card has at least one use")
	assert_eq(GameState.card_uses_remaining(b1), maxu, "seeds to max on first read")
	assert_true(GameState.spend_card_use_inst(b1), "spending the first copy succeeds")
	assert_eq(GameState.card_uses_remaining(b1), maxu - 1, "first copy went down by one")
	assert_eq(GameState.card_uses_remaining(b2), maxu, "the other copy is unaffected")

func test_weapons_live_in_the_weapon_slot_not_the_card_pool() -> void:
	var weapon := _mk(&"barrel")     # tagged "weapon"
	var card := _mk(&"bludgeon")
	GameState.deck = [weapon, card]
	var pool: Array = CombatLoadoutScript.available_from_deck(GameState.deck)
	assert_eq(pool.size(), 1, "weapon kept out of the card pool")
	assert_true(pool.has(card))
	var weapons: Array = CombatLoadoutScript.weapon_cards_from_deck(GameState.deck)
	assert_true(weapons.has(weapon), "weapon shows in the weapon list")

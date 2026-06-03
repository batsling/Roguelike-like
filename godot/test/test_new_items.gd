extends GutTest

# Validates the declarative wiring for Dead Eye and Duplicator — the two
# items that needed new engine vocabulary (attack_landed/attack_missed +
# streak_hit/streak_reset for Dead Eye; card_resolved + replay_card for
# Duplicator). These guard against .tres typos and enum drift; the runtime
# streak/replay behaviour is driven by DeckbuilderCombat at play time.

func _trigger_for(item: ItemData, on_name: String) -> Dictionary:
	for t in item.triggers:
		if String(t.get("on", "")) == on_name:
			return t
	return {}

func test_dead_eye_loads_with_streak_triggers() -> void:
	var it: ItemData = Data.get_item(&"dead_eye")
	assert_not_null(it, "dead_eye.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.RARE)

	var landed: Dictionary = _trigger_for(it, "attack_landed")
	assert_false(landed.is_empty(), "Dead Eye listens on attack_landed")
	assert_true(bool(landed.get("silent", false)), "streak hook is silent")
	var hit: Dictionary = landed.get("effects", [{}])[0]
	assert_eq(String(hit.get("type", "")), "streak_hit")
	assert_eq(String(hit.get("key", "")), "dead_eye")
	assert_true(bool(hit.get("attack_bonus", false)),
		"streak adds to outgoing attacks")
	assert_eq(String(hit.get("target", "")), "enemy",
		"streak_hit resolves to the enemy that was hit")

	var missed: Dictionary = _trigger_for(it, "attack_missed")
	assert_false(missed.is_empty(), "Dead Eye resets on attack_missed")
	var reset: Dictionary = missed.get("effects", [{}])[0]
	assert_eq(String(reset.get("type", "")), "streak_reset")
	assert_eq(String(reset.get("key", "")), "dead_eye")

func test_duplicator_loads_with_replay_trigger() -> void:
	var it: ItemData = Data.get_item(&"duplicator")
	assert_not_null(it, "duplicator.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.RARE)

	var resolved: Dictionary = _trigger_for(it, "card_resolved")
	assert_false(resolved.is_empty(), "Duplicator listens on card_resolved")
	assert_eq(String(resolved.get("if_card_tag", "")), "weapon")
	assert_eq(String(resolved.get("if_card_type", "")), "attack")
	var replay: Dictionary = resolved.get("effects", [{}])[0]
	assert_eq(String(replay.get("type", "")), "replay_card")
	assert_eq(int(replay.get("times", 0)), 1)

func test_card_type_gate_matches_attack_cards() -> void:
	# The if_card_type gate Duplicator leans on must resolve a weapon attack
	# card (type ATTACK) to "attack" and reject other types.
	var strike: CardData = Data.get_card(&"strike")
	assert_not_null(strike, "strike.tres should load")
	assert_true(ItemTriggers._card_type_is(strike, "attack"))
	assert_false(ItemTriggers._card_type_is(strike, "skill"))

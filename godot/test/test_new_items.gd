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

func test_duplicator_grants_replay_to_weapon_attacks() -> void:
	var it: ItemData = Data.get_item(&"duplicator")
	assert_not_null(it, "duplicator.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.RARE)

	assert_eq(it.card_grants.size(), 1, "Duplicator grants via card_grants")
	var grant: Dictionary = it.card_grants[0]
	assert_eq(String(grant.get("if_card_tag", "")), "weapon")
	assert_eq(String(grant.get("if_card_type", "")), "attack")
	assert_true(grant.get("addons", []).has("replay"),
		"grant hands out the replay addon")

func test_replay_count_folds_native_and_granted() -> void:
	# A bare "replay" addon is worth 1; "replay:N" is worth N. Duplicator in
	# inventory stacks +1 onto a matching weapon attack card.
	GameState.reset_run()
	var weapon_attack: CardData = Data.get_card(&"blasma_pistol")
	assert_not_null(weapon_attack, "blasma_pistol.tres should load")
	assert_eq(CardMods.replay_count(weapon_attack), 0,
		"no Replay before Duplicator is owned")
	GameState.add_item(Data.get_item(&"duplicator"))
	assert_eq(CardMods.replay_count(weapon_attack), 1,
		"Duplicator grants Replay 1 to weapon attacks")
	# A non-weapon card (Strike) is untouched by Duplicator.
	assert_eq(CardMods.replay_count(Data.get_card(&"strike")), 0)

func test_card_type_gate_matches_attack_cards() -> void:
	# The if_card_type gate Duplicator's grant leans on must resolve a weapon
	# attack card (type ATTACK) to "attack" and reject other types.
	var strike: CardData = Data.get_card(&"strike")
	assert_not_null(strike, "strike.tres should load")
	assert_true(ItemTriggers._card_type_is(strike, "attack"))
	assert_false(ItemTriggers._card_type_is(strike, "skill"))

extends GutTest

# Validates the declarative wiring for the custom items that needed new
# engine vocabulary: Dead Eye (attack_landed/attack_missed + streak_hit/
# streak_reset), Duplicator (the Replay addon via card_grants), Empty Syringe
# (status_amplify), and the eggs (upgrade_card_types). These guard against
# .tres typos and enum drift; the deeper runtime behaviour is driven by the
# combat scenes / GameState at play time.

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

# --- Empty Syringe -------------------------------------------------------

func test_empty_syringe_loads_with_status_amplify() -> void:
	var it: ItemData = Data.get_item(&"empty_syringe")
	assert_not_null(it, "empty_syringe.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	assert_eq(int(it.status_amplify.get("bleed", 0)), 1)
	assert_eq(int(it.status_amplify.get("poison", 0)), 1)

func test_status_amplify_bonus_sums_owned_items() -> void:
	GameState.reset_run()
	assert_eq(GameState.status_amplify_bonus(&"bleed"), 0, "nothing owned yet")
	GameState.add_item(Data.get_item(&"empty_syringe"))
	assert_eq(GameState.status_amplify_bonus(&"bleed"), 1)
	assert_eq(GameState.status_amplify_bonus(&"poison"), 1)
	assert_eq(GameState.status_amplify_bonus(&"burn"), 0, "only Bleed/Poison amplified")

func test_empty_syringe_amplifies_bleed_on_enemy_not_player() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"empty_syringe"))
	# Enemy (is_player defaults false): inflicting +2 Bleed lands as 3.
	var enemy := CombatActor.new()
	enemy.add_status(&"bleed", 2)
	assert_eq(enemy.get_status(&"bleed"), 3, "Empty Syringe adds +1 on an enemy")
	# Player buffs are never amplified.
	var player := CombatActor.from_player()
	player.add_status(&"bleed", 2)
	assert_eq(player.get_status(&"bleed"), 2, "no amplify on the player")
	# Decay (negative stacks) is never amplified.
	enemy.add_status(&"bleed", -3)
	assert_eq(enemy.get_status(&"bleed"), 0)

# --- Eggs ----------------------------------------------------------------

func test_eggs_load_with_upgrade_card_types() -> void:
	for pair in [["molten_egg", "attack"], ["toxic_egg", "skill"], ["frozen_egg", "power"]]:
		var it: ItemData = Data.get_item(StringName(pair[0]))
		assert_not_null(it, "%s.tres should load" % pair[0])
		assert_eq(it.rarity, ItemData.Rarity.UNCOMMON)
		assert_true(it.upgrade_card_types.has(pair[1]),
			"%s upgrades %s cards" % [pair[0], pair[1]])

func test_molten_egg_upgrades_attack_card_on_add() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"molten_egg"))
	# An Attack card (Strike) is upgraded the moment it enters the deck.
	var added: CardInstance = GameState.add_card_to_deck(Data.get_card(&"strike"))
	assert_not_null(added)
	assert_true(added.upgraded, "Molten Egg upgrades a freshly added Attack card")
	# A non-Attack card (Defend, a Skill) is left alone.
	var skill: CardInstance = GameState.add_card_to_deck(Data.get_card(&"defend"))
	assert_false(skill.upgraded, "Molten Egg ignores non-Attack cards")

func test_no_egg_means_no_upgrade() -> void:
	GameState.reset_run()
	var added: CardInstance = GameState.add_card_to_deck(Data.get_card(&"strike"))
	assert_false(added.upgraded, "no egg owned -> card added unupgraded")

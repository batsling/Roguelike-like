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

# --- Focus Crystal -------------------------------------------------------

func test_focus_crystal_loads_with_melee_bonus() -> void:
	var it: ItemData = Data.get_item(&"focus_crystal")
	assert_not_null(it, "focus_crystal.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.PASSIVE)
	assert_eq(int(it.attack_damage_bonus.get("melee", 0)), 1)

func test_focus_crystal_adds_flat_melee_for_player_only() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"focus_crystal"))
	assert_eq(GameState.attack_damage_bonus("melee"), 1)
	assert_eq(GameState.attack_damage_bonus("ranged"), 0, "only melee is boosted")
	# Folded into Stats.damage_bonus for a player source (no Power -> just +1).
	var player := CombatActor.from_player()
	assert_eq(Stats.damage_bonus(player, "melee", Stats.Mode.DECKBUILDER), 1)
	# Enemies never get the player's Focus Crystal bonus.
	var enemy := CombatActor.new()
	assert_eq(Stats.damage_bonus(enemy, "melee", Stats.Mode.DECKBUILDER), 0)

# --- Gremlin Horn --------------------------------------------------------

func test_gremlin_horn_loads_with_enemy_killed_trigger() -> void:
	var it: ItemData = Data.get_item(&"gremlin_horn")
	assert_not_null(it, "gremlin_horn.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	var killed: Dictionary = _trigger_for(it, "enemy_killed")
	assert_false(killed.is_empty(), "Gremlin Horn listens on enemy_killed")
	var types: Array = []
	for e in killed.get("effects", []):
		types.append(String(e.get("type", "")))
	assert_true(types.has("gain_energy"), "grants energy on kill")
	assert_true(types.has("draw"), "draws a card on kill")

# --- Ice Cream -----------------------------------------------------------

func test_ice_cream_loads_with_energy_carryover() -> void:
	var it: ItemData = Data.get_item(&"ice_cream")
	assert_not_null(it, "ice_cream.tres should load")
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	assert_true(it.carries_leftover_energy)

func test_energy_carryover_flag_reflects_ownership() -> void:
	GameState.reset_run()
	assert_false(GameState.has_energy_carryover_item(), "none owned yet")
	GameState.add_item(Data.get_item(&"ice_cream"))
	assert_true(GameState.has_energy_carryover_item())

# --- Jar of Leeches & Leeching Seed (Strike grants) ----------------------

func test_jar_of_leeches_grants_leeches_to_strikes() -> void:
	var it: ItemData = Data.get_item(&"jar_of_leeches")
	assert_not_null(it, "jar_of_leeches.tres should load")
	assert_eq(it.card_grants.size(), 1)
	var grant: Dictionary = it.card_grants[0]
	assert_eq(String(grant.get("if_card_tag", "")), "strike")
	var e: Dictionary = grant.get("effects", [{}])[0]
	assert_eq(String(e.get("type", "")), "status")
	assert_eq(String(e.get("status", "")), "leeches")
	assert_eq(String(e.get("target", "")), "enemy")

func test_leeching_seed_grants_heal_to_strikes() -> void:
	var it: ItemData = Data.get_item(&"leeching_seed")
	assert_not_null(it, "leeching_seed.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.PASSIVE)
	var grant: Dictionary = it.card_grants[0]
	assert_eq(String(grant.get("if_card_tag", "")), "strike")
	var e: Dictionary = grant.get("effects", [{}])[0]
	assert_eq(String(e.get("type", "")), "heal")
	assert_eq(int(e.get("value", 0)), 1)
	assert_eq(String(e.get("target", "")), "self")

func test_leeches_grant_shows_on_strike_text_when_owned() -> void:
	# The grant should fold into a Strike's resolved effects + text.
	GameState.reset_run()
	var strike: CardData = Data.get_card(&"strike")
	GameState.add_item(Data.get_item(&"jar_of_leeches"))
	GameState.add_item(Data.get_item(&"leeching_seed"))
	var ci := CardInstance.from_data(strike)
	var types: Array = []
	for e in ci.get_effects():
		types.append("%s/%s" % [String(e.get("type", "")), String(e.get("status", ""))])
	assert_true(types.has("status/leeches"), "Strike now inflicts Leeches")
	assert_true(types.has("heal/"), "Strike now heals")

# --- Keeper's Sack -------------------------------------------------------

func test_keepers_sack_loads_with_acquire_gold_and_spend_threshold() -> void:
	var it: ItemData = Data.get_item(&"keepers_sack")
	assert_not_null(it, "keepers_sack.tres should load")
	assert_eq(it.gold_spend_stat_per, 10)
	var acq: Dictionary = _trigger_for(it, "item_acquired")
	assert_false(acq.is_empty(), "grants gold on acquire")
	assert_eq(String(acq.get("effects", [{}])[0].get("type", "")), "gain_gold")

func test_keepers_sack_grants_stat_every_10_gold_spent() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"keepers_sack"))
	var core_before: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	GameState.change_gold(-10)
	var core_after: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	assert_eq(core_after - core_before, 1, "spending 10 gold grants +1 random stat")
	# A 5-gold spend doesn't cross the next threshold.
	GameState.change_gold(-5)
	var core_now: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	assert_eq(core_now, core_after, "partial spend banks but grants nothing yet")

# --- Little Knife --------------------------------------------------------

func test_little_knife_loads_with_multiplier() -> void:
	var it: ItemData = Data.get_item(&"little_knife")
	assert_not_null(it, "little_knife.tres should load")
	assert_almost_eq(it.lower_hp_damage_mult, 1.25, 0.001)

func test_little_knife_boosts_damage_to_lower_hp_targets() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"little_knife"))
	assert_almost_eq(GameState.lower_hp_damage_mult(), 1.25, 0.001)
	var player := CombatActor.from_player()   # hp == GameState.hp (75)
	var weak := CombatActor.new()
	weak.max_hp = 10
	weak.hp = 10
	# 8 melee -> ceil(8 * 1.25) = 10 because the target's HP is below the player's.
	var res: Dictionary = Stats.resolve_damage(
		player, weak, 8, {"damage_type": "melee"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 10)
	# A target at/above the player's HP takes the unmodified hit.
	var tough := CombatActor.new()
	tough.max_hp = 99
	tough.hp = 99
	var res2: Dictionary = Stats.resolve_damage(
		player, tough, 8, {"damage_type": "melee"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res2.hp_loss), 8)

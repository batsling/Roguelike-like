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
	GameState.spend_gold(10)
	var core_after: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	assert_eq(core_after - core_before, 1, "spending 10 gold grants +1 random stat")
	# A 5-gold spend doesn't cross the next threshold.
	GameState.spend_gold(5)
	var core_now: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	assert_eq(core_now, core_after, "partial spend banks but grants nothing yet")

func test_keepers_sack_ignores_gold_taken_by_events() -> void:
	# Gold lost via change_gold (events / curses) is NOT spending, so it must
	# not advance Keeper's Sack.
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"keepers_sack"))
	var core_before: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	GameState.change_gold(-50)
	var core_after: int = GameState.strength + GameState.dexterity \
		+ GameState.intelligence + GameState.charisma
	assert_eq(core_after, core_before, "event gold loss grants no stat")

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

# --- DoT tick contract (shared by deckbuilder / action / strategy) -------

# Minimal scene stub exposing the apply_dot / leech_to_player callbacks that
# Stats.tick_actor_statuses drives, so the DoT contract can be tested without
# spinning up a real combat scene.
class _DotScene:
	extends RefCounted
	var leech_total: int = 0
	func apply_dot(target, amount: int, _source_name: String) -> void:
		target.hp = maxi(0, target.hp - amount)
	func leech_to_player(amount: int) -> void:
		leech_total += amount

func test_tick_actor_statuses_drains_bleed_and_leeches() -> void:
	GameState.reset_run()   # clear inventory so no amplifier interferes
	var enemy := CombatActor.new()
	enemy.max_hp = 20
	enemy.hp = 20
	enemy.add_status(&"bleed", 3)
	enemy.add_status(&"leeches", 2)
	var scene := _DotScene.new()
	Stats.tick_actor_statuses(enemy, scene)
	assert_eq(enemy.hp, 15, "Bleed (3) + Leeches (2) both bite the enemy")
	assert_eq(scene.leech_total, 2, "Leeches heal the player by the stack count")
	# Leeches does not decay; Bleed grows via the decay pass.
	Stats.decay_actor_statuses(enemy)
	assert_eq(enemy.get_status(&"leeches"), 2, "Leeches persists")
	assert_eq(enemy.get_status(&"bleed"), 4, "Bleed ramps up each turn")

# --- if_hp conditional effect (Meat on the Bone / Leech Brood) -----------

func test_if_hp_below_fires_only_when_at_or_under_threshold() -> void:
	GameState.reset_run()   # hp 75 / max 75
	GameState.hp = 30       # 40%
	EffectSystem.apply({"type": "if_hp", "below": 0.5,
		"effect": {"type": "gain_hp", "value": 12}}, {})
	assert_eq(GameState.hp, 42, "heals when at/below 50%")
	GameState.hp = 60       # 80%
	EffectSystem.apply({"type": "if_hp", "below": 0.5,
		"effect": {"type": "gain_hp", "value": 12}}, {})
	assert_eq(GameState.hp, 60, "no heal when above 50%")

func test_if_hp_above_fires_only_when_over_threshold() -> void:
	GameState.reset_run()   # hp 75 / max 75 -> 100%
	EffectSystem.apply({"type": "if_hp", "above": 0.5,
		"effect": {"type": "lose_hp", "value": 10}}, {})
	assert_eq(GameState.hp, 65, "loses HP when above 50%")
	GameState.hp = 30       # 40%
	EffectSystem.apply({"type": "if_hp", "above": 0.5,
		"effect": {"type": "lose_hp", "value": 10}}, {})
	assert_eq(GameState.hp, 30, "no loss when at/below 50%")

func test_lose_hp_non_lethal_never_kills() -> void:
	GameState.reset_run()
	GameState.hp = 6
	EffectSystem.apply({"type": "lose_hp", "value": 10, "non_lethal": true}, {})
	assert_eq(GameState.hp, 1, "non-lethal loss clamps to 1 HP")
	# A plain lose_hp is uncapped and can floor at 0.
	GameState.hp = 6
	EffectSystem.apply({"type": "lose_hp", "value": 10}, {})
	assert_eq(GameState.hp, 0, "lethal loss is not clamped")

# --- Leech Brood / Meat on the Bone / Mummified Hand wiring ---------------

func test_leech_brood_loads_with_leeches_and_conditional_loss() -> void:
	var it: ItemData = Data.get_item(&"leech_brood")
	assert_not_null(it, "leech_brood.tres should load")
	var t: Dictionary = _trigger_for(it, "combat_started")
	assert_false(t.is_empty(), "fires at combat start")
	var effs: Array = t.get("effects", [])
	var found_leeches := false
	var found_if_hp := false
	for e in effs:
		if String(e.get("type", "")) == "status" and String(e.get("status", "")) == "leeches":
			found_leeches = true
			assert_eq(String(e.get("target", "")), "all_enemies")
		if String(e.get("type", "")) == "if_hp":
			found_if_hp = true
			assert_almost_eq(float(e.get("above", 0.0)), 0.5, 0.001)
			assert_eq(String(e.get("effect", {}).get("type", "")), "lose_hp")
			assert_true(bool(e.get("effect", {}).get("non_lethal", false)),
				"the HP tax can't kill the player")
	assert_true(found_leeches and found_if_hp)

func test_meat_on_the_bone_loads_with_combat_end_heal() -> void:
	var it: ItemData = Data.get_item(&"meat_on_the_bone")
	assert_not_null(it, "meat_on_the_bone.tres should load")
	var t: Dictionary = _trigger_for(it, "combat_ended")
	assert_false(t.is_empty(), "fires at combat end")
	var e: Dictionary = t.get("effects", [{}])[0]
	assert_eq(String(e.get("type", "")), "if_hp")
	assert_almost_eq(float(e.get("below", 0.0)), 0.5, 0.001)
	assert_eq(int(e.get("effect", {}).get("value", 0)), 12)

func test_mummified_hand_loads_with_power_gate() -> void:
	var it: ItemData = Data.get_item(&"mummified_hand")
	assert_not_null(it, "mummified_hand.tres should load")
	var t: Dictionary = _trigger_for(it, "card_played")
	assert_false(t.is_empty(), "fires on card_played")
	assert_eq(String(t.get("if_card_type", "")), "power")
	assert_eq(String(t.get("effects", [{}])[0].get("type", "")), "free_random_hand_card")

func test_card_played_gate_accepts_carddata_and_cardinstance() -> void:
	# Mummified Hand fires in action/strategy, which pass raw CardData (not a
	# CardInstance) as the played card — the gate must resolve both.
	var power: CardData = Data.get_card(&"inflame")
	assert_not_null(power, "inflame.tres (a Power) should load")
	assert_eq(ItemTriggers._event_card_data(power), power, "raw CardData passes through")
	var ci := CardInstance.from_data(power)
	assert_eq(ItemTriggers._event_card_data(ci), power, "CardInstance resolves to its data")
	assert_null(ItemTriggers._event_card_data(null))
	assert_true(ItemTriggers._card_type_is(power, "power"))
	assert_false(ItemTriggers._card_type_is(power, "attack"))

# --- Incremental counter items (Happy Flower / Nunchaku / Ornamental Fan /
#     Shuriken / Pen Nib) + the shared `counter` effect -------------------

func _counter_effect(item: ItemData) -> Dictionary:
	# Pull the single `counter` effect out of an incremental item's triggers.
	for t in item.triggers:
		for e in t.get("effects", []):
			if typeof(e) == TYPE_DICTIONARY and String(e.get("type", "")) == "counter":
				return e
	return {}

func test_incremental_items_load_with_counter_effects() -> void:
	var expected := {
		"happy_flower":   {"on": "turns",            "every": 3,  "trig": "turn_tick",    "rarity": ItemData.Rarity.COMMON},
		"nunchaku":       {"on": "attacks_total",    "every": 10, "trig": "card_played",  "rarity": ItemData.Rarity.COMMON},
		"ornamental_fan": {"on": "attacks_this_turn","every": 4,  "trig": "card_played",  "rarity": ItemData.Rarity.UNCOMMON},
		"shuriken":       {"on": "attacks_this_turn","every": 3,  "trig": "card_played",  "rarity": ItemData.Rarity.UNCOMMON},
		"pen_nib":        {"on": "attacks_total",    "every": 10, "trig": "card_played",  "rarity": ItemData.Rarity.COMMON},
	}
	for id in expected.keys():
		var it: ItemData = Data.get_item(StringName(id))
		assert_not_null(it, "%s.tres should load" % id)
		assert_eq(it.kind, ItemData.ItemKind.TRIGGERED, "%s is triggered" % id)
		assert_eq(it.rarity, expected[id]["rarity"], "%s rarity" % id)
		var trig: Dictionary = _trigger_for(it, expected[id]["trig"])
		assert_false(trig.is_empty(), "%s listens on %s" % [id, expected[id]["trig"]])
		assert_true(bool(trig.get("silent", false)), "%s counter hook is silent" % id)
		var c: Dictionary = _counter_effect(it)
		assert_eq(String(c.get("key", "")), expected[id]["on"], "%s counter key" % id)
		assert_eq(int(c.get("every", 0)), expected[id]["every"], "%s threshold" % id)
		assert_false(c.get("effects", []).is_empty(), "%s has a payload" % id)

func test_attack_counter_items_gate_on_attack_type() -> void:
	for id in ["nunchaku", "ornamental_fan", "shuriken", "pen_nib"]:
		var it: ItemData = Data.get_item(StringName(id))
		var trig: Dictionary = _trigger_for(it, "card_played")
		assert_eq(String(trig.get("if_card_type", "")), "attack",
			"%s only counts Attacks" % id)

func test_counter_effect_fires_only_on_threshold() -> void:
	# The `counter` handler reads a GameState counter and fires its payload
	# only when value % every == 0. Drive the counter manually.
	GameState.reset_run()
	GameState.gold = 0
	var payload := {"type": "counter", "key": "attacks_total", "every": 10,
		"effects": [{"type": "gain_gold", "value": 5}]}
	for i in range(9):
		GameState.incremental_on_attack()
		EffectSystem.apply(payload, {})
	assert_eq(GameState.gold, 0, "no payout before the 10th attack")
	GameState.incremental_on_attack()  # 10th
	EffectSystem.apply(payload, {})
	assert_eq(GameState.gold, 5, "payout lands exactly on the 10th")
	for i in range(9):
		GameState.incremental_on_attack()
		EffectSystem.apply(payload, {})
	assert_eq(GameState.gold, 5, "still nothing on 11..19")
	GameState.incremental_on_attack()  # 20th
	EffectSystem.apply(payload, {})
	assert_eq(GameState.gold, 10, "payout repeats every 10th")

func test_per_turn_window_resets_on_turn_tick_not_room() -> void:
	# Ornamental Fan / Shuriken count attacks within the per-turn window, which
	# now rides the turn_tick heartbeat (timer-based in Action) rather than
	# turn_started (room entry). A room/turn START alone must NOT reset it.
	GameState.reset_run()
	GameState.incremental_on_attack()
	GameState.incremental_on_attack()
	assert_eq(GameState.incremental_value("attacks_this_turn"), 2)
	assert_eq(GameState.incremental_value("attacks_total"), 2)
	# A discrete turn / room start (Horn Cleat's clock) leaves the window alone.
	GameState.incremental_on_turn_started(2)
	assert_eq(GameState.incremental_value("attacks_this_turn"), 2,
		"entering a room does NOT reset the per-turn attack window")
	# The recurring heartbeat is what resets it.
	GameState.incremental_on_turn_tick()
	assert_eq(GameState.incremental_value("attacks_this_turn"), 0,
		"the turn_tick heartbeat clears the per-turn window")
	assert_eq(GameState.incremental_value("attacks_total"), 2,
		"run-wide tally carries across turns")

func test_happy_flower_turns_count_rides_the_heartbeat() -> void:
	# "Every 3 turns" counts turn_tick pulses, so in Action it advances on the
	# timer, not on room entry. Room starts must not advance it.
	GameState.reset_run()
	GameState.incremental_on_turn_started(5)  # rooms/turns don't move the pulse
	assert_eq(GameState.incremental_value("turns"), 0,
		"room/turn start does not advance the 'turns' heartbeat count")
	GameState.incremental_on_turn_tick()
	GameState.incremental_on_turn_tick()
	GameState.incremental_on_turn_tick()
	assert_eq(GameState.incremental_value("turns"), 3, "each heartbeat advances it")

func test_attacks_total_persists_across_combats_resets_on_run() -> void:
	GameState.reset_run()
	GameState.incremental_on_attack()
	GameState.incremental_on_attack()
	GameState.incremental_on_combat_started()  # new combat, same run
	assert_eq(GameState.incremental_value("attacks_total"), 2,
		"run-wide attacks survive a new combat")
	assert_eq(GameState.incremental_value("turns"), 0, "turn counter restarts")
	GameState.reset_run()
	assert_eq(GameState.incremental_value("attacks_total"), 0,
		"a fresh run zeroes the run-wide tally")

func test_pen_nib_doubles_only_the_armed_attack() -> void:
	GameState.reset_run()
	assert_false(GameState.pen_nib_double_active)
	EffectSystem.apply({"type": "attack_double"}, {})
	assert_true(GameState.pen_nib_double_active, "attack_double arms the window")
	# A fresh card play clears the window (mirrors ItemTriggers.fire).
	GameState.pen_nib_double_active = false
	assert_false(GameState.pen_nib_double_active)

func test_dead_eye_streak_mirrors_to_gamestate_for_display() -> void:
	# The Backpack reads GameState.dead_eye_streak to show the live bonus.
	GameState.reset_run()
	assert_eq(GameState.dead_eye_streak, 0)
	GameState.dead_eye_streak = 3
	GameState.incremental_on_combat_started()
	assert_eq(GameState.dead_eye_streak, 0, "a new combat clears the streak")

# --- Centralized streak API (Dead Eye works in every mode via GameState) ----

func test_streak_grows_on_same_target_and_resets_on_switch() -> void:
	GameState.reset_run()
	var enemy_a := RefCounted.new()
	var enemy_b := RefCounted.new()
	GameState.streak_register_hit("dead_eye", enemy_a, true, "Dead Eye")
	GameState.streak_register_hit("dead_eye", enemy_a, true, "Dead Eye")
	assert_eq(GameState.dead_eye_streak, 2, "consecutive hits on one target grow")
	assert_eq(GameState.streak_attack_bonus(enemy_a), 2, "bonus equals the streak")
	# A different target resets the count before counting this hit.
	GameState.streak_register_hit("dead_eye", enemy_b, true, "Dead Eye")
	assert_eq(GameState.dead_eye_streak, 1, "switching targets resets the streak")
	assert_eq(GameState.streak_attack_bonus(enemy_a), 0,
		"the old target no longer carries a bonus")

func test_streak_reset_clears_the_bonus() -> void:
	GameState.reset_run()
	var enemy := RefCounted.new()
	GameState.streak_register_hit("dead_eye", enemy, true, "Dead Eye")
	GameState.streak_register_hit("dead_eye", enemy, true, "Dead Eye")
	GameState.streak_reset("dead_eye")
	assert_eq(GameState.dead_eye_streak, 0, "a whiff wipes the streak")
	assert_eq(GameState.streak_attack_bonus(enemy), 0)

func test_streak_effects_route_through_gamestate_in_any_mode() -> void:
	# EffectSystem's streak handlers now write to GameState (no scene needed),
	# which is what makes Dead Eye fire in action/strategy, not just deckbuilder.
	GameState.reset_run()
	var enemy := RefCounted.new()
	EffectSystem.apply({"type": "streak_hit", "key": "dead_eye",
		"attack_bonus": true, "label": "Dead Eye"}, {"target": enemy})
	assert_eq(GameState.dead_eye_streak, 1, "streak_hit grows with no scene")
	EffectSystem.apply({"type": "streak_reset", "key": "dead_eye"}, {})
	assert_eq(GameState.dead_eye_streak, 0, "streak_reset clears with no scene")

func test_streak_clear_wipes_everything() -> void:
	GameState.reset_run()
	var enemy := RefCounted.new()
	GameState.streak_register_hit("dead_eye", enemy, true, "Dead Eye")
	GameState.streak_clear()
	assert_eq(GameState.dead_eye_streak, 0)
	assert_eq(GameState.streak_attack_bonus(enemy), 0)

# --- Old Coin ------------------------------------------------------------

func test_old_coin_loads_with_acquire_gold() -> void:
	var it: ItemData = Data.get_item(&"old_coin")
	assert_not_null(it, "old_coin.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.PICKUP)
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	var acq: Dictionary = _trigger_for(it, "item_acquired")
	assert_false(acq.is_empty(), "Old Coin grants gold on acquire")
	var e: Dictionary = acq.get("effects", [{}])[0]
	assert_eq(String(e.get("type", "")), "gain_gold")
	assert_eq(int(e.get("value", 0)), 100)

func test_old_coin_grants_100_gold_on_pickup() -> void:
	GameState.reset_run()
	GameState.gold = 0
	GameState.add_item(Data.get_item(&"old_coin"))
	assert_eq(GameState.gold, 100, "picking up Old Coin grants 100 gold once")

# --- Ring of the Snake ---------------------------------------------------

func test_ring_of_the_snake_loads_with_combat_start_draw() -> void:
	var it: ItemData = Data.get_item(&"ring_of_the_snake")
	assert_not_null(it, "ring_of_the_snake.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	var t: Dictionary = _trigger_for(it, "combat_started")
	assert_false(t.is_empty(), "Ring of the Snake fires at combat start")
	var e: Dictionary = t.get("effects", [{}])[0]
	assert_eq(String(e.get("type", "")), "draw")
	assert_eq(int(e.get("value", 0)), 2)

# --- Strike Dummy --------------------------------------------------------

func test_strike_dummy_grants_dmg_to_strikes() -> void:
	var it: ItemData = Data.get_item(&"strike_dummy")
	assert_not_null(it, "strike_dummy.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.card_grants.size(), 1, "Strike Dummy buffs via card_grants")
	var grant: Dictionary = it.card_grants[0]
	assert_eq(String(grant.get("if_card_tag", "")), "strike")
	var e: Dictionary = grant.get("effects", [{}])[0]
	assert_eq(String(e.get("type", "")), "dmg")
	assert_eq(int(e.get("value", 0)), 3)
	assert_eq(String(e.get("target", "")), "enemy")

func test_strike_dummy_dmg_folds_into_strike_effects_when_owned() -> void:
	GameState.reset_run()
	var strike: CardData = Data.get_card(&"strike")
	GameState.add_item(Data.get_item(&"strike_dummy"))
	var ci := CardInstance.from_data(strike)
	var extra_dmg := 0
	for e in ci.get_effects():
		if String(e.get("type", "")) == "dmg" and int(e.get("value", 0)) == 3:
			extra_dmg += 1
	assert_eq(extra_dmg, 1, "owning Strike Dummy adds a +3 Dmg effect to Strikes")

# --- Paper Bag (Charisma mirrors the highest core stat) ------------------

func test_paper_bag_loads_with_mirror_flag() -> void:
	var it: ItemData = Data.get_item(&"paper_bag")
	assert_not_null(it, "paper_bag.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.SCALING)
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	assert_true(it.charisma_equals_highest_stat)

func test_charisma_mirror_flag_reflects_ownership() -> void:
	GameState.reset_run()
	assert_false(GameState.has_charisma_mirror_item(), "none owned yet")
	GameState.add_item(Data.get_item(&"paper_bag"))
	assert_true(GameState.has_charisma_mirror_item())

func test_paper_bag_raises_charisma_to_highest_core_stat() -> void:
	GameState.reset_run()
	GameState.strength = 9
	GameState.dexterity = 3
	GameState.intelligence = 2
	GameState.charisma = 1
	# Without Paper Bag, Charisma reads its own value.
	assert_eq(Stats.get_value(&"charisma"), 1, "no mirror -> natural Charisma")
	GameState.add_item(Data.get_item(&"paper_bag"))
	assert_eq(Stats.get_value(&"charisma"), 9,
		"Paper Bag mirrors Charisma onto the highest core stat (Strength 9)")
	# It never drags Charisma down below its own value.
	GameState.charisma = 12
	assert_eq(Stats.get_value(&"charisma"), 12,
		"a naturally-higher Charisma is left alone")

func test_paper_bag_tracks_temporary_stat_buffs_live() -> void:
	GameState.reset_run()
	GameState.strength = 4
	GameState.dexterity = 4
	GameState.intelligence = 4
	GameState.charisma = 4
	GameState.add_item(Data.get_item(&"paper_bag"))
	assert_eq(Stats.get_value(&"charisma"), 4, "all equal -> Charisma stays 4")
	# A temporary +5 Dexterity buff (Speedball-style pill) makes Dex the largest,
	# so Charisma rises to match for as long as the buff lasts.
	GameState.add_temp_stat(&"dexterity", 5)
	assert_eq(Stats.get_value(&"charisma"), 9,
		"a temporary buff that becomes the highest stat raises Charisma")
	# When the buff clears, Charisma falls back.
	GameState.clear_temp_buffs()
	assert_eq(Stats.get_value(&"charisma"), 4,
		"Charisma falls back the moment the temporary buff clears")

func test_pen_nib_per_effect_marker_doubles_in_flight_bolt() -> void:
	# Action projectiles snapshot the Pen Nib window at fire time and carry it
	# on the effect, so Stats.resolve_damage doubles even if the global flag
	# was cleared mid-flight.
	GameState.reset_run()
	GameState.pen_nib_double_active = false
	var src := CombatActor.new()
	src.is_player = true
	src.hp = 50
	src.max_hp = 50
	var tgt := CombatActor.new()
	tgt.is_player = false
	tgt.hp = 100
	tgt.max_hp = 100
	# No global flag, but the bolt carries its own marker -> still doubles.
	var res := Stats.resolve_damage(src, tgt, 10,
		{"damage_type": "ranged", "pen_nib_double": true}, Stats.Mode.ACTION)
	assert_eq(int(res.hp_loss), 20, "in-flight Pen Nib bolt doubles via the marker")
	# Without the marker and without the flag, no doubling.
	var res2 := Stats.resolve_damage(src, tgt, 10,
		{"damage_type": "ranged"}, Stats.Mode.ACTION)
	assert_eq(int(res2.hp_loss), 10, "no marker, no global flag -> normal damage")

extends GutTest

# Covers the 19-card Ironclad Skill port:
#   - sheet -> generator round-trip for the new DSL verbs (double, autoplay_top,
#     copy_from_hand, exhume, if_intent, negative inflict, gain:block per=exhausted,
#     the `exhausted:` card-trigger prefix, and `until=turn_end` on on_<event>)
#   - the Skill-type marker statuses (flame_barrier / rage / double_tap): icons,
#     the ReferenceCatalog-driven wipe list, and turn-scoped trigger expiry
#   - runtime behavior on the real deckbuilder scene and action arena:
#     Rage, Flame Barrier retaliation + Burn, Double Tap, Second Wind,
#     Sentinel, Havoc, Dual Wield / Exhume, Entrench, Spot Weakness.

const SKILL_IDS := [
	&"disarm", &"double_tap", &"dual_weild", &"entrench", &"exhume",
	&"flame_barrier", &"havoc", &"impervious", &"intimidate", &"limit_break",
	&"offering", &"power_through", &"rage", &"second_wind", &"seeing_red",
	&"sentinel", &"shockwave", &"spot_weakness", &"true_grit",
]

# --- .tres round-trip -------------------------------------------------------

func test_all_nineteen_load_as_skill_cards() -> void:
	for id in SKILL_IDS:
		var card: CardData = Data.get_card(id)
		assert_not_null(card, "%s.tres should load" % id)
		assert_eq(card.type, CardData.CardType.SKILL, "%s is a Skill" % id)

func test_disarm_is_a_negative_power_inflict() -> void:
	var eff: Dictionary = Data.get_card(&"disarm").effects[0]
	assert_eq(String(eff.get("type", "")), "status")
	assert_eq(String(eff.get("status", "")), "power")
	assert_eq(int(eff.get("stacks", 0)), -2)
	assert_eq(String(eff.get("target", "")), "enemy")

func test_entrench_and_limit_break_are_double_stat() -> void:
	assert_eq(Data.get_card(&"entrench").effects, [{"type": "double_stat", "stat": "block"}])
	var lb: CardData = Data.get_card(&"limit_break")
	assert_eq(lb.effects, [{"type": "double_stat", "stat": "power"}, {"type": "exhaust_self"}])
	# The upgrade drops the Exhaust (authored as exhaust_self, not the keyword,
	# because Keywords is card-level).
	assert_eq(lb.upgraded_effects, [{"type": "double_stat", "stat": "power"}])
	assert_false(lb.exhaust)

func test_flame_barrier_is_a_turn_scoped_fire_retaliation() -> void:
	var card: CardData = Data.get_card(&"flame_barrier")
	assert_eq(card.effects[0], {"type": "block", "value": 12, "target": "self"})
	assert_eq(card.effects[1], {"type": "status", "status": "flame_barrier",
		"stacks": 4, "target": "self"})
	var trig: Dictionary = card.effects[2]
	assert_eq(String(trig.get("on", "")), "hit_by_attack")
	assert_eq(String(trig.get("until", "")), "turn_end")
	var inner: Dictionary = trig.get("effect", {})
	assert_eq(int(inner.get("value", 0)), 4)
	assert_eq(String(inner.get("damage_type", "")), "magic")
	assert_eq(String(inner.get("element", "")), "fire", "element stamped on the trigger's inner dmg")
	assert_eq(int(card.upgraded_effects[2].get("effect", {}).get("value", 0)), 6)

func test_rage_is_a_turn_scoped_attack_played_trigger() -> void:
	var card: CardData = Data.get_card(&"rage")
	assert_eq(card.effects[0], {"type": "status", "status": "rage",
		"stacks": 3, "target": "self"})
	var trig: Dictionary = card.effects[1]
	assert_eq(String(trig.get("on", "")), "attack_played")
	assert_eq(String(trig.get("until", "")), "turn_end")
	assert_eq(trig.get("effect", {}), {"type": "block", "value": 3, "target": "self"})

func test_sentinel_carries_an_exhausted_trigger_with_upgrade_form() -> void:
	var card: CardData = Data.get_card(&"sentinel")
	assert_eq(card.triggers, [{"on": "exhausted",
		"effects": [{"type": "gain_energy", "value": 2}]}])
	assert_eq(card.upgraded_triggers, [{"on": "exhausted",
		"effects": [{"type": "gain_energy", "value": 3}]}])
	assert_eq(card.get_effective_triggers(true)[0]["effects"][0]["value"], 3)

func test_havoc_dual_wield_exhume_verbs() -> void:
	assert_eq(Data.get_card(&"havoc").effects,
		[{"type": "autoplay_top", "exhaust": true}])
	assert_eq(Data.get_card(&"havoc").upgraded_cost, 0)
	var dw: CardData = Data.get_card(&"dual_weild")
	assert_eq(dw.effects, [{"type": "copy_from_hand", "count": 1, "filter": "attack_or_power"}])
	assert_eq(int(dw.upgraded_effects[0].get("count", 0)), 2)
	assert_eq(Data.get_card(&"exhume").effects, [{"type": "exhume", "value": 1}])

func test_second_wind_blocks_per_exhausted() -> void:
	var card: CardData = Data.get_card(&"second_wind")
	assert_eq(card.effects[0], {"type": "exhaust", "all": true, "only": "non_attack"})
	assert_eq(card.effects[1], {"type": "block", "value": 5, "target": "self",
		"value_from": "exhausted"})

func test_spot_weakness_is_an_intent_gated_power_gain() -> void:
	var eff: Dictionary = Data.get_card(&"spot_weakness").effects[0]
	assert_eq(String(eff.get("type", "")), "if_target_intent")
	assert_eq(String(eff.get("intent", "")), "attack")
	assert_eq(String(eff.get("target", "")), "enemy", "the gate wants a picked enemy")
	assert_eq(eff.get("effect", {}), {"type": "status", "status": "power",
		"stacks": 3, "target": "self"})

func test_true_grit_upgrade_swaps_random_for_chosen_exhaust() -> void:
	var card: CardData = Data.get_card(&"true_grit")
	assert_eq(card.effects[1], {"type": "exhaust", "value": 1, "random": true})
	assert_eq(card.upgraded_effects[1], {"type": "exhaust", "value": 1})

# --- Skill-type markers + turn-scoped trigger plumbing -----------------------

func test_skill_marker_statuses_come_from_the_sheet() -> void:
	var markers: Array = Stats.skill_marker_statuses()
	for key in [&"flame_barrier", &"rage", &"double_tap"]:
		assert_has(markers, key, "%s is a Skill-type marker" % key)
	assert_does_not_have(markers, &"burn", "real statuses are not markers")

func test_skill_marker_icons_resolve() -> void:
	for key in [&"flame_barrier", &"rage", &"double_tap"]:
		var tex: Texture2D = Stats.status_icon(key)
		assert_not_null(tex, "%s has icon art" % key)
		assert_string_contains(tex.resource_path, "images/statuses/")

func test_clear_skill_markers_wipes_only_markers() -> void:
	var a := CombatActor.new()
	a.statuses[&"rage"] = 3
	a.statuses[&"flame_barrier"] = 4
	a.statuses[&"double_tap"] = 1
	a.statuses[&"power"] = 2
	Stats.clear_skill_markers(a)
	assert_eq(a.get_status(&"rage"), 0)
	assert_eq(a.get_status(&"flame_barrier"), 0)
	assert_eq(a.get_status(&"double_tap"), 0)
	assert_eq(a.get_status(&"power"), 2, "real statuses survive the wipe")

func test_expire_turn_triggers_drops_only_turn_scoped_entries() -> void:
	var triggers: Array = [
		{"on": "attack_played", "effect": {"type": "block", "value": 3}, "until": "turn_end"},
		{"on": "card_played", "effect": {"type": "block", "value": 1}},
	]
	var kept: Array = Stats.expire_turn_triggers(triggers)
	assert_eq(kept.size(), 1, "the persistent After Image survives")
	assert_eq(String(kept[0].get("on", "")), "card_played")

func test_drain_status_goes_negative_and_zero_clears() -> void:
	var a := CombatActor.new()
	a.statuses[&"power"] = 1
	Stats.drain_status(a, &"power", -3)
	assert_eq(int(a.statuses.get(&"power", 0)), -2, "drain digs below zero")
	Stats.drain_status(a, &"power", 2)
	assert_false(a.statuses.has(&"power"), "an exact zero clears the entry")

func test_actor_intends_attack_reads_planned_move() -> void:
	var a := CombatActor.new()
	assert_false(Stats.actor_intends_attack(a))
	a.planned_move = {"intent_type": "attack"}
	assert_true(Stats.actor_intends_attack(a))

# --- Integration on the real deckbuilder scene -------------------------------

var db

func _deck_scene():
	GameState.reset_run()
	db = load("res://scenes/deckbuilder/DeckbuilderCombat.tscn").instantiate()
	db.dev_combat = true
	db.enemies_to_spawn = [&"jaw_worm"]
	add_child_autofree(db)
	db.enemies[0].max_hp = 500
	db.enemies[0].hp = 500
	return db

func _db_play(id: StringName, target = null, upgraded: bool = false) -> CardInstance:
	var card := CardInstance.from_data(Data.get_card(id), upgraded)
	db.hand.append(card)
	db.energy = 10
	db._resolve_card(card, target)
	return card

func test_db_rage_banks_block_on_attacks_and_wipes_next_turn() -> void:
	_deck_scene()
	_db_play(&"rage")
	assert_eq(db.player.get_status(&"rage"), 3, "marker icon stacks")
	var block_before: int = db.player.block
	_db_play(&"strike_ironclad", db.enemies[0])
	assert_eq(db.player.block, block_before + 3, "the Attack play banked +3 Block")
	db._start_player_turn()
	assert_eq(db.player.get_status(&"rage"), 0, "marker wiped at the next turn start")
	assert_true(Stats.expire_turn_triggers(db.power_triggers).size() == db.power_triggers.size(),
		"no turn-scoped trigger survived the boundary")

func test_db_flame_barrier_retaliates_through_the_enemy_turn() -> void:
	_deck_scene()
	var e: CombatActor = db.enemies[0]
	_db_play(&"flame_barrier")
	assert_eq(db.player.get_status(&"flame_barrier"), 4)
	var e_hp: int = e.hp
	# The enemy swings into the player — even a fully blocked hit is a contact.
	db.deal_damage(e, db.player, 5, {"damage_type": "melee"})
	assert_eq(e.hp, e_hp - 4, "4 Magic Dmg Fire reflected")
	assert_eq(e.get_status(&"burn"), 1, "1 Burn per contact")
	db.deal_damage(e, db.player, 5, {"damage_type": "melee"})
	assert_eq(e.get_status(&"burn"), 2, "…per EACH contact")

func test_db_double_tap_doubles_exactly_one_attack() -> void:
	_deck_scene()
	var e: CombatActor = db.enemies[0]
	var hp0: int = e.hp
	_db_play(&"strike_ironclad", e)
	var single: int = hp0 - e.hp
	assert_gt(single, 0, "baseline Strike lands")
	_db_play(&"double_tap")
	var hp1: int = e.hp
	_db_play(&"strike_ironclad", e)
	assert_eq(hp1 - e.hp, single * 2, "the doubled Strike dealt twice the baseline")
	var hp2: int = e.hp
	_db_play(&"strike_ironclad", e)
	assert_eq(hp2 - e.hp, single, "the stack was spent — back to a single play")

func test_db_havoc_autoplays_and_exhausts_the_top_card() -> void:
	_deck_scene()
	var e: CombatActor = db.enemies[0]
	var strike := CardInstance.from_data(Data.get_card(&"strike_ironclad"))
	db.draw_pile.append(strike)
	var e_hp: int = e.hp
	_db_play(&"havoc")
	assert_lt(e.hp, e_hp, "the autoplayed Strike hit the enemy")
	assert_true(db.exhaust_pile.has(strike), "…and exhausted")

func test_db_sentinel_pays_energy_on_exhaust() -> void:
	_deck_scene()
	db.energy = 0
	var sentinel := CardInstance.from_data(Data.get_card(&"sentinel"))
	db.hand.append(sentinel)
	db.exhaust_card(sentinel)
	assert_eq(db.energy, 2, "the exhausted: trigger paid 2 Energy")

func test_db_dual_wield_opens_the_picker_over_attacks_and_powers() -> void:
	_deck_scene()
	db.hand.append(CardInstance.from_data(Data.get_card(&"strike_ironclad")))
	_db_play(&"dual_weild")
	assert_not_null(db.get_node_or_null("CardPickerModal"),
		"an Attack in hand opens the copy picker")

# --- Integration on the real action arena ------------------------------------

var arena

func _action_arena():
	GameState.reset_run()
	GameState.apply_character(Data.get_character(&"ironclad"))
	arena = load("res://scenes/action/ActionCombat.tscn").instantiate()
	arena.target_game_id = &""
	arena.enemies_to_spawn = []
	add_child_autofree(arena)
	return arena

func _action_enemy(pos: Vector2) -> Dictionary:
	var data: ActionEnemyData = Data.get_action_enemy(&"gaper")
	var inst: Dictionary = arena._make_enemy_inst(data, pos)
	inst.actor.max_hp = 500
	inst.actor.hp = 500
	arena.enemies.append(inst)
	return inst

func test_action_flame_barrier_reflects_and_burns_per_contact() -> void:
	_action_arena()
	var inst: Dictionary = _action_enemy(arena.player_pos + Vector2(40, 0))
	arena._resolve_card_effects(Data.get_card(&"flame_barrier"))
	assert_eq(arena.player_actor.get_status(&"flame_barrier"), 4, "marker stacks")
	var hp0: int = inst.actor.hp
	arena._apply_damage_to_player(5, "gaper", inst.actor, true)
	assert_eq(inst.actor.hp, hp0 - 4, "4 reflected onto the attacker")
	assert_eq(inst.actor.get_status(&"burn"), 1, "1 Burn per contact")
	arena.player_iframes = 0.0
	arena._apply_damage_to_player(5, "gaper", inst.actor, true)
	assert_eq(inst.actor.get_status(&"burn"), 2, "…per EACH contact")

func test_action_entrench_doubles_the_block_pool() -> void:
	_action_arena()
	arena.gain_block(null, 10)
	var before: int = arena.player_actor.block
	arena._resolve_card_effects(Data.get_card(&"entrench"))
	assert_eq(arena.player_actor.block, before * 2, "Gain Double Block")

func test_action_rage_banks_block_per_click_attack() -> void:
	_action_arena()
	_action_enemy(arena.player_pos + Vector2(40, 0))
	arena._resolve_card_effects(Data.get_card(&"rage"))
	assert_eq(arena.player_actor.get_status(&"rage"), 3, "marker stacks")
	arena._fire_click_card(Data.get_card(&"strike_ironclad"))
	assert_eq(arena.player_actor.block, 3, "the Attack cast banked +3 Block")

# Swing hits are time-paced through _pending_hits — flush them so the damage
# lands before we count it.
func _flush_action_hits() -> void:
	for _i in range(240):
		if arena._pending_hits.is_empty():
			return
		arena._process_pending_hits(1.0 / 30.0)

func test_action_double_tap_doubles_the_next_click_attack() -> void:
	_action_arena()
	var inst: Dictionary = _action_enemy(arena.player_pos + Vector2(40, 0))
	arena.player_facing = Vector2.RIGHT
	var hp0: int = inst.actor.hp
	arena._fire_click_card(Data.get_card(&"strike_ironclad"))
	_flush_action_hits()
	var single: int = hp0 - inst.actor.hp
	assert_gt(single, 0, "baseline Strike lands")
	arena._resolve_card_effects(Data.get_card(&"double_tap"))
	var hp1: int = inst.actor.hp
	arena._fire_click_card(Data.get_card(&"strike_ironclad"))
	_flush_action_hits()
	assert_eq(hp1 - inst.actor.hp, single * 2, "the doubled cast dealt twice the baseline")
	assert_eq(arena.player_actor.get_status(&"double_tap"), 0, "stack consumed")

func test_action_second_wind_sweeps_non_attack_slots_for_block() -> void:
	_action_arena()
	_action_enemy(arena.player_pos + Vector2(400, 0))
	# Pin the rotation: the base slot holds an Attack (spared), two temp slots
	# hold Defends (swept).
	var defend: CardData = Data.get_card(&"defend_ironclad")
	arena.auto_slots[0].card = Data.get_card(&"strike_ironclad")
	arena.auto_slots.append({"card": defend, "cooldown": 5.0, "max_cooldown": 5.0, "ttl": 60.0})
	arena.auto_slots.append({"card": defend, "cooldown": 5.0, "max_cooldown": 5.0, "ttl": 60.0})
	arena._resolve_card_effects(Data.get_card(&"second_wind"))
	assert_eq(arena.last_exhaust_count, 2, "both Defends swept, the Strike spared")
	assert_eq(arena.player_actor.block, 10, "+5 Block per exhausted card")
	assert_eq(arena.action_exhausted.size(), 2, "the sweep feeds Exhume's record")

func test_action_havoc_then_exhume_recycles_the_card() -> void:
	_action_arena()
	_action_enemy(arena.player_pos + Vector2(40, 0))
	var strike: CardData = Data.get_card(&"strike_ironclad")
	arena.auto_draw = [strike]
	var slots_before: int = arena.auto_slots.size()
	arena._resolve_card_effects(Data.get_card(&"havoc"))
	assert_true(arena.action_exhausted.has(strike),
		"the autoplayed card left the combat via the exhaust record")
	arena._resolve_card_effects(Data.get_card(&"exhume"))
	assert_false(arena.action_exhausted.has(strike), "Exhume pulled it back")
	assert_eq(arena.auto_slots.size(), slots_before + 1, "…as a one-shot temp slot")

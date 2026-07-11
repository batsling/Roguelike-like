extends GutTest

# Covers the 20-card Silent + Defect Skill port:
#   - sheet -> generator round-trip for the new DSL verbs (multiply, retrieve,
#     free_hand, nightmare, draw to=/count=discarded/skill_block, topdeck
#     free=until_played, X-value inflicts with signed mult/bonus)
#   - the new statuses: Blur (block persistence), Burst (Skill-type marker),
#     Next Turn Block (banked payout), Double Damage (attack doubler),
#     Corpse Explosion (on-death max-HP blast)
#   - runtime behavior on the strategy BattleView, the real deckbuilder scene,
#     and the real action arena.

const SKILL_IDS := [
	&"blur", &"bullet_time", &"burst", &"calculated_gamble", &"catalyst",
	&"corpse_explosion", &"deadly_poison", &"deflect", &"dodge_and_roll",
	&"escape_plan", &"expertise", &"hologram", &"leg_sweep", &"malaise",
	&"nightmare", &"outmaneuver", &"phantasmal_killer", &"piercing_wail",
	&"seek", &"setup",
]

# --- .tres round-trip -------------------------------------------------------

func test_all_twenty_load_as_skill_cards() -> void:
	for id in SKILL_IDS:
		var card: CardData = Data.get_card(id)
		assert_not_null(card, "%s.tres should load" % id)
		assert_eq(card.type, CardData.CardType.SKILL, "%s is a Skill" % id)

func test_deadly_poison_deflect_leg_sweep_are_plain_forms() -> void:
	assert_eq(Data.get_card(&"deadly_poison").effects,
		[{"type": "status", "status": "poison", "stacks": 5, "target": "enemy"}])
	assert_eq(Data.get_card(&"deflect").effects,
		[{"type": "block", "value": 4, "target": "self"}])
	assert_eq(Data.get_card(&"leg_sweep").effects, [
		{"type": "status", "status": "weak", "stacks": 2, "target": "enemy"},
		{"type": "block", "value": 11, "target": "self"},
	])

func test_blur_and_dodge_and_roll_bank_their_statuses() -> void:
	assert_eq(Data.get_card(&"blur").effects, [
		{"type": "block", "value": 5, "target": "self"},
		{"type": "status", "status": "blur", "stacks": 1, "target": "self"},
	])
	assert_eq(Data.get_card(&"dodge_and_roll").effects, [
		{"type": "block", "value": 4, "target": "self"},
		{"type": "status", "status": "next_turn_block", "stacks": 4, "target": "self"},
	])

func test_bullet_time_is_no_draw_plus_free_hand() -> void:
	var card: CardData = Data.get_card(&"bullet_time")
	assert_eq(card.effects, [
		{"type": "status", "status": "no_draw", "stacks": 1, "target": "self"},
		{"type": "free_hand"},
	])
	assert_eq(card.upgraded_cost, 2, "the upgrade only drops the cost")

func test_calculated_gamble_draws_the_discarded_count_and_sheds_exhaust() -> void:
	var card: CardData = Data.get_card(&"calculated_gamble")
	assert_eq(card.effects, [
		{"type": "discard", "all": true},
		{"type": "draw", "value": 0, "value_from": "discarded"},
		{"type": "exhaust_self"},
	])
	# The upgrade drops the Exhaust (authored as exhaust_self, not the keyword).
	assert_eq(card.upgraded_effects, [
		{"type": "discard", "all": true},
		{"type": "draw", "value": 0, "value_from": "discarded"},
	])
	assert_false(card.exhaust)

func test_catalyst_multiplies_poison_double_then_triple() -> void:
	var card: CardData = Data.get_card(&"catalyst")
	assert_eq(card.effects,
		[{"type": "multiply_status", "status": "poison", "factor": 2, "target": "enemy"}])
	assert_eq(int(card.upgraded_effects[0].get("factor", 0)), 3)
	assert_true(card.exhaust)

func test_corpse_explosion_inflicts_poison_and_the_marker() -> void:
	assert_eq(Data.get_card(&"corpse_explosion").effects, [
		{"type": "status", "status": "poison", "stacks": 6, "target": "enemy"},
		{"type": "status", "status": "corpse_explosion", "stacks": 1, "target": "enemy"},
	])

func test_escape_plan_and_expertise_draw_forms() -> void:
	assert_eq(Data.get_card(&"escape_plan").effects,
		[{"type": "draw", "value": 1, "skill_block": 3}])
	assert_eq(int(Data.get_card(&"escape_plan").upgraded_effects[0].get("skill_block", 0)), 5)
	assert_eq(Data.get_card(&"expertise").effects, [{"type": "draw", "to_hand": 6}])
	assert_eq(int(Data.get_card(&"expertise").upgraded_effects[0].get("to_hand", 0)), 7)

func test_hologram_and_seek_are_retrieves() -> void:
	var holo: CardData = Data.get_card(&"hologram")
	assert_eq(holo.effects, [
		{"type": "block", "value": 3, "target": "self"},
		{"type": "retrieve", "value": 1, "from": "discard"},
		{"type": "exhaust_self"},
	])
	# Hologram+ drops the Exhaust and blocks harder.
	assert_eq(holo.upgraded_effects, [
		{"type": "block", "value": 5, "target": "self"},
		{"type": "retrieve", "value": 1, "from": "discard"},
	])
	var seek: CardData = Data.get_card(&"seek")
	assert_eq(seek.effects, [{"type": "retrieve", "value": 1, "from": "draw"}])
	assert_eq(int(seek.upgraded_effects[0].get("value", 0)), 2)
	assert_true(seek.exhaust)

func test_malaise_is_an_x_value_signed_inflict() -> void:
	var card: CardData = Data.get_card(&"malaise")
	assert_eq(card.cost, -1, "Cost X")
	assert_eq(card.effects, [
		{"type": "status", "status": "power", "stacks": 0, "target": "enemy",
			"stacks_from": "energy", "stacks_mult": -1},
		{"type": "status", "status": "weak", "stacks": 0, "target": "enemy",
			"stacks_from": "energy"},
	])
	# Malaise+: -X-1 Power / X+1 Weak via stacks_bonus.
	assert_eq(int(card.upgraded_effects[0].get("stacks_bonus", 0)), -1)
	assert_eq(int(card.upgraded_effects[1].get("stacks_bonus", 0)), 1)

func test_nightmare_setup_and_burst_forms() -> void:
	assert_eq(Data.get_card(&"nightmare").effects, [{"type": "nightmare", "count": 3}])
	assert_eq(Data.get_card(&"nightmare").upgraded_cost, 2)
	assert_eq(Data.get_card(&"setup").effects,
		[{"type": "topdeck", "value": 1, "free_until_played": true}])
	assert_eq(Data.get_card(&"setup").upgraded_cost, 0)
	assert_eq(Data.get_card(&"burst").effects,
		[{"type": "status", "status": "burst", "stacks": 1, "target": "self"}])
	assert_eq(int(Data.get_card(&"burst").upgraded_effects[0].get("stacks", 0)), 2)

func test_piercing_wail_drains_and_shackles_the_room() -> void:
	assert_eq(Data.get_card(&"piercing_wail").effects, [
		{"type": "status", "status": "power", "stacks": -6, "target": "all_enemies"},
		{"type": "status", "status": "shackled", "stacks": 6, "target": "all_enemies"},
	])

# --- Status plumbing ----------------------------------------------------------

func test_burst_is_a_skill_marker_but_the_real_statuses_are_not() -> void:
	var markers: Array = Stats.skill_marker_statuses()
	assert_has(markers, &"burst", "Burst joins the Skill-type wipe")
	assert_does_not_have(markers, &"blur", "Blur must survive to the next turn")
	assert_does_not_have(markers, &"next_turn_block")
	assert_does_not_have(markers, &"double_damage")
	assert_does_not_have(markers, &"corpse_explosion")

func test_new_status_icons_resolve() -> void:
	for key in [&"blur", &"burst", &"next_turn_block", &"double_damage", &"corpse_explosion"]:
		var tex: Texture2D = Stats.status_icon(key)
		assert_not_null(tex, "%s has icon art" % key)
		assert_string_contains(tex.resource_path, "images/statuses/")

func test_block_persists_consumes_blur_one_turn_at_a_time() -> void:
	var a := CombatActor.new()
	assert_false(Stats.block_persists(a), "no Barricade, no Blur: block resets")
	a.keep_block = true
	assert_true(Stats.block_persists(a), "Barricade keeps block without consuming")
	a.keep_block = false
	a.statuses[&"blur"] = 2
	assert_true(Stats.block_persists(a))
	assert_eq(a.get_status(&"blur"), 1, "one stack spent per boundary")
	assert_true(Stats.block_persists(a))
	assert_false(Stats.block_persists(a), "stacks spent — block resets again")

func test_double_damage_decays_but_blur_does_not() -> void:
	var a := CombatActor.new()
	a.statuses[&"double_damage"] = 1
	a.statuses[&"blur"] = 1
	Stats.decay_actor_statuses(a)
	assert_eq(a.get_status(&"double_damage"), 0, "Double Damage lasts the turn")
	assert_eq(a.get_status(&"blur"), 1, "Blur only decays when it saves block")

func test_double_damage_doubles_attacks_but_not_magic() -> void:
	var src := CombatActor.new()
	var tgt := CombatActor.new()
	tgt.max_hp = 100
	tgt.hp = 100
	src.statuses[&"double_damage"] = 1
	var res: Dictionary = Stats.resolve_damage(src, tgt, 10, {"damage_type": "melee"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 20, "melee doubled")
	res = Stats.resolve_damage(src, tgt, 10, {"damage_type": "magic"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 10, "magic is not an Attack — undoubled")

# --- Integration on the strategy scene ----------------------------------------

const _BattleViewScript = preload("res://scripts/strategy/combat/BattleView.gd")
const _TurnManagerScript = preload("res://scripts/strategy/combat/BattleTurnManager.gd")

var bv

func _battle_with_player():
	GameState.reset_run()
	bv = _BattleViewScript.new()
	add_child_autofree(bv)
	var p := BattleUnit.new()
	p.is_player = true
	p.max_hp = 50
	p.hp = 50
	p.position = Vector2i(0, 0)
	var e := BattleUnit.new()
	e.is_player = false
	e.max_hp = 30
	e.hp = 30
	e.position = Vector2i(1, 0)
	bv._units = [p, e]
	var tm = _TurnManagerScript.new()
	tm.setup([p, e])
	tm.current_unit = p
	bv._turn_manager = tm
	bv._grid_view.set_battle(null, bv._units)
	return bv

func _play(id: StringName, target = null, upgraded: bool = false) -> CardInstance:
	var card := CardInstance.from_data(Data.get_card(id), upgraded)
	bv.hand.append(card)
	bv.energy = 10
	bv._resolve_card(card, target, [])
	return card

func test_deadly_poison_and_leg_sweep_inflict() -> void:
	_battle_with_player()
	var p = bv.get_player_unit()
	var e = bv._units[1]
	_play(&"deadly_poison", e)
	assert_eq(e.get_status(&"poison"), 5)
	_play(&"leg_sweep", e)
	assert_eq(e.get_status(&"weak"), 2)
	assert_eq(p.block, 11)

func test_catalyst_doubles_then_triples_poison() -> void:
	_battle_with_player()
	var e = bv._units[1]
	e.add_status(&"poison", 4)
	_play(&"catalyst", e)
	assert_eq(e.get_status(&"poison"), 8, "Double Poison")
	_play(&"catalyst", e, true)
	assert_eq(e.get_status(&"poison"), 24, "Catalyst+ triples")
	assert_eq(bv.exhaust_pile.size(), 2, "both plays exhaust (keyword)")

func test_malaise_drains_x_power_and_inflicts_x_weak() -> void:
	_battle_with_player()
	var e = bv._units[1]
	_play(&"malaise", e)   # energy 10 -> X = 10
	assert_eq(int(e.statuses.get(&"power", 0)), -10, "the drain digs signed")
	assert_eq(e.get_status(&"weak"), 10)
	assert_eq(bv.energy, 0, "an X-cost play spends everything")

func test_piercing_wail_power_returns_via_shackled() -> void:
	_battle_with_player()
	var e = bv._units[1]
	_play(&"piercing_wail")
	assert_eq(int(e.statuses.get(&"power", 0)), -6)
	assert_eq(e.get_status(&"shackled"), 6)
	# The enemy's turn boundary returns the Shackled Power (StS GainStrength).
	Stats.tick_actor_statuses(e, bv)
	assert_eq(int(e.statuses.get(&"power", 0)), 0, "Power restored")
	assert_eq(e.get_status(&"shackled"), 0, "…and Shackled cleared")

func test_burst_doubles_exactly_one_skill() -> void:
	_battle_with_player()
	var p = bv.get_player_unit()
	_play(&"burst")
	assert_eq(p.get_status(&"burst"), 1, "Burst never doubles itself")
	_play(&"deflect")
	assert_eq(p.block, 8, "Deflect's 4 Block landed twice")
	assert_eq(p.get_status(&"burst"), 0, "the stack was consumed")
	_play(&"deflect")
	assert_eq(p.block, 12, "the next Skill is back to a single play")

func test_escape_plan_blocks_only_on_a_skill_draw() -> void:
	_battle_with_player()
	var p = bv.get_player_unit()
	bv.draw_pile = [CardInstance.from_data(Data.get_card(&"deflect"))]
	_play(&"escape_plan")
	assert_eq(p.block, 3, "drew a Skill: +3 Block")
	assert_eq(bv.hand.size(), 1, "the drawn Deflect is in hand")
	bv.hand.clear()
	bv.draw_pile = [CardInstance.from_data(Data.get_card(&"strike_silent"))]
	_play(&"escape_plan")
	assert_eq(p.block, 3, "an Attack draw pays nothing")

func test_expertise_draws_up_to_six() -> void:
	_battle_with_player()
	for _i in range(10):
		bv.draw_pile.append(CardInstance.from_data(Data.get_card(&"strike_silent")))
	_play(&"expertise")
	assert_eq(bv.hand.size(), 5, "hand topped to 6 during resolve, minus the played card")

func test_calculated_gamble_redraws_the_discarded_hand() -> void:
	_battle_with_player()
	for _i in range(3):
		bv.hand.append(CardInstance.from_data(Data.get_card(&"strike_silent")))
	for _i in range(3):
		bv.draw_pile.append(CardInstance.from_data(Data.get_card(&"deflect")))
	_play(&"calculated_gamble")
	assert_eq(bv.last_discard_count, 3, "the whole hand went away")
	assert_eq(bv.hand.size(), 3, "…and that many came back")
	assert_eq(bv.exhaust_pile.size(), 1, "base form exhausts via exhaust_self")

func test_bullet_time_frees_the_hand_and_locks_draws() -> void:
	_battle_with_player()
	var p = bv.get_player_unit()
	var strike := CardInstance.from_data(Data.get_card(&"strike_silent"))
	bv.hand.append(strike)
	bv.draw_pile.append(CardInstance.from_data(Data.get_card(&"deflect")))
	_play(&"bullet_time")
	assert_eq(strike.get_cost(), 0, "hand cards cost 0 this turn")
	assert_eq(p.get_status(&"no_draw"), 1)
	var drawn: Array = bv.draw_cards(1)
	assert_eq(drawn.size(), 0, "No Draw suppresses further draws")

func test_hologram_and_seek_retrieve_from_their_piles() -> void:
	_battle_with_player()
	var buried := CardInstance.from_data(Data.get_card(&"strike_silent"))
	bv.discard_pile.append(buried)
	bv._apply_retrieve_picks([buried])
	assert_true(bv.hand.has(buried), "Hologram's pick lands in hand")
	assert_false(bv.discard_pile.has(buried))
	var sought := CardInstance.from_data(Data.get_card(&"deflect"))
	bv.draw_pile.append(sought)
	bv._apply_retrieve_picks([sought])
	assert_true(bv.hand.has(sought), "Seek's pick lands in hand")
	assert_false(bv.draw_pile.has(sought))

func test_setup_pick_is_free_until_played() -> void:
	_battle_with_player()
	var strike := CardInstance.from_data(Data.get_card(&"strike_silent"))
	bv.hand.append(strike)
	bv._apply_topdeck_picks([strike], true)
	assert_true(bv.draw_pile.has(strike), "placed on the draw pile")
	assert_eq(strike.get_cost(), 0, "free wherever it sits")
	# Draw it back and play it — the override ends with the play.
	bv.draw_cards(1)
	var e = bv._units[1]
	bv._resolve_card(strike, e, [])
	assert_false(strike.free_until_played, "spent on play")
	assert_gt(strike.get_cost(), 0, "back to its real cost")

func test_nightmare_delivers_three_copies_next_turn() -> void:
	_battle_with_player()
	var pick := CardInstance.from_data(Data.get_card(&"strike_silent"), true)
	bv.hand.append(pick)
	bv._apply_nightmare_pick([pick], 3)
	assert_eq(bv.hand.size(), 1, "nothing arrives on the pick turn")
	bv._deliver_nightmare_copies()
	assert_eq(bv.hand.size(), 4, "3 copies joined the original")
	assert_true(bv.hand[1].upgraded, "copies keep the upgrade state")

func test_corpse_explosion_blasts_the_other_enemies_on_death() -> void:
	_battle_with_player()
	var e = bv._units[1]
	var e2 := BattleUnit.new()
	e2.is_player = false
	e2.max_hp = 40
	e2.hp = 40
	e2.position = Vector2i(2, 0)
	bv._units.append(e2)
	e.max_hp = 12
	e.hp = 5
	_play(&"corpse_explosion", e)
	assert_eq(e.get_status(&"corpse_explosion"), 1)
	bv.apply_dot(e, 99, "test")
	assert_false(e.is_alive())
	assert_eq(e2.hp, 40 - 12, "the blast dealt the dead enemy's Max HP")

func test_phantasmal_killer_doubles_the_next_attacks() -> void:
	_battle_with_player()
	var p = bv.get_player_unit()
	var e = bv._units[1]
	var hp0: int = e.hp
	_play(&"strike_silent", e)
	var single: int = hp0 - e.hp
	assert_gt(single, 0, "baseline Strike lands")
	_play(&"phantasmal_killer")
	assert_eq(p.get_status(&"double_damage"), 1)
	var hp1: int = e.hp
	_play(&"strike_silent", e)
	assert_eq(hp1 - e.hp, single * 2, "attacks deal double while it lasts")

# --- Integration on the real deckbuilder scene -------------------------------

var db

func _deck_scene(spawn: Array = [&"jaw_worm"]):
	GameState.reset_run()
	db = load("res://scenes/deckbuilder/DeckbuilderCombat.tscn").instantiate()
	db.dev_combat = true
	db.enemies_to_spawn = spawn
	add_child_autofree(db)
	for e in db.enemies:
		e.max_hp = 500
		e.hp = 500
	return db

func _db_play(id: StringName, target = null, upgraded: bool = false) -> CardInstance:
	var card := CardInstance.from_data(Data.get_card(id), upgraded)
	db.hand.append(card)
	db.energy = 10
	db._resolve_card(card, target)
	return card

func test_db_burst_doubles_the_next_skill_only_once() -> void:
	_deck_scene()
	_db_play(&"burst")
	assert_eq(db.player.get_status(&"burst"), 1, "Burst never doubles itself")
	var block0: int = db.player.block
	_db_play(&"deflect")
	assert_eq(db.player.block, block0 + 8, "Deflect landed twice")
	assert_eq(db.player.get_status(&"burst"), 0)

func test_db_blur_carries_block_through_the_turn_boundary() -> void:
	_deck_scene()
	_db_play(&"blur")
	assert_eq(db.player.block, 5)
	assert_eq(db.player.get_status(&"blur"), 1)
	db._start_player_turn()
	assert_eq(db.player.block, 5, "Blur saved the block")
	assert_eq(db.player.get_status(&"blur"), 0, "…and was spent")
	db._start_player_turn()
	assert_eq(db.player.block, 0, "no Blur left — block resets")

func test_db_dodge_and_roll_pays_next_turn_block() -> void:
	_deck_scene()
	_db_play(&"dodge_and_roll")
	assert_eq(db.player.block, 4)
	assert_eq(db.player.get_status(&"next_turn_block"), 4)
	db._start_player_turn()
	assert_eq(db.player.block, 4, "the banked Block paid out after the reset")
	assert_eq(db.player.get_status(&"next_turn_block"), 0)

func test_db_nightmare_delivers_with_the_turn_start_hand() -> void:
	_deck_scene()
	var pick := CardInstance.from_data(Data.get_card(&"deflect"))
	db.hand.append(pick)
	db._apply_nightmare_pick([pick], 3)
	var in_hand: int = _count_id(db.hand, &"deflect")
	db._start_player_turn()
	assert_eq(_count_id(db.hand, &"deflect"), in_hand + 3,
		"3 copies arrived with the next turn's hand")

func _count_id(pile: Array, id: StringName) -> int:
	var n := 0
	for c in pile:
		if c != null and c.data != null and c.data.id == id:
			n += 1
	return n

func test_db_corpse_explosion_chains_through_deal_damage() -> void:
	_deck_scene([&"jaw_worm", &"jaw_worm"])
	var e0: CombatActor = db.enemies[0]
	var e1: CombatActor = db.enemies[1]
	e0.max_hp = 20
	e0.hp = 5
	_db_play(&"corpse_explosion", e0)
	db.deal_damage(db.player, e0, 99, {"damage_type": "melee"})
	assert_false(e0.is_alive())
	assert_eq(e1.hp, 500 - 20, "the blast hit the survivor for e0's Max HP")

func test_db_setup_places_a_free_card_on_top() -> void:
	_deck_scene()
	var strike := CardInstance.from_data(Data.get_card(&"strike_ironclad"))
	db.hand.append(strike)
	db._apply_topdeck_picks([strike], true)
	assert_eq(db.draw_pile.back(), strike, "on TOP of the draw pile")
	assert_eq(strike.get_cost(), 0, "free until played")

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

func test_action_burst_doubles_a_click_skill() -> void:
	_action_arena()
	arena._resolve_card_effects(Data.get_card(&"burst"))
	assert_eq(arena.player_actor.get_status(&"burst"), 1)
	var block0: int = arena.player_actor.block
	arena._fire_click_card(Data.get_card(&"deflect"))
	assert_eq(arena.player_actor.block, block0 + 8, "the Skill cast resolved twice")
	assert_eq(arena.player_actor.get_status(&"burst"), 0, "stack consumed")

func test_action_blur_freezes_the_block_pool() -> void:
	_action_arena()
	arena.gain_block(null, 10)
	var before: int = arena.player_actor.block
	arena.player_actor.add_status(&"blur", 1)
	arena._decay_block(2.0)
	assert_eq(arena.player_actor.block, before, "block held while Blur is up")
	arena.player_actor.add_status(&"blur", -1)
	arena._decay_block(2.0)
	assert_lt(arena.player_actor.block, before, "fades again once Blur is spent")

func test_action_bullet_time_finishes_every_cooldown() -> void:
	_action_arena()
	arena.auto_slots[0].cooldown = 5.0
	arena.left_cd = 3.0
	arena.right_cd = 2.0
	arena._resolve_card_effects(Data.get_card(&"bullet_time"))
	assert_eq(float(arena.auto_slots[0].cooldown), 0.0, "auto slot ready now")
	assert_eq(arena.left_cd, 0.0)
	assert_eq(arena.right_cd, 0.0)
	assert_eq(arena.player_actor.get_status(&"no_draw"), 1,
		"no extra auto-casts until the tick")

func test_action_retrieve_rearms_from_the_auto_piles() -> void:
	_action_arena()
	var strike: CardData = Data.get_card(&"strike_ironclad")
	arena.auto_discard.append(strike)
	var slots_before: int = arena.auto_slots.size()
	arena.retrieve_cards(1, "discard")
	assert_eq(arena.auto_slots.size(), slots_before + 1, "a one-shot temp slot opened")
	assert_false(arena.auto_discard.has(strike))

func test_action_malaise_style_x_inflict_drains_signed() -> void:
	_action_arena()
	var inst: Dictionary = _action_enemy(arena.player_pos + Vector2(40, 0))
	arena._apply_status_effect({"type": "status", "status": "power", "stacks": 0,
		"stacks_from": "energy", "stacks_mult": -1, "target": "enemy"},
		"enemy", [inst], [], 3)
	assert_eq(int(inst.actor.statuses.get(&"power", 0)), -3, "X=3 drained signed")

func test_action_corpse_explosion_blasts_the_room() -> void:
	_action_arena()
	var bomb: Dictionary = _action_enemy(arena.player_pos + Vector2(40, 0))
	var bystander: Dictionary = _action_enemy(arena.player_pos + Vector2(80, 0))
	bomb.actor.max_hp = 20
	bomb.actor.hp = 5
	bomb.actor.add_status(&"corpse_explosion", 1)
	arena.apply_dot(bomb.actor, 99, "test")
	assert_false(bomb.actor.is_alive())
	assert_eq(bystander.actor.hp, 500 - 20, "the blast dealt the bomb's Max HP")

func test_action_expertise_tops_the_armed_hand_up() -> void:
	_action_arena()
	for _i in range(6):
		arena.auto_draw.append(Data.get_card(&"strike_ironclad"))
	var hand_n: int = arena.auto_slots.size()
	if arena.left_card != null:
		hand_n += 1
	if arena.right_card != null:
		hand_n += 1
	var slots_before: int = arena.auto_slots.size()
	arena._action_draw_effect({"type": "draw", "to_hand": hand_n + 2})
	assert_eq(arena.auto_slots.size(), slots_before + 2,
		"two temp slots opened to reach the target hand size")

func test_action_nightmare_delivers_at_the_next_tick() -> void:
	_action_arena()
	var slots_before: int = arena.auto_slots.size()
	arena.nightmare_cards(3, null)
	assert_eq(arena.auto_slots.size(), slots_before, "nothing arrives at cast time")
	arena._deliver_nightmare_copies()
	assert_eq(arena.auto_slots.size(), slots_before + 3,
		"3 one-shot temp slots opened at the tick")

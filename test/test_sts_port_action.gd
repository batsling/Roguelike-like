extends GutTest

# Action-mode behavior for the Burn/Blood for Blood/…/Fiend Fire port batch:
#   - Clash's if_hand gate: whiffs when a non-Attack rides ANY cooldown slot
#     (auto rotation, curse slots, click cards) at the moment it fires.
#   - Fiend Fire's exhaust:all: empties every OTHER cooldown slot out of the
#     combat, then volleys one bolt per exhausted card; fizzles on zero.
#   - Eviscerate: action discards (collapsed temp slots, base-cooldown
#     penalties, discard_hand sweeps) feed discards_this_turn, which the
#     dynamic cost/cooldown reads.
#   - if_target highlight: the gate-live check that drives the slot glow.

const ACTION_COMBAT := preload("res://scenes/action/ActionCombat.tscn")

var arena

func before_each() -> void:
	GameState.reset_run()
	GameState.apply_character(Data.get_character(&"ironclad"))
	arena = ACTION_COMBAT.instantiate()
	arena.target_game_id = &""
	arena.enemies_to_spawn = []
	add_child_autofree(arena)
	_disarm_everything()

# Strip the loadout _ready armed so each test controls exactly what rides a
# cooldown slot.
func _disarm_everything() -> void:
	arena.auto_slots.clear()
	arena._curse_slots.clear()
	arena.auto_draw.clear()
	arena.auto_discard.clear()
	arena.left_card = null
	arena.right_card = null
	arena._pending_hits.clear()

func _arm_auto(card_id: StringName, ttl: float = INF) -> void:
	arena.auto_slots.append({
		"card": Data.get_card(card_id),
		"cooldown": 5.0, "max_cooldown": 5.0, "ttl": ttl,
	})

func _add_enemy(offset: Vector2) -> Dictionary:
	var data: ActionEnemyData = Data.get_action_enemy(&"gaper")
	var inst: Dictionary = arena._make_enemy_inst(data, arena.player_pos + offset)
	inst.actor.max_hp = 100
	inst.actor.hp = 100
	arena.enemies.append(inst)
	return inst

func _tick_pending(seconds: float = 2.0) -> void:
	for _i in range(int(seconds * 60.0)):
		if arena._pending_hits.is_empty():
			return
		arena._process_pending_hits(1.0 / 60.0)

func _pending_volleys() -> int:
	var n := 0
	for p in arena._pending_hits:
		if String(p.get("mode", "")) == "attack_volley":
			n += 1
	return n

# --- Clash's gate ------------------------------------------------------------

func test_armed_non_attack_detection() -> void:
	assert_false(arena._armed_non_attack_present(), "nothing armed -> all clear")
	_arm_auto(&"choke")
	assert_false(arena._armed_non_attack_present(), "attacks don't trip the gate")
	_arm_auto(&"acrobatics", 30.0)
	assert_true(arena._armed_non_attack_present(), "a Skill in the rotation trips it")

func test_curse_slot_trips_the_clash_gate() -> void:
	arena._curse_slots.append({"card": Data.get_card(&"doubt"),
		"cooldown": 10.0, "max_cooldown": 10.0})
	assert_true(arena._armed_non_attack_present(), "curse slots only hold non-Attacks")

func test_non_attack_click_card_trips_the_clash_gate() -> void:
	arena.left_card = Data.get_card(&"acrobatics")
	assert_true(arena._armed_non_attack_present())

func test_clash_whiffs_when_a_skill_rides_a_slot() -> void:
	_arm_auto(&"acrobatics", 30.0)
	arena.player_facing = Vector2.RIGHT
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	arena._resolve_card_effects(Data.get_card(&"clash"))
	_tick_pending()
	assert_eq(foe.actor.hp, 100, "Clash whiffed — the gated dmg was dropped")

func test_clash_hits_when_only_attacks_ride_slots() -> void:
	_arm_auto(&"choke")
	arena.left_card = Data.get_card(&"clash")
	arena.player_facing = Vector2.RIGHT
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	arena._resolve_card_effects(Data.get_card(&"clash"))
	_tick_pending()
	assert_lt(foe.actor.hp, 100, "all-Attack rotation -> the swing connects")

# --- Fiend Fire --------------------------------------------------------------

func test_fiend_fire_exhausts_every_other_slot_and_volleys_per_card() -> void:
	_arm_auto(&"clash")                 # permanent base slot
	_arm_auto(&"acrobatics", 30.0)      # temp slot
	arena.left_card = Data.get_card(&"choke")
	arena.player_facing = Vector2.RIGHT
	_add_enemy(Vector2(200, 0))
	arena._resolve_card_effects(Data.get_card(&"fiend_fire"))
	assert_eq(arena.last_exhaust_count, 2, "base card + temp slot; click weapons are spared")
	assert_eq(arena.auto_slots.size(), 1, "the permanent slot survives, re-armed")
	assert_null(arena.auto_slots[0].card, "no draw pile left -> it re-armed empty")
	assert_eq(arena.left_card, Data.get_card(&"choke"),
		"the click weapon stays armed — the player's manual kit is never exhausted")
	assert_eq(_pending_volleys(), 1, "2 exhausted = 2 bolts: 1 fired + 1 queued")

func test_fiend_fire_exhausted_cards_leave_the_rotation() -> void:
	_arm_auto(&"acrobatics", 30.0)
	arena._resolve_card_effects(Data.get_card(&"fiend_fire"))
	assert_eq(arena.auto_slots.size(), 0, "the temp slot collapsed")
	assert_eq(arena.auto_discard.size(), 0, "exhausted, not discarded — gone for the combat")
	assert_eq(arena.auto_draw.size(), 0)

func test_fiend_fire_clears_curse_slots_and_counts_them() -> void:
	arena._curse_slots.append({"card": Data.get_card(&"doubt"),
		"cooldown": 10.0, "max_cooldown": 10.0})
	arena._resolve_card_effects(Data.get_card(&"fiend_fire"))
	assert_eq(arena._curse_slots.size(), 0, "Fiend Fire eats curses, like the deckbuilder")
	assert_eq(arena.last_exhaust_count, 1)

func test_fiend_fire_fizzles_with_nothing_to_exhaust() -> void:
	arena.player_facing = Vector2.RIGHT
	_add_enemy(Vector2(200, 0))
	arena._resolve_card_effects(Data.get_card(&"fiend_fire"))
	assert_eq(arena.last_exhaust_count, 0)
	assert_eq(arena._pending_hits.size(), 0, "no volleys queued — the cast fizzled")

# --- Eviscerate --------------------------------------------------------------

func test_action_discards_feed_the_eviscerate_counter() -> void:
	GameState.incremental_discards_turn = 0
	_arm_auto(&"clash")                 # base slot soaks the penalty fallback
	_arm_auto(&"acrobatics", 30.0)      # one temp slot to collapse
	arena.discard_cards(2)
	assert_eq(GameState.incremental_discards_turn, 2,
		"one collapsed temp slot + one base-cooldown penalty = two discards")
	assert_eq(arena._action_card_cost(Data.get_card(&"eviscerate")), 1,
		"cost 3 - 2 discards, so the next arm's cooldown shortens")
	GameState.incremental_on_turn_tick()
	assert_eq(arena._action_card_cost(Data.get_card(&"eviscerate")), 3,
		"the turn tick resets the per-turn discount")

func test_discard_hand_counts_each_collapsed_slot() -> void:
	GameState.incremental_discards_turn = 0
	_arm_auto(&"acrobatics", 30.0)
	_arm_auto(&"backflip", 30.0)
	arena.discard_hand()
	assert_eq(GameState.incremental_discards_turn, 2)

# --- if_target highlight -----------------------------------------------------

func test_if_target_gate_live_tracks_enemy_status() -> void:
	var effects: Array = Data.get_card(&"dropkick").effects
	var foe := CombatActor.new()
	foe.max_hp = 10
	foe.hp = 10
	assert_false(Stats.if_target_gate_live(effects, [foe]),
		"no Vulnerable anywhere -> gate dark")
	foe.add_status(&"vulnerable", 1)
	assert_true(Stats.if_target_gate_live(effects, [foe]),
		"a living Vulnerable enemy -> gate lit")
	foe.hp = 0
	assert_false(Stats.if_target_gate_live(effects, [foe]),
		"dead enemies don't light the gate")

func test_gate_never_lights_for_cards_without_a_gate() -> void:
	var foe := CombatActor.new()
	foe.max_hp = 10
	foe.hp = 10
	foe.add_status(&"vulnerable", 1)
	assert_false(Stats.if_target_gate_live(Data.get_card(&"clash").effects, [foe]))

func test_slot_gate_helper_reads_the_armed_card() -> void:
	var foe: Dictionary = _add_enemy(Vector2(100, 0))
	foe.actor.add_status(&"vulnerable", 1)
	assert_true(arena._card_gate_live(Data.get_card(&"dropkick"),
		arena._living_enemy_actors()))
	assert_false(arena._card_gate_live(Data.get_card(&"clash"),
		arena._living_enemy_actors()))
	assert_false(arena._card_gate_live(null, arena._living_enemy_actors()))

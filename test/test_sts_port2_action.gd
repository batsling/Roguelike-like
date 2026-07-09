extends GutTest

# Action-mode behavior for the Flechettes/Go for the Eyes/Grand Finale/
# Headbutt/Heel Hook/Hemokinesis port batch:
#   - Flechettes: one volley per Skill riding a cooldown slot (auto rotation
#     + click cards); fizzles with none armed.
#   - Grand Finale: whiffs while any card is still queued in the auto draw
#     pile; bursts when it's empty.
#   - Go for the Eyes: the Weak inflict gates on _enemy_intends_attack
#     (winding up, or an attack off cooldown).
#   - Headbutt: topdeck from=discard pulls a random auto-discard back on top
#     of the auto draw pile without collapsing temp slots.
#   - Hemokinesis: the lose_hp cost lands on the player via apply_dot.

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

# --- Flechettes (volleys per armed Skill) --------------------------------------

func test_armed_skill_count_reads_every_slot_kind() -> void:
	assert_eq(arena._armed_skill_count(), 0, "nothing armed -> zero Skills")
	_arm_auto(&"choke")
	assert_eq(arena._armed_skill_count(), 0, "Attacks don't count")
	_arm_auto(&"acrobatics", 30.0)
	assert_eq(arena._armed_skill_count(), 1, "a Skill in the rotation counts")
	arena.left_card = Data.get_card(&"backflip")
	assert_eq(arena._armed_skill_count(), 2, "a Skill click card counts too")

func test_flechettes_volleys_once_per_armed_skill() -> void:
	_arm_auto(&"acrobatics", 30.0)
	arena.left_card = Data.get_card(&"backflip")
	arena.player_facing = Vector2.RIGHT
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	arena._resolve_card_effects(Data.get_card(&"flechettes"))
	assert_eq(_pending_volleys(), 1, "2 armed Skills = 2 volleys: 1 fired + 1 queued")
	_tick_pending()
	assert_lt(foe.actor.hp, 100, "the daggers connect")

func test_flechettes_fizzles_with_no_armed_skills() -> void:
	_arm_auto(&"choke")
	arena.player_facing = Vector2.RIGHT
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	arena._resolve_card_effects(Data.get_card(&"flechettes"))
	_tick_pending()
	assert_eq(foe.actor.hp, 100, "no Skills on slots -> the cast fizzles")
	assert_eq(arena._pending_hits.size(), 0)

# --- Grand Finale (auto draw pile gate) -----------------------------------------

func test_grand_finale_whiffs_while_the_auto_draw_pile_holds_cards() -> void:
	arena.auto_draw.append(Data.get_card(&"choke"))
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	arena._resolve_card_effects(Data.get_card(&"grand_finale"))
	_tick_pending()
	assert_eq(foe.actor.hp, 100, "cards left to draw -> the burst deals nothing")

func test_grand_finale_bursts_on_an_empty_auto_draw_pile() -> void:
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	arena._resolve_card_effects(Data.get_card(&"grand_finale"))
	_tick_pending()
	assert_lt(foe.actor.hp, 100, "empty draw pile -> the nova lands")

# --- Go for the Eyes (enemy intent gate) ----------------------------------------

func test_enemy_intends_attack_predicate() -> void:
	var inst := {"winding": true, "atk_cd": [5.0]}
	assert_true(arena._enemy_intends_attack(inst), "winding up -> intends")
	inst = {"winding": false, "atk_cd": [5.0, 3.0]}
	assert_false(arena._enemy_intends_attack(inst), "everything cooling -> no intent")
	inst = {"winding": false, "atk_cd": [5.0, 0.0]}
	assert_true(arena._enemy_intends_attack(inst), "an attack off cooldown -> intends")
	inst = {}
	assert_true(arena._enemy_intends_attack(inst),
		"un-ticked enemies count as ready (cooldowns seed at 0)")

func test_go_for_the_eyes_weakens_an_attack_ready_enemy() -> void:
	arena.player_facing = Vector2.RIGHT
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	foe["winding"] = true
	arena._resolve_card_effects(Data.get_card(&"go_for_the_eyes"))
	_tick_pending()
	assert_eq(foe.actor.get_status(&"weak"), 1, "winding enemy -> Weak lands")

func test_go_for_the_eyes_spares_a_cooling_enemy() -> void:
	arena.player_facing = Vector2.RIGHT
	var foe: Dictionary = _add_enemy(Vector2(60, 0))
	foe["winding"] = false
	foe["atk_cd"] = [5.0]
	arena._resolve_card_effects(Data.get_card(&"go_for_the_eyes"))
	_tick_pending()
	assert_eq(foe.actor.get_status(&"weak"), 0, "no attack ready -> no Weak")
	assert_lt(foe.actor.hp, 100, "the swing itself still connects")

# --- Headbutt (topdeck from=discard) --------------------------------------------

func test_headbutt_topdeck_pulls_from_the_discard_not_the_slots() -> void:
	var choke: CardData = Data.get_card(&"choke")
	arena.auto_discard.append(choke)
	_arm_auto(&"acrobatics", 30.0)
	arena.topdeck_cards(1, null, false, "discard")
	assert_eq(arena.auto_slots.size(), 1, "temp slots are NOT collapsed")
	assert_eq(arena.auto_discard.size(), 0, "the discard was pulled")
	assert_eq(arena.auto_draw.back(), choke, "…onto the TOP of the auto draw pile")

func test_warcry_topdeck_still_collapses_a_temp_slot_first() -> void:
	arena.auto_discard.append(Data.get_card(&"choke"))
	_arm_auto(&"acrobatics", 30.0)
	arena.topdeck_cards(1)
	assert_eq(arena.auto_slots.size(), 0, "the hand pool collapses the temp slot")
	assert_eq(arena.auto_discard.size(), 1, "the discard is only the fallback")

# --- Hemokinesis (lose_hp self-cost) ---------------------------------------------

func test_lose_hp_self_syncs_player_and_counts_a_loss() -> void:
	var hp_before: int = GameState.hp
	var losses_before: int = GameState.incremental_hp_losses
	GameState.set_combat_context(arena, null)
	arena._lose_hp_self(2, Data.get_card(&"hemokinesis"))
	assert_eq(GameState.hp, hp_before - 2, "Lose 2 Health")
	assert_eq(arena.player_actor.hp, GameState.hp, "the actor mirrors the HUD pool")
	assert_eq(GameState.incremental_hp_losses, losses_before + 1,
		"one hp_losses instance for Blood for Blood's discount")
	GameState.clear_combat_context()
	GameState.set_hp(hp_before)
	GameState.incremental_hp_losses = losses_before

func test_hemokinesis_cast_pays_the_cost_up_front() -> void:
	var hp_before: int = GameState.hp
	GameState.set_combat_context(arena, null)
	arena.player_facing = Vector2.RIGHT
	_add_enemy(Vector2(200, 0))
	arena._resolve_card_effects(Data.get_card(&"hemokinesis"))
	assert_eq(GameState.hp, hp_before - 2,
		"the HP cost lands at cast time, before the bolt arrives")
	GameState.clear_combat_context()
	GameState.set_hp(hp_before)

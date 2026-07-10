extends GutTest

# Action-mode behavior for the Slice/Reckless Charge/Wild Strike/Sneaky
# Strike/Unload/Sever Soul/Searing Blow port batch:
#   - Searing Blow: the rotation resolves a per-(id, count) cached CardData
#     with the banked +3s folded in, so an upgraded copy hits harder and
#     wears its +N name.
#   - Unload / Sever Soul: the discard/exhaust sweeps spare Attack cards.
#   - Sneaky Strike: the if_counter payoff grants a Haste window only when
#     the discards_this_turn counter is live.

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

func _arm_auto(card_id: StringName, ttl: float = 30.0) -> void:
	arena.auto_slots.append({
		"card": Data.get_card(card_id),
		"cooldown": 5.0, "max_cooldown": 5.0, "ttl": ttl,
	})

# --- Searing Blow (sequential upgrades reach the rotation) -----------------------

func test_searing_blow_action_card_folds_the_banked_upgrades() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"searing_blow"))
	inst.apply_upgrade()
	inst.apply_upgrade()
	var resolved: CardData = GameState._effective_action_card(inst)
	assert_eq(int(resolved.effects[0].get("value", 0)), 18, "12 + 3x2")
	assert_eq(resolved.display_name, "Searing Blow+2")
	assert_eq(resolved.cost, 2, "the cost (and so the cooldown) never moves")

func test_searing_blow_action_cache_shares_per_count_resources() -> void:
	var a := CardInstance.from_data(Data.get_card(&"searing_blow"))
	var b := CardInstance.from_data(Data.get_card(&"searing_blow"))
	a.apply_upgrade()
	b.apply_upgrade()
	assert_eq(GameState._effective_action_card(a), GameState._effective_action_card(b),
		"two +1 copies resolve to ONE cached resource")
	b.apply_upgrade()
	assert_ne(GameState._effective_action_card(a), GameState._effective_action_card(b),
		"a different count is a different resource")

func test_fresh_searing_blow_resolves_the_base_resource() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"searing_blow"))
	assert_eq(GameState._effective_action_card(inst), inst.data,
		"no banked upgrades -> the base CardData, untouched")

# --- Unload / Sever Soul (filtered sweeps in the rotation) ------------------------

func test_unload_discard_sweep_spares_armed_attacks() -> void:
	_arm_auto(&"strike_ironclad")
	_arm_auto(&"acrobatics")
	_arm_auto(&"backflip")
	var removed: int = arena.discard_hand(null, "non_attack")
	assert_eq(removed, 2, "the two Skill slots collapse")
	assert_eq(arena.auto_slots.size(), 1, "the Attack slot survives")
	assert_eq(String(arena.auto_slots[0].card.id), "strike_ironclad")
	assert_eq(arena.auto_discard.size(), 2, "collapsed cards head to the discard")

func test_plain_discard_sweep_still_takes_everything() -> void:
	_arm_auto(&"strike_ironclad")
	_arm_auto(&"acrobatics")
	assert_eq(arena.discard_hand(), 2, "no filter -> every temp slot collapses")

func test_sever_soul_exhaust_sweep_spares_armed_attacks() -> void:
	_arm_auto(&"strike_ironclad")
	_arm_auto(&"acrobatics")
	var removed: int = arena.exhaust_hand(null, "non_attack")
	assert_eq(removed, 1, "only the Skill exhausts")
	assert_eq(arena.auto_slots.size(), 1)
	assert_eq(String(arena.auto_slots[0].card.id), "strike_ironclad")
	assert_eq(arena.last_exhaust_count, 1)

# --- Sneaky Strike (if_counter -> Haste) -------------------------------------------

func test_sneaky_strike_hastes_after_a_discard_this_turn() -> void:
	var card: CardData = Data.get_card(&"sneaky_strike")
	var before: int = GameState.incremental_discards_turn
	GameState.incremental_discards_turn = 1
	arena._haste_remaining = 0.0
	arena._apply_if_counter_effect(card.effects[1])
	assert_gt(arena._haste_remaining, 0.0,
		"a live discard counter -> the +2 Energy Haste window opens")
	GameState.incremental_discards_turn = before

func test_sneaky_strike_stays_flat_without_a_discard() -> void:
	var card: CardData = Data.get_card(&"sneaky_strike")
	var before: int = GameState.incremental_discards_turn
	GameState.incremental_discards_turn = 0
	arena._haste_remaining = 0.0
	arena._apply_if_counter_effect(card.effects[1])
	assert_eq(arena._haste_remaining, 0.0, "no discards -> no Haste")
	GameState.incremental_discards_turn = before

# --- Unload's 4-projectile fan -----------------------------------------------------

func test_unload_resolves_a_four_projectile_fan() -> void:
	var spec: Dictionary = Data.action_attacks.resolve(Data.get_card(&"unload"))
	assert_eq(String(spec.get("family", "")), "projectile")
	assert_eq(int(spec.get("spread", 0)), 4)

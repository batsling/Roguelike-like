extends GutTest

# Action-mode behavior for the Immolate/Masterful Stab/Perfected Strike/
# Poisoned Stab/Pummel/Quick Slash/Rampage port batch:
#   - Perfected Strike: the +N-per-"Strike" bonus counts the combat rotation
#     (auto slots + click cards + auto draw/discard piles), the firing card
#     included once.
#   - Masterful Stab: cost_increase_from raises the effective cost — and with
#     it the derived cooldown — one step per hp_losses instance.
#   - Immolate resolves as an auto_aoe archetype (target=nearest, large disc).

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

# --- Perfected Strike (_cards_named_count) --------------------------------------

func test_cards_named_count_reads_the_whole_rotation() -> void:
	var ps: CardData = Data.get_card(&"perfected_strike")
	assert_eq(arena._cards_named_count("strike", ps), 1,
		"nothing armed -> only the firing card counts itself")
	_arm_auto(&"strike_ironclad")
	arena.left_card = Data.get_card(&"twin_strike")
	arena.auto_draw.append(Data.get_card(&"pommel_strike"))
	arena.auto_discard.append(Data.get_card(&"bash"))
	assert_eq(arena._cards_named_count("strike", ps), 4,
		"slot + click + draw-pile Strikes count; Bash doesn't")

func test_cards_named_count_does_not_double_count_an_armed_caster() -> void:
	var ps: CardData = Data.get_card(&"perfected_strike")
	_arm_auto(&"perfected_strike")
	assert_eq(arena._cards_named_count("strike", ps), 1,
		"the firing card riding a slot counts exactly once")

func test_perfected_strike_damage_scales_with_armed_strikes() -> void:
	var ps: CardData = Data.get_card(&"perfected_strike")
	_arm_auto(&"strike_ironclad")
	arena.left_card = Data.get_card(&"twin_strike")
	var value: int = arena._resolve_dmg_value(ps.effects[0], ps)
	assert_eq(value, 12, "6 + 2x(2 armed Strikes + itself)")

func test_plain_dmg_values_are_untouched() -> void:
	var bash: CardData = Data.get_card(&"bash")
	_arm_auto(&"strike_ironclad")
	assert_eq(arena._resolve_dmg_value(bash.effects[0], bash),
		int(bash.effects[0].get("value", 0)),
		"cards without the bonus field ignore the strike count")

# --- Masterful Stab (cost surcharge -> cooldown) ---------------------------------

func test_masterful_stab_cost_tracks_hp_losses() -> void:
	var stab: CardData = Data.get_card(&"masterful_stab")
	var losses_before: int = GameState.incremental_hp_losses
	GameState.incremental_hp_losses = 0
	assert_eq(arena._action_card_cost(stab), 0, "unhurt -> base cost 0")
	GameState.incremental_hp_losses = 3
	assert_eq(arena._action_card_cost(stab), 3, "3 HP losses -> cost 3")
	GameState.incremental_hp_losses = losses_before

func test_masterful_stab_cooldown_lengthens_with_the_surcharge() -> void:
	var stab: CardData = Data.get_card(&"masterful_stab")
	var losses_before: int = GameState.incremental_hp_losses
	GameState.incremental_hp_losses = 0
	var fresh: float = arena._cooldown_for(stab)
	GameState.incremental_hp_losses = 2
	assert_almost_eq(arena._cooldown_for(stab), fresh + 4.0, 0.001,
		"cost IS cooldown: +2 cost -> +4s on the cycle")
	GameState.incremental_hp_losses = losses_before

# --- Immolate (auto_aoe delivery spec) ---------------------------------------------

func test_immolate_resolves_the_auto_aoe_archetype() -> void:
	var card: CardData = Data.get_card(&"immolate")
	var spec: Dictionary = Data.action_attacks.resolve(card)
	assert_eq(String(spec.get("family", "")), "auto_aoe")
	assert_eq(String(spec.get("target_mode", "")), "nearest")
	assert_almost_eq(float(spec.get("radius_px", 0.0)),
		float(Data.action_attacks.radius_px["large"]), 0.001,
		"the Large size word drives the disc radius")

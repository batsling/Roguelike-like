extends GutTest

# Covers the Next Turn Energy / Next Turn Draw / No Draw batch (Battle Trance /
# Doppelganger / Flying Knee / Predator / Prepared / Riddle with Holes) and the
# engine pieces added with it:
#   - X-value gains (status stacks_from: "energy" + stacks_bonus) read ctx.x_value
#   - Stats.consume_status drains a banked status in one step
#   - no_draw sits in the shared decay set so it lifts at the turn boundary
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Captures every status application EffectSystem routes to the scene.
class _StatusScene:
	extends RefCounted
	var enemies: Array = []
	var applied: Array = []         # [{target, status, stacks}]
	func apply_status(target, status: StringName, stacks: int, _source = null) -> void:
		applied.append({"target": target, "status": status, "stacks": stacks})

# --- X-value gains (Doppelganger) -----------------------------------------

func test_x_value_gain_reads_energy_spent_from_ctx() -> void:
	var scene := _StatusScene.new()
	var player := CombatActor.new()
	player.is_player = true
	var eff := {"type": "status", "status": "next_turn_draw", "stacks": 0,
		"stacks_from": "energy", "target": "self"}
	EffectSystem.apply(eff, {"source": player, "scene": scene, "x_value": 3})
	assert_eq(scene.applied.size(), 1, "one application")
	assert_eq(scene.applied[0].status, &"next_turn_draw")
	assert_eq(int(scene.applied[0].stacks), 3, "X = the energy spent on the play")
	assert_eq(scene.applied[0].target, player, "self gain lands on the source")

func test_x_plus_one_upgrade_adds_flat_bonus() -> void:
	var scene := _StatusScene.new()
	var player := CombatActor.new()
	player.is_player = true
	var eff := {"type": "status", "status": "next_turn_energy", "stacks": 0,
		"stacks_from": "energy", "stacks_bonus": 1, "target": "self"}
	EffectSystem.apply(eff, {"source": player, "scene": scene, "x_value": 2})
	assert_eq(int(scene.applied[0].stacks), 3, "X+1 with X=2 -> 3 stacks")

func test_x_value_gain_at_zero_energy_applies_nothing_without_bonus() -> void:
	var scene := _StatusScene.new()
	var player := CombatActor.new()
	player.is_player = true
	var eff := {"type": "status", "status": "next_turn_draw", "stacks": 0,
		"stacks_from": "energy", "target": "self"}
	EffectSystem.apply(eff, {"source": player, "scene": scene, "x_value": 0})
	assert_eq(scene.applied.size(), 0, "X = 0 -> no stacks, no application")

func test_x_plus_one_at_zero_energy_still_grants_the_bonus() -> void:
	var scene := _StatusScene.new()
	var player := CombatActor.new()
	player.is_player = true
	var eff := {"type": "status", "status": "next_turn_draw", "stacks": 0,
		"stacks_from": "energy", "stacks_bonus": 1, "target": "self"}
	EffectSystem.apply(eff, {"source": player, "scene": scene, "x_value": 0})
	assert_eq(int(scene.applied[0].stacks), 1, "Doppelganger+ on an empty pool still banks 1")

# --- Stats.consume_status (the turn-start payout primitive) ---------------

func test_consume_status_returns_stacks_and_clears() -> void:
	var actor := CombatActor.new()
	actor.is_player = true
	actor.add_status(&"next_turn_energy", 2)
	assert_eq(Stats.consume_status(actor, &"next_turn_energy"), 2)
	assert_eq(actor.get_status(&"next_turn_energy"), 0, "all stacks lost when triggered")
	assert_eq(Stats.consume_status(actor, &"next_turn_energy"), 0, "second consume is a no-op")

func test_consume_status_handles_null_and_absent() -> void:
	assert_eq(Stats.consume_status(null, &"next_turn_draw"), 0)
	var actor := CombatActor.new()
	assert_eq(Stats.consume_status(actor, &"next_turn_draw"), 0)

# --- No Draw decay + icons -------------------------------------------------

func test_no_draw_is_in_the_shared_decay_set() -> void:
	assert_true(Stats.DECAY_STATUSES.has(&"no_draw"),
		"no_draw must lift at the turn boundary in every mode")
	assert_false(Stats.DECAY_STATUSES.has(&"next_turn_energy"),
		"next_turn_energy is consumed at payout, never decayed")
	assert_false(Stats.DECAY_STATUSES.has(&"next_turn_draw"),
		"next_turn_draw is consumed at payout, never decayed")

func test_new_statuses_have_icons_mapped() -> void:
	for sid in [&"next_turn_energy", &"next_turn_draw", &"no_draw"]:
		assert_true(Stats.STATUS_ICONS.has(sid), "%s needs a badge icon" % sid)

# --- .tres round-trips ------------------------------------------------------

func test_doppelganger_tres_banks_x_of_both_statuses() -> void:
	var card: CardData = Data.get_card(&"doppelganger")
	assert_not_null(card, "doppelganger.tres should load")
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_eq(card.rarity, CardData.Rarity.RARE)
	assert_eq(card.cost, -1, "X-cost")
	assert_true(card.exhaust)
	assert_eq(card.effects.size(), 2)
	var statuses: Array = []
	for eff in card.effects:
		assert_eq(String(eff.get("type", "")), "status")
		assert_eq(String(eff.get("stacks_from", "")), "energy")
		assert_eq(String(eff.get("target", "")), "self")
		statuses.append(String(eff.get("status", "")))
	assert_true("next_turn_draw" in statuses and "next_turn_energy" in statuses)
	for eff in card.upgraded_effects:
		assert_eq(int(eff.get("stacks_bonus", 0)), 1, "upgrade is X+1")

func test_battle_trance_draws_then_locks_draws() -> void:
	var card: CardData = Data.get_card(&"battle_trance")
	assert_not_null(card, "battle_trance.tres should load")
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_eq(card.cost, 0)
	assert_eq(String(card.effects[0].get("type", "")), "draw")
	assert_eq(int(card.effects[0].get("value", 0)), 3)
	assert_eq(String(card.effects[1].get("status", "")), "no_draw",
		"the draw resolves BEFORE No Draw locks the door")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 4)

func test_flying_knee_banks_next_turn_energy() -> void:
	var card: CardData = Data.get_card(&"flying_knee")
	assert_not_null(card, "flying_knee.tres should load")
	assert_eq(card.rarity, CardData.Rarity.COMMON)
	assert_eq(int(card.effects[0].get("value", 0)), 8)
	assert_eq(String(card.effects[1].get("status", "")), "next_turn_energy")
	assert_eq(card.attack_shape, &"poke")
	assert_eq(String(card.attack_params.get("size", "")), "medium")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 11)

func test_predator_is_common_and_a_medium_poke() -> void:
	var card: CardData = Data.get_card(&"predator")
	assert_not_null(card, "predator.tres should load")
	assert_eq(card.rarity, CardData.Rarity.COMMON, "downtuned from the legacy Uncommon")
	assert_eq(card.cost, 2)
	assert_eq(int(card.effects[0].get("value", 0)), 15)
	assert_eq(String(card.effects[1].get("status", "")), "next_turn_draw")
	assert_eq(int(card.effects[1].get("stacks", 0)), 2)
	assert_eq(card.attack_shape, &"poke")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

func test_prepared_draws_and_discards_with_the_picker() -> void:
	var card: CardData = Data.get_card(&"prepared")
	assert_not_null(card, "prepared.tres should load")
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_eq(card.cost, 0)
	assert_eq(card.attack_shape, &"", "pure Skill — no attack delivery")
	assert_eq(String(card.effects[1].get("type", "")), "discard")
	assert_false(bool(card.effects[1].get("random", false)),
		"the player picks the discard (Acrobatics rule, not All-Out Attack's)")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 2)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 2)

func test_riddle_with_holes_is_a_five_hit_small_poke() -> void:
	var card: CardData = Data.get_card(&"riddle_with_holes")
	assert_not_null(card, "riddle_with_holes.tres should load")
	assert_eq(card.rarity, CardData.Rarity.UNCOMMON)
	assert_eq(int(card.effects[0].get("value", 0)), 3)
	assert_eq(int(card.effects[0].get("hits", 0)), 5)
	assert_eq(card.attack_shape, &"poke")
	assert_eq(String(card.attack_params.get("size", "")), "small")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 4)

extends GutTest

# Covers the Warcry / Uppercut / Whirlwind / Skewer / Storm of Steel /
# Sword Boomerang / Reaper batch and the engine pieces added with it:
#   - X-cost repeat        (dmg hits_from: "energy" reads ctx.x_value)
#   - topdeck effect       (Warcry — put a hand card on top of the draw pile)
#   - discard:all + conjure count_from: "discarded" (Storm of Steel)
#   - Lifesteal / Indiscriminate addons stamping their effect flags
#   - swing size words (small / medium / large) in the Action attack library
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Records damage calls so hit counts can be asserted without a live combat.
class _DmgScene:
	extends RefCounted
	var enemies: Array = []
	var amounts: Array = []
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		amounts.append(amount)

# Records the pile-manipulation calls EffectSystem routes to the scene.
class _PileScene:
	extends RefCounted
	var enemies: Array = []
	var topdecks: Array = []        # [{n, random}]
	var discard_hand_calls: int = 0
	var conjures: Array = []        # [{card_id, destination, count, upgraded}]
	var last_discard_count: int = 0
	func topdeck_cards(n: int, _source_card = null, random: bool = false, from_pile: String = "hand", _free_until_played: bool = false) -> void:
		topdecks.append({"n": n, "random": random, "from": from_pile})
	func discard_hand(_source_card = null, _only: String = "") -> int:
		discard_hand_calls += 1
		return last_discard_count
	func conjure_card(card_id: StringName, destination: String, count: int, _source, upgraded: bool = false) -> void:
		conjures.append({"card_id": card_id, "destination": destination,
			"count": count, "upgraded": upgraded})

# --- X-cost (Whirlwind / Skewer) ------------------------------------------

func test_x_cost_dmg_repeats_once_per_energy_spent() -> void:
	var scene := _DmgScene.new()
	var eff := {"type": "dmg", "value": 5, "damage_type": "melee", "hits_from": "energy"}
	EffectSystem.apply(eff, {"source": CombatActor.new(), "target": CombatActor.new(),
		"scene": scene, "x_value": 3})
	assert_eq(scene.amounts.size(), 3, "X = 3 -> three hits")

func test_x_cost_dmg_with_zero_energy_deals_no_hits() -> void:
	var scene := _DmgScene.new()
	var eff := {"type": "dmg", "value": 7, "damage_type": "melee", "hits_from": "energy"}
	EffectSystem.apply(eff, {"source": CombatActor.new(), "target": CombatActor.new(),
		"scene": scene, "x_value": 0})
	assert_eq(scene.amounts.size(), 0, "X = 0 -> the card whiffs entirely")

func test_whirlwind_tres_is_x_cost_cleave() -> void:
	var card: CardData = Data.get_card(&"whirlwind")
	assert_not_null(card, "whirlwind.tres should load")
	assert_eq(card.cost, -1, "X-cost sentinel")
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("hits_from", "")), "energy")
	assert_eq(String(eff.get("target", "")), "all_enemies", "Cleave")
	assert_eq(int(eff.get("value", 0)), 5)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 8)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "large", "full 360 swing")

func test_skewer_tres_is_x_cost_large_poke() -> void:
	var card: CardData = Data.get_card(&"skewer")
	assert_not_null(card, "skewer.tres should load")
	assert_eq(card.cost, -1)
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("hits_from", "")), "energy")
	assert_eq(int(eff.get("value", 0)), 7)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 10)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "large")

func test_x_cost_card_instance_ignores_cost_deltas() -> void:
	# The existing CardInstance rule: X-cost cards keep cost -1 under combat
	# discounts (they spend everything regardless).
	var inst := CardInstance.from_data(Data.get_card(&"whirlwind"))
	inst.combat_cost_delta = -1
	assert_eq(inst.get_cost(), -1)

# --- Warcry (topdeck) -------------------------------------------------------

func test_topdeck_effect_routes_to_scene() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply({"type": "topdeck", "value": 1}, {"scene": scene})
	assert_eq(scene.topdecks.size(), 1)
	assert_eq(int(scene.topdecks[0]["n"]), 1)
	assert_false(bool(scene.topdecks[0]["random"]), "player-choice by default")

func test_topdeck_random_flag_passes_through() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply({"type": "topdeck", "value": 2, "random": true}, {"scene": scene})
	assert_true(bool(scene.topdecks[0]["random"]))

func test_warcry_tres_draws_then_topdecks_and_exhausts() -> void:
	var card: CardData = Data.get_card(&"warcry")
	assert_not_null(card, "warcry.tres should load")
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_eq(card.cost, 0)
	assert_true(card.exhaust, "Warcry exhausts")
	assert_eq(String(card.effects[0].get("type", "")), "draw")
	assert_eq(int(card.effects[0].get("value", 0)), 1)
	assert_eq(String(card.effects[1].get("type", "")), "topdeck")
	# Upgrade bumps the draw, keeps the topdeck.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 2)
	assert_eq(String(card.upgraded_effects[1].get("type", "")), "topdeck")

# --- Storm of Steel (discard:all + conjure count_from) ----------------------

func test_discard_all_routes_to_discard_hand() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply({"type": "discard", "all": true}, {"scene": scene})
	assert_eq(scene.discard_hand_calls, 1)

func test_conjure_count_from_discarded_uses_scene_tally() -> void:
	var scene := _PileScene.new()
	scene.last_discard_count = 4
	EffectSystem.apply({"type": "conjure", "card_id": "shiv", "destination": "hand",
		"count": 1, "count_from": "discarded"}, {"scene": scene})
	assert_eq(scene.conjures.size(), 1)
	assert_eq(int(scene.conjures[0]["count"]), 4, "one Shiv per discarded card")

func test_conjure_count_from_discarded_skips_on_zero() -> void:
	var scene := _PileScene.new()
	scene.last_discard_count = 0
	EffectSystem.apply({"type": "conjure", "card_id": "shiv", "destination": "hand",
		"count": 1, "count_from": "discarded"}, {"scene": scene})
	assert_eq(scene.conjures.size(), 0, "nothing discarded -> nothing conjured")

func test_storm_of_steel_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"storm_of_steel")
	assert_not_null(card, "storm_of_steel.tres should load")
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_true(bool(card.effects[0].get("all", false)), "discard the whole hand")
	var cj: Dictionary = card.effects[1]
	assert_eq(String(cj.get("card_id", "")), "shiv")
	assert_eq(String(cj.get("count_from", "")), "discarded")
	# Upgraded form conjures upgraded Shivs via the + suffix.
	assert_eq(String(card.upgraded_effects[1].get("card_id", "")), "shiv+")

# --- Sword Boomerang ---------------------------------------------------------

func test_sword_boomerang_tres_hits_three_random_enemies() -> void:
	var card: CardData = Data.get_card(&"sword_boomerang")
	assert_not_null(card, "sword_boomerang.tres should load")
	assert_eq(String(card.attack_shape), "boomerang")
	assert_true(card.addons.has("indiscriminate"), "random target per hit")
	var eff: Dictionary = card.effects[0]
	assert_eq(int(eff.get("hits", 0)), 3)
	assert_eq(String(eff.get("damage_type", "")), "ranged")
	assert_eq(int(card.upgraded_effects[0].get("hits", 0)), 4, "upgrade adds a hit")

func test_sword_boomerang_never_asks_for_a_target() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"sword_boomerang"))
	assert_false(inst.wants_target(), "Indiscriminate skips the target picker")

func test_boomerang_archetype_resolves_in_the_action_library() -> void:
	var action_spec: Dictionary = Data.action_attacks.resolve(Data.get_card(&"sword_boomerang"))
	assert_eq(String(action_spec.get("family", "")), "boomerang")
	assert_eq(String(action_spec.get("target_mode", "")), "random")

# --- Reaper ------------------------------------------------------------------

func test_reaper_tres_is_a_large_lifesteal_swing() -> void:
	var card: CardData = Data.get_card(&"reaper")
	assert_not_null(card, "reaper.tres should load")
	assert_true(card.exhaust)
	assert_true(card.addons.has("lifesteal"))
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("target", "")), "all_enemies", "Cleave")
	assert_eq(int(eff.get("value", 0)), 4)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 5)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "large")

func test_lifesteal_addon_stamps_the_effect_flag() -> void:
	# The addon pipeline turns the Lifesteal keyword into the lifesteal effect
	# flag every mode's deal_damage already honors.
	var card: CardData = Data.get_card(&"reaper")
	var out: Dictionary = Stats.apply_addons_to_effect(card.effects[0], card)
	assert_true(bool(out.get("lifesteal", false)), "dmg carries lifesteal: true")

# --- Uppercut ----------------------------------------------------------------

func test_uppercut_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"uppercut")
	assert_not_null(card, "uppercut.tres should load")
	assert_eq(card.cost, 2)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "medium")
	assert_eq(int(card.effects[0].get("value", 0)), 13)
	assert_eq(String(card.effects[1].get("status", "")), "weak")
	assert_eq(String(card.effects[2].get("status", "")), "vulnerable")
	# Upgrade doubles the debuffs, not the damage.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 13)
	assert_eq(int(card.upgraded_effects[1].get("stacks", 0)), 2)
	assert_eq(int(card.upgraded_effects[2].get("stacks", 0)), 2)

# --- Swing size words in the Action library ---------------------------------

func test_action_swing_arcs_grow_with_size() -> void:
	var lib: ActionAttackLibrary = Data.action_attacks
	var small: Dictionary = lib.resolve(_swing_card("small"))
	var medium: Dictionary = lib.resolve(_swing_card("medium"))
	var large: Dictionary = lib.resolve(_swing_card("large"))
	assert_lt(float(small["arc_deg"]), float(medium["arc_deg"]),
		"small swing wraps less than medium")
	assert_eq(float(large["arc_deg"]), 360.0, "large swing is the full ring")
	assert_lt(float(small["reach_px"]), float(large["reach_px"]),
		"bigger swings also reach farther")

func test_action_explicit_arc_param_still_wins() -> void:
	var card := CardData.new()
	card.attack_shape = &"swing"
	card.attack_params = {"size": "small", "arc": 270}
	var spec: Dictionary = Data.action_attacks.resolve(card)
	assert_eq(float(spec["arc_deg"]), 270.0, "arc= overrides the size word")

func _swing_card(size: String) -> CardData:
	var card := CardData.new()
	card.attack_shape = &"swing"
	card.attack_params = {"size": size}
	return card

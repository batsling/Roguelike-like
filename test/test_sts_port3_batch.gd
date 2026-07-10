extends GutTest

# Covers the Immolate / Masterful Stab / Perfected Strike / Poisoned Stab /
# Pummel / Quick Slash / Rampage batch and the engine pieces added with it:
#   - cost_increase_from        (Masterful Stab: 1 more Energy per hp_losses —
#                                the surcharge mirror of Blood for Blood)
#   - bonus_per_card_name       (Perfected Strike: +N damage per card in the
#                                combat deck whose name contains "Strike")
# Immolate rides the existing conjure verb (Burn to discard) + magic cleave +
# Fire element; Rampage is Glass Knife's boost_cards twin with a positive
# value; Poisoned Stab / Pummel / Quick Slash are existing verbs end to end.
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Records damage calls; carries the combat piles for the strike count.
class _DmgScene:
	extends RefCounted
	var enemies: Array = []
	var hand: Array = []
	var draw_pile: Array = []
	var discard_pile: Array = []
	var amounts: Array = []
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		amounts.append(amount)

# Records pile / resource calls (draw, conjure).
class _PileScene:
	extends RefCounted
	var enemies: Array = []
	var cards_drawn: int = 0
	var conjures: Array = []        # [{card_id, destination, count}]
	func draw_cards(n: int) -> void:
		cards_drawn += n
	func conjure_card(card_id: StringName, destination: String, count: int,
			_source_card = null, _force_upgraded: bool = false) -> void:
		conjures.append({"card_id": card_id, "destination": destination,
			"count": count})

func _actor(hp: int = 50) -> CombatActor:
	var a := CombatActor.new()
	a.max_hp = hp
	a.hp = hp
	return a

func _inst(id: StringName) -> CardInstance:
	return CardInstance.from_data(Data.get_card(id))

# --- Perfected Strike (bonus_per_card_name) ------------------------------------

func test_perfected_strike_counts_itself() -> void:
	var scene := _DmgScene.new()
	var ps := _inst(&"perfected_strike")
	scene.hand = [ps]
	EffectSystem.apply(Data.get_card(&"perfected_strike").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": ps})
	assert_eq(int(scene.amounts[0]), 8,
		'"Perfected Strike" contains "Strike" -> 6 + 2x1')

func test_perfected_strike_counts_strikes_across_all_piles() -> void:
	var scene := _DmgScene.new()
	var ps := _inst(&"perfected_strike")
	scene.hand = [ps, _inst(&"strike_ironclad"), _inst(&"bash")]
	scene.draw_pile = [_inst(&"twin_strike"), _inst(&"acrobatics")]
	scene.discard_pile = [_inst(&"pommel_strike")]
	EffectSystem.apply(Data.get_card(&"perfected_strike").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": ps})
	assert_eq(int(scene.amounts[0]), 14,
		"4 Strike-named cards (incl. itself) -> 6 + 2x4")

func test_perfected_strike_counts_a_played_card_removed_from_hand() -> void:
	# A scene that removes the played card from hand before resolving still
	# counts it once — the explicit played-card fallback.
	var scene := _DmgScene.new()
	var ps := _inst(&"perfected_strike")
	scene.hand = [_inst(&"strike_ironclad")]
	EffectSystem.apply(Data.get_card(&"perfected_strike").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": ps})
	assert_eq(int(scene.amounts[0]), 10,
		"the mid-resolve card counts once even outside every pile")

func test_perfected_strike_ignores_non_strike_cards() -> void:
	var scene := _DmgScene.new()
	var ps := _inst(&"perfected_strike")
	scene.hand = [ps, _inst(&"bash"), _inst(&"acrobatics")]
	scene.discard_pile = [_inst(&"cleave")]
	EffectSystem.apply(Data.get_card(&"perfected_strike").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": ps})
	assert_eq(int(scene.amounts[0]), 8, "only Strike-named cards count")

func test_perfected_strike_upgrade_bumps_the_per_card_bonus() -> void:
	var scene := _DmgScene.new()
	var ps := CardInstance.from_data(Data.get_card(&"perfected_strike"), true)
	scene.hand = [ps, _inst(&"strike_ironclad")]
	EffectSystem.apply(Data.get_card(&"perfected_strike").upgraded_effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": ps})
	assert_eq(int(scene.amounts[0]), 12, "upgraded: 6 + 3x2")

func test_perfected_strike_counts_upgraded_strikes_too() -> void:
	# "Strike+" still contains "Strike" — the match reads the display name.
	var scene := _DmgScene.new()
	var ps := _inst(&"perfected_strike")
	scene.hand = [ps, CardInstance.from_data(Data.get_card(&"strike_ironclad"), true)]
	EffectSystem.apply(Data.get_card(&"perfected_strike").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": ps})
	assert_eq(int(scene.amounts[0]), 10, "an upgraded Strike still counts")

func test_perfected_strike_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"perfected_strike")
	assert_not_null(card, "perfected_strike.tres should load")
	assert_eq(card.cost, 2)
	var dmg: Dictionary = card.effects[0]
	assert_eq(int(dmg.get("value", 0)), 6)
	assert_eq(String(dmg.get("bonus_per_card_name", "")), "strike")
	assert_eq(int(dmg.get("bonus_per_card", 0)), 2)
	assert_eq(int(card.upgraded_effects[0].get("bonus_per_card", 0)), 3)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

# --- Masterful Stab (cost_increase_from) ----------------------------------------

func test_masterful_stab_costs_one_more_per_hp_loss() -> void:
	var losses_before: int = GameState.incremental_hp_losses
	var stab := _inst(&"masterful_stab")
	GameState.incremental_hp_losses = 0
	assert_eq(stab.get_cost(), 0, "no HP losses -> the base cost 0")
	GameState.incremental_hp_losses = 3
	assert_eq(stab.get_cost(), 3, "3 HP-loss instances -> costs 3")
	GameState.incremental_hp_losses = losses_before

func test_cost_increase_nets_against_a_combat_discount() -> void:
	var losses_before: int = GameState.incremental_hp_losses
	var stab := _inst(&"masterful_stab")
	GameState.incremental_hp_losses = 2
	stab.combat_cost_delta = -1
	assert_eq(stab.get_cost(), 1, "surcharge 2 + Empty Tome -1 -> 1")
	GameState.incremental_hp_losses = losses_before

func test_masterful_stab_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"masterful_stab")
	assert_not_null(card, "masterful_stab.tres should load")
	assert_eq(card.cost, 0)
	assert_eq(String(card.cost_increase_from), "hp_losses")
	assert_eq(int(card.effects[0].get("value", 0)), 12)
	assert_eq(String(card.effects[0].get("damage_type", "")), "melee")
	# Upgrade bumps the damage; the surcharge stays.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 16)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

# --- Immolate (magic cleave + Burn conjure + Fire element) -----------------------

func test_immolate_conjures_a_burn_to_discard() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"immolate").effects[1],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.conjures.size(), 1)
	assert_eq(String(scene.conjures[0]["card_id"]), "burn")
	assert_eq(String(scene.conjures[0]["destination"]), "discard")
	assert_eq(int(scene.conjures[0]["count"]), 1)

func test_immolate_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"immolate")
	assert_not_null(card, "immolate.tres should load")
	assert_eq(card.cost, 2)
	assert_eq(String(card.element), "fire")
	var dmg: Dictionary = card.effects[0]
	assert_eq(int(dmg.get("value", 0)), 21)
	assert_eq(String(dmg.get("target", "")), "all_enemies")
	assert_eq(String(dmg.get("damage_type", "")), "magic")
	assert_eq(String(dmg.get("element", "")), "fire",
		"the element is stamped onto the dmg effect for the on-hit Burn")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 28)
	assert_eq(String(card.attack_shape), "auto_aoe")
	assert_eq(String(card.attack_params.get("target", "")), "nearest")
	assert_eq(String(card.attack_params.get("size", "")), "large")

# --- Poisoned Stab (melee + Poison inflict + Poison element) ---------------------

func test_poisoned_stab_inflicts_poison() -> void:
	var tgt := _actor()
	EffectSystem.apply(Data.get_card(&"poisoned_stab").effects[1],
		{"source": _actor(), "target": tgt, "scene": null})
	assert_eq(tgt.get_status(&"poison"), 3, "Inflict 3 Poison")

func test_poisoned_stab_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"poisoned_stab")
	assert_not_null(card, "poisoned_stab.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(String(card.element), "poison")
	assert_eq(int(card.effects[0].get("value", 0)), 6)
	assert_eq(String(card.effects[0].get("element", "")), "poison")
	var inflict: Dictionary = card.effects[1]
	assert_eq(String(inflict.get("status", "")), "poison")
	assert_eq(int(inflict.get("stacks", 0)), 3)
	# Upgrade bumps both the damage and the Poison.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 8)
	assert_eq(int(card.upgraded_effects[1].get("stacks", 0)), 4)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Pummel (multi-hit + Exhaust) -------------------------------------------------

func test_pummel_lands_four_hits_of_two() -> void:
	var scene := _DmgScene.new()
	EffectSystem.apply(Data.get_card(&"pummel").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(scene.amounts.size(), 4, "2x4 -> four hits")
	assert_eq(int(scene.amounts[0]), 2)

func test_pummel_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"pummel")
	assert_not_null(card, "pummel.tres should load")
	assert_eq(card.cost, 1)
	assert_true(card.exhaust, "Exhaust keyword -> exhaust flag")
	assert_eq(int(card.effects[0].get("hits", 0)), 4)
	assert_eq(int(card.upgraded_effects[0].get("hits", 0)), 5,
		"upgrade adds a hit, not damage")
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Quick Slash (dmg + draw) ------------------------------------------------------

func test_quick_slash_draws_a_card() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"quick_slash").effects[1],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.cards_drawn, 1, "Draw 1 Card")

func test_quick_slash_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"quick_slash")
	assert_not_null(card, "quick_slash.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(int(card.effects[0].get("value", 0)), 8)
	assert_eq(String(card.effects[1].get("type", "")), "draw")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 12)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Rampage (positive self-boost) --------------------------------------------------

func test_rampage_boost_raises_its_own_later_plays() -> void:
	# Glass Knife's machinery with the sign flipped: each play registers a
	# +5 dmg boost matched on the card's own id.
	var card: CardData = Data.get_card(&"rampage")
	var boosts: Array = [card.effects[1], card.effects[1]]
	var folded: Dictionary = Stats.apply_card_boosts(card.effects[0], card, boosts)
	assert_eq(int(folded.get("value", 0)), 18, "8 base + 5x2 registered boosts")

func test_rampage_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"rampage")
	assert_not_null(card, "rampage.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(int(card.effects[0].get("value", 0)), 8)
	var boost: Dictionary = card.effects[1]
	assert_eq(String(boost.get("type", "")), "boost_cards")
	assert_eq(String(boost.get("match_id", "")), "rampage")
	assert_eq(String(boost.get("stat", "")), "dmg")
	assert_eq(int(boost.get("value", 0)), 5)
	# Upgrade bumps the ramp, not the base damage.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 8)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 8)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "small")

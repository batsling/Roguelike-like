extends GutTest

# Covers the Slice / Reckless Charge / Wild Strike / Sneaky Strike / Unload /
# Sever Soul / Searing Blow batch and the engine pieces added with it:
#   - if_counter                (Sneaky Strike: +2 Energy only when the
#                                discards_this_turn counter is live)
#   - discard/exhaust all `only: non_attack` (Unload / Sever Soul: the hand
#                                sweeps spare Attack cards)
#   - sequential upgrades       (Searing Blow: upgradable ANY number of times,
#                                +3 dmg per banked upgrade, tracked per
#                                physical card on CardInstance.upgrade_count)
# Slice / Reckless Charge / Wild Strike are existing verbs end to end.
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Records damage calls.
class _DmgScene:
	extends RefCounted
	var enemies: Array = []
	var amounts: Array = []
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		amounts.append(amount)

# Records pile / resource calls (conjure, energy, sweeps).
class _PileScene:
	extends RefCounted
	var enemies: Array = []
	var energy_gained: int = 0
	var conjures: Array = []        # [{card_id, destination, count}]
	var discard_sweeps: Array = []  # [only]
	var exhaust_sweeps: Array = []  # [only]
	func gain_energy(n: int) -> void:
		energy_gained += n
	func conjure_card(card_id: StringName, destination: String, count: int,
			_source_card = null, _force_upgraded: bool = false) -> void:
		conjures.append({"card_id": card_id, "destination": destination,
			"count": count})
	func discard_hand(_source_card = null, only: String = "") -> int:
		discard_sweeps.append(only)
		return 0
	func exhaust_hand(_source_card = null, only: String = "") -> int:
		exhaust_sweeps.append(only)
		return 0

func _actor(hp: int = 50) -> CombatActor:
	var a := CombatActor.new()
	a.max_hp = hp
	a.hp = hp
	return a

func _inst(id: StringName) -> CardInstance:
	return CardInstance.from_data(Data.get_card(id))

# --- Sneaky Strike (if_counter) --------------------------------------------------

func test_energy_lands_when_a_discard_happened_this_turn() -> void:
	var before: int = GameState.incremental_discards_turn
	GameState.incremental_discards_turn = 1
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"sneaky_strike").effects[1],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.energy_gained, 2, "a live discard counter -> +2 Energy")
	GameState.incremental_discards_turn = before

func test_energy_skipped_without_a_discard_this_turn() -> void:
	var before: int = GameState.incremental_discards_turn
	GameState.incremental_discards_turn = 0
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"sneaky_strike").effects[1],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.energy_gained, 0, "no discards this turn -> no Energy")
	GameState.incremental_discards_turn = before

func test_sneaky_strike_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"sneaky_strike")
	assert_not_null(card, "sneaky_strike.tres should load")
	assert_eq(card.cost, 2)
	assert_eq(int(card.effects[0].get("value", 0)), 12)
	var gate: Dictionary = card.effects[1]
	assert_eq(String(gate.get("type", "")), "if_counter")
	assert_eq(String(gate.get("counter", "")), "discards_this_turn")
	assert_eq(String(gate.get("effect", {}).get("type", "")), "gain_energy")
	assert_eq(int(gate.get("effect", {}).get("value", 0)), 2)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 16)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Unload / Sever Soul (filtered hand sweeps) -----------------------------------

func test_unload_sweep_carries_the_non_attack_filter() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"unload").effects[1],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.discard_sweeps, ["non_attack"],
		"the discard sweep passes only=non_attack to the scene")

func test_sever_soul_sweep_carries_the_non_attack_filter() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"sever_soul").effects[0],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.exhaust_sweeps, ["non_attack"],
		"the exhaust sweep passes only=non_attack to the scene")

func test_unload_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"unload")
	assert_not_null(card, "unload.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(int(card.effects[0].get("value", 0)), 14)
	assert_eq(String(card.effects[0].get("damage_type", "")), "ranged")
	var sweep: Dictionary = card.effects[1]
	assert_true(bool(sweep.get("all", false)))
	assert_eq(String(sweep.get("only", "")), "non_attack")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 18)
	assert_eq(String(card.attack_shape), "projectile")
	assert_eq(int(card.attack_params.get("spread", 0)), 4,
		"Unload fans 4 projectiles in action")

func test_sever_soul_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"sever_soul")
	assert_not_null(card, "sever_soul.tres should load")
	assert_eq(card.cost, 2)
	var sweep: Dictionary = card.effects[0]
	assert_eq(String(sweep.get("type", "")), "exhaust")
	assert_true(bool(sweep.get("all", false)))
	assert_eq(String(sweep.get("only", "")), "non_attack")
	assert_eq(int(card.effects[1].get("value", 0)), 16)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 22)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Searing Blow (sequential upgrades) --------------------------------------------

func test_searing_blow_upgrades_stack_forever() -> void:
	var sb := _inst(&"searing_blow")
	assert_eq(int(sb.get_effects()[0].get("value", 0)), 12, "fresh: base 12")
	assert_true(sb.can_take_upgrade())
	sb.apply_upgrade()
	assert_eq(int(sb.get_effects()[0].get("value", 0)), 15, "+3 after one upgrade")
	assert_true(sb.can_take_upgrade(), "sequential cards never saturate")
	sb.apply_upgrade()
	sb.apply_upgrade()
	assert_eq(sb.upgrade_count, 3)
	assert_eq(int(sb.get_effects()[0].get("value", 0)), 21, "12 + 3x3")
	assert_eq(sb.get_cost(), 2, "the cost never moves")

func test_searing_blow_display_name_wears_the_count() -> void:
	var sb := _inst(&"searing_blow")
	assert_eq(sb.get_display_name(), "Searing Blow")
	sb.apply_upgrade()
	assert_eq(sb.get_display_name(), "Searing Blow+")
	sb.apply_upgrade()
	assert_eq(sb.get_display_name(), "Searing Blow+2")

func test_binary_cards_still_saturate_after_one_upgrade() -> void:
	var bash := _inst(&"bash")
	assert_true(bash.can_take_upgrade())
	bash.apply_upgrade()
	assert_false(bash.can_take_upgrade(), "a binary card saturates")
	assert_eq(bash.upgrade_count, 0, "no sequential count on binary cards")

func test_upgraded_reward_searing_blow_starts_at_one() -> void:
	# CardRewardScreen mints upgraded picks via from_data(d, true).
	var sb := CardInstance.from_data(Data.get_card(&"searing_blow"), true)
	assert_eq(sb.upgrade_count, 1)
	assert_eq(int(sb.get_effects()[0].get("value", 0)), 15)
	assert_eq(sb.get_display_name(), "Searing Blow+")

func test_searing_blow_survives_a_save_round_trip() -> void:
	var sb := _inst(&"searing_blow")
	sb.apply_upgrade()
	sb.apply_upgrade()
	var payload: Array = SaveSystem._serialize_deck([sb])
	var restored: Array = SaveSystem._resolve_deck(payload)
	assert_eq(restored.size(), 1)
	var back: CardInstance = restored[0]
	assert_eq(back.upgrade_count, 2, "the banked count persists")
	assert_eq(int(back.get_effects()[0].get("value", 0)), 18)

func test_whetstone_style_random_upgrades_keep_stacking() -> void:
	# upgrade_random_deck_cards routes through can_take_upgrade/apply_upgrade,
	# so a sequential card stays a legal pick after every upgrade.
	var deck_before: Array = GameState.deck.duplicate()
	GameState.deck = [_inst(&"searing_blow")]
	GameState.upgrade_random_deck_cards("attack", 1)
	GameState.upgrade_random_deck_cards("attack", 1)
	assert_eq((GameState.deck[0] as CardInstance).upgrade_count, 2,
		"two Whetstone passes bank two upgrades")
	GameState.deck = deck_before

func test_searing_blow_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"searing_blow")
	assert_not_null(card, "searing_blow.tres should load")
	assert_eq(card.cost, 2)
	assert_eq(card.sequential_upgrade_step, 3)
	assert_true(card.can_upgrade, "sequential cards are upgradable with N/A ↑ columns")
	assert_eq(String(card.element), "fire")
	var dmg: Dictionary = card.effects[0]
	assert_eq(int(dmg.get("value", 0)), 12)
	assert_eq(String(dmg.get("damage_type", "")), "melee")
	assert_eq(String(dmg.get("element", "")), "fire",
		"the element is stamped onto the dmg effect for the on-hit Burn")
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

# --- Slice / Reckless Charge / Wild Strike (existing verbs) -------------------------

func test_slice_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"slice")
	assert_not_null(card, "slice.tres should load")
	assert_eq(card.cost, 0)
	assert_eq(int(card.effects[0].get("value", 0)), 6)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 9)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "small")

func test_reckless_charge_conjures_a_dazed_to_deck() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"reckless_charge").effects[1],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.conjures.size(), 1)
	assert_eq(String(scene.conjures[0]["card_id"]), "dazed")
	assert_eq(String(scene.conjures[0]["destination"]), "draw")

func test_reckless_charge_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"reckless_charge")
	assert_not_null(card, "reckless_charge.tres should load")
	assert_eq(card.cost, 0)
	assert_eq(int(card.effects[0].get("value", 0)), 7)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 10)
	assert_eq(String(card.attack_shape), "smash")
	assert_eq(String(card.attack_params.get("size", "")), "small")

func test_wild_strike_conjures_a_wound_to_deck() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"wild_strike").effects[1],
		{"source": _actor(), "target": null, "scene": scene})
	assert_eq(scene.conjures.size(), 1)
	assert_eq(String(scene.conjures[0]["card_id"]), "wound")
	assert_eq(String(scene.conjures[0]["destination"]), "draw")

func test_wild_strike_feeds_perfected_strike() -> void:
	# "Wild Strike" contains "Strike" — the new batch grows Perfected Strike's
	# count for free.
	var scene := _DmgScene.new()
	var ps := _inst(&"perfected_strike")
	var _hand_stub: Array = [ps, _inst(&"wild_strike"), _inst(&"sneaky_strike")]
	# _DmgScene has no hand; count through EffectSystem's played-card fallback
	# is 1 — use a handed scene instead.
	var handed := _HandedDmgScene.new()
	handed.hand = _hand_stub
	EffectSystem.apply(Data.get_card(&"perfected_strike").effects[0],
		{"source": _actor(), "target": _actor(), "scene": handed, "card": ps})
	assert_eq(int(handed.amounts[0]), 12, "6 + 2x(itself + Wild + Sneaky)")

class _HandedDmgScene:
	extends RefCounted
	var enemies: Array = []
	var hand: Array = []
	var amounts: Array = []
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		amounts.append(amount)

func test_wild_strike_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"wild_strike")
	assert_not_null(card, "wild_strike.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(int(card.effects[0].get("value", 0)), 12)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 17)
	assert_eq(String(card.attack_shape), "smash")
	assert_eq(String(card.attack_params.get("size", "")), "small")

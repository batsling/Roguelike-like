extends GutTest

# Covers the Burn / Blood for Blood / Choke / Clash / Dash / Dropkick /
# Endless Agony / Eviscerate / Fiend Fire batch and the engine pieces added
# with it:
#   - Choked status         (bites per card play, wiped at the turn boundary)
#   - if_hand=all_attacks   (Clash whiffs with any non-Attack in hand)
#   - if_target_status      (Dropkick's gated energy/draw payoff)
#   - drawn: trigger        (Endless Agony conjures itself on draw)
#   - exhaust:all + dmg hits_from: "exhausted" (Fiend Fire)
#   - cost_reduce_from      (Blood for Blood / Eviscerate dynamic discounts)
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Records damage calls; carries an optional hand for the Clash gate.
class _DmgScene:
	extends RefCounted
	var enemies: Array = []
	var hand: Array = []
	var last_exhaust_count: int = 0
	var amounts: Array = []
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		amounts.append(amount)

# Records pile / resource calls (exhaust_hand, gain_energy, draw).
class _PileScene:
	extends RefCounted
	var enemies: Array = []
	var exhaust_hand_calls: int = 0
	var energy_gained: int = 0
	var cards_drawn: int = 0
	var conjures: Array = []
	var dots: Array = []            # [{target, amount, source}]
	func exhaust_hand(_source_card = null, _only: String = "") -> int:
		exhaust_hand_calls += 1
		return 0
	func gain_energy(n: int) -> void:
		energy_gained += n
	func draw_cards(n: int) -> void:
		cards_drawn += n
	func conjure_card(card_id: StringName, destination: String, count: int, _source, upgraded: bool = false) -> void:
		conjures.append({"card_id": card_id, "destination": destination,
			"count": count, "upgraded": upgraded})
	func apply_dot(target, amount: int, source_name: String) -> void:
		dots.append({"target": target, "amount": amount, "source": source_name})

func _actor(hp: int = 10) -> CombatActor:
	var a := CombatActor.new()
	a.max_hp = hp
	a.hp = hp
	return a

# --- Choked (Choke) ----------------------------------------------------------

func test_choked_bites_each_afflicted_actor_on_card_play() -> void:
	var scene := _PileScene.new()
	var choked_enemy := _actor()
	choked_enemy.add_status(&"choked", 3)
	var clean_enemy := _actor()
	Stats.choked_on_card_played([choked_enemy, clean_enemy], scene)
	assert_eq(scene.dots.size(), 1, "only the choked actor bites")
	assert_eq(int(scene.dots[0]["amount"]), 3, "bite equals the stacks")
	assert_eq(String(scene.dots[0]["source"]), "choked")

func test_choked_skips_dead_actors() -> void:
	var scene := _PileScene.new()
	var corpse := _actor()
	corpse.add_status(&"choked", 4)
	corpse.hp = 0
	Stats.choked_on_card_played([corpse], scene)
	assert_eq(scene.dots.size(), 0, "dead actors don't bleed out further")

func test_clear_status_stacks_wipes_choked() -> void:
	var a := _actor()
	a.add_status(&"choked", 5)
	Stats.clear_status_stacks(a, &"choked")
	assert_eq(a.get_status(&"choked"), 0, "all Choked lost at end of turn")

func test_choked_is_registered_as_a_persistence_debuff_with_icon() -> void:
	assert_true(Stats.PERSISTENCE_DEBUFFS.has(&"choked"),
		"player Persistence scales Choked like the other DoT debuffs")
	assert_true(Stats.STATUS_ICONS.has(&"choked"), "status icon mapped")

func test_choke_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"choke")
	assert_not_null(card, "choke.tres should load")
	assert_eq(card.cost, 2)
	assert_eq(int(card.effects[0].get("value", 0)), 12)
	assert_eq(String(card.effects[1].get("status", "")), "choked")
	assert_eq(int(card.effects[1].get("stacks", 0)), 3)
	# Upgrade bumps the stacks, not the damage.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 12)
	assert_eq(int(card.upgraded_effects[1].get("stacks", 0)), 5)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Clash (if_hand=all_attacks) ---------------------------------------------

func test_clash_hits_when_hand_is_all_attacks() -> void:
	var scene := _DmgScene.new()
	var clash := CardInstance.from_data(Data.get_card(&"clash"))
	var other_attack := CardInstance.from_data(Data.get_card(&"choke"))
	scene.hand = [clash, other_attack]
	EffectSystem.apply(Data.get_card(&"clash").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": clash})
	assert_eq(scene.amounts.size(), 1, "all-Attack hand -> the hit lands")
	assert_eq(int(scene.amounts[0]), 14)

func test_clash_whiffs_with_a_skill_in_hand() -> void:
	var scene := _DmgScene.new()
	var clash := CardInstance.from_data(Data.get_card(&"clash"))
	var skill := CardInstance.from_data(Data.get_card(&"acrobatics"))
	scene.hand = [clash, skill]
	EffectSystem.apply(Data.get_card(&"clash").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": clash})
	assert_eq(scene.amounts.size(), 0, "a Skill in hand -> it does nothing")

func test_clash_whiffs_with_a_status_card_in_hand() -> void:
	var scene := _DmgScene.new()
	var clash := CardInstance.from_data(Data.get_card(&"clash"))
	var wound := CardInstance.from_data(Data.get_card(&"wound"))
	scene.hand = [clash, wound]
	EffectSystem.apply(Data.get_card(&"clash").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": clash})
	assert_eq(scene.amounts.size(), 0, "statuses spoil Clash too")

func test_clash_ignores_itself_in_hand() -> void:
	var scene := _DmgScene.new()
	var clash := CardInstance.from_data(Data.get_card(&"clash"))
	scene.hand = [clash]
	EffectSystem.apply(Data.get_card(&"clash").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": clash})
	assert_eq(scene.amounts.size(), 1, "the played Clash doesn't gate itself")

func test_clash_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"clash")
	assert_not_null(card, "clash.tres should load")
	assert_eq(card.cost, 0)
	assert_eq(String(card.effects[0].get("if_hand", "")), "all_attacks")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 18)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Dropkick (if_target_status wrapper) -------------------------------------

func test_dropkick_payoff_fires_on_vulnerable_target() -> void:
	var scene := _PileScene.new()
	var tgt := _actor()
	tgt.add_status(&"vulnerable", 1)
	EffectSystem.apply({"type": "if_target_status", "status": "vulnerable",
		"target": "enemy", "effect": {"type": "gain_energy", "value": 1}},
		{"source": _actor(), "target": tgt, "scene": scene})
	assert_eq(scene.energy_gained, 1, "Vulnerable target -> +1 Energy")

func test_dropkick_payoff_skips_a_clean_target() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply({"type": "if_target_status", "status": "vulnerable",
		"target": "enemy", "effect": {"type": "draw", "value": 1}},
		{"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(scene.cards_drawn, 0, "no Vulnerable -> no payoff")

func test_dropkick_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"dropkick")
	assert_not_null(card, "dropkick.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(int(card.effects[0].get("value", 0)), 5)
	var gate: Dictionary = card.effects[1]
	assert_eq(String(gate.get("type", "")), "if_target_status")
	assert_eq(String(gate.get("status", "")), "vulnerable")
	assert_eq(String(gate.get("target", "")), "enemy",
		"explicit enemy target so strategy doesn't default the gate to self")
	assert_eq(String(gate.get("effect", {}).get("type", "")), "gain_energy")
	assert_eq(String(card.effects[2].get("effect", {}).get("type", "")), "draw")
	# Upgrade bumps only the damage.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 8)

# --- Endless Agony (drawn: trigger) ------------------------------------------

func test_endless_agony_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"endless_agony")
	assert_not_null(card, "endless_agony.tres should load")
	assert_eq(card.cost, 0)
	assert_true(card.exhaust)
	assert_eq(String(card.effects[0].get("damage_type", "")), "ranged")
	assert_eq(int(card.effects[0].get("value", 0)), 4)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 6)
	assert_eq(card.triggers.size(), 1)
	var trig: Dictionary = card.triggers[0]
	assert_eq(String(trig.get("on", "")), "drawn")
	var conj: Dictionary = trig.get("effects", [{}])[0]
	assert_eq(String(conj.get("type", "")), "conjure")
	assert_eq(String(conj.get("card_id", "")), "self")
	assert_eq(String(conj.get("destination", "")), "hand")
	assert_eq(String(card.attack_shape), "smash")
	assert_eq(String(card.attack_params.get("size", "")), "small")

func test_drawn_trigger_conjure_self_routes_to_hand() -> void:
	# The scene-level _fire_drawn_triggers hands the trigger's effects to
	# EffectSystem with the drawn card as ctx.card — conjure:self copies IT.
	var scene := _PileScene.new()
	var agony := CardInstance.from_data(Data.get_card(&"endless_agony"))
	var trig: Dictionary = agony.data.triggers[0]
	EffectSystem.apply(trig.get("effects", [{}])[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": agony})
	assert_eq(scene.conjures.size(), 1)
	assert_eq(String(scene.conjures[0]["card_id"]), "self")
	assert_eq(String(scene.conjures[0]["destination"]), "hand")

# --- Fiend Fire (exhaust:all + hits_from: "exhausted") -----------------------

func test_exhaust_all_routes_to_exhaust_hand() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply({"type": "exhaust", "all": true}, {"scene": scene})
	assert_eq(scene.exhaust_hand_calls, 1)

func test_fiend_fire_dmg_repeats_once_per_exhausted_card() -> void:
	var scene := _DmgScene.new()
	scene.last_exhaust_count = 3
	var eff := {"type": "dmg", "value": 7, "damage_type": "ranged",
		"hits_from": "exhausted"}
	EffectSystem.apply(eff, {"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(scene.amounts.size(), 3, "3 exhausted -> three hits")

func test_fiend_fire_with_empty_hand_deals_no_hits() -> void:
	var scene := _DmgScene.new()
	scene.last_exhaust_count = 0
	var eff := {"type": "dmg", "value": 7, "damage_type": "ranged",
		"hits_from": "exhausted"}
	EffectSystem.apply(eff, {"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(scene.amounts.size(), 0, "nothing exhausted -> the shot whiffs")

func test_fiend_fire_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"fiend_fire")
	assert_not_null(card, "fiend_fire.tres should load")
	assert_eq(card.cost, 2)
	assert_true(card.exhaust)
	assert_eq(String(card.element), "fire")
	assert_true(bool(card.effects[0].get("all", false)), "exhaust the whole hand")
	var dmg: Dictionary = card.effects[1]
	assert_eq(String(dmg.get("hits_from", "")), "exhausted")
	assert_eq(int(dmg.get("value", 0)), 7)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 10)
	assert_eq(String(card.attack_shape), "projectile")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

# --- Dynamic cost (Blood for Blood / Eviscerate) ------------------------------

func test_blood_for_blood_cost_drops_per_hp_loss() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"blood_for_blood"))
	GameState.incremental_hp_losses = 0
	assert_eq(inst.get_cost(), 4, "pristine: full price")
	GameState.incremental_hp_losses = 2
	assert_eq(inst.get_cost(), 2, "two HP losses -> 2 cheaper")
	GameState.incremental_hp_losses = 9
	assert_eq(inst.get_cost(), 0, "discount floors at 0")
	GameState.incremental_hp_losses = 0

func test_blood_for_blood_upgrade_starts_at_three() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"blood_for_blood"), true)
	GameState.incremental_hp_losses = 0
	assert_eq(inst.get_cost(), 3, "upgraded base cost")
	GameState.incremental_hp_losses = 1
	assert_eq(inst.get_cost(), 2)
	GameState.incremental_hp_losses = 0

func test_eviscerate_cost_tracks_discards_and_resets_on_turn_tick() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"eviscerate"))
	GameState.incremental_discards_turn = 0
	assert_eq(inst.get_cost(), 3)
	GameState.incremental_on_discard()
	GameState.incremental_on_discard()
	assert_eq(inst.get_cost(), 1, "two discards this turn -> 2 cheaper")
	GameState.incremental_on_turn_tick()
	assert_eq(inst.get_cost(), 3, "the discount is per-turn: tick resets it")

func test_hp_loss_counter_bumps_only_in_combat() -> void:
	var hp_before: int = GameState.hp
	var losses_before: int = GameState.incremental_hp_losses
	var scene := _PileScene.new()
	GameState.set_combat_context(scene, null)
	GameState.change_hp(-2)
	assert_eq(GameState.incremental_hp_losses, losses_before + 1,
		"one loss instance, whatever the size")
	GameState.change_hp(1)
	assert_eq(GameState.incremental_hp_losses, losses_before + 1,
		"healing never counts")
	GameState.clear_combat_context()
	GameState.change_hp(-1)
	assert_eq(GameState.incremental_hp_losses, losses_before + 1,
		"out-of-combat drains never count")
	GameState.set_hp(hp_before)
	GameState.incremental_hp_losses = losses_before

func test_combat_start_resets_the_dynamic_cost_counters() -> void:
	GameState.incremental_hp_losses = 5
	GameState.incremental_discards_turn = 2
	GameState.incremental_on_combat_started()
	assert_eq(GameState.incremental_hp_losses, 0)
	assert_eq(GameState.incremental_discards_turn, 0)

func test_x_cost_cards_ignore_cost_reduce() -> void:
	# cost_reduce_from on an X-cost card would be an authoring error; the
	# instance rule keeps X-cost at -1 regardless.
	var data := CardData.new()
	data.cost = -1
	data.cost_reduce_from = &"hp_losses"
	var inst := CardInstance.from_data(data)
	GameState.incremental_hp_losses = 3
	assert_eq(inst.get_cost(), -1)
	GameState.incremental_hp_losses = 0

# --- Burn / Dash (simple round-trips) -----------------------------------------

func test_burn_tres_is_an_unplayable_eot_status() -> void:
	var card: CardData = Data.get_card(&"burn")
	assert_not_null(card, "burn.tres should load")
	assert_eq(card.type, CardData.CardType.STATUS)
	assert_true(card.unplayable)
	assert_false(card.can_upgrade, "base Burn only — no upgraded form")
	assert_eq(card.effects.size(), 0, "nothing on play — it can't be played")
	var trig: Dictionary = card.triggers[0]
	assert_eq(String(trig.get("on", "")), "eot")
	var eff: Dictionary = trig.get("effects", [{}])[0]
	assert_eq(String(eff.get("type", "")), "dmg")
	assert_eq(int(eff.get("value", 0)), 2)
	assert_eq(String(eff.get("target", "")), "self")

func test_dash_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"dash")
	assert_not_null(card, "dash.tres should load")
	assert_eq(card.cost, 2)
	assert_eq(String(card.effects[0].get("type", "")), "block")
	assert_eq(int(card.effects[0].get("value", 0)), 10)
	assert_eq(int(card.effects[1].get("value", 0)), 10)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 13)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 13)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

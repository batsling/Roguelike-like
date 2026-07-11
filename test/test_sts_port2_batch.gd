extends GutTest

# Covers the Flechettes / Go for the Eyes / Grand Finale / Headbutt /
# Heel Hook / Hemokinesis batch and the engine pieces added with it:
#   - hits_from: "skills_in_hand"  (Flechettes: one hit per Skill in hand)
#   - if_target_intent             (Go for the Eyes: Weak only when the
#                                   target telegraphs an attack)
#   - if_draw: "empty"             (Grand Finale: whiffs unless the draw
#                                   pile is empty at play time)
#   - topdeck from: "discard"      (Headbutt: the pick pool is the discard)
# Heel Hook rides the existing if_target wrapper (Dropkick) and Hemokinesis
# the existing lose_hp verb (Bloodletting) + Blood element.
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Records damage calls; carries an optional hand + draw pile for the gates.
class _DmgScene:
	extends RefCounted
	var enemies: Array = []
	var hand: Array = []
	var draw_pile: Array = []
	var amounts: Array = []
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		amounts.append(amount)

# Records pile / resource calls (topdeck, gain_energy, draw).
class _PileScene:
	extends RefCounted
	var enemies: Array = []
	var energy_gained: int = 0
	var cards_drawn: int = 0
	var topdecks: Array = []        # [{n, random, from}]
	func gain_energy(n: int) -> void:
		energy_gained += n
	func draw_cards(n: int) -> void:
		cards_drawn += n
	func topdeck_cards(n: int, _source_card = null, random: bool = false, from_pile: String = "hand", _free_until_played: bool = false) -> void:
		topdecks.append({"n": n, "random": random, "from": from_pile})

func _actor(hp: int = 10) -> CombatActor:
	var a := CombatActor.new()
	a.max_hp = hp
	a.hp = hp
	return a

func _inst(id: StringName) -> CardInstance:
	return CardInstance.from_data(Data.get_card(id))

# --- Flechettes (hits_from: "skills_in_hand") ---------------------------------

func test_flechettes_hits_once_per_skill_in_hand() -> void:
	var scene := _DmgScene.new()
	var flechettes := _inst(&"flechettes")
	scene.hand = [flechettes, _inst(&"acrobatics"), _inst(&"backflip"),
		_inst(&"choke")]
	EffectSystem.apply(Data.get_card(&"flechettes").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": flechettes})
	assert_eq(scene.amounts.size(), 2, "two Skills in hand -> two hits")
	assert_eq(int(scene.amounts[0]), 4)

func test_flechettes_whiffs_with_no_skills_in_hand() -> void:
	var scene := _DmgScene.new()
	var flechettes := _inst(&"flechettes")
	scene.hand = [flechettes, _inst(&"choke")]
	EffectSystem.apply(Data.get_card(&"flechettes").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": flechettes})
	assert_eq(scene.amounts.size(), 0, "no Skills -> zero hits")

func test_flechettes_never_counts_the_played_card() -> void:
	# A hypothetical Skill playing the same effect must not count itself —
	# the count is "OTHER cards in hand", same exclusion as Clash's gate.
	var scene := _DmgScene.new()
	var acro := _inst(&"acrobatics")
	scene.hand = [acro]
	EffectSystem.apply(Data.get_card(&"flechettes").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene, "card": acro})
	assert_eq(scene.amounts.size(), 0, "the played card is excluded from the count")

func test_flechettes_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"flechettes")
	assert_not_null(card, "flechettes.tres should load")
	assert_eq(card.cost, 1)
	var dmg: Dictionary = card.effects[0]
	assert_eq(String(dmg.get("hits_from", "")), "skills_in_hand")
	assert_eq(int(dmg.get("value", 0)), 4)
	assert_eq(String(dmg.get("damage_type", "")), "ranged")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 6)
	assert_eq(String(card.attack_shape), "projectile")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

# --- Go for the Eyes (if_target_intent) ---------------------------------------

func test_weak_lands_when_the_target_intends_to_attack() -> void:
	var tgt := _actor()
	tgt.planned_move = {"display": "Bite", "intent_type": "attack", "effects": []}
	EffectSystem.apply(Data.get_card(&"go_for_the_eyes").effects[1],
		{"source": _actor(), "target": tgt, "scene": null})
	assert_eq(tgt.get_status(&"weak"), 1, "attacking intent -> Weak lands")

func test_weak_skipped_when_the_target_does_not_attack() -> void:
	var tgt := _actor()
	tgt.planned_move = {"display": "Harden", "intent_type": "defend", "effects": []}
	EffectSystem.apply(Data.get_card(&"go_for_the_eyes").effects[1],
		{"source": _actor(), "target": tgt, "scene": null})
	assert_eq(tgt.get_status(&"weak"), 0, "non-attack intent -> no Weak")

func test_weak_skipped_when_the_target_has_no_plan() -> void:
	var tgt := _actor()
	EffectSystem.apply(Data.get_card(&"go_for_the_eyes").effects[1],
		{"source": _actor(), "target": tgt, "scene": null})
	assert_eq(tgt.get_status(&"weak"), 0, "no planned move -> no Weak")

func test_ungated_inflicts_ignore_intent() -> void:
	var tgt := _actor()
	EffectSystem.apply({"type": "status", "status": "weak", "stacks": 2,
		"target": "enemy"}, {"source": _actor(), "target": tgt, "scene": null})
	assert_eq(tgt.get_status(&"weak"), 2, "no gate on the effect -> always lands")

func test_actor_intends_attack_reads_the_deckbuilder_plan() -> void:
	var a := _actor()
	assert_false(Stats.actor_intends_attack(a), "empty plan -> no attack intent")
	a.planned_move = {"intent_type": "attack"}
	assert_true(Stats.actor_intends_attack(a))
	a.planned_move = {"intent_type": "buff"}
	assert_false(Stats.actor_intends_attack(a))
	assert_false(Stats.actor_intends_attack(null))

func test_actor_intends_attack_reads_the_strategy_telegraph() -> void:
	var u := BattleUnit.new()
	u.max_hp = 10
	u.hp = 10
	assert_false(Stats.actor_intends_attack(u), "no AI -> no intent")
	var intent := EnemyIntent.new()
	intent.effects = [{"type": "dmg", "value": 3, "target": "enemy"}]
	u.ai = EnemyAI.new()
	u.ai.next_intent = intent
	assert_true(Stats.actor_intends_attack(u), "telegraphed dmg intent -> attack")
	intent.effects = [{"type": "block", "value": 5, "target": "self"}]
	assert_false(Stats.actor_intends_attack(u), "a defend telegraph is not an attack")

func test_go_for_the_eyes_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"go_for_the_eyes")
	assert_not_null(card, "go_for_the_eyes.tres should load")
	assert_eq(card.cost, 0)
	assert_eq(int(card.effects[0].get("value", 0)), 3)
	var inflict: Dictionary = card.effects[1]
	assert_eq(String(inflict.get("status", "")), "weak")
	assert_eq(int(inflict.get("stacks", 0)), 1)
	assert_eq(String(inflict.get("if_target_intent", "")), "attack")
	# Upgrade bumps both the damage and the Weak stacks.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 4)
	assert_eq(int(card.upgraded_effects[1].get("stacks", 0)), 2)
	assert_eq(String(card.attack_shape), "swing")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Grand Finale (if_draw: "empty") -------------------------------------------

func test_grand_finale_hits_with_an_empty_draw_pile() -> void:
	var scene := _DmgScene.new()
	scene.draw_pile = []
	EffectSystem.apply(Data.get_card(&"grand_finale").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(scene.amounts.size(), 1, "empty draw pile -> the burst lands")
	assert_eq(int(scene.amounts[0]), 50)

func test_grand_finale_whiffs_with_cards_left_to_draw() -> void:
	var scene := _DmgScene.new()
	scene.draw_pile = [_inst(&"choke")]
	EffectSystem.apply(Data.get_card(&"grand_finale").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(scene.amounts.size(), 0, "a card in the draw pile -> it does nothing")

func test_grand_finale_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"grand_finale")
	assert_not_null(card, "grand_finale.tres should load")
	assert_eq(card.cost, 0)
	var dmg: Dictionary = card.effects[0]
	assert_eq(String(dmg.get("if_draw", "")), "empty")
	assert_eq(String(dmg.get("target", "")), "all_enemies", "Cleave")
	assert_eq(int(dmg.get("value", 0)), 50)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 60)
	assert_eq(String(card.attack_shape), "nova")
	assert_eq(String(card.attack_params.get("size", "")), "large")

# --- Headbutt (topdeck from: "discard") ----------------------------------------

func test_topdeck_routes_the_from_pile_to_the_scene() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply(Data.get_card(&"headbutt").effects[1], {"scene": scene})
	assert_eq(scene.topdecks.size(), 1)
	assert_eq(String(scene.topdecks[0]["from"]), "discard")
	assert_eq(int(scene.topdecks[0]["n"]), 1)

func test_topdeck_defaults_to_the_hand_pool() -> void:
	var scene := _PileScene.new()
	EffectSystem.apply({"type": "topdeck", "value": 1}, {"scene": scene})
	assert_eq(String(scene.topdecks[0]["from"]), "hand", "Warcry keeps its pool")

func test_headbutt_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"headbutt")
	assert_not_null(card, "headbutt.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(int(card.effects[0].get("value", 0)), 9)
	assert_eq(String(card.effects[1].get("type", "")), "topdeck")
	assert_eq(String(card.effects[1].get("from", "")), "discard")
	# Upgrade bumps only the damage.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 12)
	assert_eq(String(card.upgraded_effects[1].get("from", "")), "discard")
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Heel Hook (if_target on Weak) ---------------------------------------------

func test_heel_hook_payoff_fires_on_a_weak_target() -> void:
	var scene := _PileScene.new()
	var tgt := _actor()
	tgt.add_status(&"weak", 1)
	var card: CardData = Data.get_card(&"heel_hook")
	EffectSystem.apply(card.effects[1],
		{"source": _actor(), "target": tgt, "scene": scene})
	EffectSystem.apply(card.effects[2],
		{"source": _actor(), "target": tgt, "scene": scene})
	assert_eq(scene.energy_gained, 1, "Weak target -> +1 Energy")
	assert_eq(scene.cards_drawn, 1, "Weak target -> Draw 1")

func test_heel_hook_payoff_skips_a_clean_target() -> void:
	var scene := _PileScene.new()
	var card: CardData = Data.get_card(&"heel_hook")
	EffectSystem.apply(card.effects[1],
		{"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(scene.energy_gained, 0, "no Weak -> no payoff")

func test_heel_hook_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"heel_hook")
	assert_not_null(card, "heel_hook.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(int(card.effects[0].get("value", 0)), 5)
	var gate: Dictionary = card.effects[1]
	assert_eq(String(gate.get("type", "")), "if_target_status")
	assert_eq(String(gate.get("status", "")), "weak")
	assert_eq(String(gate.get("target", "")), "enemy")
	assert_eq(String(gate.get("effect", {}).get("type", "")), "gain_energy")
	assert_eq(String(card.effects[2].get("effect", {}).get("type", "")), "draw")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 8)
	assert_eq(String(card.attack_shape), "poke")
	assert_eq(String(card.attack_params.get("size", "")), "small")

# --- Hemokinesis (lose_hp + Blood element) --------------------------------------

func test_hemokinesis_hp_cost_lands_and_counts_one_loss() -> void:
	var hp_before: int = GameState.hp
	var losses_before: int = GameState.incremental_hp_losses
	var scene := _PileScene.new()
	GameState.set_combat_context(scene, null)
	EffectSystem.apply(Data.get_card(&"hemokinesis").effects[0],
		{"source": _actor(), "target": _actor(), "scene": scene})
	assert_eq(GameState.hp, hp_before - 2, "Lose 2 Health")
	assert_eq(GameState.incremental_hp_losses, losses_before + 1,
		"the self-damage is one hp_losses instance (Blood for Blood synergy)")
	GameState.clear_combat_context()
	GameState.set_hp(hp_before)
	GameState.incremental_hp_losses = losses_before

func test_hemokinesis_tres_round_trips() -> void:
	var card: CardData = Data.get_card(&"hemokinesis")
	assert_not_null(card, "hemokinesis.tres should load")
	assert_eq(card.cost, 1)
	assert_eq(String(card.element), "blood")
	assert_eq(String(card.effects[0].get("type", "")), "lose_hp")
	assert_eq(int(card.effects[0].get("value", 0)), 2)
	var dmg: Dictionary = card.effects[1]
	assert_eq(int(dmg.get("value", 0)), 15)
	assert_eq(String(dmg.get("damage_type", "")), "ranged")
	assert_eq(String(dmg.get("element", "")), "blood",
		"the element is stamped onto the dmg effect for the on-hit Bleed")
	# Upgrade bumps the damage, not the HP cost.
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 2)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 20)
	assert_eq(String(card.attack_shape), "projectile")
	assert_eq(String(card.attack_params.get("size", "")), "medium")

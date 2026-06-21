extends GutTest

# Covers the mechanics added for Bloodletting / Body Slam / Bouncing Flask /
# Burning Pact, plus the shared engine pieces they ride on:
#   - dmg value_from "block"        (Body Slam — damage equal to your Block)
#   - status hits + indiscriminate  (Bouncing Flask — N poison to random foes)
#   - exhaust verb parse + draw      (Burning Pact)
#   - lose_hp + gain_energy          (Bloodletting)
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Records the damage handed to deal_damage so block-scaling can be asserted
# without a live combat scene.
class _DmgScene:
	extends RefCounted
	var enemies: Array = []
	var last_amount: int = -1
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		last_amount = amount

# Captures every status application + serves random enemies, so indiscriminate
# multi-hit inflicts can be counted and confirmed to spread across foes.
class _StatusScene:
	extends RefCounted
	var enemies: Array = []
	var applied: Array = []         # [{target, status, stacks}]
	var _i: int = 0
	func pick_random_enemy(_source):
		if enemies.is_empty():
			return null
		# Round-robin so the test can prove each hit can land on a different foe.
		var e = enemies[_i % enemies.size()]
		_i += 1
		return e
	func apply_status(target, status: StringName, stacks: int, _source = null) -> void:
		applied.append({"target": target, "status": status, "stacks": stacks})

# --- Body Slam: dmg value_from block -------------------------------------

func test_body_slam_deals_damage_equal_to_source_block() -> void:
	var scene := _DmgScene.new()
	var src := CombatActor.new()
	src.block = 8
	var enemy := CombatActor.new()
	var eff := {"type": "dmg", "value": 0, "value_from": "block", "damage_type": "melee"}
	EffectSystem.apply(eff, {"source": src, "target": enemy, "scene": scene})
	assert_eq(scene.last_amount, 8, "Body Slam should deal damage equal to the attacker's Block")

func test_body_slam_zero_block_deals_zero() -> void:
	var scene := _DmgScene.new()
	var src := CombatActor.new()
	src.block = 0
	EffectSystem.apply({"type": "dmg", "value": 0, "value_from": "block"},
		{"source": src, "target": CombatActor.new(), "scene": scene})
	assert_eq(scene.last_amount, 0, "no Block -> no damage")

func test_body_slam_tres_loads_with_block_scaling() -> void:
	var card: CardData = Data.get_card(&"body_slam")
	assert_not_null(card, "body_slam.tres should load")
	assert_eq(card.type, CardData.CardType.ATTACK)
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("value_from", "")), "block")
	assert_eq(String(eff.get("damage_type", "")), "melee")

# --- Bouncing Flask: indiscriminate multi-hit inflict --------------------

func test_indiscriminate_inflict_applies_once_per_hit() -> void:
	var scene := _StatusScene.new()
	var a := CombatActor.new()
	var b := CombatActor.new()
	scene.enemies = [a, b]
	var eff := {"type": "status", "status": "poison", "stacks": 3,
		"target": "enemy", "indiscriminate": true, "hits": 3}
	EffectSystem.apply(eff, {"source": CombatActor.new(), "target": a, "scene": scene})
	assert_eq(scene.applied.size(), 3, "3 applications (Inflict 3 Poison, repeat 2 times)")
	for rec in scene.applied:
		assert_eq(rec.status, &"poison")
		assert_eq(rec.stacks, 3)

func test_plain_inflict_still_applies_once() -> void:
	var scene := _StatusScene.new()
	var enemy := CombatActor.new()
	scene.enemies = [enemy]
	EffectSystem.apply({"type": "status", "status": "vulnerable", "stacks": 2, "target": "enemy"},
		{"source": CombatActor.new(), "target": enemy, "scene": scene})
	assert_eq(scene.applied.size(), 1, "a normal inflict is single-application")
	assert_eq(scene.applied[0].target, enemy, "and lands on the picked target")

func test_bouncing_flask_card_skips_the_target_picker() -> void:
	var card: CardData = Data.get_card(&"bouncing_flask")
	assert_not_null(card, "bouncing_flask.tres should load")
	var inst: CardInstance = CardInstance.from_data(card)
	assert_false(inst.wants_target(),
		"an indiscriminate card auto-rolls its targets, so no manual pick is needed")

func test_bouncing_flask_tres_repeats_more_when_upgraded() -> void:
	var card: CardData = Data.get_card(&"bouncing_flask")
	assert_eq(int(card.effects[0].get("hits", 0)), 3, "base = 3 applications")
	assert_eq(int(card.upgraded_effects[0].get("hits", 0)), 4, "upgraded = 4 applications")

func test_bouncing_flask_uses_keyword_and_bounce_shape() -> void:
	var card: CardData = Data.get_card(&"bouncing_flask")
	assert_true(card.addons.has(&"indiscriminate"),
		"random targeting comes from the Indiscriminate keyword, not an inline token")
	assert_false(card.effects[0].has("indiscriminate"),
		"the inline indiscriminate token is gone — the keyword stamps it at play time")
	assert_eq(String(card.attack_shape), "bounce", "action delivery is the bounce archetype")
	assert_eq(String(card.element), "poison", "carries the Poison element")

# --- Elements registry ---------------------------------------------------

func test_element_colors_match_the_sheet() -> void:
	assert_true(Elements.has_color("poison"))
	assert_true(Elements.has_color("Fire"), "lookup is case-insensitive")
	assert_false(Elements.has_color(""), "no element -> no colour")
	assert_false(Elements.has_color("physical"), "physical is colourless")
	# Light Green poison vs orange fire — distinct hues.
	assert_true(Elements.color("poison").g > Elements.color("poison").r,
		"poison is greenish")

func test_fire_element_inflicts_one_burn_only_when_target_has_none() -> void:
	var enemy := CombatActor.new()
	var oh: Dictionary = Elements.on_hit_status("fire", enemy, null)
	assert_eq(StringName(oh.get("status", &"")), &"burn")
	assert_eq(int(oh.get("stacks", 0)), 1)
	# Already burning -> the element adds nothing (per the sheet's condition).
	enemy.add_status(&"burn", 2)
	assert_true(Elements.on_hit_status("fire", enemy, null).is_empty())

func test_poison_element_skips_a_card_that_already_poisons() -> void:
	var enemy := CombatActor.new()
	# A card whose own effects already inflict Poison gets no bonus stack.
	var poisoner := CardData.new()
	poisoner.effects = [{"type": "status", "status": "poison", "stacks": 3, "target": "enemy"}]
	assert_true(Elements.on_hit_status("poison", enemy, poisoner).is_empty(),
		"Bouncing Flask already poisons, so the Poison element doesn't double up")
	# A pure damage card with the Poison element DOES apply 1 Poison on hit.
	var dmg_only := CardData.new()
	dmg_only.effects = [{"type": "dmg", "value": 5, "target": "enemy"}]
	var oh: Dictionary = Elements.on_hit_status("poison", enemy, dmg_only)
	assert_eq(StringName(oh.get("status", &"")), &"poison")

func test_no_element_or_earth_has_no_on_hit() -> void:
	var enemy := CombatActor.new()
	assert_true(Elements.on_hit_status("", enemy, null).is_empty())
	assert_true(Elements.on_hit_status("earth", enemy, null).is_empty(),
		"Earth's Effect on Attack is N/A")

func test_blood_magic_wires_its_element() -> void:
	var card: CardData = Data.get_card(&"blood_magic")
	assert_eq(String(card.element), "blood", "Blood Magic carries the Blood element")
	assert_eq(String(card.effects[0].get("element", "")), "blood",
		"the element is stamped on the dmg effect for the on-hit path")

# --- Burning Pact / Bloodletting: parse round-trip -----------------------

func test_burning_pact_parses_exhaust_then_draw() -> void:
	var card: CardData = Data.get_card(&"burning_pact")
	assert_not_null(card, "burning_pact.tres should load")
	assert_eq(String(card.effects[0].get("type", "")), "exhaust",
		"first effect exhausts a chosen card (not a raw passthrough)")
	assert_eq(int(card.effects[0].get("value", 0)), 1)
	assert_eq(String(card.effects[1].get("type", "")), "draw")
	assert_eq(int(card.effects[1].get("value", 0)), 2)
	assert_true(card.exhaust, "Burning Pact itself Exhausts (the Keyword)")
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 3, "upgraded draws 3")

func test_bloodletting_parses_lose_hp_and_energy() -> void:
	var card: CardData = Data.get_card(&"bloodletting")
	assert_not_null(card, "bloodletting.tres should load")
	assert_eq(String(card.effects[0].get("type", "")), "lose_hp")
	assert_eq(int(card.effects[0].get("value", 0)), 3)
	assert_eq(String(card.effects[1].get("type", "")), "gain_energy")
	assert_eq(int(card.effects[1].get("value", 0)), 2)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 3, "upgraded gains 3 energy")

# --- Claw / Beam / Slimed: new cardsnew rows -> generated .tres -----------

func test_claw_parses_dmg_and_self_boost() -> void:
	var card: CardData = Data.get_card(&"claw")
	assert_not_null(card, "claw.tres should load")
	assert_eq(String(card.effects[0].get("type", "")), "dmg")
	assert_eq(int(card.effects[0].get("value", 0)), 3)
	# boost_cards matching all Claws by id, +2 dmg this combat (+3 upgraded).
	assert_eq(String(card.effects[1].get("type", "")), "boost_cards")
	assert_eq(String(card.effects[1].get("match_id", "")), "claw")
	assert_eq(int(card.effects[1].get("value", 0)), 2)
	assert_eq(int(card.upgraded_effects[1].get("value", 0)), 3, "upgraded boosts by 3")

func test_sweeping_beam_is_cleave_draw_with_sweep_shape() -> void:
	var card: CardData = Data.get_card(&"sweeping_beam")
	assert_not_null(card, "sweeping_beam.tres should load")
	assert_eq(card.display_name, "Sweeping Beam", "name unchanged")
	# Cleave -> all_enemies, ranged, plus a card draw.
	assert_eq(String(card.effects[0].get("type", "")), "dmg")
	assert_eq(int(card.effects[0].get("value", 0)), 6)
	assert_eq(String(card.effects[0].get("target", "")), "all_enemies")
	assert_eq(String(card.effects[0].get("damage_type", "")), "ranged")
	assert_eq(String(card.effects[1].get("type", "")), "draw")
	assert_eq(int(card.effects[1].get("value", 0)), 1)
	assert_eq(String(card.attack_shape), "sweep_beam", "uses the sweeping-beam archetype")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 9, "upgraded deals 9")

func test_slimed_draws_one_and_exhausts() -> void:
	var card: CardData = Data.get_card(&"slimed")
	assert_not_null(card, "slimed.tres should load")
	assert_eq(String(card.effects[0].get("type", "")), "draw")
	assert_eq(int(card.effects[0].get("value", 0)), 1, "Slimed draws 1 (StS2)")
	assert_true(card.exhaust, "Slimed still Exhausts when played")

func test_sweep_beam_resolves_in_both_attack_libraries() -> void:
	# Action: a full-reach beam family carrying a sweep arc.
	var a: Dictionary = Data.action_attacks.resolve(Data.get_card(&"sweeping_beam"))
	assert_eq(String(a.get("family", "")), "sweep_beam")
	assert_gt(float(a.get("reach_px", 0.0)), 0.0, "sweep beam has reach")
	assert_gt(float(a.get("arc_deg", 0.0)), 0.0, "sweep beam pans across an arc")
	# Strategy: a wide (spread) full-range line, reading as a large sweep.
	var s: Dictionary = Data.strategy_attacks.resolve(&"sweep_beam", {})
	assert_eq(String(s.get("family", "")), "line")
	assert_true(bool(s.get("spread", false)), "strategy sweep beam fans wide")
	assert_gt(int(s.get("range_tiles", 0)), 5, "covers beam-level range")

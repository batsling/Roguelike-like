extends GutTest

# Covers the Barricade / Envenom / Evolve / Feel No Pain / Fire Breathing /
# Well-Laid Plans Power batch, authored as parsable DSL:
#   - sheet -> generator round-trip: on_<event>:<inner> trigger effects,
#     the keep_block structural verb, the retain inner verb
#   - the generic power runtime: scene power_triggers with target fan-out,
#     Stats.keeps_block / retain_total, the played-powers badge registry
#   - playing a Power is not an exhaust (and Exhaust-keyword cards still are)
# Integration runs on the real deckbuilder scene.

const POWER_IDS := [
	&"barricade", &"envenom", &"evolve",
	&"feel_no_pain", &"fire_breathing", &"well_laid_plans",
]

# --- .tres round-trip -------------------------------------------------------

func test_all_six_powers_load_as_power_cards() -> void:
	for id in POWER_IDS:
		var card: CardData = Data.get_card(id)
		assert_not_null(card, "%s.tres should load" % id)
		assert_eq(card.type, CardData.CardType.POWER, "%s is a Power" % id)

func test_barricade_is_keep_block_and_upgrade_drops_cost() -> void:
	var card: CardData = Data.get_card(&"barricade")
	assert_eq(card.effects, [{"type": "keep_block"}])
	assert_eq(card.cost, 3)
	assert_eq(card.upgraded_cost, 2)

func test_envenom_is_an_unblocked_attack_trigger() -> void:
	var eff: Dictionary = Data.get_card(&"envenom").effects[0]
	assert_eq(String(eff.get("type", "")), "trigger")
	assert_eq(String(eff.get("on", "")), "unblocked_attack")
	var inner: Dictionary = eff.get("effect", {})
	assert_eq(String(inner.get("status", "")), "poison")
	assert_eq(int(inner.get("stacks", 0)), 1)
	assert_eq(String(inner.get("target", "")), "enemy")

func test_evolve_is_a_status_drawn_draw_trigger() -> void:
	var card: CardData = Data.get_card(&"evolve")
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("on", "")), "status_drawn")
	assert_eq(int(eff.get("effect", {}).get("value", 0)), 1)
	assert_eq(int(card.upgraded_effects[0].get("effect", {}).get("value", 0)), 2)

func test_feel_no_pain_is_a_card_exhausted_block_trigger() -> void:
	var card: CardData = Data.get_card(&"feel_no_pain")
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("on", "")), "card_exhausted")
	var inner: Dictionary = eff.get("effect", {})
	assert_eq(String(inner.get("type", "")), "block")
	assert_eq(int(inner.get("value", 0)), 3)
	assert_eq(int(card.upgraded_effects[0].get("effect", {}).get("value", 0)), 4)

func test_fire_breathing_is_a_status_or_curse_drawn_aoe_trigger() -> void:
	var card: CardData = Data.get_card(&"fire_breathing")
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("on", "")), "status_or_curse_drawn")
	var inner: Dictionary = eff.get("effect", {})
	assert_eq(String(inner.get("type", "")), "dmg")
	assert_eq(int(inner.get("value", 0)), 6)
	assert_eq(String(inner.get("damage_type", "")), "magic")
	assert_eq(String(inner.get("target", "")), "all_enemies")
	assert_eq(int(card.upgraded_effects[0].get("effect", {}).get("value", 0)), 10)

func test_well_laid_plans_is_a_turn_ended_retain_trigger() -> void:
	var card: CardData = Data.get_card(&"well_laid_plans")
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("on", "")), "turn_ended")
	assert_eq(String(eff.get("effect", {}).get("type", "")), "retain")
	assert_eq(int(eff.get("effect", {}).get("value", 0)), 1)
	assert_eq(int(card.upgraded_effects[0].get("effect", {}).get("value", 0)), 2)

func test_descriptions_are_mechanical_not_gain_wording() -> void:
	# The whole point of the rewrite: no more "Gain Barricade." card text.
	for id in POWER_IDS:
		var card: CardData = Data.get_card(id)
		assert_false(card.description.begins_with("Gain %s" % card.display_name),
			"%s description should say what it does" % id)

# --- Shared helpers ---------------------------------------------------------

func test_retain_total_sums_retain_triggers_only() -> void:
	assert_eq(Stats.retain_total([]), 0)
	var triggers: Array = [
		{"on": "turn_ended", "effect": {"type": "retain", "value": 1}},
		{"on": "turn_ended", "effect": {"type": "retain", "value": 2}},
		{"on": "turn_ended", "effect": {"type": "block", "value": 5}},
		{"on": "card_played", "effect": {"type": "retain", "value": 9}},
	]
	assert_eq(Stats.retain_total(triggers), 3, "two WLP copies stack; non-retain ignored")

func test_keeps_block_reads_the_flag() -> void:
	var a := CombatActor.new()
	assert_false(Stats.keeps_block(null))
	assert_false(Stats.keeps_block(a))
	a.keep_block = true
	assert_true(Stats.keeps_block(a))

func test_power_registry_badge_icon_and_tooltip() -> void:
	var a := CombatActor.new()
	var card: CardData = Data.get_card(&"barricade")
	Stats.register_power(a, card)
	Stats.register_power(a, card)
	assert_eq(int(a.powers[&"barricade"].count), 2, "same power counts up")
	var tex: Texture2D = Stats.power_badge_icon(card)
	assert_not_null(tex)
	assert_string_contains(tex.resource_path, "powericons",
		"badge art lives in images/powericons/")
	var tip: String = Stats.power_tooltip(card, 2)
	assert_string_contains(tip, "Block is not removed",
		"tooltip is the card's own description")

# --- Integration on the real deckbuilder scene ------------------------------

var db

func _deck_scene(spawn: Array = [&"jaw_worm"]):
	GameState.reset_run()
	db = load("res://scenes/deckbuilder/DeckbuilderCombat.tscn").instantiate()
	db.dev_combat = true
	db.enemies_to_spawn = spawn
	add_child_autofree(db)
	for e in db.enemies:
		e.max_hp = 500
		e.hp = 500
	return db

func _db_play(id: StringName, target = null) -> CardInstance:
	var card := CardInstance.from_data(Data.get_card(id))
	db.hand.append(card)
	db.energy = 10
	db._resolve_card(card, target)
	return card

func test_playing_a_power_registers_and_does_not_exhaust() -> void:
	_deck_scene()
	var p: CombatActor = db.player
	# A Feel No Pain trigger is armed — if the Power play counted as an
	# exhaust it would bank Block.
	db.register_trigger("card_exhausted", {"type": "block", "value": 3, "target": "self"})
	var block0: int = p.block
	var power := _db_play(&"barricade")
	assert_eq(db.exhaust_pile.size(), 0, "the Power entered no pile")
	assert_false(db.hand.has(power), "it left the hand — used up")
	assert_true(p.keep_block, "keep_block landed on the player")
	assert_true(Stats.keeps_block(p))
	assert_eq(int(p.powers[&"barricade"].count), 1, "badge registry recorded the play")
	assert_eq(p.block, block0, "Feel No Pain did NOT fire on the Power play")

func test_exhaust_keyword_still_exhausts_and_feeds_feel_no_pain() -> void:
	_deck_scene()
	var p: CombatActor = db.player
	_db_play(&"feel_no_pain")
	var block0: int = p.block
	_db_play(&"adrenaline")   # explicit Exhaust keyword
	assert_eq(db.exhaust_pile.size(), 1, "Exhaust-keyword cards still exhaust")
	assert_eq(p.block, block0 + 3, "Feel No Pain banked Block off the exhaust")

func test_envenom_poisons_on_unblocked_attack_damage() -> void:
	_deck_scene()
	var p: CombatActor = db.player
	var e: CombatActor = db.enemies[0]
	_db_play(&"envenom")
	assert_eq(db.power_triggers.size(), 1, "trigger armed")
	db.deal_damage(p, e, 10, {"damage_type": "melee"})
	assert_eq(e.get_status(&"poison"), 1, "unblocked hit poisoned the victim")
	# Fully blocked: no poison.
	e.block = 99
	db.deal_damage(p, e, 5, {"damage_type": "melee"})
	assert_eq(e.get_status(&"poison"), 1, "blocked hit applies nothing")

func test_evolve_draws_on_status_card_draw() -> void:
	_deck_scene()
	_db_play(&"evolve")
	# draw_cards pops from the BACK: Slimed (a Status card) first, then the
	# Evolve bonus draw pulls the Strike.
	db.draw_pile.clear()
	db.draw_pile.append(CardInstance.from_data(Data.get_card(&"strike_ironclad")))
	db.draw_pile.append(CardInstance.from_data(Data.get_card(&"slimed")))
	db.hand.clear()
	db.draw_cards(1)
	assert_eq(db.hand.size(), 2, "Status draw chained one bonus draw")

func test_fire_breathing_burns_all_enemies_on_status_draw() -> void:
	_deck_scene()
	var e: CombatActor = db.enemies[0]
	_db_play(&"fire_breathing")
	var hp_before: int = e.hp
	db.draw_pile.clear()
	db.draw_pile.append(CardInstance.from_data(Data.get_card(&"slimed")))
	db.hand.clear()
	db.draw_cards(1)
	assert_eq(e.hp, hp_before - 6, "6 magic damage to the enemy on the Status draw")

func test_well_laid_plans_arms_a_retain_trigger() -> void:
	_deck_scene()
	_db_play(&"well_laid_plans")
	assert_eq(Stats.retain_total(db.power_triggers), 1,
		"end-turn intercept sees 1 card to retain")

func test_retain_this_turn_defaults_off() -> void:
	var inst := CardInstance.from_data(Data.get_card(&"cleave"))
	assert_false(inst.retain_this_turn)

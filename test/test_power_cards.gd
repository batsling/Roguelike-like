extends GutTest

# Covers the Barricade / Envenom / Evolve / Feel No Pain / Fire Breathing /
# Well-Laid Plans Power batch:
#   - sheet -> generator round-trip (.tres shape: Power type, gain:<status>)
#   - power icon lookup (images/powericons/<Img>Power.png via the
#     Stats.status_icon fallback) + hyphen-tolerant status tooltips
#   - the Stats cross-mode hooks the powers ride on (keeps_block,
#     fire_envenom, feel_no_pain_on_exhaust, fire_card_drawn_powers)
#   - Well-Laid Plans' one-turn retain flag on CardInstance

const POWER_IDS := [
	&"barricade", &"envenom", &"evolve",
	&"feel_no_pain", &"fire_breathing", &"well_laid_plans",
]

# Records the scene calls the power hooks route through, mode-agnostically.
class _PowerScene:
	extends RefCounted
	var enemies: Array = []
	var applied: Array = []      # [{target, status, stacks}]
	var blocks: Array = []       # [{target, amount}]
	var draws: int = 0
	var hits: Array = []         # [{target, amount, effect}]
	func apply_status(target, status: StringName, stacks: int, _source = null) -> void:
		applied.append({"target": target, "status": status, "stacks": stacks})
	func gain_block(target, amount: int) -> void:
		blocks.append({"target": target, "amount": amount})
	func draw_cards(n: int) -> void:
		draws += n
	func living_enemies() -> Array:
		return enemies
	func deal_damage(_src, tgt, amount: int, effect) -> void:
		hits.append({"target": tgt, "amount": amount, "effect": effect})

func _actor(status: StringName = &"", stacks: int = 0) -> CombatActor:
	var a := CombatActor.new()
	a.max_hp = 20
	a.hp = 20
	if status != &"" and stacks != 0:
		a.add_status(status, stacks)
	return a

# --- .tres round-trip -------------------------------------------------------

func test_all_six_powers_load_as_power_cards() -> void:
	for id in POWER_IDS:
		var card: CardData = Data.get_card(id)
		assert_not_null(card, "%s.tres should load" % id)
		assert_eq(card.type, CardData.CardType.POWER, "%s is a Power" % id)
		var eff: Dictionary = card.effects[0]
		assert_eq(String(eff.get("type", "")), "status", "%s gains a status" % id)
		assert_eq(String(eff.get("status", "")), String(id),
			"%s's status matches its id" % id)
		assert_eq(String(eff.get("target", "")), "self")

func test_barricade_upgrade_drops_cost() -> void:
	var card: CardData = Data.get_card(&"barricade")
	assert_eq(card.cost, 3)
	assert_eq(card.upgraded_cost, 2)

func test_stack_grants_match_sts_numbers() -> void:
	var expect := {
		&"feel_no_pain": [3, 4],
		&"fire_breathing": [6, 10],
		&"evolve": [1, 2],
		&"well_laid_plans": [1, 2],
	}
	for id in expect:
		var card: CardData = Data.get_card(id)
		assert_eq(int(card.effects[0].get("stacks", 0)), expect[id][0],
			"%s base stacks" % id)
		assert_eq(int(card.upgraded_effects[0].get("stacks", 0)), expect[id][1],
			"%s upgraded stacks" % id)

func test_descriptions_are_mechanical_not_gain_wording() -> void:
	# The whole point of the rewrite: no more "Gain Barricade." card text.
	for id in POWER_IDS:
		var card: CardData = Data.get_card(id)
		assert_false(card.description.begins_with("Gain %s" % card.display_name),
			"%s description should say what it does" % id)

# --- Icons + tooltips -------------------------------------------------------

func test_power_status_icons_resolve_from_powericons_dir() -> void:
	for id in POWER_IDS:
		var tex: Texture2D = Stats.status_icon(id)
		assert_not_null(tex, "%s should have badge art" % id)
		assert_string_contains(tex.resource_path, "powericons",
			"%s art lives in images/powericons/" % id)

func test_status_tooltip_matches_hyphenated_sheet_name() -> void:
	var tip: String = Stats.status_tooltip(&"well_laid_plans", 2)
	assert_string_contains(tip, "Retain", "tooltip should carry the sheet description")

# --- Barricade --------------------------------------------------------------

func test_keeps_block_only_with_barricade() -> void:
	assert_false(Stats.keeps_block(null))
	assert_false(Stats.keeps_block(_actor()))
	assert_true(Stats.keeps_block(_actor(&"barricade", 1)))

# --- Envenom ----------------------------------------------------------------

func test_envenom_poisons_on_unblocked_attack_damage() -> void:
	var scene := _PowerScene.new()
	var src := _actor(&"envenom", 2)
	var tgt := _actor()
	Stats.fire_envenom(src, tgt, 5, "melee", scene)
	assert_eq(scene.applied.size(), 1)
	assert_eq(scene.applied[0].status, &"poison")
	assert_eq(int(scene.applied[0].stacks), 2)

func test_envenom_skips_blocked_and_non_attack_damage() -> void:
	var scene := _PowerScene.new()
	var src := _actor(&"envenom", 2)
	var tgt := _actor()
	Stats.fire_envenom(src, tgt, 0, "melee", scene)   # fully blocked
	Stats.fire_envenom(src, tgt, 5, "magic", scene)   # not an Attack
	assert_eq(scene.applied.size(), 0)

func test_envenom_without_scene_apply_status_still_lands() -> void:
	var src := _actor(&"envenom", 1)
	var tgt := _actor()
	Stats.fire_envenom(src, tgt, 3, "ranged", null)
	assert_eq(tgt.get_status(&"poison"), 1)

# --- Feel No Pain -----------------------------------------------------------

func test_feel_no_pain_gains_block_per_exhaust() -> void:
	var scene := _PowerScene.new()
	var actor := _actor(&"feel_no_pain", 3)
	Stats.feel_no_pain_on_exhaust(actor, scene)
	assert_eq(scene.blocks.size(), 1)
	assert_eq(int(scene.blocks[0].amount), 3)

func test_feel_no_pain_without_stacks_is_inert() -> void:
	var scene := _PowerScene.new()
	Stats.feel_no_pain_on_exhaust(_actor(), scene)
	assert_eq(scene.blocks.size(), 0)

# --- Evolve + Fire Breathing ------------------------------------------------

func _card_of_type(t: int) -> CardInstance:
	var data := CardData.new()
	data.id = &"stub"
	data.display_name = "Stub"
	data.type = t
	return CardInstance.from_data(data)

func test_evolve_draws_on_status_card_only() -> void:
	var scene := _PowerScene.new()
	var actor := _actor(&"evolve", 2)
	Stats.fire_card_drawn_powers(actor, _card_of_type(CardData.CardType.STATUS), scene)
	assert_eq(scene.draws, 2, "Status draw fires Evolve")
	Stats.fire_card_drawn_powers(actor, _card_of_type(CardData.CardType.CURSE), scene)
	assert_eq(scene.draws, 2, "Curse draw does NOT fire Evolve")
	Stats.fire_card_drawn_powers(actor, _card_of_type(CardData.CardType.ATTACK), scene)
	assert_eq(scene.draws, 2, "normal draws are inert")

func test_fire_breathing_hits_all_enemies_on_status_or_curse() -> void:
	var scene := _PowerScene.new()
	scene.enemies = [_actor(), _actor()]
	var actor := _actor(&"fire_breathing", 6)
	Stats.fire_card_drawn_powers(actor, _card_of_type(CardData.CardType.STATUS), scene)
	assert_eq(scene.hits.size(), 2, "one hit per living enemy")
	assert_eq(int(scene.hits[0].amount), 6)
	assert_eq(String(scene.hits[0].effect.get("damage_type", "")), "magic")
	Stats.fire_card_drawn_powers(actor, _card_of_type(CardData.CardType.CURSE), scene)
	assert_eq(scene.hits.size(), 4, "Curse draws breathe fire too")

func test_fire_breathing_ignores_normal_draws() -> void:
	var scene := _PowerScene.new()
	scene.enemies = [_actor()]
	var actor := _actor(&"fire_breathing", 6)
	Stats.fire_card_drawn_powers(actor, _card_of_type(CardData.CardType.SKILL), scene)
	assert_eq(scene.hits.size(), 0)

# --- Well-Laid Plans --------------------------------------------------------

func test_retain_this_turn_defaults_off() -> void:
	var inst := _card_of_type(CardData.CardType.SKILL)
	assert_false(inst.retain_this_turn)

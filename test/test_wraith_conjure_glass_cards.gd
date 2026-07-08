extends GutTest

# Covers the Wraith Form / White Noise / Infernal Blade / Distraction /
# Ghostly Armor / Glass Knife batch and the engine pieces added with it:
#   - Intangible: each instance of damage / HP loss clamps to 1
#     (Stats.resolve_damage pre-block + Stats.intangible_clamp for DoTs),
#     decays on the shared turn clock, has a badge icon.
#   - conjure_random: random mint from the deck-scoped conjure pool
#     (Data.conjure_card_pool reads GameState.deck_reward_tag), free-this-turn
#     hand mints, EffectSystem -> scene.conjure_random_card hand-off.
#   - Negative self-boosts (Glass Knife): stack per play, floor at 0.
# The .tres assertions guard the spreadsheet -> generator round-trip.

# Minimal scene that records the conjure_random hand-off.
class _ConjureScene:
	extends RefCounted
	var calls: Array = []
	func conjure_random_card(card_type: String, destination: String, count: int, free: bool, _src) -> void:
		calls.append({"type": card_type, "dest": destination, "count": count, "free": free})

# --- Intangible: the damage clamp ------------------------------------------

func _actor(hp: int, is_player: bool = false) -> CombatActor:
	var a := CombatActor.new()
	a.is_player = is_player
	a.max_hp = hp
	a.hp = hp
	return a

func test_intangible_clamps_attack_damage_to_1() -> void:
	var src := _actor(50, true)
	var tgt := _actor(50)
	tgt.statuses[&"intangible"] = 2
	var res: Dictionary = Stats.resolve_damage(
		src, tgt, 30, {"damage_type": "melee"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.hp_loss), 1, "a 30-damage swing lands as 1 through Intangible")

func test_intangible_clamp_runs_before_block() -> void:
	var src := _actor(50, true)
	var tgt := _actor(50)
	tgt.statuses[&"intangible"] = 1
	tgt.block = 5
	var res: Dictionary = Stats.resolve_damage(
		src, tgt, 30, {"damage_type": "melee"}, Stats.Mode.DECKBUILDER)
	assert_eq(int(res.blocked), 1, "block soaks the CLAMPED hit (1), not the raw 30")
	assert_eq(int(res.hp_loss), 0, "so a blocked clamped hit costs 0 HP")
	assert_eq(tgt.block, 4, "and only 1 Block")

func test_intangible_applies_after_vulnerable() -> void:
	var src := _actor(50, true)
	var tgt := _actor(50)
	tgt.statuses[&"intangible"] = 1
	tgt.statuses[&"vulnerable"] = 2
	var res: Dictionary = Stats.resolve_damage(
		src, tgt, 20, {"damage_type": "ranged"}, Stats.Mode.ACTION)
	assert_eq(int(res.hp_loss), 1, "Vulnerable's +50% is clamped away — still 1")

func test_intangible_clamp_helper_leaves_small_amounts() -> void:
	var tgt := _actor(50)
	tgt.statuses[&"intangible"] = 1
	assert_eq(Stats.intangible_clamp(tgt, 7), 1, "DoT ticks clamp to 1")
	assert_eq(Stats.intangible_clamp(tgt, 1), 1, "1 stays 1")
	assert_eq(Stats.intangible_clamp(tgt, 0), 0, "0 is never raised")
	tgt.statuses.erase(&"intangible")
	assert_eq(Stats.intangible_clamp(tgt, 7), 7, "no Intangible -> untouched")
	assert_eq(Stats.intangible_clamp(null, 7), 7, "null target -> untouched")

func test_intangible_decays_and_has_icon() -> void:
	assert_true(Stats.DECAY_STATUSES.has(&"intangible"),
		"Intangible steps down 1 per turn in every mode")
	assert_true(Stats.STATUS_ICONS.has(&"intangible"), "intangible needs a badge icon")

# --- Intangible: the StS-style intent preview --------------------------------

# While the player is Intangible, an enemy's attack intent must telegraph the
# CLAMPED number — "1" (or 1xN for multi-hit), matching what the hit will deal.
func test_intent_prediction_clamps_to_1_under_intangible() -> void:
	var scene = load("res://scenes/deckbuilder/DeckbuilderCombat.tscn").instantiate()
	scene.dev_combat = true
	scene.enemies_to_spawn = [&"jaw_worm"]
	add_child_autofree(scene)
	var enemy: CombatActor = scene.enemies[0]
	enemy.statuses[&"power"] = 3
	var move := {"effects": [
		{"type": "dmg", "value": 11, "damage_type": "melee"},
		{"type": "dmg", "value": 11, "damage_type": "melee"},
	]}
	var before: Dictionary = scene._annotate_intent(enemy, move)
	assert_eq(int(before.get("intent_dmg", 0)), 14, "no Intangible: 11 + 3 Power per hit")
	assert_eq(int(before.get("intent_hits", 0)), 2, "two dmg effects = a 2-hit intent")
	scene.player.statuses[&"intangible"] = 2
	var after: Dictionary = scene._annotate_intent(enemy, move)
	assert_eq(int(after.get("intent_dmg", 0)), 1, "Intangible up: the intent reads 1 per hit")
	assert_eq(int(after.get("intent_hits", 0)), 2, "…so the panel shows 1x2")
	# Vulnerable can't push the clamped number back up.
	scene.player.statuses[&"vulnerable"] = 1
	assert_eq(int(scene._predict_intent_damage(enemy, move.effects[0])), 1,
		"Vulnerable folds in before the clamp, so it stays 1")
	# And the prediction recovers once the stacks decay away.
	scene.player.statuses.erase(&"intangible")
	scene.player.statuses.erase(&"vulnerable")
	assert_eq(int(scene._predict_intent_damage(enemy, move.effects[0])), 14,
		"clamp lifts with the status")

# --- Wraith Form .tres round-trip -------------------------------------------

func test_wraith_form_tres_gains_intangible_and_erodes_defense() -> void:
	var card: CardData = Data.get_card(&"wraith_form")
	assert_not_null(card, "wraith_form.tres should load")
	assert_eq(card.type, CardData.CardType.POWER)
	assert_eq(card.rarity, CardData.Rarity.RARE)
	assert_eq(card.cost, 3)
	assert_eq(String(card.effects[0].get("status", "")), "intangible")
	assert_eq(int(card.effects[0].get("stacks", 0)), 2)
	assert_eq(String(card.effects[0].get("target", "")), "self")
	var trig: Dictionary = card.effects[1]
	assert_eq(String(trig.get("type", "")), "trigger")
	assert_eq(String(trig.get("on", "")), "turn_started")
	var inner: Dictionary = trig.get("effect", {})
	assert_eq(String(inner.get("status", "")), "defense")
	assert_eq(int(inner.get("stacks", 0)), -1, "erodes 1 Defense per turn")
	assert_eq(int(card.upgraded_effects[0].get("stacks", 0)), 3, "upgrade banks 3 Intangible")

func test_wraith_form_power_badge_icon_resolves() -> void:
	# Powers badge on the status strip with images/powericons/<Img>Power.png.
	# WraithFormPower.png ships in the repo, so the lookup must land on it —
	# falling back to Unknown.png means the art/name pairing broke.
	var card: CardData = Data.get_card(&"wraith_form")
	var tex: Texture2D = Stats.power_badge_icon(card)
	assert_not_null(tex, "badge icon must load")
	assert_string_contains(tex.resource_path, "WraithFormPower.png",
		"badge is the uploaded art, not the Unknown fallback")

func test_negative_gain_erodes_but_never_goes_below_zero() -> void:
	var player := _actor(50, true)
	player.statuses[&"defense"] = 2
	player.add_status(&"defense", -1)
	assert_eq(player.get_status(&"defense"), 1)
	player.add_status(&"defense", -1)
	player.add_status(&"defense", -1)
	assert_eq(player.get_status(&"defense"), 0, "clamps at 0, never negative")

# --- conjure_random: pool + hand-off ----------------------------------------

func test_conjure_pool_filters_by_type() -> void:
	var prev: StringName = GameState.selected_deck
	GameState.selected_deck = &"Random"
	for kind in ["attack", "skill", "power"]:
		var pool: Array = Data.conjure_card_pool(kind)
		assert_gt(pool.size(), 0, "%s pool must not be empty" % kind)
		for c in pool:
			assert_eq(String(CardData.CardType.keys()[c.type]).to_lower(), kind,
				"%s pool holds only %ss" % [kind, kind])
			assert_ne(c.rarity, CardData.Rarity.STARTER, "starters are never minted")
			assert_false(c.tags.has("weapon"), "weapons are never minted")
	GameState.selected_deck = prev

func test_conjure_pool_respects_the_chosen_deck() -> void:
	var prev: StringName = GameState.selected_deck
	GameState.selected_deck = &"Silent"
	for c in Data.conjure_card_pool("attack"):
		assert_true(c.tags.has("silent") or c.tags.has("hero"),
			"%s leaked into the Silent deck's conjure pool" % c.id)
	GameState.selected_deck = &"Ironclad"
	for c in Data.conjure_card_pool("skill"):
		assert_true(c.tags.has("ironclad") or c.tags.has("hero"),
			"%s leaked into the Ironclad deck's conjure pool" % c.id)
	GameState.selected_deck = prev

func test_conjure_pool_unknown_type_is_empty() -> void:
	assert_eq(Data.conjure_card_pool("dice").size(), 0, "only attack/skill/power are mintable")

func test_conjure_random_effect_hands_off_to_scene() -> void:
	var scene := _ConjureScene.new()
	EffectSystem.apply(
		{"type": "conjure_random", "card_type": "power", "destination": "hand",
			"count": 1, "free": true},
		{"scene": scene, "card": null})
	assert_eq(scene.calls.size(), 1, "conjure_random calls scene.conjure_random_card once")
	assert_eq(String(scene.calls[0].get("type", "")), "power")
	assert_eq(String(scene.calls[0].get("dest", "")), "hand")
	assert_true(bool(scene.calls[0].get("free", false)), "free flag threads through")

# --- The three conjure cards' .tres round-trips ------------------------------

func _assert_conjure_card(id: StringName, card_type: String) -> void:
	var card: CardData = Data.get_card(id)
	assert_not_null(card, "%s.tres should load" % id)
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_eq(card.rarity, CardData.Rarity.UNCOMMON)
	assert_eq(card.cost, 1)
	assert_true(card.exhaust, "%s exhausts" % id)
	assert_true(card.can_upgrade)
	assert_eq(card.get_effective_cost(true), 0, "%s+ costs 0" % id)
	var eff: Dictionary = card.effects[0]
	assert_eq(String(eff.get("type", "")), "conjure_random")
	assert_eq(String(eff.get("card_type", "")), card_type)
	assert_eq(String(eff.get("destination", "")), "hand")
	assert_eq(int(eff.get("count", 0)), 1)
	assert_true(bool(eff.get("free", false)), "the mint costs 0 this turn")

func test_white_noise_mints_a_random_power() -> void:
	_assert_conjure_card(&"white_noise", "power")

func test_infernal_blade_mints_a_random_attack() -> void:
	_assert_conjure_card(&"infernal_blade", "attack")

func test_distraction_mints_a_random_skill() -> void:
	_assert_conjure_card(&"distraction", "skill")

# --- Ghostly Armor .tres round-trip ------------------------------------------

func test_ghostly_armor_is_ethereal_block() -> void:
	var card: CardData = Data.get_card(&"ghostly_armor")
	assert_not_null(card, "ghostly_armor.tres should load")
	assert_eq(card.type, CardData.CardType.SKILL)
	assert_eq(card.rarity, CardData.Rarity.UNCOMMON)
	assert_eq(card.cost, 1)
	assert_true(card.ethereal, "Ethereal lives on the keyword flag")
	assert_false(card.exhaust, "Ethereal exhausts only if UNPLAYED — not on play")
	assert_eq(String(card.effects[0].get("type", "")), "block")
	assert_eq(int(card.effects[0].get("value", 0)), 10)
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 13)

# --- Glass Knife: negative self-boost -----------------------------------------

func test_glass_knife_tres_is_a_medium_projectile_with_self_decay() -> void:
	var card: CardData = Data.get_card(&"glass_knife")
	assert_not_null(card, "glass_knife.tres should load")
	assert_eq(card.type, CardData.CardType.ATTACK)
	assert_eq(card.rarity, CardData.Rarity.RARE)
	assert_eq(card.cost, 1)
	assert_eq(card.attack_shape, &"projectile")
	assert_eq(String(card.attack_params.get("size", "")), "medium")
	var dmg: Dictionary = card.effects[0]
	assert_eq(String(dmg.get("damage_type", "")), "ranged")
	assert_eq(int(dmg.get("value", 0)), 8)
	assert_eq(int(dmg.get("hits", 0)), 2)
	var decay: Dictionary = card.effects[1]
	assert_eq(String(decay.get("type", "")), "boost_cards")
	assert_eq(String(decay.get("match_id", "")), "glass_knife")
	assert_eq(int(decay.get("value", 0)), -2, "each play registers a -2 self-boost")
	assert_eq(int(card.upgraded_effects[0].get("value", 0)), 12, "upgrade: 12x2")

func test_negative_boosts_stack_per_play_and_floor_at_zero() -> void:
	var card: CardData = Data.get_card(&"glass_knife")
	var boosts: Array = []
	# First play: no boost registered yet — full 8.
	var out: Dictionary = Stats.apply_card_boosts({"type": "dmg", "value": 8}, card, boosts)
	assert_eq(int(out.get("value", 0)), 8, "first play is full value")
	# Each play appends the card's own -2 boost.
	boosts.append({"match_id": "glass_knife", "stat": "dmg", "value": -2})
	out = Stats.apply_card_boosts({"type": "dmg", "value": 8}, card, boosts)
	assert_eq(int(out.get("value", 0)), 6, "second play: 8 - 2")
	for _i in range(5):
		boosts.append({"match_id": "glass_knife", "stat": "dmg", "value": -2})
	out = Stats.apply_card_boosts({"type": "dmg", "value": 8}, card, boosts)
	assert_eq(int(out.get("value", 0)), 0, "decayed out: floors at 0, never negative")

func test_negative_boost_only_touches_its_own_id() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	var boosts: Array = [{"match_id": "glass_knife", "stat": "dmg", "value": -2}]
	var out: Dictionary = Stats.apply_card_boosts({"type": "dmg", "value": 6}, shiv, boosts)
	assert_eq(int(out.get("value", 0)), 6, "Glass Knife's decay must not touch a Shiv")

func test_card_boost_total_sums_matching_boosts() -> void:
	var card: CardData = Data.get_card(&"glass_knife")
	var boosts: Array = [
		{"match_id": "glass_knife", "stat": "dmg", "value": -2},
		{"match_id": "glass_knife", "stat": "dmg", "value": -2},
		{"match_id": "shiv", "stat": "dmg", "value": 4},
		{"match_id": "glass_knife", "stat": "block", "value": 3},
	]
	assert_eq(Stats.card_boost_total(card, boosts, "dmg"), -4)
	assert_eq(Stats.card_boost_total(card, boosts, "block"), 3)

func test_scale_text_folds_combat_boosts_into_display() -> void:
	var card: CardData = Data.get_card(&"glass_knife")
	var boosts: Array = [{"match_id": "glass_knife", "stat": "dmg", "value": -2}]
	var shown: String = CardScaling.scale_text(
		"Deal 8x2 Dmg Ranged. Decrease the Dmg of this Card by 2 this combat.",
		null, false, card, null, boosts)
	assert_string_contains(shown, "Deal 6x2 Dmg Ranged",
		"the in-hand number steps down with the registered decay")

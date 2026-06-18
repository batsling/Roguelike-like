extends GutTest

# Covers the cross-mode plumbing that lets boost_cards (Accuracy / Claw) and
# conjure (Blade Dance / Cloak and Dagger) work in action and strategy, not just
# the deckbuilder:
#   - Stats.card_matches_boost / Stats.apply_card_boosts  (shared matcher + fold)
#   - EffectSystem boost_cards -> scene.add_card_boost     (registration)
#   - EffectSystem conjure     -> scene.conjure_card       (delivery hand-off)
# The handlers dispatch into whatever `scene` exposes the method, so a mock
# RefCounted stands in for DeckbuilderCombat / ActionCombat / BattleView.

# Minimal scene that just records the calls EffectSystem makes.
class _BoostScene:
	extends RefCounted
	var boosts: Array = []
	var conjures: Array = []
	func add_card_boost(boost: Dictionary) -> void:
		boosts.append(boost)
	func conjure_card(card_id: StringName, destination: String, count: int, _src, _up: bool = false) -> void:
		conjures.append({"id": String(card_id), "dest": destination, "count": count})

# --- Shared matcher: tag / type / id -------------------------------------

func test_card_matches_boost_by_tag() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	assert_true(Stats.card_matches_boost(shiv, {"match_tag": "shiv"}), "Shiv carries the shiv tag")
	assert_false(Stats.card_matches_boost(shiv, {"match_tag": "ironclad"}), "Shiv lacks the ironclad tag")

func test_card_matches_boost_by_type() -> void:
	var shiv: CardData = Data.get_card(&"shiv")  # type 0 = attack
	assert_true(Stats.card_matches_boost(shiv, {"match_type": "attack"}))
	assert_false(Stats.card_matches_boost(shiv, {"match_type": "skill"}))

func test_card_matches_boost_by_id() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	assert_true(Stats.card_matches_boost(shiv, {"match_id": "shiv"}), "id= matches the card's own id (Claw's matcher)")
	assert_false(Stats.card_matches_boost(shiv, {"match_id": "claw"}))

func test_card_matches_boost_null_card_is_false() -> void:
	assert_false(Stats.card_matches_boost(null, {"match_id": "shiv"}), "no card -> no match (enemy AI moves)")

# --- Fold: only dmg/block, only when matching ----------------------------

func test_apply_card_boosts_folds_matching_dmg() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	var boosts: Array = [{"match_tag": "shiv", "stat": "dmg", "value": 4}]
	var out: Dictionary = Stats.apply_card_boosts({"type": "dmg", "value": 6}, shiv, boosts)
	assert_eq(int(out.get("value", 0)), 10, "Accuracy adds +4 to a matching Shiv's damage")

func test_apply_card_boosts_stacks_multiple() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	var boosts: Array = [
		{"match_id": "shiv", "stat": "dmg", "value": 2},
		{"match_id": "shiv", "stat": "dmg", "value": 2},
	]
	var out: Dictionary = Stats.apply_card_boosts({"type": "dmg", "value": 4}, shiv, boosts)
	assert_eq(int(out.get("value", 0)), 8, "two registered boosts stack (Claw played twice)")

func test_apply_card_boosts_ignores_non_matching() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	var boosts: Array = [{"match_id": "claw", "stat": "dmg", "value": 99}]
	var out: Dictionary = Stats.apply_card_boosts({"type": "dmg", "value": 6}, shiv, boosts)
	assert_eq(int(out.get("value", 0)), 6, "a Claw boost must not touch a Shiv")

func test_apply_card_boosts_ignores_other_effect_types() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	var boosts: Array = [{"match_id": "shiv", "stat": "dmg", "value": 5}]
	var out: Dictionary = Stats.apply_card_boosts({"type": "status", "status": "poison", "stacks": 1}, shiv, boosts)
	assert_false(out.has("value"), "status effects aren't boosted")

func test_apply_card_boosts_respects_stat_kind() -> void:
	var shiv: CardData = Data.get_card(&"shiv")
	# A dmg-stat boost must not bump a block effect, and vice-versa.
	var boosts: Array = [{"match_id": "shiv", "stat": "block", "value": 3}]
	var out: Dictionary = Stats.apply_card_boosts({"type": "dmg", "value": 6}, shiv, boosts)
	assert_eq(int(out.get("value", 0)), 6, "a block boost leaves dmg alone")

# --- EffectSystem dispatch into the scene callbacks ----------------------

func test_boost_cards_effect_registers_via_scene() -> void:
	var scene := _BoostScene.new()
	EffectSystem.apply(
		{"type": "boost_cards", "match_id": "claw", "stat": "dmg", "value": 2},
		{"scene": scene})
	assert_eq(scene.boosts.size(), 1, "boost_cards calls scene.add_card_boost once")
	assert_eq(String(scene.boosts[0].get("match_id", "")), "claw")
	assert_eq(int(scene.boosts[0].get("value", 0)), 2)

func test_conjure_effect_hands_off_to_scene() -> void:
	var scene := _BoostScene.new()
	EffectSystem.apply(
		{"type": "conjure", "card_id": "shiv", "destination": "hand", "count": 3},
		{"scene": scene, "card": null})
	assert_eq(scene.conjures.size(), 1, "conjure calls scene.conjure_card once")
	assert_eq(String(scene.conjures[0].get("id", "")), "shiv")
	assert_eq(String(scene.conjures[0].get("dest", "")), "hand")
	assert_eq(int(scene.conjures[0].get("count", 0)), 3)

# --- Round-trip guards ---------------------------------------------------

func test_accuracy_tres_still_uses_tag_matcher() -> void:
	var acc: CardData = Data.get_card(&"accuracy")
	assert_not_null(acc, "accuracy.tres should load")
	var eff: Dictionary = acc.effects[0]
	assert_eq(String(eff.get("type", "")), "boost_cards")
	assert_eq(String(eff.get("match_tag", "")), "shiv")
	assert_eq(int(eff.get("value", 0)), 4)

func test_blade_dance_tres_conjures_shivs() -> void:
	var bd: CardData = Data.get_card(&"blade_dance")
	assert_not_null(bd, "blade_dance.tres should load")
	var eff: Dictionary = bd.effects[0]
	assert_eq(String(eff.get("type", "")), "conjure")
	assert_eq(String(eff.get("card_id", "")), "shiv")
	assert_eq(String(eff.get("destination", "")), "hand")

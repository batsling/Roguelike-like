extends GutTest

# Validates the curse-synergy items (Death Orb, Du-Vu Doll, Golden Beetle,
# Vitality Orb) and the engine vocabulary they needed: curse / curse-card
# tallies (GameState.curse_count / curse_card_count), dynamic effect amounts
# (value_from / stacks_from), the run-scope curse_* triggers, and "chests"
# (the project's term for an item reward). A curse and a curse CARD are
# DIFFERENT things — these tests pin that distinction down.

func _trigger_for(item: ItemData, on_name: String) -> Dictionary:
	for t in item.triggers:
		if String(t.get("on", "")) == on_name:
			return t
	return {}

# Saddles the run with `n` curses (any catalog curse; count is all that matters).
func _add_curses(n: int) -> void:
	var curse: CurseData = Data.get_curse(&"curse_of_guilt")
	for _i in range(n):
		GameState.add_active_curse(curse)

# --- Curse / curse-card tallies ------------------------------------------

func test_curse_count_tracks_active_curses() -> void:
	GameState.reset_run()
	assert_eq(GameState.curse_count(), 0, "no curses on a fresh run")
	_add_curses(2)
	assert_eq(GameState.curse_count(), 2, "active_curses size is the curse count")

func test_curse_card_count_counts_only_curse_type_cards() -> void:
	GameState.reset_run()
	GameState.deck.clear()
	GameState.deck.append(CardInstance.from_data(Data.get_card(&"strike_ironclad")))   # Attack
	GameState.deck.append(CardInstance.from_data(Data.get_card(&"guilty")))   # Curse
	assert_eq(GameState.curse_card_count(), 1, "only CURSE-type cards count")
	# Curses (active_curses) are a separate quantity from curse cards.
	_add_curses(3)
	assert_eq(GameState.curse_card_count(), 1, "adding curses doesn't change the card count")
	assert_eq(GameState.curse_count(), 3)

# --- Death Orb (card_played power -> Xx2 dmg, X = curse count) ------------

# Captures the base damage handed to deal_damage so the dynamic value can be
# asserted without a real combat scene.
class _CaptureScene:
	extends RefCounted
	var enemies: Array = []
	var last_amount: int = -1
	func deal_damage(_src, _tgt, amount: int, _eff) -> void:
		last_amount = amount

func test_death_orb_loads_with_curse_scaled_power_hit() -> void:
	var it: ItemData = Data.get_item(&"death_orb")
	assert_not_null(it, "death_orb.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.UNCOMMON)
	var trig: Dictionary = _trigger_for(it, "card_played")
	assert_false(trig.is_empty(), "Death Orb fires when a card is played")
	assert_eq(String(trig.get("if_card_type", "")), "power", "only on Powers")
	var eff: Dictionary = trig.get("effects", [{}])[0]
	assert_eq(String(eff.get("type", "")), "dmg")
	assert_eq(String(eff.get("value_from", "")), "curses",
		"scales off curses, NOT curse cards")
	assert_eq(int(eff.get("value_mult", 0)), 2, "Xx2")
	assert_eq(String(eff.get("target", "")), "all_enemies")

func test_death_orb_damage_scales_with_curse_count() -> void:
	GameState.reset_run()
	_add_curses(3)
	var scene := _CaptureScene.new()
	var enemy := CombatActor.new()
	var eff: Dictionary = Data.get_item(&"death_orb").triggers[0]["effects"][0]
	EffectSystem.apply(eff, {"source": null, "target": enemy, "scene": scene})
	assert_eq(scene.last_amount, 6, "3 curses -> 3x2 = 6 damage")
	# No curses -> no damage.
	GameState.reset_run()
	scene.last_amount = -1
	EffectSystem.apply(eff, {"source": null, "target": enemy, "scene": scene})
	assert_eq(scene.last_amount, 0, "0 curses -> 0 damage")

# --- Du-Vu Doll (combat start -> gain X Power, X = curse count) -----------

func test_du_vu_doll_loads_with_curse_scaled_power() -> void:
	var it: ItemData = Data.get_item(&"du_vu_doll")
	assert_not_null(it, "du_vu_doll.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	var trig: Dictionary = _trigger_for(it, "combat_started")
	assert_false(trig.is_empty(), "Du-Vu Doll fires at combat start")
	var eff: Dictionary = trig.get("effects", [{}])[0]
	assert_eq(String(eff.get("type", "")), "status")
	assert_eq(String(eff.get("status", "")), "power")
	assert_eq(String(eff.get("stacks_from", "")), "curses",
		"Power equals the curse count, NOT curse cards")
	assert_eq(String(eff.get("target", "")), "self")

func test_du_vu_doll_grants_power_equal_to_curse_count() -> void:
	GameState.reset_run()
	_add_curses(2)
	var player := CombatActor.from_player()
	var eff: Dictionary = Data.get_item(&"du_vu_doll").triggers[0]["effects"][0]
	EffectSystem.apply(eff, {"source": player, "target": player, "scene": null})
	assert_eq(player.get_status(&"power"), 2, "2 curses -> +2 Power")

# --- Vitality Orb (curse gained -> +8 Max HP) ----------------------------

func test_vitality_orb_loads_with_curse_applied_trigger() -> void:
	var it: ItemData = Data.get_item(&"vitality_orb")
	assert_not_null(it, "vitality_orb.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	var trig: Dictionary = _trigger_for(it, "curse_applied")
	assert_false(trig.is_empty(), "Vitality Orb reacts to gaining a curse")
	var eff: Dictionary = trig.get("effects", [{}])[0]
	assert_eq(String(eff.get("type", "")), "gain_max_hp")
	assert_eq(int(eff.get("value", 0)), 8)

func test_vitality_orb_grants_max_hp_when_a_curse_is_obtained() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"vitality_orb"))
	var before: int = GameState.max_hp
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.max_hp, before + 8, "obtaining a curse grants +8 Max HP")
	# A second curse stacks again.
	GameState.add_active_curse(Data.get_curse(&"curse_of_blindness"))
	assert_eq(GameState.max_hp, before + 16, "each curse grants another +8")

func test_vitality_orb_does_nothing_without_a_curse() -> void:
	GameState.reset_run()
	var before: int = GameState.max_hp
	GameState.add_item(Data.get_item(&"vitality_orb"))
	assert_eq(GameState.max_hp, before, "just owning it grants nothing")

# --- Golden Beetle (remove a curse OR a curse card -> gain a Chest) -------

func test_golden_beetle_loads_with_both_removal_triggers() -> void:
	var it: ItemData = Data.get_item(&"golden_beetle")
	assert_not_null(it, "golden_beetle.tres should load")
	assert_eq(it.kind, ItemData.ItemKind.TRIGGERED)
	assert_eq(it.rarity, ItemData.Rarity.RARE)
	# It counts BOTH curses and curse cards: a trigger for each.
	var rm_curse: Dictionary = _trigger_for(it, "curse_removed")
	var rm_card: Dictionary = _trigger_for(it, "curse_card_removed")
	assert_false(rm_curse.is_empty(), "reacts to a curse being removed")
	assert_false(rm_card.is_empty(), "reacts to a curse card being removed")
	for trig in [rm_curse, rm_card]:
		var eff: Dictionary = trig.get("effects", [{}])[0]
		assert_eq(String(eff.get("type", "")), "gain_chest")
		assert_eq(int(eff.get("value", 0)), 1, "one Chest per removal")

func test_golden_beetle_banks_a_chest_when_a_curse_is_lifted() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"golden_beetle"))
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.pending_chests, 0, "gaining a curse banks no chest")
	GameState.remove_active_curse(&"curse_of_guilt")
	assert_eq(GameState.pending_chests, 1, "lifting a curse banks one chest")
	assert_eq(GameState.curse_count(), 0, "the curse is gone")

func test_golden_beetle_banks_a_chest_when_a_curse_card_is_removed() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"golden_beetle"))
	GameState.deck.clear()
	GameState.deck.append(CardInstance.from_data(Data.get_card(&"guilty")))   # a curse card
	assert_eq(GameState.curse_card_count(), 1)
	GameState.remove_card_at(0)
	assert_eq(GameState.pending_chests, 1, "removing a curse card banks one chest")
	assert_eq(GameState.curse_card_count(), 0)

func test_removing_a_non_curse_card_banks_no_chest() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"golden_beetle"))
	GameState.deck.clear()
	GameState.deck.append(CardInstance.from_data(Data.get_card(&"strike_ironclad")))   # not a curse
	GameState.remove_card_at(0)
	assert_eq(GameState.pending_chests, 0, "only curse cards feed Golden Beetle")

func test_golden_beetle_idle_without_removals() -> void:
	GameState.reset_run()
	GameState.add_item(Data.get_item(&"golden_beetle"))
	_add_curses(2)
	assert_eq(GameState.pending_chests, 0, "gaining curses never banks a chest")

# --- Chests (the item-reward currency) -----------------------------------

func test_grant_and_take_pending_chests() -> void:
	GameState.reset_run()
	assert_eq(GameState.pending_chests, 0)
	GameState.grant_chest(2)
	assert_eq(GameState.pending_chests, 2, "grant_chest banks chests")
	assert_true(GameState.take_pending_chest(), "a banked chest can be taken")
	assert_eq(GameState.pending_chests, 1)
	assert_true(GameState.take_pending_chest())
	assert_false(GameState.take_pending_chest(), "no chests left to take")
	assert_eq(GameState.pending_chests, 0)

func test_gain_chest_effect_supports_dynamic_count() -> void:
	GameState.reset_run()
	_add_curses(2)
	GameState.deck.append(CardInstance.from_data(Data.get_card(&"guilty")))   # 1 curse card
	# "curses_and_cards" = 2 curses + 1 curse card = 3 chests.
	EffectSystem.apply({"type": "gain_chest", "value_from": "curses_and_cards"}, {})
	assert_eq(GameState.pending_chests, 3, "Golden-Beetle-style combined tally")

func test_reset_run_clears_pending_chests() -> void:
	GameState.grant_chest(3)
	GameState.reset_run()
	assert_eq(GameState.pending_chests, 0, "a fresh run banks no chests")

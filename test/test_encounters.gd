extends GutTest

# Covers the overworld encounter data scaffold: every encounter loads from
# data/encounters/*.tres, the Effect column parses into structured ops, and the
# Requirement Effect column parses into AND-combined comparison conditions. The
# overworld encounter node + interaction modal that consume these land later, so
# this suite is intentionally data-only.

const EXPECTED_ENCOUNTERS := [
	"deal_with_the_devil", "p_mart_shopkeeper", "trorc_shopkeeper",
	"teleporter", "divine_teleporter", "challenge_rift", "angel_room",
]

# --- Data load ---------------------------------------------------------------

func test_all_encounters_load() -> void:
	for id in EXPECTED_ENCOUNTERS:
		var e: EncounterData = Data.get_encounter(StringName(id))
		assert_not_null(e, "encounter '%s' should load" % id)
		if e != null:
			assert_eq(String(e.id), id, "%s id round-trips" % id)
			assert_false(e.display_name.is_empty(), "%s has a display name" % id)
			assert_false(e.effects.is_empty(), "%s has at least one effect" % id)

func test_all_encounters_enumerated() -> void:
	assert_eq(Data.all_encounters().size(), EXPECTED_ENCOUNTERS.size(),
		"all_encounters() returns every loaded encounter")

func test_rarity_index_maps_sheet_string() -> void:
	assert_eq(Data.get_encounter(&"p_mart_shopkeeper").rarity_index(), 0, "Common -> 0")
	assert_eq(Data.get_encounter(&"deal_with_the_devil").rarity_index(), 1, "Uncommon -> 1")
	assert_eq(Data.get_encounter(&"angel_room").rarity_index(), 2, "Rare -> 2")

func test_npc_animate_flag() -> void:
	assert_true(Data.get_encounter(&"deal_with_the_devil").is_animate(), "Satan is animate")
	assert_false(Data.get_encounter(&"teleporter").is_animate(), "N/A teleporter is inanimate")

# --- Effect DSL --------------------------------------------------------------

func test_deal_with_the_devil_effects() -> void:
	var e: EncounterData = Data.get_encounter(&"deal_with_the_devil")
	# offer 3 evil items, take any; per taken item lose %HP by rarity + 1 curse.
	var offer: Dictionary = e.effects[0]
	assert_eq(String(offer["op"]), "offer_items")
	assert_eq(String(offer["tag"]), "evil")
	assert_eq(int(offer["count"]), 3)
	assert_eq(String(offer["pick"]), "any")
	var per_hp: Dictionary = e.effects[1]
	assert_eq(String(per_hp["op"]), "per_item")
	assert_eq(String(per_hp["effect"]["op"]), "lose_hp_pct")
	assert_eq((per_hp["effect"]["by_rarity"] as Array).size(), 5, "one HP% per rarity tier")
	var per_curse: Dictionary = e.effects[2]
	assert_eq(String(per_curse["effect"]["op"]), "add_curse")
	assert_eq(int(per_curse["effect"]["count"]), 1)

func test_shop_pools_and_discount() -> void:
	var pmart: Dictionary = Data.get_encounter(&"p_mart_shopkeeper").effects[0]
	assert_eq(String(pmart["op"]), "shop")
	assert_eq((pmart["pools"] as Array), ["food", "pill"])
	assert_eq(int(pmart["discount"]), 0)
	var trorc: Dictionary = Data.get_encounter(&"trorc_shopkeeper").effects[0]
	assert_eq((trorc["pools"] as Array), ["military"])
	assert_eq(int(trorc["discount"]), 20, "Trorc gives a 20% discount")

func test_teleporter_combat_then_teleport() -> void:
	var e: EncounterData = Data.get_encounter(&"teleporter")
	assert_eq(String(e.effects[0]["op"]), "combat")
	assert_eq(String(e.effects[0]["engine"]), "action")
	assert_true(bool(e.effects[0]["elite"]))
	assert_eq(String(e.effects[1]["op"]), "teleport")
	assert_eq(String(e.effects[1]["dir"]), "nearby")

func test_divine_teleporter_offers_a_choice() -> void:
	var tp: Dictionary = Data.get_encounter(&"divine_teleporter").effects[1]
	assert_eq(String(tp["op"]), "teleport")
	assert_eq((tp["choose"] as Array), ["nearby", "previous"], "choose nearby or previous")

func test_challenge_rift_reward_fail_buckets() -> void:
	var e: EncounterData = Data.get_encounter(&"challenge_rift")
	var ch: Dictionary = e.effects[0]
	assert_eq(String(ch["op"]), "challenge")
	assert_eq(String(ch["engine"]), "action")
	assert_eq(String(ch["pool"]), "unconnected")
	assert_eq(int(ch["attempts"]), 3)
	# reward (granted up front) -> 50 gold + chest; fail -> 1 curse.
	var rewards: Array = e.effects.filter(func(x): return String(x.get("op", "")) == "reward")
	var fails: Array = e.effects.filter(func(x): return String(x.get("op", "")) == "fail")
	assert_eq(rewards.size(), 2, "two up-front rewards")
	assert_eq(fails.size(), 1, "one fail penalty")
	assert_eq(String(fails[0]["effect"]["op"]), "add_curse")

# --- Requirement Effect ------------------------------------------------------

func test_unconditional_encounters_have_no_requirement() -> void:
	assert_false(Data.get_encounter(&"teleporter").has_requirement())
	assert_true(Data.get_encounter(&"teleporter").requirement_effect.is_empty())

func test_devil_requires_a_triggered_curse() -> void:
	var conds: Array = Data.get_encounter(&"deal_with_the_devil").requirement_effect
	assert_eq(conds.size(), 1)
	assert_eq(String(conds[0]["field"]), "last_game.curses_triggered")
	assert_eq(String(conds[0]["cmp"]), ">=")
	assert_eq(int(conds[0]["value"]), 1)

func test_angel_room_requires_two_untriggered_curses() -> void:
	var conds: Array = Data.get_encounter(&"angel_room").requirement_effect
	assert_eq(conds.size(), 2, "AND of two conditions")
	assert_eq(String(conds[0]["field"]), "last_game.curses_held")
	assert_eq(int(conds[0]["value"]), 2)
	assert_eq(String(conds[1]["cmp"]), "==")
	assert_eq(int(conds[1]["value"]), 0, "with zero triggered")

# --- Requirement evaluation against run-state -------------------------------

func test_requirement_evaluator_gates_on_last_game_state() -> void:
	var held: int = GameState.last_game_curses_held
	var trig: int = GameState.last_game_curses_triggered
	var devil: Array = Data.get_encounter(&"deal_with_the_devil").requirement_effect
	var angel: Array = Data.get_encounter(&"angel_room").requirement_effect

	# No curse triggered last game -> Devil locked, and (no curses held) Angel locked.
	GameState.last_game_curses_held = 0
	GameState.last_game_curses_triggered = 0
	assert_false(GameState.encounter_requirement_met(devil), "Devil needs a triggered curse")
	assert_false(GameState.encounter_requirement_met(angel), "Angel needs 2 held curses")

	# A curse triggered last game -> Devil opens.
	GameState.last_game_curses_triggered = 1
	assert_true(GameState.encounter_requirement_met(devil), "triggered curse opens the Devil")

	# 2 held, none triggered -> Angel opens; one triggered closes it again.
	GameState.last_game_curses_held = 2
	GameState.last_game_curses_triggered = 0
	assert_true(GameState.encounter_requirement_met(angel), "2 held + 0 triggered opens Angel")
	GameState.last_game_curses_triggered = 1
	assert_false(GameState.encounter_requirement_met(angel), "a trigger closes Angel")

	# Ungated encounters are always available.
	assert_true(GameState.encounter_requirement_met(Data.get_encounter(&"teleporter").requirement_effect))

	GameState.last_game_curses_held = held
	GameState.last_game_curses_triggered = trig

# --- Art ---------------------------------------------------------------------

func test_every_encounter_has_sprite_art() -> void:
	for id in EXPECTED_ENCOUNTERS:
		var e: EncounterData = Data.get_encounter(StringName(id))
		assert_not_null(e.image, "%s should resolve its encounter sprite" % id)

# --- Shop encounters are permanent re-visitable vendors (persisted stock) ---

func _stock_ids(node) -> Array:
	var ids := []
	for it in node.shop_stock:
		ids.append(it.id)
	return ids

func test_shop_keeps_encounter_available_and_persists_stock() -> void:
	GameState.reset_run()
	var enc: EncounterData = Data.get_encounter(&"p_mart_shopkeeper")
	assert_not_null(enc, "p_mart_shopkeeper loads")
	assert_eq(enc.type.to_lower(), "shop", "is a shop")

	var node := EncounterNode.new()
	node.setup(enc, Vector2i.ZERO)
	add_child_autofree(node)

	# First open rolls and caches the stock; the shop asks to stay available.
	var m1 := EncounterModal.new()
	add_child_autofree(m1)
	m1.setup(enc, node)
	assert_true(m1.keep_available, "a shopkeeper is never consumed")
	assert_true(node.shop_rolled, "stock is rolled and cached on the node")
	var first_ids: Array = _stock_ids(node)
	assert_gt(first_ids.size(), 0, "the shop has wares")
	assert_eq(node.shop_sold.size(), first_ids.size(), "a sold flag per ware")

	# Re-opening reuses the SAME stock instead of re-rolling (no free re-roll).
	var m2 := EncounterModal.new()
	add_child_autofree(m2)
	m2.setup(enc, node)
	assert_eq(_stock_ids(node), first_ids, "re-open shows the same wares")

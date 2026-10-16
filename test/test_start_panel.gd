extends GutTest

# THE START PANEL'S DRAW AND THE KIT EACH CARD HANDS OVER.
#
#   - START_WEIGHTING: each start is drawn in proportion to 1 / its reach, so a
#     start is about as common as any other across many runs.
#   - NO REPEATS: none of the previous panel's cards is offered again, unless
#     that would cost the Amulet a genre.
#   - START_GEAR: the genre of the game a run opens on hands over its kit.

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

var _saved_starts: Array = []
var _saved_gear_on: bool = false

# The suite runs with starting gear OFF (test/pre_run_hook.gd); this file is
# about the kit, so it turns it on and puts it back.
func before_each() -> void:
	_saved_starts = GameStats.last_starts.duplicate()
	_saved_gear_on = GameState.start_gear_enabled
	GameState.start_gear_enabled = true
	GameStats.last_starts = []
	RunConfig.reset()
	GameState.reset_run()

func after_each() -> void:
	GameStats.last_starts = _saved_starts
	GameState.start_gear_enabled = _saved_gear_on
	RunConfig.reset()

# --- the shape _strict_starts_for returns, built by hand -----------------------

func _cand(id: StringName) -> Dictionary:
	var g: GameData = Data.get_game(id)
	return {"game": g, "score": 0, "slack": 6}

# genre -> {distance -> {pool: [...]}} with one distance per genre.
func _by_type(games: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for t in games:
		var pool: Array = []
		for id in games[t]:
			pool.append(_cand(id))
		out[t] = {5: {"pool": pool, "path_len": 5}}
	return out

# Four real games per genre, so the hand-built tables name games that exist.
func _games_of(type_val: int, n: int) -> Array:
	var out: Array = []
	for g in Data.all_games():
		if g is GameData and int(g.type) == type_val and RunGraph.degree(g.id) > 0:
			out.append(g.id)
			if out.size() >= n:
				break
	return out

func _ids(by_type: Dictionary, t: int) -> Array:
	var out: Array = []
	for l in by_type[t]:
		for c in by_type[t][l]["pool"]:
			out.append((c["game"] as GameData).id)
	return out

# ==============================================================================
# NO REPEATS
# ==============================================================================

func test_last_runs_games_are_taken_out_of_every_genre() -> void:
	var A := GameData.GameType.ACTION
	var S := GameData.GameType.STRATEGY
	var D := GameData.GameType.DECKBUILDER
	var a: Array = _games_of(A, 2)
	var s: Array = _games_of(S, 2)
	var d: Array = _games_of(D, 2)
	var table: Dictionary = _by_type({A: a, S: s, D: d})
	var kept: Dictionary = RunGraph._without_recent(table,
		{String(a[0]): true, String(s[0]): true, String(d[0]): true})
	assert_eq(kept.size(), 3, "every genre still has a game")
	assert_eq(_ids(kept, A), [a[1]])
	assert_eq(_ids(kept, S), [s[1]])
	assert_eq(_ids(kept, D), [d[1]])

func test_a_genre_emptied_by_the_memory_is_dropped_when_three_others_remain() -> void:
	var A := GameData.GameType.ACTION
	var S := GameData.GameType.STRATEGY
	var D := GameData.GameType.DECKBUILDER
	var T := GameData.GameType.TRADITIONAL
	var t: Array = _games_of(T, 1)
	var table: Dictionary = _by_type({A: _games_of(A, 2), S: _games_of(S, 2),
		D: _games_of(D, 2), T: t})
	var kept: Dictionary = RunGraph._without_recent(table, {String(t[0]): true})
	assert_eq(kept.size(), 3, "three genres and no repeat beats four with one")
	assert_false(kept.has(T), "the genre whose only start was seen last run sits out")

func test_the_memory_gives_way_before_the_amulet_loses_a_genre() -> void:
	var A := GameData.GameType.ACTION
	var S := GameData.GameType.STRATEGY
	var D := GameData.GameType.DECKBUILDER
	var d: Array = _games_of(D, 1)
	var table: Dictionary = _by_type({A: _games_of(A, 2), S: _games_of(S, 2), D: d})
	var kept: Dictionary = RunGraph._without_recent(table, {String(d[0]): true})
	assert_eq(kept.size(), 3, "the Amulet keeps its third genre")
	assert_eq(_ids(kept, D), d, "…by letting last run's game back, and only that genre")

func test_no_panel_repeats_the_one_before_it() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var repeats := 0
	var panels := 0
	for _i in range(12):
		var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
		if pick.is_empty():
			continue
		panels += 1
		var ids: Array = []
		for opt in pick["options"]:
			if GameStats.last_starts.has(String(opt["start_id"])):
				repeats += 1
			ids.append(String(opt["start_id"]))
		GameStats.last_starts = ids
	assert_gt(panels, 0, "the catalogue deals panels")
	# Not a strict zero by rule — the memory gives way rather than lose an Amulet —
	# but measured over 1000 runs it never needed to on the shipping catalogue.
	assert_eq(repeats, 0, "no card is one the previous panel showed")

func test_a_named_seed_ignores_the_memory_so_it_deals_the_same_map() -> void:
	GameStats.last_starts = ["hades", "balatro"]
	RunConfig.seed = 1234
	assert_true(RunGraph._recent_starts().is_empty(),
		"a seed the player named has to deal what it dealt last time")
	RunConfig.seed = 0
	assert_true(RunGraph._recent_starts().has("hades"))

func test_showing_a_panel_records_it_for_the_next_run() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	if ui._start_options.is_empty():
		pending("this catalogue deals no start panel")
		return
	var shown: Array = []
	for opt in ui._start_options:
		shown.append(String((opt["game"] as GameData).id))
	assert_eq(GameStats.last_start_panel(), shown,
		"all three cards are remembered, before any is picked")

# ==============================================================================
# START_WEIGHTING
# ==============================================================================

func test_reach_counts_the_amulets_inside_the_band() -> void:
	var start: StringName = RunGraph.best_connected(1)[0]
	var band: Vector2i = RunConfig.path_band()
	var amulets: Dictionary = {}
	for g in Data.all_games():
		if g is GameData:
			amulets[g.id] = true
	var want := 0
	var d: Dictionary = RunGraph.bfs_distances(start)
	for id in d:
		if int(d[id]) >= band.x and int(d[id]) <= band.y:
			want += 1
	assert_eq(RunGraph.start_reach(start, amulets), want)

func test_a_start_weighs_one_over_its_reach() -> void:
	var start: StringName = RunGraph.best_connected(1)[0]
	var amulets: Dictionary = {}
	for g in Data.all_games():
		if g is GameData:
			amulets[g.id] = true
	var table: Dictionary = {GameData.GameType.ACTION: {5: {"pool": [_cand(start)]}}}
	var w: Dictionary = RunGraph.start_weights(table, amulets)
	assert_almost_eq(float(w[start]), 1.0 / float(RunGraph.start_reach(start, amulets)), 1e-9)

func test_the_weighted_draw_follows_its_weights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var arr: Array = [&"a", &"b"]
	var hits := 0
	for _i in range(400):
		if RunGraph._weighted_index(arr, {&"a": 9.0, &"b": 1.0}, rng, func(e): return e) == 0:
			hits += 1
	assert_between(hits, 320, 400, "a 9:1 weight lands on the heavy side about 90% of the time")
	assert_eq(RunGraph._weighted_index(arr, {&"a": 0.0, &"b": 1.0}, rng, func(e): return e), 1,
		"a weightless entry is never drawn")

# ==============================================================================
# START_GEAR
# ==============================================================================

func test_an_action_start_hands_over_one_weapon() -> void:
	var gear: Array = GameState.roll_start_gear(GameData.GameType.ACTION)
	assert_eq(gear.size(), 1)
	assert_eq(String(gear[0].get("type", "")), "weapon")
	assert_eq(GameState.start_gear_chest(GameData.GameType.ACTION), 0)

func test_a_deckbuilder_start_hands_over_two_cards() -> void:
	var gear: Array = GameState.roll_start_gear(GameData.GameType.DECKBUILDER)
	assert_eq(gear.size(), 2)
	for e in gear:
		assert_eq(String(e.get("type", "")), "card")

func test_a_traditional_start_hands_over_three_unidentified_pieces() -> void:
	var gear: Array = GameState.roll_start_gear(GameData.GameType.TRADITIONAL)
	assert_eq(gear.size(), 3)
	for e in gear:
		assert_false(LootSystem.is_identified(e),
			"%s is something the run does not know yet" % LootSystem.display_name(e))

func test_a_strategy_start_opens_an_item_chest_and_hands_over_no_loot() -> void:
	assert_eq(GameState.roll_start_gear(GameData.GameType.STRATEGY), [])
	assert_eq(GameState.start_gear_chest(GameData.GameType.STRATEGY), 3)

func test_every_genre_has_a_line_for_its_card() -> void:
	for t in RunGraph.TYPE_ORDER:
		assert_ne(GameState.start_gear_text(t), "", "%s says what it gives" % RunGraph.type_label(t))
	assert_eq(GameState.start_gear_text(GameData.GameType.ACTION), "+1 weapon")
	assert_eq(GameState.start_gear_text(GameData.GameType.DECKBUILDER), "+2 cards")

# How many pack pieces a genre's kit hands over.
func _kit_pieces(type_val: int) -> int:
	var g: Dictionary = GameState.START_GEAR.get(type_val, {})
	return int(g.get("count", 0)) if g.has("loot") else 0

func test_picking_a_start_hands_over_its_kit_once() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	if ui._start_options.is_empty():
		pending("this catalogue deals no start panel")
		return
	var want: int = _kit_pieces(int(ui._start_options[0]["type"]))
	var before: int = GameState.loot_items.size()
	ui.choose_start(0)
	assert_true(GameState.start_gear_given)
	assert_eq(GameState.loot_items.size() - before, want, "the kit is in the pack")
	# A second game committed is not a second opening.
	var after: int = GameState.loot_items.size()
	ui._grant_start_gear_once(Data.get_game(GameState.current_game_id))
	assert_eq(GameState.loot_items.size(), after, "the kit is paid once a run")

func test_the_switch_the_suite_uses_pays_no_kit() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	GameState.start_gear_enabled = false
	var before: int = GameState.loot_items.size()
	ui._grant_start_gear_once(_game_of(GameData.GameType.DECKBUILDER))
	assert_eq(GameState.loot_items.size(), before)
	assert_false(GameState.start_gear_given, "…and the run can still be paid later")

func _game_of(type_val: int) -> GameData:
	for g in Data.all_games():
		if g is GameData and int(g.type) == type_val:
			return g
	return null

# Arranged rather than hoped for: the panel's genres are random, so this hands
# the run a Strategy game directly instead of waiting for one to be dealt.
func test_a_strategy_start_queues_its_chest() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui._grant_start_gear_once(_game_of(GameData.GameType.STRATEGY))
	var chests: Array = ui._drop_queue.filter(func(d): return (d as Dictionary).has("items"))
	assert_eq(chests.size(), 1, "one item chest is waiting")
	assert_eq((chests[0]["items"] as Array).size(), 3, "pick 1 of 3")

func test_a_traditional_start_seats_its_three_pieces() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	var before: int = GameState.loot_items.size()
	ui._grant_start_gear_once(_game_of(GameData.GameType.TRADITIONAL))
	assert_eq(GameState.loot_items.size() - before, 3)

func test_each_start_card_says_what_it_gives() -> void:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	if ui._start_picker == null or not is_instance_valid(ui._start_picker):
		pending("no start picker on this run")
		return
	var lines: Array = []
	for n in ui._start_picker.find_children("Gear", "Label", true, false):
		lines.append((n as Label).text)
	assert_eq(lines.size(), ui._start_options.size(), "one kit line per card")
	for i in range(lines.size()):
		assert_eq(lines[i], GameState.start_gear_text(int(ui._start_options[i]["type"])))

func test_the_kit_rides_the_save_and_an_old_save_counts_as_paid() -> void:
	GameState.start_gear_given = true
	var data: Dictionary = SaveSystem._build_payload()
	assert_true(bool(data.get("start_gear_given", false)), "the flag is written")
	data["start_gear_given"] = false
	SaveSystem._apply_save_data(data)
	assert_false(GameState.start_gear_given, "…and read back")
	data.erase("start_gear_given")
	SaveSystem._apply_save_data(data)
	assert_true(GameState.start_gear_given,
		"a save from before starting gear is a run already under way: no kit on load")
	GameState.reset_run()

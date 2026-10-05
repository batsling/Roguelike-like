extends GutTest

# Rifts: generation (step 1) and presentation (step 2) — docs/rifts-design.md.
#
# Every case seeds its own roll rather than hoping a random graph reaches it
# (CLAUDE.md), and puts the graph back to the bare influence map afterwards, so
# nothing here leaks rifts into another test file.

var _rifts_were_on: bool


func before_each() -> void:
	_rifts_were_on = Settings.rifts_enabled
	Settings.rifts_enabled = true
	GameState.set_rifts([])


func after_each() -> void:
	Settings.rifts_enabled = _rifts_were_on
	GameState.set_rifts([])
	# The save tests apply a save with no overworld mounted, which parks it as a
	# pending resume (SaveSystem._apply_save_data). Left there, the next test's
	# overworld would resume this file's run instead of booting its own.
	SaveSystem.cancel_pending_resume()
	# The presentation cases mount an overworld, which starts a run of its own.
	GameState.reset_run()
	GameLoop2.reset()


# A seeded panel with its rifts, or {} when this catalogue cannot deal one.
func _dealt(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
	if pick.is_empty() or (pick.get("rifts", []) as Array).is_empty():
		return {}
	return pick


# --- the one rule (§2) ------------------------------------------------------

# A rift joins two games already exactly two apart, so laying a run's rifts must
# not move a single distance between games that were on the map before.
func test_laying_a_runs_rifts_changes_no_distance() -> void:
	var pick: Dictionary = _dealt(424242)
	if pick.is_empty():
		pending("this catalogue deals no rifts (pool too small or rifts off)")
		return
	var probes: Array = [StringName(pick["amulet_id"])]
	for opt in pick["options"]:
		probes.append(StringName(opt["start_id"]))
	for r in pick["rifts"]:
		probes.append(StringName(r["a"]))
		probes.append(StringName(r["b"]))
	var before: Dictionary = {}
	for p in probes:
		before[p] = RunGraph.bfs_distances(p).duplicate()
	GameState.set_rifts(pick["rifts"])
	var moved := 0
	for p in probes:
		var after: Dictionary = RunGraph.bfs_distances(p)
		for n in before[p]:
			if int(after.get(n, -1)) != int(before[p][n]):
				moved += 1
	assert_eq(moved, 0, "a rift shortened %d distance(s); it must never shorten anything" % moved)


func test_every_rift_joins_two_games_two_apart() -> void:
	var pick: Dictionary = _dealt(13579)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	for r in pick["rifts"]:
		var d: Dictionary = RunGraph.bfs_distances(StringName(r["a"]))
		assert_eq(int(d.get(StringName(r["b"]), -1)), 2,
			"%s's ends %s and %s must be exactly two apart on the bare map" % [
				r["game"], r["a"], r["b"]])


# --- what a run deals (§3) ---------------------------------------------------

func test_a_run_deals_path_rifts_and_world_rifts() -> void:
	var pick: Dictionary = _dealt(2468)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	var paths := 0
	var worlds := 0
	for r in pick["rifts"]:
		if r["kind"] == "path":
			paths += 1
		else:
			worlds += 1
	assert_between(paths, 1, RunGraph.PATH_RIFTS_MAX,
		"a run lays one to three path rifts, one per card's route at most")
	assert_lte(worlds, RunGraph.WORLD_RIFTS, "about ten world rifts at most")
	assert_gt(worlds, 0, "the full map always has weak spots to rift")


# Each card's route clears the floor the panel was held to once the rifts are
# laid — which is the promise the split rule makes (§4).
func test_every_card_clears_its_floor_with_the_rifts_laid() -> void:
	var cards := 0
	for seed_value in [11, 22, 33]:
		var pick: Dictionary = _dealt(seed_value)
		if pick.is_empty():
			continue
		GameState.set_rifts(pick["rifts"])
		var amulet := StringName(pick["amulet_id"])
		for opt in pick["options"]:
			cards += 1
			assert_gte(RunGraph.route_slack(StringName(opt["start_id"]), amulet),
				int(pick["floor"]),
				"%s must clear floor %d with its path rift laid" % [opt["start_id"], pick["floor"]])
		GameState.set_rifts([])
	if cards == 0:
		pending("no rifts were dealt across the sampled seeds")


func test_a_rift_game_is_never_the_amulet_or_a_start() -> void:
	var pick: Dictionary = _dealt(97531)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	var taken: Dictionary = {StringName(pick["amulet_id"]): true}
	for opt in pick["options"]:
		taken[StringName(opt["start_id"])] = true
	for r in pick["rifts"]:
		assert_false(taken.has(StringName(r["game"])),
			"%s is in a rift and on the panel at once" % r["game"])
	GameState.set_rifts(pick["rifts"])
	for r in pick["rifts"]:
		assert_false(RunGraph.is_eligible_start(StringName(r["game"])),
			"a rift game is never eligible to open a run")


# --- laying and lifting ------------------------------------------------------

func test_a_laid_rift_game_leaves_the_off_map_pool_and_comes_back() -> void:
	var pick: Dictionary = _dealt(8642)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	var game := StringName(pick["rifts"][0]["game"])
	assert_true(RunGraph.is_off_map(game), "a rift game starts off the map")
	GameState.set_rifts(pick["rifts"])
	assert_false(RunGraph.is_off_map(game), "laid, it is on the map")
	assert_true(RunGraph.is_rift_game(game))
	assert_false(RunGraph.off_map_ids().has(game), "and out of Transmute's pool")
	assert_eq(RunGraph.neighbors(game).size(), 2, "a rift game has exactly its two ends")
	GameState.set_rifts([])
	assert_true(RunGraph.is_off_map(game), "lifting the rifts puts it back off the map")


func test_rifts_off_deals_none() -> void:
	Settings.rifts_enabled = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 1357
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
	if pick.is_empty():
		pending("the catalogue could not supply a run")
		return
	assert_false(pick.has("rifts"), "with rifts off a run deals none")
	assert_eq(int(pick["floor"]), RunGraph.ROUTE_SLACK_FLOOR,
		"and is held to the ordinary floor")


# Generation measures the bare map whatever the last run left laid.
func test_generation_ignores_rifts_already_laid() -> void:
	var first: Dictionary = _dealt(777)
	if first.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts([])
	var bare: Dictionary = _dealt(778)
	GameState.set_rifts(first["rifts"])
	var over_rifts: Dictionary = _dealt(778)
	assert_eq(over_rifts.get("amulet_id"), bare.get("amulet_id"),
		"the same seed picks the same Amulet with or without old rifts laid")
	assert_eq(RunGraph.rifts().size(), (first["rifts"] as Array).size(),
		"and the rifts that were laid are still laid afterwards")


# --- the run (§10) -----------------------------------------------------------

func test_reset_run_lifts_the_rifts() -> void:
	var pick: Dictionary = _dealt(5555)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts(pick["rifts"])
	assert_false(RunGraph.rifts().is_empty())
	GameState.reset_run()
	assert_true(GameState.rifts.is_empty(), "a new run starts with no rifts")
	assert_true(RunGraph.rifts().is_empty(), "and the graph is the bare map again")


func test_rift_games_are_always_enemies() -> void:
	var pick: Dictionary = _dealt(31415)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts(pick["rifts"])
	var starts: Array = []
	for opt in pick["options"]:
		starts.append(StringName(opt["start_id"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 271828
	var kinds: Dictionary = RunGraph.assign_node_kinds(rng, StringName(pick["amulet_id"]), starts)
	for r in pick["rifts"]:
		assert_eq(int(kinds.get(StringName(r["game"]), -1)), RunGraph.NodeKind.ENEMIES,
			"%s is a rift game and must be Enemies" % r["game"])


# --- the rotation (§3.3) -----------------------------------------------------

func test_last_runs_rift_games_are_saved_for_last() -> void:
	var first: Dictionary = _dealt(1111)
	if first.is_empty():
		pending("this catalogue deals no rifts")
		return
	var held: Array = GameStats.last_rifts.duplicate()
	var last: Dictionary = {}
	var ids: Array = []
	for r in first["rifts"]:
		last[StringName(r["game"])] = true
		ids.append(String(r["game"]))
	GameStats.last_rifts = ids
	var pool: int = RunGraph.rift_pool().size()
	var second: Dictionary = _dealt(2222)
	GameStats.last_rifts = held
	if second.is_empty():
		pending("the second roll dealt no rifts")
		return
	var repeats := 0
	for r in second["rifts"]:
		if last.has(StringName(r["game"])):
			repeats += 1
	if pool >= (first["rifts"] as Array).size() + (second["rifts"] as Array).size():
		assert_eq(repeats, 0, "with games to spare, no rift game repeats from last run")
	else:
		pending("the pool is too small to keep two runs apart")


# --- the save (§10) ----------------------------------------------------------

# A run's rifts ride the save: written as data, read back, and laid on the graph
# again, so a reloaded run walks the same map it was dealt.
func test_a_runs_rifts_survive_a_save_and_reload() -> void:
	var pick: Dictionary = _dealt(60606)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts(pick["rifts"])
	var dealt: Array = GameState.rifts.duplicate(true)
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem._build_payload()))
	GameState.reset_run()
	assert_true(RunGraph.rifts().is_empty(), "the reset lifts them first")
	SaveSystem._apply_save_data(data)
	assert_eq(GameState.rifts, dealt, "the save hands back the same rifts")
	for r in dealt:
		assert_true(RunGraph.is_rift_game(StringName(r["game"])),
			"%s is laid on the graph again" % r["game"])


# A save from before rifts existed has no key, and loads as a run without any.
func test_a_save_from_before_rifts_loads_without_them() -> void:
	var pick: Dictionary = _dealt(70707)
	if not pick.is_empty():
		GameState.set_rifts(pick["rifts"])
	var data: Dictionary = JSON.parse_string(JSON.stringify(SaveSystem._build_payload()))
	data.erase("rifts")
	SaveSystem._apply_save_data(data)
	assert_true(GameState.rifts.is_empty(), "no rifts key, no rifts")
	assert_true(RunGraph.rifts().is_empty(), "and the graph is the bare map")


# A run that lays rifts can always fill a rift on every card's route, after
# Transmute's reserve is kept back — otherwise a card rescued by its path rift
# would be offered on a promise the pool cannot pay (docs/rifts-design.md §10).
func test_rifts_only_run_when_the_pool_can_pay_for_every_path_rift() -> void:
	if not RunGraph.rifts_available():
		assert_lt(RunGraph.usable_rift_count(), RunGraph.PATH_RIFTS_MAX,
			"rifts are off only when the usable pool is short")
		return
	assert_gte(RunGraph.usable_rift_count(), RunGraph.PATH_RIFTS_MAX,
		"rifts are on only when every card's path rift can be filled")
	assert_lte(RunGraph.usable_rift_count(), RunGraph.rift_pool().size(),
		"the reserve only ever takes games away")


# --- verbs on a rift game (§7) ---------------------------------------------

# Transmute on a rift game gives another rift game: a connectionless game of any
# genre, drawn from the rift pool rather than from Transmute's own genre pool.
func test_transmuting_a_rift_game_gives_a_random_rift_game() -> void:
	var pick: Dictionary = _dealt(48484)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts(pick["rifts"])
	var slot := StringName(pick["rifts"][0]["game"])
	var pool: Dictionary = {}
	for id in RunGraph.rift_pool():
		pool[id] = true
	GameState.transmute = 1
	var repl: GameData = GameLoop2.transmute_game(slot, [])
	assert_not_null(repl, "a rift game can always be transmuted while the pool has games")
	if repl == null:
		return
	assert_true(pool.has(repl.id), "%s comes from the rift pool" % repl.id)
	assert_ne(repl.id, slot, "and is a different game")
	assert_eq(GameState.transmute, 0, "the charge was spent")
	assert_true(RunGraph.is_rift_game(slot), "the slot is still a rift")
	GameLoop2.transmuted.erase(slot)


# The path rifts on the cards' optimal routes: one, and a second only when a card
# needs one to reach its floor — never more (§3.1).
func test_path_rifts_are_one_and_two_only_when_needed() -> void:
	var counts := {}
	for seed_value in range(500, 512):
		var pick: Dictionary = _dealt(seed_value)
		if pick.is_empty():
			continue
		var n := 0
		for r in pick["rifts"]:
			if r["kind"] == "path":
				n += 1
		counts[n] = int(counts.get(n, 0)) + 1
		assert_between(n, 1, 2, "a run lays one path rift, two at most")
	if counts.is_empty():
		pending("no rifts were dealt across the sampled seeds")


# --- presentation (§9) -------------------------------------------------------

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

# The overworld, with a dealt run's rifts laid, and the first rift standing.
# Returns the rift record, or {} when this catalogue deals none.
func _overworld_with_a_rift() -> Dictionary:
	var pick: Dictionary = _dealt(424242)
	if pick.is_empty():
		return {}
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	# The overworld deals its own run on the way in; lay the seeded one over it so
	# the case does not ride that roll.
	GameState.set_rifts(pick["rifts"])
	return {"ui": ui, "rift": pick["rifts"][0]}

func _find_shader_rect(node: Node) -> ColorRect:
	for child in node.get_children():
		if child is ColorRect and (child as ColorRect).material is ShaderMaterial:
			return child
		var deeper: ColorRect = _find_shader_rect(child)
		if deeper != null:
			return deeper
	return null

func _all_text(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	for child in node.get_children():
		out += _all_text(child)
	return out

# A rift game's card in the offering carries the swirl behind its cover and says
# RIFT in the flag line; an ordinary game's card carries neither.
func test_a_rift_card_wears_the_swirl_and_the_flag() -> void:
	var got: Dictionary = _overworld_with_a_rift()
	if got.is_empty():
		pending("this catalogue deals no rifts")
		return
	var ui = got["ui"]
	var rift_id := StringName(got["rift"]["game"])
	var plain_id := StringName(got["rift"]["a"])
	var rift_card: Control = ui._offering._make_choice_card(0, {"game": Data.get_game(rift_id),
		"slot": rift_id, "amulet": false, "boss": false})
	autofree(rift_card)
	assert_not_null(_find_shader_rect(rift_card), "the rift card has the swirl behind its cover")
	assert_string_contains(_all_text(rift_card), "RIFT", "and says so in its flag line")
	var plain_card: Control = ui._offering._make_choice_card(1, {"game": Data.get_game(plain_id),
		"slot": plain_id, "amulet": false, "boss": false})
	autofree(plain_card)
	assert_null(_find_shader_rect(plain_card), "an influence game's card has no swirl")
	assert_false(_all_text(plain_card).contains("RIFT"), "and no rift flag")

# Standing on a rift game, a step to either end is not an influence, and the
# popup's proof slot says so instead of showing nothing.
func test_the_proof_slot_on_a_rift_step_says_no_known_influence() -> void:
	var got: Dictionary = _overworld_with_a_rift()
	if got.is_empty():
		pending("this catalogue deals no rifts")
		return
	var ui = got["ui"]
	var r: Dictionary = got["rift"]
	GameState.current_game_id = StringName(r["game"])
	var modal := GameChoiceModal.new()
	modal._choice = {"game": Data.get_game(StringName(r["a"])), "slot": StringName(r["a"]),
		"amulet": false, "boss": false}
	var block: Control = modal._build_source_block()
	autofree(modal)
	assert_not_null(block, "a rift step has a proof slot")
	if block == null:
		return
	autofree(block)
	assert_eq(String(block.name), "RiftBlock", "and it is the rift's")
	assert_string_contains(_all_text(block), "Rift: no known influence")
	assert_null(block.find_child("Proof", true, false), "with no screenshot pretending otherwise")

# The route ladder draws a step through a rift in its own dashed line: the
# segment carries the flag, and only the segments touching the rift game do.
func test_the_ladder_flags_the_steps_through_a_rift() -> void:
	var pick: Dictionary = _dealt(424242)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts(pick["rifts"])
	var r: Dictionary = pick["rifts"][0]
	var a := StringName(r["a"])
	var g := StringName(r["game"])
	var b := StringName(r["b"])
	var canvas = RouteLadder.build({"data": {"layers": [[a], [g], [b]], "edges": [
		{"from": a, "to": g, "from_depth": 0, "to_depth": 1},
		{"from": g, "to": b, "from_depth": 1, "to_depth": 2}]},
		"current": a, "amulet": b})
	autofree(canvas)
	assert_eq(canvas.segments.size(), 2)
	for seg in canvas.segments:
		assert_true(bool(seg[2]), "a step into or out of a rift game is a rift step")

# The OBS overlay is told when the game being played is a rift game.
func test_the_overlay_payload_flags_a_rift_game() -> void:
	var got: Dictionary = _overworld_with_a_rift()
	if got.is_empty():
		pending("this catalogue deals no rifts")
		return
	var r: Dictionary = got["rift"]
	GameState.current_game_id = StringName(r["game"])
	assert_true(bool(ObsCompanion.payload()["now"].get("rift", false)), "a rift game is flagged")
	GameState.current_game_id = StringName(r["a"])
	assert_false(bool(ObsCompanion.payload()["now"].get("rift", true)), "an influence game is not")


# --- rift enemies (§6, §7) ----------------------------------------------------

# A body that walked on at a rift hits RIFT_MULT times as hard, and only it does.
func test_a_rift_body_deals_double_damage() -> void:
	var e: GoalEnemyData = Data.get_goal_enemy_any(&"monkey")
	assert_not_null(e)
	if e == null:
		return
	var plain: Dictionary = {"enemy": e, "statuses": {}}
	var rift: Dictionary = {"enemy": e, "statuses": {}, "rift": true}
	assert_eq(GameLoop2.enemy_damage(rift), GameLoop2.enemy_damage(plain) * GameLoop2.RIFT_MULT)

# Committing a rift game marks the bodies it stands up; an ordinary game does not.
func test_a_rift_games_arrivals_are_rift_bodies() -> void:
	GameLoop2.reset()
	var e: GoalEnemyData = Data.get_goal_enemy_any(&"monkey")
	GameLoop2.choose_game(e, e.game_type, e.tier_index(), true, false, true)
	assert_gt(GameLoop2.arrivals.size(), 0)
	for inst in GameLoop2.arrivals:
		assert_true(GameLoop2.is_rift_body(GameLoop2.entry_for(int(inst))),
			"every body a rift game stands up is a rift body")
	GameLoop2.choose_game(e, e.game_type, e.tier_index(), true, false, false)
	for inst in GameLoop2.arrivals:
		assert_false(GameLoop2.is_rift_body(GameLoop2.entry_for(int(inst))),
			"an ordinary game's bodies are not")
	GameLoop2.reset()

# The doubling rides the body through a save.
func test_a_rift_body_stays_one_through_a_save() -> void:
	var e: GoalEnemyData = Data.get_goal_enemy_any(&"monkey")
	var entry := {"instance": 7, "enemy": e, "health": 1, "max_health": 1, "shield": 0,
		"col": 1, "row": 0, "statuses": {}, "rift": true}
	var raw = JSON.parse_string(JSON.stringify(GameLoop2._serialize_entry(entry)))
	assert_true(GameLoop2.is_rift_body(GameLoop2._deserialize_entry(raw)))
	entry.erase("rift")
	raw = JSON.parse_string(JSON.stringify(GameLoop2._serialize_entry(entry)))
	assert_false(GameLoop2.is_rift_body(GameLoop2._deserialize_entry(raw)),
		"and a body that never saw a rift does not become one")

# A rift body that falls pays RIFT_MULT pieces of loot and RIFT_MULT times its
# chest points.
func test_a_rift_body_pays_double_loot_and_chest_points() -> void:
	GameLoop2.reset()
	var e: GoalEnemyData = Data.get_goal_enemy_any(&"monkey")
	if e == null or e.is_boss() or GameLoop2.effective_health(e) != 1:
		pending("the plain one-hit body is not one hit on this build")
		return
	GameLoop2.choose_game(e, e.game_type, e.tier_index(), false, false, true)
	var inst: int = int(GameLoop2.arrivals[0])
	var seen: Array = []
	var grab := func(_enemy, _cell): seen.append(GameLoop2.defeat_loot)
	GameLoop2.enemy_defeated.connect(grab)
	var before: int = GameLoop2.chest_points
	GameLoop2.fulfill(inst, true)
	GameLoop2.enemy_defeated.disconnect(grab)
	assert_eq(seen, [GameLoop2.RIFT_MULT], "the defeat paid RIFT_MULT pieces")
	assert_eq(GameLoop2.chest_points - before, GameLoop2.chest_points_for(e) * GameLoop2.RIFT_MULT,
		"and RIFT_MULT times its chest points")
	assert_eq(GameLoop2.defeat_loot, 1, "and the count is put back for the next defeat")
	GameLoop2.reset()

# Beating a rift game doubles the win's own chest point.
func test_beating_a_rift_game_doubles_the_wins_point() -> void:
	var pick: Dictionary = _dealt(424242)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts(pick["rifts"])
	GameLoop2.reset()
	GameState.current_game_id = StringName(pick["rifts"][0]["game"])
	assert_eq(int(GameLoop2.claim_chests(true)[0]["points"]), GameLoop2.RIFT_MULT)
	GameState.current_game_id = StringName(pick["rifts"][0]["a"])
	assert_eq(int(GameLoop2.claim_chests(true)[0]["points"]), 1)

# Bash on a rift keeps the rift and swaps the game inside it for another rift game.
func test_bashing_a_rift_swaps_the_game_inside_it() -> void:
	var pick: Dictionary = _dealt(48484)
	if pick.is_empty():
		pending("this catalogue deals no rifts")
		return
	GameState.set_rifts(pick["rifts"])
	var slot := StringName(pick["rifts"][0]["game"])
	GameState.bash = 2
	var first: GameData = GameLoop2.bash_rift(slot)
	assert_not_null(first, "a rift can be bashed while the pool has games")
	if first == null:
		return
	assert_ne(first.id, slot)
	assert_true(RunGraph.is_rift_game(slot), "the rift stays")
	assert_false(GameLoop2.is_bashed(slot), "and its node is not bashed off the map")
	assert_eq(GameLoop2.game_at(slot).id, first.id, "the new game is inside it")
	assert_eq(GameState.bash, 1, "a charge was spent")
	var second: GameData = GameLoop2.bash_rift(slot)
	if second != null:
		assert_ne(second.id, first.id, "a second bash brings another game")
		assert_true(GameLoop2.is_bashed(first.id), "and the one knocked out leaves the pool")
	GameLoop2.transmuted.erase(slot)
	GameLoop2.bashed.clear()
	GameState.bash = 0

# Dash never lists a rift game, and no teleport lands on one.
func test_dash_and_teleport_skip_rift_games() -> void:
	var got: Dictionary = _overworld_with_a_rift()
	if got.is_empty():
		pending("this catalogue deals no rifts")
		return
	var ui = got["ui"]
	var r: Dictionary = got["rift"]
	var rift_id := StringName(r["game"])
	GameState.current_game_id = StringName(r["a"])
	assert_false(ui._reachable(rift_id), "no teleport pool takes a rift game")
	assert_true(ui._reachable(StringName(r["b"])), "while the map game beside it is fine")
	var listed: Array = ui._dash_list([rift_id, StringName(r["b"])])
	assert_false(listed.has(rift_id), "Dash does not list the rift game")

# End to end: picking a rift card off the offering stands rift bodies.
func test_picking_a_rift_card_stands_rift_bodies() -> void:
	var got: Dictionary = _overworld_with_a_rift()
	if got.is_empty():
		pending("this catalogue deals no rifts")
		return
	var ui = got["ui"]
	var r: Dictionary = got["rift"]
	var rift_id := StringName(r["game"])
	ui.choose_start(0)
	if ui._phase == ui.Phase.PLAYING:
		ui.report(true, [])
		ui._end_resolve()
	ui._phase = ui.Phase.SELECT
	GameState.current_game_id = StringName(r["a"])
	ui._build_choices()
	if ui._choices.is_empty():
		pending("the offering came up empty")
		return
	var idx := -1
	for i in ui._choices.size():
		if StringName(ui._choices[i].get("slot", &"")) == rift_id:
			idx = i
	if idx < 0:
		# Not dealt into the first cards: stand it in the first slot, the way a
		# transmute pastes a game onto a spot.
		var c: Dictionary = ui._choices[0].duplicate()
		c["slot"] = rift_id
		c["game"] = Data.get_game(rift_id)
		c["amulet"] = false
		c["boss"] = false
		ui._choices[0] = c
		idx = 0
	# The kinds were dealt for the run's own rifts; this one is seeded, so say it.
	GameState.node_kinds[rift_id] = RunGraph.NodeKind.ENEMIES
	ui.pick(idx)
	assert_gt(GameLoop2.arrivals.size(), 0, "the rift game stood bodies up")
	for inst in GameLoop2.arrivals:
		assert_true(GameLoop2.is_rift_body(GameLoop2.entry_for(int(inst))),
			"and each one is a rift body")


# --- Rift Keys (§8) ------------------------------------------------------------

# The overworld at its offering, standing on a game with fewer connections than
# cards (so there are empty slots), holding `keys` Rift Keys. {} when this
# catalogue has no such game.
func _at_a_quiet_game(keys: int) -> Dictionary:
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	if ui._phase == ui.Phase.PLAYING:
		ui.report(true, [])
		ui._end_resolve()
	ui._phase = ui.Phase.SELECT
	var amulet: StringName = GameState.amulet_game_id
	var ids: Array = RunGraph.bfs_distances(amulet).keys()
	ids.sort()
	for id in ids:
		var gid := StringName(id)
		if gid == amulet or RunGraph.is_rift_game(gid):
			continue
		if RunGraph.neighbors(gid).size() >= ui.offer_count():
			continue
		if RunGraph.rift_key_destinations(gid).is_empty():
			continue
		GameState.current_game_id = gid
		GameState.keys = keys
		ui._build_choices()
		return {"ui": ui, "here": gid}
	return {}

func _key_cards(ui) -> Array:
	return ui._choices.filter(func(c): return c.has("rift_key"))

func test_no_key_no_rift_cards() -> void:
	var got: Dictionary = _at_a_quiet_game(0)
	if got.is_empty():
		pending("no game on this map has an empty slot")
		return
	assert_eq(_key_cards(got["ui"]).size(), 0, "without a key the empty slots stay empty")

# With a key, every empty slot is a rift card: a rift game off the map, leading to
# a game exactly two hops away.
func test_a_key_fills_the_empty_slots_with_rift_cards() -> void:
	var got: Dictionary = _at_a_quiet_game(1)
	if got.is_empty():
		pending("no game on this map has an empty slot")
		return
	var ui = got["ui"]
	var cards: Array = _key_cards(ui)
	var plain: int = ui._choices.size() - cards.size()
	assert_eq(cards.size(), ui.offer_count() - plain, "every empty slot is filled")
	var two_away: Array = RunGraph.rift_key_destinations(got["here"])
	var pool: Array = RunGraph.rift_pool()
	for c in cards:
		assert_true(two_away.has(StringName(c["rift_key"])), "the rift leads two hops away")
		assert_true(pool.has(StringName(c["slot"])), "and holds a connectionless game")
		assert_false(RunGraph.is_rift_game(StringName(c["slot"])), "not laid until it is opened")

# A Scramble deals the rift cards again, game and destination both.
func test_a_scramble_redeals_the_rift_cards() -> void:
	var got: Dictionary = _at_a_quiet_game(1)
	if got.is_empty():
		pending("no game on this map has an empty slot")
		return
	var ui = got["ui"]
	var seen: Dictionary = {}
	for i in range(6):
		for c in _key_cards(ui):
			seen[String(c["slot"])] = true
		GameState.scramble = 1
		ui.scramble()
	assert_gt(seen.size(), 1, "six tables did not all deal the same rift game")

# Picking a rift card spends the key and opens a ONE-WAY rift: the rift game hangs
# off its destination and nothing else, and the run stands in it facing rift bodies.
func test_opening_a_rift_card_spends_a_key_and_lays_a_one_way_rift() -> void:
	var got: Dictionary = _at_a_quiet_game(2)
	if got.is_empty():
		pending("no game on this map has an empty slot")
		return
	var ui = got["ui"]
	var here: StringName = got["here"]
	var idx := -1
	for i in ui._choices.size():
		if ui._choices[i].has("rift_key"):
			idx = i
			break
	assert_gt(idx, -1)
	if idx < 0:
		return
	var gid := StringName(ui._choices[idx]["slot"])
	var dest := StringName(ui._choices[idx]["rift_key"])
	var before: Dictionary = RunGraph.bfs_distances(here).duplicate()
	ui.pick(idx)
	assert_eq(GameState.keys, 1, "one key spent")
	assert_true(RunGraph.is_rift_game(gid), "the rift is open")
	assert_eq(RunGraph.neighbors(gid), [dest], "and leads only to its destination")
	assert_false(RunGraph.neighbors(here).has(gid), "never back to where it was opened")
	assert_eq(GameState.current_game_id, gid, "the run stands in the rift")
	for inst in GameLoop2.arrivals:
		assert_true(GameLoop2.is_rift_body(GameLoop2.entry_for(int(inst))), "facing rift bodies")
	var after: Dictionary = RunGraph.bfs_distances(here)
	var moved := 0
	for n in before:
		if int(after.get(n, -1)) != int(before[n]):
			moved += 1
	assert_eq(moved, 0, "and no distance on the map moved")
	var kinds: Array = GameState.rifts.map(func(r): return String(r["kind"]))
	assert_true(kinds.has(RunGraph.RIFT_KEYED), "the keyed rift is saved with the run's rifts")

# Bash and Transmute on a rift card deal it again with another game.
func test_bash_and_transmute_redeal_a_rift_card() -> void:
	var got: Dictionary = _at_a_quiet_game(1)
	if got.is_empty():
		pending("no game on this map has an empty slot")
		return
	var ui = got["ui"]
	for verb in ["bash", "transmute"]:
		var idx := -1
		for i in ui._choices.size():
			if ui._choices[i].has("rift_key"):
				idx = i
				break
		if idx < 0:
			pending("the pool ran dry")
			return
		var old := StringName(ui._choices[idx]["slot"])
		if verb == "bash":
			GameState.bash = 1
			assert_true(ui.bash_choice(idx))
			assert_true(GameLoop2.is_bashed(old), "a bashed rift game leaves the pool")
			assert_eq(GameState.bash, 0)
		else:
			GameState.transmute = 1
			assert_true(ui.transmute_choice(idx))
			assert_eq(GameState.transmute, 0)
		var now: Array = _key_cards(ui).map(func(c): return StringName(c["slot"]))
		assert_false(now.has(old), "%s dealt %s away" % [verb, old])
		assert_false(RunGraph.is_rift_game(old), "and opened nothing")
	GameLoop2.bashed.clear()

# The key count sits with the other charges under the offering, and a key gained
# while the offering is up deals rift cards into its empty slots at once.
func test_a_key_gained_at_the_offering_shows_and_deals_at_once() -> void:
	var got: Dictionary = _at_a_quiet_game(0)
	if got.is_empty():
		pending("no game on this map has an empty slot")
		return
	var ui = got["ui"]
	ui._refresh()
	assert_eq(_key_cards(ui).size(), 0)
	GameState.keys = 1
	ui._refresh()
	assert_gt(_key_cards(ui).size(), 0, "the key deals rift cards without waiting for a move")
	var chip_text: String = _all_text(ui._select_stats)
	assert_string_contains(chip_text, "Keys 1", "and the count is under the offering")
	GameState.keys = 0
	ui._refresh()
	assert_eq(_key_cards(ui).size(), 0, "and they go when the last key does")
	assert_string_contains(_all_text(ui._select_stats), "Keys 0")

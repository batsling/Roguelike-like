extends GutTest

# Rifts, step 1: generation (docs/rifts-design.md).
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

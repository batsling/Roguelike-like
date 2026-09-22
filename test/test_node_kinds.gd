extends GutTest

# Node kinds (docs/games-first-redesign.md §19) — the storage half.
#
# A kind is what STANDS at a game rather than what the game is, and it is frozen
# at run start, so the two things worth pinning here are the default for a game
# nobody assigned and the save round-trip that keeps an assignment from being
# re-derived against a graph a filter change may have rebuilt.

func after_each() -> void:
	GameState.node_kinds.clear()


func test_the_four_kinds_exist_and_are_distinct() -> void:
	var seen := {}
	for k in [RunGraph.NodeKind.ENEMIES, RunGraph.NodeKind.EVENT,
			RunGraph.NodeKind.CHAMPION, RunGraph.NodeKind.SHOP]:
		seen[int(k)] = true
	assert_eq(seen.size(), 4, "the four kinds must be four distinct values")


func test_the_weights_are_the_specs_sixty_twenty_ten_ten() -> void:
	var w: Dictionary = RunGraph.KIND_WEIGHTS
	assert_eq(int(w[RunGraph.NodeKind.ENEMIES]), 60)
	assert_eq(int(w[RunGraph.NodeKind.EVENT]), 20)
	assert_eq(int(w[RunGraph.NodeKind.CHAMPION]), 10)
	assert_eq(int(w[RunGraph.NodeKind.SHOP]), 10)
	var total := 0
	for k in w.keys():
		total += int(w[k])
	assert_eq(total, 100, "the distribution has to be a distribution")


# The whole reason this is safe to land before anything assigns kinds: an
# unassigned map reads as all-Enemies, which is how the build already behaves.
func test_an_unassigned_game_reads_as_enemies() -> void:
	assert_eq(GameState.node_kind(&"nothing_was_ever_assigned_here"),
		RunGraph.NodeKind.ENEMIES)


func test_a_kind_is_remembered_once_assigned() -> void:
	GameState.node_kinds[&"balatro"] = RunGraph.NodeKind.SHOP
	assert_eq(GameState.node_kind(&"balatro"), RunGraph.NodeKind.SHOP)
	# …and its neighbours are untouched by it.
	assert_eq(GameState.node_kind(&"hades"), RunGraph.NodeKind.ENEMIES)


# The save carries the assignment rather than re-deriving it (§19.2). Round-trip
# through the JSON-safe shape, since that is what a real save does to it.
func test_the_assignment_survives_a_save_round_trip() -> void:
	GameState.node_kinds[&"balatro"] = RunGraph.NodeKind.SHOP
	GameState.node_kinds[&"hades"] = RunGraph.NodeKind.CHAMPION
	GameState.node_kinds[&"ftl"] = RunGraph.NodeKind.EVENT
	var blob: Dictionary = GameState.serialize_node_kinds()

	# A save is JSON, so the keys come back as Strings and the values as numbers.
	var as_json: Dictionary = JSON.parse_string(JSON.stringify(blob))
	assert_not_null(as_json, "the blob has to survive being JSON")

	GameState.node_kinds.clear()
	GameState.restore_node_kinds(as_json)
	assert_eq(GameState.node_kind(&"balatro"), RunGraph.NodeKind.SHOP)
	assert_eq(GameState.node_kind(&"hades"), RunGraph.NodeKind.CHAMPION)
	assert_eq(GameState.node_kind(&"ftl"), RunGraph.NodeKind.EVENT)


# Restoring REPLACES rather than merges: loading a save must not leave a kind
# behind from whatever run was in memory a moment ago.
func test_restoring_clears_what_was_there() -> void:
	GameState.node_kinds[&"stale_game"] = RunGraph.NodeKind.CHAMPION
	GameState.restore_node_kinds({"balatro": RunGraph.NodeKind.SHOP})
	assert_eq(GameState.node_kind(&"stale_game"), RunGraph.NodeKind.ENEMIES,
		"a kind from the previous run must not survive a load")
	assert_eq(GameState.node_kind(&"balatro"), RunGraph.NodeKind.SHOP)


func test_a_new_run_clears_the_map() -> void:
	GameState.node_kinds[&"balatro"] = RunGraph.NodeKind.SHOP
	GameState.reset_run()
	assert_eq(GameState.node_kinds.size(), 0,
		"the map's kinds go with the run that was dealt them")


func test_every_kind_has_a_label() -> void:
	assert_eq(RunGraph.kind_label(RunGraph.NodeKind.ENEMIES), "Enemies")
	assert_eq(RunGraph.kind_label(RunGraph.NodeKind.EVENT), "Event")
	assert_eq(RunGraph.kind_label(RunGraph.NodeKind.CHAMPION), "Champion")
	assert_eq(RunGraph.kind_label(RunGraph.NodeKind.SHOP), "Shop")
	# An unknown value falls back the same way node_kind() does.
	assert_eq(RunGraph.kind_label(99), "Enemies")

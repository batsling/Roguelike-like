extends GutTest

# The route floor (docs/games-first-redesign.md §19.3) — `slack`, and the filter
# that keeps a thin road out of the start panel.
#
# The arithmetic is the part worth pinning: slack is DAG nodes minus hops, and a
# single-file corridor scores 1 rather than 0 because it already carries one more
# node than its own length. Get that offset wrong and every threshold in the
# section moves by one.

# --- start eligibility (§19.3.1) -------------------------------------------

func test_the_connection_floor_is_two() -> void:
	assert_eq(RunGraph.MIN_START_CONNECTIONS, 2)


func test_the_panel_offers_three_cards_over_a_four_to_eight_band() -> void:
	assert_eq(RunGraph.NUM_START_OPTIONS, 3)
	assert_eq(RunGraph.MIN_PATH_LENGTH, 4)
	assert_eq(RunGraph.MAX_PATH_LENGTH, 8)


# The rule with the actual logic in it: three connections qualify outright, two
# qualify only if BOTH lead on, and one never does.
func test_eligibility_reads_the_neighbours_not_just_the_count() -> void:
	var three := 0
	var two_onward := 0
	var two_dead := 0
	var ones := 0
	for g in Data.all_games():
		if not (g is GameData) or not RunGraph.passes_filter(g):
			continue
		if RunGraph.is_off_map(g.id):
			continue
		var nbrs: Array = RunGraph.neighbors(g.id)
		var eligible: bool = RunGraph.is_eligible_start(g.id)
		if nbrs.size() >= 3:
			assert_true(eligible, "%s has %d connections and must qualify" % [
				g.id, nbrs.size()])
			three += 1
		elif nbrs.size() == 2:
			var all_onward := true
			for nb in nbrs:
				if RunGraph.neighbors(nb).size() < 2:
					all_onward = false
			assert_eq(eligible, all_onward,
				"%s has two connections; it qualifies exactly when both lead on" % g.id)
			if all_onward:
				two_onward += 1
			else:
				two_dead += 1
		else:
			assert_false(eligible,
				"%s has %d connections and cannot open a run" % [g.id, nbrs.size()])
			ones += 1
	# The catalogue should actually contain each case, or this test is vacuous.
	assert_gt(three, 0, "no games with three or more connections?")
	assert_gt(two_onward + two_dead, 0, "no degree-2 games to exercise the condition")


func test_no_route_is_told_apart_from_a_thin_one() -> void:
	# An id that is not on the map at all has no route, and that must not read as
	# a very thin one — every real slack is at least 1.
	var slack: int = RunGraph.route_slack(&"not_a_game_at_all", &"also_not_a_game")
	assert_eq(slack, RunGraph.NO_ROUTE,
		"unreachable has to be distinguishable from thin")
	assert_false(RunGraph.route_clears_floor(&"not_a_game_at_all", &"also_not_a_game"))


func test_the_floor_is_the_budget_plus_two() -> void:
	# hops - 1 Enemies, one Event, one Shop, the Amulet = hops + 2, plus two
	# spare nodes. If this changes, §19.3's measured tables move with it.
	assert_eq(RunGraph.ROUTE_SLACK_FLOOR, 5)


# Slack on real routes: never below 1 (a corridor), and consistent with the DAG
# the ladder actually draws.
func test_slack_matches_the_dag_it_is_read_from() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 998877
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
	if pick.is_empty():
		pending("the catalogue could not supply a run")
		return
	var amulet := StringName(pick.get("amulet_id", ""))
	var checked := 0
	for opt in pick.get("options", []):
		var start := StringName(opt.get("start_id", ""))
		var slack: int = RunGraph.route_slack(start, amulet)
		assert_ne(slack, RunGraph.NO_ROUTE,
			"an offered start has to have a route to the amulet")
		assert_true(slack >= 1,
			"a corridor scores 1; %d is below the floor of what a route can be" % slack)
		# The same number, computed the long way off the flattened DAG.
		var nodes: int = RunGraph.dag_node_ids(start, amulet).size()
		var hops: int = int(opt.get("path_len", 0))
		assert_eq(slack, nodes - hops,
			"slack must be the DAG's own node count minus its length")
		checked += 1
	if checked == 0:
		pending("no start options came back to check")


# The filter's whole job: an offered start clears the floor. This used to exempt
# the relaxed out-of-band card, which was the one thing that could sit below it;
# §19.3.2 retired that card, so the claim is now about every card on the panel.
func test_every_start_offered_clears_the_floor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13579
	var offered := 0
	var thin := 0
	# Four rolls, not a dozen: each one is a full amulet search, and this test is
	# asking a property that either holds on the first or does not hold at all.
	for _i in range(4):
		var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
		if pick.is_empty():
			continue
		var amulet := StringName(pick.get("amulet_id", ""))
		for opt in pick.get("options", []):
			assert_true(bool(opt.get("in_window", false)),
				"every card is in window now; %s is not" % opt.get("start_id", ""))
			offered += 1
			if not RunGraph.route_clears_floor(StringName(opt.get("start_id", "")), amulet):
				thin += 1
	if offered == 0:
		pending("no starts were offered across the sampled runs")
		return
	assert_eq(thin, 0,
		"%d of %d starts were offered on a road below the floor" % [thin, offered])


# --- the band is absolute (§19.3.2) ----------------------------------------

# A panel is three genres or it is no panel. The three relaxations that used to
# fill a short one are gone, so a run that reaches the picker reaches it whole.
func test_a_panel_is_never_short() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 24680
	var seen := 0
	for _i in range(4):
		var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
		if pick.is_empty():
			continue    # a legitimate outcome now — it just is not this test's case
		var options: Array = pick.get("options", [])
		assert_eq(options.size(), RunGraph.NUM_START_OPTIONS,
			"a panel that reaches the player has all its cards")
		var genres := {}
		for opt in options:
			genres[int(opt.get("type", -1))] = true
		assert_eq(genres.size(), options.size(), "one card per genre, all different")
		seen += 1
	if seen == 0:
		pending("the catalogue produced no panel at all across four rolls")


# The generator's own answer has to agree with the one the setup screen shows,
# or a target is refused for a reason the run would not have hit (§19.3.2).
func test_the_screen_and_the_generator_ask_the_same_question() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 112358
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
	if pick.is_empty():
		pending("the catalogue could not supply a run")
		return
	var amulet := StringName(pick.get("amulet_id", ""))
	assert_gte(RunGraph.panel_genres(amulet), RunGraph.NUM_START_OPTIONS,
		"%s supplied a panel, so the screen must not refuse it" % amulet)


func test_a_game_off_the_map_supplies_no_panel() -> void:
	assert_eq(RunGraph.panel_genres(&"not_a_game_at_all"), 0,
		"a game that is not on the map cannot be opened on anything")

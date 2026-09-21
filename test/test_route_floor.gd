extends GutTest

# The route floor (docs/games-first-redesign.md §19.3) — `slack`, and the filter
# that keeps a thin road out of the start panel.
#
# The arithmetic is the part worth pinning: slack is DAG nodes minus hops, and a
# single-file corridor scores 1 rather than 0 because it already carries one more
# node than its own length. Get that offset wrong and every threshold in the
# section moves by one.

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


# The filter's whole job: an offered IN-WINDOW start clears the floor. A relaxed
# out-of-band card is the one thing that can sit below it, and §19.3.2 retires
# that path — but it still exists today, so this only asserts the in-window ones.
func test_every_in_window_start_offered_clears_the_floor() -> void:
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
			if not bool(opt.get("in_window", false)):
				continue
			offered += 1
			if not RunGraph.route_clears_floor(StringName(opt.get("start_id", "")), amulet):
				thin += 1
	if offered == 0:
		pending("no in-window starts were offered across the sampled runs")
		return
	assert_eq(thin, 0,
		"%d of %d in-window starts were offered on a road below the floor" % [
			thin, offered])

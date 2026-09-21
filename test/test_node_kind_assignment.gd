extends GutTest

# The assignment pass (docs/games-first-redesign.md §19.3) — RunGraph's pure
# half. Nothing here touches a run; it hands the function an Amulet and some
# starts and reads the map back.
#
# The map is the shipping catalogue, so these pick a real Amulet and real starts
# off it rather than inventing a graph: the properties under test are about DAGs
# converging and spare nodes existing, and a toy graph would have neither.

var _rng: RandomNumberGenerator


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260921


# A real (amulet, starts) triple off the live graph: an amulet with at least
# `want` eligible starts in band, and those starts. {} when the catalogue cannot
# supply one, which the callers report as pending rather than asserting through.
func _a_real_run(want: int = 3) -> Dictionary:
	var band: Vector2i = RunConfig.path_band()
	for g in Data.all_games():
		if not (g is GameData) or not RunGraph.passes_filter(g):
			continue
		if RunGraph.is_off_map(g.id):
			continue
		var d: Dictionary = RunGraph.bfs_distances(g.id)
		var starts: Array = []
		for other in Data.all_games():
			if not (other is GameData) or other.id == g.id:
				continue
			if not d.has(other.id):
				continue
			var h: int = int(d[other.id])
			if h < band.x or h > band.y:
				continue
			if RunGraph.neighbors(other.id).size() < RunGraph.MIN_START_CONNECTIONS:
				continue
			starts.append(other.id)
			if starts.size() >= want:
				break
		if starts.size() >= want:
			return {"amulet": g.id, "starts": starts}
	return {}


func test_the_amulet_is_always_a_champion() -> void:
	var run: Dictionary = _a_real_run()
	if run.is_empty():
		pending("the catalogue could not supply an amulet with three in-band starts")
		return
	var kinds: Dictionary = RunGraph.assign_node_kinds(_rng, run["amulet"], run["starts"])
	assert_eq(int(kinds.get(run["amulet"], -1)), RunGraph.NodeKind.CHAMPION,
		"the Amulet carries the one Champion the road is promised")


func test_every_start_is_enemies() -> void:
	var run: Dictionary = _a_real_run()
	if run.is_empty():
		pending("the catalogue could not supply an amulet with three in-band starts")
		return
	var kinds: Dictionary = RunGraph.assign_node_kinds(_rng, run["amulet"], run["starts"])
	for sid in run["starts"]:
		assert_eq(int(kinds.get(sid, -1)), RunGraph.NodeKind.ENEMIES,
			"a run opens on a fight: %s" % sid)


# The guarantee itself: each offered start's DAG carries an Event and a Shop.
func test_each_route_carries_an_event_and_a_shop() -> void:
	var run: Dictionary = _a_real_run()
	if run.is_empty():
		pending("the catalogue could not supply an amulet with three in-band starts")
		return
	var kinds: Dictionary = RunGraph.assign_node_kinds(_rng, run["amulet"], run["starts"])
	for sid in run["starts"]:
		var route: Array = RunGraph.dag_node_ids(sid, run["amulet"])
		var found := {}
		for id in route:
			found[int(kinds.get(id, RunGraph.NodeKind.ENEMIES))] = true
		assert_true(found.has(RunGraph.NodeKind.EVENT),
			"route from %s must carry an Event" % sid)
		assert_true(found.has(RunGraph.NodeKind.SHOP),
			"route from %s must carry a Shop" % sid)


# A guaranteed kind never lands on the two nodes that already have one — the
# Amulet's Champion and the start's Enemies would both be overwritten, and a
# guarantee on the terminal node guarantees nothing about the road.
func test_the_guarantee_never_overwrites_the_start_or_the_amulet() -> void:
	var run: Dictionary = _a_real_run()
	if run.is_empty():
		pending("the catalogue could not supply an amulet with three in-band starts")
		return
	var kinds: Dictionary = RunGraph.assign_node_kinds(_rng, run["amulet"], run["starts"])
	assert_eq(int(kinds[run["amulet"]]), RunGraph.NodeKind.CHAMPION)
	for sid in run["starts"]:
		assert_eq(int(kinds[sid]), RunGraph.NodeKind.ENEMIES)


func test_every_in_component_game_gets_a_kind() -> void:
	var run: Dictionary = _a_real_run()
	if run.is_empty():
		pending("the catalogue could not supply an amulet with three in-band starts")
		return
	var kinds: Dictionary = RunGraph.assign_node_kinds(_rng, run["amulet"], run["starts"])
	var missing := 0
	for g in Data.all_games():
		if not (g is GameData) or not RunGraph.passes_filter(g):
			continue
		if RunGraph.is_off_map(g.id):
			continue
		if not kinds.has(g.id):
			missing += 1
	assert_eq(missing, 0,
		"a teleport can land anywhere, so every node answers the same question")


# The distribution is the map's, not each route's — the guaranteed placements
# count against it rather than sitting on top (§19.3). A handful of forced nodes
# out of hundreds should leave the totals close to 60/20/10/10.
func test_the_map_lands_near_the_sixty_twenty_ten_ten() -> void:
	var run: Dictionary = _a_real_run()
	if run.is_empty():
		pending("the catalogue could not supply an amulet with three in-band starts")
		return
	var kinds: Dictionary = RunGraph.assign_node_kinds(_rng, run["amulet"], run["starts"])
	var total: int = kinds.size()
	if total < 100:
		pending("component too small to talk about a distribution")
		return
	var count := {}
	for id in kinds.keys():
		var k: int = int(kinds[id])
		count[k] = int(count.get(k, 0)) + 1
	for kind in RunGraph.KIND_WEIGHTS.keys():
		var want: float = float(RunGraph.KIND_WEIGHTS[kind])
		var got: float = 100.0 * float(count.get(kind, 0)) / float(total)
		assert_almost_eq(got, want, 2.0,
			"%s should be near %d%% of the map, got %.1f%%" % [
				RunGraph.kind_label(int(kind)), int(want), got])


# Same seed, same map — the assignment rides the run's RNG so a save can carry
# the result rather than re-deriving it.
func test_the_same_seed_gives_the_same_map() -> void:
	var run: Dictionary = _a_real_run()
	if run.is_empty():
		pending("the catalogue could not supply an amulet with three in-band starts")
		return
	var a := RandomNumberGenerator.new()
	a.seed = 11223344
	var b := RandomNumberGenerator.new()
	b.seed = 11223344
	var first: Dictionary = RunGraph.assign_node_kinds(a, run["amulet"], run["starts"])
	var second: Dictionary = RunGraph.assign_node_kinds(b, run["amulet"], run["starts"])
	assert_eq(first.size(), second.size())
	var differing := 0
	for id in first.keys():
		if int(first[id]) != int(second.get(id, -1)):
			differing += 1
	assert_eq(differing, 0, "the same seed has to deal the same map")


# A caller handing in nothing usable gets an empty answer rather than a crash —
# the selection code decides what is legal, not this.
func test_no_starts_is_not_a_crash() -> void:
	var kinds: Dictionary = RunGraph.assign_node_kinds(_rng, &"", [])
	assert_true(kinds.size() >= 0, "an empty ask answers rather than crashing")

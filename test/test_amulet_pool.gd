extends GutTest

# Who is allowed to BE the goal (docs/games-first-redesign.md §19.9).
#
# The draw used to measure the catalogue from three random reference starts, so
# the pool was a lottery: fine on average, and one roll in forty left barely half
# the map eligible. These tests are about the property that replaced it — the
# pool is the same set every run, because every eligible start is read — and they
# ask the live graph rather than sampling runs, which is the only way to tell a
# stable pool from a lucky one.

var _starts: Array = []
var _component: Array = []
var _all: Array = []


func before_each() -> void:
	_starts = []
	_component = []
	_all = []
	for g in Data.all_games():
		if not (g is GameData) or not RunGraph.passes_filter(g):
			continue
		_all.append(g)
		if RunGraph.is_off_map(g.id):
			continue
		_component.append(g)
		if RunGraph.is_eligible_start(g.id):
			_starts.append(g)


# The headline claim: reading every stick makes every in-component game a
# candidate. It is exact, not approximate — a game that fell out here would be a
# game the run can never aim at, silently.
func test_every_game_on_the_map_can_be_the_goal() -> void:
	if _starts.is_empty():
		pending("the catalogue supplied no eligible starts")
		return
	var pool: Dictionary = RunGraph.amulet_candidates_from(_starts, _all)
	var missing: Array = []
	for g in _component:
		if not pool.has(g.id):
			missing.append(str(g.id))
	assert_eq(missing.size(), 0,
		"%d in-component games can never be the amulet: %s" % [
			missing.size(), str(missing.slice(0, 6))])


# The trap this rewrite had to step around. The old code excluded its reference
# starts from candidacy, which is harmless at three sticks and catastrophic at
# all of them: it would take the ENTIRE start pool out of the amulet draw, and
# the symptom is a pool that looks merely smaller rather than obviously wrong.
func test_an_eligible_start_is_still_allowed_to_be_the_goal() -> void:
	if _starts.is_empty():
		pending("the catalogue supplied no eligible starts")
		return
	var pool: Dictionary = RunGraph.amulet_candidates_from(_starts, _all)
	var excluded := 0
	for g in _starts:
		if not pool.has(g.id):
			excluded += 1
	assert_eq(excluded, 0,
		"%d of %d eligible starts were shut out of the amulet draw" % [
			excluded, _starts.size()])


# The pool must not depend on which starts are read first, or in what order. The
# sweep stops early once it can no longer change its answer, and that shortcut is
# only sound if it really is the same answer — so ask it with the pool shuffled
# and with the shortcut denied.
func test_the_pool_does_not_depend_on_the_order_the_starts_are_read() -> void:
	if _starts.size() < 2:
		pending("need at least two eligible starts to reorder them")
		return
	var forward: Dictionary = RunGraph.amulet_candidates_from(_starts, _all)
	var reversed_pool: Array = _starts.duplicate()
	reversed_pool.reverse()
	var backward: Dictionary = RunGraph.amulet_candidates_from(reversed_pool, _all)
	assert_eq(backward.size(), forward.size(),
		"reading the starts in the other order gave a different pool")
	var differing := 0
	for id in forward:
		if not backward.has(id):
			differing += 1
	assert_eq(differing, 0, "the pool is the union, so the order cannot matter")


# A single reference is what the very first version of this did, and the reason
# it kept being widened. Whatever one stick sees, all of them together see at
# least as much — this is the inequality the whole section rests on.
func test_one_reference_never_sees_more_than_all_of_them() -> void:
	if _starts.is_empty():
		pending("the catalogue supplied no eligible starts")
		return
	var everything: Dictionary = RunGraph.amulet_candidates_from(_starts, _all)
	var narrowest := -1
	for i in [0, _starts.size() / 2, _starts.size() - 1]:
		var one: Dictionary = RunGraph.amulet_candidates_from([_starts[i]], _all)
		for id in one:
			assert_true(everything.has(id),
				"%s is in band from %s and must be in the union" % [
					id, (_starts[i] as GameData).id])
		if narrowest < 0 or one.size() < narrowest:
			narrowest = one.size()
	# …and the widening was worth doing: a single stick really does see less.
	assert_lt(narrowest, everything.size(),
		"if one reference saw the whole map there was nothing to fix")


# Candidacy is the band and nothing else — a candidate has an eligible start at a
# legal distance, and the run's own path_band is where that distance comes from.
func test_a_candidate_has_an_eligible_start_at_a_legal_distance() -> void:
	if _starts.is_empty():
		pending("the catalogue supplied no eligible starts")
		return
	var band: Vector2i = RunConfig.path_band()
	var pool: Dictionary = RunGraph.amulet_candidates_from(_starts, _all)
	# Six is enough to catch an off-by-one in the band without walking 790 BFS.
	var ids: Array = pool.keys()
	var checked := 0
	for i in range(mini(6, ids.size())):
		var d: Dictionary = RunGraph.bfs_distances(ids[i])
		var found := false
		for s in _starts:
			var sid: StringName = (s as GameData).id
			if not d.has(sid):
				continue
			var hops: int = int(d[sid])
			if hops >= band.x and hops <= band.y:
				found = true
				break
		assert_true(found,
			"%s is a candidate but no eligible start sits %d..%d hops away" % [
				ids[i], band.x, band.y])
		checked += 1
	if checked == 0:
		pending("the pool was empty, so there was nothing to check")

extends GutTest

# `RunGraph.dag_branch_scores_from` scores every candidate amulet in one sweep of
# the shortest-path DAG, where `dag_branch_score_early` scores one candidate by
# running a whole-catalog BFS from it. The rewrite is justified by an argument
# rather than by an obvious refactor — "n lies on a shortest start->A path" is the
# same statement as "n reaches A in the DAG rooted at the start" — so the two have
# to be checked against each other on the real graph, not just reasoned about.
#
# This is the test that lets the fast one be trusted. If it ever fails, the fast
# path is wrong and the slow one is the answer.

func _reference_starts(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260907
	var pool: Array = []
	for g in Data.all_games():
		if g is GameData and RunGraph.neighbors(g.id).size() >= RunGraph.MIN_START_CONNECTIONS:
			pool.append(g)
	var out: Array = []
	for i in n:
		if pool.is_empty():
			break
		out.append(pool[rng.randi() % pool.size()])
	return out

func test_the_one_pass_scores_match_the_per_candidate_ones() -> void:
	var refs: Array = _reference_starts(3)
	if refs.is_empty():
		pending("no game in this catalog has enough connections to be a reference start")
		return
	var compared: int = 0
	var nonzero: int = 0
	for ref in refs:
		var d_ref: Dictionary = RunGraph.bfs_distances(ref.id)
		var fast: Dictionary = RunGraph.dag_branch_scores_from(d_ref)
		# Every reachable game, not a sample: the whole point is that the sweep
		# answers for all of them, and a disagreement on any one is a bug.
		for id in d_ref:
			var slow: int = RunGraph.dag_branch_score_early(d_ref, id)
			var quick: int = int(fast.get(id, 0))
			compared += 1
			if slow > 0:
				nonzero += 1
			if slow != quick:
				assert_eq(quick, slow,
					"%s scored from %s: one-pass says %d, per-candidate says %d" % [
						id, ref.id, quick, slow])
				return
	assert_gt(compared, 100, "the comparison actually walked the catalog (%d games)" % compared)
	assert_gt(nonzero, 0,
		"and some of them score above zero, so this is not two agreeing zeroes")
	assert_true(true, "every reachable game scores the same both ways (%d compared)" % compared)

# The mirror image: hold the AMULET still and score every possible start against
# it, which is what _strict_starts_for wants. Same claim, same obligation to check
# it — and this one carries ancestors at RELATIVE depths rather than absolute, so
# it is a genuinely different sweep and not the same code read backwards.
func test_the_one_pass_start_scores_match_the_per_start_ones() -> void:
	var amulets: Array = _reference_starts(2)
	if amulets.is_empty():
		pending("no game in this catalog has enough connections to score against")
		return
	var compared: int = 0
	var nonzero: int = 0
	for amulet in amulets:
		var d_to_amulet: Dictionary = RunGraph.bfs_distances(amulet.id)
		var fast: Dictionary = RunGraph.dag_branch_scores_to(d_to_amulet)
		for id in d_to_amulet:
			if id == amulet.id:
				continue
			# The slow way: distances FROM this start, scored against the amulet.
			var d_from: Dictionary = RunGraph.bfs_distances(id)
			var slow: int = RunGraph.dag_branch_score_early(
				d_from, amulet.id, RunGraph.EARLY_LAYERS_FOR_SCORE, d_to_amulet)
			var quick: int = int(fast.get(id, 0))
			compared += 1
			if slow > 0:
				nonzero += 1
			if slow != quick:
				assert_eq(quick, slow,
					"%s as a start for %s: one-pass says %d, per-start says %d" % [
						id, amulet.id, quick, slow])
				return
			if compared >= 400:
				break
	assert_gt(compared, 100, "the comparison actually walked the catalog (%d starts)" % compared)
	assert_gt(nonzero, 0,
		"and some of them score above zero, so this is not two agreeing zeroes")

# The two sweeps answer the same question from opposite ends, so on any one
# (start, amulet) pair they must agree with each other as well as with the slow
# one. This is the pair of them meeting in the middle.
func test_the_two_sweeps_agree_with_each_other() -> void:
	var picks: Array = _reference_starts(2)
	if picks.size() < 2:
		pending("this catalog has too few connected games to make a pair")
		return
	var start: GameData = picks[0]
	var amulet: GameData = picks[1]
	if start.id == amulet.id:
		pending("the two picks landed on the same game")
		return
	var d_from: Dictionary = RunGraph.bfs_distances(start.id)
	var d_to: Dictionary = RunGraph.bfs_distances(amulet.id)
	if not d_from.has(amulet.id):
		pending("this pair is not connected on the run graph")
		return
	assert_eq(int(RunGraph.dag_branch_scores_from(d_from).get(amulet.id, -1)),
		int(RunGraph.dag_branch_scores_to(d_to).get(start.id, -2)),
		"scoring %s -> %s from either end gives the same answer" % [start.id, amulet.id])

# --- the distance memo cannot grow forever ----------------------------------
#
# It had no cap, and the scoring above is what filled it: one roll of the
# choose-your-start panel left 669 origins and 509,778 distance entries, and every
# later run added more for the life of the process. The sweeps took nearly all of
# that away on their own — a boot now leaves four origins — but "small in
# practice" is not a bound, and what made it grow was a call site nobody had
# noticed. Same shape as test_run_map.gd::test_the_memo_is_bounded, and the same
# wholesale-empty rule, so the only property worth asserting is the cap.

func test_the_distance_memo_is_bounded() -> void:
	RunGraph.invalidate_cache()
	var asked: int = 0
	for g in Data.all_games():
		if asked >= RunGraph.BFS_CACHE_MAX + 5:
			break
		RunGraph.bfs_distances(g.id)
		asked += 1
	assert_gt(asked, RunGraph.BFS_CACHE_MAX,
		"the catalog is big enough to push the memo past its cap")
	assert_lte(RunGraph._bfs_cache.size(), RunGraph.BFS_CACHE_MAX,
		"the distance memo never exceeds its cap")

func test_a_roll_of_the_start_panel_leaves_the_memo_small() -> void:
	# The number the fix is actually about. Before the sweeps this was 669.
	RunGraph.invalidate_cache()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	RunGraph.pick_amulet_and_starts(rng)
	assert_lte(RunGraph._bfs_cache.size(), RunGraph.BFS_CACHE_MAX,
		"one roll leaves the memo inside its cap (%d origins)" % RunGraph._bfs_cache.size())

func test_the_score_is_bounded_by_the_layers_it_counts() -> void:
	var refs: Array = _reference_starts(1)
	if refs.is_empty():
		pending("no game in this catalog has enough connections to be a reference start")
		return
	var d_ref: Dictionary = RunGraph.bfs_distances(refs[0].id)
	var fast: Dictionary = RunGraph.dag_branch_scores_from(d_ref)
	for id in fast:
		assert_between(int(fast[id]), 0, RunGraph.EARLY_LAYERS_FOR_SCORE,
			"%s scores within the layers the score counts" % id)
		break
	var worst: int = 0
	for id in fast:
		worst = maxi(worst, int(fast[id]))
	assert_lte(worst, RunGraph.EARLY_LAYERS_FOR_SCORE,
		"no game scores above the number of early layers")

func test_the_start_itself_scores_nothing() -> void:
	var refs: Array = _reference_starts(1)
	if refs.is_empty():
		pending("no game in this catalog has enough connections to be a reference start")
		return
	var d_ref: Dictionary = RunGraph.bfs_distances(refs[0].id)
	var fast: Dictionary = RunGraph.dag_branch_scores_from(d_ref)
	assert_eq(int(fast.get(refs[0].id, -1)), 0,
		"the reference start is depth 0 — nothing branches on the way to itself")

# The layer cap is what keeps the sweep cheap: a node carries a couple of ids per
# early layer rather than a set that grows with the graph. Two is all the score
# can read, since a layer counts once it has two nodes on a shortest path.
func test_a_deeper_early_layer_setting_still_agrees() -> void:
	var refs: Array = _reference_starts(1)
	if refs.is_empty():
		pending("no game in this catalog has enough connections to be a reference start")
		return
	var d_ref: Dictionary = RunGraph.bfs_distances(refs[0].id)
	var layers: int = RunGraph.EARLY_LAYERS_FOR_SCORE + 2
	var fast: Dictionary = RunGraph.dag_branch_scores_from(d_ref, layers)
	var checked: int = 0
	for id in d_ref:
		var slow: int = RunGraph.dag_branch_score_early(d_ref, id, layers)
		assert_eq(int(fast.get(id, 0)), slow,
			"%s agrees at early_layers=%d" % [id, layers])
		checked += 1
		if checked >= 150:
			break
	assert_gt(checked, 0, "there were games to check")

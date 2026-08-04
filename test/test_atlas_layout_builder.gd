extends GutTest

# The runtime layout builder — the half of tools/bake_atlas.py that had to come
# back to GDScript so the Collection's Atlas can re-lay the sky around whatever
# its filters leave standing, instead of dimming stars where they stand.
#
# Two things are asserted throughout: the builder agrees with the BAKER about
# the shape of a sky (same capitals, regions and hops for the same input), and
# whatever it produces is drawable — no two stars on top of each other.

const BAKED := "res://data/atlas_layout.tres"

func _all_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for g in Data.all_games():
		out.append(String(g.id))
	return out

func _ids_of_type(type: int) -> PackedStringArray:
	var out := PackedStringArray()
	for g in Data.all_games():
		if int(g.type) == type:
			out.append(String(g.id))
	return out

# Every pair of stars must clear each other, exactly as the baker's own verify
# pass demands. Uses a grid so the full catalog doesn't cost 300k comparisons.
func _overlaps(layout: AtlasLayout) -> int:
	var cell := 48.0
	var grid := {}
	for i in range(layout.star_count()):
		var p: Vector2 = layout.position_of(i)
		var key := Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	var bad: int = 0
	for i in range(layout.star_count()):
		var p: Vector2 = layout.position_of(i)
		var ri: float = AtlasLayout.star_radius(layout.degree_of(i))
		var home := Vector2i(int(floor(p.x / cell)), int(floor(p.y / cell)))
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for j in grid.get(home + Vector2i(dx, dy), []):
					if int(j) <= i:
						continue
					var rr: float = ri + AtlasLayout.star_radius(layout.degree_of(j))
					if p.distance_squared_to(layout.position_of(j)) < rr * rr - 1e-3:
						bad += 1
	return bad

# --- the constellation port ------------------------------------------------

func test_the_port_agrees_with_the_baker_about_the_graph() -> void:
	var baked: AtlasLayout = load(BAKED)
	var built: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	assert_not_null(built)
	assert_eq(built.game_ids, baked.game_ids, "the same catalog, in the same order")
	assert_eq(built.edge_count(), baked.edge_count(), "and the same links")

func test_the_port_picks_the_same_capitals() -> void:
	var baked: AtlasLayout = load(BAKED)
	var built: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	var baked_caps: Array = []
	var built_caps: Array = []
	for c in baked.capitals:
		baked_caps.append(String(baked.id_at(c)))
	for c in built.capitals:
		built_caps.append(String(built.id_at(c)))
	assert_eq(built_caps, baked_caps, "same hubs, in the same order")

func test_the_port_assigns_the_same_regions_and_hops() -> void:
	var baked: AtlasLayout = load(BAKED)
	var built: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	var same_region: int = 0
	var same_hop: int = 0
	for i in range(built.star_count()):
		var j: int = baked.index_of(built.id_at(i))
		if baked.region[j] == built.region[i]:
			same_region += 1
		if baked.hops[j] == built.hops[i]:
			same_hop += 1
	assert_eq(same_region, built.star_count(), "every game lands in the same constellation")
	assert_eq(same_hop, built.star_count(), "at the same distance from its capital")

func test_the_full_sky_has_no_overlapping_stars() -> void:
	var built: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	assert_eq(_overlaps(built), 0, "the packing keeps every star clear of every other")

# --- a filtered subgraph is a sky in its own right -------------------------

func test_a_filtered_subgraph_gets_its_own_capitals() -> void:
	var deck: PackedStringArray = _ids_of_type(GameData.GameType.DECKBUILDER)
	var built: AtlasLayout = AtlasLayoutBuilder.build(deck, 8, "test")
	assert_not_null(built)
	assert_eq(built.star_count(), deck.size(), "only the survivors are in the sky")
	assert_eq(built.capitals.size(), 8, "and it is cut around its own hubs")
	for c in built.capitals:
		var g: GameData = Data.get_game(built.id_at(c))
		assert_eq(int(g.type), int(GameData.GameType.DECKBUILDER),
			"a capital of the deckbuilder sky is a deckbuilder")

func test_a_subgraph_drops_links_that_leave_it() -> void:
	var deck: PackedStringArray = _ids_of_type(GameData.GameType.DECKBUILDER)
	var built: AtlasLayout = AtlasLayoutBuilder.build(deck, 8, "test")
	for e in range(built.edge_count()):
		var a: GameData = Data.get_game(built.id_at(built.edges[e * 2]))
		var b: GameData = Data.get_game(built.id_at(built.edges[e * 2 + 1]))
		assert_eq(int(a.type), int(GameData.GameType.DECKBUILDER))
		assert_eq(int(b.type), int(GameData.GameType.DECKBUILDER))

func test_a_filtered_sky_also_has_no_overlaps() -> void:
	var built: AtlasLayout = AtlasLayoutBuilder.build(
		_ids_of_type(GameData.GameType.TRADITIONAL), 8, "test")
	assert_eq(_overlaps(built), 0)

func test_the_layout_is_a_function_of_the_set_not_its_order() -> void:
	var ids: Array = Array(_ids_of_type(GameData.GameType.STRATEGY))
	var forward := PackedStringArray(ids)
	ids.reverse()
	var backward := PackedStringArray(ids)
	var a: AtlasLayout = AtlasLayoutBuilder.build(forward, 6, "test")
	var b: AtlasLayout = AtlasLayoutBuilder.build(backward, 6, "test")
	assert_eq(a.game_ids, b.game_ids, "the same games")
	assert_eq(a.xs, b.xs, "in the same places, whichever order they arrived in")
	assert_eq(a.ys, b.ys)

func test_a_tiny_set_still_builds() -> void:
	var two := PackedStringArray([String(Data.all_games()[0].id)])
	var built: AtlasLayout = AtlasLayoutBuilder.build(two, 8, "test")
	assert_not_null(built, "one game is still a sky")
	assert_eq(built.star_count(), 1)
	assert_lte(built.capitals.size(), 1, "and cannot have more capitals than stars")

func test_an_empty_set_builds_nothing() -> void:
	assert_null(AtlasLayoutBuilder.build(PackedStringArray(), 8, "test"))
	assert_null(AtlasLayoutBuilder.build_tree(PackedStringArray(), &"rogue", "test"))

func test_unknown_ids_are_ignored() -> void:
	var built: AtlasLayout = AtlasLayoutBuilder.build(
		PackedStringArray(["rogue", "no_such_game_at_all"]), 8, "test")
	assert_eq(built.star_count(), 1, "a game that isn't in the catalog isn't a star")

# --- the radial tree -------------------------------------------------------

func test_the_tree_is_rooted_at_rogue() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	assert_true(tree.is_tree(), "a tree sky carries its parents")
	var root: int = tree.index_of(&"rogue")
	assert_eq(tree.parent[root], -1, "the root hangs off nothing")
	assert_eq(tree.hops[root], 0, "and sits at depth 0")
	assert_almost_eq(tree.position_of(root).length(), 0.0, 0.001, "dead centre")

func test_every_connected_game_hangs_off_the_tree() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var root: int = tree.index_of(&"rogue")
	for i in range(tree.star_count()):
		if tree.degree_of(i) == 0:
			assert_eq(tree.hops[i], -1, "an unconnected game is not in the tree")
			continue
		assert_gte(tree.hops[i], 0, "%s is somewhere in the tree" % tree.id_at(i))
		if i != root:
			assert_gte(tree.parent[i], 0, "%s hangs off a branch" % tree.id_at(i))

func test_a_child_is_always_one_generation_deeper_than_its_parent() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	for i in range(tree.star_count()):
		var p: int = tree.parent[i]
		if p >= 0:
			assert_eq(tree.hops[i], tree.hops[p] + 1,
				"%s sits one ring out from %s" % [tree.id_at(i), tree.id_at(p)])

func test_older_games_sit_closer_to_the_middle() -> void:
	# The tree runs outward in time because influence does — but only in the
	# large. Ring by ring it PLATEAUS at the modern end (rings 4 and 5 are both
	# ~2021: nearly everything recent is three or four steps from Rogue however
	# it got there), so the honest assertion is that the inner rings are decisively
	# older than the outer ones, not that every ring beats the last.
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var sum_year := {}
	var count := {}
	for i in range(tree.star_count()):
		var d: int = tree.hops[i]
		if d < 0:
			continue
		var g: GameData = Data.get_game(tree.id_at(i))
		sum_year[d] = float(sum_year.get(d, 0.0)) + float(g.year)
		count[d] = int(count.get(d, 0)) + 1
	var depths: Array = count.keys()
	depths.sort()
	var populated: Array = depths.filter(func(d): return int(count[d]) >= 5)
	assert_gt(populated.size(), 2, "there are enough rings to compare")
	var mean_of := func(d): return float(sum_year[d]) / float(count[d])
	var innermost: float = mean_of.call(populated[0])
	var outermost: float = mean_of.call(populated[-1])
	assert_gt(outermost, innermost + 5.0,
		"the outer rings are years newer than the inner ones (%.0f vs %.0f)"
			% [outermost, innermost])
	# And no ring is a real step BACK in time — a plateau is fine, a reversal
	# would mean the tree is putting ancestors outside their descendants.
	var previous: float = -INF
	for d in populated:
		var mean: float = mean_of.call(d)
		assert_gt(mean, previous - 1.0,
			"ring %d does not run backwards in time" % d)
		previous = mean

func test_unconnected_games_ring_the_outside() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var tree_max := 0.0
	var orbit_min := INF
	var orbit_max := 0.0
	var orbiting: int = 0
	for i in range(tree.star_count()):
		var r: float = tree.position_of(i).length()
		if tree.degree_of(i) == 0:
			orbiting += 1
			orbit_min = minf(orbit_min, r)
			orbit_max = maxf(orbit_max, r)
		else:
			tree_max = maxf(tree_max, r)
	assert_gt(orbiting, 0, "there are unconnected games to ring")
	assert_gt(orbit_min, tree_max, "every one of them sits outside the whole tree")
	assert_almost_eq(orbit_min, orbit_max, 0.5, "and they form a circle, not a cloud")

func test_the_tree_has_no_capitals_or_regions() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	assert_eq(tree.capitals.size(), 0, "a tree has one root, not eight hubs")
	for r in tree.region:
		assert_eq(r, -1, "and no constellations to belong to")

func test_the_tree_has_no_overlapping_stars() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	assert_eq(_overlaps(tree), 0, "the ring sizing keeps every star clear")

func test_branch_links_are_a_subset_of_the_real_links() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var branches: int = 0
	for e in range(tree.edge_count()):
		if tree.is_tree_edge(tree.edges[e * 2], tree.edges[e * 2 + 1]):
			branches += 1
	assert_gt(branches, 0, "the tree's own branches are drawn from real influences")
	assert_lt(branches, tree.edge_count(),
		"and the rest are cross-links the tree can't show as branches")

func test_the_tree_falls_back_when_the_root_is_filtered_out() -> void:
	# Deckbuilders don't include Rogue, so the tree has to root itself somewhere
	# rather than come back empty.
	var deck: PackedStringArray = _ids_of_type(GameData.GameType.DECKBUILDER)
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(deck, &"rogue", "test")
	assert_not_null(tree)
	assert_eq(tree.index_of(&"rogue"), -1, "Rogue really isn't in this set")
	assert_true(tree.is_tree(), "and it still built a tree")
	var roots: int = 0
	for i in range(tree.star_count()):
		if tree.parent[i] < 0 and tree.hops[i] == 0:
			roots += 1
	assert_eq(roots, 1, "with exactly one root")

func test_a_constellation_sky_is_not_a_tree() -> void:
	var built: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	assert_false(built.is_tree(), "constellations carry no parents")
	assert_false(built.is_tree_edge(0, 1), "so nothing is a branch")
	assert_false((load(BAKED) as AtlasLayout).is_tree(), "nor does the baked sky")

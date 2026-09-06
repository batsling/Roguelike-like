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

# --- the halo of unconnected games ----------------------------------------

func _halo_and_core(l: AtlasLayout) -> Array:
	# Returns [halo indices, core indices]. A game with no links is halo; a game
	# with any link at all belongs to the packing.
	var halo: Array = []
	var core: Array = []
	for i in range(l.star_count()):
		if l.degree_of(i) == 0:
			halo.append(i)
		else:
			core.append(i)
	return [halo, core]

func test_unconnected_games_ring_the_constellations() -> void:
	var built: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	var split: Array = _halo_and_core(built)
	var halo: Array = split[0]
	var core: Array = split[1]
	assert_gt(halo.size(), 50, "the catalog has plenty of unjoined games")
	# The middle of the packing, which is what the halo is drawn around.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in core:
		lo = lo.min(built.position_of(i))
		hi = hi.max(built.position_of(i))
	var centre: Vector2 = (lo + hi) * 0.5
	var furthest_core: float = 0.0
	for i in core:
		furthest_core = maxf(furthest_core, centre.distance_to(built.position_of(i)))
	for i in halo:
		assert_gt(centre.distance_to(built.position_of(i)), furthest_core,
			"%s has no links, so it sits outside the constellations" % built.id_at(i))

func test_the_halo_is_scattered_not_a_drawn_circle() -> void:
	# The whole point of the bands and the jitter: it should read as a scatter
	# around the sky, not as a rendered circle. Distinct radii is the test.
	var built: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	var halo: Array = _halo_and_core(built)[0]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(built.star_count()):
		if built.degree_of(i) > 0:
			lo = lo.min(built.position_of(i))
			hi = hi.max(built.position_of(i))
	var centre: Vector2 = (lo + hi) * 0.5
	var radii := {}
	for i in halo:
		radii[roundi(centre.distance_to(built.position_of(i)))] = true
	assert_gt(radii.size(), 10,
		"a scattered halo lands at many different distances, got %d" % radii.size())

func test_the_halo_never_overlaps_anything() -> void:
	# The bands and the capped jitter exist to make this provable rather than
	# lucky, so it is worth asserting on a filter as well as the full catalog.
	for ids in [_all_ids(), _ids_of_type(GameData.GameType.ACTION)]:
		var built: AtlasLayout = AtlasLayoutBuilder.build(ids, 8, "test")
		assert_eq(_overlaps(built), 0, "%d stars, none touching" % built.star_count())

func test_the_halo_is_the_same_scatter_every_time() -> void:
	# Jittered, but from a hash of the star rather than from random() — the sky
	# has to be a pure function of the game set.
	var a: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	var b: AtlasLayout = AtlasLayoutBuilder.build(_all_ids(), 8, "test")
	assert_eq(a.xs, b.xs, "same scatter")
	assert_eq(a.ys, b.ys)

func test_the_baked_sky_rings_its_unconnected_games_too() -> void:
	# The shipped skies come from tools/bake_atlas.py, so the Python half has to
	# have the halo as well — otherwise the unfiltered Atlas (which draws the
	# BAKED layout) would still have its unjoined games sprinkled through the
	# middle.
	var baked: AtlasLayout = load(BAKED)
	var split: Array = _halo_and_core(baked)
	var core: Array = split[1]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in core:
		lo = lo.min(baked.position_of(i))
		hi = hi.max(baked.position_of(i))
	var centre: Vector2 = (lo + hi) * 0.5
	var furthest_core: float = 0.0
	for i in core:
		furthest_core = maxf(furthest_core, centre.distance_to(baked.position_of(i)))
	for i in split[0]:
		assert_gt(centre.distance_to(baked.position_of(i)), furthest_core,
			"%s is outside the baked constellations" % baked.id_at(i))

# --- the radial tree -------------------------------------------------------

func test_the_tree_is_rooted_at_rogue() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	assert_true(tree.is_tree(), "a tree sky carries its parents")
	var root: int = tree.index_of(&"rogue")
	assert_eq(tree.parent[root], -1, "the root hangs off nothing")
	assert_eq(tree.hops[root], 0, "and sits at depth 0")
	# It lands in the middle because it is the oldest CONNECTED game, not because
	# it is the root — radius is the year now. The two coincide for the full
	# catalog, which is exactly why the tree is rooted there.
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

# `hops` stays the BRANCH depth even though the rings are years now: it is what
# the HUD's "N deep" reads, and besides `parent` it is the only record that the
# sky has a tree structure at all.
func test_a_child_is_always_one_generation_deeper_than_its_parent() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	for i in range(tree.star_count()):
		var p: int = tree.parent[i]
		if p >= 0:
			assert_eq(tree.hops[i], tree.hops[p] + 1,
				"%s is one branch step past %s" % [tree.id_at(i), tree.id_at(p)])

func test_each_year_is_its_own_ring() -> void:
	# The point of the layout: radius IS the release year, so every game from a
	# given year sits at exactly one distance from the middle.
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var ring_of := {}
	for i in range(tree.star_count()):
		if tree.hops[i] < 0:
			continue                       # the unconnected outer ring
		var year: int = Data.get_game(tree.id_at(i)).year
		var r: float = tree.position_of(i).length()
		if ring_of.has(year):
			assert_almost_eq(r, float(ring_of[year]), 0.01,
				"%s (%d) sits on its year's ring" % [tree.id_at(i), year])
		else:
			ring_of[year] = r
	assert_gt(ring_of.size(), 30, "the catalog spans a lot of years, so a lot of rings")

func test_the_rings_run_outward_in_time() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var ring_of := {}
	for i in range(tree.star_count()):
		if tree.hops[i] < 0:
			continue
		ring_of[Data.get_game(tree.id_at(i)).year] = tree.position_of(i).length()
	var years: Array = ring_of.keys()
	years.sort()
	var previous := -1.0
	for y in years:
		assert_gt(float(ring_of[y]), previous,
			"%d sits outside every year before it" % y)
		previous = float(ring_of[y])

func test_the_earliest_year_is_the_middle() -> void:
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var earliest: int = 1 << 30
	for i in range(tree.star_count()):
		if tree.hops[i] >= 0:
			earliest = mini(earliest, Data.get_game(tree.id_at(i)).year)
	for i in range(tree.star_count()):
		if tree.hops[i] >= 0 and Data.get_game(tree.id_at(i)).year == earliest:
			assert_almost_eq(tree.position_of(i).length(), 0.0, 0.01,
				"the oldest connected game is the centre")

func test_a_gap_in_the_catalog_is_a_gap_on_the_map() -> void:
	# Years are spaced by TIME, not by rank, so a decade nobody shipped in reads
	# as empty space rather than being closed up.
	var tree: AtlasLayout = AtlasLayoutBuilder.build_tree(_all_ids(), &"rogue", "test")
	var ring_of := {}
	for i in range(tree.star_count()):
		if tree.hops[i] < 0:
			continue
		ring_of[Data.get_game(tree.id_at(i)).year] = tree.position_of(i).length()
	var years: Array = ring_of.keys()
	years.sort()
	# Find a one-year step and a multi-year step, and check the second is wider.
	var single := -1.0
	var jump := -1.0
	var jump_years: int = 0
	for k in range(1, years.size()):
		var span: int = int(years[k]) - int(years[k - 1])
		var step: float = float(ring_of[years[k]]) - float(ring_of[years[k - 1]])
		if span == 1 and single < 0.0:
			single = step
		elif span > 1 and jump < 0.0:
			jump = step
			jump_years = span
	if single < 0.0 or jump < 0.0:
		pending("the run did not reach this case (single < 0.0 or jump < 0.0)")
		return                             # no gaps in this catalog to check
	assert_almost_eq(jump, single * float(jump_years), single * 0.5,
		"a %d-year gap is about %d times a one-year step" % [jump_years, jump_years])

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

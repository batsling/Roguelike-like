extends GutTest

# Validates the StrategyAttackLibrary — the shared, editable mapping from a
# card's Attack-column archetype (poke/swing/smash/projectile/beam/nova/lob) to
# its tile RANGE and grid FOOTPRINT in tactical combat. Guards that the .tres
# loads, Data exposes it, range words resolve, footprints have the expected
# shape, and directional footprints rotate to face the aimed tile.

const Lib := preload("res://scripts/resources/StrategyAttackLibrary.gd")

func _lib() -> StrategyAttackLibrary:
	return load("res://data/strategy_attacks.tres")

func test_data_exposes_strategy_attacks() -> void:
	assert_not_null(Data.strategy_attacks, "Data.strategy_attacks is populated")
	assert_true(Data.strategy_attacks is StrategyAttackLibrary,
		"it is a StrategyAttackLibrary resource")

func test_tres_loads_with_expected_reach() -> void:
	var lib := _lib()
	assert_not_null(lib, "strategy_attacks.tres loads")
	assert_eq(int(lib.reach_tiles["short"]), 1)
	assert_eq(int(lib.reach_tiles["medium"]), 2)
	assert_eq(int(lib.reach_tiles["large"]), 3)
	assert_eq(int(lib.radius_tiles["medium"]), 2)

func test_resolve_ranges_per_archetype() -> void:
	var lib := _lib()
	# poke takes its reach from the size word (short 1 / medium 2 / large 3);
	# swing is always a melee arc.
	assert_eq(int(lib.resolve(&"poke", {})["range_tiles"]), 1, "poke short = 1 tile")
	assert_eq(int(lib.resolve(&"poke", {"size": "medium"})["range_tiles"]), 2, "poke medium = 2")
	assert_eq(int(lib.resolve(&"poke", {"size": "large"})["range_tiles"]), 3, "poke large = 3")
	assert_eq(int(lib.resolve(&"swing", {})["range_tiles"]), 1, "swing is melee adjacency")
	# projectile reaches its size word; beam reaches the full board.
	assert_eq(int(lib.resolve(&"projectile", {})["range_tiles"]), 2)
	assert_eq(int(lib.resolve(&"projectile", {"size": "large"})["range_tiles"]), 3)
	assert_gt(int(lib.resolve(&"beam", {})["range_tiles"]), 50, "beam reaches across the board")
	# smash depth scales with size and is the placement range too.
	assert_eq(int(lib.resolve(&"smash", {"size": "large"})["radius"]), 3)

func test_unknown_shape_falls_back_safely() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"not_a_real_shape", {})
	assert_eq(String(spec["family"]), "front_arc", "unknown shape -> swing fallback")

func test_poke_footprint_is_single_aimed_tile() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"poke", {})
	var fp: Array = lib.footprint(spec, Vector2i(5, 5), Vector2i(6, 5))
	assert_eq(fp.size(), 1, "poke hits exactly the aimed tile")
	assert_true(fp.has(Vector2i(6, 5)))

func test_small_swing_is_the_three_front_tiles() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"swing", {"size": "small"})
	var origin := Vector2i(5, 5)
	# Aiming east: front tile + the two flanking tiles east.
	var east: Array = lib.footprint(spec, origin, Vector2i(6, 5))
	assert_eq(east.size(), 3, "small swing is the 3-tile front arc")
	assert_true(east.has(Vector2i(6, 5)) and east.has(Vector2i(6, 4)) and east.has(Vector2i(6, 6)),
		"east arc covers the eastern column")
	# Aiming north: the same arc, rotated to the northern row.
	var north: Array = lib.footprint(spec, origin, Vector2i(5, 4))
	assert_true(north.has(Vector2i(5, 4)) and north.has(Vector2i(4, 4)) and north.has(Vector2i(6, 4)),
		"north arc rotates to the northern row")

func test_medium_swing_wraps_onto_the_side_tiles() -> void:
	var lib := _lib()
	# Medium is also the default swing size.
	var spec: Dictionary = lib.resolve(&"swing", {})
	var origin := Vector2i(5, 5)
	var east: Array = lib.footprint(spec, origin, Vector2i(6, 5))
	assert_eq(east.size(), 5, "medium swing = 3 front + the 2 side tiles")
	for t in [Vector2i(6, 5), Vector2i(6, 4), Vector2i(6, 6), Vector2i(5, 4), Vector2i(5, 6)]:
		assert_true(east.has(t), "east medium swing covers %s" % str(t))

func test_large_swing_is_a_full_ring() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"swing", {"size": "large"})
	var fp: Array = lib.footprint(spec, Vector2i(5, 5), Vector2i(6, 5))
	assert_eq(fp.size(), 8, "large swing rings all 8 neighbours")
	assert_false(bool(spec.get("rotates", true)), "a full ring has no facing")

func test_arc360_swing_still_maps_to_the_full_ring() -> void:
	# Back-compat: the old "Swing, arc=360" spelling behaves exactly like Large.
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"swing", {"arc": 360})
	var fp: Array = lib.footprint(spec, Vector2i(5, 5), Vector2i(6, 5))
	assert_eq(fp.size(), 8, "arc=360 swing rings all 8 neighbours")

func test_projectile_is_a_line_outward() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"projectile", {"size": "large"})  # range 3
	var fp: Array = lib.footprint(spec, Vector2i(2, 5), Vector2i(5, 5))
	assert_eq(fp.size(), 3, "3-tile line east")
	assert_true(fp.has(Vector2i(3, 5)) and fp.has(Vector2i(4, 5)) and fp.has(Vector2i(5, 5)))

func test_projectile_stops_on_first_body_without_pierce() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"projectile", {"size": "large"})  # range 3
	var stops := {Vector2i(4, 5): true}
	var fp: Array = lib.footprint(spec, Vector2i(2, 5), Vector2i(6, 5), null, stops)
	assert_true(fp.has(Vector2i(4, 5)), "the struck body is included")
	assert_false(fp.has(Vector2i(5, 5)), "the line stops at the first body")

func test_pierce_passes_through_bodies() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"projectile", {"pierce": true, "size": "large"})  # range 3
	var stops := {Vector2i(4, 5): true}
	var fp: Array = lib.footprint(spec, Vector2i(2, 5), Vector2i(5, 5), null, stops)
	assert_eq(fp.size(), 3, "a piercing shot ignores bodies and runs its full length")

func test_nova_is_a_disc_around_the_attacker() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"nova", {"size": "medium"})  # radius 2
	var origin := Vector2i(8, 8)
	var fp: Array = lib.footprint(spec, origin, origin)
	# Chebyshev disc radius 2 -> 5x5 block minus nothing = 25 tiles.
	assert_eq(fp.size(), 25, "radius-2 nova covers a 5x5 disc")
	assert_true(fp.has(origin) and fp.has(Vector2i(6, 6)) and fp.has(Vector2i(10, 10)))

func test_aimable_tiles_respect_range() -> void:
	var lib := _lib()
	var spec: Dictionary = lib.resolve(&"poke", {"size": "medium"})  # range 2
	var tiles: Dictionary = lib.aimable_tiles(spec, Vector2i(5, 5))
	assert_false(tiles.has(Vector2i(5, 5)), "the attacker's own tile is never aimable")
	assert_true(tiles.has(Vector2i(7, 5)), "a tile 2 away is in range")
	assert_false(tiles.has(Vector2i(8, 5)), "a tile 3 away is out of range")

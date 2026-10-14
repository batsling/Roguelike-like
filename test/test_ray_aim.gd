extends GutTest

# THE RAY (RayAim, docs/loot-passives.md §12.1): the Aim a weapon or wand takes
# when the sheet says `ray` — a ball from the hero's side through the clicked
# square, mirrored off walls and enemies until its bounces run out, landing its
# effect on EVERY enemy it struck.
#
# On the base 4x4 board the ray leaves from (0.5, 2.0): the middle of the hero's
# column, beside the board's left edge. The paths below are worked by hand from
# there, so a change to the geometry fails here with the square it moved.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

# A plain one-cell body with 3 Health standing on `cell`.
func _body(cell: Vector2i) -> int:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.health = 3
	e.damage = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	var inst: int = GameLoop2.spawn_to_stack(e)
	var entry: Dictionary = GameLoop2.entry_for(inst)
	entry["col"] = cell.x
	entry["row"] = cell.y
	return inst

func _hit_ids(path: Dictionary) -> Array:
	return (path["hits"] as Array).map(func(h): return int(h["instance"]))

func _board_is_base() -> bool:
	if GameLoop2.grid_cols() != 4 or GameLoop2.grid_rows() != 4:
		pending("the board is not the base 4x4 these paths are worked on")
		return false
	return true

# --- the geometry ------------------------------------------------------------

func test_a_ray_carries_on_past_the_square_clicked_to_the_wall() -> void:
	if not _board_is_base():
		return
	var path: Dictionary = RayAim.trace(Vector2i(2, 1), 0)
	assert_eq(path["cells"], [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(4, 0)], "the click is only a direction: past it, the line drifts on up")
	assert_eq(path["end"], Vector2i(4, 0))
	path = RayAim.trace(Vector2i(4, 1), 0)
	assert_eq(path["cells"], [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)],
		"the click is only a direction: the line runs on to the back wall")
	assert_eq(path["end"], Vector2i(4, 1), "and stops on the last square before it")
	assert_eq(path["hits"], [], "an empty board strikes nobody")
	assert_eq(RayAim.impacts(path), [{"instance": 0, "cell": Vector2i(4, 1)}],
		"a ray that struck nobody lands where it stopped")
	assert_eq((path["points"] as Array)[0], Vector2(0.5, 2.0), "it leaves from the hero")

func test_a_ray_with_no_bounce_stops_at_the_first_enemy() -> void:
	if not _board_is_base():
		return
	var near: int = _body(Vector2i(3, 1))
	var far: int = _body(Vector2i(4, 1))
	var path: Dictionary = RayAim.trace(Vector2i(4, 1), 0)
	assert_eq(_hit_ids(path), [near], "the body in front shields the one behind it")
	assert_eq(path["end"], Vector2i(3, 1))
	assert_false(_hit_ids(path).has(far))

func test_a_bounce_off_the_top_wall_mirrors_the_ray_down() -> void:
	if not _board_is_base():
		return
	var path: Dictionary = RayAim.trace(Vector2i(2, 0), 1)
	assert_eq(path["bounced"], 1)
	assert_eq(path["cells"], [Vector2i(1, 1), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(4, 0), Vector2i(4, 1)], "up to the top wall, then back down")
	assert_eq(path["end"], Vector2i(4, 1), "and stopped by the back wall, its bounce spent")
	assert_eq((path["points"] as Array).size(), 3, "the hero, the bounce, the stop")

func test_a_bounce_off_an_enemy_carries_on_into_a_second_one() -> void:
	if not _board_is_base():
		return
	var first: int = _body(Vector2i(1, 0))
	var second: int = _body(Vector2i(3, 2))
	var path: Dictionary = RayAim.trace(Vector2i(2, 0), 1)
	assert_eq(_hit_ids(path), [first, second],
		"up into the first body, mirrored off its underside, down into the second")
	assert_eq(path["end"], Vector2i(3, 2))

func test_without_the_bounce_the_second_enemy_is_safe() -> void:
	if not _board_is_base():
		return
	var first: int = _body(Vector2i(1, 0))
	_body(Vector2i(3, 2))
	assert_eq(_hit_ids(RayAim.trace(Vector2i(2, 0), 0)), [first])

func test_a_ray_mirrored_back_past_the_hero_goes_home() -> void:
	if not _board_is_base():
		return
	var front: int = _body(Vector2i(1, 1))
	var path: Dictionary = RayAim.trace(Vector2i(4, 1), 3)
	assert_eq(_hit_ids(path), [front], "it strikes the body in front of you once")
	assert_eq(path["end"], GameLoop2.OFF_FIELD, "and, flipped back toward you, leaves the board")
	assert_eq(path["bounced"], 1, "the hero's side is not a wall: no bounce is spent there")

func test_a_big_body_is_struck_once_however_often_the_ray_meets_it() -> void:
	var e := GoalEnemyData.new()
	e.id = &"big"
	e.display_name = "Big"
	e.health = 5
	e.size = "4x1"
	e.shape_rows = 4
	e.shape_cols = 1
	e.shape_mask = PackedInt32Array([1, 1, 1, 1])
	var inst: int = GameLoop2.spawn_to_stack(e)
	var entry: Dictionary = GameLoop2.entry_for(inst)
	entry["col"] = GameLoop2.grid_cols()
	entry["row"] = 0
	if GameLoop2.entry_cells(entry).size() != GameLoop2.grid_rows():
		pending("the tall body did not stand across the back column")
		return
	# A wall of a body at the back: a ray bouncing off it and the top and bottom
	# walls meets it again and again.
	var path: Dictionary = RayAim.trace(Vector2i(2, 0), 6)
	assert_eq(_hit_ids(path), [inst], "one body is one hit, whatever the bounces")

func test_every_trace_ends() -> void:
	# Every square of the board, with a body in the way and without, at a generous
	# bounce count: a ray must always stop, and inside the board.
	_body(Vector2i(2, 2))
	for col in range(1, GameLoop2.grid_cols() + 1):
		for row in range(GameLoop2.grid_rows()):
			var path: Dictionary = RayAim.trace(Vector2i(col, row), 5)
			for c in path["cells"]:
				assert_true(GameLoop2._on_board(c.x, c.y), "%s stays on the board" % [c])
			assert_lte(int(path["bounced"]), 5)

# --- weapons -----------------------------------------------------------------

func test_earthquake_is_a_ray_that_bounces_once() -> void:
	var w: WeaponData = Data.get_weapon(&"earthquake")
	assert_not_null(w, "Earthquake is in the catalog")
	if w == null:
		return
	assert_eq(w.aim, "ray")
	assert_eq(w.bounce, 1, "the sheet's `bounce 1`, read out of its Effect")
	assert_eq(w.area, "3x3")
	var entry: Dictionary = WeaponSystem.new_entry(w)
	assert_true(WeaponSystem.needs_aim(entry), "a ray is aimed")
	assert_eq(WeaponSystem.aim_cells(entry).size(),
		GameLoop2.grid_cols() * GameLoop2.grid_rows(), "at any square of the board")
	assert_string_contains(LootSystem.weapon_description(entry), "bouncing once")

func test_the_makeshift_sisyphus_starts_with_earthquake() -> void:
	var c: CharacterData = Data.get_character2(&"the_makeshift_sisyphus")
	assert_not_null(c)
	if c == null:
		return
	assert_eq(c.starting_loot, [{"type": "weapon", "id": "earthquake"}])

func test_a_ray_swing_stuns_both_enemies_and_the_ground_round_each() -> void:
	if not _board_is_base():
		return
	var first: int = _body(Vector2i(1, 0))
	var second: int = _body(Vector2i(3, 2))
	var beside: int = _body(Vector2i(4, 3))     # in the 3x3 round the second
	var clear: int = _body(Vector2i(4, 0))      # in neither 3x3, and off the line
	var entry: Dictionary = WeaponSystem.new_entry(Data.get_weapon(&"earthquake"))
	WeaponSystem.swing(entry, {"target": Vector2i(2, 0)})
	for inst in [first, second, beside]:
		assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(inst)), 1,
			"body %d is stunned" % inst)
	assert_eq(GameLoop2.stun_stacks(GameLoop2.entry_for(clear)), 0, "the far corner is not")
	var strike: Dictionary = (GameLoop2.last_strike["strikes"] as Array)[0]
	assert_gt((strike.get("ray", []) as Array).size(), 2, "the board is handed the line")

func test_the_preview_and_the_swing_agree() -> void:
	_body(Vector2i(1, 0))
	_body(Vector2i(3, 2))
	var w: WeaponData = Data.get_weapon(&"earthquake")
	var entry: Dictionary = WeaponSystem.new_entry(w)
	var lit: Array = WeaponSystem.hit_cells(entry, Vector2i(2, 0))
	WeaponSystem.swing(entry, {"target": Vector2i(2, 0)})
	var strike: Dictionary = (GameLoop2.last_strike["strikes"] as Array)[0]
	assert_eq(strike["cells"], lit, "what the hover lit is what the swing covered")

# --- wands -------------------------------------------------------------------

func _wand(id: StringName) -> Dictionary:
	var w: WandData = Data.get_wand(id)
	return {"type": "wand", "id": id, "rarity": w.rarity, "charges": w.starting_charges()}

func test_the_wands_aim_in_the_weapons_words() -> void:
	assert_eq(Data.get_wand(&"wand_of_magic_missile").aim, "ray")
	assert_eq(Data.get_wand(&"wand_of_magic_missile").bounce, 1, "`Ray, Bounce 1`")
	assert_eq(Data.get_wand(&"wand_of_wishing").aim, "none", "Non-Directional is `none`")
	assert_eq(Data.get_wand(&"wand_of_nothing").aim, "random")

func test_a_ray_wand_does_its_effect_to_both_enemies_it_hits() -> void:
	if not _board_is_base():
		return
	var first: int = _body(Vector2i(1, 0))
	var second: int = _body(Vector2i(3, 2))
	var bystander: int = _body(Vector2i(4, 3))
	WandSystem.zap_wand(_wand(&"wand_of_magic_missile"), {"target": Vector2i(2, 0)})
	assert_eq(int(GameLoop2.entry_for(first)["health"]), 2, "the first body took the missile")
	assert_eq(int(GameLoop2.entry_for(second)["health"]), 2, "and so did the one it bounced into")
	assert_eq(int(GameLoop2.entry_for(bystander)["health"]), 3,
		"a wand's area is the square it hit: nobody beside is touched")
	assert_true(WandSystem.is_identified(&"wand_of_magic_missile"), "it landed, so it is learned")

func test_a_ray_wand_that_strikes_nobody_lands_where_it_stopped() -> void:
	if not _board_is_base():
		return
	WandSystem.zap_wand(_wand(&"wand_of_fire"), {"target": Vector2i(4, 1)})
	# Straight along row 1 to the back wall, mirrored off it, and back home: the
	# one bounce is spent on the wall and nothing stops it, so it lands nowhere.
	var path: Dictionary = RayAim.trace(Vector2i(4, 1), 1)
	assert_eq(path["end"], GameLoop2.OFF_FIELD, "(the path this test is about)")
	assert_true(GameLoop2.tiles.is_empty(), "a ray that went home lays nothing")
	assert_false(WandSystem.is_identified(&"wand_of_fire"), "and teaches nothing")
	# Bounce spent on the top wall, stopped by the back one: fire on that square.
	WandSystem.zap_wand(_wand(&"wand_of_fire"), {"target": Vector2i(2, 0)})
	assert_true(GameLoop2.tiles.has(Vector2i(4, 1)), "fire where the bolt stopped")

func test_a_non_directional_wand_runs_once_and_ignores_the_ray() -> void:
	WandSystem.identify(&"wand_of_create_monster")
	assert_false(WandSystem.needs_target(_wand(&"wand_of_create_monster")))
	var before: int = GameLoop2.stack.size()
	WandSystem.zap_wand(_wand(&"wand_of_create_monster"), {})
	assert_eq(GameLoop2.stack.size(), before + 1, "one body, called up once")

func test_an_unknown_wand_asks_for_any_square_and_previews_nothing() -> void:
	var entry: Dictionary = _wand(&"wand_of_magic_missile")
	assert_true(WandSystem.needs_target(entry))
	assert_eq(WandSystem.aim_cells(entry).size(),
		GameLoop2.grid_cols() * GameLoop2.grid_rows(), "every square, as any wand would")
	assert_false(WandSystem.previews_ray(entry), "drawing the line would say it is a ray wand")
	WandSystem.identify(&"wand_of_magic_missile")
	assert_true(WandSystem.previews_ray(entry), "once known, its path is shown")

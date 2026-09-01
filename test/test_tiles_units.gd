extends GutTest

# Tile effects and units (docs/games-first-redesign.md §17) — the two things that
# can be on a cell of the battlefield that are not a body.
#
# Four layers, in the order one passes through them:
#   1. the CONTENT — tiles2.0 / units2.0 load, and their authored triggers,
#      interactions and decay come through as the sheet wrote them;
#   2. the BOARD — a tile bites what walks into it and what stays on it, a unit
#      goes off under whoever steps on it, and the pair annihilate each other;
#   3. the CONTENT THAT REACHES THEM — Scroll of Fire, Red Candle, Hot Bombs and
#      Landmines;
#   4. the WIRING — routing around a minefield, save/load, and the keyword strip
#      an item's description carries.

# Choose a game and take its ESCORT straight back off the board — the same helper
# every other 2.0 suite uses, and for the same reason: a stranger from the
# authored roster standing on the board would put content these tests never asked
# about inside their assertions.
func _choose_solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 40
	GameState.hp = 40

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

# A synthetic goal-enemy with known numbers, so nothing here moves when the
# enemies2.0 sheet does.
func _enemy(goal: String = "Beat it", health: int = 3) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.goal = goal
	e.damage = 1
	e.health = health
	e.difficulty = GoalEnemyData.Difficulty.LOW
	return e

func _give(id: StringName) -> ItemData:
	var tmpl: ItemData = Data.get_item2(id)
	assert_not_null(tmpl, "items2.0 has %s" % id)
	return GameState.add_item(tmpl)

# Stand the only body on the board at a known cell, so a test about the GROUND
# doesn't also have to be about where the spawner happened to put someone.
func _park(instance: int, cell: Vector2i) -> Dictionary:
	var entry: Dictionary = GameLoop2.entry_for(instance)
	entry["col"] = cell.x
	entry["row"] = cell.y
	return entry

# ---------------------------------------------------------------------------
# 1. The content
# ---------------------------------------------------------------------------

func test_the_tiles_and_units_sheets_loaded() -> void:
	assert_not_null(Data.get_tile(&"fire"), "the Fire tile is in the catalog")
	assert_not_null(Data.get_unit(&"landmine"), "and the Landmine unit")

func test_fire_is_authored_on_both_triggers() -> void:
	# The pair is the whole point: a cell that only bit on entry would be free to
	# park on, and one that only bit at turn start would be free to walk through.
	var fire: TileEffectData = Data.get_tile(&"fire")
	assert_true(fire.has_trigger(GameLoop2.ON_ENTER), "walking in costs a stack")
	assert_true(fire.has_trigger(GameLoop2.ON_TURN_START), "and so does staying")
	assert_eq(fire.effects_for(GameLoop2.ON_ENTER).size(), 1)
	assert_eq(String(fire.effects_for(GameLoop2.ON_ENTER)[0]["op"]), "apply_status")

func test_fire_decays_in_games_not_turns() -> void:
	# How many turns a game buys is read off the distance to the Amulet (§7.4), so
	# a tile authored in turns would be worth three times as much out in the wilds
	# as it is on the doorstep. The generator refuses a Decay cell in turns; this
	# is the value that made it through.
	var fire: TileEffectData = Data.get_tile(&"fire")
	assert_eq(fire.decay_games, 3, "three GAMES")
	assert_eq(fire.decay_text, "3 Games", "and it says so in the sheet's own words")

func test_the_pairing_is_authored_from_the_mines_end_only() -> void:
	# Fire meeting a mine and a mine meeting Fire are one event, and `_settle_cell`
	# UNIONS the two sides — so authoring it once is enough, and the half that
	# carries it is the MINE. Fire deliberately says nothing: every authored
	# pairing becomes a line on the tile's hover card, and a burning square has no
	# business lecturing a player about a unit they may never own.
	var fire: TileEffectData = Data.get_tile(&"fire")
	var mine: UnitData = Data.get_unit(&"landmine")
	assert_eq(mine.interaction_with(&"tile", &"fire"),
		["detonate_unit", "remove_tile"])
	assert_eq(fire.interaction_with(&"unit", &"landmine"), [],
		"and fire does not name the mine back")
	assert_false(fire.tooltip_for().to_lower().contains("landmine"),
		"so nothing about fire mentions it")
	assert_false(str(fire.hover_card()["lines"]).to_lower().contains("landmine"),
		"on the card either")

func test_a_landmine_is_a_proxy_bomb_in_the_content() -> void:
	var mine: UnitData = Data.get_unit(&"landmine")
	assert_eq(String(mine.effects_for(GameLoop2.ON_ENTER)[0]["op"]), "detonate")
	assert_eq(mine.health, 1, "a one-shot: going off spends the whole of it")

# ---------------------------------------------------------------------------
# 2. The board
# ---------------------------------------------------------------------------

func test_a_tile_is_laid_with_its_authored_life() -> void:
	assert_true(GameLoop2.apply_tile(Vector2i(2, 1), &"fire"))
	assert_eq(GameLoop2.tile_games_left(Vector2i(2, 1)), 3)
	assert_eq(GameLoop2.tile_at(Vector2i(2, 1)).id, &"fire")

func test_a_tile_off_the_board_is_refused() -> void:
	assert_false(GameLoop2.apply_tile(Vector2i(GameLoop2.grid_cols() + 3, 0), &"fire"))
	assert_false(GameLoop2.apply_tile(Vector2i(2, 0), &"no_such_tile"))

func test_walking_into_fire_burns_the_body() -> void:
	var inst: int = _choose_solo(_enemy())
	_park(inst, Vector2i(3, 0))
	GameLoop2.apply_tile(Vector2i(2, 0), &"fire")
	assert_eq(int(GameLoop2.entry_for(inst)["statuses"].get(&"burn", 0)), 0, "not yet")
	# A shove is a way of ARRIVING in a cell, and every arrival pays the same
	# tolls — a step, a spawn, a push and a board that grew under a body all go
	# through the one function (GameLoop2._move_entry).
	GameState.push = 1
	GameLoop2.push(inst, GameLoop2.PUSH_FORWARD)
	assert_eq(int(GameLoop2.entry_for(inst)["statuses"].get(&"burn", 0)), 1,
		"a shove into the fire costs a stack, exactly as walking in would")

func test_fire_lit_under_a_body_burns_it_on_the_spot() -> void:
	# The ground changing UNDER a body is as much a meeting as the body walking
	# into it, so it costs the same stack and costs it now. It used to wait for the
	# enemy's next turn, which made a Red Candle aimed at an occupied square look
	# like a click that had missed.
	var inst: int = _choose_solo(_enemy())
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	GameLoop2.apply_tile(Vector2i(2, 1), &"fire")
	assert_eq(int(entry["statuses"].get(&"burn", 0)), 1,
		"lighting the square a body is standing on burns it immediately")

func test_fire_lit_on_bare_ground_burns_nobody() -> void:
	var inst: int = _choose_solo(_enemy())
	var entry: Dictionary = _park(inst, Vector2i(3, 0))
	GameLoop2.apply_tile(Vector2i(2, 0), &"fire")
	assert_eq(int(entry["statuses"].get(&"burn", 0)), 0,
		"a square away is a square away")

func test_fire_that_annihilates_on_arrival_burns_nobody() -> void:
	# Fire laid onto a mine is taken straight back off the board (§17), and a body
	# standing there must not be billed for ground that never existed.
	var inst: int = _choose_solo(_enemy("Beat it", 9))
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	GameLoop2.apply_unit(Vector2i(2, 1), &"landmine")
	GameLoop2.apply_tile(Vector2i(2, 1), &"fire")
	assert_null(GameLoop2.tile_at(Vector2i(2, 1)), "the fire went out on arrival")
	assert_eq(int(GameLoop2.entry_for(inst).get("statuses", {}).get(&"burn", 0)), 0,
		"so nothing on that square burned")

func test_standing_in_fire_burns_again_each_turn() -> void:
	# On the FRONT column, where the body strikes rather than steps — so it is
	# standing on the same burning cell for every turn of the game, and the count
	# is a fact about the fire rather than about where the walk took it.
	var inst: int = _choose_solo(_enemy("Beat it", 9))
	var entry: Dictionary = _park(inst, Vector2i(1, 0))
	GameLoop2.apply_tile(Vector2i(1, 0), &"fire")
	assert_eq(int(entry["statuses"].get(&"burn", 0)), 1, "one for the lighting")
	# Two turns of the board, bought outright — a reported game hands out only the
	# Amulet's extra turns (§7.4), and there is no amulet in a headless run.
	GameLoop2.attempt_turn()
	GameLoop2.attempt_turn()
	assert_eq(int(GameLoop2.entry_for(inst)["statuses"].get(&"burn", 0)),
		mini(1 + 2, Data.get_status(&"burn").max_stacks),
		"and one for every turn it started there, up to Burn's own ceiling")

func test_fire_burns_out_after_three_games() -> void:
	GameLoop2.apply_tile(Vector2i(2, 0), &"fire")
	for game in range(2):
		GameLoop2.beat_game(false)
		assert_eq(GameLoop2.tile_games_left(Vector2i(2, 0)), 2 - game,
			"still burning after %d" % (game + 1))
	var res: Dictionary = GameLoop2.beat_game(false)
	assert_null(GameLoop2.tile_at(Vector2i(2, 0)), "out on the third")
	assert_true((res["tiles_expired"] as Array).has(Vector2i(2, 0)),
		"and the resolve says which ground went out")

func test_a_tile_ticks_on_a_game_that_was_missed_too() -> void:
	# The ground burns for the time spent, not for the result: beaten or not, an
	# evening went by.
	GameLoop2.apply_tile(Vector2i(2, 0), &"fire")
	GameLoop2.beat_game(false, [])
	assert_eq(GameLoop2.tile_games_left(Vector2i(2, 0)), 2)

func test_a_mine_goes_off_under_whoever_steps_on_it() -> void:
	var inst: int = _choose_solo(_enemy("Beat it", 1))
	_park(inst, Vector2i(3, 0))
	assert_true(GameLoop2.apply_unit(Vector2i(2, 0), &"landmine"))
	GameState.push = 1
	GameLoop2.push(inst, GameLoop2.PUSH_FORWARD)
	assert_true(GameLoop2.entry_for(inst).is_empty(),
		"a 1-Health body does not survive the blast")
	assert_null(GameLoop2.unit_at(Vector2i(2, 0)), "and the mine is spent")

func test_a_mine_leaves_no_drop_the_way_a_bomb_does_not() -> void:
	# A body destroyed by a blast is destroyed, not defeated (§4) — no item, no
	# gold — and a mine is a blast.
	var inst: int = _choose_solo(_enemy("Beat it", 1))
	_park(inst, Vector2i(3, 0))
	GameLoop2.apply_unit(Vector2i(2, 0), &"landmine")
	var gold_before: int = GameState.gold
	var defeated_before: int = GameLoop2.defeated_count
	GameState.push = 1
	GameLoop2.push(inst, GameLoop2.PUSH_FORWARD)
	assert_true(GameLoop2.entry_for(inst).is_empty(), "the body is gone")
	assert_eq(GameState.gold, gold_before, "no gold")
	assert_eq(GameLoop2.defeated_count, defeated_before, "and it counts as no defeat")

func test_a_mine_fires_the_bomb_trigger_so_bomb_relics_pay() -> void:
	# The whole reason a Landmine is a UNIT rather than a one-off trap: it is a
	# proxy bomb, so the pack's bomb relics read it. Blood Bombs pays +1 Health per
	# bomb used, and a mine going off is a bomb used.
	_give(&"blood_bombs")
	GameState.hp = 10
	var bombs_before: int = GameState.bombs
	var inst: int = _choose_solo(_enemy("Beat it", 1))
	_park(inst, Vector2i(3, 0))
	GameLoop2.apply_unit(Vector2i(2, 0), &"landmine")
	GameState.push = 1
	GameLoop2.push(inst, GameLoop2.PUSH_FORWARD)
	assert_eq(GameState.hp, 11, "the mine paid Blood Bombs")
	assert_eq(GameState.bombs, bombs_before, "and spent no Bomb of its own")

func test_fire_and_a_mine_annihilate_each_other_either_way_round() -> void:
	# Laying fire onto a mine.
	GameLoop2.apply_unit(Vector2i(2, 0), &"landmine")
	assert_false(GameLoop2.apply_tile(Vector2i(2, 0), &"fire"),
		"the fire does not stick — the mine took it with it")
	assert_null(GameLoop2.unit_at(Vector2i(2, 0)), "the mine went off")
	assert_null(GameLoop2.tile_at(Vector2i(2, 0)), "and the blast blew the fire out")
	# …and dropping a mine into fire, which is the same event from the other end.
	GameLoop2.apply_tile(Vector2i(3, 1), &"fire")
	assert_false(GameLoop2.apply_unit(Vector2i(3, 1), &"landmine"))
	assert_null(GameLoop2.unit_at(Vector2i(3, 1)))
	assert_null(GameLoop2.tile_at(Vector2i(3, 1)))

func test_the_board_loses_its_furniture_when_it_shrinks() -> void:
	# A tile at column 6 of a 5-wide board is ground nothing can ever walk into.
	var item: ItemData = _give(&"mine_r_construction")
	GameLoop2.sync_grid_bounds()
	var edge := Vector2i(GameLoop2.grid_cols(), GameLoop2.grid_rows() - 1)
	GameLoop2.apply_tile(edge, &"fire")
	GameLoop2.apply_unit(Vector2i(edge.x, 0), &"landmine")
	GameState.remove_item(item)
	GameLoop2.sync_grid_bounds()
	assert_null(GameLoop2.tile_at(edge), "the tile went with the ground")
	assert_null(GameLoop2.unit_at(Vector2i(edge.x, 0)), "and so did the unit")

# ---------------------------------------------------------------------------
# 3. The content that reaches them
# ---------------------------------------------------------------------------

func test_scroll_of_fire_lights_the_front_column() -> void:
	var scroll: ScrollData = Data.get_scroll(&"scroll_of_fire")
	assert_not_null(scroll)
	ScrollSystem.read_scroll(scroll)
	for row in range(GameLoop2.grid_rows()):
		assert_eq(GameLoop2.tile_at(Vector2i(1, row)).id, &"fire",
			"row %d of the front column is alight" % row)
	assert_null(GameLoop2.tile_at(Vector2i(2, 0)), "and nothing behind it is")
	assert_eq(GameState.status_stacks(&"burn"), 3, "the reader burns too")

func test_red_candle_reaches_only_the_columns_it_authored() -> void:
	var candle: ItemData = _give(&"red_candle")
	assert_eq(candle.target_kind(), &"tile", "it points at ground, not at a body")
	assert_eq(candle.target_columns(), Vector2i(2, 3))
	# A cell inside the fence lights up…
	GameState.use_item(candle, Vector2i(3, 1))
	assert_eq(GameLoop2.tile_at(Vector2i(3, 1)).id, &"fire")

func test_red_candle_refuses_a_column_outside_its_reach() -> void:
	# Never the front column, where it would be a free hit on whatever is already
	# swinging, and never the back, where nothing would walk over it before it
	# burned out. Re-checked in the effect as well as in the board's highlight, so
	# a cell that arrived some other way obeys the same fence.
	var candle: ItemData = _give(&"red_candle")
	GameState.use_item(candle, Vector2i(1, 0))
	assert_null(GameLoop2.tile_at(Vector2i(1, 0)), "column 1 is out of reach")

func test_hot_bombs_leaves_fire_where_the_blast_was() -> void:
	_give(&"hot_bombs")
	assert_eq(GameState.bomb_tile(), &"fire")
	var inst: int = _choose_solo(_enemy("Beat it", 5))
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	GameState.bombs = 1
	assert_true(GameLoop2.bomb(inst))
	for cell in GameLoop2.entry_cells(entry):
		assert_not_null(GameLoop2.tile_at(cell), "the ground the blast covered burns")

func test_hot_bombs_reaches_a_landmines_blast_too() -> void:
	# A mine is a proxy bomb, so what the pack has done to bombs it has done to
	# mines. The mine's own cell is left on fire behind it.
	_give(&"hot_bombs")
	var inst: int = _choose_solo(_enemy("Beat it", 5))
	_park(inst, Vector2i(3, 0))
	GameLoop2.apply_unit(Vector2i(2, 0), &"landmine")
	GameState.push = 1
	GameLoop2.push(inst, GameLoop2.PUSH_FORWARD)
	assert_not_null(GameLoop2.tile_at(Vector2i(2, 0)),
		"the mine left burning ground where it went off")

func test_a_bomb_spent_on_bare_ground_still_goes_off() -> void:
	# A bomb aimed at a square rather than at a body (§17). Nothing is standing
	# there, so nothing takes damage — and with Hot Bombs the square is left
	# burning, which is the whole reason to spend one that way.
	_give(&"hot_bombs")
	GameState.bombs = 1
	assert_true(GameLoop2.bomb_cell(Vector2i(3, 1)))
	assert_eq(GameState.bombs, 0, "the charge went")
	assert_not_null(GameLoop2.tile_at(Vector2i(3, 1)),
		"and the ground it went off on is alight")

func test_a_bomb_on_the_ground_hits_whoever_is_standing_there() -> void:
	var inst: int = _choose_solo(_enemy("Beat it", 5))
	var entry: Dictionary = _park(inst, Vector2i(2, 1))
	GameState.bombs = 1
	var before: int = int(entry["health"])
	assert_true(GameLoop2.bomb_cell(Vector2i(2, 1)))
	assert_eq(int(GameLoop2.entry_for(inst)["health"]), before - 1,
		"the blast is measured on the board, not on who was aimed at")

func test_a_bomb_needs_a_charge_and_a_square_on_the_board() -> void:
	GameState.bombs = 0
	assert_false(GameLoop2.bomb_cell(Vector2i(2, 1)), "no charge, no blast")
	GameState.bombs = 1
	assert_false(GameLoop2.bomb_cell(Vector2i(GameLoop2.grid_cols() + 3, 0)),
		"and ground the board does not have is not a target")
	assert_eq(GameState.bombs, 1, "a refused bomb spends nothing")

func test_a_bomb_on_the_ground_pays_the_bomb_relics() -> void:
	# One bomb, one `bomb_used` trigger, wherever it was pointed — Blood Bombs pays
	# for a bomb spent on an empty square exactly as for one spent on a body.
	_give(&"blood_bombs")
	GameState.hp = 10
	GameState.bombs = 1
	GameLoop2.bomb_cell(Vector2i(3, 2))
	assert_eq(GameState.hp, 11)

func test_landmines_puts_one_mine_down_after_a_game() -> void:
	_give(&"landmines")
	assert_true(GameLoop2.units.is_empty(), "nothing on the ground yet")
	TriggerBus.game_beaten.emit({"game_id": &"whatever"})
	assert_eq(GameLoop2.units.size(), 1, "one mine, on ground nothing was standing on")
	for cell in GameLoop2.units.keys():
		assert_eq(GameLoop2.unit_at(cell).id, &"landmine")

func test_an_empty_cell_is_one_with_nothing_on_it_at_all() -> void:
	# "A random empty Tile" in the item's own words, read strictly: a mine dropped
	# onto burning ground would go off on the spot and take the item's whole payout
	# for that game with it.
	for col in range(1, GameLoop2.grid_cols() + 1):
		for row in range(GameLoop2.grid_rows()):
			GameLoop2.apply_tile(Vector2i(col, row), &"fire")
	assert_true(GameLoop2.empty_cells().is_empty(), "every cell is spoken for")
	_give(&"landmines")
	TriggerBus.game_beaten.emit({"game_id": &"whatever"})
	assert_true(GameLoop2.units.is_empty(), "so no mine was laid this game")

# ---------------------------------------------------------------------------
# 4. The wiring
# ---------------------------------------------------------------------------

func test_a_mined_lane_scores_worse_than_a_clear_one() -> void:
	var e: GoalEnemyData = _enemy()
	GameLoop2.apply_unit(Vector2i(2, 0), &"landmine")
	var mined: Dictionary = GameLoop2.path_blockers(e, 0, GameLoop2.grid_cols())
	var clear: Dictionary = GameLoop2.path_blockers(e, 1, GameLoop2.grid_cols())
	assert_eq(int(mined["mines"]), 1, "row 0 has a mine on the way in")
	assert_eq(int(clear["mines"]), 0, "row 1 does not")

func test_a_spawn_prefers_the_lane_without_the_mine() -> void:
	# "Generally" avoid, not "never cross": a mine ranks BELOW a body in the way,
	# because a body is a wall that may never move and a mine is a toll paid once.
	var e: GoalEnemyData = _enemy()
	for row in range(GameLoop2.grid_rows()):
		if row != 2:
			GameLoop2.apply_unit(Vector2i(2, row), &"landmine")
	var rows: Array = GameLoop2._spawn_rows(e, GameLoop2.grid_cols())
	assert_eq(rows, [2], "the one clean lane is the only best one")

func test_a_walled_lane_still_beats_a_merely_mined_one() -> void:
	# The ranking, the other way up. Row 0 is mined; row 1 has a BODY parked in it.
	# The mined lane wins, because the mine costs a point of Health and the body
	# might never move.
	var blocker: int = _choose_solo(_enemy())
	_park(blocker, Vector2i(2, 1))
	for row in range(GameLoop2.grid_rows()):
		if row != 1:
			GameLoop2.apply_unit(Vector2i(2, row), &"landmine")
	var rows: Array = GameLoop2._spawn_rows(_enemy(), GameLoop2.grid_cols())
	assert_true(rows.has(0), "the mined lanes are still on the table")
	assert_false(rows.has(1), "the walled one is not")

func test_the_ground_survives_a_save_and_a_load() -> void:
	GameLoop2.apply_tile(Vector2i(2, 1), &"fire")
	GameLoop2.beat_game(false)                     # burn one game off it
	GameLoop2.apply_unit(Vector2i(3, 2), &"landmine")
	var saved: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	assert_true(GameLoop2.tiles.is_empty())
	GameLoop2.restore(saved)
	assert_eq(GameLoop2.tile_at(Vector2i(2, 1)).id, &"fire")
	assert_eq(GameLoop2.tile_games_left(Vector2i(2, 1)), 2,
		"with the games it had left, not a fresh three")
	assert_eq(GameLoop2.unit_at(Vector2i(3, 2)).id, &"landmine")

func test_a_save_naming_content_the_catalog_lost_is_dropped() -> void:
	GameLoop2.restore({"tiles": [{"col": 2, "row": 0, "id": "deleted_tile", "games": 3}],
		"units": [{"col": 3, "row": 0, "id": "deleted_unit", "health": 1}]})
	assert_true(GameLoop2.tiles.is_empty(), "a tile nobody can describe is not restored")
	assert_true(GameLoop2.units.is_empty())

# --- what the ground says when you point at it (§17) ------------------------
#
# A furnished square answers the mouse with the same HoverCard an enemy, an item
# and a status get. It used to answer with Godot's plain grey tooltip, which was
# the one thing on the board that looked like it belonged to another program —
# and which could only spell "burns out in 2 more games" where a clock and a
# number are read at a glance.

func test_a_fire_tile_describes_itself_as_a_card() -> void:
	var card: Dictionary = Data.get_tile(&"fire").hover_card(2)
	assert_eq(String(card.get("title", "")), "Fire", "named as itself")
	assert_eq(card.get("art"), Data.get_tile(&"fire").image, "with its own art")
	var lines: String = "\n".join(PackedStringArray(card.get("lines", [])))
	assert_string_contains(lines, "Burn", "and what it does to whoever stands in it")

func test_the_tiles_clock_is_a_pip_with_the_time_left_on_it() -> void:
	var pips: Array = Data.get_tile(&"fire").hover_card(2).get("pips", [])
	assert_eq(pips.size(), 1, "one pip: how long it has left")
	var text: String = String(pips[0].get("text", ""))
	assert_string_contains(text, "⏱", "a clock, so it reads as a timer")
	assert_string_contains(text, "2", "and the number on it")

func test_the_catalog_reading_gives_the_life_the_tile_is_authored_with() -> void:
	# -1 is "describe the tile", not "describe this one on the board".
	var text: String = String(Data.get_tile(&"fire").hover_card().get("pips")[0]["text"])
	assert_string_contains(text, "3", "Fire lasts three games")
	assert_false(text.contains("left"), "but none of them has been spent yet")

func test_the_board_hands_a_burning_square_the_tiles_card() -> void:
	var board := BattlefieldView.new()
	add_child_autofree(board)
	GameLoop2.apply_tile(Vector2i(2, 1), &"fire")
	var card: Dictionary = board.ground_hover(Vector2i(2, 1))
	assert_eq(String(card.get("title", "")), "Fire")
	assert_string_contains(String(card.get("pips")[0]["text"]), "3 games left",
		"with the clock the square itself is running")

func test_a_square_with_a_unit_and_a_tile_answers_with_one_card() -> void:
	# "What is on this square" is one question. The unit heads the card — it is the
	# thing standing there — and the ground joins it as a pip and a line.
	var board := BattlefieldView.new()
	add_child_autofree(board)
	# Authored around the pair that annihilates: put them on the board directly, so
	# this is about the card rather than about the interaction.
	GameLoop2.tiles[Vector2i(2, 1)] = {"id": &"fire", "games": 2}
	GameLoop2.units[Vector2i(2, 1)] = {"id": &"landmine", "health": 1}
	var card: Dictionary = board.ground_hover(Vector2i(2, 1))
	assert_eq(String(card.get("title", "")), "Landmine", "the unit heads it")
	var pips: String = ""
	for pip in card.get("pips", []):
		pips += String(pip.get("text", "")) + " "
	assert_string_contains(pips, "⏱", "and the tile's clock rides along: %s" % pips)

func test_bare_ground_has_nothing_to_say() -> void:
	var board := BattlefieldView.new()
	add_child_autofree(board)
	assert_true(board.ground_hover(Vector2i(2, 1)).is_empty(),
		"an empty square opens no card")

# --- the keyword strip (§17) ----------------------------------------------

func test_an_items_description_finds_the_keywords_it_names() -> void:
	var found: Array = Keywords.found_in(Data.get_item2(&"hot_bombs").description)
	var names: Array = found.map(func(k): return String(k["name"]))
	assert_true(names.has("Fire Tile"), "\"Bombs Apply the Fire Tile\" names the tile")

func test_the_landmines_description_finds_the_unit() -> void:
	var found: Array = Keywords.found_in(Data.get_item2(&"landmines").description)
	var names: Array = found.map(func(k): return String(k["name"]))
	assert_true(names.has("Landmine Unit"))

func test_a_status_named_in_an_items_text_is_a_keyword_too() -> void:
	# One registry for all three kinds: from the reader's side "what is that?" is
	# one question.
	var found: Array = Keywords.found_in(Data.get_item2(&"staff_of_flame").description)
	var names: Array = found.map(func(k): return String(k["name"]))
	assert_true(names.has("Burn"), "\"Apply +3 Burn to a target enemy\"")

func test_a_keyword_is_matched_on_whole_words_only() -> void:
	# "Burn" must not light up inside "Burning Blood", which is a real relic.
	var found: Array = Keywords.found_in("Burning Blood is not a status.")
	assert_eq(found.size(), 0, "no keyword here")

func test_every_keyword_can_describe_itself() -> void:
	# The chip's hover is asked of the CONTENT, so a keyword that could not answer
	# would be a chip that opened onto nothing.
	for text in ["Gain +1 Burn", "Apply the Fire Tile", "Apply the Landmine Unit"]:
		for entry in Keywords.found_in(text):
			assert_ne(Keywords.describe(entry), "",
				"%s says what it is" % entry["name"])

# ---------------------------------------------------------------------------
# 5. Web — the tile whose clock is measured in BITES (§17, §13.2)
# ---------------------------------------------------------------------------
#
# Fire is the roster's tile that lasts N games; Web is the first that lasts until
# it catches something. The pair is what makes `decay_on_trigger` a field rather
# than "1 Game" with different words: a web nobody steps in is still there three
# games later, and a fire nobody steps in is not.

func test_web_is_authored_on_both_triggers_like_fire() -> void:
	var web: TileEffectData = Data.get_tile(&"web")
	assert_not_null(web, "the Web tile is in the catalog")
	if web == null:
		return
	assert_true(web.has_trigger(&"enemy_enters"), "walking in webs you")
	assert_true(web.has_trigger(&"enemy_turn_start"), "and so does standing in it")
	assert_eq(String(web.effects_for(&"enemy_enters")[0].get("status", "")), "stun")

func test_web_is_a_one_shot_and_fire_is_a_clock() -> void:
	var web: TileEffectData = Data.get_tile(&"web")
	assert_true(web.decay_on_trigger, "Until Triggered")
	assert_eq(web.decay_games, 0, "and no game count beside it — one clock, not two")
	var fire: TileEffectData = Data.get_tile(&"fire")
	assert_false(fire.decay_on_trigger, "Fire counts games instead")
	assert_gt(fire.decay_games, 0)

func test_walking_into_a_web_stuns_and_clears_the_square() -> void:
	var inst: int = _choose_solo(_enemy())
	var cell := Vector2i(2, 0)
	_park(inst, Vector2i(3, 0))
	GameLoop2.apply_tile(cell, &"web")
	assert_not_null(GameLoop2.tile_at(cell), "the web is laid")
	var entry: Dictionary = GameLoop2.entry_for(inst)
	GameLoop2._move_entry(entry, cell.y, cell.x)
	assert_eq(GameLoop2.entry_status_stacks(entry, &"stun"), 1, "+1 Stun for stepping in")
	assert_null(GameLoop2.tile_at(cell),
		"and the web is gone — it caught something, which is its whole clock")

func test_a_web_nobody_steps_in_outlives_a_game() -> void:
	_choose_solo(_enemy())
	var cell := Vector2i(4, 2)
	GameLoop2.apply_tile(cell, &"web")
	GameLoop2.beat_game()
	assert_not_null(GameLoop2.tile_at(cell),
		"a clock measured in bites does not tick with the calendar")

func test_a_stunned_body_loses_its_turn_and_the_stack_wears_off() -> void:
	var inst: int = _choose_solo(_enemy())
	var entry: Dictionary = GameLoop2.entry_for(inst)
	GameLoop2.apply_status_to(inst, &"stun", 2)
	assert_true(GameLoop2.is_stunned(entry), "two stacks is two turns off")
	GameLoop2.attempt_turn()
	assert_eq(GameLoop2.entry_status_stacks(entry, &"stun"), 1,
		"Each Turn — one stack per turn that elapsed")
	GameLoop2.attempt_turn()
	assert_eq(GameLoop2.entry_status_stacks(entry, &"stun"), 0)
	assert_false(GameLoop2.is_stunned(entry), "and it acts again")

func test_the_scrolls_stun_is_the_same_status_the_web_applies() -> void:
	# ONE BOOK (§13.2). `GameLoop2.stun` was the board's own counter and it applies
	# the Stun status now, so a scared monster and a webbed one are the same body in
	# the same state — and everything that reads a stun reads one number.
	var inst: int = _choose_solo(_enemy())
	var entry: Dictionary = GameLoop2.entry_for(inst)
	GameLoop2.stun(inst)
	assert_true(GameLoop2.is_stunned(entry), "it does not act")
	assert_eq(GameLoop2.entry_status_stacks(entry, &"stun"), 1,
		"and the reason is a stack of Stun, not a field of its own")
	assert_eq(GameLoop2.stun_stacks(entry), 1)
	assert_false(entry.has("stun"), "the counter is gone from the entry entirely")

func test_sticky_bombs_lays_web_where_hot_bombs_lays_fire() -> void:
	assert_eq(GameState.bomb_tile(), &"")
	_give(&"sticky_bombs")
	assert_eq(GameState.bomb_tile(), &"web",
		"the item does what its card says, through the tile layer")

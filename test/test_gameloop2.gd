extends GutTest

# Tests for the games-first loop resolver (GameLoop2) — the enemy-stack state
# machine, the one-game grace timing (§7.2), shields-then-hp damage (§3), drops on
# defeat (§8), stun, bomb, old-goal fulfilment, enemy rolling, and win/lose.
# Pure logic, no scene: this is the headless core the overworld + OBS HUD ride on.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 10
	GameState.hp = 10

# Number of .tres resource files in a data directory — the count Data._load_dir
# is expected to load, so the roster tests stay correct as content grows and
# still catch a file that fails to load (e.g. a broken image reference).
func _tres_count(path: String) -> int:
	var n := 0
	for f in DirAccess.get_files_at(path):
		if f.ends_with(".tres") or f.ends_with(".res"):
			n += 1
	return n

# A synthetic goal-enemy with a known damage, so timing/damage assertions don't
# depend on authored content.
func _enemy(dmg: int, boss := false) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = dmg
	e.health = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	e.boss = boss
	return e

# A synthetic enemy of an arbitrary footprint: `mask` is one int per row, bit `c`
# set when column `c` of that row is solid (GoalEnemyData.shape_mask).
func _shaped(dmg: int, rows: int, cols: int, mask: Array = []) -> GoalEnemyData:
	var e := _enemy(dmg)
	e.shape_rows = rows
	e.shape_cols = cols
	var rowsmask: Array = mask.duplicate()
	if rowsmask.is_empty():
		# No mask given -> a solid rectangle: every column of every row.
		for r in range(rows):
			rowsmask.append((1 << cols) - 1)
	e.shape_mask = PackedInt32Array(rowsmask)
	return e

# The Skeletal Bastion's footprint — a 2x3 L turned a quarter turn
# counter-clockwise, so the top row is a gap except at its back corner:
#     . . #
#     # # #
func _bastion(dmg: int = 3) -> GoalEnemyData:
	return _shaped(dmg, 2, 3, [0b100, 0b111])

# The front (leftmost) grid column a stacked enemy occupies (1 = front/melee,
# grid_cols() = the back of the board, offgrid_col() = off-grid queue), or -1 if it's
# gone.
func _col_of(instance: int) -> int:
	for e in GameLoop2.stack:
		if int(e["instance"]) == instance:
			return int(e.get("col", -1))
	return -1

# A stacked enemy's whole entry (health / stun / col / row), or {} if it's gone.
func _entry(instance: int) -> Dictionary:
	for e in GameLoop2.stack:
		if int(e["instance"]) == instance:
			return e
	return {}

# The grid row a stacked enemy's footprint starts on, or -1 if it's gone.
func _row_of(instance: int) -> int:
	for e in GameLoop2.stack:
		if int(e["instance"]) == instance:
			return int(e.get("row", -1))
	return -1

# How many stacked enemies start in grid column `col`.
func _count_in_col(col: int) -> int:
	var n: int = 0
	for e in GameLoop2.stack:
		if int(e.get("col", -1)) == col:
			n += 1
	return n

# Beat a game with no chosen enemy: this just advances the grid one column and
# lets the front line strike — the clean way to march a stacked enemy forward in
# a test without spawning clutter enemies.
func _tick() -> void:
	GameLoop2.beat_game(false)

# Beat games until `instance` is standing in the front column, stopping BEFORE it
# gets to strike (attacks resolve ahead of the advance). Written as a loop rather
# than a fixed number of ticks so these tests describe the timing rule — "it
# strikes once it reaches the front" — instead of how wide the board happens to
# be.
func _march_to_front(instance: int) -> void:
	for _i in range(GameLoop2.grid_cols() + 2):
		if _col_of(instance) <= 1:
			return
		_tick()

# --- choose / spawn -------------------------------------------------------

func test_choose_game_sets_current() -> void:
	var inst: int = GameLoop2.choose_game(_enemy(1))
	assert_gt(inst, 0)
	assert_true(GameLoop2.has_current())

# --- goal met -> defeat + drop -------------------------------------------

func test_goal_met_defeats_drops_and_deals_no_damage() -> void:
	GameLoop2.choose_game(_enemy(3))
	var res: Dictionary = GameLoop2.beat_game(true)
	assert_eq(GameLoop2.defeated_count, 1)
	# The drop is presented inline on the battlefield (no RewardScreen chest is
	# banked), so we assert the drop tally the overworld consumes off the resolve.
	assert_eq(int(res["drops"]), 1, "a defeated enemy drops one item")
	assert_eq(GameLoop2.stack_size(), 0)
	assert_eq(GameState.hp, 10, "a met goal deals no damage")
	assert_false(GameLoop2.has_current())

# --- one-game grace (§7.2) -----------------------------------------------

func test_failed_enemy_does_not_attack_the_game_it_stacks() -> void:
	GameLoop2.choose_game(_enemy(2))
	GameLoop2.beat_game(false)
	assert_eq(GameState.hp, 10, "the enemy that just stacked cannot hit this game")
	assert_eq(GameLoop2.stack_size(), 1)

# An enemy spawns at the back column and closes one column per game beaten; only
# once it reaches the front (col 1) does it strike (§grid). Front attacks resolve
# BEFORE the advance, so an enemy that just stepped into the front holds fire that
# game and strikes on the next.
func test_stacked_enemy_marches_forward_then_attacks() -> void:
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # A -> spawn col
	assert_eq(_col_of(a), GameLoop2.spawn_col(), "spawns at the back")
	assert_eq(GameState.hp, 10, "the back column can't strike")
	_tick()                                          # A closes one column
	assert_eq(_col_of(a), GameLoop2.spawn_col() - 1)
	assert_eq(GameState.hp, 10)
	_march_to_front(a)                               # A -> col 1 (front), no strike yet
	assert_eq(_col_of(a), 1)
	assert_eq(GameState.hp, 10, "reaches the front but strikes next game")
	_tick()                                          # A strikes for 2
	assert_eq(GameState.hp, 8)

# --- grid: advance / stall / overflow (§grid) ----------------------------

func test_enemy_closes_one_column_per_game() -> void:
	var a: int = GameLoop2.choose_game(_enemy(1)) ; GameLoop2.beat_game(false)
	assert_eq(_col_of(a), GameLoop2.spawn_col(), "spawns at the back column")
	for step in range(1, GameLoop2.spawn_col()):
		_tick()
		assert_eq(_col_of(a), GameLoop2.spawn_col() - step, "closes one column per game")
	assert_eq(_col_of(a), 1, "reaches the front")
	_tick()
	assert_eq(_col_of(a), 1, "cannot advance past the front")

# A 1x1 enemy spawns with its only cell on the back column; a WIDER one spawns
# far enough back that its RIGHTMOST cell lands there, which puts its leading
# edge closer to the player and shortens its march (§grid).
func test_wide_enemy_spawns_with_its_back_edge_on_the_last_column() -> void:
	var small: int = GameLoop2.spawn_to_stack(_enemy(1))
	assert_eq(_col_of(small), GameLoop2.grid_cols(), "a 1x1 spawns on the back column")
	GameLoop2.reset()
	var wide: int = GameLoop2.spawn_to_stack(_shaped(1, 1, 3))
	assert_eq(_col_of(wide), GameLoop2.grid_cols() - 2,
		"a 3-wide body starts two columns further in so its back edge touches the last column")

# The consequence of that: a long enemy reaches you in fewer games.
func test_a_longer_enemy_reaches_the_front_sooner() -> void:
	var wide: int = GameLoop2.spawn_to_stack(_shaped(2, 1, 3))
	var games: int = 0
	while _col_of(wide) > 1 and games < 10:
		_tick()
		games += 1
	assert_eq(games, GameLoop2.grid_cols() - 3,
		"a 3-wide body only has to cross the columns its front edge hasn't reached")
	assert_eq(GameState.hp, 10, "and it still gets its one game of grace at the front")
	_tick()
	assert_eq(GameState.hp, 8, "then it strikes")

func test_enemies_spawn_on_a_random_row() -> void:
	# Spawning one enemy at a time onto an empty board should not always pick the
	# same lane. (Flakes with probability grid_rows()^-19 — 1 in ~2.7e11 at 4 rows.)
	var seen: Dictionary = {}
	for i in range(20):
		GameLoop2.reset()
		var inst: int = GameLoop2.spawn_to_stack(_enemy(0))
		seen[_row_of(inst)] = true
	assert_gt(seen.size(), 1, "spawn rows vary instead of always filling row 0")
	for row in seen:
		assert_between(int(row), 0, GameLoop2.grid_rows() - 1, "and stay on the board")

# A random row, but never a DEAD one: enemies never change lanes, so a row with a
# body parked in it is a row the new arrival could never strike from. Those rows
# are skipped while any clear lane is left.
func test_spawns_pick_a_row_with_a_clear_path_to_the_player() -> void:
	# Wall off every lane but one, at the front where nothing can get past.
	var blocked: Array = [0, 1, 3]
	for row in blocked:
		GameLoop2.stack.append({"instance": 900 + row, "enemy": _enemy(0), "stun": 0,
			"health": 1, "col": 1, "row": row})
	for i in range(12):
		var inst: int = GameLoop2.spawn_to_stack(_enemy(0))
		assert_eq(_row_of(inst), 2, "spawns into the one lane that still reaches the player")
		# Take it off again so the open lane doesn't fill up during the loop.
		GameLoop2.stack.remove_at(GameLoop2._index_of(inst))

func test_a_blocked_lane_is_still_used_when_no_lane_is_clear() -> void:
	# Every row walled at the front: there is no good answer, so the enemy still
	# takes the board rather than stalling off-grid forever.
	for row in range(GameLoop2.grid_rows()):
		GameLoop2.stack.append({"instance": 900 + row, "enemy": _enemy(0), "stun": 0,
			"health": 1, "col": 1, "row": row})
	var inst: int = GameLoop2.spawn_to_stack(_enemy(0))
	assert_eq(GameLoop2.offgrid_count(), 0, "it still finds somewhere to stand")
	assert_between(_row_of(inst), 0, GameLoop2.grid_rows() - 1, "on the board")

# When NO lane is completely clear, take the emptiest one rather than treating
# every option as equally hopeless. This is the board from the Beholster report: a
# 2x2 whose only two standable rows are both obstructed, one by a single enemy and
# one by two.
func test_a_big_enemy_takes_the_lane_with_the_fewest_bodies_in_the_way() -> void:
	GameLoop2.stack = [
		# Row 0 column 3 — blocks a 2x2 from standing at row 0 at all.
		{"instance": 951, "enemy": _enemy(0), "stun": 0, "health": 1, "col": 3, "row": 0},
		# Row 2 column 2 — in the way of a 2x2 entering at row 1 OR row 2.
		{"instance": 952, "enemy": _enemy(0), "stun": 0, "health": 1, "col": 2, "row": 2},
		# Row 3 column 1 — only in the way of one entering at row 2.
		{"instance": 953, "enemy": _enemy(0), "stun": 0, "health": 1, "col": 1, "row": 3},
	]
	var big: GoalEnemyData = _shaped(3, 2, 2)
	assert_eq(int(GameLoop2.path_blockers(big, 1, GameLoop2.grid_cols() - 1)["enemies"]), 1,
		"entering a row up, it only has to outlive one body")
	assert_eq(int(GameLoop2.path_blockers(big, 2, GameLoop2.grid_cols() - 1)["enemies"]), 2,
		"a row down, it is stuck behind two")
	for i in range(12):
		var inst: int = GameLoop2.spawn_to_stack(big)
		assert_eq(_row_of(inst), 1, "so it spawns one row up, in the emptier lane")
		GameLoop2.stack.remove_at(GameLoop2._index_of(inst))

# Ties are still random — "emptiest lane" must not collapse into "always row 0".
func test_equally_clear_lanes_are_still_chosen_at_random() -> void:
	var seen: Dictionary = {}
	for i in range(20):
		GameLoop2.reset()
		seen[_row_of(GameLoop2.spawn_to_stack(_shaped(0, 2, 2)))] = true
	assert_gt(seen.size(), 1, "an empty board offers several equally good rows")

# The path check is footprint-aware: a body only needs the lanes its own cells
# will pass through.
func test_path_check_uses_the_whole_footprint() -> void:
	# A 1x1 sitting at the front of row 1.
	GameLoop2.stack = [{"instance": 901, "enemy": _enemy(0), "stun": 0, "health": 1,
		"col": 1, "row": 1}]
	var tall: GoalEnemyData = _shaped(0, 2, 1)      # two rows tall, one column wide
	assert_false(GameLoop2.has_clear_path(tall, 0, GameLoop2.grid_cols()),
		"a 2-tall body starting at row 0 would drag its lower half into the blocked lane")
	assert_true(GameLoop2.has_clear_path(tall, 2, GameLoop2.grid_cols()),
		"but rows 2-3 are clear all the way in")

func test_spawn_column_overflows_to_off_grid_when_full() -> void:
	for i in range(GameLoop2.grid_rows()):
		GameLoop2.spawn_to_stack(_enemy(0))
	assert_eq(GameLoop2.offgrid_count(), 0, "the spawn column holds grid_rows() enemies")
	GameLoop2.spawn_to_stack(_enemy(0))
	assert_eq(GameLoop2.offgrid_count(), 1, "the next enemy waits off-grid")

func test_full_front_column_stalls_the_queue() -> void:
	# Six enemies converging on a grid_rows()-wide front column.
	for i in range(6):
		GameLoop2.spawn_to_stack(_enemy(0))
	assert_eq(GameLoop2.offgrid_count(), 6 - GameLoop2.grid_rows(), "two overflow the spawn column")
	# March forward; the front column caps attackers at grid_rows() and the rest jam.
	for i in range(12):
		_tick()
	var front: int = 0
	for e in GameLoop2.stack:
		if int(e["col"]) == 1:
			front += 1
	assert_eq(front, GameLoop2.grid_rows(), "no more than grid_rows() enemies pack the front")
	assert_eq(GameLoop2.stack_size(), 6, "the jammed enemies are still on the field")
	assert_eq(GameLoop2.offgrid_count(), 0, "the off-grid queue has slid onto the grid")

# --- footprints: a big body is a wall (§grid) -----------------------------

# A multi-cell enemy occupies every cell of its footprint, so a smaller one can't
# walk through it — it stalls in the column behind and waits.
func test_a_wide_enemy_blocks_a_smaller_one_behind_it() -> void:
	# A 1x2 body parked at the front of row 0, and a 1x1 directly behind it.
	var wall := {"instance": 91, "enemy": _shaped(0, 1, 2), "stun": 0, "health": 1,
		"col": 1, "row": 0}
	var runt := {"instance": 92, "enemy": _enemy(0), "stun": 0, "health": 1,
		"col": 3, "row": 0}
	GameLoop2.stack = [wall, runt]
	_tick()
	assert_eq(_col_of(92), 3, "column 2 is the wall's back half — the runt can't enter it")
	assert_eq(_col_of(91), 1, "and the wall is already as far forward as it goes")

# The L's notch is a real gap: a 1x1 fits into the empty corner of its bounding
# box, but not into any cell the L actually fills.
func test_the_l_shape_blocks_its_solid_cells_but_not_its_notch() -> void:
	var bastion := {"instance": 81, "enemy": _bastion(3), "stun": 0, "health": 1,
		"col": 1, "row": 0}
	GameLoop2.stack = [bastion]
	var runt: GoalEnemyData = _enemy(0)
	# Row 0 columns 1-2 are the notch above the L's base; column 3 of row 0 is solid.
	assert_true(GameLoop2.fits_at(runt, 0, 1), "the notch is standable")
	assert_true(GameLoop2.fits_at(runt, 0, 2), "so is the rest of the notch")
	assert_false(GameLoop2.fits_at(runt, 0, 3), "the L's raised back corner is solid")
	assert_false(GameLoop2.fits_at(runt, 1, 1), "and its whole base row is solid")
	assert_false(GameLoop2.fits_at(runt, 1, 2))
	assert_false(GameLoop2.fits_at(runt, 1, 3))

# An enemy only steps forward when its ENTIRE footprint clears, so the L cannot
# slide over a body tucked into the lane its base needs.
func test_a_shaped_enemy_needs_its_whole_footprint_clear_to_advance() -> void:
	var bastion := {"instance": 81, "enemy": _bastion(0), "stun": 0, "health": 1,
		"col": 2, "row": 0}
	# A 1x1 sitting in row 1 column 1 — dead ahead of the L's base row.
	var blocker := {"instance": 82, "enemy": _enemy(0), "stun": 0, "health": 1,
		"col": 1, "row": 1}
	GameLoop2.stack = [bastion, blocker]
	_tick()
	assert_eq(_col_of(81), 2, "the L is held up by the body in front of its base")
	# Clear the blocker and it walks on.
	GameLoop2.stack = [bastion]
	_tick()
	assert_eq(_col_of(81), 1, "with the lane clear it closes as normal")

# An enemy strikes as soon as ANY of its cells is in the front column — the
# reason a long body hurts sooner than a compact one.
func test_any_cell_in_the_front_column_counts_as_the_front_line() -> void:
	var wide := {"instance": 71, "enemy": _shaped(4, 1, 3), "stun": 0, "health": 1,
		"col": 1, "row": 0}
	GameLoop2.stack = [wide]
	assert_eq(GameLoop2.front_count(), 1, "its leading cell is in column 1")
	assert_eq(GameLoop2.stacked_damage_per_game(), 4)
	_tick()
	assert_eq(GameState.hp, 6, "so it strikes even though most of it is further back")

# --- shields absorb before hp, then expire with the game (§3.2) -----------
#
# Shields belong to the game in play, so these set them just before the resolve
# that takes the hit — exactly where a selection grant would have put them.

func test_shields_absorb_the_front_line_before_hp() -> void:
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # spawn col
	_march_to_front(a)
	GameState.shields = 3
	_tick()                                                        # 2 dmg -> shields
	assert_eq(GameState.hp, 10, "the shields ate the hit")
	assert_eq(int(GameLoop2.last_result["blocked"]), 2, "the resolve reports what they absorbed")
	assert_eq(GameState.shields, 0, "and whatever survived expired with the game")
	assert_eq(int(GameLoop2.last_result["shields_expired"]), 1, "the leftover is reported too")

func test_shield_overflow_hits_hp() -> void:
	var a: int = GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)  # spawn col
	_march_to_front(a)
	GameState.shields = 1
	_tick()                                                        # 3 dmg: 1 shield, 2 hp
	assert_eq(GameState.shields, 0)
	assert_eq(GameState.hp, 8)

func test_unspent_shields_do_not_carry_into_the_next_game() -> void:
	GameLoop2.choose_game(_enemy(1))
	GameState.shields = 4
	GameLoop2.beat_game(true)          # nothing on the stack yet -> nothing to absorb
	assert_eq(GameState.shields, 0, "the game they belonged to is over")
	assert_eq(int(GameLoop2.last_result["shields_expired"]), 4)

# --- shields granted on selection (§3.2) ----------------------------------

func _game_of_type(t: int) -> GameData:
	var g := GameData.new()
	g.id = &"synthetic_game"
	g.display_name = "Synthetic Game"
	g.type = t
	return g

func test_selection_grants_three_shields_and_five_for_traditional() -> void:
	assert_eq(GameLoop2.shields_for_game(_game_of_type(GameData.GameType.ACTION)), 3)
	assert_eq(GameLoop2.shields_for_game(_game_of_type(GameData.GameType.STRATEGY)), 3)
	assert_eq(GameLoop2.shields_for_game(_game_of_type(GameData.GameType.DECKBUILDER)), 3)
	assert_eq(GameLoop2.shields_for_game(_game_of_type(GameData.GameType.TRADITIONAL)), 5,
		"a Traditional roguelike is the long haul")

func test_grant_selection_shields_adds_and_announces() -> void:
	watch_signals(TriggerBus)
	assert_eq(GameState.shields, 0)
	var n: int = GameLoop2.grant_selection_shields(_game_of_type(GameData.GameType.TRADITIONAL))
	assert_eq(n, 5, "the grant is reported back")
	assert_eq(GameState.shields, 5)
	assert_signal_emitted(TriggerBus, "game_selected",
		"items hooked on selection (Anchor) get their chance")

# --- the attempt tracker (§3.2) -------------------------------------------

func test_each_attempt_spends_a_shield_then_health() -> void:
	GameLoop2.choose_game(_enemy(1))
	GameState.shields = 2
	assert_eq(GameLoop2.log_attempt(), "shield", "a lost run spends a shield first")
	assert_eq(GameState.shields, 1)
	assert_eq(GameLoop2.log_attempt(), "shield")
	assert_eq(GameState.shields, 0)
	assert_eq(GameState.hp, 10, "Health is untouched while shields last")
	assert_eq(GameLoop2.log_attempt(), "health", "out of shields, a lost run costs Health")
	assert_eq(GameState.hp, 10 - GameLoop2.ATTEMPT_HEALTH_COST)
	assert_eq(GameLoop2.attempts(), 3, "every try is counted")
	assert_eq(GameLoop2.attempts_on_shields(), 2, "two of them were paid with shields")

func test_attempts_can_kill_the_run() -> void:
	GameLoop2.choose_game(_enemy(1))
	GameState.shields = 0
	GameState.hp = 2
	watch_signals(GameLoop2)
	GameLoop2.log_attempt()
	assert_false(GameLoop2.run_over, "one Health left is still a run")
	GameLoop2.log_attempt()
	assert_eq(GameState.hp, 0)
	assert_true(GameLoop2.run_over, "losing the last Health to a retry ends the run")
	assert_signal_emitted(GameLoop2, "run_lost")
	assert_eq(GameLoop2.log_attempt(), "", "and no further tries are logged")

func test_undo_attempt_refunds_exactly_what_it_spent() -> void:
	GameLoop2.choose_game(_enemy(1))
	GameState.shields = 1
	GameLoop2.log_attempt()                       # spends the shield
	GameLoop2.log_attempt()                       # spends Health
	assert_eq(GameState.shields, 0)
	assert_eq(GameState.hp, 10 - GameLoop2.ATTEMPT_HEALTH_COST)
	assert_eq(GameLoop2.undo_attempt(), "health")
	assert_eq(GameState.hp, 10, "the Health comes back")
	assert_eq(GameLoop2.undo_attempt(), "shield")
	assert_eq(GameState.shields, 1, "and so does the shield")
	assert_eq(GameLoop2.attempts(), 0)
	assert_eq(GameLoop2.undo_attempt(), "", "nothing left to take back")

func test_attempts_are_per_game() -> void:
	GameLoop2.choose_game(_enemy(1))
	GameState.shields = 3
	GameLoop2.log_attempt()
	assert_eq(GameLoop2.attempts(), 1)
	var res: Dictionary = GameLoop2.beat_game(true)
	assert_eq(int(res["attempts"]), 1, "the resolve reports what the game took")
	assert_eq(GameLoop2.attempts(), 0, "and the tracker closes with the game")
	GameLoop2.choose_game(_enemy(1))
	assert_eq(GameLoop2.attempts(), 0, "a new game starts on a clean tracker")

func test_attempts_need_a_game_in_play() -> void:
	GameState.shields = 3
	assert_eq(GameLoop2.log_attempt(), "", "there is nothing to be losing runs of")
	assert_eq(GameState.shields, 3)

# --- old-goal fulfilment (§2) --------------------------------------------

func test_fulfilling_old_goal_defeats_and_prevents_its_attack() -> void:
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)
	# Next game: fulfil A's old goal while beating this game.
	GameLoop2.choose_game(_enemy(0))
	var res: Dictionary = GameLoop2.beat_game(false, [a])
	assert_eq(GameState.hp, 10, "a fulfilled enemy never lands its hit")
	assert_eq(int(res["drops"]), 1, "fulfilment drops its item (inline)")
	assert_eq(GameLoop2.defeated_count, 1)
	# Only the current (failed) enemy remains on the stack.
	assert_eq(GameLoop2.stack_size(), 1)

# --- stun (§4.1 / §7.2) ---------------------------------------------------

func test_stun_skips_the_next_attack_only() -> void:
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # spawn col
	_march_to_front(a)
	assert_eq(_col_of(a), 1)
	GameLoop2.stun(a)                                         # freeze its first strike
	_tick()                                                  # A stunned, holds fire
	assert_eq(GameState.hp, 10, "stun skips A's first strike")
	_tick()                                                  # A strikes now
	assert_eq(GameState.hp, 8)

# --- push (Manager's verb, §7.2) ------------------------------------------

func test_push_shoves_the_enemy_back_a_column_and_spends_a_charge() -> void:
	GameState.push = 1
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # spawn col
	_march_to_front(a)
	assert_eq(_col_of(a), 1)
	assert_true(GameLoop2.push(a), "push a front-line enemy back a column")
	assert_eq(GameState.push, 0, "push is spent")
	assert_eq(_col_of(a), 2, "shoved from the front back to column 2")
	_tick()                                                  # A closes back to col 1, no strike
	assert_eq(GameState.hp, 10, "the pushed enemy is out of melee this game")
	_tick()                                                  # A strikes now
	assert_eq(GameState.hp, 8)

func test_push_needs_a_free_cell_behind_the_target() -> void:
	GameState.push = 3
	# Walk one enemy to the front, THEN pack the column behind it.
	var a: int = GameLoop2.spawn_to_stack(_enemy(0))
	_march_to_front(a)
	assert_eq(_col_of(a), 1, "A is at the front")
	for i in range(GameLoop2.grid_rows()):
		GameLoop2.spawn_to_stack(_enemy(0))
	# Walk the fresh spawns up until they fill the column right behind A.
	while _count_in_col(2) < GameLoop2.grid_rows():
		_tick()
	assert_false(GameLoop2.can_push(a), "column 2 is packed — nowhere to shove A")
	assert_false(GameLoop2.push(a), "a blocked push fails")
	assert_eq(GameState.push, 3, "a blocked push spends nothing")
	assert_eq(_col_of(a), 1, "A hasn't moved")

func test_push_fails_at_the_back_column() -> void:
	GameState.push = 1
	var a: int = GameLoop2.spawn_to_stack(_enemy(1))
	assert_eq(_col_of(a), GameLoop2.spawn_col())
	assert_false(GameLoop2.can_push(a), "already as far back as the grid goes")
	assert_false(GameLoop2.push(a))
	assert_eq(GameState.push, 1, "the charge is kept")

func test_push_requires_a_charge() -> void:
	GameState.push = 0
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # spawn col
	_march_to_front(a)
	assert_false(GameLoop2.push(a), "no push without a charge")
	assert_eq(_col_of(a), 1, "an un-pushed enemy holds its ground")
	_tick()                                                  # A strikes on schedule
	assert_eq(GameState.hp, 8, "an un-pushed enemy strikes on schedule")

# --- bomb (§4 / §7.1) -----------------------------------------------------

func test_bomb_removes_normal_enemy_without_drop() -> void:
	var chests_before: int = GameState.pending_chests
	GameState.bombs = 1
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)
	assert_true(GameLoop2.bomb(a))
	assert_eq(GameLoop2.stack_size(), 0)
	assert_eq(GameState.bombs, 0, "bomb is spent")
	assert_eq(GameState.pending_chests, chests_before, "bombing drops nothing")

func test_bomb_cannot_kill_a_boss() -> void:
	# A boss IS a legal target (that's how Sticky Bombs reaches one) — it just
	# takes none of the damage, so the charge goes and the boss stays.
	GameState.bombs = 1
	var b: int = GameLoop2.choose_game(_enemy(3, true)) ; GameLoop2.beat_game(false)
	assert_true(GameLoop2.bomb(b), "a boss can be bombed")
	assert_eq(GameLoop2.stack_size(), 1, "the boss shrugs off the blast")
	assert_eq(GameState.bombs, 0, "the charge is spent either way")

func test_bomb_only_deals_one_damage() -> void:
	# Normal enemies have Health 1, so one bomb clears one — but an Alien-Baby
	# buffed two-Health enemy survives its first (docs §4: bombs deal 1 damage).
	GameState.bombs = 2
	var e: GoalEnemyData = _enemy(2)
	e.health = 2
	var a: int = GameLoop2.choose_game(e) ; GameLoop2.beat_game(false)
	assert_true(GameLoop2.bomb(a))
	assert_eq(GameLoop2.stack_size(), 1, "a two-Health enemy survives one bomb")
	assert_true(GameLoop2.bomb(a))
	assert_eq(GameLoop2.stack_size(), 0, "the second bomb finishes it")

func test_bomb_requires_a_charge() -> void:
	GameState.bombs = 0
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)
	assert_false(GameLoop2.bomb(a))
	assert_eq(GameLoop2.stack_size(), 1)

func test_bomb_fires_the_bomb_used_trigger_once() -> void:
	# Blood Bombs hangs +1 Health here, so the hook must fire once per BOMB, not
	# once per body the blast touched.
	watch_signals(TriggerBus)
	GameState.bombs = 1
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)
	assert_true(GameLoop2.bomb(a))
	assert_signal_emit_count(TriggerBus, "bomb_used", 1)

# --- bomb-modifying items (§8) --------------------------------------------

func test_sticky_bombs_stun_what_the_blast_cannot_kill() -> void:
	GameState.add_item(Data.get_item2(&"sticky_bombs"))
	GameState.bombs = 1
	var b: int = GameLoop2.choose_game(_enemy(3, true)) ; GameLoop2.beat_game(false)
	assert_true(GameLoop2.bomb(b))
	assert_eq(int(_entry(b).get("stun", 0)), 1,
		"the boss survives the blast and is stunned by it")

# Park a 1x1 enemy on an exact cell, so a blast-shape assertion doesn't depend on
# where the random spawn rows happened to put things.
func _park(row: int, col: int) -> int:
	var inst: int = GameLoop2.spawn_to_stack(_enemy(1))
	var entry: Dictionary = _entry(inst)
	entry["row"] = row
	entry["col"] = col
	return inst

func test_brimstone_bombs_blast_the_row_and_column() -> void:
	GameState.add_item(Data.get_item2(&"brimstone_bombs"))
	GameState.bombs = 1
	var a: int = _park(0, 1)          # the target
	var same_row: int = _park(0, 3)
	var same_col: int = _park(2, 1)
	var neither: int = _park(2, 3)
	assert_true(GameLoop2.bomb(a))
	assert_eq(_col_of(a), -1, "the target dies")
	assert_eq(_col_of(same_row), -1, "so does everything down its row")
	assert_eq(_col_of(same_col), -1, "and everything down its column")
	assert_eq(_col_of(neither), 3, "a body off both lines is untouched")
	assert_eq(GameState.bombs, 0, "still just the one charge")

func test_a_plain_bomb_only_hits_its_target() -> void:
	GameState.bombs = 1
	var a: int = _park(0, 1)
	var same_row: int = _park(0, 3)
	assert_true(GameLoop2.bomb(a))
	assert_eq(_col_of(a), -1)
	assert_eq(_col_of(same_row), 3, "without Brimstone the blast is one body")

func test_barricade_banks_unspent_shields() -> void:
	GameState.shields = 4
	var _a: int = GameLoop2.choose_game(_enemy(1))
	GameLoop2.beat_game(true)
	assert_eq(GameState.shields, 0, "shields normally expire with the game")
	GameLoop2.reset()
	GameState.add_item(Data.get_item2(&"barricade"))
	GameState.shields = 4
	var _b: int = GameLoop2.choose_game(_enemy(1))
	GameLoop2.beat_game(true)
	assert_eq(GameState.shields, 4, "Barricade rolls them into the next game")

# --- Mine-r Construction: the board grows (§7.3) --------------------------

func _minor() -> ItemData:
	return Data.get_item2(&"mine_r_construction")

func test_the_board_is_four_by_four_until_something_grows_it() -> void:
	assert_eq(GameLoop2.grid_cols(), 4)
	assert_eq(GameLoop2.grid_rows(), 4)
	assert_eq(GameLoop2.spawn_col(), 4, "the back column is the last one")
	assert_eq(GameLoop2.offgrid_col(), 5, "and the queue waits one past it")

func test_mine_r_construction_adds_a_column_and_a_row() -> void:
	GameState.add_item(_minor())
	assert_eq(GameLoop2.grid_cols(), 5, "one more column of distance to cross")
	assert_eq(GameLoop2.grid_rows(), 5, "and one more lane to stand in")
	assert_eq(GameLoop2.offgrid_col(), 6, "the queue moves out with the edge")

func test_copies_of_mine_r_construction_stack() -> void:
	GameState.add_item(_minor())
	GameState.add_item(_minor())
	assert_eq(GameLoop2.grid_cols(), 6)
	assert_eq(GameLoop2.grid_rows(), 6)

func test_losing_mine_r_construction_takes_the_column_back() -> void:
	var inst: ItemData = GameState.add_item(_minor())
	GameState.remove_item(inst)
	assert_eq(GameLoop2.grid_cols(), 4)
	assert_eq(GameLoop2.grid_rows(), 4)

func test_a_grown_board_spawns_enemies_a_column_further_out() -> void:
	GameState.add_item(_minor())
	var a: int = GameLoop2.choose_game(_enemy(1))
	GameLoop2.beat_game(false)
	assert_eq(_col_of(a), 5, "the new back column is where it walks on")

func test_growing_the_board_buys_a_game_of_distance() -> void:
	# The enemy already standing on the board keeps its column — the board grew
	# behind it, it did not get pushed back — so the gain is for what spawns next.
	var a: int = GameLoop2.choose_game(_enemy(1))
	GameLoop2.beat_game(false)
	assert_eq(_col_of(a), 4)
	GameState.add_item(_minor())
	assert_eq(_col_of(a), 4, "the bodies on the board stay where they stand")
	var b: int = GameLoop2.choose_game(_enemy(1))
	GameLoop2.beat_game(false)
	assert_eq(_col_of(b), 5, "the newcomer starts a column further out")

func test_the_queue_walks_onto_the_room_the_growth_made() -> void:
	# Fill the back column, then jam one more enemy behind it: with 4 lanes the
	# fifth has nowhere to stand and waits off-grid.
	for _i in range(GameLoop2.grid_rows()):
		GameLoop2.spawn_to_stack(_enemy(1))
	var waiting: int = GameLoop2.spawn_to_stack(_enemy(1))
	assert_eq(_col_of(waiting), GameLoop2.offgrid_col(), "no lane left for it")
	assert_eq(GameLoop2.offgrid_count(), 1)
	GameState.add_item(_minor())
	assert_eq(GameLoop2.offgrid_count(), 0,
		"the new lane is somewhere to stand, so it walks straight on")
	assert_lte(_col_of(waiting), GameLoop2.grid_cols(), "and it is on the board")

func test_shrinking_the_board_re_seats_a_body_it_no_longer_holds() -> void:
	var item: ItemData = GameState.add_item(_minor())
	var a: int = GameLoop2.spawn_to_stack(_enemy(1))
	assert_eq(_col_of(a), 5, "standing on the column the item added")
	GameState.remove_item(item)
	assert_lte(_col_of(a), GameLoop2.grid_cols(),
		"losing the item cannot leave it standing off the edge of the board")

# --- loss / run-over ------------------------------------------------------

func test_lethal_hit_ends_the_run() -> void:
	watch_signals(GameLoop2)
	GameState.hp = 2
	var a: int = GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)  # spawn col
	_march_to_front(a)
	_tick()                                                       # 3 dmg -> dead
	assert_eq(GameState.hp, 0)
	assert_true(GameLoop2.run_over)
	assert_false(GameLoop2.won)
	assert_signal_emitted(GameLoop2, "run_lost")

func test_no_resolution_after_run_over() -> void:
	GameState.hp = 1
	var a: int = GameLoop2.choose_game(_enemy(5)) ; GameLoop2.beat_game(false)  # spawn col
	_march_to_front(a)
	_tick()                                                       # lethal
	assert_true(GameLoop2.run_over)
	var beaten_before: int = GameLoop2.games_beaten
	GameLoop2.choose_game(_enemy(5)) ; GameLoop2.beat_game(false)
	assert_eq(GameLoop2.games_beaten, beaten_before, "beat_game is a no-op after loss")

# --- win ------------------------------------------------------------------

func test_clear_amulet_wins() -> void:
	watch_signals(GameLoop2)
	GameLoop2.choose_game(_enemy(1))
	GameLoop2.clear_amulet()
	assert_true(GameLoop2.won)
	assert_true(GameLoop2.run_over)
	assert_false(GameLoop2.has_current())
	assert_eq(GameLoop2.defeated_count, 1, "the amulet enemy is defeated (drops inline)")
	assert_signal_emitted(GameLoop2, "run_won")

# --- spawn_to_stack (Scroll of Create Monster, §4.1) ----------------------

func test_spawn_to_stack_adds_a_following_enemy() -> void:
	var inst: int = GameLoop2.spawn_to_stack(_enemy(2))
	assert_gt(inst, 0)
	assert_eq(GameLoop2.stack_size(), 1)
	assert_eq(_col_of(inst), GameLoop2.spawn_col(), "conjured at the back column")
	# Like any spawn, it closes in and only strikes once it reaches the front.
	_march_to_front(inst)
	assert_eq(_col_of(inst), 1)
	assert_eq(GameState.hp, 10, "closing in costs nothing")
	_tick()                             # strikes for 2
	assert_eq(GameState.hp, 8, "the conjured enemy hits for 2 once at the front")

# --- aggravate (Scroll of Aggravate Monsters, §4.1) -----------------------

func test_aggravate_adds_damage_for_n_games_then_expires() -> void:
	var a: int = GameLoop2.choose_game(_enemy(1)) ; GameLoop2.beat_game(false)  # A(1) spawn col
	_march_to_front(a)
	GameLoop2.aggravate(2, 1)                                       # +2 for 1 game
	assert_eq(GameLoop2.stacked_damage_per_game(), 3, "1 base + 2 aggravate at the front")
	_tick()                                                        # A hits 1+2=3
	assert_eq(GameState.hp, 7)
	# The buff lasted one game; the next hit is the base damage again.
	assert_eq(GameLoop2.enemy_damage_bonus_games, 0, "aggravate expired")
	_tick()                                                        # A hits 1
	assert_eq(GameState.hp, 6)

# --- stacked-damage preview (HUD) -----------------------------------------

# Only the front column threatens damage next game; enemies still closing in do
# not count toward the "front line" preview.
func test_stacked_damage_per_game_sums_the_front_column() -> void:
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # A spawn col
	var b: int = GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)  # A closes, B spawns
	_march_to_front(a)                                             # A at the front, B a column back
	assert_eq(GameLoop2.stacked_damage_per_game(), 2, "only A is at the front")
	_march_to_front(b)                                             # B joins the front line
	assert_eq(GameLoop2.stacked_damage_per_game(), 5, "A and B both at the front")

# --- board verbs: Bash / Transmute (§4) ----------------------------------

func _find_game_with_type(type_val: GameData.GameType) -> GameData:
	for g in Data.all_games():
		if g is GameData and g.type == type_val:
			return g
	return null

func test_game_type_key_maps_type() -> void:
	var db: GameData = _find_game_with_type(GameData.GameType.DECKBUILDER)
	assert_not_null(db)
	assert_eq(String(GameLoop2.game_type_key(db)), "deckbuilder")
	var trad: GameData = _find_game_with_type(GameData.GameType.TRADITIONAL)
	assert_not_null(trad)
	assert_eq(String(GameLoop2.game_type_key(trad)), "traditional")

func test_bash_removes_game_and_spends_charge() -> void:
	GameState.bash = 1
	var g: GameData = Data.all_games()[0]
	assert_true(GameLoop2.bash_game(g.id))
	assert_true(GameLoop2.is_bashed(g.id))
	assert_eq(GameState.bash, 0)
	assert_false(GameLoop2.bash_game(g.id), "already bashed / no charge")

func test_bash_requires_charge() -> void:
	GameState.bash = 0
	var g: GameData = Data.all_games()[0]
	assert_false(GameLoop2.bash_game(g.id))
	assert_false(GameLoop2.is_bashed(g.id))

func test_transmute_returns_same_type_offgraph_game() -> void:
	GameState.transmute = 1
	var db: GameData = _find_game_with_type(GameData.GameType.DECKBUILDER)
	var repl: GameData = GameLoop2.transmute_game(db.id, [db.id])
	assert_not_null(repl, "a same-type off-graph game exists")
	assert_ne(String(repl.id), String(db.id), "not the source game")
	assert_eq(String(GameLoop2.game_type_key(repl)), "deckbuilder", "same effective type")
	assert_eq(GameState.transmute, 0, "a transmute charge is spent")

func test_transmute_excludes_connected_and_bashed() -> void:
	GameState.transmute = 5
	var db: GameData = _find_game_with_type(GameData.GameType.DECKBUILDER)
	var repl: GameData = GameLoop2.transmute_game(db.id, [db.id])
	# Feed the first result back as connected + bash it; a second transmute must
	# avoid both.
	GameLoop2.bashed.append(repl.id)
	var repl2: GameData = GameLoop2.transmute_game(db.id, [db.id, repl.id])
	assert_not_null(repl2)
	assert_ne(String(repl2.id), String(repl.id), "excludes the connected/bashed game")

func test_transmute_requires_charge() -> void:
	GameState.transmute = 0
	var g: GameData = Data.all_games()[0]
	assert_null(GameLoop2.transmute_game(g.id, []))

# A Traditional game is the run's long haul — 5 tries rather than 3 — so
# transmuting one into another Traditional is no relief. It leaves the type
# instead, drawn flat from every non-Traditional game off the map.
func test_transmute_moves_a_traditional_game_off_its_type() -> void:
	GameState.transmute = 12
	var trad: GameData = _find_game_with_type(GameData.GameType.TRADITIONAL)
	for _i in range(12):
		var repl: GameData = GameLoop2.transmute_game(trad.id, [trad.id])
		assert_not_null(repl, "a non-Traditional off-graph game exists")
		assert_ne(String(GameLoop2.game_type_key(repl)), "traditional",
			"%s must not transmute into another Traditional game" % repl.display_name)
		GameLoop2.transmuted.clear()

func test_transmute_reaches_more_than_one_type_from_traditional() -> void:
	# Flat across the non-Traditional catalog, so over enough rolls it must land
	# on at least two different types rather than being pinned to one.
	GameState.transmute = 40
	var trad: GameData = _find_game_with_type(GameData.GameType.TRADITIONAL)
	var seen := {}
	for _i in range(40):
		var repl: GameData = GameLoop2.transmute_game(trad.id, [trad.id])
		if repl != null:
			seen[String(GameLoop2.game_type_key(repl))] = true
		GameLoop2.transmuted.clear()
	assert_gt(seen.size(), 1, "the roll spreads across types, got %s" % [seen.keys()])

# --- run start (loadout) --------------------------------------------------

func test_start_run_applies_isaac_loadout() -> void:
	GameLoop2.start_run(Data.get_character2(&"isaac"))
	assert_eq(GameState.max_hp, 6, "Isaac Health 6")
	assert_eq(GameState.hp, 6)
	assert_eq(GameState.bombs, 1, "Isaac starts with 1 Bomb")
	assert_eq(GameState.shields, 0)
	assert_false(GameLoop2.run_over)
	assert_eq(GameLoop2.stack_size(), 0)
	var has_d6: bool = false
	for it in GameState.inventory:
		if it is ItemData and String(it.id) == "d6":
			has_d6 = true
	assert_true(has_d6, "Isaac starts holding the D6")

func test_start_run_applies_mina_verbs() -> void:
	GameLoop2.start_run(Data.get_character2(&"min"))
	assert_eq(GameState.max_hp, 8, "Noita Health 8")
	assert_eq(GameState.transmute, 1, "Minä starts with 1 Transmute")

# --- scramble (§4) --------------------------------------------------------

func test_scramble_rerolls_current_and_spends_charge() -> void:
	GameState.scramble = 1
	var slime: GoalEnemyData = Data.get_goal_enemy(&"spike_slime_l")  # deckbuilder/low
	GameLoop2.choose_game(slime)
	var fresh: GoalEnemyData = GameLoop2.scramble()
	assert_not_null(fresh, "scramble returns a new enemy")
	assert_eq(String(fresh.game_type), "deckbuilder", "rerolled within the same type")
	assert_eq(fresh.tier_index(), slime.tier_index(), "and the same tier")
	assert_eq(GameState.scramble, 0, "a scramble charge is spent")
	assert_true(GameLoop2.has_current())

func test_scramble_requires_current_and_charge() -> void:
	GameState.scramble = 0
	GameLoop2.choose_game(_enemy(2))
	assert_null(GameLoop2.scramble(), "no charge -> no reroll")
	GameState.scramble = 1
	GameLoop2.current = {}
	assert_null(GameLoop2.scramble(), "no current game -> no reroll")
	assert_eq(GameState.scramble, 1, "a failed scramble is not spent")

func test_choose_game_of_type_rolls_and_sets_current() -> void:
	var e: GoalEnemyData = GameLoop2.choose_game_of_type(&"action", GoalEnemyData.Difficulty.LOW)
	assert_not_null(e, "a roll returns an enemy")
	assert_eq(String(e.game_type), "action", "rolled an action-type enemy")
	assert_eq(e.tier_index(), 0, "rolled at the Low tier")
	assert_false(e.is_boss(), "a normal roll is not a boss")
	assert_true(GameLoop2.has_current())

# --- enemy roll by type + tier (§7) --------------------------------------

func test_roll_enemy_matches_type_and_tier() -> void:
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"deckbuilder", GoalEnemyData.Difficulty.LOW)
	assert_not_null(e)
	assert_eq(String(e.game_type), "deckbuilder")
	assert_eq(e.tier_index(), 0)

func test_roll_enemy_action_low_matches_type_and_tier() -> void:
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"action", GoalEnemyData.Difficulty.LOW)
	assert_not_null(e)
	assert_eq(String(e.game_type), "action")
	assert_eq(e.tier_index(), 0)

func test_roll_enemy_traditional_matches_type_and_tier() -> void:
	# Traditional is the fourth type (the NetHack/Rogue roster); it used to have
	# no enemies at all and relied on the widened filter.
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"traditional", GoalEnemyData.Difficulty.LOW)
	assert_not_null(e)
	assert_eq(String(e.game_type), "traditional")
	assert_eq(e.tier_index(), 0)

func test_roll_enemy_widens_when_the_tier_is_empty() -> void:
	# Nothing is authored at Traditional/Insane — the roll must still return an
	# enemy rather than null (widened filter).
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"traditional", GoalEnemyData.Difficulty.INSANE)
	assert_not_null(e)
	assert_eq(String(e.game_type), "traditional", "widens on tier before type")

func test_roll_enemy_never_returns_a_boss() -> void:
	# The normal-enemy pool must exclude bosses (they roll from a separate pool).
	for i in range(20):
		var e: GoalEnemyData = GameLoop2.roll_enemy(&"", i % 3)
		assert_false(e.is_boss(), "%s is a boss and should not roll as a normal enemy" % e.id)

# --- bosses (§7.1) --------------------------------------------------------

func test_bosses_load_and_flag() -> void:
	assert_eq(Data.all_bosses().size(), _tres_count("res://data/bosses2.0/"), "every bosses2.0 .tres loads")
	for b in Data.all_bosses():
		assert_true(b.is_boss(), "%s should be flagged boss" % b.id)

func test_time_eater_boss_fields() -> void:
	var b: GoalEnemyData = Data.get_boss(&"time_eater")
	assert_not_null(b)
	assert_true(b.is_boss())
	assert_eq(String(b.game_type), "deckbuilder")
	assert_eq(int(b.difficulty), int(GoalEnemyData.Difficulty.HIGH))
	assert_eq(b.damage, 7, "bosses hit above the 1-3 band")
	assert_eq(String(b.goal_type), "restriction")

func test_the_creator_is_insane_tier() -> void:
	var b: GoalEnemyData = Data.get_boss(&"the_creator")
	assert_eq(int(b.difficulty), int(GoalEnemyData.Difficulty.INSANE))
	assert_eq(b.tier_index(), 3)
	assert_eq(b.damage, 9)

func test_roll_boss_returns_a_boss() -> void:
	var b: GoalEnemyData = GameLoop2.roll_boss(&"", GoalEnemyData.Difficulty.HIGH)
	assert_not_null(b)
	assert_true(b.is_boss())
	assert_eq(b.tier_index(), 2)

func test_roll_boss_reaches_insane_tier() -> void:
	var b: GoalEnemyData = GameLoop2.roll_boss(&"strategy", GoalEnemyData.Difficulty.INSANE)
	assert_not_null(b)
	assert_eq(b.tier_index(), 3, "The Creator is the Insane-tier Strategy boss")

func test_real_boss_takes_no_bomb_damage() -> void:
	GameState.bombs = 3
	var b: GoalEnemyData = GameLoop2.roll_boss(&"", GoalEnemyData.Difficulty.HIGH)
	var inst: int = GameLoop2.choose_game(b)
	GameLoop2.beat_game(false)   # boss stacks
	assert_true(GameLoop2.bomb(inst), "a real boss is a legal bomb target")
	assert_eq(GameState.bombs, 2, "the charge is spent")
	assert_eq(GameLoop2.stack_size(), 1, "but the boss takes no damage from it")

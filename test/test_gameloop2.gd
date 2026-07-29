extends GutTest

# Tests for the games-first loop resolver (GameLoop2) — the enemy-stack state
# machine, the one-game grace timing (§7.2), block-then-hp damage (§3), drops on
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
	GameState.block = 0

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

# The grid column a stacked enemy currently occupies (1 = front/melee,
# GRID_COLS = spawn, OFFGRID_COL = off-grid queue), or -1 if it's gone.
func _col_of(instance: int) -> int:
	for e in GameLoop2.stack:
		if int(e["instance"]) == instance:
			return int(e.get("col", -1))
	return -1

# Beat a game with no chosen enemy: this just advances the grid one column and
# lets the front line strike — the clean way to march a stacked enemy forward in
# a test without spawning clutter enemies.
func _tick() -> void:
	GameLoop2.beat_game(false)

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
	assert_eq(_col_of(a), GameLoop2.SPAWN_COL, "spawns at the back")
	assert_eq(GameState.hp, 10, "the back column can't strike")
	_tick()                                          # A -> col 2
	assert_eq(_col_of(a), 2)
	assert_eq(GameState.hp, 10)
	_tick()                                          # A -> col 1 (front), no strike yet
	assert_eq(_col_of(a), 1)
	assert_eq(GameState.hp, 10, "reaches the front but strikes next game")
	_tick()                                          # A strikes for 2
	assert_eq(GameState.hp, 8)

# --- grid: advance / stall / overflow (§grid) ----------------------------

func test_enemy_closes_one_column_per_game() -> void:
	var a: int = GameLoop2.choose_game(_enemy(1)) ; GameLoop2.beat_game(false)
	assert_eq(_col_of(a), GameLoop2.SPAWN_COL, "spawns at the back column")
	_tick()
	assert_eq(_col_of(a), 2, "closes one column per game")
	_tick()
	assert_eq(_col_of(a), 1, "reaches the front")
	_tick()
	assert_eq(_col_of(a), 1, "cannot advance past the front")

func test_spawn_column_overflows_to_off_grid_when_full() -> void:
	for i in range(GameLoop2.GRID_ROWS):
		GameLoop2.spawn_to_stack(_enemy(0))
	assert_eq(GameLoop2.offgrid_count(), 0, "the spawn column holds GRID_ROWS enemies")
	GameLoop2.spawn_to_stack(_enemy(0))
	assert_eq(GameLoop2.offgrid_count(), 1, "the next enemy waits off-grid")

func test_full_front_column_stalls_the_queue() -> void:
	# Six enemies converging on a GRID_ROWS-wide front column.
	for i in range(6):
		GameLoop2.spawn_to_stack(_enemy(0))
	assert_eq(GameLoop2.offgrid_count(), 6 - GameLoop2.GRID_ROWS, "two overflow the spawn column")
	# March forward; the front column caps attackers at GRID_ROWS and the rest jam.
	for i in range(8):
		_tick()
	var front: int = 0
	for e in GameLoop2.stack:
		if int(e["col"]) == 1:
			front += 1
	assert_eq(front, GameLoop2.GRID_ROWS, "no more than GRID_ROWS enemies pack the front")
	assert_eq(GameLoop2.stack_size(), 6, "the jammed enemies are still on the field")
	assert_eq(GameLoop2.offgrid_count(), 0, "the off-grid queue has slid onto the grid")

# --- block absorbs before hp (§3) ----------------------------------------

func test_block_absorbs_first() -> void:
	GameState.block = 3
	GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)   # spawn col
	_tick() ; _tick()                                              # march to the front
	_tick()                                                        # 2 dmg -> block
	assert_eq(GameState.block, 1)
	assert_eq(GameState.hp, 10)

func test_block_overflow_hits_hp() -> void:
	GameState.block = 1
	GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)   # spawn col
	_tick() ; _tick()                                              # march to the front
	_tick()                                                        # 3 dmg: 1 blk, 2 hp
	assert_eq(GameState.block, 0)
	assert_eq(GameState.hp, 8)

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
	_tick() ; _tick()                                        # march A to the front
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
	_tick() ; _tick()                                        # march A to the front
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
	_tick() ; _tick()                              # A: spawn col -> col 2 -> col 1
	assert_eq(_col_of(a), 1, "A is at the front")
	for i in range(GameLoop2.GRID_ROWS):
		GameLoop2.spawn_to_stack(_enemy(0))
	_tick()                                        # the four spawns fill column 2
	assert_false(GameLoop2.can_push(a), "column 2 is packed — nowhere to shove A")
	assert_false(GameLoop2.push(a), "a blocked push fails")
	assert_eq(GameState.push, 3, "a blocked push spends nothing")
	assert_eq(_col_of(a), 1, "A hasn't moved")

func test_push_fails_at_the_back_column() -> void:
	GameState.push = 1
	var a: int = GameLoop2.spawn_to_stack(_enemy(1))
	assert_eq(_col_of(a), GameLoop2.SPAWN_COL)
	assert_false(GameLoop2.can_push(a), "already as far back as the grid goes")
	assert_false(GameLoop2.push(a))
	assert_eq(GameState.push, 1, "the charge is kept")

func test_push_requires_a_charge() -> void:
	GameState.push = 0
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # spawn col
	_tick() ; _tick()                                        # march A to the front
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
	GameState.bombs = 1
	var b: int = GameLoop2.choose_game(_enemy(3, true)) ; GameLoop2.beat_game(false)
	assert_false(GameLoop2.bomb(b), "bosses are bomb-immune")
	assert_eq(GameLoop2.stack_size(), 1)
	assert_eq(GameState.bombs, 1, "a failed bomb is not spent")

func test_bomb_requires_a_charge() -> void:
	GameState.bombs = 0
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)
	assert_false(GameLoop2.bomb(a))
	assert_eq(GameLoop2.stack_size(), 1)

# --- loss / run-over ------------------------------------------------------

func test_lethal_hit_ends_the_run() -> void:
	watch_signals(GameLoop2)
	GameState.hp = 2
	GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)  # spawn col
	_tick() ; _tick()                                             # march to the front
	_tick()                                                       # 3 dmg -> dead
	assert_eq(GameState.hp, 0)
	assert_true(GameLoop2.run_over)
	assert_false(GameLoop2.won)
	assert_signal_emitted(GameLoop2, "run_lost")

func test_no_resolution_after_run_over() -> void:
	GameState.hp = 1
	GameLoop2.choose_game(_enemy(5)) ; GameLoop2.beat_game(false)  # spawn col
	_tick() ; _tick()                                             # march to the front
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
	assert_eq(_col_of(inst), GameLoop2.SPAWN_COL, "conjured at the back column")
	# Like any spawn, it closes in and only strikes once it reaches the front.
	_tick()                             # -> col 2
	assert_eq(GameState.hp, 10)
	_tick()                             # -> col 1
	assert_eq(GameState.hp, 10)
	_tick()                             # strikes for 2
	assert_eq(GameState.hp, 8, "the conjured enemy hits for 2 once at the front")

# --- aggravate (Scroll of Aggravate Monsters, §4.1) -----------------------

func test_aggravate_adds_damage_for_n_games_then_expires() -> void:
	GameLoop2.choose_game(_enemy(1)) ; GameLoop2.beat_game(false)   # A(1) spawn col
	_tick() ; _tick()                                              # march A to the front
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
	GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)   # A spawn col
	GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)   # A->col2, B spawn col
	GameLoop2.choose_game(_enemy(0)) ; GameLoop2.beat_game(false)   # A->col1, B->col2
	assert_eq(GameLoop2.stacked_damage_per_game(), 2, "only A is at the front")
	_tick()                                                        # A strikes; A & B now front
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

# --- run start (loadout) --------------------------------------------------

func test_start_run_applies_isaac_loadout() -> void:
	GameLoop2.start_run(Data.get_character2(&"isaac"))
	assert_eq(GameState.max_hp, 6, "Isaac Health 6")
	assert_eq(GameState.hp, 6)
	assert_eq(GameState.bombs, 1, "Isaac starts with 1 Bomb")
	assert_eq(GameState.block, 0)
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

func test_roll_enemy_widens_when_type_absent() -> void:
	# No Traditional enemies authored yet — the roll must still return a tier-0
	# enemy rather than null (widened filter).
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"traditional", GoalEnemyData.Difficulty.LOW)
	assert_not_null(e)
	assert_eq(e.tier_index(), 0)

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

func test_real_boss_is_bomb_immune() -> void:
	GameState.bombs = 3
	var b: GoalEnemyData = GameLoop2.roll_boss(&"", GoalEnemyData.Difficulty.HIGH)
	var inst: int = GameLoop2.choose_game(b)
	GameLoop2.beat_game(false)   # boss stacks
	assert_false(GameLoop2.bomb(inst), "a real boss cannot be bombed")
	assert_eq(GameState.bombs, 3, "the bomb is not spent on a boss")
	assert_eq(GameLoop2.stack_size(), 1, "the boss stays on the stack")

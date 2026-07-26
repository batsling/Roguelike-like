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
	GameState.block = 0

# A synthetic goal-enemy with a known damage, so timing/damage assertions don't
# depend on authored content.
func _enemy(dmg: int, boss := false) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = dmg
	e.health = 1
	e.difficulty = GoalEnemyData.Difficulty.BOSS if boss else GoalEnemyData.Difficulty.LOW
	return e

# --- choose / spawn -------------------------------------------------------

func test_choose_game_sets_current() -> void:
	var inst: int = GameLoop2.choose_game(_enemy(1))
	assert_gt(inst, 0)
	assert_true(GameLoop2.has_current())

# --- goal met -> defeat + drop -------------------------------------------

func test_goal_met_defeats_drops_and_deals_no_damage() -> void:
	var chests_before: int = GameState.pending_chests
	GameLoop2.choose_game(_enemy(3))
	var res: Dictionary = GameLoop2.beat_game(true)
	assert_eq(GameLoop2.defeated_count, 1)
	assert_eq(GameState.pending_chests, chests_before + 1, "defeat drops a chest")
	assert_eq(GameLoop2.stack_size(), 0)
	assert_eq(GameState.hp, 10, "a met goal deals no damage")
	assert_false(GameLoop2.has_current())
	assert_eq(int(res["drops"]), 1)

# --- one-game grace (§7.2) -----------------------------------------------

func test_failed_enemy_does_not_attack_the_game_it_stacks() -> void:
	GameLoop2.choose_game(_enemy(2))
	GameLoop2.beat_game(false)
	assert_eq(GameState.hp, 10, "the enemy that just stacked cannot hit this game")
	assert_eq(GameLoop2.stack_size(), 1)

func test_stacked_enemy_attacks_the_following_game() -> void:
	GameLoop2.choose_game(_enemy(2))       # A spawns
	GameLoop2.beat_game(false)             # A stacks, no hit yet
	GameLoop2.choose_game(_enemy(3))       # B spawns
	GameLoop2.beat_game(false)             # A hits for 2; B stacks (its grace)
	assert_eq(GameState.hp, 8)
	assert_eq(GameLoop2.stack_size(), 2)
	GameLoop2.choose_game(_enemy(0))       # C spawns
	GameLoop2.beat_game(false)             # A(2) + B(3) hit = 5
	assert_eq(GameState.hp, 3)

# --- block absorbs before hp (§3) ----------------------------------------

func test_block_absorbs_first() -> void:
	GameState.block = 3
	GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)   # stacks
	GameLoop2.choose_game(_enemy(0)) ; GameLoop2.beat_game(false)   # 2 dmg -> block
	assert_eq(GameState.block, 1)
	assert_eq(GameState.hp, 10)

func test_block_overflow_hits_hp() -> void:
	GameState.block = 1
	GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)   # stacks
	GameLoop2.choose_game(_enemy(0)) ; GameLoop2.beat_game(false)   # 3 dmg: 1 blk, 2 hp
	assert_eq(GameState.block, 0)
	assert_eq(GameState.hp, 8)

# --- old-goal fulfilment (§2) --------------------------------------------

func test_fulfilling_old_goal_defeats_and_prevents_its_attack() -> void:
	var chests_before: int = GameState.pending_chests
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)
	# Next game: fulfil A's old goal while beating this game.
	GameLoop2.choose_game(_enemy(0))
	GameLoop2.beat_game(false, [a])
	assert_eq(GameState.hp, 10, "a fulfilled enemy never lands its hit")
	assert_eq(GameState.pending_chests, chests_before + 1, "fulfilment drops its item")
	assert_eq(GameLoop2.defeated_count, 1)
	# Only the current (failed) enemy remains on the stack.
	assert_eq(GameLoop2.stack_size(), 1)

# --- stun (§4.1 / §7.2) ---------------------------------------------------

func test_stun_skips_the_next_attack_only() -> void:
	var a: int = GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)  # A stacks
	GameLoop2.stun(a)
	GameLoop2.choose_game(_enemy(0)) ; GameLoop2.beat_game(false)  # A stunned, skips
	assert_eq(GameState.hp, 10, "stun skips A's first attack")
	GameLoop2.choose_game(_enemy(0)) ; GameLoop2.beat_game(false)  # A attacks now
	assert_eq(GameState.hp, 8)

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
	GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)  # stacks
	GameLoop2.choose_game(_enemy(0)) ; GameLoop2.beat_game(false)  # 3 dmg -> dead
	assert_eq(GameState.hp, 0)
	assert_true(GameLoop2.run_over)
	assert_false(GameLoop2.won)
	assert_signal_emitted(GameLoop2, "run_lost")

func test_no_resolution_after_run_over() -> void:
	GameState.hp = 1
	GameLoop2.choose_game(_enemy(5)) ; GameLoop2.beat_game(false)
	GameLoop2.choose_game(_enemy(5)) ; GameLoop2.beat_game(false)  # lethal
	assert_true(GameLoop2.run_over)
	var beaten_before: int = GameLoop2.games_beaten
	GameLoop2.choose_game(_enemy(5)) ; GameLoop2.beat_game(false)
	assert_eq(GameLoop2.games_beaten, beaten_before, "beat_game is a no-op after loss")

# --- win ------------------------------------------------------------------

func test_clear_amulet_wins() -> void:
	watch_signals(GameLoop2)
	var chests_before: int = GameState.pending_chests
	GameLoop2.choose_game(_enemy(1))
	GameLoop2.clear_amulet()
	assert_true(GameLoop2.won)
	assert_true(GameLoop2.run_over)
	assert_false(GameLoop2.has_current())
	assert_eq(GameState.pending_chests, chests_before + 1, "the amulet enemy drops too")
	assert_signal_emitted(GameLoop2, "run_won")

# --- stacked-damage preview (HUD) -----------------------------------------

func test_stacked_damage_per_game_sums_active_enemies() -> void:
	GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)
	GameLoop2.choose_game(_enemy(3)) ; GameLoop2.beat_game(false)
	assert_eq(GameLoop2.stacked_damage_per_game(), 5)

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
	assert_eq(String(e.id), "baby_alien")
	assert_true(GameLoop2.has_current())

# --- enemy roll by type + tier (§7) --------------------------------------

func test_roll_enemy_matches_type_and_tier() -> void:
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"deckbuilder", GoalEnemyData.Difficulty.LOW)
	assert_not_null(e)
	assert_eq(String(e.game_type), "deckbuilder")
	assert_eq(e.tier_index(), 0)

func test_roll_enemy_action_low_is_baby_alien() -> void:
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"action", GoalEnemyData.Difficulty.LOW)
	assert_eq(String(e.id), "baby_alien")

func test_roll_enemy_widens_when_type_absent() -> void:
	# No Traditional enemies authored yet — the roll must still return a tier-0
	# enemy rather than null (widened filter).
	var e: GoalEnemyData = GameLoop2.roll_enemy(&"traditional", GoalEnemyData.Difficulty.LOW)
	assert_not_null(e)
	assert_eq(e.tier_index(), 0)

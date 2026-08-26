extends GutTest

# The TIMED STATUS LAYER (docs/potions-design.md §5) — stacks that expire on their
# own, the first thing in this build with a clock on it. Nothing applies one yet:
# potions are the content that will (§4.1 of that doc), and this suite is what
# lets the layer land before them.
#
# Four things are being tested, in the order a borrowed stack passes through them:
#   1. it READS as part of the status — permanent + timed, capped, on both holders;
#   2. it SAYS it is borrowed, everywhere the goal it rewrites is quoted;
#   3. it EXPIRES whole when a game resolves, and takes back the shields it handed
#      out but not the ones the body already spent (§5.5);
#   4. it SURVIVES a save, on the player and on a body.
#
# `dexterity` is the status these use throughout because it is the one with a
# combat side that HANDS SOMETHING OUT (shield points, §13.4) — which is the half
# of the design that needed a new rule rather than a new field.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 20
	GameState.hp = 20

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _enemy() -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.goal = "Beat it"
	e.damage = 1
	e.health = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	return e

# Stand one body on the board and hand its entry back. The escort a real choice
# rolls (§7.5) is taken straight off again — these tests are about one body's
# statuses, and a stranger from the authored roster standing beside it would put
# content they never asked about inside the assertions.
func _solo_entry() -> Dictionary:
	var inst: int = GameLoop2.choose_game(_enemy())
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return GameLoop2.entry_for(inst)

# Resolve a game the way the loop does, with nothing reported. That is the tick
# every clock in the build runs on — the ground burns down on it (§17) and now the
# borrowed statuses run out on it too.
func _resolve_a_game() -> Dictionary:
	return GameLoop2.beat_game(false, [], {})

# ---------------------------------------------------------------------------
# 1. A borrowed stack is part of the status
# ---------------------------------------------------------------------------

func test_a_timed_stack_counts_toward_the_players_total() -> void:
	GameState.apply_status(&"dexterity", 2)          # permanent
	GameState.apply_status(&"dexterity", 5, 1)       # borrowed for a game
	assert_eq(GameState.status_stacks(&"dexterity"), 7,
		"the two layers add up — that is what makes it a layer rather than a flag")
	assert_eq(GameState.permanent_stacks(&"dexterity"), 2,
		"and the permanent half is still separately knowable")

func test_the_players_status_list_reports_one_row_with_the_clock_on_it() -> void:
	GameState.apply_status(&"dexterity", 3, 2)
	var rows: Array = GameState.status_list().filter(
		func(r): return (r["status"] as StatusData).id == &"dexterity")
	assert_eq(rows.size(), 1, "one row, not one per layer")
	assert_eq(int(rows[0]["stacks"]), 3)
	assert_eq(int(rows[0]["games"]), 2, "and it carries how long it has left")

func test_a_permanent_stack_underneath_means_the_status_is_not_going_anywhere() -> void:
	GameState.apply_status(&"dexterity", 1)
	GameState.apply_status(&"dexterity", 4, 1)
	assert_eq(GameState.status_games_left(&"dexterity"), 0,
		"a clock is only worth quoting when the whole status leaves with it")

func test_two_borrowed_rows_report_the_soonest_clock() -> void:
	GameState.apply_status(&"dexterity", 1, 3)
	GameState.apply_status(&"dexterity", 1, 1)
	assert_eq(GameState.status_games_left(&"dexterity"), 1)
	assert_eq(GameState.status_stacks(&"dexterity"), 2)

func test_a_borrowed_stack_cannot_push_a_status_past_its_ceiling() -> void:
	# Burn is the one status the sheet caps (Max: 3, §13.1). The permanent path
	# enforces that on the way in; the timed layer has to enforce it on the way out
	# or a potion would be a way around an authored ceiling.
	GameState.apply_status(&"burn", 3)
	GameState.apply_status(&"burn", 3, 1)
	assert_eq(GameState.status_stacks(&"burn"), 3, "capped, both layers together")

func test_the_ceiling_never_pulls_the_permanent_count_down() -> void:
	# Stacks ALREADY over a cap tick down one at a time rather than being frozen
	# there (§13.1, and test_statuses.gd owns that rule). Summing a timed layer on
	# top must not turn a read into a clamp — the ceiling is about the way up.
	GameState.player_statuses[&"burn"] = 5
	assert_eq(GameState.status_stacks(&"burn"), 5, "untouched with nothing borrowed")
	GameState.apply_status(&"burn", 2, 1)
	assert_eq(GameState.status_stacks(&"burn"), 5,
		"and a borrowed stack cannot lift it past the cap, nor lower what is there")

func test_a_body_carries_the_two_layers_the_same_way() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"strength", 2)
	GameLoop2.apply_status_to(int(entry["instance"]), &"strength", 3, 1)
	assert_eq(GameLoop2.entry_status_stacks(entry, &"strength"), 5)
	assert_eq(GameLoop2.entry_status_games_left(entry, &"strength"), 0,
		"permanent stacks underneath, so nothing is leaving")

func test_a_borrowed_strength_is_felt_in_combat_while_it_lasts() -> void:
	var entry: Dictionary = _solo_entry()
	var before: int = GameLoop2.enemy_damage(entry)
	GameLoop2.apply_status_to(int(entry["instance"]), &"strength", 2, 1)
	assert_eq(GameLoop2.enemy_damage(entry), before + 2,
		"the combat side reads the merged total, not just the permanent dict")

# ---------------------------------------------------------------------------
# 2. It says it is borrowed
# ---------------------------------------------------------------------------

func test_a_borrowed_clause_says_so_on_the_goal_line() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 1, 1)
	var text: String = GameLoop2.goal_text_for(entry)
	assert_string_contains(text, "this game only",
		"a clause the player cannot tell is temporary is a clause they will route "
		+ "around a tax that is about to lift")

func test_a_permanent_clause_does_not() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 1)
	assert_false(GameLoop2.goal_text_for(entry).contains("this game only"),
		"a permanent clause promises nothing about running out")

func test_the_clock_reads_the_same_wherever_it_is_quoted() -> void:
	assert_eq(StatusData.clock_note(0), "", "no clock, no line")
	assert_eq(StatusData.clock_suffix(0), "")
	assert_string_contains(StatusData.clock_note(1), "This game only")
	assert_string_contains(StatusData.clock_note(3), "3 games")
	var dex: StatusData = Data.get_status(&"dexterity")
	assert_string_contains(dex.tooltip_for(StatusData.ENEMY, 1, false, 1),
		"This game only", "the pip every surface draws says it too")
	assert_false(dex.tooltip_for(StatusData.ENEMY, 1).contains("This game only"),
		"and a status with no clock grows no line about one")

# ---------------------------------------------------------------------------
# 3. It expires when a game resolves
# ---------------------------------------------------------------------------

func test_a_borrowed_stack_is_gone_after_one_game() -> void:
	GameState.apply_status(&"dexterity", 4, 1)
	assert_eq(GameState.status_stacks(&"dexterity"), 4)
	_resolve_a_game()
	assert_eq(GameState.status_stacks(&"dexterity"), 0, "one game, and it is spent")

func test_the_permanent_stacks_under_it_survive() -> void:
	GameState.apply_status(&"dexterity", 2)
	GameState.apply_status(&"dexterity", 5, 1)
	_resolve_a_game()
	assert_eq(GameState.status_stacks(&"dexterity"), 2,
		"the layer expires whole and leaves what the run actually owns")

func test_a_two_game_clock_survives_the_first_game() -> void:
	GameState.apply_status(&"dexterity", 1, 2)
	_resolve_a_game()
	assert_eq(GameState.status_stacks(&"dexterity"), 1)
	assert_eq(GameState.status_games_left(&"dexterity"), 1)
	_resolve_a_game()
	assert_eq(GameState.status_stacks(&"dexterity"), 0)

func test_the_resolve_reports_what_ran_out() -> void:
	GameState.apply_status(&"dexterity", 3, 1)
	var res: Dictionary = _resolve_a_game()
	var expired: Array = res.get("statuses_expired", [])
	assert_eq(expired.size(), 1, "the report screen is told, like it is about tiles")
	assert_eq((expired[0]["status"] as StatusData).id, &"dexterity")
	assert_eq(int(expired[0]["stacks"]), 3)

func test_a_bodys_borrowed_status_expires_on_the_same_tick() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"strength", 3, 1)
	assert_eq(GameLoop2.entry_status_stacks(entry, &"strength"), 3)
	_resolve_a_game()
	assert_eq(GameLoop2.entry_status_stacks(entry, &"strength"), 0,
		"one clock, whoever is holding it")

# --- the shield claw-back (§5.5) -------------------------------------------

func test_a_borrowed_dexterity_takes_its_unspent_shields_back() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 3, 1)
	assert_eq(GameLoop2.enemy_shield(entry), 3,
		"Dexterity hands out a POOL when it lands (§13.4)")
	_resolve_a_game()
	assert_eq(GameLoop2.enemy_shield(entry), 0,
		"and the clock takes back what the body never spent")

func test_it_only_takes_back_what_is_left() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 3, 1)
	entry["shield"] = 1                     # two of the three already soaked hits
	_resolve_a_game()
	assert_eq(GameLoop2.enemy_shield(entry), 0,
		"min(granted, pool) — a spent shield is not billed twice")

func test_a_permanent_dexterity_keeps_its_shields() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 2)
	_resolve_a_game()
	assert_eq(GameLoop2.enemy_shield(entry), 2,
		"the claw-back belongs to the clock, not to the status — §13.4 is unchanged "
		+ "for everything that is not borrowed")

func test_the_claw_back_cannot_eat_a_pool_something_else_refilled() -> void:
	var entry: Dictionary = _solo_entry()
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 1, 1)  # +1, borrowed
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 2)     # +2, owned
	var pool: int = GameLoop2.enemy_shield(entry)
	_resolve_a_game()
	assert_eq(GameLoop2.enemy_shield(entry), pool - 1,
		"only the borrowed row's own grant comes off")

# --- decay spends the borrowed stack first ---------------------------------

func test_a_decay_spends_the_borrowed_stack_before_the_owned_one() -> void:
	GameState.apply_status(&"burn", 1)       # owned
	GameState.apply_status(&"burn", 1, 1)    # borrowed
	GameState.remove_status(&"burn", 1)
	assert_eq(GameState.status_stacks(&"burn"), 1)
	assert_eq(GameState.permanent_stacks(&"burn"), 1,
		"the stack that was leaving anyway is the one a decay spends")

# ---------------------------------------------------------------------------
# 4. It survives a save
# ---------------------------------------------------------------------------

func test_the_players_borrowed_stacks_round_trip() -> void:
	GameState.apply_status(&"dexterity", 2)
	GameState.apply_status(&"dexterity", 5, 2)
	var permanent: Dictionary = GameState.serialize_statuses()
	var timed: Array = GameState.serialize_timed_statuses()
	GameState.reset_run()
	GameState.restore_statuses(permanent)
	GameState.restore_timed_statuses(timed)
	assert_eq(GameState.status_stacks(&"dexterity"), 7)
	assert_eq(GameState.status_games_left(&"dexterity"), 0, "permanent underneath")
	assert_eq(GameState.permanent_stacks(&"dexterity"), 2)

func test_a_reloaded_clock_still_runs_out() -> void:
	GameState.apply_status(&"dexterity", 4, 1)
	var timed: Array = GameState.serialize_timed_statuses()
	GameState.reset_run()
	GameState.restore_timed_statuses(timed)
	_resolve_a_game()
	assert_eq(GameState.status_stacks(&"dexterity"), 0)

func test_a_bodys_borrowed_stacks_and_their_debt_round_trip() -> void:
	# A REAL enemy, unlike every test above: `_deserialize_entry` drops a body whose
	# id the catalog cannot look up (the same call a stale save gets), and the
	# synthetic the other tests use is by definition not in it.
	var roster: Array = Data.all_goal_enemies()
	if roster.is_empty():
		return
	var inst: int = GameLoop2.choose_game(roster[0])
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	var entry: Dictionary = GameLoop2.entry_for(inst)
	GameLoop2.apply_status_to(int(entry["instance"]), &"dexterity", 3, 1)
	var blob: Dictionary = GameLoop2.serialize()
	GameLoop2.restore(blob)
	var back: Dictionary = GameLoop2.stack[0]
	assert_eq(GameLoop2.entry_status_stacks(back, &"dexterity"), 3)
	assert_eq(GameLoop2.enemy_shield(back), 3, "the pool it was handed")
	_resolve_a_game()
	assert_eq(GameLoop2.entry_status_stacks(back, &"dexterity"), 0)
	assert_eq(GameLoop2.enemy_shield(back), 0,
		"and a reloaded row still knows what it owes")

func test_a_save_from_before_the_layer_restores_without_one() -> void:
	# An older save has no `timed_statuses` key at all. It must read as a run
	# carrying nothing borrowed rather than as a broken restore.
	GameState.restore_timed_statuses(null)
	assert_eq(GameState.timed_statuses.size(), 0)
	GameState.restore_statuses({"dexterity": 2})
	assert_eq(GameState.status_stacks(&"dexterity"), 2)

func test_a_row_naming_a_status_the_catalog_lost_is_dropped() -> void:
	GameState.restore_timed_statuses([
		{"id": "no_such_status", "stacks": 2, "games": 1},
		{"id": "dexterity", "stacks": 1, "games": 1},
	])
	assert_eq(GameState.timed_statuses.size(), 1,
		"a status the catalog cannot describe is dropped, like the permanent ones")
	assert_eq(GameState.status_stacks(&"dexterity"), 1)

# ---------------------------------------------------------------------------
# 5. EVERY BORROWED APPLICATION IS ITS OWN INSTANCE (§5.4)
#
# The rule the checklist reads: a temporary status never merges — not with another
# temporary one, and not with the stacks the run owns. `strength` throughout here
# rather than `dexterity`, because these are about the GOAL a status hangs off and
# strength's player side is the claimable one.
# ---------------------------------------------------------------------------

func test_two_borrowed_applications_are_two_rows_with_two_clocks() -> void:
	GameState.apply_status(&"strength", 3, 1)
	GameState.apply_status(&"strength", 3, 2)
	assert_eq(GameState.timed_statuses.size(), 2,
		"Reptile Trinket firing twice is two borrowed Strengths, not one of six")
	assert_eq(GameState.status_stacks(&"strength"), 6,
		"but what they DO is still felt as a total")
	_resolve_a_game()
	assert_eq(GameState.status_stacks(&"strength"), 3,
		"and the one-game row runs out on its own")

func test_every_instance_is_numbered_and_no_number_comes_round_twice() -> void:
	GameState.apply_status(&"strength", 1, 1)
	GameState.apply_status(&"strength", 1, 1)
	var first: int = int(GameState.timed_statuses[0]["instance"])
	var second: int = int(GameState.timed_statuses[1]["instance"])
	assert_ne(first, second, "the number is what holds two rows of one status apart")
	_resolve_a_game()                                   # both expire
	GameState.apply_status(&"strength", 1, 1)
	assert_ne(int(GameState.timed_statuses[0]["instance"]), first,
		"a fresh row never inherits a dead row's number")

func test_the_checklist_offers_the_owned_stacks_and_each_loan_separately() -> void:
	GameState.apply_status(&"strength", 1)              # owned
	GameState.apply_status(&"strength", 3, 1)           # borrowed
	var rows: Array = GameState.status_objectives()
	assert_eq(rows.size(), 2, "two offers with two deadlines, so two rows")
	assert_eq(int(rows[0]["stacks"]), 1, "the stacks the run owns")
	assert_eq(int(rows[0]["games"]), 0, "and they are not going anywhere")
	assert_eq(String(rows[0]["key"]), "strength",
		"the permanent bucket answers to the bare id, as it always did")
	assert_eq(int(rows[1]["stacks"]), 3, "the loan, on its own row")
	assert_eq(int(rows[1]["games"]), 1, "with its own clock on it")
	assert_true(String(rows[1]["key"]).begins_with("strength#"))

func test_the_hud_still_reads_them_as_one_chip() -> void:
	GameState.apply_status(&"strength", 1)
	GameState.apply_status(&"strength", 3, 1)
	var shown: Array = GameState.status_list()
	assert_eq(shown.size(), 1, "one icon on the player, whatever the goals do")
	assert_eq(int(shown[0]["stacks"]), 4, "and one number: what a stack does is a total")

func test_claiming_a_borrowed_row_pays_for_the_stacks_behind_that_row() -> void:
	GameState.apply_status(&"strength", 1)
	GameState.apply_status(&"strength", 3, 1)
	var rows: Array = GameState.status_objectives()
	assert_true(GameLoop2.claim_player_objective(String(rows[1]["key"])),
		"the borrowed row is claimable in its own right")
	assert_true(GameLoop2.claim_player_objective(String(rows[0]["key"])),
		"and the owned one is still there to claim after it")

func test_a_stale_key_from_an_expired_loan_pays_nothing() -> void:
	GameState.apply_status(&"strength", 3, 1)
	var key: String = String(GameState.status_objectives()[0]["key"])
	_resolve_a_game()
	assert_false(GameLoop2.claim_player_objective(key),
		"the row it named is gone, so there is nothing behind it to pay")

func test_a_borrowed_row_survives_a_save_under_the_same_key() -> void:
	GameState.apply_status(&"strength", 2, 2)
	var key: String = String(GameState.status_objectives()[0]["key"])
	var blob: Array = GameState.serialize_timed_statuses()
	GameState.restore_timed_statuses(blob)
	assert_eq(String(GameState.status_objectives()[0]["key"]), key,
		"a tick recorded before the reload still names the row it named")

func test_a_claimed_row_is_remembered_so_a_repaint_cannot_pay_it_twice() -> void:
	# `_arm_row` locks a checklist row by asking the loop whether it was answered,
	# and the status rows were the only ones that never told it — so a repaint
	# handed the player an open box for a goal they had already claimed.
	GameState.apply_status(&"strength", 2)
	var key: String = String(GameState.status_objectives()[0]["key"])
	assert_false(GameLoop2.row_answered("status:%s" % key), "nothing ticked yet")
	GameLoop2.mark_row_answered("status:%s" % key)
	assert_true(GameLoop2.row_answered("status:%s" % key),
		"and a rebuilt row draws itself locked from this")

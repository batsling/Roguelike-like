extends GutTest

# Tests for Statuses 2.0 (docs/games-first-redesign.md §13) — the goal-rewriting
# balance lever locations, items and scrolls reach the run through.
#
# Three layers, in the order a status passes through them:
#   1. the CONTENT — statuses2.0 loads, and its {expr} holes resolve to the
#      numbers the sheet's prose promises;
#   2. the RULES — each side's authored MODE (goal / clause / bonus) rewrites
#      goals the way §13 says, and decay only where the sheet asks for it;
#   3. the WIRING — the apply_status effect verb, and save/load round-trips for
#      both the player's statuses and the ones riding bodies on the board.

# Choose a game and take its ESCORT straight back off the board.
#
# Committing to a game stands a second, randomly-rolled body beside the game's
# own enemy (§7.5, and test_gameloop2.gd, which is where that rule is tested).
# These tests are about something else, and a stranger from the authored roster
# standing on the board would put content they never asked about inside their
# assertions.
func _choose_solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 20
	GameState.hp = 20

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

# A synthetic goal-enemy with a known goal, so the clause assertions don't move
# when the enemies2.0 sheet does.
func _enemy(goal: String = "Beat it") -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.goal = goal
	e.damage = 1
	e.health = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	return e

# A synthetic status, so the rule tests don't depend on the authored roster.
# `player` / `enemy` are side blocks in the shape the generator emits.
func _status(id: StringName, player: Dictionary = {}, enemy: Dictionary = {}) -> StatusData:
	var s := StatusData.new()
	s.id = id
	s.display_name = String(id).capitalize()
	s.on_player = player
	s.on_enemy = enemy
	return s

func _sideblock(mode: String, condition: String, reward: Array = [],
		reward_text: String = "", decay: bool = false) -> Dictionary:
	return {"mode": mode, "condition": condition, "reward": reward,
		"reward_text": reward_text, "decay": decay}

# ---------------------------------------------------------------------------
# 1. The content
# ---------------------------------------------------------------------------

func test_the_statuses_sheet_loaded() -> void:
	assert_gt(Data.all_statuses().size(), 0, "data/statuses2.0 loaded at least one status")
	for id in [&"strength", &"speed", &"dexterity", &"marked"]:
		assert_not_null(Data.get_status(id), "%s is in the catalog" % id)

func test_each_side_carries_its_own_authored_mode() -> void:
	# The two halves are authored independently: Strength taxes the enemy and pays
	# the player, Marked taxes the player and pays out on the enemy.
	var strength: StatusData = Data.get_status(&"strength")
	assert_eq(strength.mode_for(StatusData.PLAYER), &"goal")
	assert_eq(strength.mode_for(StatusData.ENEMY), &"clause")
	var marked: StatusData = Data.get_status(&"marked")
	assert_eq(marked.mode_for(StatusData.PLAYER), &"clause")
	assert_eq(marked.mode_for(StatusData.ENEMY), &"bonus")

func test_buff_and_debuff_are_flavour_not_mechanics() -> void:
	# Kept for the HUD tint and the collection filter; nothing dispatches on it.
	assert_true(Data.get_status(&"strength").is_buff())
	assert_true(Data.get_status(&"marked").is_debuff())

func test_decay_is_authored_per_side() -> void:
	# Strength's standing goal keeps paying — it IS the reward. Marked sheds a
	# stack on either side, which is what makes it survivable.
	assert_false(Data.get_status(&"strength").decays(StatusData.PLAYER), "Strength persists")
	assert_true(Data.get_status(&"marked").decays(StatusData.PLAYER), "Marked ticks down")
	assert_true(Data.get_status(&"marked").decays(StatusData.ENEMY), "and so does its bonus")

func test_a_flat_condition_scales_with_the_stack() -> void:
	var marked: StatusData = Data.get_status(&"marked")
	assert_eq(marked.condition_text(StatusData.ENEMY, 1), "you get 1 achievement",
		"singular at one stack")
	assert_eq(marked.condition_text(StatusData.ENEMY, 3), "you get 3 achievements")

func test_speed_window_tightens_on_the_authored_curve() -> void:
	# 1 + (1/2)^(X-2) hours, halving toward a floor of one hour. These are the
	# numbers the sheet's formula promises, and the reason the {expr} holes exist
	# at all — the ONLY status behaviour that isn't a straight multiple of X.
	# This curve was Dexterity's before the combat side landed (§13.2); it kept
	# the goal and took the name that describes it.
	var speed: StatusData = Data.get_status(&"speed")
	assert_eq(speed.condition_text(StatusData.PLAYER, 1), "beaten in 3 hours or less")
	assert_eq(speed.condition_text(StatusData.PLAYER, 2), "beaten in 2 hours or less")
	assert_eq(speed.condition_text(StatusData.PLAYER, 3), "beaten in 1 hour 30 minutes or less")
	assert_eq(speed.condition_text(StatusData.PLAYER, 4), "beaten in 1 hour 15 minutes or less")
	assert_eq(speed.condition_text(StatusData.PLAYER, 5), "beaten in 1 hour 8 minutes or less")

func test_a_fractional_window_reads_as_hours_and_minutes() -> void:
	# A time window is held against a clock, so "1.5 hours" would be arithmetic the
	# player has to do themselves mid-run.
	assert_eq(StatusData.format_hours(3.0), "3 hours")
	assert_eq(StatusData.format_hours(1.0), "1 hour")
	assert_eq(StatusData.format_hours(1.5), "1 hour 30 minutes")
	assert_eq(StatusData.format_hours(1.25), "1 hour 15 minutes")
	assert_eq(StatusData.format_hours(1.125), "1 hour 8 minutes", "67.5 min, to the minute")
	assert_eq(StatusData.format_hours(0.75), "45 minutes", "no hours part when there is none")
	assert_eq(StatusData.format_hours(2.0 / 60.0), "2 minutes")
	assert_eq(StatusData.format_hours(1.0 / 60.0), "1 minute", "singular")

func test_whole_numbers_lose_their_decimal_tail() -> void:
	# A plain count, with no :hours format on its hole.
	assert_eq(StatusData.format_number(2.0), "2")
	assert_eq(StatusData.format_number(1.5), "1.5")
	assert_eq(StatusData.format_number(1.125), "1.125")

func test_rewards_scale_with_the_stack() -> void:
	var strength: StatusData = Data.get_status(&"strength")
	var effects: Array = strength.reward_effects(StatusData.PLAYER, 3)
	assert_eq(effects.size(), 2, "Strength pays a chest reward and a Bash")
	assert_eq(String(effects[0].get("type", "")), "chest_reward")
	assert_eq(int(effects[0].get("value", 0)), 3, "the chest reward scales to X")
	assert_false(effects[0].has("scaled"), "the {expr} hole is resolved, not passed through")
	# The VERB payout does not scale — the chest is what grows with the stack now,
	# so the sheet writes `gain_stat bash 1` and means it at every X.
	assert_eq(String(effects[1].get("type", "")), "gain_stat")
	assert_eq(int(effects[1].get("value", 0)), 1, "a flat Bash at any stack")
	assert_eq(int(Data.get_status(&"strength").reward_effects(StatusData.PLAYER, 1)[1]
		.get("value", 0)), 1, "and the same one at one stack")

func test_a_clause_side_pays_nothing() -> void:
	# A `clause` is a requirement, not a payout — the generator rejects a reward on
	# one, so there is nothing to hand out here.
	assert_eq(Data.get_status(&"strength").reward_effects(StatusData.ENEMY, 3).size(), 0)
	assert_eq(Data.get_status(&"marked").reward_effects(StatusData.PLAYER, 3).size(), 0)

func test_reward_text_reads_at_the_live_stack() -> void:
	# The `[chest reward]` the sheet's prose writes, resolved to the chests it
	# actually buys at this stack count (§8.2).
	assert_eq(Data.get_status(&"strength").reward_at(StatusData.PLAYER, 2),
		"+1 Medium Chest, +1 Bash")
	assert_eq(Data.get_status(&"strength").reward_at(StatusData.PLAYER, 5),
		"+1 Huge Chest and 1 Small Chest, +1 Bash")
	assert_eq(Data.get_status(&"marked").reward_at(StatusData.ENEMY, 1), "+1 Small Chest")

func test_every_status_has_art_and_does_something() -> void:
	for s in Data.all_statuses():
		var sd: StatusData = s
		assert_true(sd.has_side(StatusData.PLAYER) or sd.has_side(StatusData.ENEMY),
			"%s acts on at least one side" % sd.id)
		assert_not_null(sd.image, "%s resolved its art" % sd.id)

# ---------------------------------------------------------------------------
# 2. The rules — the four quadrants
# ---------------------------------------------------------------------------

func test_a_goal_on_the_player_side_is_an_extra_objective_not_a_clause() -> void:
	GameState.apply_status(&"strength", 2)
	_choose_solo(_enemy("Beat it"))
	# It pays the player; it does not tighten anything the enemy asked for.
	assert_eq(GameLoop2.goal_text_for(GameLoop2.arrival()), "Beat it",
		"a player-side goal leaves enemy goals alone")
	var objectives: Array = GameState.status_objectives()
	assert_eq(objectives.size(), 1, "it shows up as a standing objective")
	assert_eq((objectives[0]["status"] as StatusData).objective_text(StatusData.PLAYER, 2),
		"If the difficulty is increased 2 times, gain +1 Medium Chest, +1 Bash")

func test_a_clause_on_an_enemy_tightens_that_enemys_goal() -> void:
	_choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 2, "current")
	assert_eq(GameLoop2.goal_text_for(GameLoop2.arrival()),
		"Beat it and the difficulty must be increased 2 times")

func test_a_clause_on_the_player_tightens_every_enemys_goal() -> void:
	_choose_solo(_enemy("Beat it"))
	GameLoop2.beat_game(false)          # it walks onto the board
	_choose_solo(_enemy("Beat another"))
	GameState.apply_status(&"marked", 3)
	assert_eq(GameLoop2.goal_text_for(GameLoop2.arrival()),
		"Beat another and you must get 3 achievements", "the current enemy")
	assert_eq(GameLoop2.goal_text_for(GameLoop2.stack[0]),
		"Beat it and you must get 3 achievements", "and the follower too")

func test_a_bonus_on_an_enemy_is_claimable_not_required() -> void:
	_choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	assert_eq(GameLoop2.goal_text_for(GameLoop2.arrival()), "Beat it",
		"the goal itself is untouched")
	var bonuses: Array = GameLoop2.bonus_objectives_for(GameLoop2.arrival())
	assert_eq(bonuses.size(), 1, "it hangs a bonus objective off the enemy")
	assert_eq((bonuses[0]["status"] as StatusData).objective_text(StatusData.ENEMY, 2),
		"and if you get 2 achievements, gain +1 Medium Chest")

func test_clauses_stack_enemy_first_then_player() -> void:
	_choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 1, "current")
	GameState.apply_status(&"marked", 2)
	assert_eq(GameLoop2.goal_text_for(GameLoop2.arrival()),
		"Beat it and the difficulty must be increased 1 time"
		+ " and you must get 2 achievements",
		"the enemy's own clause reads before the one every enemy carries")

# --- targeting ------------------------------------------------------------

func test_target_all_covers_the_board_and_the_current_enemy() -> void:
	_choose_solo(_enemy("A"))
	GameLoop2.beat_game(false)
	_choose_solo(_enemy("B"))
	assert_eq(GameLoop2.apply_enemy_status(&"marked", 1, "all"), 2, "both bodies")
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.arrival()).size(), 1)
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0]).size(), 1)

func test_target_current_leaves_the_followers_alone() -> void:
	_choose_solo(_enemy("A"))
	GameLoop2.beat_game(false)
	_choose_solo(_enemy("B"))
	assert_eq(GameLoop2.apply_enemy_status(&"marked", 1, "current"), 1)
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0]).size(), 0,
		"the follower is untouched")

func test_target_random_lands_on_exactly_one_body() -> void:
	_choose_solo(_enemy("A"))
	GameLoop2.beat_game(false)
	_choose_solo(_enemy("B"))
	assert_eq(GameLoop2.apply_enemy_status(&"marked", 1, "random"), 1)
	var total: int = GameLoop2.enemy_statuses(GameLoop2.arrival()).size() \
		+ GameLoop2.enemy_statuses(GameLoop2.stack[0]).size()
	assert_eq(total, 1, "one body, whichever it was")

func test_applying_a_status_twice_raises_intensity() -> void:
	# Stackable: Intensity — a second Marked is one Marked at 2, not two Markeds.
	GameState.apply_status(&"marked", 1)
	assert_eq(GameState.apply_status(&"marked", 2), 3)
	assert_eq(GameState.status_list().size(), 1, "still one status")

func test_an_unknown_status_id_is_refused_rather_than_stored() -> void:
	assert_eq(GameState.apply_status(&"not_a_status", 2), 0)
	assert_false(GameState.has_status(&"not_a_status"))
	assert_eq(GameLoop2.apply_enemy_status(&"not_a_status", 2, "all"), 0)

# --- the enemy's statuses ride the body -----------------------------------

func test_a_status_on_the_current_enemy_survives_it_walking_onto_the_board() -> void:
	# The one place this could silently break: the current enemy is not on the
	# stack, and joining it rebuilds the entry.
	_choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	GameLoop2.beat_game(false)
	assert_eq(GameLoop2.stack.size(), 1)
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0]).size(), 1,
		"Marked came with it")
	# Marked's ENEMY side is a `bonus`, not a clause on the goal. The mode, not just
	# the status, has to survive the move.
	assert_eq(GameLoop2.goal_text_for(GameLoop2.stack[0]), "Beat it")
	assert_eq(GameLoop2.bonus_objectives_for(GameLoop2.stack[0]).size(), 1,
		"and it is still a bonus over there")

func test_an_enemy_clause_survives_it_walking_onto_the_board() -> void:
	# The same move for the other mode: a clause has to still be welded onto the
	# goal once the enemy is a follower.
	_choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 2, "current")
	GameLoop2.beat_game(false)
	assert_eq(GameLoop2.goal_text_for(GameLoop2.stack[0]),
		"Beat it and the difficulty must be increased 2 times")

# ---------------------------------------------------------------------------
# 2b. Decay and payout
# ---------------------------------------------------------------------------

func test_a_player_clause_ticks_once_for_a_game_whose_goal_was_met() -> void:
	GameState.apply_status(&"marked", 3)
	_choose_solo(_enemy("Beat it"))
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"marked"), 2, "one stack for the completion")

func test_a_player_clause_does_not_tick_on_a_missed_goal() -> void:
	GameState.apply_status(&"marked", 3)
	_choose_solo(_enemy("Beat it"))
	GameLoop2.beat_game(false)
	assert_eq(GameState.status_stacks(&"marked"), 3, "nothing was completed")

func test_a_player_clause_does_not_tick_on_a_free_game() -> void:
	# A game with no enemy reports goal_met = true (the checklist auto-clears), but
	# a goal nobody set can't have carried the clause.
	GameState.apply_status(&"marked", 2)
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"marked"), 2)

func test_a_player_clause_ticks_once_per_game_not_once_per_goal() -> void:
	# Clearing four followers in one game must not wipe a 4-stack status whole:
	# the sheet's "decrease stack by 1 when completed" is a per-game count.
	GameState.apply_status(&"marked", 4)
	var instances: Array = []
	for i in range(3):
		instances.append(_choose_solo(_enemy("Goal %d" % i)))
		GameLoop2.beat_game(false)
	_choose_solo(_enemy("Current"))
	GameLoop2.beat_game(true, instances)
	assert_eq(GameState.status_stacks(&"marked"), 3, "one tick for the whole game")

func test_a_player_clause_falls_off_at_zero() -> void:
	GameState.apply_status(&"marked", 1)
	_choose_solo(_enemy("Beat it"))
	GameLoop2.beat_game(true)
	assert_false(GameState.has_status(&"marked"), "spent")
	assert_eq(GameState.status_list().size(), 0, "and pruned, not left at zero")

func test_a_player_objective_pays_out_and_stays() -> void:
	GameState.apply_status(&"strength", 2)
	GameState.bash = 0
	_choose_solo(_enemy("Beat it"))
	GameLoop2.beat_game(true, [], {"status_goals": [&"strength"]})
	assert_eq(GameState.bash, 1, "a flat +1 Bash, whatever the stack")
	# [chest reward] 2 is ONE Medium chest, not two Small ones (§8.2).
	assert_eq(GameState.pending_chests, 1, "one chest")
	assert_eq(GameState.pending_chest_choices, [2], "and it is a Medium")
	assert_eq(GameState.status_stacks(&"strength"), 2,
		"the status persists — its side does not decay")

func test_a_player_objective_pays_nothing_when_it_is_not_ticked() -> void:
	GameState.apply_status(&"strength", 2)
	GameState.bash = 0
	_choose_solo(_enemy("Beat it"))
	GameLoop2.beat_game(true)
	assert_eq(GameState.bash, 0, "an unticked standing goal is simply not claimed")

func test_claiming_an_enemy_bonus_pays_and_ticks_that_enemy() -> void:
	var inst: int = _choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	var res: Dictionary = GameLoop2.beat_game(false, [],
		{"bonuses": [{"instance": inst, "status": &"marked"}]})
	assert_eq(int(res.get("status_rewards", 0)), 1, "the claim resolved")
	assert_eq(GameState.pending_chests, 1, "[chest reward] 2 is one Medium chest")
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0])[0]["stacks"], 1,
		"one stack spent on the claim")

func test_an_enemy_bonus_can_be_claimed_on_the_game_that_kills_it() -> void:
	# The claim is resolved BEFORE the board is, so beating an enemy and claiming
	# its bonus in the same game pays both rather than swallowing the bonus.
	var inst: int = _choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 1, "current")
	var res: Dictionary = GameLoop2.beat_game(true, [],
		{"bonuses": [{"instance": inst, "status": &"marked"}]})
	assert_eq(int(res.get("status_rewards", 0)), 1, "the bonus still paid")
	assert_eq(GameLoop2.stack.size(), 0, "and the enemy still died")

func test_a_clause_side_cannot_be_claimed_as_an_enemy_bonus() -> void:
	# The modes are not interchangeable: Strength's enemy side is a tax, and there
	# is nothing to claim on it.
	var inst: int = _choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 2, "current")
	assert_false(GameLoop2.claim_enemy_bonus(inst, &"strength"))
	assert_eq(GameState.pending_chests, 0)

func test_a_clause_side_cannot_be_claimed_as_a_player_objective() -> void:
	GameState.apply_status(&"marked", 2)
	assert_false(GameLoop2.claim_player_objective(&"marked"))
	assert_eq(GameState.status_stacks(&"marked"), 2, "and nothing ticked")

# ---------------------------------------------------------------------------
# 3. The wiring
# ---------------------------------------------------------------------------

func test_the_apply_status_effect_reaches_the_player() -> void:
	EffectSystem.apply({"type": "apply_status", "status": "marked", "value": 2}, {})
	assert_eq(GameState.status_stacks(&"marked"), 2, "target defaults to the player")

func test_the_apply_status_effect_reaches_the_board() -> void:
	_choose_solo(_enemy("Beat it"))
	EffectSystem.apply({"type": "apply_status", "status": "strength", "value": 1,
		"target": "current"}, {})
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.arrival()).size(), 1)
	assert_eq(GameState.status_stacks(&"strength"), 0, "and not the player")

func test_player_statuses_round_trip_through_a_save() -> void:
	GameState.apply_status(&"marked", 3)
	GameState.apply_status(&"strength", 1)
	var blob: Dictionary = GameState.serialize_statuses()
	GameState.reset_run()
	assert_eq(GameState.status_list().size(), 0, "cleared by the run reset")
	GameState.restore_statuses(blob)
	assert_eq(GameState.status_stacks(&"marked"), 3)
	assert_eq(GameState.status_stacks(&"strength"), 1)

func test_a_status_id_the_catalog_lost_is_dropped_on_load() -> void:
	GameState.restore_statuses({"marked": 2, "deleted_status": 5})
	assert_eq(GameState.status_stacks(&"marked"), 2)
	assert_false(GameState.has_status(&"deleted_status"),
		"a status with no resource would render as a blank clause")

func test_enemy_statuses_round_trip_through_a_save() -> void:
	_choose_solo(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	GameLoop2.beat_game(false)
	var blob: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	assert_eq(GameLoop2.stack.size(), 0)
	GameLoop2.restore(blob)
	# The synthetic enemy isn't in the catalog, so the entry itself won't rehydrate
	# — assert on the serialized shape instead, which is what SaveSystem writes.
	var saved: Array = blob.get("stack", [])
	assert_eq(saved.size(), 1)
	assert_eq(int((saved[0]["statuses"] as Dictionary).get("marked", 0)), 2,
		"the body's statuses are in the save blob")

func test_a_real_enemy_keeps_its_statuses_across_a_save() -> void:
	var real: GoalEnemyData = Data.all_goal_enemies()[0]
	_choose_solo(real)
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	GameLoop2.beat_game(false)
	var blob: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	GameLoop2.restore(blob)
	assert_eq(GameLoop2.stack.size(), 1, "the body came back")
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0])[0]["stacks"], 2,
		"and so did its Marked")

# --- the display contract -------------------------------------------------

func test_goal_text_of_an_empty_entry_is_empty_not_a_crash() -> void:
	assert_eq(GameLoop2.goal_text_for({}), "", "no current game, no goal line")

func test_a_side_with_no_reward_still_renders_its_wording() -> void:
	# A payout-free objective is legal — nothing in the schema requires a reward.
	var s: StatusData = _status(&"synthetic",
		_sideblock("goal", "you do the thing"),
		_sideblock("bonus", "you do the thing"))
	assert_eq(s.objective_text(StatusData.PLAYER, 1), "If you do the thing",
		"no reward, no trailing comma")
	assert_eq(s.objective_text(StatusData.ENEMY, 1), "and if you do the thing")

func test_a_side_left_blank_is_inert() -> void:
	# A status is allowed to act on only one side; the other reads as doing nothing
	# rather than as an empty clause welded onto every goal.
	var s: StatusData = _status(&"synthetic", _sideblock("goal", "you do the thing"))
	assert_true(s.has_side(StatusData.PLAYER))
	assert_false(s.has_side(StatusData.ENEMY))
	assert_eq(s.mode_for(StatusData.ENEMY), &"")
	assert_false(s.is_claimable(StatusData.ENEMY))

# ---------------------------------------------------------------------------
# 4. The views — where a status is actually READ
#
# The board is the primary surface: the player's own statuses under the hero's
# portrait, an enemy's under its box. Both go through the same pip and the same
# tooltip, so a status cannot say one thing in one place and something else in
# another.
# ---------------------------------------------------------------------------

const OVERWORLD := preload("res://scenes/redesign2/Overworld2.tscn")

# A mounted overworld with a run under way, for the view tests.
func _booted():
	var ui = OVERWORLD.instantiate()
	add_child_autofree(ui)
	ui.choose_start(0)
	# The opening game stands an ESCORT beside its enemy (§7.5). Everything below
	# is about what a status does to ONE body, so it comes straight back off —
	# same reason as _choose_solo above.
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return ui

func test_the_hero_strip_shows_the_players_statuses() -> void:
	var ui = _booted()
	assert_false(ui._board._hero_statuses.visible, "hidden while nothing is on you")
	GameState.apply_status(&"marked", 2)
	GameState.apply_status(&"strength", 1)
	ui._board.refresh()
	assert_true(ui._board._hero_statuses.visible, "and shown once something is")
	assert_eq(ui._board._hero_statuses.get_child_count(), 2, "one pip per status")

func test_the_hero_strip_sits_between_the_portrait_and_the_health() -> void:
	# The order is the whole point of where it was put: tries / who you are / what
	# is riding you / what is left of you.
	var ui = _booted()
	GameState.apply_status(&"marked", 1)
	ui._board.refresh()
	var column: Node = ui._board._hero_statuses.get_parent()
	var portrait: Node = ui._board._hero_icon.get_parent()   # the framed portrait
	assert_gt(ui._board._hero_statuses.get_index(), portrait.get_index(),
		"statuses come after the portrait")
	assert_lt(ui._board._hero_statuses.get_index(), ui._board._hero_hp.get_index(),
		"and before the health")
	assert_eq(column, ui._board._hero_hp.get_parent(), "all in the one hero column")

# A pip's hover is a CARD now (HoverCard), not a wall of plain text — so what it
# says is asserted off the model the card is built from rather than off
# `tooltip_text`, which is only the fallback string.
func test_a_status_pip_carries_the_full_hover_card() -> void:
	var ui = _booted()
	GameState.apply_status(&"speed", 3)
	ui._board.refresh()
	var pip: Control = ui._board._hero_statuses.get_child(0)
	assert_true(pip.has_meta(HoverCard.META), "the pip carries a hover card")
	var card: Dictionary = pip.get_meta(HoverCard.META)
	assert_eq(String(card.get("title", "")), "Speed", "the name heads it")
	assert_string_contains(String(card.get("subtitle", "")), "3 stacks",
		"with the live stack count under it")
	assert_string_contains("\n".join(PackedStringArray(card.get("lines", []))),
		"1 hour 30 minutes", "and the line at that stack")
	# The fallback text Godot needs before it will ask for a custom tooltip at all.
	assert_string_contains(pip.tooltip_text, "Speed", "and the plain fallback still names it")

# The card is drawable, and what it draws is what the model said.
func test_a_hover_card_draws_its_model() -> void:
	var speed: StatusData = Data.get_status(&"speed")
	var card: Control = HoverCard.build(speed.hover_card(StatusData.PLAYER, 3))
	assert_not_null(card, "the model builds a card")
	assert_string_contains(_all_text(card), "Speed", "with the name on it")
	assert_string_contains(_all_text(card), "3 stacks", "and the stack count")
	card.queue_free()

# Every Label in a built card, joined — which of them holds a line is layout.
func _all_text(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	for child in node.get_children():
		out += _all_text(child)
	return out

func test_the_tooltip_names_what_each_side_does() -> void:
	var marked: StatusData = Data.get_status(&"marked")
	assert_string_contains(marked.tooltip_for(StatusData.PLAYER, 2),
		"Every enemy's goal also needs", "the player side taxes every goal")
	assert_string_contains(marked.tooltip_for(StatusData.ENEMY, 2),
		"Bonus", "the enemy side pays out")
	assert_string_contains(marked.tooltip_for(StatusData.PLAYER, 2),
		"Loses a stack", "and a decaying side says so")

func test_an_enemys_statuses_draw_under_its_box() -> void:
	var ui = _booted()
	ui.pick(0)
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	ui.report(false)                      # it walks onto the board carrying Marked
	ui._board.refresh()
	assert_eq(GameLoop2.stack.size(), 1)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var node: Control = ui._board._enemy_nodes.get(inst)
	assert_not_null(node, "the body has a node on the board")
	var badges: Control = node.get_meta("badges")
	# The strip is the one badge child that is a container of pips rather than a
	# label, and it hangs BELOW the box (a negative bottom offset).
	var strip: Control = null
	for child in badges.get_children():
		if child is HBoxContainer:
			strip = child
	assert_not_null(strip, "a status strip was added")
	assert_eq(strip.get_child_count(), 1, "one pip for the one status")
	# Pinned to the box's BOTTOM edge and pushed outward from it — the two halves
	# of "below the box, not over the art". The resolved offsets are asserted on
	# the anchors rather than on pixels, because a Control's offsets are not
	# settled until it has been laid out and this test never renders a frame.
	assert_eq(strip.anchor_top, 1.0, "anchored to the bottom edge")
	assert_eq(strip.anchor_bottom, 1.0)
	assert_gt(BattlefieldView.STATUS_STRIP_DROP, 0, "and pushed out past it")

# ---------------------------------------------------------------------------
# 5. The COMBAT side (§13.4)
#
# The half of the mechanic that moves a number instead of a goal. Four numbers,
# one aggregator, and one rule about who feels them — so these tests are mostly
# about the seams: that both holders read the same totals, that a hit on an enemy
# and a hit on the player go through the same arithmetic, and that a shield is a
# pool that gets spent rather than a reading of a stack count.
# ---------------------------------------------------------------------------

# A synthetic status with only a combat side, so the rules can be tested without
# the authored roster's goals coming along for the ride.
func _combat_status(id: StringName, combat: Dictionary, enemy_only: bool = true) -> StatusData:
	var s: StatusData = _status(id)
	s.combat = combat
	s.enemy_only = enemy_only
	return s

# --- what the sheet authored ----------------------------------------------

func test_the_roster_authored_the_combat_sides_the_sheet_promises() -> void:
	assert_eq(Data.get_status(&"strength").combat_bonus(&"damage_dealt", 3), 3,
		"Strength: +X damage dealt")
	assert_eq(Data.get_status(&"speed").combat_bonus(&"tile_move", 2), 2,
		"Speed: +X tiles per turn")
	assert_eq(Data.get_status(&"dexterity").combat_bonus(&"shield", 4), 4,
		"Dexterity: +X shields")
	assert_eq(Data.get_status(&"marked").combat_mult(&"damage_taken"), 2.0,
		"Marked: double damage taken")
	assert_true(Data.get_status(&"marked").pierces_shields(), "and through shields")

func test_only_the_debuff_reaches_the_player() -> void:
	# EnemyOnly is what Buff/Debuff always meant: a debuff is felt by whoever is
	# carrying it, a buff only ever by an enemy.
	for id in [&"strength", &"speed", &"dexterity"]:
		var buff: StatusData = Data.get_status(id)
		assert_true(buff.combat_applies(StatusData.ENEMY), "%s acts on an enemy" % id)
		assert_false(buff.combat_applies(StatusData.PLAYER), "%s does not on the player" % id)
	var marked: StatusData = Data.get_status(&"marked")
	assert_true(marked.combat_applies(StatusData.ENEMY))
	assert_true(marked.combat_applies(StatusData.PLAYER), "Marked is felt both ways")

func test_a_multiplier_is_flat_while_a_bonus_scales() -> void:
	# A doubling that compounded per stack would turn a 1-damage board into a
	# 16-damage one off a status the player never chose to stack.
	var marked: StatusData = Data.get_status(&"marked")
	for stacks in [1, 3, 7]:
		assert_eq(marked.combat_mult(&"damage_taken"), 2.0,
			"still x2 at %d stacks" % stacks)
	var strength: StatusData = Data.get_status(&"strength")
	assert_eq(strength.combat_bonus(&"damage_dealt", 1), 1)
	assert_eq(strength.combat_bonus(&"damage_dealt", 4), 4, "the bonus does scale")

# --- the aggregator -------------------------------------------------------

func test_bonuses_sum_multipliers_multiply_and_flags_or() -> void:
	# Two synthetic statuses, so this asserts the ARITHMETIC rather than whatever
	# the roster happens to author today. They are put in and taken back out of the
	# catalog around the one call, because combat_totals resolves ids through Data.
	Data._statuses[&"synth_a"] = _combat_status(
		&"synth_a", {"damage_dealt": "X", "damage_taken_mult": 2.0})
	Data._statuses[&"synth_b"] = _combat_status(
		&"synth_b", {"damage_dealt": "X", "damage_taken_mult": 3.0, "pierce_shields": true})
	var totals: Dictionary = StatusData.combat_totals(
		{&"synth_a": 2, &"synth_b": 3}, StatusData.ENEMY)
	Data._statuses.erase(&"synth_a")
	Data._statuses.erase(&"synth_b")
	assert_eq(int(totals["damage_dealt"]), 5, "2 + 3")
	assert_eq(float(totals["damage_taken_mult"]), 6.0, "2 x 3")
	assert_true(bool(totals["pierce_shields"]), "one piercer is enough")

func test_a_status_the_catalog_lost_contributes_nothing_to_the_totals() -> void:
	# The same rule the goal side keeps: an id nothing can describe is skipped
	# rather than being read as a zero-stack anything.
	var totals: Dictionary = StatusData.combat_totals({&"no_such_status": 4},
		StatusData.ENEMY)
	assert_eq(int(totals["damage_dealt"]), 0)
	assert_eq(float(totals["damage_taken_mult"]), 1.0)

func test_an_empty_holder_totals_to_no_change() -> void:
	var totals: Dictionary = StatusData.combat_totals({}, StatusData.ENEMY)
	assert_eq(int(totals["damage_dealt"]), 0)
	assert_eq(float(totals["damage_taken_mult"]), 1.0, "a multiplier of one, not zero")
	assert_false(bool(totals["pierce_shields"]))

func test_the_bonus_lands_before_the_multiplier() -> void:
	assert_eq(StatusData.apply_damage_mods(1, 1, 2.0), 4, "(1 + 1) x 2")
	assert_eq(StatusData.apply_damage_mods(3, 0, 1.0), 3, "no mods, no change")
	assert_eq(StatusData.apply_damage_mods(1, -5, 2.0), 0, "and never below zero")

# --- Strength: what a hit lands for ---------------------------------------

func test_strength_raises_what_an_enemy_hits_for() -> void:
	var ui = _booted()
	ui.pick(0)
	var base: int = int(GameLoop2.arrival()["enemy"].damage)
	assert_eq(GameLoop2.enemy_damage(GameLoop2.arrival()), base, "unbuffed, it is the stat")
	GameLoop2.apply_enemy_status(&"strength", 2, "current")
	assert_eq(GameLoop2.enemy_damage(GameLoop2.arrival()), base + 2, "+1 per stack")

func test_a_strength_stack_is_felt_on_the_players_health() -> void:
	var ui = _booted()
	ui.pick(0)
	ui.report(false)                       # it walks onto the board and starts closing
	GameState.shields = 0                  # no tries left, so every point lands on Health
	GameLoop2.apply_enemy_status(&"strength", 3, "all")
	# Walk it into the front column so it actually swings this game.
	for entry in GameLoop2.stack:
		entry["col"] = 1
	var before: int = GameState.hp
	var enemy_dmg: int = GameLoop2.enemy_damage(GameLoop2.stack[0])
	GameLoop2.beat_game(false)
	assert_eq(before - GameState.hp, enemy_dmg * GameLoop2.enemy_turns(),
		"every swing landed for the buffed number")

func test_the_damage_badge_quotes_the_buffed_number() -> void:
	# A badge reading the base stat would be telling the player the board is safer
	# than it is.
	var ui = _booted()
	ui.pick(0)
	ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	GameLoop2.apply_enemy_status(&"strength", 2, "all")
	assert_true(ui._board._damage_badge_text(entry, 1).contains(
		str(GameLoop2.enemy_damage(entry))), "the badge says what it will hit for")

# --- Dexterity: a shield is a pool, spent once ----------------------------

func test_dexterity_grants_shield_points_when_it_lands() -> void:
	var ui = _booted()
	ui.pick(0)
	assert_eq(GameLoop2.enemy_shield(GameLoop2.arrival()), 0)
	GameLoop2.apply_enemy_status(&"dexterity", 2, "current")
	assert_eq(GameLoop2.enemy_shield(GameLoop2.arrival()), 2, "one point per stack")

func test_a_shield_absorbs_a_hit_instead_of_the_body_taking_it() -> void:
	var ui = _booted()
	ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	GameLoop2.apply_enemy_status(&"dexterity", 2, "current")
	var health: int = int(GameLoop2.arrival()["health"])
	GameLoop2.beat_game(true)              # goal met — one point of damage
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_false(entry.is_empty(), "it survived: the shield ate the hit")
	assert_eq(GameLoop2.enemy_shield(entry), 1, "and spent one point doing it")
	assert_eq(int(entry["health"]), health, "Health is untouched")

func test_a_spent_shield_does_not_come_back_with_the_stacks() -> void:
	# The shield is what Dexterity GAVE the body, not a reading of how much
	# Dexterity it has — so soaking a hit costs a point that stays gone.
	var ui = _booted()
	ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	GameLoop2.apply_enemy_status(&"dexterity", 2, "current")
	GameLoop2.beat_game(true)
	var entry: Dictionary = GameLoop2.entry_for(inst)
	assert_eq(GameLoop2.enemy_statuses(entry)[0]["stacks"], 2, "both stacks still on it")
	assert_eq(GameLoop2.enemy_shield(entry), 1, "but only one shield left")

func test_a_second_application_tops_the_shield_up() -> void:
	var ui = _booted()
	ui.pick(0)
	GameLoop2.apply_enemy_status(&"dexterity", 1, "current")
	GameLoop2.apply_enemy_status(&"dexterity", 2, "current")
	assert_eq(GameLoop2.enemy_shield(GameLoop2.arrival()), 3,
		"the difference between the old X and the new one")

func test_a_shielded_body_dies_once_the_shield_is_gone() -> void:
	var ui = _booted()
	ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	GameLoop2.apply_enemy_status(&"dexterity", 1, "current")
	GameLoop2.beat_game(true)              # shield 1 -> 0
	assert_false(GameLoop2.entry_for(inst).is_empty(), "still standing")
	assert_true(GameLoop2.fulfill(inst), "the next hit is fulfilled")
	assert_true(GameLoop2.entry_for(inst).is_empty(), "and this one killed it")

func test_a_shield_survives_a_save() -> void:
	# Recomputing it from the stacks on load would hand back the point the body
	# already spent, which is why it is saved beside Health.
	var ui = _booted()
	ui.pick(0)
	GameLoop2.apply_enemy_status(&"dexterity", 3, "current")
	GameLoop2.beat_game(true)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var left: int = GameLoop2.enemy_shield(GameLoop2.entry_for(inst))
	var blob: Dictionary = GameLoop2.serialize()
	GameLoop2.reset()
	GameLoop2.restore(blob)
	assert_eq(GameLoop2.enemy_shield(GameLoop2.stack[0]), left, "the pool came back as it was")

# --- Marked: double damage, straight through shields ----------------------

func test_marked_doubles_the_damage_an_enemy_takes() -> void:
	var ui = _booted()
	ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	# Alien Baby makes a body take two goals to put down; Marked puts it down in
	# one, which is the whole point of the status.
	GameLoop2.arrival()["health"] = 2
	GameLoop2.apply_enemy_status(&"marked", 1, "current")
	GameLoop2.beat_game(true)
	assert_true(GameLoop2.entry_for(inst).is_empty(), "one goal was worth two damage")

func test_marked_ignores_a_shield_rather_than_spending_it() -> void:
	var ui = _booted()
	ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	GameLoop2.apply_enemy_status(&"dexterity", 5, "current")
	GameLoop2.apply_enemy_status(&"marked", 1, "current")
	GameLoop2.beat_game(true)
	assert_true(GameLoop2.entry_for(inst).is_empty(),
		"five shields stopped none of it")

func test_marked_on_the_player_doubles_what_lands_and_skips_the_tries() -> void:
	# The rule that makes EnemyOnly worth having: a debuff is felt by whoever is
	# carrying it, Shields included.
	var ui = _booted()
	ui.pick(0)
	ui.report(false)
	for entry in GameLoop2.stack:
		entry["col"] = 1
	GameState.shields = 10                 # plenty of tries to absorb it, in theory
	GameState.apply_status(&"marked", 1)
	var swing: int = GameLoop2.enemy_damage(GameLoop2.stack[0])
	var turns: int = GameLoop2.enemy_turns()
	var before: int = GameState.hp
	var res: Dictionary = GameLoop2.beat_game(false)
	assert_eq(before - GameState.hp, swing * 2 * turns, "doubled, and all of it on Health")
	# `blocked` rather than the shield count: shields are the tries at ONE game and
	# expire when it resolves (§3), so reading them afterwards would say 0 whether
	# they were spent or merely lost.
	assert_eq(int(res["blocked"]), 0, "the tries absorbed nothing")

func test_an_unmarked_player_still_spends_shields_first() -> void:
	var ui = _booted()
	ui.pick(0)
	ui.report(false)
	for entry in GameLoop2.stack:
		entry["col"] = 1
	GameState.shields = 10
	var before: int = GameState.hp
	var res: Dictionary = GameLoop2.beat_game(false)
	assert_eq(GameState.hp, before, "the tries took it, as they always have")
	assert_gt(int(res["blocked"]), 0, "and were spent doing so")

# --- Speed: extra tiles per turn ------------------------------------------

func test_speed_closes_extra_columns_per_turn() -> void:
	var ui = _booted()
	ui.pick(0)
	ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	entry["col"] = GameLoop2.grid_cols()
	var start: int = int(entry["col"])
	GameLoop2.apply_status_to(int(entry["instance"]), &"speed", 1)
	GameLoop2._advance_stack()
	assert_eq(int(entry["col"]), start - 2, "one step of its own, plus one from Speed")

func test_speed_stops_at_the_front_column_rather_than_overshooting() -> void:
	var ui = _booted()
	ui.pick(0)
	ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	entry["col"] = 2
	GameLoop2.apply_status_to(int(entry["instance"]), &"speed", 5)
	GameLoop2._advance_stack()
	assert_eq(int(entry["col"]), 1, "melee is as far as anything walks")

func test_a_stunned_body_does_not_move_however_fast_it_is() -> void:
	var ui = _booted()
	ui.pick(0)
	ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	entry["col"] = GameLoop2.grid_cols()
	entry["stun"] = 1
	var start: int = int(entry["col"])
	GameLoop2.apply_status_to(int(entry["instance"]), &"speed", 3)
	GameLoop2._advance_stack()
	assert_eq(int(entry["col"]), start, "a stun beats Speed")

# --- the tooltip ----------------------------------------------------------

func test_the_tooltip_carries_the_combat_line_at_the_live_stack() -> void:
	var tip: String = Data.get_status(&"strength").tooltip_for(StatusData.ENEMY, 3)
	assert_true(tip.contains("+3 damage"), "the number in force, not the sheet's X")

func test_the_tooltip_says_when_a_buff_is_enemies_only() -> void:
	# Otherwise a player holding Strength has a pip that looks like it does
	# something and a tooltip that never mentions it doesn't.
	var tip: String = Data.get_status(&"strength").tooltip_for(StatusData.PLAYER, 2)
	assert_true(tip.to_lower().contains("enemies only"))

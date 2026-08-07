extends GutTest

# Tests for Statuses 2.0 (docs/games-first-redesign.md §13) — the goal-rewriting
# balance lever locations, items and scrolls reach the run through.
#
# Three layers, in the order a status passes through them:
#   1. the CONTENT — statuses2.0 loads, and its {expr} holes resolve to the
#      numbers the sheet's prose promises;
#   2. the RULES — the four quadrants (buff/debuff x player/enemy) each rewrite
#      goals the way §13 says, and decay only where it should;
#   3. the WIRING — the apply_status effect verb, and save/load round-trips for
#      both the player's statuses and the ones riding bodies on the board.

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
func _status(id: StringName, kind: StringName, condition: String,
		reward: Array = [], decays: bool = false) -> StatusData:
	var s := StatusData.new()
	s.id = id
	s.display_name = String(id).capitalize()
	s.kind = kind
	s.condition = condition
	s.reward = reward
	s.decays_on_complete = decays
	return s

# ---------------------------------------------------------------------------
# 1. The content
# ---------------------------------------------------------------------------

func test_the_statuses_sheet_loaded() -> void:
	assert_gt(Data.all_statuses().size(), 0, "data/statuses2.0 loaded at least one status")
	for id in [&"strength", &"dexterity", &"marked"]:
		assert_not_null(Data.get_status(id), "%s is in the catalog" % id)

func test_strength_and_dexterity_are_buffs_marked_is_a_debuff() -> void:
	assert_true(Data.get_status(&"strength").is_buff(), "Strength is a buff")
	assert_true(Data.get_status(&"dexterity").is_buff(), "Dexterity is a buff")
	assert_true(Data.get_status(&"marked").is_debuff(), "Marked is a debuff")

func test_only_debuffs_decay_on_completion() -> void:
	# The design call in §13: a buff persists because it IS the reward; a debuff
	# sheds a stack each time you satisfy it, which is what makes it survivable.
	assert_false(Data.get_status(&"strength").decays_on_complete, "Strength persists")
	assert_true(Data.get_status(&"marked").decays_on_complete, "Marked ticks down")

func test_a_flat_condition_scales_with_the_stack() -> void:
	var marked: StatusData = Data.get_status(&"marked")
	assert_eq(marked.condition_text(1), "you get 1 achievements")
	assert_eq(marked.condition_text(3), "you get 3 achievements")

func test_dexterity_window_tightens_on_the_authored_curve() -> void:
	# 1 + (1/2)^(X-2) hours, halving toward a floor of one hour. These are the
	# numbers the sheet's formula promises, and the reason the {expr} holes exist
	# at all — the ONLY status behaviour that isn't a straight multiple of X.
	var dex: StatusData = Data.get_status(&"dexterity")
	assert_eq(dex.condition_text(1), "beaten in 3 hours or less")
	assert_eq(dex.condition_text(2), "beaten in 2 hours or less")
	assert_eq(dex.condition_text(3), "beaten in 1.5 hours or less")
	assert_eq(dex.condition_text(4), "beaten in 1.25 hours or less")

func test_whole_numbers_lose_their_decimal_tail() -> void:
	# "beaten in 2 hours", never "beaten in 2.0 hours" — this is read on a
	# checklist row, not printed to a log.
	assert_eq(StatusData.format_number(2.0), "2")
	assert_eq(StatusData.format_number(1.5), "1.5")
	assert_eq(StatusData.format_number(1.125), "1.125")

func test_rewards_scale_with_the_stack() -> void:
	var strength: StatusData = Data.get_status(&"strength")
	var effects: Array = strength.reward_effects(3)
	assert_eq(effects.size(), 2, "Strength pays a chest and a Bash")
	for eff in effects:
		assert_eq(int(eff.get("value", 0)), 3, "%s scales to X" % eff.get("type"))
		assert_false(eff.has("scaled"), "the {expr} hole is resolved, not passed through")
	assert_eq(int(effects[0].get("choices", 0)), 1, "a Small Chest offers one item (§8.2)")

func test_reward_text_reads_at_the_live_stack() -> void:
	assert_eq(Data.get_status(&"strength").reward_at(2), "+2 Small Chests, +2 Bashes")
	assert_eq(Data.get_status(&"marked").reward_at(1), "+1 Small Chest")

func test_every_status_has_art_and_a_condition() -> void:
	for s in Data.all_statuses():
		var sd: StatusData = s
		assert_ne(sd.condition, "", "%s authored a condition" % sd.id)
		assert_not_null(sd.image, "%s resolved its art" % sd.id)

# ---------------------------------------------------------------------------
# 2. The rules — the four quadrants
# ---------------------------------------------------------------------------

func test_a_buff_on_the_player_is_an_extra_goal_not_a_clause() -> void:
	GameState.apply_status(&"strength", 2)
	GameLoop2.choose_game(_enemy("Beat it"))
	# It pays the player; it does not tighten anything the enemy asked for.
	assert_eq(GameLoop2.goal_text_for(GameLoop2.current), "Beat it",
		"a player buff leaves enemy goals alone")
	var buffs: Array = GameState.status_buffs()
	assert_eq(buffs.size(), 1, "it shows up as a standing goal")
	assert_string_contains(String((buffs[0]["status"] as StatusData).player_goal_text(2)),
		"the difficulty is increased 2 times")

func test_a_buff_on_an_enemy_tightens_that_enemys_goal() -> void:
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 2, "current")
	assert_eq(GameLoop2.goal_text_for(GameLoop2.current),
		"Beat it and the difficulty is increased 2 times")

func test_a_debuff_on_the_player_tightens_every_enemys_goal() -> void:
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.beat_game(false)          # it walks onto the board
	GameLoop2.choose_game(_enemy("Beat another"))
	GameState.apply_status(&"marked", 3)
	assert_eq(GameLoop2.goal_text_for(GameLoop2.current),
		"Beat another and you get 3 achievements", "the current enemy")
	assert_eq(GameLoop2.goal_text_for(GameLoop2.stack[0]),
		"Beat it and you get 3 achievements", "and the follower too")

func test_a_debuff_on_an_enemy_is_a_bonus_not_a_requirement() -> void:
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	assert_eq(GameLoop2.goal_text_for(GameLoop2.current), "Beat it",
		"the goal itself is untouched")
	var bonuses: Array = GameLoop2.bonus_objectives_for(GameLoop2.current)
	assert_eq(bonuses.size(), 1, "it hangs a bonus objective off the enemy")
	assert_string_contains((bonuses[0]["status"] as StatusData).bonus_text(2),
		"and if you get 2 achievements")

func test_clauses_stack_enemy_first_then_player() -> void:
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 1, "current")
	GameState.apply_status(&"marked", 2)
	assert_eq(GameLoop2.goal_text_for(GameLoop2.current),
		"Beat it and the difficulty is increased 1 times and you get 2 achievements",
		"the enemy's own clause reads before the one every enemy carries")

# --- targeting ------------------------------------------------------------

func test_target_all_covers_the_board_and_the_current_enemy() -> void:
	GameLoop2.choose_game(_enemy("A"))
	GameLoop2.beat_game(false)
	GameLoop2.choose_game(_enemy("B"))
	assert_eq(GameLoop2.apply_enemy_status(&"marked", 1, "all"), 2, "both bodies")
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.current).size(), 1)
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0]).size(), 1)

func test_target_current_leaves_the_followers_alone() -> void:
	GameLoop2.choose_game(_enemy("A"))
	GameLoop2.beat_game(false)
	GameLoop2.choose_game(_enemy("B"))
	assert_eq(GameLoop2.apply_enemy_status(&"marked", 1, "current"), 1)
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0]).size(), 0,
		"the follower is untouched")

func test_target_random_lands_on_exactly_one_body() -> void:
	GameLoop2.choose_game(_enemy("A"))
	GameLoop2.beat_game(false)
	GameLoop2.choose_game(_enemy("B"))
	assert_eq(GameLoop2.apply_enemy_status(&"marked", 1, "random"), 1)
	var total: int = GameLoop2.enemy_statuses(GameLoop2.current).size() \
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
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	GameLoop2.beat_game(false)
	assert_eq(GameLoop2.stack.size(), 1)
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0]).size(), 1,
		"Marked came with it")
	# Marked is a DEBUFF, so on an enemy it is a bonus objective — not a clause on
	# the goal. The quadrant, not just the status, has to survive the move.
	assert_eq(GameLoop2.goal_text_for(GameLoop2.stack[0]), "Beat it")
	assert_eq(GameLoop2.bonus_objectives_for(GameLoop2.stack[0]).size(), 1,
		"and it is still a bonus over there")

func test_an_enemy_buff_survives_it_walking_onto_the_board() -> void:
	# The same move for the other quadrant: a buff's clause has to still be welded
	# onto the goal once the enemy is a follower.
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 2, "current")
	GameLoop2.beat_game(false)
	assert_eq(GameLoop2.goal_text_for(GameLoop2.stack[0]),
		"Beat it and the difficulty is increased 2 times")

# ---------------------------------------------------------------------------
# 2b. Decay and payout
# ---------------------------------------------------------------------------

func test_a_player_debuff_ticks_once_for_a_game_whose_goal_was_met() -> void:
	GameState.apply_status(&"marked", 3)
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"marked"), 2, "one stack for the completion")

func test_a_player_debuff_does_not_tick_on_a_missed_goal() -> void:
	GameState.apply_status(&"marked", 3)
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.beat_game(false)
	assert_eq(GameState.status_stacks(&"marked"), 3, "nothing was completed")

func test_a_player_debuff_does_not_tick_on_a_free_game() -> void:
	# A game with no enemy reports goal_met = true (the checklist auto-clears), but
	# a goal nobody set can't have carried the clause.
	GameState.apply_status(&"marked", 2)
	GameLoop2.beat_game(true)
	assert_eq(GameState.status_stacks(&"marked"), 2)

func test_a_player_debuff_ticks_once_per_game_not_once_per_goal() -> void:
	# Clearing four followers in one game must not wipe a 4-stack debuff whole:
	# the sheet's "decrease stack by 1 when completed" is a per-game count.
	GameState.apply_status(&"marked", 4)
	var instances: Array = []
	for i in range(3):
		instances.append(GameLoop2.choose_game(_enemy("Goal %d" % i)))
		GameLoop2.beat_game(false)
	GameLoop2.choose_game(_enemy("Current"))
	GameLoop2.beat_game(true, instances)
	assert_eq(GameState.status_stacks(&"marked"), 3, "one tick for the whole game")

func test_a_player_debuff_falls_off_at_zero() -> void:
	GameState.apply_status(&"marked", 1)
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.beat_game(true)
	assert_false(GameState.has_status(&"marked"), "spent")
	assert_eq(GameState.status_list().size(), 0, "and pruned, not left at zero")

func test_a_player_buff_pays_out_and_stays() -> void:
	GameState.apply_status(&"strength", 2)
	GameState.bash = 0
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.beat_game(true, [], {"status_goals": [&"strength"]})
	assert_eq(GameState.bash, 2, "+X Bashes at X = 2")
	assert_eq(GameState.pending_chests, 2, "+X Small Chests at X = 2")
	assert_eq(GameState.status_stacks(&"strength"), 2, "the buff persists — it is the reward")

func test_a_player_buff_pays_nothing_when_its_goal_is_not_ticked() -> void:
	GameState.apply_status(&"strength", 2)
	GameState.bash = 0
	GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.beat_game(true)
	assert_eq(GameState.bash, 0, "an unticked standing goal is simply not claimed")

func test_claiming_an_enemy_bonus_pays_and_ticks_that_enemy() -> void:
	var inst: int = GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	var res: Dictionary = GameLoop2.beat_game(false, [],
		{"bonuses": [{"instance": inst, "status": &"marked"}]})
	assert_eq(int(res.get("status_rewards", 0)), 1, "the claim resolved")
	assert_eq(GameState.pending_chests, 2, "+X Small Chests at X = 2")
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.stack[0])[0]["stacks"], 1,
		"one stack spent on the claim")

func test_an_enemy_bonus_can_be_claimed_on_the_game_that_kills_it() -> void:
	# The claim is resolved BEFORE the board is, so beating an enemy and claiming
	# its bonus in the same game pays both rather than swallowing the bonus.
	var inst: int = GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"marked", 1, "current")
	var res: Dictionary = GameLoop2.beat_game(true, [],
		{"bonuses": [{"instance": inst, "status": &"marked"}]})
	assert_eq(int(res.get("status_rewards", 0)), 1, "the bonus still paid")
	assert_eq(GameLoop2.stack.size(), 0, "and the enemy still died")

func test_a_buff_cannot_be_claimed_as_an_enemy_bonus() -> void:
	# The quadrants are not interchangeable: a buff on an enemy is a tax, and
	# there is nothing to claim on it.
	var inst: int = GameLoop2.choose_game(_enemy("Beat it"))
	GameLoop2.apply_enemy_status(&"strength", 2, "current")
	assert_false(GameLoop2.claim_enemy_bonus(inst, &"strength"))
	assert_eq(GameState.pending_chests, 0)

func test_a_debuff_cannot_be_claimed_as_a_player_goal() -> void:
	GameState.apply_status(&"marked", 2)
	assert_false(GameLoop2.complete_player_status_goal(&"marked"))
	assert_eq(GameState.status_stacks(&"marked"), 2, "and nothing ticked")

# ---------------------------------------------------------------------------
# 3. The wiring
# ---------------------------------------------------------------------------

func test_the_apply_status_effect_reaches_the_player() -> void:
	EffectSystem.apply({"type": "apply_status", "status": "marked", "value": 2}, {})
	assert_eq(GameState.status_stacks(&"marked"), 2, "target defaults to the player")

func test_the_apply_status_effect_reaches_the_board() -> void:
	GameLoop2.choose_game(_enemy("Beat it"))
	EffectSystem.apply({"type": "apply_status", "status": "strength", "value": 1,
		"target": "current"}, {})
	assert_eq(GameLoop2.enemy_statuses(GameLoop2.current).size(), 1)
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
	GameLoop2.choose_game(_enemy("Beat it"))
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
	GameLoop2.choose_game(real)
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

func test_a_status_with_no_reward_still_renders_its_clause() -> void:
	# A tax-only status is legal — nothing in the schema requires a payout.
	var s: StatusData = _status(&"synthetic", &"buff", "you do the thing")
	assert_eq(s.player_goal_text(1), "If you do the thing",
		"no reward, no trailing comma")
	assert_eq(s.bonus_text(1), "and if you do the thing")

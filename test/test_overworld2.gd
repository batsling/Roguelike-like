extends GutTest

# Drive tests for the Overworld2 panel — the click-to-choose games-first
# overworld. It must build headless, boot a real start/amulet graph, and drive a
# run through the same public methods its cards call (pick -> report), plus the
# board verbs (bash/transmute) and the difficulty-gate boss round.

const SCENE := preload("res://scenes/redesign2/Overworld2.tscn")

var _ui

func before_each() -> void:
	_ui = SCENE.instantiate()
	add_child_autofree(_ui)   # _ready -> builds UI + boots a run

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func test_boots_a_run_with_a_graph_and_choices() -> void:
	assert_false(GameLoop2.run_over, "a fresh run is live")
	assert_ne(String(GameState.current_game_id), "", "player placed on a start game")
	assert_ne(String(GameState.amulet_game_id), "", "an amulet was picked")
	assert_gt(_ui._choices.size(), 0, "the start's neighbours are offered as choices")

func test_each_choice_has_a_game_and_a_previewable_enemy() -> void:
	for c in _ui._choices:
		assert_true(c["game"] is GameData, "choice carries a real game")
		assert_true(c["enemy"] is GoalEnemyData, "choice pre-rolled an enemy for hover")

func test_pick_then_report_advances_the_loop() -> void:
	var target: StringName = _ui._choices[0]["game"].id
	_ui.pick(0)
	assert_true(GameLoop2.has_current(), "picking spawns the enemy")
	assert_eq(GameState.current_game_id, target, "player travelled to the picked game")
	var gp_before: int = GameState.games_played
	_ui.report(false)             # miss -> the enemy stacks and follows
	assert_eq(GameState.games_played, gp_before + 1, "the game counts as played")
	assert_eq(GameLoop2.stack_size(), 1, "a missed goal leaves a following enemy")
	assert_gt(_ui._choices.size(), 0, "a fresh offering is drawn from the new position")

func test_report_goal_met_defeats_and_drops() -> void:
	_ui.pick(0)
	_ui.report(true)              # met -> defeat + a drop in the tray, nothing stacks
	assert_eq(GameLoop2.stack_size(), 0, "a met goal leaves nothing following")
	assert_eq(_ui._drop_queue.size(), 1, "the kill queued a drop")

# An enemy kill drops loot into the tray under the inventory, right of the grid
# (not a RewardScreen chest, §8); claiming it adds the item and clears the drop.
func test_defeat_drop_is_collectable_from_the_loot_tray() -> void:
	_ui.pick(0)
	_ui.report(true)
	assert_eq(_ui._drop_queue.size(), 1, "a drop is waiting to be claimed")
	assert_eq(_ui._loot_box.get_child_count(), 1, "and it shows as a row in the loot tray")
	# No RewardScreen is opened for an enemy drop anymore.
	var found: RewardScreen = null
	for c in _ui.get_children():
		if c is RewardScreen:
			found = c
			break
	assert_null(found, "enemy drops go to the tray, not a RewardScreen")
	var inv_before: int = GameState.inventory.size()
	_ui._collect_drop(_ui._drop_queue[0])        # click Claim
	assert_eq(_ui._drop_queue.size(), 0, "the drop was consumed")
	assert_eq(GameState.inventory.size(), inv_before + 1, "claiming adds the item")
	assert_eq(_ui._items_box.get_child_count(), GameState.inventory.size(),
		"and the inventory panel beside the board lists it")

func test_skipped_drop_is_discarded() -> void:
	_ui.pick(0)
	_ui.report(true)
	assert_eq(_ui._drop_queue.size(), 1)
	var inv_before: int = GameState.inventory.size()
	_ui._skip_drop(_ui._drop_queue[0])           # click Skip
	assert_eq(_ui._drop_queue.size(), 0, "the drop was cleared")
	assert_eq(GameState.inventory.size(), inv_before, "skipping keeps the inventory unchanged")

func test_fulfilling_a_follower_goal_defeats_and_drops_it() -> void:
	# Miss a goal so an enemy follows, then on the next game tick its fulfilment
	# checkbox: it should be defeated (and drop) before it can hit (§2).
	_ui.pick(0)
	_ui.report(false)
	assert_eq(GameLoop2.stack_size(), 1, "a missed goal leaves a follower")
	var hp_before: int = GameState.hp
	var drops_before: int = _ui._drop_queue.size()
	_ui.pick(0)                                  # play another game
	assert_eq(_ui._fulfil_checks.size(), 1, "the follower is offered for fulfilment")
	_ui._fulfil_checks[0]["check"].button_pressed = true
	_ui.report(false)                            # miss current, but fulfil the follower
	assert_eq(_ui._drop_queue.size(), drops_before + 1, "the fulfilled follower dropped into the tray")
	assert_eq(GameState.hp, hp_before, "fulfilling it before it hit means no damage")
	# The only follower now is this game's freshly-stacked enemy, not the old one.
	assert_eq(GameLoop2.stack_size(), 1, "old follower gone; current game's enemy stacked")

# --- battlefield interaction (click-to-inspect + combat verbs) -------------
#
# The board is a BattlefieldView mounted by the overworld (_ui._board): clicks and
# the combat toolbar live there, while the inspect card it asks for is opened by
# the overworld, which owns the Push / Bomb charges.

func test_clicking_an_enemy_selects_it_and_opens_its_card() -> void:
	_ui.pick(0)
	_ui.report(false)                              # an enemy now follows
	var entry: Dictionary = GameLoop2.stack[0]
	var inst: int = int(entry["instance"])
	_ui._board.click_enemy(inst, entry, int(entry["col"]), false)
	assert_eq(_ui._board.selected_instance, inst, "the clicked enemy is targeted")
	assert_not_null(_ui._info_popup, "its info card opened")
	_ui._close_enemy_info()
	assert_null(_ui._info_popup, "the card closes")

func test_the_game_being_played_is_not_targetable_by_the_verbs() -> void:
	_ui.pick(0)                                    # its enemy waits off the field
	var cur: Dictionary = GameLoop2.current
	_ui._board.click_enemy(int(cur["instance"]), cur, GameLoop2.OFFGRID_COL, true)
	assert_eq(_ui._board.selected_instance, 0, "the current game's enemy can't be pushed/bombed")
	assert_not_null(_ui._info_popup, "but its card still opens")

func test_toolbar_push_is_disabled_without_a_target_or_room() -> void:
	GameState.push = 1
	_ui.pick(0)
	_ui.report(false)
	_ui._board.selected_instance = 0
	_ui._board.refresh_toolbar()
	assert_true(_ui._board.push_btn.disabled, "no target -> Push is unavailable")
	# Target the follower: it sits at the back column, so there's nowhere to shove it.
	var inst: int = int(GameLoop2.stack[0]["instance"])
	_ui._board.selected_instance = inst
	_ui._board.refresh_toolbar()
	assert_eq(int(GameLoop2.stack[0]["col"]), GameLoop2.SPAWN_COL)
	assert_true(_ui._board.push_btn.disabled, "nothing behind the back column -> Push is unavailable")

func test_selection_clears_when_the_enemy_dies() -> void:
	GameState.bombs = 1
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	_ui._board.selected_instance = inst
	_ui.bomb_follower(inst)
	assert_eq(GameLoop2.stack_size(), 0, "the bomb removed it")
	assert_eq(_ui._board.selected_instance, 0, "the dead target is deselected")

func test_report_accepts_an_explicit_fulfilment_list() -> void:
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	_ui.pick(0)
	_ui.report(false, [inst])                    # explicit list bypasses the checkboxes
	for entry in GameLoop2.stack:
		assert_ne(int(entry["instance"]), inst, "the explicitly-fulfilled follower is gone")

func test_level_up_checkbox_grants_the_reward() -> void:
	# Zoe's level-up is "Perfect a Game" -> +1 Dash. Ticking the level-up box on
	# report should apply the character's level_up_stats.
	_ui.start_run(&"zoe")
	var dash_before: int = GameState.dash_charges
	var lvl_before: int = GameState.player_level
	_ui.pick(0)
	assert_not_null(_ui._levelup_check, "Zoe has a level-up condition -> a checkbox")
	_ui._levelup_check.button_pressed = true
	_ui.report(true)
	assert_eq(GameState.dash_charges, dash_before + 1, "level-up granted +1 Dash")
	assert_eq(GameState.player_level, lvl_before + 1, "player level advanced")

func test_level_up_not_applied_when_unchecked() -> void:
	_ui.start_run(&"zoe")
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_ui.report(true)                              # box left unticked
	assert_eq(GameState.dash_charges, dash_before, "no level-up without the tick")

func test_isaac_level_up_grants_a_chest() -> void:
	_ui.start_run(&"isaac")                       # reward_type item -> Small Chest
	var chests_before: int = GameState.pending_chests
	_ui.pick(0)
	if _ui._levelup_check != null:
		_ui._levelup_check.button_pressed = true
	_ui.report(false)
	assert_eq(GameState.pending_chests, chests_before + 1, "Isaac's level-up banks a chest")

func test_dash_offers_every_connected_game_and_spends_a_charge() -> void:
	GameState.dash_charges = 1
	_ui._build_choices()
	var capped: int = _ui._choices.size()
	var all_nbrs: int = 0
	for gid in RunGraph.neighbors(GameState.current_game_id):
		if not GameLoop2.is_bashed(gid):
			all_nbrs += 1
	_ui.dash()
	assert_true(_ui._dash_mode, "dash mode is on")
	assert_eq(_ui._choices.size(), all_nbrs, "dash offers every connected game")
	if all_nbrs > _ui.offer_count():
		assert_gt(_ui._choices.size(), capped, "dash exceeds the normal cap")
	_ui.pick(0)
	assert_eq(GameState.dash_charges, 0, "the dash pick spent the charge")
	assert_false(_ui._dash_mode, "dash mode cleared after the pick")

func test_cancel_dash_restores_the_limited_offering() -> void:
	GameState.dash_charges = 1
	_ui._build_choices()
	var capped: int = _ui._choices.size()
	_ui.dash()
	_ui.cancel_dash()
	assert_false(_ui._dash_mode)
	assert_eq(GameState.dash_charges, 1, "cancel didn't spend a charge")
	assert_eq(_ui._choices.size(), capped, "offering back to the capped set")

# --- offering size + scramble (§4/§7) --------------------------------------

# The offering is three cards (or every neighbour, when a node has fewer).
func test_offering_is_capped_at_three() -> void:
	assert_eq(_ui.BASE_OFFER_COUNT, 3, "the base offering is three games")
	assert_eq(_ui.offer_count(), 3, "with no bonus, three cards are visible")
	var nbrs: int = RunGraph.neighbors(GameState.current_game_id).size()
	assert_eq(_ui._choices.size(), mini(3, nbrs), "at most three games are offered")

# Items / level-ups widen the offering by granting the "game_choices" stat.
func test_game_choices_bonus_widens_the_offering() -> void:
	# Walk to a node with room to grow, so the cap is what's limiting the count.
	var attempts: int = 0
	while RunGraph.neighbors(GameState.current_game_id).size() <= 3 and attempts < 12:
		_ui.pick(0)
		_ui.report(false)
		attempts += 1
	if RunGraph.neighbors(GameState.current_game_id).size() <= 3:
		# Thin graph run — nothing to widen into. Assert what still holds there (the
		# graph, not the cap, is the limit) so the test is never silent.
		assert_lte(_ui._choices.size(), _ui.offer_count(),
			"a thin node offers at most the cap")
		return
	var before: int = _ui._choices.size()
	GameState.grant_run_stat("game_choices", 2)
	assert_gte(GameState.game_choice_bonus, 2, "the bonus lands on GameState")
	assert_eq(_ui.offer_count(), 3 + GameState.game_choice_bonus, "the visible count grew with it")
	_ui._build_choices()
	assert_gt(_ui._choices.size(), before, "more games are offered")

# Scramble spends a charge and re-rolls the offering: fresh enemies always, and
# fresh games too wherever the node has more neighbours than the cap.
func test_scramble_rerolls_the_offering_and_spends_a_charge() -> void:
	GameState.scramble = 1
	var before_slots: Array = []
	var before_enemies: Array = []
	for c in _ui._choices:
		before_slots.append(c["slot"])
		before_enemies.append(c["enemy"])
	assert_true(_ui.scramble(), "a charge rerolls the offering")
	assert_eq(GameState.scramble, 0, "the charge is spent")
	assert_eq(_ui._choices.size(), before_slots.size(), "the same number of cards is offered")
	var slots_after: Array = []
	for c in _ui._choices:
		slots_after.append(c["slot"])
	if RunGraph.neighbors(GameState.current_game_id).size() > _ui.offer_count():
		assert_ne(slots_after, before_slots, "a spare neighbour means new games are drawn")
	for c in _ui._choices:
		assert_true(c["enemy"] is GoalEnemyData, "every rerolled card has a fresh enemy")

func test_scramble_needs_a_charge_and_the_select_phase() -> void:
	GameState.scramble = 0
	assert_false(_ui.scramble(), "no charge -> no reroll")
	GameState.scramble = 1
	_ui.pick(0)                                   # -> Phase.PLAYING
	assert_false(_ui.scramble(), "you can't reroll a game you're already playing")
	assert_eq(GameState.scramble, 1, "a refused scramble is not spent")

func test_boss_round_on_difficulty_gate() -> void:
	# The tier steps every GAMES_PER_TIER games; that crossing is a boss round.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	_ui._build_choices()
	assert_true(_ui._boss_round, "a games-played multiple of the tier step is a boss round")
	for c in _ui._choices:
		assert_true(bool(c["boss"]), "every boss-round choice spawns a boss")

func test_boss_is_the_capstone_of_the_tier_just_played() -> void:
	# Boss rounds are every GAMES_PER_TIER games; each boss rolls at the tier the
	# player just cleared (game-4 boss is Low), then the run advances. Once on
	# Insane, bosses stay Insane.
	var T := RunDifficulty.Tier
	# Normal games use the plain tier.
	GameState.games_played = 2
	assert_eq(_ui._current_tier(), T.LOW, "games 1-3 are Low")
	GameState.games_played = 4
	assert_eq(_ui._current_tier(), T.MEDIUM, "games after the first boss are Medium")
	# Boss rounds cap the tier just played.
	GameState.games_played = 3   # game 4 boss
	assert_true(_ui._is_boss_round())
	assert_eq(_ui._current_tier(), T.LOW, "the game-4 boss is a Low boss")
	GameState.games_played = 6   # game 7 boss
	assert_eq(_ui._current_tier(), T.MEDIUM, "the next boss is Medium")
	GameState.games_played = 9   # game 10 boss
	assert_eq(_ui._current_tier(), T.HIGH, "then High")
	GameState.games_played = 12  # game 13 boss
	assert_eq(_ui._current_tier(), T.INSANE, "then Insane")
	GameState.games_played = 15  # every 3 games on Insane
	assert_true(_ui._is_boss_round())
	assert_eq(_ui._current_tier(), T.INSANE, "Insane bosses keep coming every 3 games")

func test_bash_removes_a_choice_from_the_pool() -> void:
	GameState.bash = 1
	_ui._build_choices()
	var bashed_id: StringName = _ui._choices[0]["slot"]
	_ui.bash_choice(0)
	assert_true(GameLoop2.is_bashed(bashed_id), "the game is destroyed out of the pool")
	assert_eq(GameState.bash, 0, "bash spent a charge")
	# The bashed game no longer appears in the offering (a limited offering may
	# backfill the freed slot from the reachable pool).
	for c in _ui._choices:
		assert_ne(c["slot"], bashed_id, "bashed game not re-offered")

func test_bash_allowed_on_boss_round_still_faces_a_boss() -> void:
	# The boss is tied to the difficulty gate, not the game: you may bash the
	# offered game, but whatever backfills the slot still spawns a boss.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	GameState.bash = 1
	_ui._build_choices()
	var bashed_id: StringName = _ui._choices[0]["slot"]
	_ui.bash_choice(0)
	assert_eq(GameState.bash, 0, "bash is allowed on a boss round")
	assert_true(GameLoop2.is_bashed(bashed_id), "the game was destroyed")
	assert_true(_ui._boss_round, "still a boss round after bashing")
	for c in _ui._choices:
		assert_true(bool(c["boss"]), "every remaining choice still spawns a boss")

func test_transmute_on_boss_round_still_faces_a_boss() -> void:
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	GameState.transmute = 1
	_ui._build_choices()
	if _ui._choices.size() < 2:
		pass_test("graph too sparse for an off-map transmute target")
		return
	var slot: StringName = _ui._choices[0]["slot"]
	_ui.transmute_choice(0)
	# The slot's game may have been swapped for an off-graph game...
	for c in _ui._choices:
		if c["slot"] == slot:
			assert_true(bool(c["boss"]), "the transmuted game still spawns a boss")

extends GutTest

# Drive tests for the Overworld2 panel — the click-to-choose games-first
# overworld. It must build headless, boot a real start/amulet graph, and drive a
# run through the same public methods its cards call (pick -> report), plus the
# board verbs (bash/transmute) and the difficulty-gate boss round.

const SCENE := preload("res://scenes/redesign2/Overworld2.tscn")
const OVERWORLD := preload("res://scripts/redesign2/Overworld2.gd")

var _ui

func before_each() -> void:
	_ui = SCENE.instantiate()
	add_child_autofree(_ui)   # _ready -> builds UI + rolls the choose-your-start panel
	# A fresh run opens on the START-SELECT panel (three genres, all the same
	# distance from the amulet); taking one is what gives the run a position, so
	# every test below starts from there.
	_ui.choose_start(0)

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	SaveSystem.clear_all_saves()
	SaveSystem.cancel_pending_resume()

# Re-boot the run on a specific character and take the first offered start, so a
# test that needs a particular level-up / loadout lands where before_each does.
func _reboot(character_id: StringName) -> void:
	_ui.start_run(character_id)
	_ui.choose_start(0)

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

func test_toolbar_bomb_is_offered_against_a_boss() -> void:
	# A boss takes no bomb damage, but it IS a legal target — that is the only way
	# to land Sticky Bombs' stun — so the button stays live and the tooltip warns.
	GameState.bombs = 1
	var boss := GoalEnemyData.new()
	boss.id = &"synthetic_boss"
	boss.display_name = "Synthetic Boss"
	boss.boss = true
	boss.health = 1
	boss.damage = 5
	var inst: int = GameLoop2.spawn_to_stack(boss)
	_ui._board.selected_instance = inst
	_ui._board.refresh_toolbar()
	assert_false(_ui._board.bomb_btn.disabled, "a boss can be bombed")
	assert_true(_ui._board.bomb_btn.tooltip_text.contains("boss"),
		"and the tooltip says the damage won't land")
	GameState.bombs = 0
	_ui._board.refresh_toolbar()
	assert_true(_ui._board.bomb_btn.disabled, "no charge -> no bomb")

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
	_reboot(&"zoe")
	var dash_before: int = GameState.dash_charges
	var lvl_before: int = GameState.player_level
	_ui.pick(0)
	assert_not_null(_ui._levelup_check, "Zoe has a level-up condition -> a checkbox")
	_ui._levelup_check.button_pressed = true
	_ui.report(true)
	assert_eq(GameState.dash_charges, dash_before + 1, "level-up granted +1 Dash")
	assert_eq(GameState.player_level, lvl_before + 1, "player level advanced")

func test_level_up_not_applied_when_unchecked() -> void:
	_reboot(&"zoe")
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_ui.report(true)                              # box left unticked
	assert_eq(GameState.dash_charges, dash_before, "no level-up without the tick")

func test_isaac_level_up_grants_a_chest() -> void:
	_reboot(&"isaac")                       # reward_type item -> Small Chest
	var chests_before: int = GameState.pending_chests
	_ui.pick(0)
	if _ui._levelup_check != null:
		_ui._levelup_check.button_pressed = true
	_ui.report(false)
	assert_eq(GameState.pending_chests, chests_before + 1, "Isaac's level-up banks a chest")

func test_poe_level_up_grants_a_size_rolled_chest() -> void:
	_reboot(&"poe_ratcho")                  # reward_type random_sized_chest
	var chests_before: int = GameState.pending_chests
	_ui.pick(0)
	if _ui._levelup_check != null:
		_ui._levelup_check.button_pressed = true
	_ui.report(false)
	assert_eq(GameState.pending_chests, chests_before + 1, "Poe's level-up banks a chest")
	var choices: int = GameState.pending_chest_choices.back()
	assert_true([1, 2, 3, 5].has(choices),
		"chest SIZE is rolled: Small=1 / Medium=2 / Large=3 / Huge=5, got %d" % choices)

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

# --- shields = the tries at the game you selected (§3.2) -------------------

func test_picking_a_game_grants_its_shields() -> void:
	assert_eq(GameState.shields, 0, "no tries before a game is selected")
	var game: GameData = _ui._choices[0]["game"]
	var expected: int = GameLoop2.shields_for_game(game)
	_ui.pick(0)
	assert_eq(GameState.shields, expected,
		"%s granted its %d tries" % [game.display_name, expected])
	assert_eq(expected, 5 if game.type == GameData.GameType.TRADITIONAL else 3,
		"5 for a Traditional roguelike, 3 for anything else")

func test_anchor_adds_a_try_on_top_of_the_grant() -> void:
	GameState.add_item(Data.get_item2(&"anchor"))
	var game: GameData = _ui._choices[0]["game"]
	_ui.pick(0)
	assert_eq(GameState.shields, GameLoop2.shields_for_game(game) + 1,
		"Anchor's shield lands on selection, before you go and play")

func test_shields_expire_when_the_game_is_reported() -> void:
	_ui.pick(0)
	assert_gt(GameState.shields, 0)
	_ui.report(true)
	assert_eq(GameState.shields, 0, "the tries belonged to that game")

# --- the attempt tracker ---------------------------------------------------

func test_ticking_an_attempt_spends_a_shield_then_health() -> void:
	_ui.pick(0)
	var shields: int = GameState.shields
	assert_eq(_ui.log_attempt(), "shield")
	assert_eq(GameState.shields, shields - 1, "a lost run costs a shield")
	assert_true(_ui._attempt_count.text.contains("1"), "the strip counts it: %s" % _ui._attempt_count.text)
	assert_true(_ui._attempt_pips.text.contains("◇"), "and a pip goes hollow: %s" % _ui._attempt_pips.text)
	# Burn the rest, then the next tick has to come off Health.
	while GameState.shields > 0:
		_ui.log_attempt()
	var hp: int = GameState.hp
	assert_eq(_ui.log_attempt(), "health")
	assert_eq(GameState.hp, hp - GameLoop2.ATTEMPT_HEALTH_COST)
	assert_true(_ui._attempt_hint.text.contains("Health"),
		"and the strip warns what the next one costs: %s" % _ui._attempt_hint.text)

func test_undoing_an_attempt_restores_the_shield() -> void:
	_ui.pick(0)
	var shields: int = GameState.shields
	_ui.log_attempt()
	assert_eq(_ui.undo_attempt(), "shield")
	assert_eq(GameState.shields, shields, "the shield came back")
	assert_eq(GameLoop2.attempts(), 0)
	assert_true(_ui._attempt_undo.disabled, "nothing left to take back")

func test_the_tracker_is_only_live_while_a_game_is_in_play() -> void:
	assert_true(_ui._attempt_btn.disabled, "no game selected -> nothing to lose runs of")
	_ui.pick(0)
	assert_false(_ui._attempt_btn.disabled, "a game in play -> the tracker is live")
	_ui.report(true)
	assert_true(_ui._attempt_btn.disabled, "reported -> closed again")

# Between games the pool is empty, so the HUD previews the grant of whatever card
# you're pointing at — the number is part of the routing decision.
func test_the_hud_previews_the_hovered_games_grant() -> void:
	assert_true(_ui._hud.text.contains("[b]Shields[/b] 0"),
		"nothing hovered -> the live (empty) pool: %s" % _ui._hud.text)
	_ui._show_preview(0)                          # hovering the first card
	var grant: int = GameLoop2.shields_for_game(_ui._choices[0]["game"])
	assert_true(_ui._hud.text.contains("+%d" % grant),
		"hovering previews what that game grants: %s" % _ui._hud.text)
	_ui._clear_hover_grant()                      # mouse left the card
	assert_true(_ui._hud.text.contains("[b]Shields[/b] 0"),
		"and it can't advertise a game you're not pointing at: %s" % _ui._hud.text)
	# Once a game is in play the slot is the live pool again, hover or not.
	_ui.pick(0)
	assert_true(_ui._hud.text.contains("[b]Shields[/b] %d" % GameState.shields),
		"in play it's the real count: %s" % _ui._hud.text)

func test_the_offering_shows_the_tries_each_game_grants() -> void:
	var labels: Array = []
	for card in _ui._choices_row.get_children():
		for child in card.get_children():
			if child is Label:
				labels.append(String((child as Label).text))
	var joined: String = "\n".join(labels)
	assert_true(joined.contains("tries"), "each card states its shield grant: %s" % joined)

# --- the board / checklist stage -------------------------------------------

# The stage keeps its shape in both phases — checklist left, board right — so the
# board is never hidden and the checklist never appears from nowhere. Only the
# checklist's contents and the report-only controls change.
func test_the_stage_keeps_its_shape_in_both_phases() -> void:
	assert_true(_ui._select_box.visible, "the offering is up while choosing")
	assert_true(_ui._board.visible, "the board is on screen with it")
	assert_true(_ui._play_panel.visible, "and so is the checklist")
	assert_eq(_ui._stage_panel.get_parent(), _ui._right_col, "board on the right")
	assert_false(_ui._done_btn.visible, "but there's no game to complete yet")
	assert_false(_ui._attempt_wrap.visible, "and no runs to be losing")
	assert_false(_ui._np_box.visible, "and nothing being played")
	_ui.pick(0)
	assert_eq(_ui._stage_panel.get_parent(), _ui._right_col, "the board hasn't moved")
	assert_eq(_ui._stage_panel.get_index(), 0, "still above the pack in that column")
	assert_true(_ui._play_panel.visible, "the checklist is now the report step")
	assert_true(_ui._done_btn.visible, "with something to complete")
	assert_true(_ui._attempt_wrap.visible, "and runs to lose")
	assert_false(_ui._select_box.visible, "the offering is out of the way")

# Choosing a game, the checklist lists the goals already on you: the character's
# level-up challenge and every follower's outstanding goal.
func test_the_standing_checklist_lists_what_you_owe() -> void:
	_reboot(&"isaac")                       # Isaac has a level-up condition
	var texts := func() -> String:
		var out: Array = []
		for row in _ui._verify_box.get_children():
			if row is Label:
				out.append(String((row as Label).text))
			for child in row.get_children():
				if child is Label:
					out.append(String((child as Label).text))
		return "\n".join(out)
	var listed: String = texts.call()
	assert_true(listed.contains("What you need to do"), "the panel says what it is: %s" % listed)
	assert_true(listed.contains("Unlock a new Item"), "the level-up challenge is listed: %s" % listed)
	assert_true(listed.contains("Nothing is following you"), "and an empty stack says so: %s" % listed)
	# Miss a goal so an enemy follows: its goal joins the list.
	_ui.pick(0)
	_ui.report(false)
	var follower: GoalEnemyData = GameLoop2.stack[0]["enemy"]
	listed = texts.call()
	assert_true(listed.contains(follower.goal),
		"the follower's outstanding goal is listed: %s" % listed)
	assert_false(listed.contains("Nothing is following you"), "and the empty note is gone")

func test_the_standing_checklist_has_no_tick_boxes() -> void:
	# Nothing is reportable until a game is in play, so the standing list is rows.
	for row in _ui._verify_box.get_children():
		for child in row.get_children():
			assert_false(child is CheckBox, "the standing list is read-only")
	assert_eq(_ui._fulfil_checks.size(), 0, "and holds no fulfilment state")
	assert_null(_ui._goal_check)
	assert_null(_ui._levelup_check)

# The stage is two columns: what you tick on the left, what you look at on the
# right — board first, the pack under it.
func test_the_checklist_sits_left_of_the_board_with_the_pack_below() -> void:
	_ui.pick(0)
	assert_eq(_ui._left_col.get_parent(), _ui._right_col.get_parent(), "one row holds both columns")
	assert_lt(_ui._left_col.get_index(), _ui._right_col.get_index(),
		"the checklist column comes first — it's on the left")
	assert_true(_ui._left_col.is_ancestor_of(_ui._play_panel), "the checklist is in the left column")
	assert_true(_ui._right_col.is_ancestor_of(_ui._board), "the board is in the right column")
	assert_true(_ui._right_col.is_ancestor_of(_ui._pack_col), "and so is the pack")
	assert_lt(_ui._stage_panel.get_index(), _ui._pack_col.get_index(),
		"the pack sits under the board, not over it")
	# On screen, that has to actually be left-of / below — tree order alone would
	# still pass if the columns were stacked. Needs a frame for layout to run.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(_ui._play_panel.global_position.x, _ui._board.global_position.x,
		"the checklist is drawn to the left of the board")
	assert_gt(_ui._pack_col.global_position.y, _ui._board.global_position.y,
		"the pack is drawn below the board")

func test_the_pack_stays_in_the_right_column_in_both_phases() -> void:
	assert_true(_ui._right_col.is_ancestor_of(_ui._pack_col), "choosing: the pack is on the right")
	assert_true(_ui._pack_col.visible, "and the inventory never goes away")
	_ui.pick(0)
	assert_true(_ui._right_col.is_ancestor_of(_ui._pack_col), "playing: it stays there")
	assert_true(_ui._pack_col.visible)

func test_the_summary_line_counts_the_followers() -> void:
	_ui.pick(0)
	_ui.report(false)                    # a missed goal leaves one following
	assert_eq(GameLoop2.stack.size(), 1)
	assert_true(_ui._stack.text.contains("1 closing in"),
		"the board's own heading says what's out there: %s" % _ui._stack.text)

# --- rating is a button, never a pop-up -----------------------------------

func _rating_modal():
	for c in _ui.get_children():
		if c is RateGameModal:
			return c
	return null

func test_reporting_a_game_never_pops_the_rating_modal() -> void:
	_ui.pick(0)
	_ui.report(true)
	assert_null(_rating_modal(), "finishing a game doesn't force the rating prompt")

func test_the_played_game_stays_rateable_from_a_button() -> void:
	var played: GameData = _ui._choices[0]["game"]
	_ui.pick(0)
	_ui.report(true)
	assert_eq(_ui._last_played_game, played, "the reported game is remembered for rating")
	# The select-screen controls row offers it as a button.
	var labels: Array = []
	for c in _ui._controls_row.get_children():
		if c is Button:
			labels.append(String(c.text))
	var joined: String = "\n".join(labels)
	assert_true(joined.contains("Rate %s" % played.display_name),
		"a '★ Rate <game>' button is offered: %s" % joined)
	# Pressing it is what opens the modal.
	_ui._prompt_rating(played)
	var modal: Control = _rating_modal()
	assert_not_null(modal, "the button opens the rating modal")
	# And it covers the screen, so the dim reads and clicks can't fall through to
	# the board behind it.
	assert_gt(modal.size.x, 0.0, "the modal fills the viewport")
	assert_gt(modal.size.y, 0.0, "the modal fills the viewport")

# --- repeat beats pay a Dash (REPEAT_BEAT_DASH) ----------------------------

func test_first_clear_records_the_game_and_grants_no_dash() -> void:
	var played: GameData = _ui._choices[0]["game"]
	var dash_before: int = GameState.dash_charges
	var lifetime_before: int = GameStats.beaten_count(played.id)
	_ui.pick(0)
	_ui.report(true)
	assert_true(GameState.has_beaten_game(played.id), "the clear is banked on the run")
	assert_eq(GameState.dash_charges, dash_before, "a first clear pays nothing extra")
	assert_eq(GameStats.beaten_count(played.id), lifetime_before + 1,
		"and the lifetime tally the Collection shows moved too")

func test_beating_a_game_again_grants_a_dash() -> void:
	# Stand where a game you've already cleared is on offer (the run graph lets you
	# double back, so an offered game can be one you beat earlier).
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_beaten(target.id)
	_ui._build_choices()
	assert_eq(_ui._choices[0]["game"], target, "the offering is stable for the position")
	assert_true(bool(_ui._choices[0]["repeat"]), "the card is flagged as a repeat")
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_ui.report(true)
	assert_eq(GameState.dash_charges, dash_before + _ui.REPEAT_BEAT_DASH,
		"beating it a second time granted a Dash")

func test_repeat_card_shows_the_dash_bonus_above_it() -> void:
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_beaten(target.id)
	_ui._build_choices()
	_ui._render_choices()
	var first: Node = _ui._choices_row.get_child(0).get_child(0)
	assert_true(first is Label, "the bonus sits ABOVE the cover art")
	assert_eq((first as Label).text, "⚡ Gain +%d Dash" % _ui.REPEAT_BEAT_DASH,
		"and it says what beating it again grants")
	# A game not yet beaten keeps the row (so the covers stay in line) but says
	# nothing in it.
	GameState.beaten_games.clear()
	_ui._build_choices()
	_ui._render_choices()
	var plain: Node = _ui._choices_row.get_child(0).get_child(0)
	assert_true(plain is Label and (plain as Label).text == "",
		"an unbeaten game's card has an empty bonus row")

# --- revisiting a game offers a different draw -----------------------------

# The offering is drawn in a stable position-seeded order, but ARRIVING at a game
# again re-seeds it: doubling back is a fresh decision, not a rerun.
func test_revisiting_a_game_redraws_the_offering() -> void:
	# Find a hub with more neighbours than the offering can show — only there can
	# the games in the slots change at all.
	var hub: StringName = &""
	for g in Data.all_games():
		if RunGraph.neighbors(g.id).size() > _ui.offer_count() + 2:
			hub = g.id
			break
	if hub == &"":
		pass_test("no hub node in this run's graph")
		return
	GameState.set_current_game(hub)          # arrival #1
	_ui._build_choices()
	var first_draw: Array = _ui._choices.map(func(c): return c["slot"])
	# Re-building without moving must NOT reshuffle (bash / transmute rely on it).
	_ui._build_choices()
	assert_eq(_ui._choices.map(func(c): return c["slot"]), first_draw,
		"standing still keeps the same games in the slots")
	# Walk away and come back a few times: the draw has to change.
	var changed: bool = false
	for _i in range(4):
		GameState.set_current_game(&"__elsewhere__")
		GameState.set_current_game(hub)      # arrival #2, #3, …
		_ui._build_choices()
		if _ui._choices.map(func(c): return c["slot"]) != first_draw:
			changed = true
			break
	assert_true(changed, "revisiting %s drew a different set of games" % hub)

# --- a pickup's effects show on the HUD immediately ------------------------

func test_claimed_loot_updates_the_hud_immediately() -> void:
	var heart: ItemData = Data.get_item2(&"hollow_heart")   # +4 Max Health on acquire
	assert_not_null(heart)
	var max_before: int = GameState.max_hp
	var drop: Dictionary = {"item": heart}
	_ui._drop_queue.append(drop)
	_ui._refresh_loot()
	_ui._collect_drop(drop)
	assert_eq(GameState.max_hp, max_before + 4, "the pickup's effect landed")
	assert_true(_ui._hud.text.contains("%d/%d" % [GameState.hp, GameState.max_hp]),
		"and the HUD already shows it: %s" % _ui._hud.text)

func test_hud_follows_a_verb_gain_without_a_loop_resolve() -> void:
	var before: String = _ui._hud.text
	GameState.grant_run_stat("dash", 2)      # emits stats_changed, no loop tick
	assert_ne(_ui._hud.text, before, "the HUD repaints off the stat change")
	assert_true(_ui._hud.text.contains("[b]Dash[/b] %d" % GameState.dash_charges),
		"showing the new Dash count: %s" % _ui._hud.text)

func test_bash_removes_a_choice_from_the_pool() -> void:
	GameState.bash = 1
	_ui._build_choices()
	var idx: int = _first_bashable()
	var bashed_id: StringName = _ui._choices[idx]["slot"]
	_ui.bash_choice(idx)
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
	var idx: int = _first_bashable()
	var bashed_id: StringName = _ui._choices[idx]["slot"]
	_ui.bash_choice(idx)
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

# --- helpers for the sections below ---------------------------------------

# The first offered card that bash is actually allowed to destroy — bashing the
# amulet is refused (it's the run's goal), and picking index 0 blindly makes any
# bash test flaky on the runs where the amulet lands in the offering.
func _first_bashable() -> int:
	for i in range(_ui._choices.size()):
		if not bool(_ui._choices[i]["amulet"]):
			return i
	return 0

# A game with more connections than the offering can show, so there is a spare
# neighbour for a bashed slot to be refilled from. &"" when the graph has none.
func _hub_with_spare_neighbours() -> StringName:
	for g in Data.all_games():
		if RunGraph.neighbors(g.id).size() > _ui.offer_count() + 1:
			return g.id
	return &""

# --- choose your start (the run's opening screen) --------------------------

func test_a_fresh_run_opens_on_the_start_picker() -> void:
	_ui.start_run()
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT, "a fresh run opens on the start picker")
	assert_eq(String(GameState.current_game_id), "", "no position on the graph until one is taken")
	assert_ne(String(GameState.amulet_game_id), "", "but the amulet is already rolled")
	assert_true(_ui._choices.is_empty(), "and there is no travel offering yet")

func test_the_start_picker_offers_three_games_of_different_types() -> void:
	_ui.start_run()
	assert_eq(_ui._start_options.size(), RunGraph.NUM_START_OPTIONS,
		"the panel offers %d starts" % RunGraph.NUM_START_OPTIONS)
	var types: Dictionary = {}
	for opt in _ui._start_options:
		types[int(opt["type"])] = true
	assert_eq(types.size(), _ui._start_options.size(), "each offered start is a different game type")

func test_every_offered_start_sits_in_the_amulet_distance_band() -> void:
	_ui.start_run()
	for opt in _ui._start_options:
		var game: GameData = opt["game"]
		var dist: Dictionary = RunGraph.bfs_distances(game.id)
		var hops: int = int(dist.get(GameState.amulet_game_id, -1))
		assert_eq(hops, int(opt["path_len"]),
			"%s's card shows its real graph distance" % game.display_name)
		assert_true(hops >= RunGraph.MIN_PATH_LENGTH and hops <= RunGraph.MAX_PATH_LENGTH,
			"%s is %d games from the amulet, inside the %d-%d band" % [
				game.display_name, hops, RunGraph.MIN_PATH_LENGTH, RunGraph.MAX_PATH_LENGTH])

func test_choosing_a_start_places_the_player_and_draws_the_first_offering() -> void:
	_ui.start_run()
	var chosen: GameData = _ui._start_options[1]["game"]
	_ui.choose_start(1)
	assert_eq(GameState.current_game_id, chosen.id, "the player stands on the chosen start")
	assert_eq(GameState.start_game_id, chosen.id, "and the run records it as its start")
	assert_eq(_ui._phase, OVERWORLD.Phase.SELECT, "the run falls through to the normal offering")
	assert_true(_ui._start_options.is_empty(), "the start panel is done with")
	assert_gt(_ui._choices.size(), 0, "the start's neighbours are on the table")
	# The start is where you BEGIN, not a game you were sent to beat.
	assert_false(GameLoop2.has_current(), "no enemy spawns for the start game")
	assert_eq(GameState.shields, 0, "and it grants no tries")

func test_the_start_picker_ignores_a_travel_pick() -> void:
	_ui.start_run()
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT, "travel is not a thing yet")
	assert_false(GameLoop2.has_current(), "and nothing spawned")

# --- bash: destroy the game, refill the slot from the same pool -------------

func test_bash_refills_the_slot_from_a_connected_game() -> void:
	var hub: StringName = _hub_with_spare_neighbours()
	if hub == &"":
		pass_test("no node with a spare connection in this run's graph")
		return
	GameState.set_current_game(hub)
	_ui._build_choices()
	GameState.bash = 1
	var idx: int = _first_bashable()
	var bashed_id: StringName = _ui._choices[idx]["slot"]
	var before: Array = _ui._choices.map(func(c): return c["slot"])
	_ui.bash_choice(idx)
	var after: Array = _ui._choices.map(func(c): return c["slot"])
	assert_true(GameLoop2.is_bashed(bashed_id), "the bashed game is destroyed for the run")
	assert_eq(after.size(), before.size(), "the offering kept its size")
	assert_false(after.has(bashed_id), "the destroyed game is off the table")
	var fresh: Array = after.filter(func(s): return not before.has(s))
	assert_eq(fresh.size(), 1, "exactly one new game took the freed slot")
	assert_true(RunGraph.neighbors(hub).has(StringName(fresh[0])),
		"and the replacement is connected to where the player is standing")

func test_a_bashed_slot_never_offers_the_destroyed_game_again() -> void:
	var hub: StringName = _hub_with_spare_neighbours()
	if hub == &"":
		pass_test("no node with a spare connection in this run's graph")
		return
	GameState.set_current_game(hub)
	_ui._build_choices()
	GameState.bash = 1
	var bashed_id: StringName = _ui._choices[_first_bashable()]["slot"]
	_ui.bash_choice(_first_bashable())
	# Walk away and come back — a re-seeded draw must still skip the destroyed game.
	for _i in range(4):
		GameState.set_current_game(&"__elsewhere__")
		GameState.set_current_game(hub)
		_ui._build_choices()
		for c in _ui._choices:
			assert_ne(c["slot"], bashed_id, "the destroyed game stays out of the pool")

func test_bashing_one_card_leaves_the_other_cards_enemies_alone() -> void:
	var hub: StringName = _hub_with_spare_neighbours()
	if hub == &"":
		pass_test("no node with a spare connection in this run's graph")
		return
	GameState.set_current_game(hub)
	_ui._build_choices()
	GameState.bash = 1
	var idx: int = _first_bashable()
	var kept: Dictionary = {}
	for i in range(_ui._choices.size()):
		if i != idx:
			kept[_ui._choices[i]["slot"]] = (_ui._choices[i]["enemy"] as GoalEnemyData).id
	_ui.bash_choice(idx)
	for c in _ui._choices:
		if kept.has(c["slot"]):
			assert_eq((c["enemy"] as GoalEnemyData).id, kept[c["slot"]],
				"the untouched card kept the enemy it was showing")

func test_the_amulet_game_cannot_be_bashed() -> void:
	var amulet: StringName = GameState.amulet_game_id
	var nbrs: Array = RunGraph.neighbors(amulet)
	if nbrs.is_empty():
		pass_test("the amulet has no neighbour to stand on")
		return
	GameState.set_current_game(nbrs[0])
	_ui._build_choices()
	var idx: int = -1
	for i in range(_ui._choices.size()):
		if bool(_ui._choices[i]["amulet"]):
			idx = i
	assert_gt(idx, -1, "standing next to the amulet puts it in the offering")
	GameState.bash = 1
	_ui.bash_choice(idx)
	assert_eq(GameState.bash, 1, "the charge is not spent")
	assert_false(GameLoop2.is_bashed(amulet), "the run's goal survives")

func test_bash_is_refused_when_it_would_leave_nowhere_to_go() -> void:
	# A node with exactly one connection: destroying that one card would strand
	# the run, so the bash is refused rather than the slot left empty.
	var leaf: StringName = &""
	for g in Data.all_games():
		if RunGraph.neighbors(g.id).size() == 1:
			leaf = g.id
			break
	if leaf == &"":
		pass_test("no single-connection node in this run's graph")
		return
	GameState.set_current_game(leaf)
	_ui._build_choices()
	assert_eq(_ui._choices.size(), 1, "a leaf node offers exactly one game")
	GameState.bash = 1
	_ui.bash_choice(0)
	assert_eq(GameState.bash, 1, "the charge is kept")
	assert_eq(_ui._choices.size(), 1, "and the last card stays on the table")

# --- saving and resuming a run --------------------------------------------

func test_a_saved_run_round_trips_through_a_live_overworld() -> void:
	GameState.bash = 1
	var idx: int = _first_bashable()
	var destroyed: StringName = _ui._choices[idx]["slot"]
	_ui.bash_choice(idx)
	_ui.pick(0)
	_ui.report(false)                       # a missed goal leaves an enemy following
	_ui.pick(0)                             # and a game is now in play
	GameState.bombs = 2
	var expect_game: StringName = GameState.current_game_id
	var expect_hp: int = GameState.hp
	var expect_shields: int = GameState.shields
	var expect_stack: int = GameLoop2.stack_size()
	var expect_chosen: StringName = (_ui._chosen["game"] as GameData).id
	var expect_choices: int = _ui._choices.size()
	assert_true(SaveSystem.save_named("round trip"), "the run wrote to disk")

	# Wipe the run to nothing, then load it back into the still-mounted overworld.
	GameState.reset_run()
	GameLoop2.reset()
	GameState.set_overworld_context(_ui)    # reset_run clears the registration
	assert_true(SaveSystem.load_named("round trip"), "the save read back")

	assert_eq(GameState.current_game_id, expect_game, "the player is where they were")
	assert_eq(GameState.hp, expect_hp, "Health came back")
	assert_eq(GameState.shields, expect_shields, "the tries at the game in play came back")
	assert_eq(GameState.bombs, 2, "the board verbs came back")
	assert_eq(GameLoop2.stack_size(), expect_stack, "the followers came back")
	assert_true(GameLoop2.is_bashed(destroyed), "the destroyed game is still destroyed")
	assert_true(GameLoop2.has_current(), "the game in play is still in play")
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "and the screen is back on the report step")
	assert_eq((_ui._chosen["game"] as GameData).id, expect_chosen, "reporting on the same game")
	assert_eq(_ui._choices.size(), expect_choices, "the offering came back with it")

func test_a_restored_follower_keeps_its_place_on_the_board() -> void:
	_ui.pick(0)
	_ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	var expect: Dictionary = {
		"enemy": (entry["enemy"] as GoalEnemyData).id,
		"col": int(entry["col"]), "row": int(entry["row"]),
		"health": int(entry["health"]), "instance": int(entry["instance"]),
	}
	assert_true(SaveSystem.save_named("board"))
	GameState.reset_run()
	GameLoop2.reset()
	GameState.set_overworld_context(_ui)
	assert_true(SaveSystem.load_named("board"))
	assert_eq(GameLoop2.stack_size(), 1, "the follower came back")
	var back: Dictionary = GameLoop2.stack[0]
	assert_eq((back["enemy"] as GoalEnemyData).id, expect["enemy"], "the same enemy")
	assert_eq(int(back["col"]), int(expect["col"]), "standing in the same column")
	assert_eq(int(back["row"]), int(expect["row"]), "and the same row")
	assert_eq(int(back["health"]), int(expect["health"]), "with the same goals left on it")
	assert_eq(int(back["instance"]), int(expect["instance"]), "under the same instance handle")

func test_a_load_with_no_overworld_mounted_parks_the_view_for_the_next_one() -> void:
	_ui.pick(0)
	assert_true(SaveSystem.save_named("parked"))
	GameState.clear_overworld_context(_ui)
	assert_true(SaveSystem.load_named("parked"))
	assert_true(SaveSystem.has_pending_resume(), "the view waits for an overworld to boot")
	var view: Dictionary = SaveSystem.take_pending_view_state()
	assert_false(SaveSystem.has_pending_resume(), "claiming it clears the handshake")
	assert_eq(int(view.get("phase", -1)), OVERWORLD.Phase.PLAYING,
		"and it carries the screen the run was on")
	GameState.set_overworld_context(_ui)

func test_carried_items_survive_a_save_load_without_compounding() -> void:
	var vajra: ItemData = Data.get_item2(&"vajra")          # +1 Bash on pickup
	var heart: ItemData = Data.get_item2(&"hollow_heart")   # +4 Max Health on pickup
	assert_not_null(vajra)
	assert_not_null(heart)
	GameState.add_item(vajra)
	GameState.add_item(heart)
	var expect_bash: int = GameState.bash
	var expect_max_hp: int = GameState.max_hp
	var expect_items: int = GameState.inventory.size()
	assert_true(SaveSystem.save_named("pack"))
	GameState.reset_run()
	GameLoop2.reset()
	GameState.set_overworld_context(_ui)
	assert_true(SaveSystem.load_named("pack"))
	assert_eq(GameState.inventory.size(), expect_items, "the pack came back")
	assert_eq(GameState.bash, expect_bash, "Bash is what it was — not doubled by the reload")
	assert_eq(GameState.max_hp, expect_max_hp, "and neither is Max Health")

func test_reporting_a_game_keeps_the_run_recoverable() -> void:
	_ui.pick(0)
	_ui.report(false)
	assert_true(SaveSystem.has_autosave(), "the run keeps a recovery point")
	var summaries: Array = SaveSystem.list_resumable()
	assert_gt(summaries.size(), 0, "and the Continue list can see it")
	assert_true(bool(summaries[0].get("autosave", false)), "the autosave leads the list")

func test_a_lost_run_clears_its_recovery_point() -> void:
	_ui.pick(0)
	assert_true(SaveSystem.has_autosave(), "there is something to clear")
	GameState.shields = 0
	GameState.hp = 1
	_ui.log_attempt()                       # a lost run with no shields costs the last Health
	assert_true(GameLoop2.run_over, "the run ended")
	assert_false(SaveSystem.has_autosave(), "Continue must not offer a finished run")

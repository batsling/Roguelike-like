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
	_ui._board.click_enemy(int(cur["instance"]), cur, GameLoop2.offgrid_col(), true)
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
	assert_eq(int(GameLoop2.stack[0]["col"]), GameLoop2.spawn_col())
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
	assert_true(listed.contains("Use sorrow or self-inflicted pain as a weapon"),
		"the level-up challenge is listed: %s" % listed)
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

# The report checklist is the one place the player ANSWERS something, and Godot's
# stock check glyphs are a hairline outline drawn for a light theme — against this
# palette they read as an empty gap. The theme draws its own.
func test_the_checklist_boxes_are_drawn_not_left_to_the_stock_theme() -> void:
	var theme: Theme = UITheme.shared()
	for name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		assert_true(theme.has_icon(name, "CheckBox"), "CheckBox/%s is themed" % name)
		var icon: Texture2D = theme.get_icon(name, "CheckBox")
		assert_eq(icon.get_width(), UITheme.CHECK_ICON,
			"%s is drawn at the chunky size, not the stock 16px" % name)
	# The two states have to differ in COLOUR, not only in contents — a tick alone
	# is what was already too faint to see.
	var on: Image = theme.get_icon("checked", "CheckBox").get_image()
	var off: Image = theme.get_icon("unchecked", "CheckBox").get_image()
	assert_ne(on.get_pixel(1, 1), off.get_pixel(1, 1), "the border changes with the state")
	assert_ne(on.get_pixel(12, 12), off.get_pixel(12, 12), "and so does the fill")

# A ticked row restyles itself, so a part-filled checklist is readable from the
# board beside it rather than box by box.
func test_ticking_a_checklist_row_restyles_the_whole_row() -> void:
	_ui.pick(0)
	if _ui._goal_check == null:
		return
	var row: Control = _ui._goal_check.get_parent().get_parent()
	var before: StyleBox = row.get_theme_stylebox("panel")
	_ui._goal_check.button_pressed = true
	assert_ne(row.get_theme_stylebox("panel"), before, "the row answers with the box")
	_ui._goal_check.button_pressed = false
	assert_eq(row.get_theme_stylebox("panel"), before, "and goes back when unticked")

# The offering moved out of the full-width band above the stage and into the LEFT
# column, above the checklist — so the cards being chosen between and the board
# they will be walked onto are on screen together, without a scroll.
func test_the_offering_sits_above_the_checklist_beside_the_board() -> void:
	assert_true(_ui._left_col.is_ancestor_of(_ui._select_box),
		"the offering is in the left column, not in a band of its own")
	var offering: Control = _ui._select_box.get_meta("wrap")
	assert_lt(offering.get_index(), _ui._report_panel.get_index(),
		"and above the checklist in it")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(_ui._select_box.global_position.x, _ui._board.global_position.x,
		"which puts it left of the board")
	# ALONGSIDE, not above: the two have to share rows on the page, or the board is
	# still a scroll away from the cards. Whichever is taller, they overlap.
	var cards_top: float = _ui._select_box.global_position.y
	var cards_bottom: float = cards_top + _ui._select_box.size.y
	var board_top: float = _ui._board.global_position.y
	var board_bottom: float = board_top + _ui._board.size.y
	assert_lt(maxf(cards_top, board_top), minf(cards_bottom, board_bottom),
		"the offering and the board occupy the same band of the page")

# Nothing on the page may be wider than the page. The board grows a column per
# difficulty tier, so this is checked on the WIDEST board the run can reach.
func test_the_stage_fits_the_viewport_at_every_board_size() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var page: float = get_viewport().get_visible_rect().size.x - 32.0  # scroll margins
	assert_gt(page, 0.0)
	for growth in range(0, RunDifficulty.grid_growth_for(RunDifficulty.MAX_TIER) + 1):
		GameState.games_played = growth * RunDifficulty.GAMES_PER_TIER
		GameLoop2.sync_grid_bounds()
		_ui._refresh()
		await get_tree().process_frame
		var row: Control = _ui._left_col.get_parent()
		assert_lte(row.get_combined_minimum_size().x, page,
			"the %d-column board still fits the page (needs %.0f of %.0f)" % [
				GameLoop2.grid_cols(), row.get_combined_minimum_size().x, page])

# …which it manages by shrinking the cells rather than by running off the edge.
func test_the_cells_shrink_as_the_board_widens() -> void:
	var small: int = BattlefieldView.fitted_cell(GameLoop2.BASE_GRID_COLS)
	var big: int = BattlefieldView.fitted_cell(GameLoop2.BASE_GRID_COLS + 3)
	assert_eq(small, BattlefieldView.CELL_MAX, "a small board draws at full size")
	assert_lt(big, small, "a wide one draws tighter")
	assert_gte(big, BattlefieldView.CELL_MIN, "but never below the readable floor")
	# The budget holds for every board the run can actually reach, and the cell
	# never grows back as columns are added.
	var widest: int = GameLoop2.BASE_GRID_COLS \
		+ RunDifficulty.grid_growth_for(RunDifficulty.MAX_TIER)
	var last: int = BattlefieldView.CELL_MAX + 1
	for cols in range(2, widest + 1):
		var cell: int = BattlefieldView.fitted_cell(cols)
		var w: int = cols * cell + (cols - 1) * BattlefieldView.CELL_SEP
		assert_lte(w, BattlefieldView.FIELD_WIDTH_BUDGET,
			"%d columns stay within the width budget" % cols)
		assert_lte(cell, last, "%d columns don't draw bigger than %d" % [cols, cols - 1])
		last = cell
	# Past that — a board widened further by items — the floor wins over the
	# budget on purpose: cells that small stop being readable, and the page has
	# the room, since the offering column shrinks to meet it.
	assert_eq(BattlefieldView.fitted_cell(widest + 6), BattlefieldView.CELL_MIN,
		"an item-widened board bottoms out at the readable floor rather than vanishing")

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

# Where the cover-art button sits among a card's children, so the tests below can
# say "above the art" without pinning an exact index.
func _cover_index(card: Node) -> int:
	for i in range(card.get_child_count()):
		var child: Node = card.get_child(i)
		if child is Button and (child as Button).custom_minimum_size == _ui.COVER_SIZE:
			return i
	return -1

func _label_index(card: Node, text: String) -> int:
	for i in range(card.get_child_count()):
		var child: Node = card.get_child(i)
		if child is Label and String((child as Label).text) == text:
			return i
	return -1

func test_repeat_card_shows_the_dash_bonus_above_it() -> void:
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_beaten(target.id)
	_ui._build_choices()
	_ui._render_choices()
	var card: Node = _ui._choices_row.get_child(0)
	var bonus: int = _label_index(card, "⚡ Gain +%d Dash" % _ui.REPEAT_BEAT_DASH)
	assert_gt(bonus, -1, "the card says what beating it again grants")
	assert_lt(bonus, _cover_index(card), "and it sits ABOVE the cover art")
	# A game not yet beaten keeps the row (so the covers stay in line) but says
	# nothing in it.
	GameState.beaten_games.clear()
	_ui._build_choices()
	_ui._render_choices()
	var plain: Node = _ui._choices_row.get_child(0)
	assert_gt(_label_index(plain, ""), -1,
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

# ---------------------------------------------------------------------------
# Routing: what a card says about where it puts you
#
# Every offered game is a routing decision, and the card states it up front —
# the Amulet itself, a step along a shortest path, or ground given away.
# ---------------------------------------------------------------------------

# A game one step nearer the Amulet than where the player stands.
func _a_step_forward() -> StringName:
	var dag: Dictionary = RunGraph.shortest_path_dag(
		GameState.current_game_id, GameState.amulet_game_id)
	var layers: Array = dag.get("layers", [])
	if layers.size() < 2 or (layers[1] as Array).is_empty():
		return &""
	return StringName(layers[1][0])

func test_a_step_along_the_shortest_path_reads_as_optimal() -> void:
	var forward: StringName = _a_step_forward()
	assert_ne(String(forward), "", "there is a route to the Amulet from the start")
	if forward == &"":
		return
	var note: Dictionary = _ui.route_note({"slot": forward, "amulet": false})
	assert_true(String(note["text"]).contains("OPTIMAL"),
		"the card calls it out: %s" % note["text"])
	assert_eq(_ui.steps_to_amulet(forward), _ui.steps_to_amulet(GameState.current_game_id) - 1,
		"and it really is a step closer")

func test_the_amulet_card_says_it_is_the_amulet() -> void:
	var note: Dictionary = _ui.route_note({
		"slot": GameState.amulet_game_id, "amulet": true})
	assert_true(String(note["text"]).contains("AMULET"),
		"the run-ending card names itself: %s" % note["text"])
	assert_eq(note["color"], UITheme.GOLD, "in the Amulet's own colour")

func test_a_card_that_walks_away_reads_as_a_detour() -> void:
	# A game FURTHER from the Amulet than where the player stands: landing there
	# costs ground, and the card has to say so before it's clicked. (Bash and
	# Transmute can put any game on a card, so this isn't restricted to
	# neighbours — the label is judged on distance, not adjacency.)
	var here: int = _ui.steps_to_amulet(GameState.current_game_id)
	assert_gt(here, 0, "the run starts some distance out")
	var away: StringName = &""
	for gid in _ui._amulet_dist.keys():
		if int(_ui._amulet_dist[gid]) > here:
			away = gid
			break
	assert_ne(String(away), "", "the graph has ground to lose")
	var note: Dictionary = _ui.route_note({"slot": away, "amulet": false})
	assert_true(String(note["text"]).contains("Detour"),
		"a step backwards is labelled one: %s" % note["text"])
	# And a game the same distance out is neither progress nor loss.
	var level: StringName = &""
	for gid in _ui._amulet_dist.keys():
		if int(_ui._amulet_dist[gid]) == here and gid != GameState.current_game_id:
			level = gid
			break
	if level != &"":
		assert_true(String(_ui.route_note({"slot": level, "amulet": false})["text"]).contains("Sideways"),
			"and standing still is labelled that")

func test_every_offered_card_states_its_route_above_the_art() -> void:
	_ui._render_choices()
	for i in range(_ui._choices.size()):
		var card: Node = _ui._choices_row.get_child(i)
		var note: Dictionary = _ui.route_note(_ui._choices[i])
		var idx: int = _label_index(card, String(note["text"]))
		assert_gt(idx, -1, "card %d states where it puts you" % i)
		assert_lt(idx, _cover_index(card), "and does it above the cover art")

# ---------------------------------------------------------------------------
# The per-card map: the optimal path a game WOULD open, before taking it
# ---------------------------------------------------------------------------

func _map_button(card: Node) -> Button:
	for child in card.get_children():
		if child is Button and String((child as Button).text).contains("Map"):
			return child
	return null

func test_every_offered_card_carries_a_map_button_above_its_art() -> void:
	_ui._render_choices()
	for i in range(_ui._choices.size()):
		var card: Node = _ui._choices_row.get_child(i)
		var btn: Button = _map_button(card)
		assert_not_null(btn, "card %d offers its map" % i)
		if btn != null:
			assert_lt(btn.get_index(), _cover_index(card), "the map button sits above the image")

func test_the_card_map_is_the_optimal_path_from_that_game() -> void:
	var slot: StringName = _ui._choices[0]["slot"]
	var modal = _ui.preview_map(slot)
	assert_not_null(modal, "the button opens a map")
	if modal == null:
		return
	var layers: Array = modal.map_data().get("layers", [])
	assert_gt(layers.size(), 0, "the preview has a route to draw")
	assert_true((layers[0] as Array).has(slot), "it starts at the game you're considering")
	assert_true((layers[layers.size() - 1] as Array).has(GameState.amulet_game_id),
		"and ends at the Amulet")
	assert_eq(modal.shortest_distance(), _ui.steps_to_amulet(slot),
		"its depth is that game's own distance to the Amulet")

func test_the_start_picker_maps_each_start_without_naming_the_amulet() -> void:
	_ui.start_run()                       # back to the choose-your-start panel
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT)
	_ui._render_start_choices()
	var card: Node = _ui._choices_row.get_child(0)
	assert_not_null(_map_button(card), "a start card offers its map too")
	var start_id: StringName = _ui._start_options[0]["game"].id
	var modal = _ui.preview_map(start_id)
	assert_not_null(modal)
	if modal == null:
		return
	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	assert_eq(modal.node_name(GameState.amulet_game_id), "The Amulet — ???",
		"the destination is drawn, never named — that's the run's one secret")
	assert_ne(modal.node_name(start_id), "The Amulet — ???")
	if amulet != null:
		assert_ne(modal.node_name(GameState.amulet_game_id), amulet.display_name)

# ---------------------------------------------------------------------------
# The board gets to finish
#
# The resolve animation is the only place the run's consequences are SHOWN, so
# the screen it plays on has to still be there when it plays.
# ---------------------------------------------------------------------------

func test_the_board_says_how_long_its_playback_runs() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	assert_eq(_ui._board.animate_resolve(before, {"attacks": []}), 0.0,
		"nothing to show, nothing to wait for")
	assert_gt(before.size(), 0, "the picked game put an enemy on the board")
	var inst: int = int(before.keys()[0])
	var secs: float = _ui._board.animate_resolve(before,
		{"attacks": [{"instance": inst, "damage": 3}]})
	assert_almost_eq(secs, _ui._board.FX_ATTACK_TIME, 0.001,
		"a strike is what the host waits on")

func test_the_offering_waits_for_the_board_before_coming_back() -> void:
	_ui.pick(0)
	_ui.report(false)
	# The RUN has already moved on — nothing in it waits on an animation.
	assert_eq(_ui._phase, OVERWORLD.Phase.SELECT, "the next decision is already built")
	assert_gt(_ui._choices.size(), 0)
	assert_false(_ui._select_box.visible,
		"but the screen stays on the board while it plays the resolve")
	# …and when the board lands it hands over to a CONTINUE button rather than to
	# the next offering: the resolve is the only place the run's consequences are
	# shown, and it shouldn't be snatched away the instant the last tween ends.
	await wait_seconds(1.2)
	assert_true(_ui._resolving, "the screen is still held on the board it just played")
	assert_true(_ui._continue_bar.visible, "waiting on Continue")
	assert_false(_ui._select_box.visible, "so the offering hasn't jumped back in")

	_ui.continue_resolve()                   # what pressing the button does
	assert_false(_ui._resolving, "pressing it releases the hold")
	assert_false(_ui._continue_bar.visible, "and takes the button with it")
	assert_true(_ui._select_box.visible, "and the offering comes back")

func test_continue_is_what_lands_the_end_of_run_screen() -> void:
	_ui.pick(0)
	_ui._resolving = true                    # as it is between a report and its playback
	GameLoop2._finish_run(false)
	_ui._offer_continue()                    # the board finishes its playback
	assert_true(_ui._continue_bar.visible, "the verdict waits behind a Continue too")
	assert_null(_end_screen(), "so it doesn't land on top of the animation")
	_ui.continue_resolve()
	assert_not_null(_end_screen(), "and lands when the player says go on")

# ---------------------------------------------------------------------------
# The end of a run
# ---------------------------------------------------------------------------

func _end_screen():
	for c in _ui.get_children():
		if c is CanvasLayer:
			for g in c.get_children():
				if g is RunOverScreen and not g.is_queued_for_deletion():
					return g
	return null

func test_a_lost_run_ends_on_a_verdict_screen() -> void:
	_ui.pick(0)
	GameState.shields = 0
	GameState.hp = 1
	_ui.log_attempt()                        # the last Health goes
	assert_true(GameLoop2.run_over, "the run ended")
	var screen = _end_screen()
	assert_not_null(screen, "a finished run ends on a screen, not just a banner line")
	if screen == null:
		return
	assert_eq(screen.verdict(), "lost")
	assert_true(screen.headline().contains("ENDS HERE"), "it says so: %s" % screen.headline())
	assert_eq(int(screen.stats()["played"]), GameState.games_played,
		"and reads the run back: games played")
	assert_gt(screen.route_ids().size(), 0, "with the road actually walked")

func test_a_won_run_ends_on_the_amulet_screen() -> void:
	GameLoop2._finish_run(true)
	var screen = _end_screen()
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(screen.verdict(), "won")
	assert_true(screen.headline().contains("AMULET"), "it names the prize: %s" % screen.headline())
	assert_eq(int(screen.stats()["steps_left"]), 0, "you were standing on it")

func test_the_verdict_waits_for_the_killing_blow_to_finish_playing() -> void:
	_ui.pick(0)
	_ui._resolving = true                    # as it is between a report and its playback
	GameLoop2._finish_run(false)
	assert_null(_end_screen(), "the verdict doesn't land on top of the animation")
	assert_true(_ui._run_over_pending, "it's owed, though")
	_ui._end_resolve()                       # the board finishes
	assert_not_null(_end_screen(), "and lands the moment the board is done")

func test_only_one_verdict_screen_per_run() -> void:
	GameLoop2._finish_run(false)
	var first = _end_screen()
	_ui._queue_run_over(false)
	assert_eq(_end_screen(), first, "a second end signal doesn't stack a second screen")

func test_a_new_run_clears_the_last_ones_verdict() -> void:
	GameLoop2._finish_run(false)
	assert_not_null(_end_screen())
	_ui.start_run()
	assert_null(_end_screen(), "a fresh run starts on a clean page")
	assert_false(_ui._resolving, "and with nothing held over from the last one")

# The advance has to be MEASURABLE the instant the board repaints, or it never
# animates: the resolve compares where everyone stood with where they now stand,
# and a rebuilt overflow lane that still holds last frame's token answers for an
# enemy that has already walked onto the grid.
func test_an_enemy_that_walks_onto_the_grid_reads_as_having_moved() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(GameLoop2.current["instance"])
	assert_true(before.has(inst), "the game in play waits off the field")
	_ui.report(false)                      # missed -> it walks onto the board
	var after: Dictionary = _ui._board.capture_positions()
	assert_true(after.has(inst), "and now stands on the grid")
	var moved: float = (after[inst] as Rect2).position.distance_to((before[inst] as Rect2).position)
	assert_gt(moved, 2.0,
		"the advance is measurable straight away — a stale off-field token would say it never moved")

# ---------------------------------------------------------------------------
# Winning: clearing the Amulet game ends the run, in your favour
# ---------------------------------------------------------------------------

# Put the Amulet on the board next door and return the card offering it. The
# Amulet is always included in the offering when it's reachable, so this is the
# ordinary end of a run, reached early.
func _offer_the_amulet_next_door() -> int:
	var nb: StringName = RunGraph.neighbors(GameState.current_game_id)[0]
	GameState.amulet_game_id = nb
	_ui._build_choices()
	for i in range(_ui._choices.size()):
		if _ui._choices[i]["slot"] == nb:
			return i
	return -1

func test_beating_the_amulet_game_wins_the_run() -> void:
	var idx: int = _offer_the_amulet_next_door()
	assert_gt(idx, -1, "the Amulet is offered once it's reachable")
	assert_true(bool(_ui._choices[idx]["amulet"]), "and the card knows what it is")
	_ui.pick(idx)
	_ui.report(true)                          # the goal is met — that's the run
	assert_true(GameLoop2.run_over, "clearing the Amulet game ends the run")
	assert_true(GameLoop2.won, "as a win")
	_ui._end_resolve()                        # the board finishes its playback
	var screen = _end_screen()
	assert_not_null(screen, "and it lands on a win screen")
	if screen == null:
		return
	assert_eq(screen.verdict(), "won")
	assert_true(screen.headline().contains("YOU WIN"), "which says so: %s" % screen.headline())
	assert_eq(int(screen.stats()["steps_left"]), 0, "nothing left between you and it")
	assert_eq(StringName(screen.route_ids()[screen.route_ids().size() - 1]),
		GameState.amulet_game_id, "the road ends on the Amulet game")

func test_the_win_is_banked_on_the_amulet_game() -> void:
	var idx: int = _offer_the_amulet_next_door()
	var amulet: StringName = GameState.amulet_game_id
	var wins_before: int = GameStats.amulet_wins(amulet)
	_ui.pick(idx)
	_ui.report(true)
	assert_eq(GameStats.amulet_wins(amulet), wins_before + 1,
		"the game you won on carries the crown afterwards")

func test_missing_the_goal_on_the_amulet_game_is_not_a_win() -> void:
	var idx: int = _offer_the_amulet_next_door()
	_ui.pick(idx)
	_ui.report(false)                         # played it, didn't clear it
	assert_false(GameLoop2.run_over, "the run goes on")
	assert_null(_end_screen(), "and nothing declares a winner")

# ---------------------------------------------------------------------------
# The map: the star chart, with the ladder floating over it
# ---------------------------------------------------------------------------

func _chart() -> AtlasView:
	for c in _ui.get_children():
		if c is AtlasView and not c.is_queued_for_deletion():
			return c
	return null

func test_the_map_is_the_star_chart_with_the_ladder_over_it() -> void:
	var modal = _ui.open_map()
	assert_not_null(modal, "the Map button opens something")
	var atlas: AtlasView = _chart()
	assert_not_null(atlas, "and what it opens is the star chart")
	if atlas == null or modal == null:
		return
	assert_true(atlas.is_ancestor_of(modal),
		"with the ladder mounted over it, so closing the chart takes it along")
	assert_eq(modal.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the ladder is a window, not a modal — the sky under it stays live")
	assert_eq(atlas.preview_origin, &"", "the run's own map routes from where you stand")

func test_the_ladder_window_can_be_moved_but_not_lost() -> void:
	var modal = _ui.open_map()
	var before: Vector2 = modal.panel_position()
	modal._move_panel(before + Vector2(140, 70))
	assert_ne(modal.panel_position(), before, "it drags")
	modal._move_panel(Vector2(-9000, -9000))
	assert_gte(modal.panel_position().y, 0.0, "and can't be dragged off the top…")
	assert_gt(modal.panel_position().x + modal._panel.size.x, 0.0, "…or off the side")

func test_clicking_a_game_on_the_ladder_finds_it_on_the_chart() -> void:
	var modal = _ui.open_map()
	var atlas: AtlasView = _chart()
	if atlas == null or not atlas.has_layout():
		return
	assert_true(modal.show_on_chart(GameState.amulet_game_id), "the chart takes the click")
	assert_eq(atlas.layout.id_at(atlas.selected_index()), GameState.amulet_game_id,
		"and lands on that game")

func test_a_card_map_draws_that_cards_route_on_the_chart() -> void:
	var slot: StringName = _ui._choices[0]["slot"]
	var modal = _ui.preview_map(slot)
	var atlas: AtlasView = _chart()
	assert_not_null(atlas, "a card's map opens the chart too")
	if atlas == null or not atlas.has_layout():
		return
	assert_eq(atlas.preview_origin, slot, "routed from the game on the card")
	assert_eq(atlas.preview_index(), atlas.layout.index_of(slot))
	assert_true(atlas.marker_text(atlas.preview_index()).contains("IF YOU GO HERE"),
		"and the chart says which star that is")
	# The corridor drawn on the sky IS the ladder in the window: same DAG, edge
	# for edge, from the candidate rather than from where the player stands.
	var dag: Dictionary = RunGraph.shortest_path_dag(slot, GameState.amulet_game_id)
	var expected: int = 0
	for edge in dag.get("edges", []):
		if atlas.layout.index_of(StringName(edge["from"])) >= 0 \
				and atlas.layout.index_of(StringName(edge["to"])) >= 0:
			expected += 1
	assert_eq(atlas.trail_segment_count(), expected,
		"the chart's route and the ladder are the same graph")
	assert_eq(modal.shortest_distance(), _ui.steps_to_amulet(slot))

func test_the_start_pickers_map_raises_no_chart() -> void:
	# Before the run has a position the Amulet's identity is the one secret the
	# picker keeps; a sky with the route drawn on it would point straight at it.
	_ui.start_run()
	var modal = _ui.preview_map(_ui._start_options[0]["game"].id)
	assert_null(_chart(), "no star chart from the start picker")
	assert_eq(modal.node_name(GameState.amulet_game_id), "The Amulet — ???",
		"and the ladder still won't name the destination")

# ---------------------------------------------------------------------------
# Amulet pressure on the offering: what a card costs in PACE (§7.4)
# ---------------------------------------------------------------------------
#
# The route badge says how much ground a card gives or takes. These say what that
# ground costs, because a player who can't see the pace change before clicking
# can't make the trade the mechanic exists to offer.

# A game at exactly `hops` from the Amulet, or &"" if the graph has none.
func _a_game_at_hops(hops: int) -> StringName:
	for gid in _ui._amulet_dist.keys():
		if int(_ui._amulet_dist[gid]) == hops:
			return gid
	return &""

func test_a_card_names_the_pace_it_would_put_you_on() -> void:
	for hops in [6, 4, 1]:
		var gid: StringName = _a_game_at_hops(hops)
		if gid == &"":
			continue
		var note: Dictionary = _ui.turn_note({"slot": gid, "amulet": false})
		assert_eq(int(note["turns"]), RunDifficulty.turns_for_hops(hops),
			"a card %d hops out reads the same rung the loop resolves on" % hops)
		assert_true(String(note["text"]).contains("×%d" % int(note["turns"])),
			"and says the number out loud: %s" % note["text"])

func test_stepping_toward_the_amulet_warns_that_they_speed_up() -> void:
	# Stand in the far band and look at a card deep in the near one: the card has
	# to say the enemies get faster BEFORE it's clicked.
	var here: StringName = _a_game_at_hops(6)
	var there: StringName = _a_game_at_hops(1)
	if here == &"" or there == &"":
		return
	GameState.set_current_game(here)
	var note: Dictionary = _ui.turn_note({"slot": there, "amulet": false})
	assert_eq(int(note["turns"]), 3, "one hop from the Amulet is the doorstep")
	assert_true(String(note["text"]).contains("speed up"),
		"the card warns before the click: %s" % note["text"])
	assert_eq(note["color"], RunDifficulty.turns_band_color(3),
		"in the band's own colour, same as the board's strip")

func test_backing_off_reads_as_the_relief_it_is() -> void:
	var here: StringName = _a_game_at_hops(1)
	var there: StringName = _a_game_at_hops(6)
	if here == &"" or there == &"":
		return
	GameState.set_current_game(here)
	var note: Dictionary = _ui.turn_note({"slot": there, "amulet": false})
	assert_eq(int(note["turns"]), 1)
	assert_true(String(note["text"]).contains("slow down"),
		"walking away buys pace, and the card says so: %s" % note["text"])

func test_a_card_that_changes_nothing_says_so_quietly() -> void:
	var here: StringName = _a_game_at_hops(6)
	var there: StringName = _a_game_at_hops(5)
	if here == &"" or there == &"":
		return
	GameState.set_current_game(here)
	var note: Dictionary = _ui.turn_note({"slot": there, "amulet": false})
	assert_true(String(note["text"]).contains("Still"),
		"same band either way: %s" % note["text"])
	assert_eq(note["color"], UITheme.TEXT_DIM, "and it doesn't shout about it")

func test_the_amulet_card_makes_no_threat_about_afterwards() -> void:
	# Taking the Amulet ends the run on the spot; a "×3 turns" warning there would
	# be describing a game that never happens.
	var note: Dictionary = _ui.turn_note({
		"slot": GameState.amulet_game_id, "amulet": true})
	assert_eq(String(note["text"]), "", "the winning card carries no pace warning")

func test_every_offered_card_states_its_pace_above_the_art() -> void:
	_ui._render_choices()
	for i in range(_ui._choices.size()):
		var card: Node = _ui._choices_row.get_child(i)
		var note: Dictionary = _ui.turn_note(_ui._choices[i])
		if String(note["text"]) == "":
			continue                       # the Amulet's card, which says nothing
		var idx: int = _label_index(card, String(note["text"]))
		assert_gt(idx, -1, "card %d states the pace it puts you on" % i)
		assert_lt(idx, _cover_index(card), "and does it above the cover art")

# ---------------------------------------------------------------------------
# The difficulty step widens the battlefield (§7.3)
# ---------------------------------------------------------------------------

func test_crossing_a_tier_grows_the_board_and_says_so() -> void:
	# Park the run one game short of a tier step, then play that game: the board
	# is a column and a row wider on the other side of the report, and the run log
	# carries the news (the new cells light up on the board itself).
	GameState.games_played = RunDifficulty.GAMES_PER_TIER - 1
	_ui._build_choices()
	var cols_before: int = GameLoop2.grid_cols()
	var rows_before: int = GameLoop2.grid_rows()
	var log_before: int = GameLog.messages.size()
	_ui.pick(0)
	_ui.report(false)
	assert_eq(GameLoop2.grid_cols(), cols_before + 1, "the step widened the board")
	assert_eq(GameLoop2.grid_rows(), rows_before + 1, "in both dimensions")
	var said: bool = false
	for i in range(log_before, GameLog.messages.size()):
		if String(GameLog.messages[i].get("text", "")).contains("battlefield grows"):
			said = true
	assert_true(said, "and the run log says the battlefield grew")

func test_an_ordinary_game_leaves_the_board_alone() -> void:
	GameState.games_played = 0
	_ui._build_choices()
	var cols_before: int = GameLoop2.grid_cols()
	_ui.pick(0)
	_ui.report(false)
	assert_eq(GameLoop2.grid_cols(), cols_before,
		"a game that crosses no gate changes nothing about the board")

func test_the_playback_runs_one_beat_per_turn() -> void:
	# Three turns of enemy action have to be SHOWN as three, not collapsed into a
	# single slide — watching the same beat land three times is how the amulet
	# ladder is felt rather than merely read (§7.4).
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	assert_gt(before.size(), 0, "the picked game put an enemy on the board")
	var inst: int = int(before.keys()[0])
	var one: float = _ui._board.animate_resolve(before, {
		"turns": 1, "turn_frames": [{inst: Vector2i(1, 0)}],
		"attacks": [{"instance": inst, "turn": 0, "damage": 3}]})
	var three: float = _ui._board.animate_resolve(before, {
		"turns": 3,
		"turn_frames": [{inst: Vector2i(1, 0)}, {inst: Vector2i(1, 0)}, {inst: Vector2i(1, 0)}],
		"attacks": [
			{"instance": inst, "turn": 0, "damage": 3},
			{"instance": inst, "turn": 1, "damage": 3},
			{"instance": inst, "turn": 2, "damage": 3}]})
	assert_almost_eq(three, one * 3.0, 0.001,
		"the host holds the screen for every turn, not just the first")

func test_a_resolve_from_before_the_ladder_still_plays() -> void:
	# A result with no turn/turn_frames fields — a save restored from before the
	# ladder existed, or a test building one by hand — is one turn's worth of
	# playback rather than nothing at all.
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	assert_almost_eq(_ui._board.animate_resolve(before,
			{"attacks": [{"instance": inst, "damage": 1}]}),
		_ui._board.FX_ATTACK_TIME, 0.001, "an untagged attack belongs to turn one")

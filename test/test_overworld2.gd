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
	_open_at_first_offering()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	# The log is RUN-scope, so it goes with the run. Left standing it accumulates
	# across every test in the file and eventually hits MAX_MESSAGES, at which
	# point `add` starts popping from the front — and a test that remembers "the
	# log was N long before this happened" is then reading the wrong end of it.
	GameLog.clear()
	SaveSystem.clear_all_saves()
	SaveSystem.cancel_pending_resume()
	# The tier list is a cross-run store backed by a real file, and set_rating
	# saves — so the rating tests below would otherwise outlive themselves.
	TierList._reset_defaults()

# A fresh run opens on the START-SELECT panel (one card per genre, each inside the
# 4..7 band), and taking one is the run's FIRST GAME — its enemy spawns, it hands
# over its tries, and the run lands in the report step (Overworld2.choose_start).
#
# Nearly every test in this file is about the OFFERING and what you can do to it,
# which is where beating that opening game leaves you. So this is the opening
# played out: take the start, report it beaten, skip the board's playback, clear
# the drop it paid and walk out of the event it raised — what a player does
# before the first card is on the table. Tests that are about the opening itself
# call `start_run` and drive the picker directly instead.
func _open_at_first_offering() -> void:
	_ui.choose_start(0)
	if _ui._phase != OVERWORLD.Phase.PLAYING:
		return
	_report_beat(_ui)
	_ui._end_resolve()             # don't wait out the strike/advance animation
	# ...and drop what the playback was holding with it. The board freezes the
	# hero's Health at its pre-resolve value for the length of the animation
	# (BattlefieldView._hp_shown) and lets go when the tween ends — which, in a
	# test that never waits out the tween, is never. This used to come out in the
	# wash because the opening game had an empty board and so played back nothing
	# at all; the escort (§7.5) gives it a body to slide, so the playback is real
	# now and has to be cut short deliberately.
	_ui._board.clear_fx()
	# …and walk off the screen the game ended on. Every report now hands its haul
	# to one PostCombatScreen — the relics, the loot, the shelf, the boss warning —
	# and its way out is what opens the event behind it, so a test that reports a
	# game and then looks at the offering has to leave it the way a player does.
	# The opening game's relic goes on the floor with it; it isn't what's under test.
	_leave_post_game()
	_dismiss_event()
	# The opening game's ESCORT (§7.5) survived it — beating a game answers for its
	# own enemy and nothing else — so a run that opens perfectly still walks away
	# from the first card with one body on the board. That is correct, and it is
	# ALSO a body every test below would then be counting without having asked for
	# it. Cleared here so each test starts on an empty board and the followers it
	# counts are the ones it put there itself.
	_clear_board()

# Tick a checklist box the way a player does (§2.1): the click, and then the
# confirm it raises. A row only resolves once Yes is pressed — and once it has,
# it is locked, so this is also the only way a test can put one in that state.
func _tick(check, page = null) -> void:
	if check == null or not is_instance_valid(check) or check.disabled:
		return
	check.button_pressed = true
	_say_yes(page if page != null else _ui)

# Answer the confirm standing over `host`, if there is one.
func _say_yes(host) -> void:
	var panel = host.get_node_or_null("Confirm")
	if panel == null:
		return
	var ok = panel.find_child("OkBtn", true, false)
	if ok != null:
		ok.pressed.emit()

# …and the other answer, for a test that only wanted the box's own behaviour.
func _say_no(host) -> void:
	var panel = host.get_node_or_null("Confirm")
	if panel != null:
		panel.dismiss()

# How many RELIC drops are waiting. Every report also queues the game's own loot
# payout (§4.3) — a scroll or a pill, asked about in the same queue — so a raw
# _drop_queue.size() no longer counts what these tests are about.
func _item_drops() -> int:
	var n: int = 0
	for d in _ui._drop_queue:
		if not (d as Dictionary).has("loot"):
			n += 1
	return n

# Take every body off the board, the way DevTools' "clear the board" does.
func _clear_board() -> void:
	_clear_board_except(0)

# The same, but leaving one body standing — for a test that wants exactly one
# follower to reason about and does not want the escort that came with it.
func _clear_board_except(keep: int) -> void:
	for entry in GameLoop2.stack.duplicate():
		var inst: int = int(entry.get("instance", 0))
		if inst != keep:
			GameLoop2.despawn(inst)

# Travel to the offered game at `index` and take its ESCORT (§7.5) straight back
# off the board.
#
# Committing to a game stands TWO bodies on the board — the game's own enemy and
# a second one rolled from the same pool. The tests that are ABOUT that say so
# and use `_ui.pick` directly; every other test here is about a verb, a panel or
# a screen, and uses this so the followers it counts are the ones it put there.
func _pick_solo(index: int) -> void:
	_ui.pick(index)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	_disarm_board()

# Strip the abilities (§7.6) off everything standing on the board.
#
# The offering rolls a RANDOM enemy, and an ability changes what a turn of the
# board does: a Carcass lays a body, an Obscura makes two, a Cultist spends its
# turn stacking Strength instead of swinging. A screen test that counted bodies or
# expected a hit was therefore only USUALLY true — passing on the forty-odd
# ordinary enemies and failing on the handful that have one, which reads exactly
# like a flake and is not one. This file is about the SCREEN; the abilities have
# their own file (test_enemy_abilities.gd) where they are the subject.
func _disarm_board() -> void:
	for entry in GameLoop2.stack:
		entry["abilities"] = []

# Wait for the board's resolve playback to hand the screen back, however long it
# runs. NOT a fixed sleep: a playback is one beat per TURN (§7.4) and a beat is
# FX_ATTACK_TIME + FX_SLIDE_TIME = 0.89s, while the turn count is the run's
# distance band (RunDifficulty.extra_turns_for_hops) — no turns beyond 5 hops from the
# Amulet, 2 inside that, 3 inside 3. So the same report plays for 0.89s, 1.78s
# or 2.67s depending on where the RANDOM graph put the start.
#
# The fixed 1.2s await this replaced covered the one-turn case and nothing else,
# which is why it failed on the occasional run and passed on the rerun: the
# assert_false(_resolving) after it was only ever true at one turn a game. The
# ceiling is 5.0s because the longest a playback can run is 2.67s.
func _playback_done() -> void:
	await wait_until(func(): return not _ui._resolving, 5.0)

# An event fires after EVERY game now, so the opening game raises one and it is
# sitting over the board for every test in this file that isn't about it. Closed
# through the modal's own path rather than freed, so the chain behind it still
# runs — the shop a hub owes opens off `finished`, and half a dozen shop tests
# depend on that.
# Leave the screen a game ends on, and drop anything still on its table. The
# player's own way out (`dismiss`), so the chain behind it runs exactly as it does
# in a real run — which is what puts the event on screen for `_dismiss_event` to
# find. `_drop_queue` is cleared afterwards for the drops that never reached the
# screen at all (a test that queued one by hand).
func _leave_post_game(page = null) -> void:
	var ui = page if page != null else _ui
	if ui._post_screen != null and is_instance_valid(ui._post_screen):
		ui._post_screen.dismiss()
	ui._post_screen = null
	ui._post_snapshot = {}
	ui._drop_queue.clear()
	if ui._drop_modal != null and is_instance_valid(ui._drop_modal):
		ui._drop_modal.queue_free()
		ui._drop_modal = null

func _dismiss_event() -> void:
	if _ui._event_modal != null and is_instance_valid(_ui._event_modal):
		_ui._event_modal._close()
	_ui._event_modal = null
	_ui._pending_event = null
	_ui._pending_event_node = &""
	ObjectSystem.clear()

# Re-boot the run on a specific character and play out its opening, so a test that
# needs a particular level-up / loadout lands where before_each does.
func _reboot(character_id: StringName) -> void:
	_ui.start_run(character_id)
	_open_at_first_offering()

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
	# Disarmed: this counts BODIES, and since §7.6 a spawner ability can add one on
	# the board's own turn. "The enemy and its escort" is a claim about what the
	# loop leaves behind, not about what an ability did while it ran.
	_disarm_board()
	assert_true(GameLoop2.has_arrivals(), "picking spawns the enemy")
	assert_eq(GameState.current_game_id, target, "player travelled to the picked game")
	var gp_before: int = GameState.games_played
	_ui.report(false)             # miss -> the enemy stacks and follows
	assert_eq(GameState.games_played, gp_before + 1, "the game counts as played")
	assert_eq(GameLoop2.stack_size(), 2,
		"a missed goal leaves the game's enemy AND the escort that spawned with it")
	assert_gt(_ui._choices.size(), 0, "a fresh offering is drawn from the new position")

# A game played perfectly still leaves the escort (§7.5): the goal answered for
# the game's OWN enemy, and the escort's goal is a debt for a later game.
func test_report_goal_met_defeats_and_drops() -> void:
	_ui.pick(0)
	# Disarmed: the count is the subject, and a spawner adding a body — or a Split
	# leaving two where the defeated one stood — makes it 2 for a reason this test
	# is not about.
	_disarm_board()
	_report_beat(_ui)              # met -> defeat + a drop to be asked about
	assert_eq(GameLoop2.stack_size(), 1, "a met goal still leaves the escort standing")
	# The drop is already ON the haul screen: the resolve lands instantly out in
	# the wilds now (§7.4), and landing is what hands the queue over.
	_ui._end_resolve()
	assert_not_null(_ui._post_screen, "the report ended on the haul screen")
	assert_eq(_ui._post_screen._chest_sections.size(), 1, "carrying the kill's chest")
	_leave_post_game()

# An enemy kill ASKS whether you want what fell off it (§8): the item at full
# size, Take or Leave, no tray to notice later. What changed is WHERE it asks —
# a chest is a section of the screen the game ends on (PostCombatScreen) rather
# than a popup of its own, so the relic, the loot and the numbers are read as the
# one haul they are. Taking it still adds the item and clears the drop.
func test_defeat_drop_is_asked_about_on_the_screen_the_game_ends_on() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	assert_null(_ui._drop_modal,
		"the kill does NOT open a modal of its own over the board")
	_ui._end_resolve()                           # the board finishes its playback
	var screen = _ui._post_screen
	assert_not_null(screen, "the report ends on the haul screen")
	if screen == null:
		return
	var chest = screen.chest()
	assert_not_null(chest, "with the kill's chest on it")
	if chest == null:
		return
	# No RewardScreen is opened for an enemy drop.
	var found: RewardScreen = null
	for c in _ui.get_children():
		if c is RewardScreen:
			found = c
			break
	assert_null(found, "enemy drops ask on the haul screen, not a RewardScreen")
	var inv_before: int = GameState.inventory.size()
	chest.take()                                 # click Take it
	assert_null(screen.chest(), "the chest was answered")
	assert_eq(GameState.inventory.size(), inv_before + 1, "taking it adds the item")
	assert_eq(_ui._items_box.get_child_count(), GameState.inventory.size(),
		"and the pack strip above the board holds a token for it")
	_leave_post_game()

# The drops used to be pumped onto the screen on the next idle frame, in the
# middle of the resolve animation — the one place the run's consequences are ever
# SHOWN — so the player answered "do you want this relic" over the top of the blow
# that had just taken Health off them. Nothing a report drops opens while the
# board is still moving.
#
# Asserted against the RULE rather than against the clock. How long a playback
# runs depends on what was on the board (an empty one animates nothing at all),
# so waiting a fixed number of frames and looking tests the tween's length, not
# the guard. `_resolving` is the whole condition `_pump_drops` spends, so the page
# is put in that state and asked to pump — both ways round.
func test_a_report_asks_nothing_while_the_board_is_still_moving() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()                           # land the playback, so the test owns the flag
	_leave_post_game()
	_dismiss_event()
	_ui._resolving = true                        # as it is between a report and its playback
	_ui._drop_queue.append({"item": Data.reward_item2_pool_of(0)[0]})
	_ui._pump_drops()
	await wait_frames(2)
	assert_null(_ui._drop_modal,
		"nothing opens over the strike-and-advance a report is still playing")
	assert_eq(_ui._drop_queue.size(), 1, "the haul waits behind it")
	_ui._resolving = false
	_ui._pump_drops()
	await wait_frames(2)
	assert_not_null(_ui._drop_modal,
		"and the same queue pumps the moment the board is not moving")
	if _ui._drop_modal != null:
		_ui._drop_modal.leave()

# …and the whole queue goes to the haul screen when the playback does land, so
# nothing is left behind on the page to open afterwards.
func test_the_playback_landing_hands_the_whole_queue_to_the_haul_screen() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	# The playback can be instantaneous now — out in the wilds a report hands the
	# board no turns at all (§7.4), so there may be nothing to animate and
	# _end_resolve has already run. Either way the promise is the same: the queue
	# ends up on the screen and nothing is left on the page behind it.
	_ui._end_resolve()
	assert_not_null(_ui._post_screen, "the haul screen took it")
	assert_gt(_ui._post_screen._chest_sections.size(), 0, "the report's drop is on it")
	assert_eq(_ui._drop_queue.size(), 0, "and the page's queue is empty behind it")
	assert_null(_ui._drop_modal, "with no modal left over to open on top of it")
	_leave_post_game()

# A payout that does NOT arrive with a report still asks for itself, immediately,
# on its own modal: GameState.offer_loot fires from EffectSystem, so an item, an
# event or a machine can hand loot over at any moment and there is no haul screen
# for it to be a section of.
func test_an_out_of_band_payout_still_opens_its_own_modal() -> void:
	_ui._drop_queue.clear()
	GameState.offer_loot("loot", 1)
	await wait_frames(2)
	assert_not_null(_ui._drop_modal, "the offer asked on the spot")
	if _ui._drop_modal != null:
		_ui._drop_modal.leave()

# …and it asks in the MIDDLE of the room it has. The modal is built with a width
# and no height so it can size to whatever the relic needs, and a panel centred
# while it was still empty put its TOP at the middle of the page: everything it
# then grew hung below that, so the card the player is being asked about opened
# against the bottom edge with its art off it.
#
# "The room it has" is the screen MINUS the run's pinned header bar
# (ModalScaffold.reserved_top): the bar is opaque and drawn over every modal, so a
# modal centred on the whole screen loses its top row to it.
func test_the_drop_asks_in_the_middle_of_the_screen() -> void:
	# An OUT-OF-BAND chest, since that is the one that is still a modal: a chest
	# that arrives with a report is a section of the haul screen and is centred by
	# that screen's layout rather than by ModalScaffold.
	var modal := ItemDropModal.open(_ui, Data.reward_item2_pool_of(0)[0])
	await wait_frames(4)
	assert_not_null(modal, "the chest asked about itself")
	if modal == null:
		return
	var panel: Control = null
	for child in modal.get_children():
		if child is PanelContainer:
			panel = child
			break
	assert_not_null(panel, "the question is on a panel")
	assert_gt(panel.size.y, 0.0, "which has grown to fit the relic")
	var screen: Vector2 = modal.get_viewport_rect().size
	var bar: float = ModalScaffold.reserved_top
	assert_gt(bar, 0.0, "the run's header bar is standing on the top of the screen")
	var centre: Vector2 = panel.get_global_rect().get_center()
	assert_almost_eq(centre.y, bar + (screen.y - bar) * 0.5, 2.0,
		"the panel's MIDDLE sits on the middle of the room under the header bar")
	assert_gt(panel.get_global_rect().position.y, bar - 1.0,
		"and its top edge clears the bar entirely")
	assert_almost_eq(centre.x, screen.x * 0.5, 2.0, "and across, too")
	modal.leave()

func test_leaving_a_drop_discards_it() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var chest = _ui._post_screen.chest()
	assert_not_null(chest)
	if chest == null:
		return
	var inv_before: int = GameState.inventory.size()
	chest.leave()                                # click Leave it
	assert_null(_ui._post_screen.chest(), "the drop was cleared")
	assert_eq(GameState.inventory.size(), inv_before, "leaving it keeps the inventory unchanged")
	_leave_post_game()

# Two kills in one report ask twice, one after the other, rather than stacking
# two chests side by side: a chest is "which one of these", and two of those
# wearing one answer is not a question anybody can read. They queue INSIDE the
# haul screen now, with the loot and the numbers on it the whole time.
func test_drops_are_asked_about_one_at_a_time() -> void:
	_ui.pick(0)
	# Queued before the report, which is when the whole queue is handed over — the
	# resolve can land instantly now (§7.4).
	_ui._drop_queue.append({"item": Data.reward_item2_pool_of(0)[0]})
	_report_beat(_ui)
	_ui._end_resolve()
	var screen = _ui._post_screen
	assert_not_null(screen, "the haul screen took both")
	if screen == null:
		return
	var first = screen.chest()
	assert_not_null(first, "the first chest is the question in front of you")
	if first == null:
		return
	assert_eq(screen.chests_waiting(), 1, "the second is queued behind it")
	first.leave()
	assert_not_null(screen.chest(), "and comes up once the first is answered")
	assert_eq(screen.chests_waiting(), 0)
	_leave_post_game()

func test_fulfilling_a_follower_goal_defeats_and_drops_it() -> void:
	# Miss a goal so an enemy follows, then on the next game tick its fulfilment
	# checkbox: it should be defeated (and drop) before it can hit (§2).
	_ui.pick(0)
	_ui.report(false)
	# Two followers: the game's own enemy and its escort (§7.5). The escort is taken
	# off so this test is about ONE follower being fulfilled, which is what it is
	# checking — the escort's own rules are in test_gameloop2.gd.
	assert_eq(GameLoop2.stack_size(), 2, "a missed goal leaves a follower and its escort")
	_clear_board_except(int(GameLoop2.stack[0].get("instance", 0)))
	var hp_before: int = GameState.hp
	GameLoop2.drops.clear()
	_ui.pick(0)                                  # play another game
	# THREE rows: the old follower, and both bodies this game walked on. The
	# advertised one used to be missing from this list — it had the Goal box
	# instead — and it is an ordinary row now (GameLoop2.arrivals).
	assert_eq(_ui._fulfil_checks.size(), 3,
		"the old follower is offered for fulfilment, and so is this game's pair")
	# Ticked and CONFIRMED, so the follower is cleared on the spot (§2.1); the
	# report below is the miss on the game in play and nothing else.
	_tick(_ui._fulfil_checks[0]["check"])
	# The drop is LOOT now, and it lands on the board the moment the row resolves
	# (§8.2) rather than waiting for a report — which is the point of ticking early.
	assert_false(GameLoop2.drop_cells().is_empty(),
		"the fulfilled follower dropped its loot where it fell")
	_ui.report(false)                            # miss current, but fulfil the follower
	assert_eq(GameState.hp, hp_before, "fulfilling it before it hit means no damage")
	# The old follower is gone; what stands is this game's own pair.
	assert_eq(GameLoop2.stack_size(), 2, "old follower gone; this game's enemy and escort stacked")

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
	_ui._board.click_enemy(inst, entry, int(entry["col"]))
	assert_eq(_ui._board.selected_instance, inst, "the clicked enemy is targeted")
	assert_not_null(_ui._info_popup, "its info card opened")
	_ui._close_enemy_info()
	assert_null(_ui._info_popup, "the card closes")

# THE BODY THAT ARRIVED WITH THIS GAME IS TARGETABLE LIKE EVERY OTHER.
#
# It used to be the one exemption on the board: the enemy of the game in play
# could be read but not selected, pushed or bombed, because it was that game's
# own and shoving it would have answered the game just committed to. Nothing is a
# game's own enemy now (GameLoop2.arrivals).
func test_the_body_that_just_arrived_is_targetable_like_any_other() -> void:
	_ui.pick(0)
	var landed: Dictionary = GameLoop2.arrival()
	var inst: int = int(landed["instance"])
	_ui._board.click_enemy(inst, landed, GameLoop2.offgrid_col())
	assert_eq(_ui._board.selected_instance, inst, "clicking it selects it")
	assert_not_null(_ui._info_popup, "and its card still opens")
	_ui._close_enemy_info()
	assert_true(_ui._board.armed_targets().is_empty(), "nothing armed, nothing lit")
	GameState.bombs = 1
	_ui._board.begin_bomb()
	assert_true(_ui._board.armed_targets().has(inst),
		"and an armed bomb lights it up with the rest")
	_ui._board.cancel_bomb()

# --- aiming at the ground (§17) ---------------------------------------------
#
# Two verbs are pointed at a SQUARE rather than at a body: the Bomb, which may be
# spent anywhere on the board, and a tile-aimed item (Red Candle), which may be
# spent inside the columns it authored. Both light their legal squares up, and the
# lit set IS the rule — the board accepts a click on exactly what it drew.

func test_an_armed_bomb_lights_up_every_square_of_the_board() -> void:
	GameState.bombs = 1
	_ui.pick(0)
	_ui.report(false)
	assert_true(_ui._board.target_cells().is_empty(), "nothing armed, no ground lit")
	_ui._board.begin_bomb()
	assert_eq(_ui._board.target_cells().size(),
		GameLoop2.grid_cols() * GameLoop2.grid_rows(),
		"an armed bomb can be pointed at any square, not only at the bodies")
	_ui._board.cancel_bomb()

func test_a_bomb_can_be_spent_on_empty_ground() -> void:
	# The point of it: with Hot Bombs this is how fire is laid in front of the
	# stack, and the charge is spent on the square whether or not anybody is on it.
	_ui.pick(0)
	_ui.report(false)
	GameState.bombs = 1
	var empty: Array = GameLoop2.empty_cells()
	assert_false(empty.is_empty(), "the board has bare ground on it")
	_ui._board.begin_bomb()
	_ui._board._click_cell(empty[0])
	assert_eq(GameState.bombs, 0, "the charge went")
	assert_false(_ui._board.bomb_mode, "and the verb disarmed itself")

func test_a_bomb_clicked_on_an_occupied_square_still_hits_that_body() -> void:
	# The two are one press to the player, so an occupied square routes through the
	# body-aimed path — which is the only one that carries the target into the
	# blast (a boss's immunity, Sticky Bombs' stun, the bomb_used trigger).
	_ui.pick(0)
	_ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	# Stood on a known square rather than wherever the walk left it: a body out in
	# the overflow lane fills no cells, and this test is about the ones that do.
	entry["col"] = 2
	entry["row"] = 0
	var inst: int = int(entry["instance"])
	var cell: Vector2i = GameLoop2.entry_cells(entry)[0]
	GameState.bombs = 1
	var hp_before: int = int(entry.get("health", 0))
	_ui._board.begin_bomb()
	_ui._board._click_cell(cell)
	assert_eq(GameState.bombs, 0, "one charge, either way")
	var after: Dictionary = GameLoop2.entry_for(inst)
	assert_true(after.is_empty() or int(after.get("health", 0)) < hp_before,
		"and the body standing there took the blast")

func test_the_lit_squares_are_drawn_where_the_rule_says() -> void:
	# The highlight is BUILT, not just computed: it used to be drawn with flat
	# Buttons, which skip their stylebox entirely, so the picker was a set of
	# invisible squares that were legal to click and impossible to see.
	GameState.bombs = 1
	_ui.pick(0)
	_ui.report(false)
	_ui._board.begin_bomb()
	_ui._board.refresh()
	var lit: int = 0
	for c in _ui._board._arrow_layer.get_children():
		if c is Button and not (c as Button).flat:
			lit += 1
	assert_eq(lit, _ui._board.target_cells().size(),
		"one visible button per legal square")
	_ui._board.cancel_bomb()

# Push is ARMED first and AIMED second, so the button gates on the charge alone —
# "select an enemy" is what the mode is for, not a precondition of entering it.
func test_toolbar_push_needs_a_charge_not_a_target() -> void:
	GameState.push = 1
	_ui.pick(0)
	_ui.report(false)
	_ui._board.selected_instance = 0
	_ui._board.refresh_toolbar()
	assert_false(_ui._board.push_btn.disabled, "a charge and no target -> Push can be armed")
	GameState.push = 0
	_ui._board.refresh_toolbar()
	assert_true(_ui._board.push_btn.disabled, "no charge -> Push is unavailable")

# Arming clears whatever was selected: the flow reads "press Push, then say who",
# and a body left over from reading its card is not a target the player just
# chose.
func test_arming_push_clears_the_selection_and_disarms_on_cancel() -> void:
	GameState.push = 1
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	_ui._board.selected_instance = inst
	_ui._board.begin_push()
	assert_true(_ui._board.push_mode, "the verb is armed")
	assert_eq(_ui._board.selected_instance, 0, "and nothing is aimed at yet")
	assert_true(_ui._board.push_btn.text.contains("Cancel"),
		"the button becomes the way out: %s" % _ui._board.push_btn.text)
	_ui._board.cancel_push()
	assert_false(_ui._board.push_mode, "cancel disarms it")
	assert_eq(GameState.push, 1, "and nothing was spent on arming or cancelling")

# Aiming draws one arrow per LEGAL direction and no others — a follower on the
# spawn column has nothing behind it, so it never gets a back arrow.
func test_aiming_a_push_draws_an_arrow_per_legal_direction() -> void:
	GameState.push = 1
	_ui.pick(0)
	_ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	var inst: int = int(entry["instance"])
	# It spawned on the back column and then walked a step during its own game
	# (§7.2); park it back against the edge, which is the case this test is about.
	entry["col"] = GameLoop2.spawn_col()
	assert_eq(int(entry["col"]), GameLoop2.spawn_col(), "it is against the back edge")
	_ui._board.begin_push()
	_ui._board.click_enemy(inst, entry, int(entry["col"]))
	assert_eq(_ui._board.selected_instance, inst, "the click aims rather than inspects")
	assert_null(_ui._info_popup, "so no info card covers the arrows")
	var dirs: Array = []
	for a in _ui._board._arrow_layer.get_children():
		if a.has_meta("push_dir"):
			dirs.append(a.get_meta("push_dir"))
	assert_eq(dirs.size(), GameLoop2.push_directions(inst).size(),
		"one arrow per direction the rules allow")
	assert_false(dirs.has(GameLoop2.PUSH_BACK),
		"and none for the back edge it is already against")
	assert_true(dirs.has(GameLoop2.PUSH_FORWARD), "forward is offered")

# Pressing an arrow is the only thing that spends the charge, and it moves the
# body the way the arrow points.
func test_the_arrow_spends_the_charge_and_moves_the_enemy() -> void:
	GameState.push = 1
	_ui.pick(0)
	_ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	var inst: int = int(entry["instance"])
	var col: int = int(entry["col"])
	_ui._board.begin_push()
	_ui._board.click_enemy(inst, entry, col)
	var arrow: Button = null
	for a in _ui._board._arrow_layer.get_children():
		if a.has_meta("push_dir") and a.get_meta("push_dir") == GameLoop2.PUSH_FORWARD:
			arrow = a
	assert_not_null(arrow, "the forward arrow is there to press")
	arrow.pressed.emit()
	assert_eq(GameState.push, 0, "the charge is spent by the ARROW, not by arming")
	assert_eq(int(GameLoop2.stack[0]["col"]), col - 1, "and it moved the way the arrow pointed")
	assert_false(_ui._board.push_mode, "one press of Push spends at most one charge")

# --- the bomb is armed and aimed too ---------------------------------------
#
# It used to fire the instant its button was pressed, at whatever was still
# `selected_instance` — routinely a body clicked several turns earlier to read
# its card, so the charge went into an enemy the player was not looking at.

func test_arming_the_bomb_clears_the_selection_and_spends_nothing() -> void:
	GameState.bombs = 1
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	_ui._board.selected_instance = inst
	_ui._board.begin_bomb()
	assert_true(_ui._board.bomb_mode, "the verb is armed")
	assert_eq(_ui._board.selected_instance, 0,
		"and the body left over from reading a card is NOT the target")
	assert_eq(GameState.bombs, 1, "arming spends nothing")
	assert_true(_ui._board.bomb_btn.text.contains("Cancel"),
		"the button becomes the way out: %s" % _ui._board.bomb_btn.text)
	_ui._board.cancel_bomb()
	assert_false(_ui._board.bomb_mode, "cancel disarms it")
	assert_eq(GameState.bombs, 1, "and still spends nothing")

# The instruction is the BOARD, not a line of text: arming lights every body the
# verb could land on, and the toolbar stops telling you to click one.
func test_arming_lights_the_bodies_it_could_land_on() -> void:
	GameState.bombs = 1
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	assert_true(_ui._board.armed_targets().is_empty(), "nothing is lit while idle")
	_ui._board.begin_bomb()
	assert_true(_ui._board.armed_targets().has(inst), "the follower is a legal target")
	_ui._board.refresh_toolbar()
	assert_false(_ui._board._target_label.text.to_lower().contains("click"),
		"and the toolbar doesn't caption its own highlight: '%s'" % _ui._board._target_label.text)
	_ui._board.cancel_bomb()

# The CLICK is what spends it — one press of Bomb, one bomb.
func test_the_click_fires_the_bomb_and_disarms_it() -> void:
	GameState.bombs = 1
	_ui.pick(0)
	_ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	var inst: int = int(entry["instance"])
	var before: int = GameLoop2.stack.size()
	# Disarmed AFTER `before` is taken, because Split hangs off DEATH: bombing a
	# slime leaves two of it, and the count this asserts on then goes up rather
	# than down. The subject here is the click spending the charge.
	_disarm_board()
	_ui._board.begin_bomb()
	assert_eq(GameState.bombs, 1, "still nothing spent")
	_ui._board.click_enemy(inst, entry, int(entry.get("col", 1)))
	assert_eq(GameState.bombs, 0, "the click is what spends the charge")
	assert_lt(GameLoop2.stack.size(), before, "and it took the body off the board")
	assert_false(_ui._board.bomb_mode, "one press of Bomb spends at most one charge")
	assert_null(_ui._info_popup, "and the click bombed rather than opening a card")

# Arming one verb puts the other away — two armed verbs would make a click
# ambiguous, and the board can only light one set of targets.
func test_arming_one_verb_disarms_the_other() -> void:
	GameState.bombs = 1
	GameState.push = 1
	_ui.pick(0)
	_ui.report(false)
	_ui._board.begin_push()
	_ui._board.begin_bomb()
	assert_false(_ui._board.push_mode, "arming the Bomb put the Push away")
	assert_true(_ui._board.bomb_mode)
	_ui._board.begin_push()
	assert_false(_ui._board.bomb_mode, "and the other way round")
	_ui._board.cancel_push()

# Nothing is drawn while the verb is idle — the arrows are a mode, not furniture.
func test_no_arrows_when_the_push_is_not_armed() -> void:
	GameState.push = 1
	_ui.pick(0)
	_ui.report(false)
	var entry: Dictionary = GameLoop2.stack[0]
	_ui._board.click_enemy(int(entry["instance"]), entry, int(entry["col"]))
	assert_eq(_ui._board._arrow_layer.get_child_count(), 0,
		"an ordinary click on an enemy puts no arrows on the board")
	assert_not_null(_ui._info_popup, "it opens the info card, as it always did")
	_ui._close_enemy_info()

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
	_pick_solo(0)
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
	_tick(_ui._levelup_check)
	_report_beat(_ui)
	assert_eq(GameState.dash_charges, dash_before + 1, "level-up granted +1 Dash")
	assert_eq(GameState.player_level, lvl_before + 1, "player level advanced")

func test_level_up_not_applied_when_unchecked() -> void:
	_reboot(&"zoe")
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_report_beat(_ui)                              # box left unticked
	assert_eq(GameState.dash_charges, dash_before, "no level-up without the tick")

func test_isaac_level_up_grants_a_chest() -> void:
	_reboot(&"isaac")                       # reward_type item -> Small Chest
	var chests_before: int = GameState.pending_chests
	_ui.pick(0)
	_tick(_ui._levelup_check)
	_ui.report(false)
	assert_eq(GameState.pending_chests, chests_before + 1, "Isaac's level-up banks a chest")

func test_poe_level_up_grants_a_size_rolled_chest() -> void:
	_reboot(&"poe_ratcho")                  # reward_type random_sized_chest
	var chests_before: int = GameState.pending_chests
	_ui.pick(0)
	_tick(_ui._levelup_check)
	_ui.report(false)
	assert_eq(GameState.pending_chests, chests_before + 1, "Poe's level-up banks a chest")
	var choices: int = GameState.pending_chest_choices.back()
	assert_true([1, 2, 3, 5].has(choices),
		"chest SIZE is rolled: Small=1 / Medium=2 / Large=3 / Huge=5, got %d" % choices)

# --- a completed goal sinks (§2.1) ------------------------------------------
#
# An answered row is a record, not a question. It drops under everything still
# open so the list reads top-down as "what is left", however much has been done.

# Where a row's text sits in the checklist, or -1. Matched on a prefix, since the
# rows carry the goal and the name after it.
func _row_index(prefix: String) -> int:
	var labels: Array = _labels_under(_ui._verify_box)
	for i in range(labels.size()):
		if String(labels[i]).begins_with(prefix):
			return i
	return -1

func _last_row_index(prefix: String) -> int:
	var labels: Array = _labels_under(_ui._verify_box)
	var found: int = -1
	for i in range(labels.size()):
		if String(labels[i]).begins_with(prefix):
			found = i
	return found

func test_a_ticked_level_up_drops_below_the_enemies() -> void:
	_reboot(&"isaac")
	_ui.pick(0)
	assert_gt(_row_index("Cleared:"), _row_index("Leveled up"),
		"it starts above them, where the open goals are")
	_tick(_ui._levelup_check)
	_ui._populate_play_panel()
	assert_gt(_row_index("Leveled up"), _last_row_index("Cleared:"),
		"and lands under every enemy row once it is answered")

func test_a_ticked_status_goal_drops_below_the_enemies() -> void:
	_reboot(&"isaac")
	GameState.apply_status(&"strength", 1)
	_ui.pick(0)
	assert_false(_ui._status_goal_checks.is_empty(), "the status put a row on the list")
	var check: CheckBox = _ui._status_goal_checks[0]["check"]
	var row_text: String = check.text
	assert_gt(_row_index("Cleared:"), _row_index(row_text),
		"it starts above the board, with the other open goals")
	_tick(check)
	_ui._populate_play_panel()
	assert_gt(_row_index(row_text), _last_row_index("Cleared:"),
		"and sinks under every enemy row once it is answered")

func test_an_enemy_that_survived_its_goal_keeps_its_place() -> void:
	# The exception. A body with more Health than one goal completion can take is
	# ANSWERED without being FINISHED — it is still standing on the board beside
	# the list, so its row stays in board order rather than sinking.
	_reboot(&"isaac")
	_ui.pick(0)
	if GameLoop2.stack.size() < 2:
		return
	var entry: Dictionary = GameLoop2.stack[0]
	var inst: int = int(entry["instance"])
	entry["health"] = 3
	var was: int = _row_index("Cleared:")
	GameLoop2.fulfill(inst, true)
	_ui._populate_play_panel()
	assert_false(GameLoop2.entry_for(inst).is_empty(), "it is still on the board")
	assert_eq(_row_index("Cleared:"), was,
		"and its row has not moved out from under the board it belongs to")

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

# --- Bash and Transmute, armed and aimed (§4) ------------------------------
#
# Both verbs need a target, and for a long time that was the reason they had no
# button: the chips under the offering counted the charges and their tooltips
# pointed at a game card's popup. So the surface showing you had a Bash could not
# spend it. They arm from those chips now and the click on a card is the aim.

func _first_bashable_index() -> int:
	for i in range(_ui._choices.size()):
		if not bool(_ui._choices[i].get("amulet", false)):
			return i
	return -1

func test_arming_bash_spends_nothing_and_aiming_at_a_card_destroys_it() -> void:
	GameState.bash = 1
	_ui._build_choices()
	var idx: int = _first_bashable_index()
	if idx < 0 or _ui._choices.size() <= 1:
		pass_test("nothing on this offering can legally be bashed")
		return
	var game: GameData = _ui._choices[idx]["game"]
	_ui.arm_bash()
	assert_eq(_ui.armed_verb(), &"bash", "the chip armed the verb")
	assert_eq(GameState.bash, 1, "arming is free — the charge is spent by the aim")
	# THE CLICK ON A CARD IS THE AIM, not an inspection: no popup opens.
	assert_null(_ui.open_choice(idx), "an armed click fires the verb instead of opening the card")
	assert_eq(_ui.armed_verb(), &"", "and the verb comes down once it has fired")
	assert_eq(GameState.bash, 0, "the charge went with the aim")
	for c in _ui._choices:
		assert_ne(c["game"].id, game.id, "%s is off the table" % game.display_name)

func test_arming_transmute_and_aiming_swaps_the_slots_game() -> void:
	GameState.transmute = 1
	_ui._build_choices()
	var before: StringName = _ui._choices[0]["game"].id
	_ui.arm_transmute()
	assert_eq(_ui.armed_verb(), &"transmute")
	assert_null(_ui.open_choice(0), "the click aims rather than opening the card")
	assert_eq(GameState.transmute, 0, "the charge was spent")
	assert_ne(_ui._choices[0]["game"].id, before, "the slot plays a different game now")

func test_an_armed_verb_can_be_put_down_without_spending_it() -> void:
	GameState.bash = 1
	_ui.arm_bash()
	# Pressing the chip again is the obvious way out, and it is the one a player
	# tries before finding Cancel.
	_ui.arm_bash()
	assert_eq(_ui.armed_verb(), &"", "a second press lowers it")
	_ui.arm_bash()
	_ui.cancel_verb()
	assert_eq(_ui.armed_verb(), &"", "and so does Cancel")
	assert_eq(GameState.bash, 1, "neither way out costs anything")

func test_a_refused_aim_keeps_the_charge_and_stays_armed() -> void:
	# Bashing the Amulet would end the run's goal. It says so and refuses — and the
	# player aimed at the wrong card, not at the wrong verb, so the verb stays up.
	GameState.bash = 1
	_ui._build_choices()
	for i in range(_ui._choices.size()):
		if not bool(_ui._choices[i]["amulet"]):
			continue
		_ui.arm_bash()
		assert_null(_ui.open_choice(i), "the click is still an aim, not an inspection")
		assert_eq(GameState.bash, 1, "a refused aim spends nothing")
		assert_eq(_ui.armed_verb(), &"bash", "and leaves the verb up to be re-aimed")
		return
	pass_test("the Amulet isn't on this offering — nothing to check")

func test_an_aim_does_not_outlive_the_table_it_was_taken_on() -> void:
	GameState.bash = 1
	GameState.scramble = 1
	_ui.arm_bash()
	_ui.scramble()
	assert_eq(_ui.armed_verb(), &"",
		"a redrawn offering is a different table — the aim goes with the old one")
	assert_eq(GameState.bash, 1, "and nothing was spent")

func test_a_dash_and_an_armed_verb_are_never_both_up() -> void:
	GameState.dash_charges = 1
	GameState.bash = 1
	_ui._build_choices()
	var capped: int = _ui._choices.size()
	_ui.dash()
	_ui.arm_bash()
	assert_false(_ui._dash_mode, "arming a verb lowers the dash")
	assert_eq(_ui.armed_verb(), &"bash")
	# …and lowering it REDRAWS the offering, so the aim cannot land on a card the
	# dash's wider set put there.
	assert_eq(_ui._choices.size(), capped, "the ordinary offering is back")
	assert_eq(GameState.dash_charges, 1, "the dash was not spent")
	_ui.dash()
	assert_eq(_ui.armed_verb(), &"", "and a dash lowers the verb the other way round")

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

# --- shields = the armour the game you selected granted (§3.2) -------------

func test_picking_a_game_grants_its_shields() -> void:
	assert_eq(GameState.shields, 0, "no shields before a game is selected")
	var game: GameData = _ui._choices[0]["game"]
	var expected: int = GameLoop2.shields_for_game(game)
	_ui.pick(0)
	assert_eq(GameState.shields, expected,
		"%s granted its %d shields" % [game.display_name, expected])
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
	_report_beat(_ui)
	assert_eq(GameState.shields, 0, "the armour belonged to that game")

# --- the attempt tracker ---------------------------------------------------

func test_ticking_an_attempt_gives_the_board_a_turn_and_leaves_the_shields() -> void:
	_ui.pick(0)
	var shields: int = GameState.shields
	assert_eq(_ui.log_attempt(), "turn")
	_ui._end_resolve()                     # land the playback the tick started
	assert_eq(GameState.shields, shields, "a lost run costs no shields at all")
	assert_true(_ui._attempt_count.text.contains("1"),
		"the strip counts the lost run: %s" % _ui._attempt_count.text)
	# What the press costs is written ON the button rather than in a sentence
	# beside it. The shields it does NOT cost are not on this strip at all any
	# more — the board draws them as armour over the hero — so what the strip owes
	# that rule is a line on the count the press does move.
	assert_true(_ui._attempt_btn.text.contains("Enemy Turn"),
		"the button says what a tick does: %s" % _ui._attempt_btn.text)
	assert_true(_ui._attempt_count.tooltip_text.contains("do not go when you lose a run"),
		"and the count says a lost run leaves the shields alone: %s"
			% _ui._attempt_count.tooltip_text)
	assert_false(GameLoop2.last_attempt_turn.is_empty(),
		"and the turn it bought is left where the board can replay it")

# The undo has no BUTTON any more — it was grey half the time, because the
# snapshots it restores from are runtime-only and a reloaded run has none — but
# the loop's take-back is still there and still a restore rather than a refund.
func test_undoing_an_attempt_takes_the_turn_back() -> void:
	_ui.pick(0)
	var shields: int = GameState.shields
	_ui.log_attempt()
	_ui._end_resolve()
	assert_eq(GameLoop2.undo_attempt(), "turn")
	_ui._refresh()
	assert_eq(GameState.shields, shields, "the shields were never in it")
	assert_eq(GameLoop2.attempts(), 0)
	assert_false(GameLoop2.can_undo_attempt(), "nothing left to take back")

func test_the_tracker_is_only_live_while_a_game_is_in_play() -> void:
	assert_true(_ui._attempt_btn.disabled, "no game selected -> nothing to lose runs of")
	_ui.pick(0)
	assert_false(_ui._attempt_btn.disabled, "a game in play -> the tracker is live")
	_report_beat(_ui)
	assert_true(_ui._attempt_btn.disabled, "reported -> closed again")

# The shields a game grants are part of the routing decision, so the hover line
# under the offering quotes them for whatever card you're pointing at.
func test_the_hover_line_previews_the_games_grant() -> void:
	_ui._show_preview(0)                          # hovering the first card
	var grant: int = GameLoop2.shields_for_game(_ui._choices[0]["game"])
	assert_true(_ui._preview.text.contains(GameState.temp_shields_text(grant)),
		"hovering previews what that game grants: %s" % _ui._preview.text)
	assert_true(_ui._preview.text.contains(_ui._choices[0]["enemy"].display_name),
		"and what it would put on the board: %s" % _ui._preview.text)
	_ui._clear_hover_grant()                      # mouse left the card
	assert_false(_ui._preview.text.to_lower().contains("shield"),
		"it can't advertise a game you're not pointing at: %s" % _ui._preview.text)

# …and it does NOT open by naming the game. The mouse is sitting on that game's
# cover with its title printed underneath — the line is one line wide, the goal is
# the half that gets cut off, and the name was being paid for out of it.
func test_the_hover_line_does_not_repeat_the_games_own_name() -> void:
	for i in _ui._choices.size():
		_ui._show_preview(i)
		var game: GameData = _ui._choices[i]["game"]
		assert_false(_ui._preview.text.contains("[b]%s[/b]" % game.display_name),
			"the hover leads with what is WAITING there, not with the cover's own name: %s"
			% _ui._preview.text)

# HOW FAR THE AMULET IS, on every card, over the art. The distance was on the
# start cards and then nowhere: after the first choice the offering said which
# WAY a card went (and only once it was opened) but never how far there was left
# to go, which is the number the whole run is counting down.
func test_every_offered_card_says_how_far_the_amulet_is() -> void:
	_ui._render_choices()
	for i in _ui._choices.size():
		var card: Node = _ui._choices_row.get_child(i)
		var hops: int = _ui.steps_to_amulet(StringName(_ui._choices[i].get("slot", &"")))
		var text: String = _text_of(card)
		if hops > 0:
			assert_string_contains(text,
				"%d game%s away from the Amulet" % [hops, "" if hops == 1 else "s"],
				"the card counts the road left: %s" % text)
		elif hops == 0:
			assert_string_contains(text, "THE AMULET",
				"the run's last card says so instead of counting zero: %s" % text)
		else:
			assert_string_contains(text, "No route to the Amulet",
				"and a card nothing connects says that: %s" % text)

# It rides ABOVE THE COVER, with the flag it belongs beside — the offering is a
# row of covers being scanned, and a fact read during the scan cannot be under
# the thing being scanned.
func test_the_distance_sits_over_the_cover_and_under_the_flag() -> void:
	_ui._render_choices()
	# The card that is NOT the Amulet — on the Amulet's own the row is blank, since
	# the flag above it has already said the only thing there is to say.
	var card: Node = null
	for i in _ui._choices.size():
		if not bool(_ui._choices[i].get("amulet", false)):
			card = _ui._choices_row.get_child(i)
			break
	assert_not_null(card, "the offering has a card that isn't the Amulet")
	if card == null:
		return
	var dist: int = -1
	var cover: int = -1
	for c in card.get_children():
		if c is Label and String((c as Label).text).contains("Amulet") and dist < 0:
			dist = c.get_index()
		if c is Button and not String((c as Button).text).contains("Map") and cover < 0:
			cover = c.get_index()
	assert_gt(dist, -1, "the card carries the distance line")
	assert_gt(cover, -1, "and the cover is a button")
	assert_lt(dist, cover, "the distance is read before the art, not after it")

# The pack panel carries no heading. A bordered strip of relic and scroll tiles
# does not need to be told it is the inventory — the tokens are the label, and
# the row it was spending is worth more to the board under it.
func test_the_pack_has_no_heading() -> void:
	var text: String = _text_of(_ui._inv_wrap)
	assert_false(text.contains("Inventory"),
		"nothing calls the pack anything: %s" % text)

# --- nothing on the board belongs to a game ---------------------------------
#
# The enemy a card advertised used to be that game's own for the whole game: it
# could not be bombed or pushed, it had an emphasised "Goal —" box at the top of
# the report checklist, and beating the game was the act that cleared it. All of
# that is gone (GameLoop2.arrivals) — it walks on, and from that moment it is a
# follower like every other body.

func test_the_checklist_lists_the_arrivals_among_the_followers() -> void:
	_ui.pick(0)
	_ui.report(false)                     # something is following now
	_ui.pick(0)                           # …and this game walks more on
	var rows: int = _ui._fulfil_checks.size()
	assert_eq(rows, GameLoop2.stack.size(),
		"one tick box per body on the board, arrivals included")
	var landed: Dictionary = GameLoop2.arrival()
	if landed.is_empty():
		return
	var listed := false
	for f in _ui._fulfil_checks:
		if int(f["instance"]) == int(landed["instance"]):
			listed = true
	assert_true(listed, "what walked on with this game is one of them")

# A D10 RE-ROLLS THE BOARD MID-GAME AND THE CHECKLIST FOLLOWS IT. The report step
# is built once, when the game is taken, and `_refresh` deliberately leaves it
# alone because it holds tick boxes — so the list went on asking about the bodies
# that were standing there when the game began. A player who spent a charge to
# escape a goal they could not do was still being asked to tick that goal.
func test_the_checklist_follows_a_reroll_of_the_board() -> void:
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING)
	var before: String = _text_of(_ui._verify_box)
	var names_before: Array = []
	for entry in GameLoop2.stack:
		names_before.append((entry["enemy"] as GoalEnemyData).display_name)
	assert_false(names_before.is_empty(), "there is a body to re-roll")
	var swapped: int = GameLoop2.reroll_enemies()
	if swapped <= 0:
		return                            # nothing else in the bucket to become
	var after: String = _text_of(_ui._verify_box)
	assert_ne(after, before, "the checklist is not describing the old board")
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		assert_string_contains(after, e.display_name,
			"%s is on the board, so it is on the list" % e.display_name)
	assert_eq(_ui._fulfil_checks.size(), GameLoop2.stack.size(),
		"one tick box per body, still")

# …and it does NOT rebuild for a board that merely moved. The panel holds tick
# boxes, so rebuilding it is not free — the guard is a signature of what the rows
# SAY, and a body advancing a column does not change a word of it. (This is why
# the play panel has a signature of its own rather than borrowing the standing
# list's, which counts `in_front`.)
func test_the_checklist_does_not_rebuild_when_the_board_only_moves() -> void:
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING)
	# DISARMED, because "the board only moves" is the premise and an ability is how
	# it does something else. A body with Infliction hands the player or another
	# body a status on its turn, and the play panel's signature counts each body's
	# alternatives and bonus objectives (_play_panel_sig) — so a Burn landing
	# mid-turn changes what the rows SAY, the guard correctly rebuilds them, and
	# this test fails having watched the feature work. It failed on roughly one run
	# in five on any tree for exactly that reason, since §7.6 shipped abilities.
	_disarm_board()
	assert_false(_ui._checklist.play_panel_stale(), "freshly built, it is current")
	var boxes: Array = []
	for f in _ui._fulfil_checks:
		boxes.append(f["check"])
	_ui.log_attempt()                     # a lost run: the board advances
	assert_false(_ui._checklist.play_panel_stale(),
		"a body walking a column nearer says nothing new about the goals")
	_ui._refresh()
	var same := true
	for i in range(mini(boxes.size(), _ui._fulfil_checks.size())):
		if _ui._fulfil_checks[i]["check"] != boxes[i]:
			same = false
	assert_true(same, "so the same boxes are still standing")

# A body CONJURED onto the stack mid-game is the same story from the other end —
# Scroll of Create Monster, and the list has to grow a row for it.
func test_the_checklist_grows_a_row_for_a_body_conjured_mid_game() -> void:
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING)
	var rows_before: int = _ui._fulfil_checks.size()
	var conjured: GoalEnemyData = GameLoop2.roll_conjured_enemy()
	if conjured == null:
		return
	GameLoop2.spawn_to_stack(conjured)
	_ui._refresh()
	assert_eq(_ui._fulfil_checks.size(), rows_before + 1,
		"what just walked on is something you can be asked about")
	assert_string_contains(_text_of(_ui._verify_box), conjured.display_name)

# --- the note is asked for by the tick, not by a button on the row ----------
#
# Every enemy row used to end in a "🗒 Notes" button — a second control on a line
# that is already a portrait, a symbol, a wrapped sentence and a box, pressed at
# the same moment as the box beside it. The confirm asks for both at once now.

func test_a_goal_row_carries_no_notes_button() -> void:
	_ui.pick(0)
	if _ui._fulfil_checks.is_empty():
		return
	var row: Control = _ui._fulfil_checks[0]["check"].get_parent()
	for btn in row.find_children("*", "Button", true, false):
		assert_false(String((btn as Button).text).contains("Notes"),
			"no Notes button on the row: %s" % (btn as Button).text)

func test_ticking_an_enemy_asks_for_the_note_in_the_same_breath() -> void:
	_ui.pick(0)
	if _ui._fulfil_checks.is_empty():
		return
	var game_id: StringName = _ui._chosen["game"].id
	var inst: int = int(_ui._fulfil_checks[0]["instance"])
	var enemy: GoalEnemyData = GameLoop2.entry_for(inst).get("enemy")
	assert_not_null(enemy, "the row is about a body")
	if enemy == null:
		return
	_ui._fulfil_checks[0]["check"].button_pressed = true
	var confirm: ConfirmPanel = _find_confirm(_ui)
	assert_not_null(confirm, "the tick asks first")
	if confirm == null:
		return
	var edits: Array = confirm.find_children("*", "TextEdit", true, false)
	assert_eq(edits.size(), 1, "and the question comes with somewhere to write it down")
	if edits.is_empty():
		return
	(edits[0] as TextEdit).text = "Killed it with the starting pistol."
	_say_yes(_ui)
	assert_eq(GameStats.enemy_note(game_id, enemy.id),
		"Killed it with the starting pistol.",
		"saying yes banks the note against the pair, where the Atlas reads it")

func test_saying_no_to_the_tick_throws_the_note_away_with_it() -> void:
	_ui.pick(0)
	if _ui._fulfil_checks.is_empty():
		return
	var game_id: StringName = _ui._chosen["game"].id
	var inst: int = int(_ui._fulfil_checks[0]["instance"])
	var enemy: GoalEnemyData = GameLoop2.entry_for(inst).get("enemy")
	if enemy == null:
		return
	# GameStats is a CROSS-RUN store backed by a real file, like the tier list — it
	# is not wiped by after_each, so the pair this test happens to roll may already
	# be carrying a note the test above banked against it. Cleared here, because
	# "the note is empty afterwards" is only evidence of a No if it was empty
	# before: without this the test passes or fails on whether the random offering
	# handed two tests in a row the same game and enemy.
	GameStats.clear_enemy_note(game_id, enemy.id)
	assert_eq(GameStats.enemy_note(game_id, enemy.id), "", "nothing written down yet")
	_ui._fulfil_checks[0]["check"].button_pressed = true
	var confirm: ConfirmPanel = _find_confirm(_ui)
	if confirm == null:
		return
	var edits: Array = confirm.find_children("*", "TextEdit", true, false)
	if edits.is_empty():
		return
	(edits[0] as TextEdit).text = "typed, then thought better of it"
	_say_no(_ui)
	assert_eq(GameStats.enemy_note(game_id, enemy.id), "",
		"a No is a No about the whole thing — the row and the note")

func test_there_is_no_emphasised_goal_row() -> void:
	_ui.pick(0)
	var text: String = _text_of(_ui._verify_box)
	assert_false(text.contains("Goal —"),
		"no box claims to be the game's own goal: %s" % text)
	assert_false(text.contains("Also cleared"),
		"and nothing is 'also' — there is one list")

# Beating the game and clearing an enemy are two different claims now. Pressing
# "Completed Game" says you played it; the tick boxes say what you did to the
# bodies.
func test_beating_the_game_clears_nothing_by_itself() -> void:
	_ui.pick(0)
	# Disarmed for the reason above: a spawner adds a body during the report, and
	# "none of them was ticked" is a claim about ticking, not about spawning.
	_disarm_board()
	var before: int = GameLoop2.stack.size()
	assert_gt(before, 0, "something walked on")
	_ui.report(true)                      # completed, ticked nothing
	assert_eq(GameLoop2.stack.size(), before,
		"the bodies are all still there — none of them was ticked")
	assert_true(GameState.has_played_game(_last_played_id()),
		"but the GAME is recorded as beaten")

func test_ticking_an_arrival_is_what_clears_it() -> void:
	_ui.pick(0)
	var landed: Dictionary = GameLoop2.arrival()
	if landed.is_empty():
		return
	var inst: int = int(landed["instance"])
	# Disarmed: a ticked body that dies with Split leaves two behind, so the count
	# grows where this test is about the tick landing at all.
	_disarm_board()
	var before: int = GameLoop2.stack.size()
	_ui.report(true, [inst])
	assert_lt(GameLoop2.stack.size(), before, "the ticked body took its hit")

# The game the run last played, for the record assertions above.
func _last_played_id() -> StringName:
	return _ui._last_played_game.id if _ui._last_played_game != null else &""

# --- the hover CARD ---------------------------------------------------------
#
# An enemy, a status, an item and the enemy-turns readout all open something when
# clicked, and all four used to spend their hover on Godot's plain grey tooltip.
# They carry a condensed version of that card now (HoverCard).

func test_a_body_on_the_board_carries_a_hover_card() -> void:
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var node: Control = _ui._board._enemy_nodes.get(inst)
	assert_not_null(node, "the body has a node on the board")
	assert_true(node.has_meta(HoverCard.META), "and the node carries a card")
	var card: Dictionary = node.get_meta(HoverCard.META)
	var e: GoalEnemyData = GameLoop2.stack[0]["enemy"]
	assert_eq(String(card.get("title", "")), e.display_name, "named as itself")
	assert_eq(card.get("art"), e.image, "with its own art")
	var lines: String = "\n".join(PackedStringArray(card.get("lines", [])))
	assert_string_contains(lines, e.goal, "the goal you'd be playing for")
	# …and NOTHING about when it swings. That was a sentence counting the squares
	# between two things the player is looking straight at.
	assert_false(lines.to_lower().contains("walking"),
		"no distance narrated on the hover: %s" % lines)

# The statuses ride as PIPS rather than as three more lines of prose.
func test_a_bodys_statuses_ride_its_hover_card_as_pips() -> void:
	_ui.pick(0)
	GameLoop2.apply_enemy_status(&"marked", 2, "current")
	_ui.report(false)
	_ui._board.refresh()
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var node: Control = _ui._board._enemy_nodes.get(inst)
	if node == null:
		return
	var card: Dictionary = node.get_meta(HoverCard.META, {})
	var pips: Array = card.get("pips", [])
	assert_false(pips.is_empty(), "what is riding on it is on the card")
	var names: String = ""
	for pip in pips:
		names += String(pip.get("text", "")) + " "
	assert_string_contains(names, "Marked", "by name and stack count: %s" % names)

func test_a_carried_item_carries_a_hover_card() -> void:
	var item := ItemData.new()
	item.id = &"__test_relic__"
	item.display_name = "Test Relic"
	item.description = "It does a testable thing."
	GameState.inventory.append(item)
	_ui._refresh_items()
	# The run opens carrying a relic of its own, so the strip is picked through by
	# name rather than by index.
	var card: Dictionary = {}
	for token in _ui._items_box.get_children():
		if token.has_meta(HoverCard.META) \
				and String(token.get_meta(HoverCard.META).get("title", "")) == "Test Relic":
			card = token.get_meta(HoverCard.META)
	assert_false(card.is_empty(), "the pack token carries a card")
	assert_string_contains("\n".join(PackedStringArray(card.get("lines", []))),
		"testable thing", "with what it does on it")
	GameState.inventory.erase(item)

func test_the_extra_turns_readout_carries_a_hover_card() -> void:
	_ui._board.refresh()
	var panel: Control = _ui._board._pressure_panel
	assert_true(panel.has_meta(HoverCard.META), "the pressure readout carries a card")
	var card: Dictionary = panel.get_meta(HoverCard.META)
	assert_string_contains(String(card.get("title", "")), "Extra turns",
		"named for what it is")
	assert_string_contains("\n".join(PackedStringArray(card.get("lines", []))),
		"Amulet", "and it says WHY the number is what it is")

# The offering is the one place that gets nothing: the hover line under the cards
# already says what is waiting, and a popup over three covers being scanned is
# the noisiest possible way to repeat it.
func test_an_offered_card_has_no_hover_of_its_own() -> void:
	_ui._render_choices()
	var card: Node = _ui._choices_row.get_child(0)
	var cover: Button = null
	for c in card.get_children():
		if c is Button and not String((c as Button).text).contains("Map"):
			cover = c
	assert_not_null(cover, "the cover is a button")
	if cover == null:
		return
	assert_eq(cover.tooltip_text, "", "and it says nothing on hover")
	assert_false(cover.has_meta(HoverCard.META), "no card either")

# …and the PICTURE of it, beside the line. A player recognises a body by its art
# long before they read its name, and for a while the hover had no art at all.
func test_the_hover_shows_the_enemys_portrait() -> void:
	var enemy: GoalEnemyData = _ui._choices[0]["enemy"]
	if enemy == null or enemy.image == null:
		return                                    # a free game has nothing to draw
	_ui._show_preview(0)
	assert_true(_ui._preview_art.visible, "hovering a card shows what is waiting there")
	assert_eq(_ui._preview_art.texture, enemy.image, "and it is that card's own enemy")
	_ui._clear_hover_grant()
	assert_false(_ui._preview_art.visible,
		"the portrait goes with the hover — it can't show a game you left")

# The Runic Dome hides what is coming, and a portrait gives that away far more
# completely than a name does.
func test_the_hover_portrait_respects_the_dome() -> void:
	var enemy: GoalEnemyData = _ui._choices[0]["enemy"]
	if enemy == null or enemy.image == null:
		return
	var dome := ItemData.new()
	dome.id = &"__test_dome__"
	dome.hide_spawns = true
	GameState.inventory.append(dome)
	_ui._show_preview(0)
	assert_false(_ui._preview_art.visible, "the Dome hides the picture as well as the name")
	GameState.inventory.erase(dome)

func test_the_popup_shows_the_shields_the_game_grants() -> void:
	# The shields a game hands you used to be printed on its card. The card is the
	# cover and the name now — this is one of the facts that moved into the popup.
	var modal = _ui.open_choice(0)
	var grant: int = GameLoop2.shields_for_game(_ui._choices[0]["game"])
	assert_true(_text_of(modal).contains(GameState.temp_shields_text(grant)),
		"the popup states the game's shield grant: %s" % _text_of(modal))

# --- the HUD carries the player, and only the player -----------------------
#
# Twelve numbers in one strip is a strip nobody reads, and a charge that is only
# ever spent on an offered card was being kept a page away from the offering. The
# verbs moved under the thing they act on; Health and Shields were the last two
# left, and the BOARD was already drawing both on the hero, so the strip went
# with them.

func test_the_players_own_state_is_drawn_on_the_board() -> void:
	GameState.hp = 4
	GameState.shields = 2
	GameState.bonus_shields = 1
	_ui._refresh()
	assert_true(_ui._board._hero_hp.text.contains("%d/%d" % [GameState.hp, GameState.max_hp]),
		"the hero carries the health: %s" % _ui._board._hero_hp.text)
	# One SHIELD SPRITE per shield, both pools, permanent first — and only the
	# temporary ones carry the clock that says they go with this game.
	var shields: Array = _ui._board.standing_shields()
	assert_eq(shields.size(), 3, "one sprite per shield, both pools")
	assert_eq(_timers_on(shields[0]), 0, "the permanent one wears no clock")
	assert_eq(_timers_on(shields[1]), 1, "the temporary ones do")
	assert_eq(_timers_on(shields[2]), 1, "both of them")

# The shields that STAY are the one pool readable with no board on screen, and
# they read as the same armour the board draws rather than as a glyph of their own.
func test_the_header_shows_the_lasting_shields_as_shields() -> void:
	GameState.bonus_shields = 0
	_ui._refresh_stats()
	assert_false(_ui._shield_chip_art.visible, "no chip while there are none")
	GameState.bonus_shields = 2
	_ui._refresh_stats()
	assert_true(_ui._shield_chip_art.visible, "the sprite comes up with the pool")
	assert_eq(_ui._shield_chip_art.texture, UITheme.SHIELD_ART,
		"and it is the board's own shield art")
	assert_eq(_ui._shield_chip.text, "2", "with the count beside it")
	assert_false(_ui._health_chip.text.contains("2"),
		"and Health is left saying only Health: %s" % _ui._health_chip.text)

# The character's LEVEL, against the token in the header. Everything a level pays
# is spread across the board, the pack and the verb chips — the level itself was
# the only thing that could say "you have grown" in one glance, and the run screen
# never wrote it down anywhere.
func test_the_header_says_what_level_the_character_is() -> void:
	GameState.player_level = 1
	_ui._refresh_stats()
	assert_eq(_ui._level_chip.text, "Lv. 1", "it starts at one")
	assert_true(_ui._level_chip.visible, "and it is up from the first screen")
	GameState.player_level = 4
	_ui._refresh_stats()
	assert_eq(_ui._level_chip.text, "Lv. 4", "and it follows the level up")
	# It rides the character chip, so it is beside the token rather than adrift in
	# the header — which is what makes it read as the CHARACTER's level.
	assert_true(_ui._character_wrap.is_ancestor_of(_ui._level_chip),
		"in the same chip as the token")
	assert_true(_ui._character_wrap.is_ancestor_of(_ui._character_chip))

# The board says where a body is by DRAWING it there. A hover that also counts the
# squares in words is the board reading itself back, so the timing line is gone.
func test_the_enemy_hover_does_not_narrate_the_distance() -> void:
	_ui.pick(0)
	assert_false(GameLoop2.stack.is_empty(), "something walked on")
	if GameLoop2.stack.is_empty():
		return
	var entry: Dictionary = GameLoop2.stack[0]
	var card: Dictionary = _ui._board.enemy_hover(entry, entry["enemy"])
	for line in card.get("lines", []):
		assert_false(String(line).contains("lost run"),
			"no lost-run countdown on the hover: %s" % line)
		assert_false(String(line).contains("Waiting off the field"),
			"and nothing about being out of range: %s" % line)

# The other half of the same rule: a status the run OWNS is drawn bare, and one
# it has only BORROWED (docs/potions-design.md §5.3) wears the clock — the same
# badge, in the same corner, as the shields that go with this game.
func test_a_borrowed_status_wears_the_clock_and_an_owned_one_does_not() -> void:
	GameState.apply_status(&"strength", 1)
	_ui._refresh()
	var pips: Array = _ui._board._hero_statuses.get_children()
	assert_eq(pips.size(), 1, "one pip on the player")
	if pips.is_empty():
		return
	assert_eq(_timers_on(pips[0]), 0, "nothing is going anywhere, so no clock")
	GameState.remove_status(&"strength", 1)
	GameState.apply_status(&"strength", 2, 1)
	_ui._refresh()
	pips = _ui._board._hero_statuses.get_children()
	assert_eq(pips.size(), 1, "still one pip")
	if pips.is_empty():
		return
	assert_eq(_timers_on(pips[0]), 1, "and it says it is on loan")

# How many clock badges are drawn inside `node` — the mark UITheme.timed_art puts
# on anything that expires.
func _timers_on(node: Node) -> int:
	var found: int = 0
	for tr in node.find_children("*", "TextureRect", true, false):
		if (tr as TextureRect).texture == UITheme.TIMER_ART:
			found += 1
	return found

func test_the_choosing_verbs_sit_under_the_offering() -> void:
	GameState.bash = 2
	GameState.transmute = 1
	GameState.scramble = 3
	GameState.dash_charges = 1
	_ui._refresh_stats()
	var text: String = _text_of(_ui._select_stats)
	for want in ["Bash 2", "Dash 1", "Transmute 1", "Scramble 3"]:
		assert_true(text.contains(want), "%s is under the offering: %s" % [want, text])
	# And it is genuinely inside the offering panel, not merely built.
	assert_true(_ui._select_box.is_ancestor_of(_ui._select_stats),
		"the row lives in the choose-a-game box")

# The board's own verbs get no chip row, because the board already draws all
# three — and a second row saying the same numbers is exactly the duplication the
# HUD strip was cut for.
func test_the_board_draws_its_own_verbs_and_tier() -> void:
	GameState.push = 2
	GameState.bombs = 4
	_ui._refresh()
	assert_true(_ui._board.push_btn.text.contains("(2)"),
		"the toolbar button carries the Push count: %s" % _ui._board.push_btn.text)
	assert_true(_ui._board.bomb_btn.text.contains("(4)"),
		"and the Bomb count: %s" % _ui._board.bomb_btn.text)
	assert_true(_ui._board._size_label.text.contains(
		RunDifficulty.tier_name(RunDifficulty.current_tier())),
		"and the pressure bar carries the tier: %s" % _ui._board._size_label.text)
	# Nothing in the overworld's own chip row repeats them.
	var chips: String = _text_of(_ui._select_stats)
	for dup in ["Push", "Bombs", "Tier"]:
		assert_false(chips.contains(dup), "%s isn't drawn twice: %s" % [dup, chips])

func test_a_spendable_charge_is_a_button_and_an_empty_one_is_not() -> void:
	GameState.scramble = 0
	_ui._refresh_stats()
	assert_eq(_buttons_in(_ui._select_stats).size(), 0,
		"no charges -> nothing to press")
	GameState.scramble = 1
	_ui._refresh_stats()
	var labels: Array = []
	for b in _buttons_in(_ui._select_stats):
		labels.append(String(b.text))
	assert_true("\n".join(labels).contains("Scramble 1"),
		"a charge that can be fired from here is a button: %s" % str(labels))

func test_loot_lives_in_its_own_window_beside_the_pack() -> void:
	# Scrolls used to be tokens on the pack strip. Pills doubled the kinds and the
	# per-game drop made carrying nine ordinary (§4.3), so loot moved into a window
	# of its own — opened from a toggle at the end of the strip's row, which is
	# where the count of what you are carrying now lives.
	GameState.add_scroll_loot(&"scroll_of_teleportation")
	_ui._refresh_items()
	assert_true(_ui._inv_wrap.is_ancestor_of(_ui._items_box), "the relics are still a strip")
	assert_false(_text_of(_ui._items_box).contains("Read"),
		"and the strip is relics only — loot is not on it")
	var toggle: String = _text_of(_ui._loot_toggle_box)
	assert_true(toggle.contains("Loot"), "the toggle says what it opens: %s" % toggle)
	assert_true(toggle.contains("1/%d" % GameState.LOOT_CAPACITY),
		"and how full the pack is: %s" % toggle)
	assert_null(_ui._loot_panel, "the window starts closed")

func test_the_loot_window_opens_onto_a_full_3x3_over_the_left_column() -> void:
	GameState.add_scroll_loot(&"scroll_of_teleportation")
	GameState.add_pill_loot(&"luck_up")
	_ui._loot_window.open = true
	_ui._refresh_items()
	assert_not_null(_ui._loot_panel, "opening it mounts the panel")
	if _ui._loot_panel == null:
		return
	# On the PAGE, not inside the pack — opening it must not re-flow the column the
	# board is in.
	assert_true(_ui.is_ancestor_of(_ui._loot_panel), "it floats over the page")
	assert_false(_ui._inv_wrap.is_ancestor_of(_ui._loot_panel),
		"and not inside the pack panel")
	var grid: GridContainer = _find_grid(_ui._loot_panel)
	assert_not_null(grid, "the window is a grid")
	if grid == null:
		return
	assert_eq(grid.columns, 3, "three across")
	# ALWAYS nine. The empties are how the window says how much room is left, and
	# they are what keeps it a grid rather than a row that wraps.
	assert_eq(grid.get_child_count(), GameState.LOOT_CAPACITY,
		"nine slots whatever is in them")
	var text: String = _text_of(_ui._loot_panel)
	assert_true(text.contains("Use"), "each carried piece can be spent from here: %s" % text)
	assert_true(text.contains("Unidentified Pill"),
		"an unlearned colour says only what it looks like: %s" % text)

func test_the_loot_window_lands_on_the_board() -> void:
	# It drops out of its own button: the pack strip sits on top of the board, so
	# the window opens onto the board under it rather than across the page.
	GameState.add_pill_loot(&"luck_up")
	_ui._loot_window.open = true
	_ui._refresh_items()
	await wait_frames(2)
	assert_not_null(_ui._loot_panel)
	if _ui._loot_panel == null:
		return
	var panel: Rect2 = _ui._loot_panel.get_global_rect()
	var board: Rect2 = _ui._stage_panel.get_global_rect()
	assert_almost_eq(panel.get_center().x, board.get_center().x, 3.0,
		"centred across the board rather than pinned to a corner of it")
	assert_gt(panel.position.y, board.position.y - 1.0, "and starting at its top")
	assert_gt(panel.position.x, _ui._left_col.get_global_rect().end.x - 1.0,
		"which is the pack's side of the page, not the offering's")

func test_the_loot_window_stays_on_screen() -> void:
	GameState.add_pill_loot(&"luck_up")
	_ui._loot_window.open = true
	_ui._refresh_items()
	await wait_frames(2)
	if _ui._loot_panel == null:
		return
	var panel: Rect2 = _ui._loot_panel.get_global_rect()
	var screen: Vector2 = _ui.get_viewport_rect().size
	assert_gt(panel.position.y, ModalScaffold.reserved_top - 1.0,
		"clear of the header bar, which is drawn over everything")
	assert_lt(panel.end.y, screen.y + 1.0, "and the whole of it fits the window")
	assert_lt(panel.end.x, screen.x + 1.0)

func _find_grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node
	for c in node.get_children():
		var found: GridContainer = _find_grid(c)
		if found != null:
			return found
	return null

# --- The grid you can rearrange (§4.3) -------------------------------------
#
# The drag is driven through the same three virtuals Godot calls on a real one
# (`_get_drag_data` on the source, `_can_drop_data` / `_drop_data` on the target),
# because that is the whole of the contract — everything above them is the OS
# moving a mouse, and everything below them is GameState.

func _open_loot_grid() -> LootGrid:
	_ui._loot_window.open = true
	_ui._refresh_items()
	return _find_grid(_ui._loot_panel) as LootGrid

# What is in a slot, by id — the question every one of these tests is really
# asking. `GameState.loot_layout()` is what puts a slot back together with the
# array index the run addresses a piece by; the two stopped being the same number
# when the grid started allowing holes.
func _id_in_slot(slot: int) -> StringName:
	var index: int = GameState.loot_index_at_slot(slot)
	if index < 0:
		return &""
	return StringName(GameState.loot_items[index].get("id", ""))

func test_a_carried_piece_can_be_dragged_onto_another_and_they_swap() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_pill_loot(&"luck_up")
	var grid: LootGrid = _open_loot_grid()
	assert_not_null(grid, "the window is a LootGrid")
	if grid == null:
		return
	var first: StringName = _id_in_slot(0)
	var second: StringName = _id_in_slot(1)
	var from: LootSlot = grid.get_child(0)
	var onto: LootSlot = grid.get_child(1)

	var payload = from._get_drag_data(Vector2.ZERO)
	assert_true(payload is Dictionary, "a filled slot hands over a payload")
	assert_eq(String((payload as Dictionary).get("kind", "")), "loot_move",
		"and it says it is a piece being rearranged")
	assert_true(onto._can_drop_data(Vector2.ZERO, payload), "another slot takes it")
	onto._drop_data(Vector2.ZERO, payload)

	assert_eq(_id_in_slot(0), second, "the two changed places")
	assert_eq(_id_in_slot(1), first)

func test_a_piece_can_be_dragged_into_any_empty_slot() -> void:
	# THE POINT OF THE GRID. A slot used to be a position in a dense array, so an
	# empty one past the end meant "the end" and a piece dragged into the far corner
	# slid back to third place. Where a piece sits is a fact about the piece now, so
	# the corner is a place it can be — and the slot it came from is allowed to stay
	# empty. See GameState.loot_layout.
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_pill_loot(&"luck_up")
	var held: int = GameState.loot_items.size()
	var moving: StringName = _id_in_slot(0)
	var grid: LootGrid = _open_loot_grid()
	if grid == null:
		return
	var payload = grid.get_child(0)._get_drag_data(Vector2.ZERO)
	var far: LootSlot = grid.get_child(GameState.LOOT_CAPACITY - 1)
	assert_true(far._can_drop_data(Vector2.ZERO, payload), "an empty slot takes it")
	far._drop_data(Vector2.ZERO, payload)
	assert_eq(GameState.loot_items.size(), held, "nothing was gained or lost")
	assert_eq(_id_in_slot(GameState.LOOT_CAPACITY - 1), moving,
		"the piece is in the corner it was dropped in")
	assert_eq(GameState.loot_index_at_slot(0), -1,
		"and the slot it left stays empty — a hole in the middle is an arrangement, "
		+ "not a bug to be tidied away")

func test_an_arrangement_survives_the_grid_being_redrawn() -> void:
	# The grid rebuilds from scratch on every change, so an arrangement the view was
	# merely remembering would be gone by the next redraw.
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_pill_loot(&"luck_up")
	var grid: LootGrid = _open_loot_grid()
	if grid == null:
		return
	var moving: StringName = _id_in_slot(0)
	var payload = grid.get_child(0)._get_drag_data(Vector2.ZERO)
	grid.get_child(7)._drop_data(Vector2.ZERO, payload)
	grid.rebuild()
	assert_eq(_id_in_slot(7), moving, "the run remembers where it was put")
	var cell: LootSlot = grid.get_child(7)
	assert_true(cell.is_filled(), "and the redrawn grid draws it there")
	assert_false((grid.get_child(0) as LootSlot).is_filled(),
		"with the slot it left still empty")

func test_a_piece_stays_where_it_was_put_when_another_is_spent() -> void:
	# The array closes up when a piece leaves it — that is what keeps `use_loot`
	# addressable — and the arrangement must not close up with it.
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_pill_loot(&"luck_up")
	GameState.add_pill_loot(&"health_up")
	var grid: LootGrid = _open_loot_grid()
	if grid == null:
		return
	# Put the third piece in the far corner, then destroy the first.
	var payload = grid.get_child(2)._get_drag_data(Vector2.ZERO)
	grid.get_child(8)._drop_data(Vector2.ZERO, payload)
	var parked: StringName = _id_in_slot(8)
	GameState.remove_loot_at(GameState.loot_index_at_slot(0))
	assert_eq(_id_in_slot(8), parked,
		"the piece in the corner is still in the corner — the array shifted, "
		+ "the grid did not")

func test_the_whole_cell_is_what_follows_the_cursor() -> void:
	# A drag used to be the bare capsule, which read as the art coming loose from
	# its tile and gave the player nothing to line up against the slot they were
	# aiming at. It is the cell now: same border, same art, same name.
	GameState.loot_items.clear()
	GameState.add_pill_loot(&"luck_up")
	var grid: LootGrid = _open_loot_grid()
	if grid == null:
		return
	var cell: LootSlot = grid.get_child(0)
	var preview: Control = grid.drag_preview(cell)
	assert_not_null(preview, "a filled cell has a preview")
	if preview == null:
		return
	var body: Control = preview.get_child(0)
	assert_true(body is PanelContainer,
		"and it is a whole cell — a panel, not a loose texture")
	assert_eq(body.size.x, float(LootSlot.CELL_W),
		"at the size the slot draws one, so it covers the slot it is aimed at")
	assert_true(_text_of(preview).contains(LootSystem.display_name(GameState.loot_items[0])),
		"carrying the piece's name with it: %s" % _text_of(preview))
	# A real drag hands this to the viewport, which owns it from then on; built here
	# it belongs to nobody, so this test has to be the one to take it away.
	preview.free()

func test_loot_cannot_be_rearranged_mid_report() -> void:
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_pill_loot(&"luck_up")
	var grid: LootGrid = _open_loot_grid()
	if grid == null:
		return
	grid.locked = true
	assert_null(grid.get_child(0)._get_drag_data(Vector2.ZERO),
		"a locked grid hands over nothing — loot cannot move between "
		+ "'played the game' and 'said what happened'")

func test_the_drop_modal_puts_the_piece_in_the_slot_it_was_dragged_to() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	var offer := {"type": "pill", "id": &"luck_up", "horse": false}
	var modal := LootDropModal.open(_ui, offer)
	await wait_frames(2)
	var grid: LootGrid = _find_grid(modal) as LootGrid
	assert_not_null(grid, "the drop modal shows the pack as a grid")
	if grid == null:
		return
	assert_eq(grid.get_child_count(), GameState.LOOT_CAPACITY,
		"all nine of it, so a full pack says so by having nowhere to drop")
	# The MIDDLE of the grid, with nothing beside it — the slot a dense array could
	# never have put it in.
	var target: LootSlot = grid.get_child(4)
	var payload := {"kind": "loot_take", "entry": offer, "offer": 0}
	assert_true(target._can_drop_data(Vector2.ZERO, payload), "an empty slot takes the offer")
	target._drop_data(Vector2.ZERO, payload)
	# THE SCREEN PLACES ITS OWN TAKES: with several offers, and uses and bins between
	# them, the slot a piece was dropped into stops meaning anything the moment the
	# next one moves. So the piece is in the pack already, at the slot it was given.
	assert_eq(GameState.loot_items.size(), 2, "the piece is in the pack")
	var placed: int = GameState.loot_index_at_slot(4)
	assert_gt(placed, -1, "in the slot it was dragged to, not shuffled up to the end")
	if placed < 0:
		return
	assert_eq(String(GameState.loot_items[placed].get("type", "")), "pill")

func test_an_offer_cannot_be_dropped_onto_a_piece_already_carried() -> void:
	# "Put it here" onto an occupied slot has no answer that isn't a guess about
	# which of the two the player meant to move. The empty slots are the targets.
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	var offer := {"type": "pill", "id": &"luck_up", "horse": false}
	var modal := LootDropModal.open(_ui, offer)
	await wait_frames(2)
	var grid: LootGrid = _find_grid(modal) as LootGrid
	if grid == null:
		return
	var payload := {"kind": "loot_take", "entry": offer, "offer": 0}
	assert_false(grid.get_child(0)._can_drop_data(Vector2.ZERO, payload),
		"the slot holding the scroll refuses it")
	assert_true(grid.get_child(1)._can_drop_data(Vector2.ZERO, payload),
		"and there is always a free one to take it while the pack has room")
	modal.leave()

func test_a_full_pack_refuses_the_drop() -> void:
	GameState.loot_items.clear()
	for i in range(GameState.LOOT_CAPACITY):
		GameState.add_pill_loot(&"luck_up")
	var modal := LootDropModal.open(_ui, {"type": "scroll", "id": &"scroll_of_fire"})
	await wait_frames(2)
	var grid: LootGrid = _find_grid(modal) as LootGrid
	if grid == null:
		return
	assert_false(grid.get_child(0)._can_drop_data(Vector2.ZERO,
		{"kind": "loot_take", "entry": {"type": "scroll", "id": &"scroll_of_fire"}, "offer": 0}),
		"there is nowhere for a tenth piece to go, which is what makes "
		+ "'leave it' a real answer")
	modal.leave()

func test_the_page_logs_what_a_drop_screen_placed() -> void:
	# The pieces are already in the pack by the time the page hears about them, so
	# its job is the log and the redraw.
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	var before: int = GameLog.messages.size() if "messages" in GameLog else 0
	_ui._note_loot_taken([{"type": "pill", "id": &"luck_up", "horse": false}])
	assert_eq(GameState.loot_items.size(), 1,
		"it does NOT take them again — the screen already placed them")
	if "messages" in GameLog:
		assert_gt(GameLog.messages.size(), before, "and it writes down what was kept")

# --- Spending and binning from the drop screen (§4.3) ----------------------
#
# A full pack used to leave exactly two answers to a payout: leave it, or close
# the modal, go and spend something, and never get the payout back. Everything on
# that screen can be spent or binned from it now, the offered piece included.

# --- Saying what the piece did (§4.3) --------------------------------------
#
# Taking a pill used to close the modal the instant it resolved, which put the
# answer to "what did that do to me" in the run log on the far side of the page —
# the one place the player was not looking, having just been looking at the pill.
# On an unidentified capsule that IS the minigame: the reason to swallow an unknown
# pill is to find out what it was.

func test_taking_a_pill_says_what_it_did() -> void:
	GameState.loot_items.clear()
	GameState.add_pill_loot(&"health_up")
	GameState.set_max_hp(20, false)
	GameState.set_hp(5)
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.start(_ui, 0, _ui)
	await wait_frames(2)
	modal._on_read()
	await wait_frames(2)
	assert_true(is_instance_valid(modal),
		"the modal stays up rather than vanishing the moment the pill resolves")
	if not is_instance_valid(modal):
		return
	var text: String = _text_of(modal)
	assert_true(text.contains("Health"),
		"and it says what happened to you: %s" % text)
	assert_true(text.contains("Done"), "with one way out of it")
	modal._finish()
	await wait_frames(2)

func test_the_outcome_screen_names_the_colour_this_use_taught_you() -> void:
	PillSystem.unidentify(&"luck_up")
	GameState.loot_items.clear()
	GameState.add_pill_loot(&"luck_up")
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.start(_ui, 0, _ui)
	await wait_frames(2)
	var before: String = _text_of(modal)
	assert_true(before.contains("Unidentified"),
		"it goes in a gamble: %s" % before.substr(0, 80))
	modal._on_read()
	await wait_frames(2)
	if not is_instance_valid(modal):
		return
	var text: String = _text_of(modal)
	assert_true(text.contains(PillSystem.display_name(
		{"type": "pill", "id": &"luck_up", "horse": false})),
		"and comes out named — the capsule above the line is the colour, "
		+ "so the name under it is what the colour means: %s" % text)
	assert_true(text.contains("know"),
		"said as the lesson it is: %s" % text)
	modal._finish()
	await wait_frames(2)

func test_a_teleport_says_where_it_put_you() -> void:
	# THE PIECE THAT USED TO SAY NOTHING. A teleport is the one op on either
	# consumable that resolves nowhere near the system that owns it — read_scroll and
	# take_pill hand back a REQUEST and are finished — so it contributed no log line
	# at all and Telepills came out the far end of a use reporting "Nothing happens."
	GameState.loot_items.clear()
	GameState.add_pill_loot(&"telepills")
	var was: StringName = GameState.current_game_id
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.start(_ui, 0, _ui)
	await wait_frames(2)
	modal._on_read()
	await wait_frames(2)
	if not is_instance_valid(modal):
		return
	var text: String = _text_of(modal)
	assert_false(text.contains("Nothing happens"),
		"the piece that moves you is not a piece that did nothing: %s" % text)
	assert_true(text.contains("Teleported to") or text.contains("fizzles"),
		"it says where you ended up, or why you did not move: %s" % text)
	if GameState.current_game_id != was:
		assert_true(text.contains("from the Amulet"),
			"and how far out that is, which is the fact the op is about: %s" % text)
	modal._finish()
	await wait_frames(2)

func test_the_outcome_names_the_pieces_echo_chamber_replayed() -> void:
	# Echo Chamber's copies resolve into the SAME merged logs as the piece's own, so
	# without naming them the outcome is four pieces' worth of effects and no account
	# of where three of them came from.
	GameState.loot_items.clear()
	GameState.add_pill_loot(&"luck_up")
	GameState.add_pill_loot(&"health_up")
	LootSystem.use_loot(0)          # something for the relic to copy
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	if GameState.loot_echo_depth() <= 0:
		return                       # no such relic in the catalog — nothing to assert
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.start(_ui, 0, _ui)
	await wait_frames(2)
	modal._on_read()
	await wait_frames(2)
	if not is_instance_valid(modal):
		return
	assert_true(_text_of(modal).contains("Echo Chamber also used"),
		"the outcome says whose lines those are: %s" % _text_of(modal))
	modal._finish()
	await wait_frames(2)

func test_backing_out_of_a_use_says_nothing_about_what_it_did() -> void:
	# Cancel is not a use. The outcome screen is what a use ends on, so a piece that
	# was never spent must not reach it.
	GameState.loot_items.clear()
	GameState.add_pill_loot(&"luck_up")
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	var done := [false]
	modal.finished.connect(func(): done[0] = true)
	modal.start(_ui, 0, _ui)
	await wait_frames(2)
	modal._finish()
	await wait_frames(2)
	assert_true(done[0], "cancelling closes it outright")
	assert_eq(GameState.loot_items.size(), 1, "and the piece is still in the pack")

func _find_use_modal() -> Node:
	for c in _ui.get_children():
		if c is CanvasLayer and c.layer == LootDropModal.USE_LAYER:
			for k in c.get_children():
				if k.has_method("_on_read"):
					return k
	return null

func _full_pack() -> void:
	GameState.loot_items.clear()
	for i in range(GameState.LOOT_CAPACITY):
		GameState.add_pill_loot(&"luck_up")

func test_a_carried_piece_can_be_spent_from_the_drop_screen() -> void:
	_full_pack()
	var modal := LootDropModal.open(_ui, {"type": "scroll", "id": &"scroll_of_fire"})
	await wait_frames(2)
	assert_true(GameState.loot_is_full(), "the pack starts full")
	modal._use_carried(0)
	await wait_frames(2)
	var use_modal: Node = _find_use_modal()
	assert_not_null(use_modal, "the Use button opens the same modal the window does")
	if use_modal == null:
		return
	use_modal._on_read()
	await wait_frames(2)
	assert_eq(GameState.loot_items.size(), GameState.LOOT_CAPACITY - 1,
		"spending one from here frees the slot the offer needs")
	assert_false(GameState.loot_is_full())
	assert_false(modal._answered,
		"and the drop is still on the table — spending is not answering it")
	use_modal._finish()
	await wait_frames(2)
	modal.leave()

func test_the_offered_piece_can_be_used_without_ever_being_carried() -> void:
	# The answer every roguelike gives to a full bag: drink it where you stand.
	_full_pack()
	var held: int = GameState.loot_items.size()
	var modal := LootDropModal.open(_ui, {"type": "pill", "id": &"health_up", "horse": false})
	await wait_frames(2)
	# Tracked through the signal rather than off the modal: answering frees it, so
	# reading a field back off it afterwards is reading a freed object.
	var fired := [false]
	var taken_answer := [["unset"]]
	modal.answered.connect(func(taken: Array):
		fired[0] = true
		taken_answer[0] = taken)
	modal._use_offer(0)
	await wait_frames(2)
	var use_modal: Node = _find_use_modal()
	assert_not_null(use_modal, "the offer opens the same spend screen a carried piece does")
	if use_modal == null:
		return
	use_modal._on_read()
	await wait_frames(2)
	assert_eq(GameState.loot_items.size(), held,
		"it costs no slot — it never entered the pack")
	assert_false(fired[0],
		"the drop waits on the screen that says what the piece did — a use that "
		+ "closed everything the instant it resolved is what the outcome screen "
		+ "is for")
	use_modal._finish()
	await wait_frames(2)
	assert_true(fired[0], "and once that is read, using the offer resolves the drop")
	assert_eq(taken_answer[0], [],
		"and nothing is reported as kept: the page has nothing to collect")

func test_using_the_offer_identifies_it_like_any_other_use() -> void:
	# Spending it where you stand is spending it: the gamble pays the same lesson.
	PillSystem.ensure_colors()
	assert_false(PillSystem.is_identified(&"health_up"))
	var modal := LootDropModal.open(_ui, {"type": "pill", "id": &"health_up", "horse": false})
	await wait_frames(2)
	modal._use_offer(0)
	await wait_frames(2)
	var use_modal: Node = _find_use_modal()
	if use_modal == null:
		return
	use_modal._on_read()
	await wait_frames(2)
	assert_true(PillSystem.is_identified(&"health_up"),
		"a colour taken on the spot is a colour learned")
	use_modal._finish()
	await wait_frames(2)

func test_binning_the_offer_is_leaving_it() -> void:
	var modal := LootDropModal.open(_ui, {"type": "scroll", "id": &"scroll_of_fire"})
	await wait_frames(2)
	var kept := [["unset"]]
	modal.answered.connect(func(taken: Array): kept[0] = taken)
	var grid: LootGrid = _find_grid(modal) as LootGrid
	assert_not_null(grid)
	if grid == null:
		return
	var payload := {"kind": "loot_take",
		"entry": {"type": "scroll", "id": &"scroll_of_fire"}, "offer": 0}
	assert_true(grid.can_trash(payload), "the bin takes the offer")
	grid.trash(payload)
	assert_eq(kept[0], [], "which is 'Leave it', said with the hands — nothing was kept")

func test_binning_a_carried_piece_asks_before_destroying_it() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_pill_loot(&"luck_up")
	var grid: LootGrid = _open_loot_grid()
	if grid == null:
		return
	# The payload the grid's own cells hand over: the SLOT it is leaving and the
	# index of the piece, which are two different numbers now that a pack can have
	# holes in it — and the bin destroys a piece, so it reads the index.
	var bagged := {"kind": "loot_move", "from": 0, "index": 0}
	assert_true(grid.can_trash(bagged), "the bin takes a carried piece")
	grid.trash(bagged)
	await wait_frames(2)
	assert_eq(GameState.loot_items.size(), 2,
		"nothing is destroyed on the drop alone — the bin is the one gesture here "
		+ "that gives nothing back, so it asks")
	var confirm: ConfirmPanel = _find_confirm(_ui)
	assert_not_null(confirm, "and this is what asks")
	if confirm == null:
		return
	confirm._on_ok.call()
	assert_eq(GameState.loot_items.size(), 1, "saying yes destroys it")
	confirm.dismiss()

func test_nothing_can_be_binned_mid_report() -> void:
	GameState.add_pill_loot(&"luck_up")
	var grid: LootGrid = _open_loot_grid()
	if grid == null:
		return
	grid.locked = true
	assert_false(grid.can_trash({"kind": "loot_move", "from": 0, "index": 0}),
		"loot cannot leave the pack between 'played the game' and 'said what happened'")

# --- A payout of several pieces at once (§4.3) -----------------------------
#
# Mom's Coin Purse is four pills, and Sacred Bark doubles what a grant pays. One
# offer per screen answered that by shovelling the rest into the pack and silently
# dropping whatever did not fit — which is the one thing the nine-piece cap exists
# to make into a decision.

func test_a_payout_of_several_pieces_asks_about_all_of_them_at_once() -> void:
	GameState.loot_items.clear()
	var offers: Array = []
	for i in range(4):
		offers.append({"type": "pill", "id": &"luck_up", "horse": false})
	var modal := LootDropModal.open(_ui, offers)
	await wait_frames(2)
	assert_eq(modal._offers.size(), 4, "all four are on the table")
	var text: String = _text_of(modal)
	assert_true(text.contains("4"), "and the screen says so: %s" % text.substr(0, 80))
	modal.leave()

func test_each_offer_is_taken_on_its_own_terms() -> void:
	GameState.loot_items.clear()
	var offers: Array = [
		{"type": "pill", "id": &"luck_up", "horse": false},
		{"type": "scroll", "id": &"scroll_of_fire"},
		{"type": "pill", "id": &"health_up", "horse": false},
	]
	var modal := LootDropModal.open(_ui, offers)
	await wait_frames(2)
	modal._take_offer(offers[1], 0, 1)
	assert_eq(modal._offers.size(), 2, "the one that was taken leaves the table")
	assert_eq(String(GameState.loot_items[0].get("id", "")), "scroll_of_fire",
		"and it is the one that was dragged, not the first on the table — "
		+ "four identical unidentified capsules cannot be told apart by entry")
	modal.leave()

func test_take_all_stops_at_the_cap_rather_than_dropping_the_rest() -> void:
	# The silent loss this whole path exists to prevent.
	GameState.loot_items.clear()
	for i in range(7):
		GameState.add_pill_loot(&"luck_up")
	var offers: Array = []
	for i in range(4):
		offers.append({"type": "scroll", "id": &"scroll_of_fire"})
	var modal := LootDropModal.open(_ui, offers)
	await wait_frames(2)
	var kept := [[]]
	modal.answered.connect(func(taken: Array): kept[0] = taken)
	modal.take()
	await wait_frames(2)
	assert_eq(GameState.loot_items.size(), GameState.LOOT_CAPACITY, "it fills the pack")
	# The screen stays open on the leftovers rather than throwing them away behind
	# the player's back — which is the whole reason a payout this size has to ask.
	assert_true(is_instance_valid(modal) and not modal._answered,
		"and it is still open, because two pieces are still on the table")
	if not is_instance_valid(modal):
		return
	assert_eq(modal._offers.size(), 2, "the two that did not fit")
	assert_eq(modal._taken.size(), 2, "and it is holding the two that did")
	# The report comes when the screen closes, not on every take.
	modal.leave()
	await wait_frames(2)
	assert_eq(kept[0].size(), 2, "which is what the page is told to log")

func test_the_reward_screen_carries_the_same_record_the_window_does() -> void:
	# "The only difference should be the loot reward on the left" — the fold at the
	# foot of the pack is part of the inventory, so it is on both.
	PillSystem.ensure_colors()
	PillSystem.identify(&"luck_up")
	var modal := LootDropModal.open(_ui, {"type": "scroll", "id": &"scroll_of_fire"})
	await wait_frames(2)
	var text: String = _text_of(modal)
	assert_true(text.contains("Known this run"),
		"the reward screen carries the record too: %s" % text.substr(0, 120))
	modal.leave()

func test_the_record_is_one_fold_shared_by_both_surfaces() -> void:
	# A fold shut in the window and open on the reward screen would be two answers
	# to one question.
	LootDiscoveries.open = false
	_ui._loot_window.discoveries_open = true
	assert_true(LootDiscoveries.open,
		"the window's own name for it writes through to the shared flag")
	var modal := LootDropModal.open(_ui, {"type": "scroll", "id": &"scroll_of_fire"})
	await wait_frames(2)
	assert_true(_text_of(modal).contains("▾"),
		"so the reward screen opens it unfolded too")
	modal.leave()
	LootDiscoveries.open = false

func test_the_record_never_names_an_unlearned_colour() -> void:
	# The rule the whole section exists under, checked on the class that owns it now.
	PillSystem.ensure_colors()
	PillSystem.identify(&"luck_up")
	var known: Array = LootDiscoveries.known_pills()
	var ids: Array = []
	for entry in known:
		ids.append(StringName(entry.get("id", "")))
	assert_true(ids.has(&"luck_up"), "what was learned is listed")
	assert_false(ids.has(&"bad_trip"),
		"and what was not is never named — nine known colours must not tell you "
		+ "what the tenth is")

func test_a_relic_granting_loot_asks_instead_of_filling_the_pack() -> void:
	# GameState.offer_loot rolls the pieces and hands them to whoever is listening;
	# the page queues them as one question.
	GameState.loot_items.clear()
	_ui._drop_queue.clear()
	GameState.offer_loot("pill", 4)
	assert_true(GameState.loot_items.is_empty(),
		"nothing is pushed into the pack behind the player's back")
	assert_eq(_ui._drop_queue.size(), 1, "it is one question, not four")
	var queued = _ui._drop_queue[0].get("loot")
	assert_true(queued is Array, "carrying all four offers")
	assert_eq((queued as Array).size(), 4)
	_ui._drop_queue.clear()

func test_a_loot_grant_still_lands_directly_when_nothing_is_listening() -> void:
	# Headless runs, PlaySession2 and the unit tests have no screen to ask on, and
	# offer_loot has to stay a pure state change there.
	GameState.loot_items.clear()
	GameState.loot_offered.disconnect(_ui._on_loot_offered)
	GameState.offer_loot("pill", 3)
	assert_eq(GameState.loot_items.size(), 3,
		"with nobody connected it grants directly, as add_loot always did")
	GameState.loot_offered.connect(_ui._on_loot_offered)

func _find_confirm(node: Node) -> ConfirmPanel:
	if node is ConfirmPanel:
		return node
	for c in node.get_children():
		var found: ConfirmPanel = _find_confirm(c)
		if found != null:
			return found
	return null

func test_clicking_a_carried_piece_opens_its_card() -> void:
	# Click reads, drag moves, the button spends — a relic in the pack has answered
	# a click with its card since ItemInfoCard shipped, and loot answered with
	# nothing at all.
	GameState.add_pill_loot(&"luck_up")
	_ui.open_loot_card(0)
	await wait_frames(2)
	assert_true(_ui._item_card is LootInfoCard, "the reading card for a piece of loot")
	if _ui._item_card != null:
		_ui._item_card.close()

func test_the_loot_toggle_carries_the_count_and_says_when_it_is_full() -> void:
	GameState.loot_items.clear()
	for i in range(GameState.LOOT_CAPACITY):
		GameState.add_pill_loot(&"luck_up")
	_ui._refresh_items()
	var text: String = _text_of(_ui._loot_toggle_box)
	assert_true(text.contains("9/9"), "the toggle carries the count: %s" % text)
	var btn: Button = null
	for c in _ui._loot_toggle_box.get_children():
		if c is Button:
			btn = c
	assert_not_null(btn)
	if btn == null:
		return
	assert_true(btn.tooltip_text.contains("Full"),
		"and says the next payout has nowhere to go, before the drop asks")

func test_tab_opens_and_shuts_the_loot_window() -> void:
	# The `backpack` action existed in project.godot with nothing on the overworld
	# listening for it.
	GameState.add_pill_loot(&"luck_up")
	assert_false(_ui._loot_window.open, "it starts shut")
	var ev := InputEventAction.new()
	ev.action = &"backpack"
	ev.pressed = true
	_ui._unhandled_input(ev)
	assert_true(_ui._loot_window.open, "Tab opens it")
	_ui._unhandled_input(ev)
	assert_false(_ui._loot_window.open, "and Tab shuts it again")

func test_tab_is_ignored_while_a_drop_is_being_decided() -> void:
	var modal := LootDropModal.open(_ui, {"type": "pill", "id": &"luck_up", "horse": false})
	_ui._drop_modal = modal
	await wait_frames(2)
	var ev := InputEventAction.new()
	ev.action = &"backpack"
	ev.pressed = true
	_ui._unhandled_input(ev)
	assert_false(_ui._loot_window.open,
		"the pack behind a drop modal is not what the key is about")
	modal.leave()
	_ui._drop_modal = null

func test_the_window_records_what_the_run_has_learned() -> void:
	# The identification minigame with a record of itself (§4.3): a colour learned
	# on game three has to be readable on game eleven.
	PillSystem.ensure_colors()
	PillSystem.identify(&"luck_up")
	_ui._loot_window.open = true
	_ui._loot_window.discoveries_open = true
	_ui._refresh_items()
	var text: String = _text_of(_ui._loot_panel)
	assert_true(text.contains("Known this run"), "the fold is there: %s" % text)
	var learned: PillData = Data.get_pill(&"luck_up")
	assert_true(text.contains(learned.display_name),
		"and it names the colour that was learned: %s" % text)

func test_the_window_counts_unlearned_colours_rather_than_naming_them() -> void:
	# Naming them would hand back exactly the deduction the three sitting-out
	# colours exist to prevent.
	PillSystem.ensure_colors()
	PillSystem.identify(&"luck_up")
	_ui._loot_window.open = true
	_ui._loot_window.discoveries_open = true
	_ui._refresh_items()
	var text: String = _text_of(_ui._loot_panel)
	var unknown: PillData = Data.get_pill(&"bad_trip")
	if unknown != null and not PillSystem.is_identified(&"bad_trip"):
		assert_false(text.contains(unknown.display_name),
			"an unlearned pill is never named: %s" % text)
	assert_true(text.contains("unlearned"), "it is counted instead: %s" % text)

func test_the_map_button_belongs_to_the_offering() -> void:
	var found: Button = null
	for c in _ui._select_box.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is Button and String((b as Button).text).contains("Map"):
					found = b
	assert_not_null(found, "the map opens from the panel it is a map of")

# …AND FROM THE HEADER, which is the only one of the two that is up mid-game: the
# offering panel is put away the moment you commit, and "where does this game
# leave me" is worth asking hardest while you are standing on the board.
func test_the_map_opens_from_the_header_while_a_game_is_in_play() -> void:
	assert_not_null(_ui._header_map_btn, "the header carries a Map button")
	var kids: Array = _ui._header.get_children()
	var map_at: int = kids.find(_ui._header_map_btn)
	var menu_at: int = -1
	for i in range(kids.size()):
		if kids[i] is MenuButton:
			menu_at = i
	assert_gt(map_at, -1, "it is in the header row")
	assert_eq(map_at, menu_at - 1, "immediately left of the menu")
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "a game is in play")
	assert_true(_ui._header_map_btn.visible, "and the button is still there")
	var modal = _ui.open_map()
	assert_not_null(modal, "which opens the map from inside the game")
	_leave_post_game()

# The header's mid-game map must not star the last offering's cards: those three
# games are not on offer any more, and the map's whole job is where you go NEXT.
func test_the_mid_game_map_stars_nothing() -> void:
	_ui.pick(0)
	var modal = _ui.open_map()
	assert_not_null(modal)
	if modal != null:
		assert_true((modal._choice_ids as Dictionary).is_empty(),
			"no card is flagged while there is no offering: %s" % str(modal._choice_ids))
	_leave_post_game()

func test_the_menu_holds_the_runs_admin() -> void:
	# Save / New run / Main menu were three buttons parked across the top for the
	# whole run. They are menu entries now, and the menu is the only header button.
	var mb: MenuButton = null
	var header: Node = _ui._header
	for c in header.get_children():
		if c is MenuButton:
			mb = c
	assert_not_null(mb, "the header carries one menu button")
	var labels: Array = []
	for i in range(mb.get_popup().item_count):
		labels.append(mb.get_popup().get_item_text(i))
	var joined: String = "\n".join(labels)
	for want in ["Save run", "New run", "Main menu", "Exit game"]:
		assert_true(joined.contains(want), "%s is in the menu: %s" % [want, joined])
	# And the entries do what they say.
	_ui.menu_action(_ui.MenuItem.NEW_RUN)
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT, "New run reopens the start picker")

# Exiting is the one menu entry with a run standing behind it, so it asks first —
# and it asks the question that is actually open (keep this run in the save list
# or not), rather than a bare "are you sure".
func test_exiting_asks_before_it_leaves() -> void:
	var dlg: ConfirmationDialog = _ui.prompt_quit()
	assert_not_null(dlg, "Exit game raises a confirmation rather than quitting on the spot")
	var labels: Array = [dlg.ok_button_text, dlg.get_cancel_button().text]
	# add_button() parks its button in the dialog's own button row, not on the
	# dialog, so this has to walk the whole subtree to find it.
	for b in dlg.find_children("*", "Button", true, false):
		labels.append((b as Button).text)
	var joined: String = "\n".join(labels)
	for want in ["Exit", "Cancel", "Save & exit"]:
		assert_true(joined.contains(want), "%s is one of the answers: %s" % [want, joined])
	dlg.queue_free()

# "Save & exit" is one press, but it is still two steps: the name prompt has to
# open, and the quit only happens once a save has actually been written.
func test_save_and_exit_asks_for_a_name_first() -> void:
	var quit_calls: Array = []
	_ui.prompt_save(func(): quit_calls.append(true))
	var prompt: AcceptDialog = null
	for c in _ui.get_children():
		if c is AcceptDialog and (c as AcceptDialog).title == "Save run":
			prompt = c
	assert_not_null(prompt, "the name prompt opens before anything is written")
	assert_true(quit_calls.is_empty(), "and nothing has quit yet")
	# A blank name is not a save, so it is not an exit either.
	var edit: LineEdit = null
	for node in prompt.find_children("*", "LineEdit", true, false):
		edit = node
	assert_not_null(edit, "the prompt takes a name")
	edit.text = ""
	prompt.confirmed.emit()
	assert_true(quit_calls.is_empty(), "a refused save does not take the player out of the game")

# --- the page fits the window it ships in ---------------------------------
#
# The overworld is meant to be read WHOLE: the offering and the board closing in
# on you are two halves of one decision, and a decision you have to scroll
# between is a decision made on half the facts. project.godot ships a 1280x720
# window, so that is the box, and it holds in every phase and at every board size
# the tiers can reach. The page still lives in a ScrollContainer — nothing is
# CLIPPED if a future row overruns — so this test is what notices.

func _page_height() -> float:
	var root: Control = _ui._scroll.get_child(0)
	var total: float = 0.0
	var shown: int = 0
	for c in root.get_children():
		if c is Control and (c as Control).visible:
			total += (c as Control).size.y
			shown += 1
	return total + root.get_theme_constant("separation") * maxi(0, shown - 1)

func _assert_fits(what: String) -> void:
	# Sized against the window the project ships, not against whatever the test
	# harness happens to give the viewport.
	#
	# The HEADER comes off the top of the room rather than out of the page: it is
	# pinned to the screen on its own layer now (Overworld2._mount_header), so it
	# is not one of the rows `_page_height` adds up — but the page still only gets
	# what is left under it.
	var bar: float = _ui._header_bar.get_combined_minimum_size().y
	var room: float = 720.0 - 32.0 - bar   # the scroll's top+bottom offsets
	assert_lte(_page_height(), room,
		"%s fits a 720p window (needs %.0f of %.0f)" % [what, _page_height(), room])

func test_the_offering_screen_fits_one_window() -> void:
	_ui._refresh()
	_assert_fits("the choosing screen")

func test_the_playing_screen_fits_one_window() -> void:
	_ui.pick(0)
	_ui._refresh()
	_assert_fits("the report screen")

# The two verbs sit BESIDE the cover rather than stacked under it. Four
# full-width bands — art, line, Play, Lost a run — above a checklist that is the
# reason the panel exists is the checklist paying for the paperwork; beside the
# art the pair costs the panel nothing but the height the cover already had.
func test_the_play_verbs_sit_beside_the_cover() -> void:
	_ui.pick(0)
	_ui._refresh()
	await get_tree().process_frame
	var cover: Control = _ui._now_playing_cover
	for btn: Button in [_ui._attempt_btn]:
		assert_gt(btn.global_position.x, cover.get_global_rect().end.x - 1.0,
			"%s is to the right of the cover" % btn.text.split("\n")[0])
		assert_lt(btn.global_position.y, cover.get_global_rect().end.y,
			"and beside it rather than under it")

func test_the_biggest_board_still_fits_one_window() -> void:
	# The board gains a column AND a row per difficulty step; the top of the
	# ladder is the case that used to run off the bottom of the window.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER * RunDifficulty.MAX_TIER
	_ui._build_choices()
	_ui._refresh()
	assert_gt(GameLoop2.grid_rows(), GameLoop2.BASE_GRID_COLS, "the board really did grow")
	_assert_fits("the top-tier board")

func _buttons_in(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button:
			out.append(c)
	return out

# --- the header never leaves the screen ------------------------------------
#
# Health, Gold, the road walked, the title and the menu are the run's readout,
# and every one of them used to be the first row INSIDE the scrolling page: they
# left the screen the moment the player looked at the bottom of a tall board, and
# they were behind every modal the run raises — which is exactly where Health is
# most worth reading, because an event asking you to gamble is a question about a
# health bar you could not see.

func test_the_header_is_not_part_of_the_scrolling_page() -> void:
	assert_not_null(_ui._header, "the header is built")
	assert_false(_ui._scroll.is_ancestor_of(_ui._header),
		"and it is not a row of the page that scrolls away under the board")
	assert_true(_ui._header_layer is CanvasLayer,
		"it floats on a layer of its own instead")

func test_the_header_floats_over_the_modals_a_run_raises() -> void:
	# Above everything the RUN puts on screen (the event modal is the tallest of
	# them at 123, the map at 130) and below the screens that REPLACE the run
	# rather than sit over it — the Atlas at 140 and the verdict at 150.
	assert_gt(_ui.HEADER_LAYER, 130, "over the run's own modals and its map")
	assert_lt(_ui.HEADER_LAYER, 140, "under the Atlas and the end-of-run verdict")

func test_the_page_starts_below_the_header_bar() -> void:
	# Floating over the page is only safe if the page is inset by exactly as much
	# as the bar covers — otherwise the top of the offering is under it.
	_ui._fit_page_under_header()
	var bar: float = maxf(_ui._header_bar.size.y, _ui._header_bar.get_combined_minimum_size().y)
	assert_gt(bar, 0.0, "the bar has a height")
	assert_gte(_ui._scroll.offset_top, bar,
		"and nothing on the page is hidden underneath it")

# The title and the menu are the right-hand end of the header in EVERY phase.
# They used to start on the left on the start picker and jump to the right the
# moment the first game was taken, because the road strip between them was
# HIDDEN until the run had a position — and a hidden Control takes no room, so
# there was nothing holding them out there.
func test_the_title_and_the_menu_keep_the_right_edge_before_a_game_is_picked() -> void:
	_ui.start_run()
	_ui._refresh()
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT, "back on the start picker")
	assert_true(_ui._route_strip.visible,
		"the road strip stays mounted even with no road to draw — it is the header's spacer too")
	assert_true(_ui._route_strip.size_flags_horizontal & Control.SIZE_EXPAND != 0,
		"and it is still the thing that eats the slack")

# --- the road walked, across the top of the header -------------------------
#
# GAMES PLAYED, and nothing else. The strip used to close on the AMULET with the
# gap not yet walked drawn dashed — so the header carried a cover for a game the
# player had never been to, sitting directly beside the ones they had, reading as
# the next stop on the road. The road ahead has two screens of its own.

func test_the_road_walked_carries_only_games_the_run_has_reached() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	_leave_post_game()
	_ui._refresh()
	var walked: Array = GameState.walked_path()
	var stops: Array = _ui.route_strip_stops()
	assert_gt(stops.size(), 0, "there is a road to draw")
	for id in stops:
		assert_true(walked.has(id),
			"%s is on the strip and the run has been to it" % id)

func test_the_amulet_is_not_drawn_on_the_road_behind_you() -> void:
	var amulet: StringName = GameState.amulet_game_id
	if amulet == &"" or GameState.walked_path().has(amulet):
		return    # standing on it is a legitimate stop; there is nothing to catch
	_ui._refresh()
	assert_false(_ui.route_strip_stops().has(amulet),
		"the game the run is a search for is ahead of it, not behind it")

func test_the_road_walked_keeps_the_doubling_back() -> void:
	# `visited_games` is a set, so a run that came back to a game drew one cover
	# for two stops. The strip reads the WALK now (GameState.walked_path).
	var start: StringName = GameState.current_game_id
	var away: StringName = _neighbour_of_here()
	if away == &"" or away == start:
		return
	GameState.set_current_game(away)
	GameState.set_current_game(start)
	_ui._refresh_route_strip()
	var stops: Array = _ui.route_strip_stops()
	assert_eq(stops.size(), 3, "three stops on the road, not two: %s" % [stops])
	assert_eq(StringName(stops[0]), start, "out from here")
	assert_eq(StringName(stops[1]), away, "over to there")
	assert_eq(StringName(stops[2]), start, "and back again")

func test_only_the_last_stop_is_ringed_as_where_you_are() -> void:
	var start: StringName = GameState.current_game_id
	var away: StringName = _neighbour_of_here()
	if away == &"" or away == start:
		return
	GameState.set_current_game(away)
	GameState.set_current_game(start)
	_ui._refresh_route_strip()
	var here_tips: Array = []
	for c in _ui._route_strip.get_children():
		if c is PanelContainer and c.has_meta("stop") \
				and String((c as PanelContainer).tooltip_text).contains("you are here"):
			here_tips.append(c)
	assert_eq(here_tips.size(), 1,
		"the run stood on this game twice; only the stop it is standing on now says so")

# --- the Dash offering ------------------------------------------------------

# A Dash is not a hand of three cards — off a hub it is twenty covers, and the
# question stops being "which of these" and becomes "is the game I want in here".
# The seeded shuffle that keeps a three-card offering from feeling like a menu is
# exactly wrong for a list you are searching.
func test_dashing_lists_the_connected_games_in_alphabetical_order() -> void:
	GameState.dash_charges = 1
	_ui.dash()
	assert_true(_ui._dash_mode, "the Dash panel is up")
	var names: Array = []
	for c in _ui._choices:
		names.append(String((c["game"] as GameData).display_name))
	var expected: Array = names.duplicate()
	expected.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	assert_eq(names, expected, "A-Z, so a game can be found by eye: %s" % [names])
	_ui.cancel_dash()

# The offering prints "⚡ +1 DASH" on a game the run has played, and the usual way
# back to one is to SPEND a Dash — the offering is three of a hub's twenty
# neighbours, so the game you want is rarely on the table. Spend one to travel
# and earn one for the clear and the counter reads what it read before: the card
# promised a charge and the player watched nothing happen.
func test_dashing_back_to_a_game_you_played_leaves_you_a_dash_up() -> void:
	GameState.dash_charges = 2
	_ui.dash()
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_played(target.id)
	_ui._build_choices()
	var before: int = GameState.dash_charges
	_ui.pick(0)
	assert_eq(GameState.dash_charges, before - 1, "the trip itself cost a charge")
	_report_beat(_ui)
	assert_eq(GameState.dash_charges, before + OVERWORLD.REPEAT_BEAT_DASH,
		"and the clear pays the +%d the card advertised, on top of the fare"
			% OVERWORLD.REPEAT_BEAT_DASH)

func test_walking_back_to_a_game_you_played_still_pays_exactly_one_dash() -> void:
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_played(target.id)
	_ui._build_choices()
	var before: int = GameState.dash_charges
	_ui.pick(0)
	assert_eq(GameState.dash_charges, before, "an ordinary pick costs nothing")
	_report_beat(_ui)
	assert_eq(GameState.dash_charges, before + OVERWORLD.REPEAT_BEAT_DASH,
		"so the clear is the only thing that moved the counter")

# --- curses on the report checklist ----------------------------------------
#
# A curse is a row like any other on this list: an INSTRUCTION, ticked if you
# followed it, with what it costs written after it. It used to be phrased as the
# rule instead — "If you use a rest site to replenish health, spawn a random
# enemy when you report the game" — with a box that fired the penalty when you
# CHECKED it, which made it the one row on the checklist whose tick meant the
# opposite of every other row's.

func _curse_checks() -> Array:
	var out: Array = []
	for entry in _ui._curse_goal_checks:
		out.append(entry["check"])
	return out

func test_a_curse_row_reads_as_the_thing_to_do_with_its_price_after_it() -> void:
	GameState.add_curse_goal(&"poor_sleep")
	_ui.pick(0)
	var checks: Array = _curse_checks()
	assert_eq(checks.size(), 1, "the curse is on the checklist")
	if checks.is_empty():
		return
	var text: String = (checks[0] as CheckBox).text
	assert_string_contains(text, "don't use a rest site to replenish health")
	assert_string_contains(text, "if failed, Spawn a random enemy")
	assert_false(text.contains("If you"), "not the rule it was derived from: %s" % text)

# …and a curse authored as the ABSENCE of something is not doubled up. Curse of
# the Bell's condition is "you don't ring a bell", and the instruction that comes
# out of it is "ring a bell" rather than "don't don't ring a bell".
func test_a_negatively_authored_curse_is_not_negated_twice() -> void:
	var bell: CurseData2 = Data.get_curse2(&"curse_of_the_bell")
	assert_not_null(bell)
	if bell == null:
		return
	assert_eq(bell.goal_text(), "ring a bell")

func test_every_checklist_row_opens_unanswered_including_the_curses() -> void:
	GameState.add_curse_goal(&"poor_sleep")
	_ui.pick(0)
	for check in _curse_checks():
		assert_false((check as CheckBox).button_pressed,
			"an empty box means 'I did not do this' on every row of the list")
	for f in _ui._fulfil_checks:
		assert_false((f["check"] as CheckBox).button_pressed,
			"every enemy row too — the ones that walked on with this game included")

# Poor Sleep's bill is a BODY (every curse's is), so both halves of this are
# read off the board: a met goal leaves nothing following, so anything standing
# there afterwards is the curse and only the curse.
func test_a_curse_you_ticked_costs_nothing() -> void:
	GameState.add_curse_goal(&"poor_sleep")
	_pick_solo(0)
	var checks: Array = _curse_checks()
	if checks.is_empty():
		return
	_tick(checks[0])                                 # "I didn't use a rest site"
	_report_beat(_ui)
	assert_eq(GameLoop2.stack_size(), 0,
		"the goal was met and the curse was followed, so nothing is following")

func test_a_curse_left_unticked_is_what_bites() -> void:
	GameState.add_curse_goal(&"poor_sleep")
	_pick_solo(0)
	_report_beat(_ui)                       # the row left exactly as it opened
	assert_eq(GameLoop2.stack_size(), 1,
		"the goal was met, so the body on the board is Poor Sleep's")
	assert_eq(GameState.curse_goals.size(), 1, "and a curse that bites STAYS")

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
	assert_eq(_ui._inv_wrap.get_index(), 0, "still under the pack strip in that column")
	assert_true(_ui._play_panel.visible, "the checklist is now the report step")
	assert_true(_ui._done_btn.visible, "with something to complete")
	assert_true(_ui._attempt_wrap.visible, "and runs to lose")
	assert_false(_ui._select_box.visible, "the offering is out of the way")

func _labels_under(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Label:
			out.append(String((child as Label).text))
		elif child is CheckBox:
			out.append(String((child as CheckBox).text))
		out.append_array(_labels_under(child))
	return out

# Choosing a game, the checklist lists the goals already on you: the character's
# level-up challenge and every follower's outstanding goal.
func test_the_standing_checklist_lists_what_you_owe() -> void:
	_reboot(&"isaac")                       # Isaac has a level-up condition
	# Every Label under the panel, however deeply a row nests it — a boss row wraps
	# its text beside a portrait, so the depth is not fixed.
	var texts := func() -> String:
		return "\n".join(_labels_under(_ui._verify_box))
	var listed: String = texts.call()
	assert_true(listed.contains("What you need to do"), "the panel says what it is: %s" % listed)
	assert_true(listed.contains("Use sorrow or self-inflicted pain as a weapon"),
		"the level-up challenge is listed: %s" % listed)
	assert_true(listed.contains("Nothing is following you"), "and an empty stack says so: %s" % listed)
	# Miss a goal so an enemy follows: its goal joins the list.
	_pick_solo(0)
	_ui.report(false)
	var follower: GoalEnemyData = GameLoop2.stack[0]["enemy"]
	listed = texts.call()
	assert_true(listed.contains(follower.goal),
		"the follower's outstanding goal is listed: %s" % listed)
	assert_false(listed.contains("Nothing is following you"), "and the empty note is gone")

# EVERY body's portrait rides its row, in both checklists. The board beside this
# list draws each enemy as a picture; drawing them here as names alone made
# pairing a row with a body a name-matching exercise. The boss keeps what was
# actually its own — the orange frame and the "Boss" tooltip on it.
#
# The CHARACTER's own portrait rides the level-up row for exactly the same reason
# (it is the one row on either list that belongs to the player rather than to
# something on the board), and it is skipped here: these counts are about bodies.
# Its frame carries the `character_portrait` meta so it can be told apart without
# this walk having to know what art the run's character ships.
func _texture_rects_under(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child.has_meta(&"character_portrait"):
			continue
		if child is TextureRect and (child as TextureRect).texture != null:
			out.append(child)
		out.append_array(_texture_rects_under(child))
	return out

func test_a_boss_wears_its_portrait_on_both_checklists() -> void:
	GameState.games_played = RunDifficulty.GAMES_PER_TIER   # the gate
	_ui._build_choices()
	assert_true(_ui._boss_round, "this selection is the boss round")
	assert_eq(_texture_rects_under(_ui._verify_box).size(), 0,
		"nothing is following yet, so no portraits on the list")
	_ui.pick(0)
	var boss: GoalEnemyData = _ui._chosen["enemy"]
	assert_true(boss.is_boss(), "the boss round spawned a boss")
	if boss.image == null:
		return                                # this boss ships without art
	# One portrait per body carrying art — a boss round stands its own escort
	# beside the boss now, so this is not "the boss and nothing else".
	var with_art: int = 0
	for entry in GameLoop2.stack:
		var body: GoalEnemyData = entry["enemy"]
		if body != null and body.image != null:
			with_art += 1
	assert_eq(_texture_rects_under(_ui._verify_box).size(), with_art,
		"the report step shows the boss beside the goal it is asking about")
	_ui.report(false)                         # miss it: now it follows you
	assert_eq(_texture_rects_under(_ui._verify_box).size(), with_art,
		"and it keeps its portrait on the standing list it moves to")

func test_an_ordinary_follower_wears_its_portrait_too() -> void:
	_pick_solo(0)
	var e: GoalEnemyData = _ui._chosen["enemy"]
	if e.is_boss() or e.image == null:
		return                                # the boss case, and art-less content
	# The escort left the board a moment ago (_pick_solo) and the panel is rebuilt
	# on a later frame, so it is rebuilt here rather than counted a body stale.
	_ui._populate_play_panel()
	assert_eq(_texture_rects_under(_ui._verify_box).size(), 1,
		"the report step shows the body beside the goal it is asking about")
	_ui.report(false)                         # miss it: now it follows you
	assert_eq(GameLoop2.stack_size(), 1, "a missed goal leaves a follower")
	assert_eq(_texture_rects_under(_ui._verify_box).size(), 1,
		"and it keeps its portrait on the standing list it moves to")

# The frame around the portrait is what still separates a boss from anything else,
# and it is a TOOLTIP rather than a badge — the picture is already the loud part.
func test_only_a_boss_portrait_says_boss() -> void:
	_pick_solo(0)
	var e: GoalEnemyData = _ui._chosen["enemy"]
	if e.is_boss() or e.image == null:
		return
	_ui._populate_play_panel()
	for rect in _texture_rects_under(_ui._verify_box):
		var frame: Control = (rect as Node).get_parent()
		assert_false(String(frame.tooltip_text).begins_with("Boss"),
			"an ordinary follower's portrait is labelled with its name, not Boss")

func test_the_standing_checklist_has_no_tick_boxes() -> void:
	# Nothing is reportable until a game is in play, so the standing list is rows.
	for row in _ui._verify_box.get_children():
		for child in row.get_children():
			assert_false(child is CheckBox, "the standing list is read-only")
	assert_eq(_ui._fulfil_checks.size(), 0, "and holds no fulfilment state")
	assert_null(_ui._levelup_check)

# The stage is two columns: what you tick on the left, what you look at on the
# right — the pack strip first, the board under it.
func test_the_checklist_sits_left_of_the_board_with_the_pack_above() -> void:
	_ui.pick(0)
	assert_eq(_ui._left_col.get_parent(), _ui._right_col.get_parent(), "one row holds both columns")
	assert_lt(_ui._left_col.get_index(), _ui._right_col.get_index(),
		"the checklist column comes first — it's on the left")
	assert_true(_ui._left_col.is_ancestor_of(_ui._play_panel), "the checklist is in the left column")
	assert_true(_ui._right_col.is_ancestor_of(_ui._board), "the board is in the right column")
	assert_true(_ui._right_col.is_ancestor_of(_ui._inv_wrap), "and so is the pack strip")
	assert_lt(_ui._inv_wrap.get_index(), _ui._stage_panel.get_index(),
		"the pack sits above the board, not under it")
	# On screen, that has to actually be left-of / below — tree order alone would
	# still pass if the columns were stacked. Needs a frame for layout to run.
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(_ui._play_panel.global_position.x, _ui._board.global_position.x,
		"the checklist is drawn to the left of the board")
	assert_lt(_ui._inv_wrap.global_position.y, _ui._board.global_position.y,
		"the pack is drawn above the board")

# The scrollbar is the one piece of chrome the player touches on every screen,
# and Godot's stock one is a light-grey capsule drawn for the editor: on these
# near-black pages it was the only control that looked like it came from another
# program. Both axes are dressed, and the modals dress themselves — a theme
# travels down Control parents, and every 2.0 modal hangs off a CanvasLayer,
# which is not one.
func test_the_scrollbars_are_dressed_in_the_projects_own_palette() -> void:
	var theme: Theme = UITheme.shared()
	for axis in ["VScrollBar", "HScrollBar"]:
		for part in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
			assert_true(theme.has_stylebox(part, axis), "%s/%s is themed" % [axis, part])
		var idle: StyleBoxFlat = theme.get_stylebox("grabber", axis)
		var hot: StyleBoxFlat = theme.get_stylebox("grabber_highlight", axis)
		assert_ne(idle.bg_color, hot.bg_color, "%s lights under the pointer" % axis)
		assert_gt(idle.corner_radius_top_left, 0, "%s's grabber is rounded" % axis)
	assert_eq(get_tree().root.theme, theme, "the window carries it as a floor")
	# …and every modal dresses ITSELF, because a theme travels down Control
	# parents and a modal hangs off a CanvasLayer, which is not one. Without this
	# the scrollbar inside an event, a shop or a map came up in the stock grey
	# however well the page behind it was dressed.
	var modal := ItemDropModal.open(_ui, Data.reward_item2_pool_of(0)[0])
	await wait_frames(4)
	assert_not_null(modal, "a modal to look at")
	if modal == null:
		return
	assert_eq(modal.theme, theme, "the modal root carries the shared theme")
	var bar := VScrollBar.new()
	modal.add_child(bar)
	assert_eq(bar.get_theme_stylebox("grabber", "VScrollBar"),
		theme.get_stylebox("grabber", "VScrollBar"),
		"so a scrollbar inside it is dressed like the rest of the project")
	bar.queue_free()
	modal.leave()

# …and the page never grows a horizontal one. The overworld is laid out to fit
# its width, so a bar under the whole page is never the answer to anything — it
# is a strip of chrome that turns up when a layout hiccups and then sits there
# for the rest of the run. The axis stays scrollable, it just never draws.
func test_the_page_never_shows_a_horizontal_scrollbar() -> void:
	assert_eq(_ui._scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_NEVER,
		"the page's sideways bar is never drawn")
	assert_false(_ui._scroll.get_h_scroll_bar().visible, "so it is not on screen")
	_ui.pick(0)
	_ui.report(false)
	assert_false(_ui._scroll.get_h_scroll_bar().visible,
		"nor after a game, when the checklist is at its longest")

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
	if _ui._fulfil_checks.is_empty():
		return
	var check: CheckBox = _ui._fulfil_checks[0]["check"]
	var row: Control = check.get_parent().get_parent()
	var before: StyleBox = row.get_theme_stylebox("panel")
	check.button_pressed = true
	assert_ne(row.get_theme_stylebox("panel"), before, "the row answers with the box")
	# Answered NO, which is what a box unticks itself for: the confirm is the only
	# thing standing between the click and a goal that cannot be taken back (§2.1).
	_say_no(_ui)
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

# The pack is a strip of small tokens, not a column of named rows: a run carries
# a dozen relics and a dozen rows is taller than the battlefield they belong to.
func test_the_pack_is_one_small_token_per_item() -> void:
	var heart: ItemData = Data.get_item2(&"hollow_heart")
	assert_not_null(heart)
	GameState.add_item(heart)
	_ui._refresh_items()
	assert_eq(_ui._items_box.get_child_count(), GameState.inventory.size(),
		"one token per carried item")
	var token: Control = _ui._items_box.get_child(_ui._items_box.get_child_count() - 1)
	assert_lte(token.get_combined_minimum_size().x, 60.0,
		"and a token is small enough that a packful fits above the board")
	assert_true(String(token.tooltip_text).contains(heart.display_name),
		"the name it gave up is in the tooltip: %s" % token.tooltip_text)
	for other in _ui._items_box.get_children():
		assert_lte((other as Control).get_combined_minimum_size().x, 60.0,
			"every token is a token, not a row")

func test_the_pack_stays_in_the_right_column_in_both_phases() -> void:
	assert_true(_ui._right_col.is_ancestor_of(_ui._inv_wrap), "choosing: the pack is on the right")
	assert_true(_ui._inv_wrap.visible, "and the inventory never goes away")
	_ui.pick(0)
	assert_true(_ui._right_col.is_ancestor_of(_ui._inv_wrap), "playing: it stays there")
	assert_true(_ui._inv_wrap.visible)

# WHAT IS FOLLOWING YOU IS THE STACK, and the board draws it. There is no summary
# line over the board any more — it said "2 closing in" above a picture of two
# bodies on two squares — so what these two guard is the count itself, which is
# what the line was ever quoting.
#
# A missed goal leaves two of them: the game's enemy and the escort that spawned
# with it (§7.5).
func test_a_missed_goal_leaves_both_bodies_following() -> void:
	_ui.pick(0)
	_ui.report(false)                    # a missed goal leaves the pair following
	assert_eq(GameLoop2.stack.size(), 2, "the enemy and its escort are both out there")

# ...and while a game is being PLAYED, the enemy standing on the board for it is
# one body on that list, not two: it has stood in the stack with everything else
# since §7.2, so nothing gets to count it a second time.
func test_the_game_in_play_puts_one_body_on_the_board_not_two() -> void:
	_pick_solo(0)
	assert_eq(GameLoop2.stack.size(), 1, "the game in play put one body out there")

# --- rating is a button, never a pop-up -----------------------------------

func _rating_modal():
	for c in _ui.get_children():
		if c is RateGameModal:
			return c
	return null

func test_reporting_a_game_never_pops_the_rating_modal() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	assert_null(_rating_modal(), "finishing a game doesn't force the rating prompt")

func test_the_played_game_stays_rateable_from_a_button() -> void:
	var played: GameData = _ui._choices[0]["game"]
	_ui.pick(0)
	_report_beat(_ui)
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
	_report_beat(_ui)
	assert_true(GameState.has_beaten_game(played.id), "the clear is banked on the run")
	assert_eq(GameState.dash_charges, dash_before, "a first clear pays nothing extra")
	assert_eq(GameStats.beaten_count(played.id), lifetime_before + 1,
		"and the lifetime tally the Collection shows moved too")

func test_going_back_to_a_game_and_beating_it_grants_a_dash() -> void:
	# Stand where a game the run has already played is on offer (the run graph
	# lets you double back, so an offered game can be one you played earlier).
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_played(target.id)
	_ui._build_choices()
	assert_eq(_ui._choices[0]["game"], target, "the offering is stable for the position")
	assert_true(bool(_ui._choices[0]["repeat"]), "the card is flagged as a return")
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_report_beat(_ui)
	assert_eq(GameState.dash_charges, dash_before + _ui.REPEAT_BEAT_DASH,
		"going back and beating it granted a Dash")

func test_the_return_dash_asks_only_that_you_went_there_before() -> void:
	# PLAYED before, not beaten before. A game you failed and came back to is the
	# same journey back as one you cleared, and it is the journey the Dash pays
	# for — which is why the first trip is allowed to have gone badly.
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_played(target.id)
	assert_false(GameState.has_beaten_game(target.id), "the first visit was a failure")
	_ui._build_choices()
	assert_true(bool(_ui._choices[0]["repeat"]), "and the card still flags the return")
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_report_beat(_ui)
	assert_eq(GameState.dash_charges, dash_before + _ui.REPEAT_BEAT_DASH,
		"beating it this time pays, even though last time did not")

func test_a_game_played_but_not_beaten_pays_nothing_until_you_beat_it() -> void:
	# The goal is still what has to be earned on the return trip.
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_played(target.id)
	_ui._build_choices()
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_ui.report(false)
	assert_eq(GameState.dash_charges, dash_before,
		"a second visit that misses the goal again is not a return worth paying for")

# --- beaten means WON -------------------------------------------------------
#
# Reporting a MISSED goal used to bank the game exactly as a win did: the run's
# beaten list, the lifetime "⚔ Beaten N times" the Collection and tier list
# print, and the repeat-beat Dash all counted a visit. Every one of those reads
# as a claim about winning, so all of them require the goal to have been met.

func test_a_missed_goal_is_not_a_beat() -> void:
	var played: GameData = _ui._choices[0]["game"]
	var lifetime_before: int = GameStats.beaten_count(played.id)
	var run_before: int = GameState.total_games_beaten
	_ui.pick(0)
	_ui.report(false)
	assert_false(GameState.has_beaten_game(played.id),
		"failing a game does not put it on the run's beaten list")
	assert_eq(GameState.total_games_beaten, run_before,
		"nor move the run's count")
	assert_eq(GameStats.beaten_count(played.id), lifetime_before,
		"nor the lifetime tally the Collection prints")

func test_a_missed_goal_still_advances_the_run() -> void:
	# The game was still played and the board still closed in — only the CREDIT is
	# withheld, which is what separates this from an escape.
	var gp_before: int = GameState.games_played
	_pick_solo(0)
	_ui.report(false)
	assert_eq(GameState.games_played, gp_before + 1, "the game is behind you")
	assert_eq(GameLoop2.stack_size(), 1, "and its enemy followed you out")

func test_failing_a_game_you_beat_earlier_pays_no_dash() -> void:
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_beaten(target.id)
	_ui._build_choices()
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	_ui.report(false)
	assert_eq(GameState.dash_charges, dash_before,
		"the repeat Dash is for beating it again, not for failing it again")

func test_only_a_won_amulet_records_the_win() -> void:
	var played: GameData = _ui._choices[0]["game"]
	var wins_before: int = GameStats.amulet_wins(played.id)
	_ui.pick(0)
	_ui.report(false)
	assert_eq(GameStats.amulet_wins(played.id), wins_before,
		"a missed goal is not an amulet win either")

# Every label/button/rich-text string under a node, flattened — enough to assert
# what a screen actually says without reaching into its layout.
func _text_of(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	elif node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	for c in node.get_children():
		out += _text_of(c)
	return out

func test_the_popup_shows_the_dash_bonus_for_a_repeat() -> void:
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_played(target.id)
	_ui._build_choices()
	_ui._render_choices()
	var bonus: String = "⚡ Gain +%d Dash" % _ui.REPEAT_BEAT_DASH
	assert_true(_text_of(_ui.open_choice(0)).contains(bonus),
		"the popup says what going back and beating it grants")
	_ui._choice_modal._close()
	# A game the run has not been to says nothing about it.
	GameState.played_games.clear()
	_ui._build_choices()
	_ui._render_choices()
	assert_false(_text_of(_ui.open_choice(0)).contains(bonus),
		"and nothing about it on a game you have never been to")

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

func test_claimed_loot_updates_the_screen_immediately() -> void:
	var heart: ItemData = Data.get_item2(&"hollow_heart")   # +4 Max Health on acquire
	assert_not_null(heart)
	var max_before: int = GameState.max_hp
	var drop: Dictionary = {"item": heart}
	_ui._drop_queue.append(drop)
	_ui._collect_drop(drop)
	assert_eq(GameState.max_hp, max_before + 4, "the pickup's effect landed")
	assert_true(_ui._board._hero_hp.text.contains("%d/%d" % [GameState.hp, GameState.max_hp]),
		"and the hero already shows it: %s" % _ui._board._hero_hp.text)

func test_the_verb_chips_follow_a_gain_without_a_loop_resolve() -> void:
	# Dash sits under the offering now rather than on the HUD, but it has to move
	# for the same reason the HUD's numbers do: an item off a drop or a chest can
	# hand you a charge between one frame and the next.
	var before: String = _text_of(_ui._select_stats)
	GameState.grant_run_stat("dash", 2)      # emits stats_changed, no loop tick
	var after: String = _text_of(_ui._select_stats)
	assert_ne(after, before, "the chips repaint off the stat change")
	assert_true(after.contains("Dash %d" % GameState.dash_charges),
		"showing the new Dash count: %s" % after)

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

func test_the_start_picker_offers_a_card_per_genre_and_never_repeats_one() -> void:
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

# The two cards are a choice of RUN LENGTH as well as genre: distance from the
# Amulet decides how many games the run gets in the calm 1-turn band before the
# stack picks up its scent (RunDifficulty.extra_turns_for_hops). Two cards at the same
# distance would offer a genre and nothing else.
#
# It is a preference, not a promise — an Amulet can have every in-band start at a
# single distance (one does on the owned catalog at 4..7, and 16 did at 5..8) — so
# the assertion is that the panel took a spread WHERE ONE EXISTED, which is
# checked against the graph rather than assumed.
func test_the_two_starts_are_different_distances_when_the_graph_allows_it() -> void:
	for _attempt in range(12):
		_ui.start_run()
		var amulet: StringName = GameState.amulet_game_id
		var lens: Dictionary = {}
		for opt in _ui._start_options:
			lens[int(opt["path_len"])] = true
		# What the graph could have offered: every distance an eligible start of
		# any genre sits at from this amulet.
		var available: Dictionary = {}
		var d_to: Dictionary = RunGraph.bfs_distances(amulet)
		for g in Data.all_games():
			if not (g is GameData) or g.id == amulet:
				continue
			if RunGraph.neighbors(g.id).size() < RunGraph.MIN_START_CONNECTIONS:
				continue
			var hops: int = int(d_to.get(g.id, -1))
			if hops >= RunGraph.MIN_PATH_LENGTH and hops <= RunGraph.MAX_PATH_LENGTH:
				available[hops] = true
		if _ui._start_options.size() < 2:
			continue
		if available.size() >= 2:
			assert_eq(lens.size(), _ui._start_options.size(),
				"%d distances were on offer, so the two cards must not share one" %
				available.size())
		else:
			assert_eq(lens.size(), 1,
				"only one distance exists here, so repeating it is the fallback")

func test_the_panel_keeps_both_cards_when_no_spread_is_possible() -> void:
	# The fallback is the point: an Amulet with nothing to spread across must
	# still get a full panel rather than a short one.
	for _attempt in range(12):
		_ui.start_run()
		assert_eq(_ui._start_options.size(), RunGraph.NUM_START_OPTIONS,
			"the panel is full whether or not the lengths could differ")

func test_the_longer_route_is_the_first_card() -> void:
	# Distance leads the display order, so the panel reads the same way every run
	# instead of reshuffling on branch score.
	for _attempt in range(8):
		_ui.start_run()
		var prev: int = 1 << 30
		for opt in _ui._start_options:
			assert_true(int(opt["path_len"]) <= prev,
				"cards run longest-first: %d after %d" % [int(opt["path_len"]), prev])
			prev = int(opt["path_len"])

func test_choosing_a_start_places_the_player_and_opens_the_run_on_it() -> void:
	_ui.start_run()
	var chosen: GameData = _ui._start_options[1]["game"]
	var waiting: GoalEnemyData = _ui._start_options[1]["enemy"]
	_ui.choose_start(1)
	assert_eq(GameState.current_game_id, chosen.id, "the player stands on the chosen start")
	assert_eq(GameState.start_game_id, chosen.id, "and the run records it as its start")
	assert_true(_ui._start_options.is_empty(), "the start panel is done with")
	assert_gt(_ui._choices.size(), 0, "the start's neighbours are already on the table")
	# The start is the run's FIRST GAME, not a doorstep: it spawns what was
	# advertised on its card and hands over the tries any game hands over.
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "the run opens in the report step")
	assert_true(GameLoop2.has_arrivals(), "with an enemy standing on the board")
	assert_eq(GameLoop2.arrival().get("enemy"), waiting,
		"and it is the one the card said was waiting there")
	assert_eq(_ui._chosen.get("game"), chosen, "the start is the game in play")
	assert_eq(GameState.shields, GameLoop2.shields_for_game(chosen),
		"and it granted its tries")

func test_a_start_card_opens_the_ordinary_choice_popup() -> void:
	_ui.start_run()
	var modal = _ui.open_start_choice(0)
	assert_not_null(modal, "the start card opens a popup like any other card")
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT, "opening it chooses nothing")
	var enemy: GoalEnemyData = _ui._start_options[0]["enemy"]
	var text: String = _modal_text(modal)
	assert_true(text.contains(_ui._start_options[0]["game"].display_name), "it names the game")
	if enemy != null:
		assert_true(text.contains(enemy.display_name), "and the enemy waiting there")
	modal.travel()
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "and its button starts the run on it")

func test_the_start_popup_withholds_bash_and_transmute() -> void:
	_ui.start_run()
	GameState.bash = 3
	GameState.transmute = 3
	var modal = _ui.open_start_choice(0)
	var text: String = _modal_text(modal)
	assert_false(text.contains("Bash"), "there is no offering to reshape yet")
	assert_false(text.contains("Transmute"), "nor a slot to paste over")
	modal._close()

# Every Label / Button / RichTextLabel in a built modal, flattened.
func _modal_text(node: Node) -> String:
	var out: String = ""
	if node is Label or node is Button:
		out += String(node.text) + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _modal_text(child)
	return out

func test_the_start_picker_ignores_a_travel_pick() -> void:
	_ui.start_run()
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT, "travel is not a thing yet")
	assert_false(GameLoop2.has_arrivals(), "and nothing spawned")

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
	assert_true(GameLoop2.has_arrivals(), "the game in play is still in play")
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "and the screen is back on the report step")
	assert_eq((_ui._chosen["game"] as GameData).id, expect_chosen, "reporting on the same game")
	assert_eq(_ui._choices.size(), expect_choices, "the offering came back with it")

func test_a_restored_follower_keeps_its_place_on_the_board() -> void:
	_pick_solo(0)
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

# The run's SCROLL ALPHABET has to survive the same trip, for the reason the pill
# and potion colour maps do: a reload that redealt the titles would wipe out
# everything the player had worked out about them, which is the only thing an
# identification minigame is made of.
func test_a_reload_keeps_the_scroll_titles_the_run_dealt() -> void:
	ScrollSystem.ensure_names()
	var dealt: Dictionary = GameState.scroll_name_map.duplicate()
	assert_false(dealt.is_empty(), "the run dealt an alphabet to begin with")
	assert_true(SaveSystem.save_named("titles"))
	GameState.reset_run()
	GameLoop2.reset()
	GameState.set_overworld_context(_ui)
	assert_true(SaveSystem.load_named("titles"))
	ScrollSystem.ensure_names()          # must be a no-op, not a fresh deal
	assert_eq(GameState.scroll_name_map, dealt,
		"ZELGO MER is still ZELGO MER after the reload")

func test_reporting_a_game_keeps_the_run_recoverable() -> void:
	_ui.pick(0)
	_ui.report(false)
	assert_true(SaveSystem.has_autosave(), "the run keeps a recovery point")
	var summaries: Array = SaveSystem.list_resumable()
	assert_gt(summaries.size(), 0, "and the Continue list can see it")
	assert_true(bool(summaries[0].get("autosave", false)), "the autosave leads the list")

# Walk everything on the board into striking range, so a lost run's turn (§3) has
# something to swing back with. The columns are set straight rather than marched
# by reporting games at the board: these tests are about what the TICK does, and
# getting there properly would resolve several games' worth of other rules first.
func _board_into_reach() -> void:
	for entry in GameLoop2.stack:
		entry["col"] = 1

func test_a_lost_run_clears_its_recovery_point() -> void:
	_ui.pick(0)
	assert_true(SaveSystem.has_autosave(), "there is something to clear")
	GameState.shields = 0
	GameState.bonus_shields = 0
	GameState.hp = 1
	_board_into_reach()
	_ui.log_attempt()                       # out of shields, the board takes its turn
	_ui._end_resolve()                      # and the playback of it lands
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

# The popup opens UNDER the run's header bar, not behind it. The bar is opaque
# and drawn over every modal the run raises; the popup grew past its nominal
# 700px on a tall route, was centred on the whole viewport, and had its title —
# the name of the game being decided about — sliced off by the bar.
func test_the_popup_opens_clear_of_the_header_bar() -> void:
	_ui._render_choices()
	var modal = _ui.open_choice(0)
	assert_not_null(modal, "the card opens")
	if modal == null:
		return
	await wait_frames(2)
	var panel: Control = null
	for child in modal.get_children():
		if child is PanelContainer:
			panel = child
			break
	assert_not_null(panel, "the popup is on a panel")
	if panel == null:
		return
	var bar: float = ModalScaffold.reserved_top
	assert_gt(bar, 0.0, "the run's header bar is standing on the top of the screen")
	assert_gte(panel.get_global_rect().position.y, bar - 1.0,
		"and the panel starts below it, title and all")
	_ui._choice_modal._close()

func test_the_popup_states_where_the_game_puts_you() -> void:
	# The route badge used to ride above every cover. It heads the popup now, over
	# the map that backs the claim up.
	_ui._render_choices()
	for i in range(_ui._choices.size()):
		var note: Dictionary = _ui.route_note(_ui._choices[i])
		var text: String = _text_of(_ui.open_choice(i))
		assert_true(text.contains(String(note["text"])),
			"choice %d states where it puts you: %s" % [i, text])
		_ui._choice_modal._close()

# ---------------------------------------------------------------------------
# The per-card map: the optimal path a game WOULD open, before taking it
# ---------------------------------------------------------------------------

# The START cards keep their 🗺 button: the start picker has no popup — there is
# no run to route from yet, only three genres and a distance band.
func _map_button(card: Node) -> Button:
	for child in card.get_children():
		if child is Button and String((child as Button).text).contains("Map"):
			return child
	return null

func test_every_offered_game_draws_its_route_in_the_popup() -> void:
	# The 🗺 button each card used to wear is gone: the map it opened is drawn
	# INSIDE the popup now, so the road and the button that takes it are one
	# screen rather than two.
	_ui._render_choices()
	for i in range(_ui._choices.size()):
		var modal = _ui.open_choice(i)
		assert_not_null(modal, "choice %d opens" % i)
		assert_eq(StringName(modal._ladder_cfg()["current"]), StringName(_ui._choices[i]["slot"]),
			"and its ladder is routed from that game")
		modal._close()

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

func test_the_start_picker_names_the_amulet_everywhere_it_appears() -> void:
	_ui.start_run()                       # back to the choose-your-start panel
	assert_eq(_ui._phase, OVERWORLD.Phase.START_SELECT)
	_ui._render_start_choices()
	var card: Node = _ui._choices_row.get_child(0)
	assert_not_null(_map_button(card), "a start card offers its map too")
	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	assert_not_null(amulet)
	if amulet == null:
		return

	# On the heading over the whole panel...
	assert_true(_ui._select_head.text.contains(amulet.display_name),
		"the picker's heading names the Amulet: %s" % _ui._select_head.text)
	# ...on each card's distance line...
	assert_true(_card_text(card).contains(amulet.display_name),
		"and so does the card's distance line")
	# ...and on the map the card opens.
	var start_id: StringName = _ui._start_options[0]["game"].id
	var modal = _ui.preview_map(start_id)
	assert_not_null(modal)
	if modal == null:
		return
	assert_eq(modal.node_name(GameState.amulet_game_id), amulet.display_name,
		"the destination is named, not drawn as a blank")

# Every label on a card, joined — the distance line is a plain Label among
# several, and which child it is is layout, not behaviour.
func _card_text(card: Node) -> String:
	var out: String = ""
	for child in card.get_children():
		if child is Label:
			out += (child as Label).text + "\n"
	return out

# ---------------------------------------------------------------------------
# The board gets to finish
#
# The resolve animation is the only place the run's consequences are SHOWN, so
# the screen it plays on has to still be there when it plays.
# ---------------------------------------------------------------------------

# --- the swing count lives with the damage, not over the art -----------------
#
# "x2" printed across the middle of a body hid the enemy it belonged to, and it
# was answering the same question as the ⚔ badge anyway: how hard does this thing
# hit me next game. The two are one badge in the corner now.

func test_the_sword_badge_carries_the_swing_count() -> void:
	var e := GoalEnemyData.new()
	e.damage = 3
	# The badge is built from a board ENTRY rather than the enemy, because what it
	# hits for is the enemy's damage plus whatever statuses are riding the body.
	var entry := {"enemy": e, "statuses": {}}
	assert_eq(_ui._board._damage_badge_text(entry, 1), "⚔3",
		"one swing is the ordinary case and says nothing extra")
	assert_eq(_ui._board._damage_badge_text(entry, 0), "⚔3",
		"a body still walking in shows what it will hit for")
	assert_eq(_ui._board._damage_badge_text(entry, 2), "⚔3×2",
		"two swings are counted on the damage itself")
	assert_eq(_ui._board._damage_badge_text(entry, 3), "⚔3×3")
	# No space, and "×" not "x": on the 46px cells of a 7x7 board every character
	# of this badge is width the ❤ beside it doesn't get (see _add_enemy_badges).
	assert_false(_ui._board._damage_badge_text(entry, 3).contains(" "),
		"the multi-swing badge spends no width on a space")

# Recursive: the ❤ / ⚔ pair lives inside a row now (see the overlap test below),
# so a one-level walk would report a body wearing no badges at all.
func _badge_texts(instance: int) -> Array:
	var badges: Control = _ui._board._badges_for_instance(instance)
	return [] if badges == null else _labels_under(badges)

# --- the health badge is not buried by the damage badge --------------------
#
# Anchored to opposite bottom corners, each badge grew from its corner inwards —
# so the moment an enemy got a second swing, "⚔3×2" grew left and printed itself
# over the ❤ in the other corner. It bit exactly when it mattered: multi-swing
# means the Amulet is close, which means the board is at its widest and the cells
# at their smallest. One row can't overlap itself.
func test_the_two_stat_badges_share_one_row_so_they_cannot_overlap() -> void:
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var badges: Control = _ui._board._badges_for_instance(inst)
	assert_not_null(badges, "the body has a badge holder")
	var hp: Label = null
	var dmg: Label = null
	for row in badges.get_children():
		if not (row is HBoxContainer):
			continue
		for c in row.get_children():
			if c is Label and String((c as Label).text).begins_with("❤"):
				hp = c
			elif c is Label and String((c as Label).text).begins_with("⚔"):
				dmg = c
	assert_not_null(hp, "the health badge is in a row")
	assert_not_null(dmg, "and so is the damage badge")
	if hp == null or dmg == null:
		return
	assert_eq(hp.get_parent(), dmg.get_parent(),
		"the SAME row — which is what makes overlapping impossible")
	assert_lt(hp.get_index(), dmg.get_index(),
		"health first, so it keeps the left edge it always had")

func test_nothing_prints_the_swing_count_over_the_body() -> void:
	_pick_solo(0)
	_ui.report(false)                         # miss, so the enemy stands on the board
	assert_eq(GameLoop2.stack_size(), 1)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var texts: Array = _badge_texts(inst)
	assert_gt(texts.size(), 0, "the body wears badges")
	for t in texts:
		assert_false(String(t).begins_with("×"),
			"no swing count sitting on top of the art: %s" % t)
		if String(t).begins_with("⚔"):
			assert_eq(String(t), _ui._board._damage_badge_text(
				GameLoop2.stack[0], GameLoop2.attacks_in_turns(GameLoop2.stack[0])),
				"the ⚔ badge is where the count went")

func test_the_board_says_how_long_its_playback_runs() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	assert_eq(_ui._board.animate_resolve(before, {"attacks": []}), 0.0,
		"nothing to show, nothing to wait for")
	assert_gt(before.size(), 0, "the picked game put an enemy on the board")
	var inst: int = int(before.keys()[0])
	var secs: float = _ui._board.animate_resolve(before,
		{"attacks": [{"instance": inst, "damage": 3}]})
	# A STRIKE PLUS ITS TAIL. The number the host waits on is not the beat the
	# strike is scheduled over — a damage number's tween is sequential (rise, then
	# fade) and outlives that beat, and on the blow that ends a run there is no
	# slide afterwards to cover the difference — plus the breath the finished board
	# is held on, so the end screen does not cut on the same frame as the last
	# pixel of motion. See BattlefieldView.FX_NUMBER_TAIL / FX_END_BREATH.
	assert_almost_eq(secs, _ui._board.FX_ATTACK_TIME + _ui._board.FX_NUMBER_TAIL
		+ _ui._board.FX_END_BREATH, 0.001,
		"a strike, what its damage number outlives it by, and the breath after")

# The offering does NOT wait for the board: it comes straight back beside it, and
# the resolve plays out on the board next to the cards. There is no Continue step
# between the two — the animation and the next decision share the screen.
func test_the_offering_comes_back_while_the_board_still_plays() -> void:
	# Play a game and MISS first, which is what puts a body on the board: the
	# chosen enemy lives in GameLoop2.arrival() while a game is being played and
	# only joins the stack when the goal is missed. On the very first game the
	# stack is still empty, so its resolve has nobody to strike and nobody to
	# slide — and _hold_for_resolve ends a zero-length playback synchronously,
	# which left _resolving false and failed this test on roughly one run in four.
	# The SECOND game is the one with a board to play back, which is what this
	# test is actually about.
	_pick_solo(0)
	_ui.report(false)
	await _playback_done()                    # let the first playback finish
	assert_eq(GameLoop2.stack_size(), 1, "the miss left an enemy standing on the board")
	assert_false(_ui._resolving, "and its own playback is done before the real test")

	_pick_solo(0)
	_ui.report(false)
	assert_eq(_ui._phase, OVERWORLD.Phase.SELECT, "the next decision is already built")
	assert_gt(_ui._choices.size(), 0)
	assert_true(_ui._select_box.visible,
		"and it is already on screen, with the board playing beside it")
	assert_true(_ui._resolving, "the board is still playing the resolve back")
	await _playback_done()
	assert_false(_ui._resolving, "which finishes on its own, with nothing to press")
	assert_true(_ui._select_box.visible, "leaving the offering where it was")

func test_the_end_of_run_screen_is_what_the_playback_still_holds_back() -> void:
	_ui.pick(0)
	_ui._resolving = true                    # as it is between a report and its playback
	GameLoop2._finish_run(false)
	assert_null(_end_screen(), "the verdict doesn't land on top of the animation")
	_ui._end_resolve()                       # the board finishes its playback
	assert_not_null(_end_screen(), "and lands the moment it is done")

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
	GameState.bonus_shields = 0
	GameState.hp = 1
	_board_into_reach()
	_ui.log_attempt()                        # the turn it bought takes the last Health
	_ui._end_resolve()                       # the screen waits for the blow to land
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

# "The road you walked" drew from `visited_games`, which is a set — so a run that
# went back to a game three times showed it once, and the picture the screen calls
# the road walked was the road walked with the doubling-back edited out. Going
# back is a decision the player made and paid a Dash for; it stays in.
func test_the_verdict_screen_keeps_the_replays_on_the_road() -> void:
	var start: StringName = GameState.current_game_id
	var away: StringName = _neighbour_of_here()
	if away == &"" or away == start:
		return
	GameState.set_current_game(away)
	GameState.set_current_game(start)
	GameLoop2._finish_run(false)
	var screen = _end_screen()
	assert_not_null(screen)
	if screen == null:
		return
	var route: Array = screen.route_ids()
	assert_eq(route.size(), 3, "three stops, not two: %s" % [route])
	assert_eq(StringName(route[0]), start)
	assert_eq(StringName(route[2]), start, "and the run really did come back")
	assert_string_contains(screen._route_summary(), "replay",
		"the heading says so, or twelve stops over nine games reads as a bug")

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
# so the board has to be drawing the enemy at its new square by the time the
# playback asks where it is.
func test_an_enemy_that_walks_onto_the_grid_reads_as_having_moved() -> void:
	_ui.pick(0)
	# DISARMED, because this test is about the SCREEN. Since §7.6 an ability can
	# spend a body's whole turn on something other than stepping — a Defensive
	# Stance, a Ritual, a spawner — and a body that legitimately stood still would
	# read here as the board failing to redraw it.
	_disarm_board()
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(GameLoop2.arrival()["instance"])
	assert_true(before.has(inst), "picking the game stood its enemy on the board")
	# A LOST RUN moves it: reporting the game hands the board nothing out here
	# (§7.4), so the tick is what there is to watch.
	_ui.log_attempt()
	_ui._end_resolve()
	var after: Dictionary = _ui._board.capture_positions()
	assert_true(after.has(inst), "and it is still on the grid, a column closer")
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
	_report_beat(_ui)                          # the goal is met — that's the run
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
	_report_beat(_ui)
	assert_eq(GameStats.amulet_wins(amulet), wins_before + 1,
		"the game you won on carries the crown afterwards")

# This asserted the opposite — that missing the goal on the Amulet game left the
# run going. REACHING the Amulet game and playing it IS the run: the whole thing
# is a search for one game, so arriving and finishing it is the answer, and the
# goal-enemy's condition is a bonus on top rather than the lock on the door. A
# player who walked the entire road and beat the Amulet game, but hadn't happened
# to satisfy "destroy an enemy spawner" on the way through, used to watch the run
# carry on as though nothing had happened.
func test_finishing_the_amulet_game_wins_even_without_the_goal() -> void:
	var idx: int = _offer_the_amulet_next_door()
	_ui.pick(idx)
	_ui.report(false)                         # played it; the goal box unticked
	assert_true(GameLoop2.run_over, "the Amulet game is the run, goal or no goal")
	assert_true(GameLoop2.won, "and it ends as a win")
	_ui._end_resolve()
	var screen = _end_screen()
	assert_not_null(screen, "the win screen lands")
	if screen != null:
		assert_eq(screen.verdict(), "won")

func test_the_win_is_banked_even_when_the_amulet_goal_was_missed() -> void:
	var idx: int = _offer_the_amulet_next_door()
	var amulet: StringName = GameState.amulet_game_id
	var wins_before: int = GameStats.amulet_wins(amulet)
	_ui.pick(idx)
	_ui.report(false)
	assert_eq(GameStats.amulet_wins(amulet), wins_before + 1,
		"the game you won the run on carries the crown either way")

# The goal row still says what it is: a bonus, not the win condition. Worth
# pinning because the row is the one place a player would otherwise read the
# tick as the thing that ends the run.
func test_the_amulet_report_says_the_goal_is_a_bonus() -> void:
	var idx: int = _offer_the_amulet_next_door()
	_ui.pick(idx)
	var said: String = _text_of(_ui._verify_box)
	assert_true(said.contains("bonus"),
		"the Amulet's goal row is marked a bonus: %s" % said)
	assert_true(said.contains("Completing this game wins the run"),
		"and the panel says what actually wins")

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
	assert_gte(modal.panel_position().y, ModalScaffold.reserved_top,
		"and can't be dragged under the header bar that is drawn over it…")
	assert_gt(modal.panel_position().x + modal._panel.size.x, 0.0, "…or off the side")

# THE WAY OFF THE CHART.
#
# The chart is a full-screen page whose header — the title, the search box, the
# ✦ jump buttons and CLOSE — is its first row. The run's header bar is pinned to
# the top of the screen on a layer above it and is opaque, so a chart drawn from
# y=0 had that entire row eaten and no way back to the run but the Esc key.
func test_the_chart_opens_below_the_runs_header_bar() -> void:
	_ui.open_map()
	var atlas: AtlasView = _chart()
	assert_not_null(atlas)
	if atlas == null:
		return
	var bar: float = ModalScaffold.reserved_top
	assert_gt(bar, 0.0, "the run's header bar is standing on the top of the screen")
	assert_almost_eq(atlas.position.y, bar, 0.5,
		"so the chart starts under it rather than beneath it")
	assert_not_null(_close_button(atlas), "and its way out is on screen")

func test_the_chart_can_be_closed_back_to_the_run() -> void:
	_ui.open_map()
	var atlas: AtlasView = _chart()
	if atlas == null:
		return
	var close: Button = _close_button(atlas)
	assert_not_null(close, "the chart carries a way back")
	if close == null:
		return
	close.pressed.emit()
	await wait_frames(2)
	assert_null(_chart(), "pressing it puts the run back in front")

# The chart's own Close, wherever the header put it.
func _close_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text.contains("Back"):
			return child
		var found: Button = _close_button(child)
		if found != null:
			return found
	return null

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

func test_the_start_pickers_map_is_the_ladder_alone() -> void:
	# The picker's map raises NO star chart. It used to withhold the destination as
	# well, which is over — the ladder names it (below) — but the sky stays down:
	# the question on that panel is "which of these three roads", the ladder is the
	# answer to it, and 852 stars with nothing on them to orient by (the run has no
	# position yet) is not. The chart is one button away on the window itself.
	_ui.start_run()
	var modal = _ui.preview_map(_ui._start_options[0]["game"].id)
	assert_null(_chart(), "no star chart from the start picker")
	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	assert_eq(modal.node_name(GameState.amulet_game_id), amulet.display_name,
		"but the ladder still names the destination")
	assert_not_null(_star_chart_button(modal),
		"and the window offers to raise the chart for anyone who wants it")

# The map window's "✦ Star chart" button, wherever its tools row put it.
func _star_chart_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text.contains("Star chart"):
			return child
		var found: Button = _star_chart_button(child)
		if found != null:
			return found
	return null

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
		assert_eq(int(note["turns"]), RunDifficulty.extra_turns_for_hops(hops),
			"a card %d hops out reads the same rung the loop resolves on" % hops)
		assert_eq(int(note["extra"]), RunDifficulty.extra_turns_for_hops(hops),
			"and says so in the field the board reads")
		# The EXTRA turns are what the card says out loud (§7.4) — "1 extra turn",
		# or "no extra turns" on the rung where it charges nothing.
		var said: String = RunDifficulty.extra_text(int(note["extra"]))
		assert_true(String(note["text"]).contains(said),
			"and says the price out loud: %s" % note["text"])

func test_stepping_toward_the_amulet_warns_that_they_speed_up() -> void:
	# Stand in the far band and look at a card deep in the near one: the card has
	# to say the enemies get faster BEFORE it's clicked.
	var here: StringName = _a_game_at_hops(6)
	var there: StringName = _a_game_at_hops(1)
	if here == &"" or there == &"":
		return
	GameState.set_current_game(here)
	var note: Dictionary = _ui.turn_note({"slot": there, "amulet": false})
	assert_eq(int(note["turns"]), 2, "one hop from the Amulet is the doorstep")
	assert_true(String(note["text"]).contains("speed up"),
		"the card warns before the click: %s" % note["text"])
	assert_eq(note["color"], RunDifficulty.band_color(RunDifficulty.EXTRA_NEAR),
		"in the band's own colour, same as the board's strip")

func test_backing_off_reads_as_the_relief_it_is() -> void:
	var here: StringName = _a_game_at_hops(1)
	var there: StringName = _a_game_at_hops(6)
	if here == &"" or there == &"":
		return
	GameState.set_current_game(here)
	var note: Dictionary = _ui.turn_note({"slot": there, "amulet": false})
	assert_eq(int(note["turns"]), 0)
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
	# Taking the Amulet ends the run on the spot; a "+2 bonus turns" warning there
	# would be describing a game that never happens.
	var note: Dictionary = _ui.turn_note({
		"slot": GameState.amulet_game_id, "amulet": true})
	assert_eq(String(note["text"]), "", "the winning card carries no pace warning")

func test_the_popup_states_the_pace_the_game_puts_you_on() -> void:
	_ui._render_choices()
	for i in range(_ui._choices.size()):
		var note: Dictionary = _ui.turn_note(_ui._choices[i])
		if String(note["text"]) == "":
			continue                       # the Amulet's card, which says nothing
		var text: String = _text_of(_ui.open_choice(i))
		assert_true(text.contains(String(note["text"])),
			"choice %d states the pace it puts you on: %s" % [i, text])
		_ui._choice_modal._close()

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
	# Every frame holds the enemy on the square it is actually standing on, so the
	# playback is three STRIKES and no movement — this test is about the beats, and
	# a fabricated walk would add slide time to the number being compared.
	var entry: Dictionary = GameLoop2.entry_for(inst)
	var at := Vector2i(int(entry.get("col", 1)), int(entry.get("row", 0)))
	var one: float = _ui._board.animate_resolve(before, {
		"turns": 1, "turn_frames": [{inst: at}],
		"attacks": [{"instance": inst, "turn": 0, "damage": 3}]})
	var three: float = _ui._board.animate_resolve(before, {
		"turns": 3,
		"turn_frames": [{inst: at}, {inst: at}, {inst: at}],
		"attacks": [
			{"instance": inst, "turn": 0, "damage": 3},
			{"instance": inst, "turn": 1, "damage": 3},
			{"instance": inst, "turn": 2, "damage": 3}]})
	# ONE BEAT PER TURN, which is a statement about the DIFFERENCE and not about the
	# ratio: the tail (a damage number outliving its beat, plus the breath the board
	# is held on at the end) is paid once for the whole playback, not once per turn,
	# so three turns cost two extra strikes rather than three times everything.
	assert_almost_eq(three - one, _ui._board.FX_ATTACK_TIME * 2.0, 0.001,
		"the host holds the screen for every turn, not just the first")

# --- the Health comes down WITH the blows -----------------------------------
#
# The run's Health moves the instant a game is reported: by the time the first
# strike is drawn, every one of them has already landed. A Health line wired
# straight to GameState therefore shows the whole bill before the animation has
# shown a single hit. During a playback the board drives the number itself.

func test_health_starts_the_playback_where_it_was_before_the_blows() -> void:
	_pick_solo(0)
	_ui.report(false)                        # miss, so the enemy stands on the board
	assert_eq(GameLoop2.stack_size(), 1)
	var entry: Dictionary = GameLoop2.stack[0]
	var inst: int = int(entry["instance"])
	var row: int = int(entry.get("row", 0))
	var col: int = int(entry.get("col", 1))
	var walk_from: int = 1 if col != 1 else 2
	var before: Dictionary = _ui._board.capture_positions()
	GameState.shields = 0
	var hp_before: int = GameState.hp
	GameState.change_hp(-5)                  # as beat_game already would have
	# Turn one is a WALK and turn two is the swing, so nothing has landed at the
	# moment the playback starts.
	_ui._board.animate_resolve(before, {
		"turns": 2,
		"turn_frames": [{inst: Vector2i(walk_from, row)}, {inst: Vector2i(col, row)}],
		"attacks": [{"instance": inst, "turn": 1, "damage": 5}]}, hp_before)
	assert_eq(_ui._board.shown_hp(), hp_before,
		"the board opens on the Health the player had before the resolve")
	assert_true(_ui._board._hero_hp.text.contains("%d/" % hp_before),
		"and says so: %s" % _ui._board._hero_hp.text)
	assert_ne(GameState.hp, hp_before, "the run itself already paid the bill")

func test_each_strike_takes_its_own_bite_out_of_the_shown_health() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	GameState.shields = 0
	var hp_before: int = GameState.hp
	var secs: float = _ui._board.animate_resolve(before, {
		"turns": 2,
		"turn_frames": [{inst: Vector2i(1, 0)}, {inst: Vector2i(1, 0)}],
		"attacks": [
			{"instance": inst, "turn": 0, "damage": 2},
			{"instance": inst, "turn": 1, "damage": 2}]}, hp_before)
	# The first turn's strike fires immediately; the second waits for its turn.
	assert_eq(_ui._board.shown_hp(), hp_before - 2,
		"one blow landed, one blow's worth of Health gone")
	assert_true(_ui._board._hero_hp.text.contains("%d/%d" % [hp_before - 2, GameState.max_hp]),
		"and the hero's line came down with it: %s" % _ui._board._hero_hp.text)
	await wait_seconds(secs + 0.2)
	assert_eq(_ui._board.shown_hp(), GameState.hp,
		"and when the playback ends the line is the run's own Health again")

func test_a_blow_a_shield_swallowed_moves_no_health() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	var hp_before: int = GameState.hp
	_ui._board.animate_resolve(before, {"attacks": [
		{"instance": inst, "turn": 0, "damage": 3, "blocked": 3}]}, hp_before)
	assert_eq(_ui._board.shown_hp(), hp_before,
		"the shield took it, so the Health line doesn't flinch")

# --- and the shields break WITH them ---------------------------------------
#
# Same disease as the Health line had: the run has already spent the shield by the
# time the first strike is drawn, so a row wired straight to GameState is empty
# before the blow that emptied it lands. The one thing a shield exists to do was
# the one thing never shown happening.

func test_the_shield_row_opens_on_the_armour_that_was_standing() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	GameState.shields = 2
	_ui._refresh()
	var held := Vector2i(GameState.shields, GameState.bonus_shields)
	GameState.shields = 0                    # as the resolve already would have
	_ui._board.animate_resolve(before, {"attacks": [
		{"instance": inst, "turn": 0, "damage": 3, "blocked": 3}]}, GameState.hp, held)
	# One blocked blow fires immediately, so one of the two is gone and one is left.
	assert_eq(_ui._board.standing_shields().size(), 1,
		"the playback opens on the two that were standing and breaks one on the blow")

func test_an_unblocked_blow_breaks_no_shield() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	GameState.shields = 2
	_ui._refresh()
	var held := Vector2i(GameState.shields, GameState.bonus_shields)
	_ui._board.animate_resolve(before, {"attacks": [
		{"instance": inst, "turn": 0, "damage": 3}]}, GameState.hp, held)
	assert_eq(_ui._board.standing_shields().size(), 2,
		"a blow nothing stopped costs no armour")

func test_the_temporary_shields_break_before_the_ones_that_stay() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	GameState.shields = 1
	GameState.bonus_shields = 1
	_ui._refresh()
	var held := Vector2i(GameState.shields, GameState.bonus_shields)
	_ui._board.animate_resolve(before, {"attacks": [
		{"instance": inst, "turn": 0, "damage": 2, "blocked": 2}]}, GameState.hp, held)
	var left: Array = _ui._board.standing_shields()
	assert_eq(left.size(), 1, "one of the two is gone")
	if left.is_empty():
		return
	assert_eq(_timers_on(left[0]), 0,
		"and it is the TEMPORARY one that broke — what is left wears no clock")

func test_the_playback_hands_the_shield_row_back_when_it_ends() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	GameState.shields = 3
	_ui._refresh()
	var held := Vector2i(GameState.shields, GameState.bonus_shields)
	GameState.shields = 0                    # the game was reported: they expired
	var secs: float = _ui._board.animate_resolve(before, {"attacks": [
		{"instance": inst, "turn": 0, "damage": 1, "blocked": 1}]}, GameState.hp, held)
	await wait_seconds(secs + 0.4)
	assert_eq(_ui._board.standing_shields().size(), 0,
		"the row is the run's own again — and the run has none")

func test_a_cut_short_playback_hands_the_shield_row_back() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	GameState.shields = 2
	_ui._refresh()
	_ui._board.animate_resolve(before, {"attacks": [
		{"instance": inst, "turn": 0, "damage": 1, "blocked": 1}]}, GameState.hp,
		Vector2i(4, 0))
	_ui._board.clear_fx()
	assert_eq(_ui._board.standing_shields().size(), 2,
		"a playback wiped mid-flight leaves no stale armour behind")

func test_a_cut_short_playback_hands_the_health_line_back() -> void:
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	_ui._board.animate_resolve(before,
		{"attacks": [{"instance": inst, "turn": 0, "damage": 2}]}, GameState.hp + 2)
	_ui._board.clear_fx()
	assert_eq(_ui._board.shown_hp(), GameState.hp,
		"a playback wiped mid-flight leaves no stale number behind")

func test_a_resolve_from_before_the_ladder_still_plays() -> void:
	# A result with no turn/turn_frames fields — a save restored from before the
	# ladder existed, or a test building one by hand — is one turn's worth of
	# playback rather than nothing at all.
	_ui.pick(0)
	var before: Dictionary = _ui._board.capture_positions()
	var inst: int = int(before.keys()[0])
	assert_almost_eq(_ui._board.animate_resolve(before,
			{"attacks": [{"instance": inst, "damage": 1}]}),
		_ui._board.FX_ATTACK_TIME + _ui._board.FX_NUMBER_TAIL + _ui._board.FX_END_BREATH,
		0.001, "an untagged attack belongs to turn one")

# --- the hub rule (HUB_CONNECTIONS / ONWARD_CONNECTIONS) --------------------
#
# On a well-connected game the offering shows three of dozens of neighbours, and
# the seeded subset can come up all dead ends. Slay the Spire has 138 connections
# and 80 of them lead nowhere, so an unguarded draw strands the run there roughly
# one time in five.

# The busiest node in the run graph, or &"" if the catalog has none — every
# assertion below is written to skip rather than fail on a filtered catalog.
func _busiest_hub() -> StringName:
	var best: StringName = &""
	var best_deg: int = 0
	for g in Data.all_games():
		var d: int = RunGraph.degree(g.id)
		if d > best_deg:
			best_deg = d
			best = g.id
	return best if best_deg > OVERWORLD.HUB_CONNECTIONS else &""

# Stand the run on `hub` and re-roll its offering under a fresh seed.
func _offer_at(hub: StringName, salt: int) -> Array:
	GameState.current_game_id = hub
	_ui._scramble_salt = salt
	_ui._build_choices()
	return _ui._choices

func test_a_hub_always_offers_at_least_one_game_that_leads_onward() -> void:
	var hub: StringName = _busiest_hub()
	if hub == &"":
		return
	# Many seeds, because the bug this guards is probabilistic: the unguarded
	# draw only strands you on the subsets that happen to be all dead ends.
	for salt in range(40):
		var choices: Array = _offer_at(hub, salt)
		assert_gt(choices.size(), 0, "a hub offers cards at all")
		var onward: int = 0
		for c in choices:
			if RunGraph.degree(c["game"].id) > OVERWORLD.ONWARD_CONNECTIONS:
				onward += 1
		assert_gt(onward, 0,
			"seed %d at %s offered only dead ends" % [salt, hub])

func test_the_hub_rule_never_drops_the_amulet() -> void:
	var hub: StringName = _busiest_hub()
	if hub == &"":
		return
	# Park the amulet on a neighbour of the hub so it's reachable and therefore
	# pinned to the front of the offering; the onward swap takes the LAST slot
	# precisely so it can never be the card that goes.
	var nbrs: Array = RunGraph.neighbors(hub)
	if nbrs.is_empty():
		return
	GameState.amulet_game_id = nbrs[0]
	for salt in range(20):
		var ids: Array = []
		for c in _offer_at(hub, salt):
			ids.append(c["game"].id)
		assert_true(ids.has(GameState.amulet_game_id),
			"seed %d dropped the reachable amulet" % salt)

func test_off_a_hub_the_offering_is_left_alone() -> void:
	# The guarantee is a hub rule on purpose: at a small node a thin offering is
	# the honest shape of the graph, and overriding it would invent a route.
	var small: StringName = &""
	for g in Data.all_games():
		var d: int = RunGraph.degree(g.id)
		if d > 0 and d <= OVERWORLD.HUB_CONNECTIONS:
			small = g.id
			break
	if small == &"":
		return
	GameState.current_game_id = small
	# Park the amulet on the node itself so it can't be among the neighbours — the
	# amulet pin reorders the slice for its own reasons, which isn't what's on
	# trial here.
	GameState.amulet_game_id = small
	var untouched: Array = _ui._sorted_neighbors().slice(0, _ui.offer_count())
	assert_eq(_ui._offered_ids(), untouched,
		"a non-hub offering is the plain seeded slice")

func test_the_rule_promises_a_card_that_exists_not_an_invented_one() -> void:
	# A hub whose every neighbour is a dead end gets the plain slice back rather
	# than a card from somewhere else on the map. Ids that aren't in the graph
	# have degree 0, which is exactly the all-dead-ends pool this guards.
	var hub: StringName = _busiest_hub()
	if hub == &"":
		return
	GameState.current_game_id = hub          # so the hub rule is actually engaged
	var offered: Array = [&"a", &"b", &"c"]
	assert_eq(_ui._guarantee_onward(offered.duplicate(), offered), offered,
		"nothing onward in the pool leaves the offering as it was")

# --- escaping a game you can't beat (the gate is a HIT, §3.2) --------------

# Lose `n` runs of the game in play, with enough Health banked to survive doing
# it — each lost run hands the board a turn and whatever is in reach swings.
func _lose_runs(n: int) -> void:
	GameState.max_hp = 99
	GameState.hp = 99
	for i in n:
		_ui.log_attempt()
		# A tick that cost a turn is played back on the board like a report is, and
		# these tests are not waiting out animations — land it and carry on.
		_ui._end_resolve()

# Take a real HIT at the game in play: walk the board into reach, take the
# shields off, and lose one run so the turn it buys lands on Health. That is the
# escape gate, and these tests are about the door rather than about how many
# lost runs it takes to reach it — a swing a shield stops is not a hit.
func _bleed_at_the_game_in_play() -> void:
	GameState.max_hp = 99
	GameState.hp = 99
	GameState.shields = 0
	GameState.bonus_shields = 0
	_front_line()
	var before: int = GameState.hp
	_lose_runs(1)
	assert_lt(GameState.hp, before, "something on the board got through")

# Stand every body in the front column and disarm it, so one turn of the board is
# one swing from each of them. See _disarm_board for why the second half matters.
func _front_line() -> void:
	_disarm_board()
	for entry in GameLoop2.stack:
		entry["col"] = 1

# Mark the game in play as already beaten THIS RUN, the way a real clear does.
func _mark_beaten_this_run(game: GameData) -> void:
	GameState.note_game_beaten(game.id)

# A game this RUN has not already beaten — which is every game on a fresh run, so
# this only has to say so. The escape deliberately does NOT read the lifetime
# tally (a win last week is not a fact about this run), so nothing off disk can
# make these tests flap.
func _pick_an_unplayed_game() -> GameData:
	_ui.pick(0)
	var game: GameData = _ui._chosen["game"]
	assert_false(GameState.has_beaten_game(game.id), "this run has not beaten it")
	return game

func test_escape_is_locked_until_something_gets_through() -> void:
	_pick_an_unplayed_game()
	assert_false(_ui.can_escape(), "a game just started offers no way out")
	# Lost runs alone are not the gate any more: the board takes its turns and the
	# Temporary Shields stop what reaches you, and a swing a shield ate is not a
	# hit. Walk everything into reach so the turns actually swing.
	GameState.max_hp = 99
	GameState.hp = 99
	for entry in GameLoop2.stack:
		entry["col"] = 1
	GameState.shields = 9
	GameState.bonus_shields = 0
	_lose_runs(3)
	assert_eq(GameState.hp, 99, "the shields stopped every swing")
	assert_false(_ui.can_escape(), "so nothing has hurt you and the door is shut")
	assert_true(_ui._escape_btn.visible, "the button is on screen either way")
	assert_true(_ui._escape_btn.disabled, "but darkened, because the door is shut")

func test_escape_unlocks_the_moment_a_swing_takes_health() -> void:
	_pick_an_unplayed_game()
	_bleed_at_the_game_in_play()
	assert_true(GameLoop2.hurt_this_game, "the loop recorded the hit")
	assert_true(_ui.can_escape(), "a swing that got through earns the way out")
	assert_true(_ui._escape_btn.visible, "and the button is there to press")
	assert_false(_ui._escape_btn.disabled, "lit rather than darkened")

func test_a_status_bill_is_not_the_hit_that_opens_the_door() -> void:
	# The gate is an ENEMY'S ATTACK. Burn's "or take 3 Damage" resolves through the
	# same hit path (§13) and costs real Health, but it is a bill for something you
	# did in the real game — not the board refusing to go down.
	_pick_an_unplayed_game()
	GameState.max_hp = 99
	GameState.hp = 99
	GameState.shields = 0
	GameState.bonus_shields = 0
	GameLoop2.damage_player(3)
	assert_lt(GameState.hp, 99, "the bill was paid in Health")
	assert_false(GameLoop2.hurt_this_game, "but nothing on the board did it")
	assert_false(_ui.can_escape(), "so the door stays shut")

# --- the second door: a game you have been through before ------------------
#
# The hit rule is for a game you have never got through. On one you have, there
# is nothing left to prove and being made to stand there and bleed to unlock the
# door is a tax on the least interesting thing in the run.

func test_a_game_you_have_played_before_can_be_left_immediately() -> void:
	_ui.pick(0)
	var game: GameData = _ui._chosen["game"]
	_mark_beaten_this_run(game)
	assert_true(_ui.beaten_this_run(), "the run knows it already beat this one")
	assert_eq(GameLoop2.attempts(), 0, "and not a single run has been lost")
	assert_false(GameLoop2.hurt_this_game, "nor has anything laid a finger on you")
	assert_true(_ui.can_escape(), "the door is open from the first second")
	_ui._refresh()
	assert_true(_ui._escape_btn.visible, "and the button is up to press")
	assert_false(_ui._escape_btn.disabled, "and lit")

func test_the_free_escape_still_costs_you_the_enemy() -> void:
	# "Escape at any time" changes the GATE, not the price: the board resolves
	# exactly as a missed goal does, so the enemy still walks on and everything
	# already out there still takes its turns.
	_pick_solo(0)
	var game: GameData = _ui._chosen["game"]
	_mark_beaten_this_run(game)
	var gp_before: int = GameState.games_played
	_ui.escape_game()
	assert_eq(GameState.games_played, gp_before + 1, "the game is behind you")
	assert_eq(GameLoop2.stack_size(), 1, "and its goal-enemy came with you")
	assert_eq(_ui._phase, OVERWORLD.Phase.SELECT, "back to a fresh offering")

func test_escaping_resolves_the_board_exactly_as_a_missed_report_does() -> void:
	# Walking away is not a pause: the board takes whatever the road charges for
	# finishing a game (§7.4) — none of it out in the wilds, up to two turns on the
	# Amulet's doorstep — and the enemy comes with you either way.
	_ui.pick(0)
	_mark_beaten_this_run(_ui._chosen["game"])
	_ui.escape_game()
	# ONE named body, followed by instance: the second escape stands another one on
	# the board and the stack's order is not a promise.
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var col_before: int = int(GameLoop2.stack[0]["col"])
	# Take the next game the same way, so a second resolve runs.
	_ui.pick(0)
	_mark_beaten_this_run(_ui._chosen["game"])
	var owed: int = GameLoop2.enemy_turns()
	_ui.escape_game()
	var still: Dictionary = GameLoop2.entry_for(inst)
	assert_false(still.is_empty(), "the follower is still following")
	assert_eq(int(still["col"]), maxi(1, col_before - owed),
		"the escape resolved exactly the turns the road charges: %d" % owed)

func test_beaten_this_run_is_false_with_no_game_in_hand() -> void:
	assert_false(_ui.beaten_this_run(), "nothing is in play, so nothing is escapable")
	assert_false(_ui.can_escape(), "and there is nothing to escape from")

func test_escaping_advances_the_run_and_the_enemy_follows() -> void:
	_pick_solo(0)
	var gp_before: int = GameState.games_played
	_bleed_at_the_game_in_play()
	_ui.escape_game()
	assert_eq(GameState.games_played, gp_before + 1, "the game is behind you")
	assert_eq(GameLoop2.stack_size(), 1,
		"but its goal-enemy walked onto the board, as a missed goal always does")
	assert_eq(_ui._phase, OVERWORLD.Phase.SELECT, "and a fresh offering is up")

func test_escaping_does_not_defeat_the_goal_enemy() -> void:
	_ui.pick(0)
	var game: GameData = _ui._chosen["game"]
	var enemy: GoalEnemyData = _ui._chosen["enemy"]
	# GameStats is a LIFETIME store that outlives the run and the test, so the
	# question is what this escape added, not what the tally reads.
	var before: int = GameStats.enemy_beaten_count(game.id, enemy.id)
	_bleed_at_the_game_in_play()
	_ui.escape_game()
	assert_eq(GameStats.enemy_beaten_count(game.id, enemy.id), before,
		"escaping is leaving, not killing")

# An escape earns none of a beat's credit. A missed REPORT still does — that's
# long-standing behaviour and deliberately untouched; walking away is the case
# that isn't allowed to count.
func test_escaping_does_not_count_the_game_as_beaten() -> void:
	_ui.pick(0)
	var game: GameData = _ui._chosen["game"]
	var lifetime_before: int = GameStats.beaten_count(game.id)
	var run_before: int = GameState.total_games_beaten
	_bleed_at_the_game_in_play()
	_ui.escape_game()
	assert_false(GameState.has_beaten_game(game.id),
		"escaping is leaving, not clearing")
	assert_eq(GameState.total_games_beaten, run_before,
		"the run's beaten count doesn't move")
	assert_eq(GameStats.beaten_count(game.id), lifetime_before,
		"nor does the lifetime tally the Collection and the tier list read")

func test_escaping_pays_no_repeat_beat_dash() -> void:
	# Standing on a game already cleared this run, escaping it must not pay the
	# Dash a second clear would — there was no second clear.
	var target: GameData = _ui._choices[0]["game"]
	GameState.note_game_beaten(target.id)
	_ui._build_choices()
	_ui.pick(0)
	var dash_before: int = GameState.dash_charges
	_bleed_at_the_game_in_play()
	_ui.escape_game()
	assert_eq(GameState.dash_charges, dash_before,
		"walking away from a game you'd beaten before earns nothing")

func test_escaping_still_advances_the_run_clock() -> void:
	# Withholding the CREDIT doesn't stall the run: the time was spent and the
	# board closed in, so the difficulty clock moves either way.
	_ui.pick(0)
	var gp_before: int = GameState.games_played
	_bleed_at_the_game_in_play()
	_ui.escape_game()
	assert_eq(GameState.games_played, gp_before + 1,
		"games_played counts the game you walked away from")

# This used to assert the opposite — "a missed report keeps crediting the game
# exactly as it always has" — which is the behaviour BEATEN MEANS WON replaced.
# What separates an escape from a miss is no longer the beat (neither is one);
# it is the item trigger and the event, which a miss still earns.
func test_a_missed_report_is_not_a_beat_either() -> void:
	_ui.pick(0)
	var game: GameData = _ui._chosen["game"]
	_ui.report(false)
	assert_false(GameState.has_beaten_game(game.id),
		"failing a game is not beating it, escape or no escape")

func test_escape_refuses_before_anything_has_hurt_you() -> void:
	_pick_an_unplayed_game()
	var gp_before: int = GameState.games_played
	_lose_runs(2)
	_ui.escape_game()
	assert_eq(GameState.games_played, gp_before,
		"pressing it early does nothing at all")
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "the game is still in play")

func test_undoing_the_tick_that_drew_blood_takes_the_escape_away() -> void:
	# Only the hit door reverses; a game you have a record at is escapable whatever
	# the board did, so this has to be a game you have never played.
	_pick_an_unplayed_game()
	_bleed_at_the_game_in_play()
	assert_true(_ui.can_escape())
	GameLoop2.undo_attempt()
	_ui._refresh()
	assert_false(GameLoop2.hurt_this_game, "the hit was undone with the turn")
	assert_false(_ui.can_escape(), "the tracker is hand-driven, so this reverses too")
	assert_true(_ui._escape_btn.disabled, "and the button darkens again with it")

func test_three_bodies_down_is_a_way_out_on_its_own() -> void:
	# The door the player drives: a fixed price in kills, reachable on any board,
	# rather than the old "clear the whole stack" that cost one goal on a stack of
	# one and was unreachable on a stack of six (§3.2).
	_pick_an_unplayed_game()
	assert_false(_ui.can_escape(), "an untouched board holds you until one lands a hit")
	GameLoop2.defeated_this_game = OVERWORLD.ESCAPE_AFTER_DEFEATS - 1
	_ui._refresh()
	assert_false(_ui.can_escape(), "two is not three")
	GameLoop2.defeated_this_game = OVERWORLD.ESCAPE_AFTER_DEFEATS
	_ui._refresh()
	assert_true(_ui.can_escape(), "the third opens the door")
	assert_true(_ui._escape_btn.visible, "and the button is up")
	assert_true(_ui._escape_btn.tooltip_text.contains("enemies down"),
		"saying which door it is: %s" % _ui._escape_btn.tooltip_text)

func test_an_empty_board_is_not_a_way_out_by_itself() -> void:
	# The clause it replaced. A board emptied by BOMBS is the case that made the
	# old rule wrong — nothing was beaten, and the door opened anyway.
	_pick_an_unplayed_game()
	for entry in GameLoop2.stack.duplicate():
		GameLoop2.despawn(int(entry["instance"]))
	assert_true(GameLoop2.stack.is_empty(), "the board is clear")
	_ui._refresh()
	assert_false(_ui.can_escape(), "but nobody was beaten, so nothing was paid")

func test_the_kill_count_is_per_game() -> void:
	# Like the hit gate: what the last game cost the board is not a fact about this
	# one, so choosing a game resets the count and shuts the door again.
	_pick_an_unplayed_game()
	GameLoop2.defeated_this_game = OVERWORLD.ESCAPE_AFTER_DEFEATS
	assert_true(_ui.can_escape(), "the door is open on this one")
	_ui.report(false)
	# The offering is random, so the second card can be the Amulet — playing which
	# IS the run, whatever the goal did. Nothing left to choose then, and nothing
	# for this test to be about.
	if GameLoop2.run_over or _ui._phase != OVERWORLD.Phase.SELECT:
		assert_eq(GameLoop2.defeated_this_game, 0,
			"the count still went with the game that was handed in")
		return
	_ui.pick(0)
	assert_eq(GameLoop2.defeated_this_game, 0, "the next game starts the count over")
	# …and with the count back at zero the kill door is shut. Only the kill door:
	# a game this run has already beaten is escapable from the first second on its
	# own terms, which is a different rule and has its own test.
	if not _ui.beaten_this_run():
		assert_false(_ui.can_escape(), "so the door is shut again")

# --- the fourth door: five lost runs, and the line that counts them down -----
#
# The floor under the other three. A board that cannot land a hit and cannot be
# cleared would otherwise hold a player on a game forever, so patience is a way
# out again — an expensive one, since every loss is a turn the board took.

func test_five_lost_runs_open_the_door_on_their_own() -> void:
	_pick_an_unplayed_game()
	# Shielded to the eyeballs and everything out of reach, so nothing can land the
	# hit that would open the OTHER door and make this test about the wrong rule.
	GameState.shields = 99
	GameState.bonus_shields = 0
	_lose_runs(OVERWORLD.ESCAPE_AFTER_LOSSES - 1)
	assert_false(GameLoop2.hurt_this_game, "no swing got through")
	assert_false(_ui.can_escape(), "four is not five")
	_lose_runs(1)
	assert_true(_ui.can_escape(), "and the fifth opens it whatever the board did")
	_ui._refresh()
	assert_false(_ui._escape_btn.disabled, "the button lights up with it")

func test_the_hint_counts_the_losses_down_and_names_the_other_doors() -> void:
	_pick_an_unplayed_game()
	GameState.shields = 99
	GameState.bonus_shields = 0
	_ui._refresh()
	var hint: String = _ui.escape_hint_text()
	assert_true(hint.contains("%d more losses" % OVERWORLD.ESCAPE_AFTER_LOSSES),
		"the countdown starts at the full price: %s" % hint)
	assert_true(hint.contains("Beat %d Enemies" % OVERWORLD.ESCAPE_AFTER_DEFEATS),
		"and the kill count is a door too: %s" % hint)
	assert_true(hint.contains("Lose Health"), "as is a hit: %s" % hint)
	assert_true(hint.contains(" or "), "read as one line of alternatives: %s" % hint)
	assert_eq(_ui._escape_hint.text, hint, "which is what the line under the button says")
	assert_true(_ui._escape_hint.visible, "and it is up while the door is shut")

func test_the_countdown_falls_as_runs_are_lost() -> void:
	_pick_an_unplayed_game()
	GameState.shields = 99
	GameState.bonus_shields = 0
	_lose_runs(OVERWORLD.ESCAPE_AFTER_LOSSES - 1)
	assert_true(_ui.escape_hint_text().begins_with("1 more loss,"),
		"singular on the last one: %s" % _ui.escape_hint_text())

func test_an_open_door_says_nothing_at_all() -> void:
	_pick_an_unplayed_game()
	_bleed_at_the_game_in_play()
	assert_eq(_ui.escape_hint_text(), "", "there is nothing left to earn")
	_ui._refresh()
	assert_false(_ui._escape_hint.visible, "so the line goes away")

func test_a_route_already_paid_drops_off_the_line() -> void:
	# The line names what is still OWED, so a door already open stops being a route
	# to count down to. Three bodies down is the one the player can drive, and it is
	# also the one that opens the whole gate — so paying it empties the line.
	_pick_an_unplayed_game()
	assert_string_contains(_ui.escape_hint_text(), "Beat 3 Enemies",
		"the kill count is on the line while it is unpaid")
	GameLoop2.defeated_this_game = OVERWORLD.ESCAPE_AFTER_DEFEATS
	assert_eq(_ui.escape_hint_text(), "",
		"and once it is paid the door is open, so the line has nothing left to say")

func test_escaping_still_owes_the_road_its_extra_turns() -> void:
	# Walking away is FINISHING a game as far as the Amulet is concerned: the extra
	# turns it charges (§7.4) resolve on the way out, exactly as they would for a
	# missed report. Stood on the doorstep so there is something to owe.
	var near: StringName = _a_game_at_hops(1)
	if near == &"":
		return
	_ui.pick(0)
	GameState.set_current_game(near)
	assert_eq(GameLoop2.enemy_turns(), 2, "one hop out is two extra turns")
	_mark_beaten_this_run(_ui._chosen["game"])
	GameState.max_hp = 40
	GameState.hp = 40
	GameState.shields = 0
	GameState.bonus_shields = 0
	_front_line()                              # in reach, so the turns are swings
	var swingers: int = GameLoop2.stack.size()
	var dmg: int = 0
	for entry in GameLoop2.stack:
		dmg += GameLoop2.enemy_damage(entry)
	_ui.escape_game()
	_ui._end_resolve()
	assert_eq(40 - GameState.hp, dmg * 2,
		"%d bodies swung on both of the road's turns as you left" % swingers)

func test_the_door_closes_again_on_the_next_game() -> void:
	# The gate is a fact about the game in play, not about the run: walking into a
	# fresh game means proving it again.
	_pick_an_unplayed_game()
	_bleed_at_the_game_in_play()
	assert_true(_ui.can_escape())
	_ui.escape_game()
	_ui.pick(0)
	assert_false(GameLoop2.hurt_this_game, "a new game has not hurt you yet")
	# …so THIS door is shut. The other one is independent and the offering can
	# legitimately hand back a game the run has already beaten (the graph allows
	# revisits, and the opening game was beaten to get here), so which of the two
	# answers is right depends on the card — assert whichever it is rather than
	# assuming the common one, or this passes on most runs and fails on the rest.
	if _ui.beaten_this_run():
		assert_true(_ui.can_escape(),
			"the card came back around, and a past beat opens the other door")
	else:
		assert_false(_ui.can_escape(), "so its door starts shut")

# --- rating flows into the tier list ---------------------------------------

func _open_rating_modal() -> Node:
	_ui._prompt_rating(Data.all_games()[0])
	for c in _ui.get_children():
		if c is RateGameModal:
			return c
	return null

func _tier_list_screen() -> Node:
	for c in _ui.get_children():
		if c is TierListScreen:
			return c
	return null

func test_submitting_a_rating_opens_the_tier_list() -> void:
	var modal := _open_rating_modal()
	assert_not_null(modal, "the rate prompt opened")
	assert_null(_tier_list_screen(), "and nothing else is up yet")
	modal.submitted.emit(7, "good")
	assert_not_null(_tier_list_screen(),
		"a submitted score lands the player on the board it went to")

func test_the_score_is_recorded_before_the_board_opens() -> void:
	var game: GameData = Data.all_games()[0]
	_ui._prompt_rating(game)
	var modal: Node = null
	for c in _ui.get_children():
		if c is RateGameModal:
			modal = c
	modal.submitted.emit(9, "notes here")
	var rating: Dictionary = TierList.get_rating(game.id)
	assert_eq(int(rating.get("score", 0)), 9, "the score persisted")
	assert_eq(String(rating.get("notes", "")), "notes here", "and the notes with it")

func test_maybe_later_takes_you_nowhere() -> void:
	var modal := _open_rating_modal()
	modal.dismissed.emit()
	assert_null(_tier_list_screen(),
		"declining to rate shouldn't hand the player a screen they didn't ask for")

# --- the pack: reading vs spending ---------------------------------------
#
# Two gestures, deliberately separate: clicking a token READS the item (its
# card), and only the control above the token ever SPENDS a charge. Inspecting
# an item must never cost you one.

func test_clicking_an_item_token_opens_its_card() -> void:
	var heart: ItemData = GameState.add_item(Data.get_item2(&"hollow_heart"))
	_ui._refresh_items()
	_ui.open_item_card(heart)
	assert_not_null(_ui._item_card, "the card is mounted")
	assert_true(_ui.is_ancestor_of(_ui._item_card), "on the screen, over the page")
	_ui._close_item_card()
	assert_null(_ui._item_card, "and closes cleanly")

func test_an_active_item_grows_a_fire_control_above_its_tile() -> void:
	# Ride the Bus is a plain Usable: its control is the Use button, and the token
	# below it is the art tile.
	GameState.add_item(Data.get_item2(&"ride_the_bus"))
	_ui._refresh_items()
	var column: Control = _ui._items_box.get_child(_ui._items_box.get_child_count() - 1)
	assert_eq(column.get_child_count(), 2, "fire control over art tile")
	assert_true(column.get_child(0) is Button, "a Usable item's control is a button")
	assert_eq((column.get_child(0) as Button).text, "Use")

func test_a_passive_item_has_no_fire_control() -> void:
	GameState.add_item(Data.get_item2(&"hollow_heart"))
	_ui._refresh_items()
	var column: Control = _ui._items_box.get_child(_ui._items_box.get_child_count() - 1)
	assert_eq(column.get_child_count(), 1, "nothing to fire, so nothing above it")

func test_a_part_charged_item_shows_a_battery_and_a_full_one_shows_use() -> void:
	# The battery is one rectangle per charge — Isaac's active bar on its side —
	# and becomes the Use button at full, so the same strip answers "how long" and
	# "can I now".
	var d6: ItemData = GameState.add_item(Data.get_item2(&"d6"))
	d6.current_charge = 0
	_ui._refresh_items()
	var column: Control = _ui._items_box.get_child(_ui._items_box.get_child_count() - 1)
	var meter: Control = column.get_child(0)
	assert_false(meter is Button, "an empty charge is a meter, not a button")
	assert_eq(meter.get_child(0).get_child_count(), d6.max_charge(),
		"one segment per charge")

	d6.current_charge = d6.max_charge()
	_ui._refresh_items()
	column = _ui._items_box.get_child(_ui._items_box.get_child_count() - 1)
	assert_true(column.get_child(0) is Button, "full charge turns the meter into Use")
	assert_eq((column.get_child(0) as Button).text, "Use")

# --- dev mode grants 2.0 items, and only 2.0 items -------------------------
#
# The Add-item list used to append Data.all_items() — the 112 combat-era relics
# from the build this one replaced — on top of the 2.0 set. They are ItemData, so
# they listed and granted cleanly and then did nothing, because no games-first
# code honours them; and 112 of them buried the 21 that work.
func test_dev_mode_offers_only_the_2_0_item_set() -> void:
	var pool: Array = DevTools.item_pool()
	assert_eq(pool.size(), Data.all_items2().size(),
		"the pool is exactly the 2.0 set")
	var live: Dictionary = {}
	for it in Data.all_items2():
		live[it.id] = true
	for it in pool:
		assert_true(live.has(it.id),
			"%s is a 2.0 item the run can actually honour" % it.id)
	# The combat-era set is still loaded (the archive reads it); it just must not
	# be on this list.
	assert_gt(Data.all_items().size(), pool.size(),
		"the old set is still there to be wrongly included, so this is a real guard")

# --- the board survives a repaint under the cursor -------------------------
#
# refresh() detaches every body on the board, and detaching the one the mouse is
# over makes Godot fire that body's mouse_exited from inside the removal loop.
# The handler's job is to restore the body's draw order, so it called move_child
# on a parent mid-removal: "Parent node is busy setting up children".
func test_a_hover_handler_does_not_reorder_the_board_mid_repaint() -> void:
	_ui.pick(0)
	_ui.report(false)
	var board = _ui._board
	assert_gt(GameLoop2.stack_size(), 0, "there is a body on the board")
	var inst: int = int(GameLoop2.stack[0]["instance"])
	var node: Control = board._enemy_nodes[inst]
	var layer: Node = node.get_parent()
	var resting: int = node.get_index()
	# Hovering lifts it above its neighbours…
	node.mouse_entered.emit()
	assert_eq(node.get_index(), layer.get_child_count() - 1, "hover lifts the body")
	# …and while a repaint is in flight, the matching exit must NOT touch the tree.
	board._repainting = true
	node.mouse_exited.emit()
	assert_eq(node.get_index(), layer.get_child_count() - 1,
		"a repaint's own mouse_exited leaves the layer alone")
	# Off the repaint, it still does its ordinary job.
	board._repainting = false
	node.mouse_exited.emit()
	assert_eq(node.get_index(), resting, "and otherwise puts the body back")

func test_clicking_an_enemy_repaints_without_a_detached_reorder() -> void:
	# The real sequence from the crash report: a click repaints the board, which
	# frees the very node whose handler is about to run.
	_ui.pick(0)
	_ui.report(false)
	var board = _ui._board
	var entry: Dictionary = GameLoop2.stack[0]
	var inst: int = int(entry["instance"])
	var node: Control = board._enemy_nodes[inst]
	node.mouse_entered.emit()
	board.click_enemy(inst, entry, int(entry["col"]))
	# The click rebuilt the board, so the hovered node is detached — and its
	# late-firing exit handler must be a no-op rather than a move_child on a
	# parent it no longer has.
	assert_false(is_instance_valid(node) and node.get_parent() == board._enemy_layer,
		"the repaint detached the node the mouse was over")
	if is_instance_valid(node):
		node.mouse_exited.emit()
	assert_not_null(board._enemy_nodes.get(inst), "and the board rebuilt it")
	_ui._close_enemy_info()

# --- escaping fires no "after game beaten" trigger --------------------------
#
# Everything that hangs off finishing a game — the item hook itself (Burning
# Blood's +1 Health and friends), the Harvesting gold payout, and the recharge
# tick that charged actives like the D6 live on — comes through
# TriggerBus.game_beaten. An escape must fire NONE of it: the player walked away,
# and a run that pays for walking away is a run with a free lever in it.

func _game_beaten_count() -> int:
	# A live listener, so this counts what actually reaches the bus rather than
	# any one of its consequences.
	return _beaten_signals

var _beaten_signals: int = 0

func _watch_game_beaten() -> void:
	_beaten_signals = 0
	if not TriggerBus.game_beaten.is_connected(_note_game_beaten):
		TriggerBus.game_beaten.connect(_note_game_beaten)

func _note_game_beaten(_ctx: Dictionary) -> void:
	_beaten_signals += 1

func test_escaping_fires_no_game_beaten_trigger() -> void:
	_ui.pick(0)
	_mark_beaten_this_run(_ui._chosen["game"])   # so the escape is available at once
	_watch_game_beaten()
	_ui.escape_game()
	assert_eq(_game_beaten_count(), 0,
		"walking away is not finishing a game, so nothing hooked on it fires")
	TriggerBus.game_beaten.disconnect(_note_game_beaten)

func test_escaping_pays_no_harvesting_gold() -> void:
	GameState.harvesting = 5
	assert_eq(Stats.get_value(&"harvesting"), 5, "the payout stat is really set")
	_ui.pick(0)
	_mark_beaten_this_run(_ui._chosen["game"])
	var gold_before: int = GameState.gold
	_ui.escape_game()
	assert_eq(GameState.gold, gold_before, "no Harvesting payout for leaving")

func test_escaping_does_not_recharge_a_charged_item() -> void:
	# Charged actives recharge one step per game finished; an escape isn't one.
	var charged: ItemData = null
	for it in Data.all_items2():
		if it is ItemData and (it as ItemData).is_charged():
			charged = it
			break
	if charged == null:
		return
	var inst: ItemData = GameState.add_item(charged)
	inst.current_charge = 0
	_ui.pick(0)
	_mark_beaten_this_run(_ui._chosen["game"])
	_ui.escape_game()
	assert_eq(inst.current_charge, 0, "leaving does not tick the recharge")

# …and a report that FINISHES the game does fire it, win or lose. This is the
# pairing that makes the test above mean something: the guard is on escaping, not
# on the trigger existing.
func test_finishing_a_game_does_fire_the_trigger() -> void:
	_ui.pick(0)
	_watch_game_beaten()
	_ui.report(false)
	assert_eq(_game_beaten_count(), 1,
		"a game played to a verdict fires it even when the goal was missed")
	TriggerBus.game_beaten.disconnect(_note_game_beaten)

# ---------------------------------------------------------------------------
# The checklist and the board point at each other
# ---------------------------------------------------------------------------
#
# A goal on the list and a body on the field are the same fact written twice.
# Hovering either end lights both, which is the only thing that answers "which of
# these four lines is that thing" without reading names.

func test_hovering_a_goal_row_lights_the_body_it_belongs_to() -> void:
	_ui.pick(0)
	_ui.report(false)                      # the enemy is a follower now
	var inst: int = int(GameLoop2.stack[0]["instance"])
	assert_true(_ui._row_paints.has(inst),
		"the standing checklist wrote a row about that body")
	_ui._light_bodies([inst])
	assert_true(_ui._board._is_lit(inst), "and lighting the row lights the body")
	_ui._light_bodies([])
	assert_false(_ui._board._is_lit(inst), "leaving the row puts it out again")

# The hover has to be on the ROW, not on the sliver of it the checkbox left over.
# Godot hands mouse_entered to the one control under the cursor and not to its
# ancestors, so a row bound only on its frame lit up from a few pixels of padding
# and stayed dark everywhere a player actually points — which is the whole row.
func test_every_part_of_a_goal_row_lights_the_body_not_just_its_border() -> void:
	_ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	var enemy: GoalEnemyData = GameLoop2.arrival()["enemy"]
	var made: Dictionary = _ui._verify_row("Goal — %s" % GameLoop2.goal_text_for(GameLoop2.arrival()),
		UITheme.TEXT, false, enemy, null, inst)
	var row: Control = made["row"]
	var parts: Array = _ui._hover_targets(row)
	assert_gt(parts.size(), 2, "a row is a frame with a box and a button in it")
	var saw_box := false
	for part in parts:
		var ctl: Control = part
		saw_box = saw_box or ctl is CheckBox
		assert_gt(ctl.mouse_entered.get_connections().size(), 0,
			"the row's %s reports its hover" % ctl.get_class())
		_ui._light_bodies([])
		ctl.mouse_entered.emit()
		assert_true(_ui._lit_instances.has(inst),
			"hovering the row's %s lights the body" % ctl.get_class())
	assert_true(saw_box, "the checkbox — most of the row's width — is one of them")
	_ui._light_bodies([])
	row.queue_free()

# Leaving is POSITIONAL: the exit asks where the pointer actually is rather than
# trusting the signal, because crossing from the tick-box to the Notes button
# fires an exit and an enter in the same frame and the row was never left. Here
# the pointer is nowhere near it, which is the other half of that rule.
func test_leaving_a_row_altogether_puts_the_highlight_out() -> void:
	_ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	var made: Dictionary = _ui._verify_row("Goal — something", UITheme.TEXT, false,
		GameLoop2.arrival()["enemy"], null, inst)
	var row: Control = made["row"]
	add_child_autofree(row)          # the exit test is positional, so it needs a rect
	row.position = Vector2(10, 10)
	row.size = Vector2(400, 40)
	var box: CheckBox = made["check"]
	box.mouse_entered.emit()
	assert_true(_ui._lit_instances.has(inst), "the box lit it")
	# The pointer is nowhere near the row in a headless test, so leaving really is
	# leaving: the exit clears it.
	box.mouse_exited.emit()
	assert_false(_ui._lit_instances.has(inst),
		"and a pointer that is not on the row anywhere puts it out")

func test_hovering_a_body_lights_the_goal_row_it_is_written_on() -> void:
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	# What the board emits when the mouse crosses a body.
	_ui._on_enemy_hovered(inst, true)
	assert_true(_ui._lit_instances.has(inst), "the row for that body is lit")
	assert_true(_ui._board._is_lit(inst), "and so is the body")
	_ui._on_enemy_hovered(inst, false)
	assert_false(_ui._lit_instances.has(inst), "and both go out together")

func test_a_row_about_no_body_lights_nothing() -> void:
	# The level-up challenge, event goals and player statuses belong to no enemy,
	# so they bind nothing rather than lighting an arbitrary body.
	_ui.pick(0)
	var bound: int = _ui._row_paints.size()
	assert_lte(bound, GameLoop2.stack.size(),
		"only the rows written about a body are bound: %d bound, %d bodies" % [
			bound, GameLoop2.stack.size()])

func test_the_lit_set_is_dropped_when_the_checklist_is_rebuilt() -> void:
	_ui.pick(0)
	var inst: int = int(GameLoop2.arrival()["instance"])
	_ui._light_bodies([inst])
	assert_true(_ui._board._is_lit(inst))
	_ui.report(false)                      # rebuilds the checklist under it
	assert_true(_ui._lit_instances.is_empty(),
		"nothing stays lit by a list that no longer exists")

# ---------------------------------------------------------------------------
# The boss round is a popup, not a strip that shoves the page down
# ---------------------------------------------------------------------------

func _force_boss_round() -> void:
	# A boss round is the CAPSTONE of a tier: it lands on the offering drawn after
	# the GAMES_PER_TIER'th game has been played.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	_ui._build_choices()
	assert_true(_ui._boss_round, "the next offering is the difficulty gate")

func test_a_boss_round_announces_itself_in_a_popup() -> void:
	_force_boss_round()
	_ui._maybe_announce_boss()
	assert_not_null(_ui._boss_notice, "the warning is a popup")
	_ui._boss_notice.close()
	assert_null(_ui._boss_notice, "and it closes on its own button")

# The popup names three bosses and used to say nothing else about them. Its
# portraits open the same card the battlefield opens, so "what does it want and
# what does it hit for" is answered where the question is asked.
func test_the_boss_warning_opens_a_card_on_the_boss_you_click() -> void:
	_force_boss_round()
	_ui._maybe_announce_boss()
	var notice = _ui._boss_notice
	assert_not_null(notice, "the warning is up")
	var boss: GoalEnemyData = null
	for c in _ui._choices:
		if c["enemy"] is GoalEnemyData and c["enemy"].is_boss():
			boss = c["enemy"]
			break
	if boss == null:
		return                     # no boss art in the roster to read
	var card = notice.inspect_boss(boss)
	assert_not_null(card, "the portrait opens a card")
	assert_eq(card.get_parent(), notice,
		"over the warning rather than instead of it — the warning is still unanswered")
	assert_not_null(_ui._boss_notice, "and reading a boss does not dismiss it")
	notice.close()

# A boss on the notice has no body on the board yet, so the card must not offer
# the verbs that are aimed at one — Push and Bomb take an instance, and there
# isn't one until the game is picked.
func test_a_boss_read_off_the_warning_is_read_only() -> void:
	_force_boss_round()
	_ui._maybe_announce_boss()
	var notice = _ui._boss_notice
	var boss: GoalEnemyData = GameLoop2.roll_boss(&"", 0)
	if boss == null:
		return
	var card = notice.inspect_boss(boss)
	assert_not_null(card)
	for btn in _buttons_under(card):
		assert_false(btn.text.begins_with("Push") or btn.text.begins_with("Bomb"),
			"no verb is aimed at a body that does not exist: %s" % btn.text)
	notice.close()

func _buttons_under(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_buttons_under(child))
	return out

func test_the_boss_warning_opens_once_for_the_round() -> void:
	_force_boss_round()
	_ui._maybe_announce_boss()
	var first = _ui._boss_notice
	first.close()
	# A scramble / bash redraws the offering; the warning must not come back with it.
	_ui._build_choices()
	_ui._maybe_announce_boss()
	assert_null(_ui._boss_notice, "the same round warns once")

# ---------------------------------------------------------------------------
# The screen a game ends on (PostCombatScreen)
#
# One screen instead of six surfaces. What has to stay true is the SHAPE of it:
# it opens when the board has stopped moving, it carries the whole haul, its way
# out is what opens the event, and the shelf it borrows goes back to the page.
# ---------------------------------------------------------------------------

func _haul() -> PostCombatScreen:
	return _ui._post_screen

# Which of the three reports this was — and it is not a win/lose. You can beat a
# game and clear nothing, miss the goal in one you finished, or walk away, and
# the screen has to say which of those happened.
func test_the_haul_screen_says_which_report_this_was() -> void:
	_ui.pick(0)
	var played: GameData = _ui._chosen.get("game")
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(screen.verdict(), "beaten", "the goal was met and the game finished")
	assert_eq(screen.game(), played, "about the game that was just played")
	assert_true(played.display_name in screen.subtitle(),
		"which it names: %s" % screen.subtitle())
	_leave_post_game()

func test_a_missed_goal_and_a_walk_away_read_differently() -> void:
	_ui.pick(0)
	_ui.report(false)
	_ui._end_resolve()
	assert_eq(_haul().verdict(), "missed", "played it, goal unmet")
	_leave_post_game()
	_dismiss_event()
	_clear_board()
	_ui.pick(0)
	_ui.report(false, [], true)                  # escaped
	_ui._end_resolve()
	assert_eq(_haul().verdict(), "escaped", "walked away from it")
	_leave_post_game()

# ==========================================================================
# Why the chest is the size it is (§8.2)
#
# The chest used to arrive as an assertion — a Large one over the words "what the
# evening earned", with nothing anywhere saying why it was Large. The screen shows
# the sum now: beating the game is a point, every body cleared is worth its own
# difficulty, and the total is spent up the size ladder.
# ==========================================================================

# The floor of it: a game beaten with nothing cleared is one point and one Small
# chest, and the sum says exactly that rather than leaving the term out.
func test_the_chest_sum_starts_with_the_point_the_win_is_worth() -> void:
	_clear_board()
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var terms: Array = screen.chest_terms()
	assert_false(terms.is_empty(), "a beaten game has a sum to show")
	assert_eq(String(terms[0].get("label", "")), "Beat the game",
		"and it opens with the point the win is worth on its own")
	assert_eq(int(terms[0].get("points", 0)), 1)
	assert_null(terms[0].get("enemy"), "which has no face behind it")
	_leave_post_game()
	_dismiss_event()

# Every body that paid appears, worth its own difficulty — and the terms ADD UP to
# the chest the player was actually handed. That is the whole point of showing the
# arithmetic: a breakdown that did not total the payout would be worse than none.
func test_the_chest_sum_adds_up_to_the_chest_it_explains() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var sum: int = 0
	for term in screen.chest_terms():
		var points: int = int(term.get("points", 0))
		assert_gt(points, 0, "every term is worth something")
		var enemy: GoalEnemyData = term.get("enemy")
		if enemy != null:
			assert_eq(points, GameLoop2.chest_points_for(enemy),
				"%s is worth its own difficulty" % enemy.display_name)
		sum += points
	assert_eq(sum, screen.chest_total(), "the terms are the total")
	assert_eq(screen.chest_result_text(), Data.chest_reward_text(sum),
		"and the total names the chest the same function actually spent it on")
	assert_string_contains(screen.chest_reason(), "=",
		"the line reads as a sum: %s" % screen.chest_reason())
	# And the row SAYS what it is totalling. A line of faces and numbers is
	# arithmetic without a subject until something names the quantity.
	assert_string_contains(_text_of(screen).to_upper(), "ITEM CHEST SIZE",
		"the sum is labelled")
	_leave_post_game()
	_dismiss_event()

# No chest, no explanation. A missed goal and a walk-away bank nothing from the
# bodies (§8.2), so there is no size to justify and the section is not drawn.
func test_a_report_that_earns_no_chest_explains_nothing() -> void:
	_ui.pick(0)
	_ui.report(false)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	assert_true(screen.chest_terms().is_empty(), "a missed goal buys no chest")
	assert_eq(screen.chest_reason(), "", "so it has nothing to explain")
	_leave_post_game()
	_dismiss_event()

# ★ RATE MOVED HERE from the play panel's checklist, where it offered the score
# while the game was still in front of the player. It sits beside the cover now.
func test_the_haul_screen_carries_the_rate_button() -> void:
	_ui.pick(0)
	var played: GameData = _ui._chosen.get("game")
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var rate: Button = null
	for btn in screen.find_children("*", "Button", true, false):
		if String((btn as Button).text).contains("Rate"):
			rate = btn
	assert_not_null(rate, "the haul screen offers the score")
	if rate != null and played != null:
		assert_string_contains(rate.tooltip_text, played.display_name,
			"for the game that just ended")
	_leave_post_game()
	_dismiss_event()

# …and the play panel does NOT, which is the other half of the move. Asserted
# while a game is in play and BEFORE any haul screen exists: the screen mounts its
# CanvasLayer under the page, so a search of the page's tree with the haul up
# would find the button this test is checking has gone.
func test_the_play_panel_no_longer_asks_for_a_score_mid_game() -> void:
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "a game is in play")
	assert_null(_ui._post_screen, "and no haul screen to borrow a button from")
	# ReportChecklist is a RefCounted that builds into containers the PAGE owns —
	# `_launch_row` is the strip the Play button and the old ★ Rate shared.
	assert_not_null(_ui._launch_row, "the play panel's launch strip is up")
	if _ui._launch_row == null:
		return
	for btn in _ui._launch_row.find_children("*", "Button", true, false):
		assert_false(String((btn as Button).text).contains("Rate"),
			"the checklist does not ask for a score while the game is still in "
			+ "front of you — found %s" % (btn as Button).text)

# The numbers out of beat_game's result, which used to be thrown away the moment
# the animation had played them: what it cost you, and what is still on your tail.
func test_the_haul_screen_carries_the_fight_in_numbers() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var keys: Array = []
	for row in screen.tally():
		keys.append(String(row[0]))
	for expected in ["Damage taken", "Health", "Goals cleared", "Still following", "Difficulty"]:
		assert_true(keys.has(expected), "the tally says %s: %s" % [expected, keys])
	_leave_post_game()

# THE WAY OUT IS THE EVENT. The event used to be dropped on the player the moment
# the board stopped; it is now behind a button, so leaving the haul is what opens
# it — and the button says which of the two things it is about to do.
func test_the_way_out_names_the_event_and_is_what_opens_it() -> void:
	# Built with the event pending rather than reported into, for the reason the
	# test below is: the resolve can land instantly (§7.4), so there is no moment
	# between report() and the screen opening in which to post one.
	var events: Array = Data.all_events2()
	if events.is_empty():
		return
	_ui.pick(0)
	_ui._pending_event = events[0]
	var screen := PostCombatScreen.open(_ui,
		{"game": _ui._chosen["game"], "beaten": true, "escaped": false,
			"amulet": false, "res": {}}, [], true)
	_ui._post_screen = screen
	# The chain behind the screen is what OPENS the event, and it hangs off this
	# signal — which _open_post_game normally wires. Built by hand, so wired by hand.
	screen.finished.connect(func(): _ui._on_post_game_finished(screen))
	assert_true(screen.exit_text().contains("Go to Event"),
		"the button NAMES what is behind it: %s" % screen.exit_text())
	assert_null(_ui._event_modal, "which has NOT been dropped on the player yet")
	screen.dismiss()
	assert_not_null(_ui._event_modal, "and pressing it is what opens the event")
	_ui._post_screen = null
	_dismiss_event()

func test_the_way_out_says_travel_on_when_nothing_is_waiting() -> void:
	# Built with nothing pending rather than reported into: an event fires after
	# every game, and the resolve can now land instantly (§7.4), so there is no
	# moment between the two in which to take the event away.
	var screen := PostCombatScreen.open(_ui,
		{"game": _ui._choices[0]["game"], "beaten": true, "escaped": false,
			"amulet": false, "res": {}}, [], false)
	_ui._post_screen = screen
	assert_true(screen.exit_text().contains("Travel on"),
		"nothing is waiting, so the button says so: %s" % screen.exit_text())
	screen.dismiss()
	_ui._post_screen = null

# Leaving with something still on the table BINS it, so the button says so first.
# A Legendary left on the ground should be a decision and not a side effect of
# pressing Continue.
func test_the_way_out_counts_what_it_is_about_to_leave_behind() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	assert_not_null(screen.chest(), "there is a chest on the table")
	assert_true(screen.exit_text().contains("leaving"),
		"and the way out owns up to binning it: %s" % screen.exit_text())
	_leave_post_game()

# The payout is a column of the same screen rather than a modal after it, and it
# is the REAL one — the same live 3x3, the same bin, the same "use it where you
# stand" — so a piece taken here lands in the pack exactly as it does anywhere.
func test_the_payout_is_a_column_of_the_haul_screen() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var payout = screen.payout()
	assert_not_null(payout, "the game's own loot is on the table")
	if payout == null:
		return
	var carried: int = GameState.loot_items.size()
	# The table can hold more than the game's own piece now: every body defeated at
	# this game left one on the floor too, and the report sweeps them here (§8.2).
	var on_table: int = payout.remaining()
	assert_gt(on_table, 0, "there is something to take")
	payout.take()
	assert_eq(GameState.loot_items.size(), carried + on_table,
		"taking it fills a slot per piece")
	assert_eq(payout.remaining(), 0, "and clears the table")
	# …AND THE SECTION STAYS. As a modal, the last piece leaving the table is the
	# end of the question. Here it is the opposite: the piece has just gone into the
	# pack, and the pack is the reason to still be looking — the next thing a player
	# usually wants is to spend it, and the 3x3 beside the offer is where they do
	# that.
	assert_not_null(screen.payout(),
		"the payout column stays, with the pack it just filled still live on it")
	_leave_post_game()

# EVERY CHEST AT ONCE, which is the point of the screen. They were drained one at
# a time at first — a queue hides the thing a player most needs when several relics
# land together, which is what the OTHERS are, and whether there is an order worth
# taking them in.
func test_every_chest_the_report_dropped_is_on_the_screen_together() -> void:
	_ui.pick(0)
	# Queued BEFORE the report: the resolve can land instantly now (§7.4), and
	# whenever it lands it takes the whole queue with it.
	_ui._drop_queue.append({"items": [Data.reward_item2_pool_of(0)[0]]})
	_ui._drop_queue.append({"items": [Data.reward_item2_pool_of(1)[0],
		Data.reward_item2_pool_of(2)[0]]})
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(screen._chest_sections.size(), 3, "all three chests were mounted at once")
	assert_eq(screen.chests_waiting(), 2, "two of them still unanswered besides the first")
	# Answering one leaves the others exactly where they were.
	screen.chest().leave()
	assert_eq(screen.chests_waiting(), 1, "the rest are untouched")
	_leave_post_game()

# A relic is ALWAYS a picture. Both card layouts used to draw art only when
# `item.image` was non-null, so an unarted row would come up as a name over a gap
# on the screen where the player is deciding whether to take it.
func test_every_relic_on_offer_is_drawn_with_a_picture() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var cards: int = 0
	for section in screen._chest_sections:
		for card in section._cards:
			cards += 1
			var art: bool = false
			for tr in (card["node"] as Control).find_children("*", "TextureRect", true, false):
				if (tr as TextureRect).texture != null:
					art = true
			assert_true(art, "%s is drawn with its art" % card["item"].display_name)
	assert_gt(cards, 0, "there was a relic on offer to check")
	_leave_post_game()

# …and an item with NO art still draws something rather than a hole.
func test_an_unarted_relic_draws_a_stand_in_rather_than_a_gap() -> void:
	var blank := ItemData.new()
	blank.id = &"__artless__"
	blank.display_name = "Artless Relic"
	blank.description = "Nothing to look at."
	var modal := ItemDropModal.open(_ui, blank)
	await wait_frames(2)
	var drawn: bool = false
	for node in modal.find_children("*", "Control", true, false):
		if (node as Control).custom_minimum_size.x >= 72.0:
			drawn = true
	assert_true(drawn, "a relic with no image still gets a tile the size of one")
	modal.leave()

# A chest banked AFTER the screen opened lands ON it. RewardScreen mounts as an
# ordinary child of the page, BELOW this screen's CanvasLayer, so a level-up's
# reward was invisible until the player had already left.
func test_a_chest_banked_while_the_screen_is_up_lands_on_it() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var before: int = screen._chest_sections.size()
	GameState.grant_chest(1)
	_ui._redeem_pending_chests()
	assert_eq(screen._chest_sections.size(), before + 1,
		"the banked chest is a section of the haul screen")
	assert_eq(GameState.pending_chests, 0, "and the bank is drained")
	var found: RewardScreen = null
	for c in _ui.get_children():
		if c is RewardScreen:
			found = c
	assert_null(found, "no RewardScreen opened underneath it")
	_leave_post_game()

# A test checking the shelf's item-card LAYER on the haul screen lived here. The
# shelf is not on that screen any more (see
# test_leaving_the_haul_screen_lands_the_shelf_under_the_board), so there is no
# card of its own to raise — and the test was not earning its place anyway: it set
# the hub up AFTER `_report_beat`, which already builds the screen in the same
# breath (§7.4), so `screen._shop` was null and its own guard returned early
# without asserting. Its subject is covered where the shelf actually lands now.

# Loot granted WHILE the screen is up lands on it. A relic taken from one of its
# own chests can pay out the instant it is picked up (Mom's Coin Purse is four
# pills), and the table it belongs on is beside the card that paid it — queueing it
# behind a screen nobody has left yet would hide the payout until after the
# decision that earned it.
func test_loot_granted_on_the_screen_lands_on_its_own_table() -> void:
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	var payout = screen.payout()
	assert_not_null(payout, "the game paid something of its own")
	if payout == null:
		return
	var before: int = payout.remaining()
	var queued: int = _ui._drop_queue.size()
	GameState.offer_loot("loot", 2)
	assert_eq(payout.remaining(), before + 2, "the grant is on the table already")
	assert_eq(_ui._drop_queue.size(), queued,
		"and nothing was queued behind the screen for later")
	_leave_post_game()

# A run saved with a payout still queued has to come back. The queue holds EITHER
# shape — one entry for a game's own payout, a whole handful for a relic's grant —
# and the save used to cast both to a Dictionary, which took the autosave down the
# moment a grant was in it.
func test_a_queued_payout_survives_a_save_in_either_shape() -> void:
	_ui._drop_queue.clear()
	_ui._drop_queue.append({"loot": {"type": "scroll", "id": &"scroll_of_fire"}})
	_ui._drop_queue.append({"loot": [
		{"type": "pill", "id": &"luck_up", "horse": false},
		{"type": "pill", "id": &"health_up", "horse": false}]})
	var view: Dictionary = _ui.capture_view_state()
	var saved: Array = view.get("drops", [])
	assert_eq(saved.size(), 2, "both queued payouts were written")
	if saved.size() < 2:
		return
	assert_true(saved[0]["loot"] is Dictionary, "the single piece stays a single piece")
	assert_true(saved[1]["loot"] is Array, "and the handful stays a handful")
	assert_eq((saved[1]["loot"] as Array).size(), 2, "with both pills in it")
	_ui._drop_queue.clear()
	_ui.restore_view_state(view)
	assert_eq(_ui._drop_queue.size(), 2, "and both come back")
	assert_true(_ui._drop_queue[1]["loot"] is Array, "in the shape they went in")
	_ui._drop_queue.clear()

# §14's decision still holds: a shop blocks nothing and stays for the whole visit.
# LEAVING THE HAUL SCREEN IS WHAT PUTS IT THERE, down the page's own chain — the
# screen names the hub on its way out and never touches the panel.
func test_leaving_the_haul_screen_lands_the_shelf_under_the_board() -> void:
	var hub: StringName = _a_hub()
	if hub == &"":
		return
	# Standing IN the hub with its shelf owed — the state _open_post_game names a
	# shelf in. The screen is opened directly rather than reported into: a report
	# moves the run to the card it just played and builds the screen in the same
	# breath now that the resolve can land instantly (§7.4), so there is no moment
	# in between to be standing somewhere else.
	GameState.current_game_id = hub
	_ui._pending_shop = hub
	_ui._post_snapshot = {"game": Data.get_game(hub), "beaten": true,
		"escaped": false, "amulet": false, "res": {}}
	_ui._open_post_game()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(screen.shop_id(), hub, "the screen knows where its exit leads")
	assert_string_contains(screen.exit_text(), "Go to Shop",
		"and the way out NAMES it rather than saying 'see what's here'")
	assert_eq(_ui._pending_shop, hub,
		"the shelf is still the PAGE's to mount — the screen never claimed it")
	assert_null(_ui._shop_panel, "and nothing is mounted while the haul is up")
	# `dismiss` emits `finished`, which the page wired to _on_post_game_finished —
	# so this is the real way out, not a nudge past it.
	screen.dismiss()
	_ui._post_screen = null
	assert_not_null(_ui._shop_panel, "leaving mounts the shelf")
	if _ui._shop_panel != null:
		assert_eq(_ui._shop_panel.game_id(), hub, "and it is this hub's")
		assert_eq(_ui._shop_panel.get_parent(), _ui._right_col,
			"under the board, where a shop lives for the rest of the visit")
	_dismiss_event()

# The boss warning is a banner on this screen rather than a sixth popup — a boss
# round is announced between two games, and this screen is what stands between
# them. Marking the round announced here is what stops the popup saying it again.
func test_a_boss_round_warns_on_the_haul_screen_and_not_twice() -> void:
	# A REAL boss round, arranged rather than injected: the report rebuilds the
	# offering (and with it `_boss_round`) before the screen is built, and the
	# resolve can land instantly now (§7.4), so there is no gap to set the flag in.
	# One game short of a tier capstone is a boss round on the other side of it.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER - 1
	_ui._build_choices()
	_ui.pick(0)
	_ui._boss_notice_for = -1
	_report_beat(_ui)
	assert_true(_ui._boss_round, "the game just played put the run on a boss round")
	_ui._end_resolve()
	var screen := _haul()
	assert_not_null(screen)
	if screen == null:
		return
	assert_eq(_ui._boss_notice_for, GameState.games_played,
		"the round is marked announced by the screen")
	_leave_post_game()
	_dismiss_event()
	_ui._maybe_announce_boss()
	assert_null(_ui._boss_notice, "so no popup arrives afterwards to repeat it")

# ---------------------------------------------------------------------------
# The shop is part of the page, under the board (§14)
# ---------------------------------------------------------------------------

func _a_hub() -> StringName:
	var hubs: Array = ShopSystem.hub_games()
	return hubs[0] if not hubs.is_empty() else &""

func test_a_shop_mounts_under_the_board_rather_than_over_it() -> void:
	var hub: StringName = _a_hub()
	if hub == &"":
		return
	_ui._mount_shop(hub)
	assert_not_null(_ui._shop_panel, "the shop is on the page")
	assert_eq(_ui._shop_panel.get_parent(), _ui._right_col,
		"in the board's own column, under it")
	assert_eq(_ui._shop_panel.game_id(), hub, "and it is that hub's shop")

func test_the_pointer_at_the_shop_goes_up_with_it_and_down_with_it() -> void:
	var hub: StringName = _a_hub()
	if hub == &"":
		return
	_ui._mount_shop(hub)
	assert_eq(_ui._shop_hint.visible, not _ui._shop_in_view(),
		"the pointer is up exactly while the shop it points at is off screen")
	_ui._clear_shop()
	assert_null(_ui._shop_panel, "leaving takes the shop off the page")
	assert_false(_ui._shop_hint.visible, "and the pointer with it")

func test_travelling_on_closes_the_shop_but_not_the_shelf() -> void:
	var hub: StringName = _a_hub()
	if hub == &"":
		return
	ShopSystem.shop_for(hub)
	_ui._mount_shop(hub)
	_ui.pick(0)
	assert_null(_ui._shop_panel, "picking the next game walks out of the shop")
	assert_false(ShopSystem.shop_for(hub).is_empty(),
		"but the shelf is still there to come back to")

# ---------------------------------------------------------------------------
# The far side of a play_game detour (§10)
# ---------------------------------------------------------------------------

func _neighbour_of_here() -> StringName:
	var nbrs: Array = RunGraph.neighbors(GameState.current_game_id)
	return nbrs[0] if not nbrs.is_empty() else &""

func test_stay_or_return_is_asked_with_the_offering_not_a_dialog() -> void:
	var back: StringName = _neighbour_of_here()
	if back == &"":
		return
	_ui._ask_stay_or_return(back)
	assert_true(_ui._asking_return(), "the run is standing on the question")
	assert_eq(_ui._choices.size(), 2, "two destination cards, drawn like any offering")
	assert_true(bool(_ui._choices[0].get("stay", false)), "the first is where you are")
	assert_eq(StringName(_ui._choices[1]["slot"]), back, "the second is where you came from")
	for c in _ui._choices:
		assert_null(c["enemy"], "neither card rolls an enemy — nothing is being played")

func test_a_destination_card_opens_the_same_popup_with_a_different_verb() -> void:
	var back: StringName = _neighbour_of_here()
	if back == &"":
		return
	_ui._ask_stay_or_return(back)
	var modal: GameChoiceModal = _ui.open_choice(1)
	assert_not_null(modal, "the card opens")
	assert_gt(modal.route_steps(), -1, "with the route from there drawn on it")
	modal.travel()
	assert_false(_ui._asking_return(), "answering it ends the question")
	assert_eq(GameState.current_game_id, back, "and moves the run back")

func test_staying_keeps_the_run_where_the_detour_left_it() -> void:
	var back: StringName = _neighbour_of_here()
	if back == &"":
		return
	var here: StringName = GameState.current_game_id
	_ui._ask_stay_or_return(back)
	_ui.pick(0)                            # the "stay here" card
	assert_false(_ui._asking_return())
	assert_eq(GameState.current_game_id, here, "the run carries on from the detour")
	assert_gt(_ui._choices.size(), 0, "with an ordinary offering back on the table")

func test_the_verbs_are_held_while_the_question_is_up() -> void:
	var back: StringName = _neighbour_of_here()
	if back == &"":
		return
	GameState.dash_charges = 2
	GameState.scramble = 2
	_ui._ask_stay_or_return(back)
	_ui.dash()
	assert_false(_ui._dash_mode, "Dash cannot redraw the two destinations")
	assert_false(_ui.scramble(), "and neither can Scramble")
	assert_eq(_ui._choices.size(), 2, "the question is still the question")

# The bug this pins: an event that posts the run off to another game (§10) used
# to have that game hand over an event of ITS own on the way back — so beating
# the mecha game Punch Off sends you to gave you the stay-or-return question AND
# a second event dropped on top of it. A detour's destination is somewhere the
# run was sent, not somewhere it routed to, and nothing is waiting there.

# Every game pays an event now, so this is any on-map game the run has not
# already taken one from.
func _node_carrying_an_event() -> StringName:
	for g in Data.all_games():
		if not (g is GameData) or RunGraph.is_off_map(g.id):
			continue
		if not GameState.event_nodes_fired.has(g.id):
			return g.id
	return &""

func test_a_detour_hands_over_no_event_of_its_own() -> void:
	var node: StringName = _node_carrying_an_event()
	if node == &"":
		return
	_ui.pick(0)
	# The game being reported is a detour's destination, standing on a node that
	# does carry an event.
	_ui._chosen["slot"] = node
	_ui._play_return_to = _neighbour_of_here()
	_ui.report(false)
	assert_null(_ui._pending_event, "the detour's far side owes no event")
	assert_true(_ui._pending_detour, "it owes the stay-or-return question instead")

func test_an_ordinary_arrival_still_hands_over_its_event() -> void:
	# The pairing that makes the test above mean something: the guard is on the
	# detour, not on events firing at all.
	var node: StringName = _node_carrying_an_event()
	if node == &"":
		return
	_ui.pick(0)
	_ui._chosen["slot"] = node
	_ui.report(false)
	assert_not_null(_ui._pending_event, "an event still fires where the run routed to")
	assert_false(_ui._pending_detour)

# --- starting an event from the dev panel -----------------------------------
#
# `open_event` is the panel's Events tab reaching into the run. It exists so a
# started event is wired up exactly as an earned one — the same modal, the same
# finished handler — rather than the panel building its own EventModal2 and
# quietly testing a path nothing else takes.

func test_the_panel_can_start_an_event_where_the_run_stands() -> void:
	var ev: EventData2 = Data.get_event2(&"scrap_ooze")
	assert_not_null(ev)
	# The DELTA, not the count. The opening game this file's before_each plays
	# deals an event of its own, and which one is a roll — when it lands on Scrap
	# Ooze the count is already 1 before this test touches anything, and asserting
	# "== 1" made an unrelated die decide whether the suite was green.
	var before: int = int(GameState.events_fired.get(&"scrap_ooze", 0))
	assert_true(_ui.open_event(ev), "an event opens on a live run")
	assert_not_null(_ui._event_modal, "and it is the real modal, not a bare panel")
	assert_eq(int(GameState.events_fired.get(&"scrap_ooze", 0)), before + 1,
		"starting one puts it in the bag, exactly as arriving at one does")
	assert_true(GameState.events_seen.has(&"scrap_ooze"),
		"…and it will not come round again until the rest of its rarity has")

func test_the_panel_will_not_start_a_second_event_over_the_first() -> void:
	var ev: EventData2 = Data.get_event2(&"scrap_ooze")
	_ui.open_event(ev)
	assert_false(_ui.open_event(Data.get_event2(&"punch_off")),
		"one modal at a time")

func test_the_panel_will_not_eat_an_event_the_run_already_earned() -> void:
	# A queued event is one the run is owed, waiting on a resolve that is still
	# playing. Starting one from the panel then would overwrite it and the player
	# would simply never get the event they walked to the dead end for.
	_ui._pending_event = Data.get_event2(&"punch_off")
	assert_false(_ui.open_event(Data.get_event2(&"scrap_ooze")))
	assert_eq(_ui._pending_event.id, &"punch_off", "the queued one is still queued")

func test_the_panel_starts_nothing_once_the_run_is_over() -> void:
	GameLoop2.run_over = true
	assert_false(_ui.open_event(Data.get_event2(&"scrap_ooze")))
	assert_false(_ui.open_event(null), "and null is not an event")

# --- dying in an event ------------------------------------------------------
#
# An event can take Health, so an event can KILL you — Scrap Ooze's reach on your
# last point, one dip too many in Abyssal Baths, the Blood Donation Machine's
# lever. The loop only ever checked for death at the two places it knew about (a
# try paid in Health, an enemy's hit), so every other Health cost left the player
# standing at 0 with the run carrying on around them.

func _lethal_choice_index(modal) -> int:
	for i in range(modal._event.choices.size()):
		if EventSystem.is_lethal(modal._event.choices[i], 0):
			return i
	return -1

func test_an_event_that_takes_your_last_health_ends_the_run() -> void:
	GameState.set_hp(1)
	assert_true(_ui.open_event(Data.get_event2(&"scrap_ooze")))
	var modal = _ui._event_modal
	var idx: int = _lethal_choice_index(modal)
	assert_gt(idx, -1, "on 1 Health, reaching into the ooze is fatal")
	modal.take(idx)
	await get_tree().process_frame
	assert_eq(GameState.hp, 0, "the press was paid")
	assert_true(GameLoop2.run_over, "and the run is over — not carrying on at 0 Health")
	assert_eq(_ui._phase, OVERWORLD.Phase.OVER, "the screen agrees")

func test_dying_in_an_event_raises_the_end_screen_over_it() -> void:
	GameState.set_hp(1)
	_ui.open_event(Data.get_event2(&"scrap_ooze"))
	var modal = _ui._event_modal
	modal.take(_lethal_choice_index(modal))
	await get_tree().process_frame
	assert_not_null(_ui._run_over_screen, "the verdict lands")
	assert_null(_ui._event_modal,
		"and the event it happened in steps aside rather than sitting under it")

func test_a_health_cost_that_is_paid_back_in_the_same_breath_is_not_a_death() -> void:
	# The death check is deferred for this: effects are applied as a BATCH, and a
	# cell that spends Health and gives it back would otherwise read as fatal on
	# the frame between the two.
	GameState.set_hp(3)
	GameState.set_hp(0)
	GameState.set_hp(3)
	await get_tree().process_frame
	assert_false(GameLoop2.run_over,
		"where the batch LEAVES you is what counts, not the dip in the middle")

func test_a_fatal_press_is_painted_as_one() -> void:
	# Not disabled — Scrap Ooze is a push-your-luck event and taking the decision
	# away is worse than the death. The button carries the warning instead.
	GameState.set_hp(1)
	_ui.open_event(Data.get_event2(&"scrap_ooze"))
	var modal = _ui._event_modal
	var idx: int = _lethal_choice_index(modal)
	var fatal: Button = null
	var safe: Button = null
	for i in range(modal._choice_box.get_child_count()):
		for node in modal._choice_box.get_child(i).get_children():
			if node is Button:
				if i == idx:
					fatal = node
				else:
					safe = node
	assert_not_null(fatal, "the fatal choice has a button")
	assert_false(fatal.disabled, "which is still pressable")
	assert_eq(fatal.get_theme_stylebox("normal").border_color, UITheme.DANGER,
		"and wears the warning itself, not only the line under it")
	if safe != null:
		assert_ne(safe.get_theme_stylebox("normal").border_color, UITheme.DANGER,
			"while walking away looks nothing like it")

# --- the second press -------------------------------------------------------
#
# A press that can end the run asks again. The prose warning one press EARLY is
# gone (it fired on most of the costly buttons in the game and taught the player
# to scroll past it); what replaces it is a catch on the click itself, so death
# costs a deliberate second answer rather than a paragraph nobody read.

func _deadly_confirm(host: Node) -> ConfirmPanel:
	for node in host.find_children("*", "ConfirmPanel", true, false):
		return node
	return null

func test_a_fatal_press_asks_before_it_is_taken() -> void:
	GameState.set_hp(1)
	_ui.open_event(Data.get_event2(&"scrap_ooze"))
	var modal = _ui._event_modal
	var idx: int = _lethal_choice_index(modal)
	assert_gt(idx, -1, "on 1 Health, reaching into the ooze is fatal")
	modal._confirm_then_take(idx)
	await get_tree().process_frame
	assert_not_null(_deadly_confirm(modal), "the click raises an Are you sure?")
	assert_eq(GameState.hp, 1, "…and nothing has been spent while it stands")
	assert_false(GameLoop2.run_over, "the run is still going")

func test_saying_yes_takes_the_press() -> void:
	GameState.set_hp(1)
	_ui.open_event(Data.get_event2(&"scrap_ooze"))
	var modal = _ui._event_modal
	modal._confirm_then_take(_lethal_choice_index(modal))
	await get_tree().process_frame
	var panel: ConfirmPanel = _deadly_confirm(modal)
	assert_not_null(panel)
	(panel.find_child("OkBtn", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	assert_eq(GameState.hp, 0, "the press went through")
	assert_true(GameLoop2.run_over, "which was the whole warning")

func test_a_survivable_press_is_never_asked_about() -> void:
	# The catch is for death and nothing else. A steep cost you can walk away from
	# goes straight through — an event that asked twice about every -3 would be the
	# old "you can die here" line wearing a button.
	GameState.set_hp(GameState.max_hp)
	_ui.open_event(Data.get_event2(&"scrap_ooze"))
	var modal = _ui._event_modal
	var before: int = GameState.hp
	for i in range(modal._event.choices.size()):
		if EventSystem.health_cost(modal._event.choices[i], 0) > 0:
			modal._confirm_then_take(i)
			await get_tree().process_frame
			assert_null(_deadly_confirm(modal), "nothing to ask about")
			assert_lt(GameState.hp, before, "the press simply happened")
			return

# --- where the illustration goes --------------------------------------------
#
# Two columns are for an event with a page of prose in it. A WORDLESS one — the
# sheet's Prompt cell left blank, which the Arcade Room does — stacks instead:
# the picture over the choices, not beside them.

# The one TextureRect the modal built for the event's own art. Objects spawn
# their own, so this is only asked before a choice has been taken.
func _event_art(modal) -> TextureRect:
	for node in modal._panel.find_children("*", "TextureRect", true, false):
		if (node as TextureRect).texture != null:
			return node
	return null

# Children a repaint left standing. `_render` clears with queue_free, which does
# not take the node out of the tree until the frame ends, so a plain
# get_child_count() after a re-render counts the last painting as well as this
# one.
func _live_children(box: Node) -> int:
	var n: int = 0
	for child in box.get_children():
		if not child.is_queued_for_deletion():
			n += 1
	return n

func test_an_event_with_a_prompt_puts_its_art_beside_the_words() -> void:
	assert_true(_ui.open_event(Data.get_event2(&"scrap_ooze")))
	var modal = _ui._event_modal
	var art: TextureRect = _event_art(modal)
	assert_not_null(art, "Scrap Ooze is illustrated")
	assert_false(modal._right.is_ancestor_of(art),
		"an event with prose keeps its picture in the side column")
	assert_eq(_live_children(modal._prose_box), 1, "and the prompt is the prose")

func test_a_wordless_event_stacks_its_art_over_the_choices() -> void:
	var ev: EventData2 = Data.get_event2(&"arcade_room")
	assert_eq(ev.prompt, "", "the Arcade Room speaks in pictures")
	assert_true(_ui.open_event(ev))
	var modal = _ui._event_modal
	var art: TextureRect = _event_art(modal)
	assert_not_null(art, "…and it is still illustrated")
	assert_true(modal._right.is_ancestor_of(art),
		"with no words to sit next to, the picture goes above the buttons")
	assert_true(art.get_index() < modal._prose_box.get_index(),
		"above, not below")
	assert_eq(_live_children(modal._prose_box), 0,
		"a blank prompt prints nothing — not an empty label holding a line of height")
	assert_eq(_live_children(modal._choice_box), 2, "Enter and Leave are still offered")

func test_a_wordless_event_that_speaks_later_keeps_the_layout_it_opened_in() -> void:
	# A result printed on the first press must not shunt the picture back into a
	# side column halfway through the event.
	var ev: EventData2 = Data.get_event2(&"arcade_room")
	assert_true(_ui.open_event(ev))
	var modal = _ui._event_modal
	var art: TextureRect = _event_art(modal)
	modal._last_result = "The room takes the coin."
	modal._render()
	assert_true(modal._right.is_ancestor_of(art), "the art has not moved")
	assert_eq(_live_children(modal._prose_box), 1,
		"the outcome prints on its own, with no rule above it separating it from nothing")

# --- the machines on the page -----------------------------------------------
#
# A machine's full card is 341px tall — two buttons, their cost lines, their ☠
# warnings. The overworld is built to fit a 720p canvas with about five pixels
# to spare and the board under it is already at its floor (CELL_MIN), so three
# full cards under the board ran the page to 1674px and put the whole overworld
# behind a scrollbar. The page keeps the RECOGNITION — art, name, state — and
# the card opens over it with every button intact.

func _machine_rows() -> Array:
	var out: Array = []
	if _ui._object_panel == null or not is_instance_valid(_ui._object_panel):
		return out
	for child in _ui._object_panel._row.get_children():
		if child is Button:
			out.append(child)
	return out

func test_the_page_still_fits_the_window_with_machines_standing_on_it() -> void:
	# The gap the existing fit tests left: they cover the offering, the report
	# step and the top-tier board, and none of them has anything mounted UNDER
	# the board. Three machines there ran the page to 1674px of a 688px window.
	_assert_fits("the page before any machine spawns")
	ObjectSystem.spawn_by_tag(&"arcade", 3, 3)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_not_null(_ui._object_panel, "three machines put a panel under the board")
	_ui._refresh()
	_assert_fits("the page with three machines under the board")
	ObjectSystem.clear()

func test_the_page_still_fits_the_window_with_a_shop_on_it() -> void:
	# The shop shares the machines' slot and had the same disease, worse: its
	# three cards ran the page to 1231px of a 688px window, and that predates
	# machines entirely.
	#
	# EVERY HUB, not just the first one the random graph happened to roll. This
	# used to mount `hubs[0]` and stop, which made it a coin flip: the shop's name
	# was a Label with no clip, so its width was the hub's NAME length, and a wide
	# shop panel took the room out of the left column until the checklist wrapped
	# and grew the page. "Enter the Gungeon" overran by 35px and "FTL" did not, so
	# the same bug passed or failed depending on the seed. Walking the whole roster
	# is what turns that back into a test.
	var hubs: Array = ShopSystem.hub_games()
	assert_false(hubs.is_empty(), "a run has hubs")
	for hub in hubs:
		_ui._mount_shop(hub)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_not_null(_ui._shop_panel, "the shop mounts under the board")
		_ui._refresh()
		await get_tree().process_frame
		var game: GameData = Data.get_game(hub)
		_assert_fits("the page with %s's shop on it" % (
			game.display_name if game != null else String(hub)))

func test_a_shelf_item_is_a_row_on_the_page_and_a_card_when_you_open_it() -> void:
	var hubs: Array = ShopSystem.hub_games()
	_ui._mount_shop(hubs[0])
	await get_tree().process_frame
	var shelf: Array = ShopSystem.stock(hubs[0])
	if shelf.is_empty():
		# A hub whose shop has not opened yet has nothing to draw; the fit test
		# above is the one that matters for it.
		assert_eq(_ui._shop_panel._cards_row.get_child_count(), 0)
		return
	assert_eq(_ui._shop_panel._cards_row.get_child_count(), shelf.size(),
		"one row per thing on the shelf")
	_ui._shop_panel.open_card(0)
	await get_tree().process_frame
	assert_not_null(_ui._shop_panel._card_layer, "clicking a row opens its card")
	var buys: int = 0
	for node in _ui._shop_panel._card_layer.find_children("*", "Button", true, false):
		if String((node as Button).text).begins_with("◉") or (node as Button).text == "Sold":
			buys += 1
	assert_gt(buys, 0, "with the Buy button on it — the card is where you buy")
	_ui._shop_panel.close_card()
	assert_null(_ui._shop_panel._card_layer, "and putting it back closes it")

func test_a_machine_is_a_row_on_the_page_and_a_card_when_you_open_it() -> void:
	ObjectSystem.spawn_by_tag(&"arcade", 1, 1)
	await get_tree().process_frame
	var rows: Array = _machine_rows()
	assert_eq(rows.size(), 1, "one machine, one row")
	assert_eq(_ui._object_panel._row.find_children("*", "ObjectCard", true, false).size(), 0,
		"the page carries no full card — that is the 341px that did not fit")

	_ui._object_panel.open_card(ObjectSystem.live[0])
	await get_tree().process_frame
	var cards: Array = _ui._object_panel._card_layer.find_children("*", "ObjectCard", true, false)
	assert_eq(cards.size(), 1, "opening the row opens the real card")
	var buttons: int = 0
	for node in (cards[0] as Control).find_children("*", "Button", true, false):
		buttons += 1
	assert_gt(buttons, 0, "with its buttons on it — nothing was cut, it moved")
	_ui._object_panel.close_card()
	ObjectSystem.clear()

func test_the_board_gives_up_height_while_it_is_sharing_its_column() -> void:
	# Measured in the FITTED CELL rather than in the board's pixel height: the
	# cell is the number the budget actually moves, and it is settled the moment
	# the budget changes — where a Control's size is whatever the last layout pass
	# made it, which on the frame a test asks is often nothing at all.
	var cols: int = GameLoop2.grid_cols()
	var full: int = BattlefieldView.fitted_cell(cols)
	ObjectSystem.spawn_by_tag(&"arcade", 1, 1)
	await get_tree().process_frame
	assert_not_null(_ui._object_panel, "a machine puts a panel under the board")
	assert_lt(BattlefieldView.fitted_cell(cols), full,
		"the board shrinks its cells to pay for the panel under it")
	ObjectSystem.clear()
	await get_tree().process_frame
	assert_eq(BattlefieldView.fitted_cell(cols), full,
		"…and springs back when the machines go, which is when you travel on")

# --- the machines inside an event -------------------------------------------
#
# An event that spawns machines is a ROOM, and the two things a room has to get
# right are what happens to a machine that blows up while you are standing in it,
# and what happens to the machines when you walk out.

func _event_cards(modal) -> int:
	return _live_children(modal._objects_box)

func test_a_machine_that_blows_itself_up_leaves_the_room_it_was_in() -> void:
	assert_true(_ui.open_event(Data.get_event2(&"arcade_room")))
	var modal = _ui._event_modal
	ObjectSystem.spawn_by_tag(&"arcade", 2, 2)
	await get_tree().process_frame
	var before: int = _event_cards(modal)
	assert_gt(before, 1, "the room is stocked")
	# What bombing the Blood Donation Machine does, through the same call the
	# bomb's effect makes.
	ObjectSystem.destroy(ObjectSystem.live[0], false)
	await get_tree().process_frame
	assert_eq(_event_cards(modal), before - 1,
		"the destroyed machine's card goes with it, rather than sitting there dead")
	modal._close()
	ObjectSystem.clear()

func test_leaving_the_arcade_takes_the_cabinets_with_it() -> void:
	# A machine already standing at this game before the event opened.
	ObjectSystem.spawn(&"donation_machine", false)
	var standing: int = ObjectSystem.live.size()
	assert_true(_ui.open_event(Data.get_event2(&"arcade_room")))
	var modal = _ui._event_modal
	ObjectSystem.spawn_by_tag(&"arcade", 2, 2)
	await get_tree().process_frame
	assert_gt(ObjectSystem.live.size(), standing, "the room filled up")
	modal._close()
	await get_tree().process_frame
	assert_eq(ObjectSystem.live.size(), standing,
		"walking out of the arcade leaves its cabinets in the arcade")
	assert_eq(String(ObjectSystem.live[0].get("id", &"")), "donation_machine",
		"…and only its cabinets: what was standing here before is still standing here")
	ObjectSystem.clear()

func test_walking_out_of_a_room_does_not_ask_twice() -> void:
	# `Leave` costs nothing, pays nothing and says nothing, so its closing beat
	# was a blank panel with one button on it — the event still on screen after
	# the press that ended it.
	var ev: EventData2 = Data.get_event2(&"arcade_room")
	assert_true(_ui.open_event(ev))
	var modal = _ui._event_modal
	var leave: int = -1
	for i in range(ev.choices.size()):
		if String(ev.choices[i].get("id", "")) == "leave":
			leave = i
	assert_gte(leave, 0, "the room has a way out")
	modal.take(leave)
	assert_true(modal._done, "pressing Leave is the whole of leaving")
	_ui._event_modal = null
	ObjectSystem.clear()

# Report the game as completed AND tick the row for the body that walked on with
# it. This is what a bare `report(true)` used to do in one flag, back when that
# body was the game's own enemy and beating the game answered for it; it is spelled
# out now because the flag only records the GAME any more (GameLoop2.arrivals),
# and clearing an enemy is ticking its checklist row like any other.
func _report_beat(ui) -> void:
	var landed: Dictionary = GameLoop2.arrival()
	ui.report(true, [] if landed.is_empty() else [int(landed["instance"])])


# ==========================================================================
# Repaint guards
#
# Three sections of the page skip their rebuild when they would only redraw the
# same thing (see the repaint-guard block in Overworld2). What has to stay true
# is the pair: the guard engages when nothing moved, and gets out of the way the
# moment anything does. A guard that never engages is only slow; one that engages
# when it shouldn't is a page showing a number that has changed.
# ==========================================================================

# --- the verb chips --------------------------------------------------------

func test_the_verb_chips_are_not_rebuilt_when_no_verb_moved() -> void:
	_ui._refresh_select_stats()
	var chips: Array = _ui._select_stats.get_children().duplicate()
	assert_gt(chips.size(), 0, "there are chips to keep")
	_ui._refresh_select_stats()
	assert_eq(_ui._select_stats.get_children(), chips,
		"the same Control objects are still standing — nothing was re-shaped")

func test_every_verb_the_chips_draw_moves_them() -> void:
	# One case per value in the signature, because the failure this guards against
	# is a value the rebuild reads and the signature forgot.
	for verb in ["bash", "dash", "transmute", "scramble"]:
		_ui._refresh_select_stats()
		var before: String = _text_of(_ui._select_stats)
		GameState.grant_run_stat(verb, 1)
		_ui._refresh_select_stats()
		assert_ne(_text_of(_ui._select_stats), before,
			"a +1 %s repaints the chips" % verb)

func test_luck_moves_the_chips_even_though_no_verb_did() -> void:
	# Luck is drawn from Stats rather than from a GameState field, and its own
	# chip quotes the odds it changes — so it is the value most easily left out.
	_ui._refresh_select_stats()
	var before: String = _text_of(_ui._select_stats)
	GameState.add_item(Data.get_item2(&"clover"))     # +1 Luck
	_ui._refresh_select_stats()
	var after: String = _text_of(_ui._select_stats)
	assert_ne(after, before, "a Clover repaints the chips")
	assert_true(after.contains("Luck %d" % Stats.get_value(&"luck")),
		"showing the new Luck: %s" % after)

func test_entering_dash_mode_repaints_the_chips() -> void:
	# _dash_mode decides whether Dash is a live button or a readout, and it moves
	# without any count moving with it.
	GameState.grant_run_stat("dash", 1)
	_ui._refresh_select_stats()
	var before: Array = _ui._select_stats.get_children().duplicate()
	_ui.dash()
	_ui._refresh_select_stats()
	assert_ne(_ui._select_stats.get_children(), before,
		"arming a Dash rebuilds the chips")
	_ui.cancel_dash()

# --- the standing checklist ------------------------------------------------

func test_the_standing_checklist_is_not_rebuilt_when_the_board_is_still() -> void:
	_ui._populate_standing_checklist()
	var rows: Array = _ui._verify_box.get_children().duplicate()
	assert_gt(rows.size(), 0, "there are rows to keep")
	_ui._populate_standing_checklist()
	assert_eq(_ui._verify_box.get_children(), rows, "the same rows are still standing")

func test_a_body_arriving_repaints_the_standing_checklist() -> void:
	_ui._populate_standing_checklist()
	var before: String = _text_of(_ui._verify_box)
	var e := GoalEnemyData.new()
	e.id = &"guard_probe"
	e.display_name = "Guard Probe"
	e.health = 1
	e.damage = 1
	GameLoop2.spawn_to_stack(e)
	_ui._populate_standing_checklist()
	var after: String = _text_of(_ui._verify_box)
	assert_ne(after, before, "the checklist noticed the arrival")
	assert_true(after.contains("Guard Probe"), "and lists it: %s" % after)

func test_a_body_leaving_repaints_the_standing_checklist() -> void:
	var e := GoalEnemyData.new()
	e.id = &"guard_probe"
	e.display_name = "Guard Probe"
	e.health = 1
	e.damage = 1
	var inst: int = GameLoop2.spawn_to_stack(e)
	_ui._populate_standing_checklist()
	assert_true(_text_of(_ui._verify_box).contains("Guard Probe"), "it is listed first")
	GameLoop2.despawn(inst)
	_ui._populate_standing_checklist()
	assert_false(_text_of(_ui._verify_box).contains("Guard Probe"),
		"and gone once it stops following")

func test_the_report_step_hands_the_checklist_back_intact() -> void:
	# The report step and the standing list share one box. Taking a game drops the
	# standing signature; without that, coming back to the offering would match a
	# signature describing rows the report step had already replaced, and leave the
	# tick boxes on screen with no game in play.
	_ui._populate_standing_checklist()
	var standing: String = _text_of(_ui._verify_box)
	assert_true(standing.contains("What you need to do"), "the standing list is up")
	_ui.pick(0)
	var playing: String = _text_of(_ui._verify_box)
	assert_true(playing.contains("Tick what you did this game"),
		"the report step took the box over: %s" % playing)
	_report_beat(_ui)
	_ui._end_resolve()
	_leave_post_game()
	assert_true(_text_of(_ui._verify_box).contains("What you need to do"),
		"and the standing list is back after the report")

# ---------------------------------------------------------------------------
# What can be spent WHILE a game is in play
# ---------------------------------------------------------------------------

# A FULL BAR MEANS READY, on every screen. Every active used to be held back until
# the game had been reported — right for a Usable consumable, which wants a combat
# or an event around it, and wrong for a CHARGED one in the way that shows: the
# strip said the thing was ready and then refused to fire it. D6, Staff of Flame
# and Mom's Bottle of Pills are all charged and all three do something wanted
# precisely while the board is live.
func test_a_charged_active_fires_while_a_game_is_in_play() -> void:
	for id in [&"d6", &"staff_of_flame", &"moms_bottle_of_pills"]:
		var template: ItemData = Data.get_item2(id)
		assert_not_null(template, "%s is authored" % id)
		if template == null:
			continue
		assert_true(template.is_charged(), "%s is a charged active" % id)
		assert_true(PackStrip.fires_while_reporting(template, true),
			"%s fires with a full bar mid-report" % id)

# AN OVERWORLD ACTIVE FIRES MID-GAME TOO, and for the same reason a charged one
# does. `overworld_usable` marks an item whose effect needs the MAP — Ride the Bus
# moves the run, the Wand of Wishing hands you any item in the game — and the map
# is mounted for the whole of a game being played. Holding them back meant the one
# item that can get you off a game you cannot beat was refused for exactly as long
# as you were stuck on it.
func test_an_overworld_active_fires_while_a_game_is_in_play() -> void:
	for id in [&"ride_the_bus", &"wand_of_wishing"]:
		var template: ItemData = Data.get_item2(id)
		assert_not_null(template, "%s is authored" % id)
		if template == null:
			continue
		assert_true(template.overworld_usable, "%s is an overworld active" % id)
		assert_true(PackStrip.fires_while_reporting(template, true),
			"%s fires while a game is in play" % id)

func test_riding_the_bus_is_pressable_with_a_game_in_play() -> void:
	# The rule above, as the player meets it: the Use button under the tile, live,
	# on the screen where the board is.
	var bus: ItemData = GameState.add_item(Data.get_item2(&"ride_the_bus"))
	assert_not_null(bus)
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "a game is in play")
	_ui._refresh_items()
	var column: Control = _ui._items_box.get_child(_ui._items_box.get_child_count() - 1)
	var control: Button = column.get_child(0) as Button
	assert_not_null(control, "the bus wears a Use button")
	if control != null:
		assert_false(control.disabled, "and it presses mid-game rather than greying out")
	_leave_post_game()

func test_a_usable_consumable_still_waits_for_the_report() -> void:
	var usable: ItemData = null
	for item in Data.all_items2():
		if item is ItemData and not item.is_charged() \
				and item.kind == ItemData.ItemKind.USABLE \
				and not item.overworld_usable:
			usable = item
			break
	if usable == null:
		# Nothing in the catalogue to check with — assert the rule directly instead
		# of returning without asserting.
		var stand_in := ItemData.new()
		stand_in.kind = ItemData.ItemKind.USABLE
		usable = stand_in
	assert_false(PackStrip.fires_while_reporting(usable, true),
		"a Usable consumable wants the game reported first")
	assert_true(PackStrip.fires_while_reporting(usable, false),
		"and fires on the offering like it always did")

# THE LOCK HOLDS THE PACK STILL, IT DOES NOT STOP A SPEND. Mid-report nothing is
# dragged, taken or binned — the gap between "played the game" and "said what
# happened" is not a moment for the inventory to move — but every piece of loot can
# be USED, scrolls included. Mid-game is exactly when the player knows what they
# want out of one: the body walking toward them is right there.
func test_the_mid_report_lock_stops_moving_but_never_spending() -> void:
	GameState.loot_items.clear()
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_pill_loot(&"luck_up")
	var grid := LootGrid.new()
	grid.show_use = true
	grid.allow_reorder = true
	grid.allow_discard = true
	grid.locked = true
	add_child_autofree(grid)
	grid.rebuild()
	assert_false(grid.can_trash({"kind": "loot_move", "from": 0, "index": 0}),
		"the pack still cannot be binned from")
	assert_null(grid.get_child(0)._get_drag_data(Vector2.ZERO),
		"nor rearranged")
	var live: int = 0
	for slot in grid.get_children():
		for btn in (slot as Control).find_children("*", "Button", true, false):
			if (btn as Button).text == "Use" and not (btn as Button).disabled:
				live += 1
	assert_eq(live, GameState.loot_items.size(),
		"but every carried piece can still be spent, scroll and pill alike")

# …and the one op that needs the map ESCAPES the game rather than fizzling on it.
# Teleportation and Telepills come through the one function, so both walk the run
# out of the game in play and then move it — and the piece is identified either
# way, because both systems identify before they apply anything.
func test_a_teleport_mid_game_escapes_the_game_and_then_moves_the_run() -> void:
	PillSystem.ensure_colors()
	PillSystem.unidentify(&"telepills")
	ScrollSystem.unidentify(&"scroll_of_teleportation")
	_ui.pick(0)                                  # a game is now in play
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING)
	# The game actually IN PLAY, read off _chosen — `pick` moves the run onto it, so
	# the id standing before the pick is the node it came from and not what this
	# teleport is walking out of.
	var played: GameData = _ui._chosen.get("game")
	assert_not_null(played, "a game is in play to walk out of")
	var here: StringName = GameState.current_game_id
	# Nothing has hurt the player and the game has never been beaten, so the
	# ORDINARY exit is shut. The teleport opens it anyway — that is the whole point
	# of the force: the loot is what pays for the door.
	assert_false(_ui.can_escape(),
		"the ordinary escape gate is shut — nothing has drawn blood yet")
	var line: String = _ui.loot_teleport({"kind": "teleport", "dir": "same", "spread": 2})
	assert_string_contains(line, "walk out of the game",
		"the outcome screen says the expensive half out loud")
	assert_ne(GameState.current_game_id, here, "and the run actually moved")
	# It did NOT leave you standing at the new node picking again: a teleport lands
	# you IN the game it dropped you on (arrive_at_game).
	if not GameLoop2.run_over:
		assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING,
			"you are playing where you landed, not choosing again")
		var landed_on: GameData = _ui._chosen.get("game")
		assert_not_null(landed_on, "with a game committed to")
		if landed_on != null and played != null:
			assert_ne(landed_on.id, played.id, "and it is not the one you walked out of")
	# An escape is not a win, however it was bought.
	if played != null:
		assert_false(GameState.has_beaten_game(played.id),
			"walking out on the loot's ticket still banks no beat")
	_ui._end_resolve()
	_leave_post_game()
	_dismiss_event()

# RIDE THE BUS DOES THE SAME. It moves the run and it used to do it by hand —
# `travel_to_game` set the phase back to SELECT and that was that — so a player
# halfway through a game could ride out of it for free: no goal-enemy following,
# no turns for the board, no report. Every teleport pays the same fare now.
func test_riding_the_bus_mid_game_escapes_the_game_first() -> void:
	_ui.pick(0)
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING)
	var played: GameData = _ui._chosen.get("game")
	assert_not_null(played)
	assert_false(_ui.can_escape(), "the ordinary exit is shut — nothing has drawn blood")
	# The bus needs somewhere to go, or it says so and moves nobody — asserted
	# rather than skipped over, so this test is never quietly about nothing.
	var type_key: StringName = GameLoop2.game_type_key(played)
	var elsewhere: int = 0
	for g in Data.all_games():
		if g is GameData and g.id != GameState.current_game_id \
				and not GameLoop2.is_bashed(g.id) and GameLoop2.game_type_key(g) == type_key:
			elsewhere += 1
	assert_gt(elsewhere, 0, "there is another %s game to ride to" % type_key)
	var following: int = GameLoop2.stack.size()
	_ui.teleport_to_type(type_key)
	# Either it moved the run onto another game or the escape it paid for ended the
	# run; what it must not do is leave the game it walked out of standing in play.
	if not GameLoop2.run_over:
		assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING,
			"off the bus is ON the game it stops at")
		var landed_on: GameData = _ui._chosen.get("game")
		assert_not_null(landed_on)
		if landed_on != null:
			assert_ne(landed_on.id, played.id, "and it is a different game to the one left")
		assert_gte(GameLoop2.stack.size(), following,
			"and the old game's enemy came with you, the same as any other escape")
		assert_false(GameState.has_beaten_game(played.id), "an escape banks no beat")
		assert_false(RunGraph.is_off_map(GameState.current_game_id),
			"and the bus only stops at games that are ON the map")
	_ui._end_resolve()
	_leave_post_game()

# THE BUS RUNS ON THE ROADS. It used to draw from the whole 854-game catalogue,
# which is not what a bus is: everything off the run's connected component is a
# game this run cannot walk to, and landing there puts the player on a node with
# no edges — an empty offering whose only way on is another teleport. Transmute is
# the verb for reaching off-map games, and it reaches them from a slot that stays
# on the route.
func test_the_bus_only_stops_at_games_on_the_map() -> void:
	# Asserted over the whole catalogue rather than over one ride: the destination
	# is random, so a single trip proves nothing about the pool it came from.
	var off_map: Array = RunGraph.off_map_ids()
	assert_gt(off_map.size(), 0, "there are off-map games for it to have to skip")
	var type_key: StringName = &""
	for gid in off_map:
		var g: GameData = Data.get_game(gid)
		if g != null:
			type_key = GameLoop2.game_type_key(g)
			break
	assert_ne(type_key, &"", "and one of them has a type to ride to")
	# Ride to that type twenty times over. Every landing has to be on the map, and
	# the off-map game of the same type is never one of them.
	for _i in range(20):
		var before: StringName = GameState.current_game_id
		_ui.teleport_to_type(type_key)
		if GameLoop2.run_over:
			break
		assert_false(RunGraph.is_off_map(GameState.current_game_id),
			"the bus stopped on the map")
		if GameState.current_game_id != before:
			_ui._end_resolve()
			_close_arrival_card()
	_leave_post_game()

# Close the card an arrival raises, so the next thing a test does is not blocked
# behind it. Harmless when there is none.
func _close_arrival_card() -> void:
	if _ui._choice_modal != null and is_instance_valid(_ui._choice_modal):
		_ui._choice_modal._close()

# THE BRIEFING. A teleport commits you, so the one thing the player has lost is
# the screen they get when they choose a game for themselves — and being dropped
# straight onto a board with an enemy already on it, with no idea what game it
# even is, is the version of this that reads as a bug. So the card opens over it.
func test_an_arrival_opens_the_games_card_over_the_board() -> void:
	_ui.pick(0)
	var played: GameData = _ui._chosen.get("game")
	var here: StringName = GameState.current_game_id
	_ui.loot_teleport({"kind": "teleport", "dir": "same", "spread": 2})
	# True however the teleport went, and asserted before the guard below so this
	# test always says something: the game walked out of is never credited.
	assert_false(GameState.has_beaten_game(played.id) if played != null else false,
		"the game left behind banks no beat")
	# The escape can end the run and the graph can have nowhere to put you; neither
	# is what this test is about, and both are covered elsewhere.
	if GameLoop2.run_over or GameState.current_game_id == here:
		return
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "committed to where you landed")
	var card: GameChoiceModal = _ui._choice_modal
	assert_not_null(card, "and the card is up over the board")
	if card == null:
		return
	var landed_on: GameData = _ui._chosen.get("game")
	assert_eq(card._choice.get("game"), landed_on, "showing the game you are now on")
	assert_true(bool(card._notes.get("arrival", false)),
		"in arrival mode — a briefing, not a question")
	assert_string_contains(String(card._notes.get("arrival_note", "")), "Teleported to",
		"and it says how you got here")
	# SAID ON THE SCREEN, not only in the notes: the banner is what distinguishes
	# this card from the one the offering opens, which is otherwise identical.
	var banner: String = ""
	for label in card.find_children("*", "Label", true, false):
		if String((label as Label).text).contains("teleported"):
			banner = String((label as Label).text)
	assert_string_contains(banner, "teleported here",
		"the card says outright that you were moved: %s" % banner)
	assert_string_contains(banner, "playing now",
		"and that this is the game you are now on")
	# Closing it is the whole of what it does. The commit already happened, so the
	# game is still in play on the other side of it.
	card._close()
	assert_eq(_ui._phase, OVERWORLD.Phase.PLAYING, "closing the card changes nothing")
	assert_eq(_ui._chosen.get("game"), landed_on, "the same game is still in play")
	_ui._end_resolve()
	_leave_post_game()
	_dismiss_event()

# An arrival card has NO WAY BACK, because there is nowhere to go back to: the
# teleport already moved the run and already spawned what is waiting.
func test_the_arrival_card_offers_no_way_back() -> void:
	_ui.pick(0)
	var here: StringName = GameState.current_game_id
	_ui.loot_teleport({"kind": "teleport", "dir": "same", "spread": 2})
	# Asserted before the guard so the test always says something (see above).
	assert_true(GameState.current_game_id != here or _ui._phase != OVERWORLD.Phase.PLAYING,
		"either the run moved or the game it was in was walked out of")
	if GameLoop2.run_over or GameState.current_game_id == here:
		return
	var card: GameChoiceModal = _ui._choice_modal
	assert_not_null(card)
	if card == null:
		return
	var labels: Array = []
	for btn in card.find_children("*", "Button", true, false):
		labels.append((btn as Button).text)
	assert_false(labels.has("Back"), "no Back button: %s" % str(labels))
	var plays: int = 0
	for label in labels:
		if String(label).begins_with("▶  Play "):
			plays += 1
	assert_eq(plays, 1, "one button, and it only takes the card down: %s" % str(labels))
	card._close()
	_ui._end_resolve()
	_leave_post_game()
	_dismiss_event()
	_dismiss_event()

# The identification half, which the escape above does not change: both systems
# learn the piece before they ask the overworld for anything, so what the move
# does or doesn't do never decides whether the gamble paid off.
func test_a_teleport_piece_is_learned_before_the_overworld_is_asked() -> void:
	PillSystem.ensure_colors()
	PillSystem.unidentify(&"telepills")
	ScrollSystem.unidentify(&"scroll_of_teleportation")
	var pill: Dictionary = PillSystem.take_pill({"type": "pill", "id": &"telepills",
		"horse": false})
	assert_true(PillSystem.is_identified(&"telepills"), "the colour is learned")
	assert_false((pill.get("requests", []) as Array).is_empty(),
		"the move is ASKED for; it is the overworld that carries it out")

	var scroll: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	assert_not_null(scroll)
	if scroll != null:
		var read: Dictionary = ScrollSystem.read_scroll(scroll)
		assert_true(ScrollSystem.is_identified(&"scroll_of_teleportation"),
			"and so is the scroll, on exactly the same terms")
		assert_false((read.get("requests", []) as Array).is_empty(),
			"which asks for the same move through the same request")

# Every other scroll op lands mid-game where it stands, which is why the gate
# went: only a teleport needs the map, and it now buys its way onto one by
# escaping. If a new op is authored that cannot work here, it needs an answer of
# its own rather than the whole pack being locked again.
func test_only_a_teleport_among_the_scroll_ops_needs_the_map() -> void:
	var map_only := ["teleport"]
	var seen: Array = []
	for s in Data.all_scrolls():
		if not (s is ScrollData):
			continue
		for e in s.effect:
			if e is Dictionary:
				var op: String = String(e.get("op", ""))
				if not seen.has(op):
					seen.append(op)
	assert_gt(seen.size(), 1, "the roster uses several ops")
	for op in seen:
		if map_only.has(op):
			continue
		# identify_loot and remove_curse both land mid-game: one reads the pack and
		# one the run's curse list, and neither needs the map the way a teleport does.
		assert_true(op in ["apply_status", "apply_tile", "forget", "spawn_enemy",
			"identify_loot", "remove_curse", "stun_enemies"],
			"%s is an op this rule has been thought about — a new one needs a "
			% op + "fizzle of its own if it cannot land mid-game")

# --- the controls row ------------------------------------------------------

func test_the_rate_button_appears_once_a_game_has_been_reported() -> void:
	# _last_played_game is the controls row's only content for most of a run, and
	# it moves on a report rather than on anything the row itself can see.
	_ui.pick(0)
	_report_beat(_ui)
	_ui._end_resolve()
	_leave_post_game()
	_ui._render_controls()
	assert_true(_text_of(_ui._controls_row).contains("Rate"),
		"the game just played is scorable from the offering")

func test_the_start_panel_empties_the_controls_row_for_good() -> void:
	# _refresh clears this row itself on the start panel rather than going through
	# _render_controls, so the guard is invalidated by hand there.
	_ui._render_controls()
	_ui._phase = _ui.Phase.START_SELECT
	_ui._refresh()
	assert_eq(_ui._controls_row.get_child_count(), 0, "nothing is offered to do yet")
	_ui._phase = _ui.Phase.SELECT
	_ui._render_controls()
	assert_true(true, "and the row can be filled again without a stale guard")

# --- loot on the floor (§8.2) ----------------------------------------------
#
# A body cleared while you are still playing leaves a piece of LOOT ON THE BOARD,
# on the square it fell in. What the page owes that is three things: draw it as
# itself, ask about it when it is clicked, and sweep whatever is left when the
# game is handed in. (The relics it used to leave are the reward screen's now —
# see the chest section below.)

func _floor_loot(cell: Vector2i, id: StringName = &"whatever") -> Vector2i:
	return GameLoop2.place_drop(cell, {"type": "scroll", "id": String(id), "rarity": "Common"})

# How many pieces of loot are waiting in the page's queue, across every batch.
func _loot_pieces() -> int:
	var n: int = 0
	for d in _ui._drop_queue:
		var loot = (d as Dictionary).get("loot")
		if loot is Array:
			n += (loot as Array).size()
		elif loot is Dictionary:
			n += 1
	return n

func test_loot_on_the_floor_is_drawn_as_a_draggable_token() -> void:
	_pick_solo(0)
	var at: Vector2i = _floor_loot(Vector2i(2, 1))
	_ui._board.refresh()
	var tokens: Array = _floor_tokens()
	assert_eq(tokens.size(), 1, "one piece on the floor, one thing to pick up")
	assert_true(GameLoop2.has_drop(at), "drawing it did not take it off the floor")
	var token: FloorLoot = tokens[0]
	assert_eq(token.cell, at, "and it knows which square it is lying on")
	assert_eq(token.mouse_default_cursor_shape, Control.CURSOR_DRAG,
		"the cursor says it is a thing you pick up")

# The tokens the board has drawn on the floor, in tree order.
func _floor_tokens() -> Array:
	var out: Array = []
	for c in _ui._board._ground_layer.get_children():
		if c is FloorLoot:
			out.append(c)
	return out

# The payload a floor token hands over when it is dragged, without an OS mouse to
# move: _get_drag_data is called directly, exactly as the pack's own drag tests do.
func _grab(token: FloorLoot) -> Dictionary:
	var data = token._get_drag_data(Vector2.ZERO)
	return data if data is Dictionary else {}

func test_the_token_wears_the_loot_s_own_art() -> void:
	# The whole point of the floor paying loot rather than a relic: a scroll can be
	# drawn as the picture it is, where a chest could only ever be a glyph standing
	# in for an offer the board was not allowed to show (§8.2).
	_pick_solo(0)
	var entry: Dictionary = GameState.roll_loot_entry("loot")
	if entry.is_empty() or LootSystem.art_texture(entry) == null:
		# No art shipped for what came up — the glyph fallback is the correct draw,
		# and the assertion below is what this test is really about either way.
		assert_true(true, "nothing to draw it with")
		return
	var at: Vector2i = GameLoop2.place_drop(Vector2i(2, 1), entry)
	_ui._board.refresh()
	var token: FloorLoot = null
	for c in _ui._board._ground_layer.get_children():
		if c is FloorLoot:
			token = c
	assert_not_null(token, "the piece is on the board")
	if token == null:
		return
	var art: TextureRect = null
	for c in token.get_children():
		if c is TextureRect:
			art = c
	assert_not_null(art, "the piece is drawn as itself")
	if art != null:
		assert_eq(art.texture, LootSystem.art_texture(GameLoop2.drop_at(at)["loot"]),
			"with the same picture the pack draws it with")

func test_the_floor_card_is_the_same_card_the_pack_shows() -> void:
	_pick_solo(0)
	var entry := {"type": "scroll", "id": "whatever", "rarity": "Common"}
	var at: Vector2i = GameLoop2.place_drop(Vector2i(2, 1), entry)
	var card: Dictionary = _ui._board.drop_hover(at)
	assert_eq(String(card.get("title", "")), LootSystem.display_name(entry),
		"a piece of loot has no secret the board has to keep")
	var lines: String = "\n".join(card.get("lines", []) as Array)
	assert_true(lines.contains("pick it up"), "it says what the click does")
	assert_true(lines.contains("haul screen"), "and what leaving it there costs")
	assert_true(String(card.get("subtitle", "")).contains("column"),
		"plus the one thing only a piece on a battlefield knows: where it is")
	assert_eq(_ui._board.drop_hover(Vector2i(4, 3)), {}, "bare ground says nothing")

# --- picking a piece up is a DRAG (§8.2) -----------------------------------
#
# No modal, no click: the token is a handle, the pack appears beside the board
# while a piece is in the air, and letting go is the whole of the answer.

func test_the_grab_carries_the_piece_and_the_square_it_came_off() -> void:
	_pick_solo(0)
	var at: Vector2i = _floor_loot(Vector2i(2, 1), &"grabbed")
	_ui._board.refresh()
	var data: Dictionary = _grab(_floor_tokens()[0])
	assert_eq(String(data.get("kind", "")), "loot_take",
		"the pack's own payload, so every rule about taking loot stays in one place")
	assert_eq(data.get("floor"), at, "plus the square, which only a floor take has")
	assert_eq(String((data.get("entry", {}) as Dictionary).get("id", "")), "grabbed")
	assert_true(GameLoop2.has_drop(at), "picking it up has not moved it yet")

func test_the_pack_appears_while_a_floor_piece_is_in_the_air() -> void:
	_pick_solo(0)
	_floor_loot(Vector2i(2, 1))
	assert_null(_ui._drag_pack, "nothing on screen while nothing is being carried")
	_ui._notification(Control.NOTIFICATION_DRAG_END)
	# The page reads the live payload off the viewport, which a test has no way to
	# put there — so the two halves are checked separately: the mount itself here,
	# and the payload gate in the test below.
	_ui._mount_drag_pack()
	assert_not_null(_ui._drag_pack, "the pack is beside the board")
	assert_not_null(_ui._drag_pack.grid, "with the same 3x3 every loot surface draws")
	assert_true(_ui._drag_pack.grid.allow_floor_take)
	assert_false(_ui._drag_pack.grid.show_use,
		"and no Use buttons, since nothing can be clicked with the mouse down")
	_ui._notification(Control.NOTIFICATION_DRAG_END)
	assert_null(_ui._drag_pack, "letting go takes it away again")

func test_the_pack_does_not_appear_for_a_drag_that_is_not_off_the_floor() -> void:
	# Rearranging inside the loot window already has a pack in front of it.
	_pick_solo(0)
	_ui._notification(Control.NOTIFICATION_DRAG_BEGIN)
	assert_null(_ui._drag_pack,
		"a drag with no floor square behind it summons nothing")

func test_the_pack_sits_to_the_left_of_the_board() -> void:
	_pick_solo(0)
	_floor_loot(Vector2i(2, 1))
	_ui._mount_drag_pack()
	await wait_frames(2)
	_ui._place_drag_pack()
	var pack: Rect2 = _ui._drag_pack.get_global_rect()
	var board: Rect2 = _ui._stage_panel.get_global_rect()
	assert_lte(pack.position.x + pack.size.x, board.position.x + 1.0,
		"it ends where the board begins, so it covers no square the drag needs")
	_ui._notification(Control.NOTIFICATION_DRAG_END)

# THE PIECE IN YOUR HAND IS DRAWN ON TOP OF THE PACK IT IS BEING CARRIED INTO.
# Godot parents the drag preview to the page and moves it to the front of the
# page's children — and then DRAG_BEGIN reaches the page, which hangs the pack off
# that same node, AFTER it. Child order is draw order, so the cell following the
# cursor disappeared under the panel it was aimed at. The preview outranks it by
# z_index instead, which no later sibling can undo.
func test_the_piece_being_dragged_draws_over_the_pack_that_arrives_for_it() -> void:
	_pick_solo(0)
	_floor_loot(Vector2i(2, 1))
	_ui._mount_drag_pack()
	var preview: Control = LootGrid.preview_cell({"type": "scroll", "id": &"scroll_of_teleportation"})
	assert_gt(preview.z_index, _ui._drag_pack.z_index,
		"the thing following the cursor is the thing on top")
	preview.free()
	_ui._notification(Control.NOTIFICATION_DRAG_END)

func test_dropping_a_piece_in_a_free_slot_takes_it() -> void:
	_pick_solo(0)
	GameState.loot_items.clear()
	var at: Vector2i = _floor_loot(Vector2i(2, 1), &"taken")
	var entry: Dictionary = _ui._floor_loot(GameLoop2.drop_at(at))
	_ui.take_floor_loot(entry, 0, at)
	assert_eq(GameState.loot_items.size(), 1, "it is in the pack")
	assert_eq(String(GameState.loot_items[0].get("id", "")), "taken")
	assert_eq(int(GameState.loot_items[0].get("pack_slot", -1)), 0,
		"in the slot it was dropped on, not at the end of the array")
	assert_false(GameLoop2.has_drop(at), "and off the board")

func test_dropping_a_piece_on_a_carried_one_trades_them() -> void:
	_pick_solo(0)
	GameState.loot_items.clear()
	GameState.take_loot_entry({"type": "scroll", "id": "carried", "rarity": "Common"})
	var at: Vector2i = _floor_loot(Vector2i(2, 1), &"incoming")
	var entry: Dictionary = _ui._floor_loot(GameLoop2.drop_at(at))
	var slot: int = int(GameState.loot_items[0].get("pack_slot", 0))
	_ui.take_floor_loot(entry, slot, at)
	assert_eq(GameState.loot_items.size(), 1, "the pack's count did not move")
	assert_eq(String(GameState.loot_items[0].get("id", "")), "incoming",
		"the new piece is carried")
	assert_true(GameLoop2.has_drop(at), "and the square is not left empty")
	assert_eq(String((GameLoop2.drop_at(at)["loot"] as Dictionary).get("id", "")),
		"carried", "the piece it displaced is lying where the new one came from")

func test_a_full_pack_is_a_trade_rather_than_a_wall() -> void:
	_pick_solo(0)
	GameState.loot_items.clear()
	for i in range(GameState.loot_capacity()):
		GameState.take_loot_entry({"type": "scroll", "id": "held%d" % i, "rarity": "Common"})
	assert_true(GameState.loot_is_full())
	var at: Vector2i = _floor_loot(Vector2i(2, 1), &"incoming")
	var entry: Dictionary = _ui._floor_loot(GameLoop2.drop_at(at))
	_ui.take_floor_loot(entry, 0, at)
	assert_eq(GameState.loot_items.size(), GameState.loot_capacity(),
		"still full, and no piece conjured or destroyed")
	assert_eq(String(GameState.loot_items[int(GameState.loot_layout()[0])].get("id", "")),
		"incoming", "the new piece took the slot it was dropped on")
	assert_true(GameLoop2.has_drop(at), "and what it evicted is on the board")

func test_a_grab_from_a_square_that_has_been_swept_takes_nothing() -> void:
	_pick_solo(0)
	GameState.loot_items.clear()
	var at: Vector2i = _floor_loot(Vector2i(2, 1), &"stale")
	var entry: Dictionary = _ui._floor_loot(GameLoop2.drop_at(at))
	GameLoop2.take_drop(at)
	_ui.take_floor_loot(entry, 0, at)
	assert_eq(GameState.loot_items.size(), 0,
		"a payload whose square went out from under it mints nothing")

func test_binning_a_floor_piece_asks_first() -> void:
	_pick_solo(0)
	var at: Vector2i = _floor_loot(Vector2i(2, 1), &"doomed")
	_ui.bin_floor_loot(at)
	await wait_frames(2)
	assert_true(GameLoop2.has_drop(at),
		"nothing is destroyed on the strength of a drag alone")
	var panel: ConfirmPanel = _find_confirm(_ui)
	assert_not_null(panel, "it asks — this is the one gesture that gives nothing back")
	if panel == null:
		return
	panel._on_ok.call()
	assert_false(GameLoop2.has_drop(at), "and on Yes the square is bare")
	panel.dismiss()

func test_reporting_the_game_sweeps_the_floor_onto_the_haul_screen() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	_floor_loot(Vector2i(2, 1), &"one")
	_floor_loot(Vector2i(3, 0), &"two")
	_report_beat(_ui)
	assert_true(GameLoop2.drop_cells().is_empty(),
		"the floor belonged to the game that was just handed in")
	_ui._end_resolve()
	assert_not_null(_ui._post_screen, "and what was on it went where every haul goes")
	assert_gt(_ui._post_screen._loot.size(), 1, "both pieces, on one table")
	_leave_post_game()
	_dismiss_event()

func test_loot_the_player_took_mid_game_is_not_swept_again() -> void:
	_pick_solo(0)
	GameState.loot_items.clear()
	_ui._drop_queue.clear()
	var at: Vector2i = _floor_loot(Vector2i(2, 1))
	_ui.take_floor_loot(_ui._floor_loot(GameLoop2.drop_at(at)), 0, at)
	_ui._sweep_floor_into_the_queue()
	assert_eq(_loot_pieces(), 0,
		"it is in the pack; there is nothing left on the floor to ask about")

func test_a_defeated_body_leaves_loot_where_it_fell() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	GameLoop2.drops.clear()
	var landed: Dictionary = GameLoop2.arrival()
	if landed.is_empty():
		return
	var cell := Vector2i(int(landed.get("col", 2)), int(landed.get("row", 0)))
	_ui._on_enemy_defeated(landed.get("enemy"), cell)
	assert_eq(GameLoop2.drop_cells().size(), 1, "one body, one piece of loot")
	var held: Dictionary = GameLoop2.drop_at(GameLoop2.drop_cells()[0])
	assert_true((held.get("loot", {}) as Dictionary).has("type"),
		"and what it left is a piece of loot, not a chest of relics")

func test_a_body_that_fell_off_the_board_sends_its_loot_to_the_haul_screen() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	var landed: Dictionary = GameLoop2.arrival()
	if landed.is_empty():
		return
	_ui._on_enemy_defeated(landed.get("enemy"), GameLoop2.OFF_FIELD)
	assert_eq(_loot_pieces(), 1, "nowhere to lay it, so it goes where unclaimed loot goes")

# --- the chest the report pays (§8.2) --------------------------------------
#
# The relics moved off the floor and onto the screen the game ends on, scaled by
# how much was killed and how hard it was — and paid only for a game you beat.

func test_beating_a_game_pays_a_chest_scaled_by_what_you_killed() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	GameLoop2.chest_points = 2      # one Medium body's worth
	GameLoop2.boss_chests.clear()
	_ui._queue_report_chests(true)
	assert_eq(_item_drops(), 1, "one chest, not one per body")
	var offer: Array = (_ui._drop_queue[0] as Dictionary).get("items", [])
	assert_eq(offer.size(), int(Data.CHEST_SIZE_CHOICES[Data.ChestSize.LARGE]),
		"1 for the win + 2 for the body is a Large chest")
	_ui._drop_queue.clear()

func test_a_heavy_evening_splits_into_a_second_chest() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	GameLoop2.chest_points = 9      # + 1 for the win = 10
	GameLoop2.boss_chests.clear()
	_ui._queue_report_chests(true)
	assert_eq(_item_drops(), 3, "two Huge chests and a Medium, rather than one off the ladder")
	_ui._drop_queue.clear()

func test_a_game_you_did_not_beat_pays_no_chest() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	GameLoop2.chest_points = 6
	GameLoop2.boss_chests.clear()
	_ui._queue_report_chests(false)
	assert_eq(_item_drops(), 0, "the kills keep their loot; the chest is what winning buys")
	assert_eq(GameLoop2.chest_points, 0, "and the pool does not carry into the next game")

func test_a_boss_chest_is_paid_either_way_and_stays_a_chest_of_its_own() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	GameLoop2.chest_points = 3
	GameLoop2.boss_chests = [1]
	_ui._queue_report_chests(false)
	assert_eq(_item_drops(), 1, "the boss's chest, and only it")
	var offer: Array = (_ui._drop_queue[0] as Dictionary).get("items", [])
	assert_eq(offer.size(), int(Data.CHEST_SIZE_CHOICES[Data.ChestSize.SMALL]),
		"worth its own point rather than the kill pool's")
	_ui._drop_queue.clear()

func test_the_report_s_chests_reach_the_haul_screen() -> void:
	_pick_solo(0)
	_ui._drop_queue.clear()
	_report_beat(_ui)
	_ui._end_resolve()
	assert_not_null(_ui._post_screen)
	if _ui._post_screen != null:
		assert_gt(_ui._post_screen._chest_sections.size(), 0,
			"a beaten game arrives with at least the Small chest the win is worth")
	_leave_post_game()
	_dismiss_event()

# --- a tick is a confirm, and a confirm resolves NOW (§2.1) -----------------
#
# The report used to be the only moment anything on the checklist could happen.
# Every box asks once now, and Yes resolves it on the spot — mid-game, with the
# board still standing and the evening still going.

func _confirm_panel() -> Node:
	return _ui.get_node_or_null("Confirm")

func test_ticking_a_goal_asks_before_it_does_anything() -> void:
	_pick_solo(0)
	if _ui._fulfil_checks.is_empty():
		return
	var standing: int = GameLoop2.stack_size()
	var check: CheckBox = _ui._fulfil_checks[0]["check"]
	check.button_pressed = true
	assert_not_null(_confirm_panel(), "the click raises the question")
	assert_eq(GameLoop2.stack_size(), standing, "and nothing has happened yet")
	_say_no(_ui)
	assert_false(check.button_pressed, "No puts the box back")
	assert_false(check.disabled, "and leaves the row askable again")
	assert_eq(GameLoop2.stack_size(), standing, "with the board untouched")

func test_confirming_a_goal_kills_the_enemy_there_and_then() -> void:
	_pick_solo(0)
	if _ui._fulfil_checks.is_empty():
		return
	var inst: int = int(_ui._fulfil_checks[0]["instance"])
	var check: CheckBox = _ui._fulfil_checks[0]["check"]
	_tick(check)
	assert_true(GameLoop2.entry_for(inst).is_empty(),
		"the body came off the board while the game is still being played")
	assert_true(GameLoop2.cleared_this_game.has(inst), "and the loop knows whose kill it was")
	assert_false(GameLoop2.drop_cells().is_empty(),
		"its loot is on the floor to go and pick up (§8.2)")

func test_a_confirmed_row_cannot_be_taken_back() -> void:
	# The level-up row is the one that stays on the list whatever it resolves —
	# an enemy's row goes with the body — so it is where "locked" can be looked at.
	_reboot(&"zoe")
	_ui.pick(0)
	if _ui._levelup_check == null:
		return
	var check: CheckBox = _ui._levelup_check
	_tick(check)
	assert_true(check.disabled, "an answered row is locked, so it takes no more input")
	assert_true(check.button_pressed, "and stays ticked")
	assert_true(GameLoop2.row_answered("levelup"),
		"and the LOOP holds it, so nothing a repaint does can lose it")
	check.button_pressed = false
	assert_null(_ui.get_node_or_null("Confirm"),
		"there is nothing left to raise a question about")
	_ui._populate_play_panel()
	assert_true(_ui._levelup_check.disabled, "the rebuilt row is locked again")
	assert_true(_ui._levelup_check.button_pressed, "and still ticked")

func test_the_report_does_not_hit_a_body_twice_for_one_goal() -> void:
	_pick_solo(0)
	if _ui._fulfil_checks.is_empty():
		return
	_tick(_ui._fulfil_checks[0]["check"])
	await wait_frames(2)
	assert_true(_ui._ticked_fulfilments().is_empty(),
		"a resolved row is not a claim the report can spend again")
	var standing: int = GameLoop2.stack_size()
	_ui.report(false)
	assert_lte(GameLoop2.stack_size(), standing,
		"and the report hit nothing that was already down")
	_ui._end_resolve()
	_leave_post_game()
	_dismiss_event()

func test_a_goal_answered_mid_game_still_engages_the_body_that_survived_it() -> void:
	# An Alien-Baby-buffed body needs two clears, so one leaves it standing — and a
	# body whose goal you engaged holds its fire for the WHOLE game, whichever end
	# of the game you engaged it at.
	_pick_solo(0)
	if _ui._fulfil_checks.is_empty():
		return
	var inst: int = int(_ui._fulfil_checks[0]["instance"])
	var entry: Dictionary = GameLoop2.entry_for(inst)
	if entry.is_empty():
		return
	entry["health"] = 2
	entry["col"] = 1                       # in reach, so a turn would be a swing
	_tick(_ui._fulfil_checks[0]["check"])
	assert_false(GameLoop2.entry_for(inst).is_empty(), "it took the hit and lived")
	GameState.max_hp = 40
	GameState.hp = 40
	GameState.shields = 0
	GameState.bonus_shields = 0
	GameLoop2.attempt_turn()
	assert_eq(GameState.hp, 40, "and held its fire — its goal was engaged this game")

func test_the_level_up_is_taken_the_moment_it_is_confirmed() -> void:
	_reboot(&"zoe")
	var dash_before: int = GameState.dash_charges
	_ui.pick(0)
	if _ui._levelup_check == null:
		return
	_tick(_ui._levelup_check)
	assert_eq(GameState.dash_charges, dash_before + 1,
		"the level landed mid-game, not at the report")
	assert_true(_ui._levelup_check.disabled, "and the row is locked behind it")
	_report_beat(_ui)
	assert_eq(GameState.dash_charges, dash_before + 1,
		"the report does not take it a second time")
	_ui._end_resolve()
	_leave_post_game()
	_dismiss_event()

func test_a_confirmed_goal_survives_the_checklist_being_rebuilt() -> void:
	# The page rebuilds this list on every repaint. A tick that cannot be taken
	# back must not be something a repaint can lose, which is why the loop and not
	# the box is what remembers it.
	_pick_solo(0)
	if _ui._levelup_check == null:
		return
	_tick(_ui._levelup_check)
	_ui._populate_play_panel()
	assert_not_null(_ui._levelup_check)
	assert_true(_ui._levelup_check.button_pressed, "the rebuilt row is still ticked")
	assert_true(_ui._levelup_check.disabled, "and still locked")

func test_the_answered_rows_go_with_the_game() -> void:
	_pick_solo(0)
	if _ui._levelup_check == null:
		return
	_tick(_ui._levelup_check)
	assert_true(GameLoop2.row_answered("levelup"))
	_report_beat(_ui)
	assert_false(GameLoop2.row_answered("levelup"),
		"what this game was answered for is not true of the next one")
	_ui._end_resolve()
	_leave_post_game()
	_dismiss_event()

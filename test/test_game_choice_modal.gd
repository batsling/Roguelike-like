extends GutTest

# GameChoiceModal — the popup a card opens (§4).
#
# Clicking an offered game used to commit to it on the spot, which meant every
# fact the decision needed had to be printed on the cover. Now the click ASKS:
# the popup shows the optimal path from that game drawn as the real route ladder,
# what is waiting there, what it costs, and the three buttons that answer the
# card. It decides nothing itself — every answer comes straight back out to the
# overworld's public verbs, which is what these tests check.

const SCENE := preload("res://scenes/redesign2/Overworld2.tscn")

var _ui

func before_each() -> void:
	_ui = SCENE.instantiate()
	add_child_autofree(_ui)
	# The start is the run's first game now (Overworld2.choose_start), so the run
	# opens in the report step. This file is about the popup an OFFERED card opens,
	# which means playing that opening game out first: report it, skip the board's
	# playback, drop its relic on the floor.
	_ui.choose_start(0)
	if _ui._phase == _ui.Phase.PLAYING:
		_ui.report(true)
		_ui._end_resolve()
		_ui._drop_queue.clear()
		if _ui._drop_modal != null and is_instance_valid(_ui._drop_modal):
			_ui._drop_modal.queue_free()
			_ui._drop_modal = null

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	SaveSystem.clear_all_saves()
	SaveSystem.cancel_pending_resume()

# --- opening ---------------------------------------------------------------

func test_opening_a_card_does_not_choose_it() -> void:
	var before: StringName = GameState.current_game_id
	var modal = _ui.open_choice(0)
	assert_not_null(modal, "the card opens a popup")
	assert_eq(_ui._phase, _ui.Phase.SELECT, "and the run is still choosing")
	assert_eq(GameState.current_game_id, before, "nothing has been travelled to")

func test_the_popup_names_the_game_and_its_enemy() -> void:
	var choice: Dictionary = _ui._choices[0]
	var modal = _ui.open_choice(0)
	var text: String = _text_of(modal)
	assert_true(text.contains(choice["game"].display_name),
		"the game is named: %s" % text)
	assert_true(text.contains(choice["enemy"].display_name),
		"and so is what's waiting there: %s" % text)

func test_only_one_popup_is_open_at_a_time() -> void:
	var first = _ui.open_choice(0)
	var second = _ui.open_choice(1)
	assert_eq(first, second, "a second card doesn't stack a second popup")

func test_a_card_that_is_not_on_the_table_opens_nothing() -> void:
	assert_null(_ui.open_choice(99), "out of range")
	assert_null(_ui.open_choice(-1), "and below it")

func test_nothing_opens_while_a_game_is_being_played() -> void:
	_ui.pick(0)
	assert_null(_ui.open_choice(0),
		"the offering is gone once you've committed, so there is nothing to open")

# --- the optimal path ------------------------------------------------------

func test_the_popup_draws_the_route_from_the_game_it_is_offering() -> void:
	var slot: StringName = _ui._choices[0]["slot"]
	var modal = _ui.open_choice(0)
	var cfg: Dictionary = modal._ladder_cfg()
	assert_eq(StringName(cfg["current"]), slot,
		"the ladder is routed from the offered game, not from where you stand")
	assert_eq(StringName(cfg["amulet"]), GameState.amulet_game_id,
		"and it ends on the Amulet")
	assert_true(bool(cfg["preview"]),
		"the top rung is where you WOULD be, so it's a preview")

func test_the_route_the_popup_draws_is_the_route_the_badge_claims() -> void:
	# The card's route badge and the map behind it are the same BFS; if they can
	# disagree, one of them is lying to the player.
	var slot: StringName = _ui._choices[0]["slot"]
	var modal = _ui.open_choice(0)
	assert_eq(modal.route_steps(), _ui.steps_to_amulet(slot),
		"the ladder's depth is the distance the offering quotes")

func test_the_ladder_is_drawn_with_arrows_between_the_rungs() -> void:
	var modal = _ui.open_choice(0)
	var canvas = modal._ladder_holder
	assert_true(canvas is RouteLadder.GraphCanvas, "the ladder is the arrow canvas")
	if modal.route_steps() > 0:
		assert_gt(canvas.segments.size(), 0, "a route of any length has arrows on it")
		assert_gt(canvas.get_child_count(), 1, "and more than one rung")

func test_the_amulets_own_card_is_a_one_rung_route() -> void:
	var idx: int = -1
	for i in range(_ui._choices.size()):
		if bool(_ui._choices[i]["amulet"]):
			idx = i
			break
	if idx < 0:
		pass_test("the Amulet isn't on this offering — nothing to check")
		return
	var modal = _ui.open_choice(idx)
	assert_eq(modal.route_steps(), 0, "you'd already be standing on it")

# --- answering it ----------------------------------------------------------

func test_travel_picks_the_game_and_closes_the_popup() -> void:
	var slot: StringName = _ui._choices[0]["slot"]
	var modal = _ui.open_choice(0)
	modal.travel()
	assert_eq(_ui._phase, _ui.Phase.PLAYING, "travelling commits to the game")
	assert_eq(GameState.current_game_id, slot, "and moves the run there")
	assert_null(_ui._choice_modal, "the popup is gone")

func test_back_chooses_nothing() -> void:
	var before: StringName = GameState.current_game_id
	var modal = _ui.open_choice(0)
	modal._close()
	assert_eq(_ui._phase, _ui.Phase.SELECT, "still choosing")
	assert_eq(GameState.current_game_id, before, "and still standing where you were")
	assert_null(_ui._choice_modal, "the popup is gone")

func test_bash_from_the_popup_destroys_the_game() -> void:
	GameState.bash = 1
	var idx: int = _first_bashable()
	if idx < 0:
		pass_test("nothing on this offering can legally be bashed")
		return
	var game: GameData = _ui._choices[idx]["game"]
	var modal = _ui.open_choice(idx)
	modal.bash()
	assert_eq(GameState.bash, 0, "the charge was spent")
	var still_offered: bool = false
	for c in _ui._choices:
		if c["game"].id == game.id:
			still_offered = true
	assert_false(still_offered, "%s is off the table" % game.display_name)

func test_transmute_from_the_popup_swaps_the_game() -> void:
	GameState.transmute = 1
	var before: StringName = _ui._choices[0]["game"].id
	var modal = _ui.open_choice(0)
	modal.transmute()
	assert_eq(GameState.transmute, 0, "the charge was spent")
	assert_ne(_ui._choices[0]["game"].id, before, "the slot plays a different game now")

func test_the_verbs_are_only_offered_when_there_is_a_charge() -> void:
	GameState.bash = 0
	GameState.transmute = 0
	var quiet: String = _text_of(_ui.open_choice(0))
	assert_false(quiet.contains("Bash"), "no charge, no button: %s" % quiet)
	assert_false(quiet.contains("Transmute"), "same for Transmute: %s" % quiet)
	_ui._choice_modal._close()

	GameState.bash = 1
	GameState.transmute = 1
	var idx: int = _first_bashable()
	if idx < 0:
		idx = 0
	var loud: String = _text_of(_ui.open_choice(idx))
	assert_true(loud.contains("Transmute"), "a charge puts the verb on the card: %s" % loud)

func test_the_amulets_card_never_offers_a_bash() -> void:
	# Destroying the game the run is a search for would end it, so the popup
	# refuses rather than offering a button that argues back.
	GameState.bash = 3
	for i in range(_ui._choices.size()):
		if not bool(_ui._choices[i]["amulet"]):
			continue
		var text: String = _text_of(_ui.open_choice(i))
		assert_false(text.contains("⛏  Bash"),
			"the Amulet's card has no Bash button: %s" % text)
		return
	pass_test("the Amulet isn't on this offering — nothing to check")

# --- the card it opened from ----------------------------------------------

func test_the_card_itself_is_just_the_cover_and_the_name() -> void:
	# Everything else it used to carry moved into the popup. What must survive on
	# the card is the game's name and, when it is the one, the Amulet's flag.
	var choice: Dictionary = _ui._choices[0]
	var card: Control = _ui._choices_row.get_child(0)
	var text: String = _text_of(card)
	assert_true(text.contains(choice["game"].display_name), "the name stays: %s" % text)
	for moved in ["tries", "Map", "OPTIMAL", "Detour", "Enemies speed up", "Beatable"]:
		assert_false(text.contains(moved), "'%s' moved into the popup: %s" % [moved, text])

func test_the_amulet_is_flagged_on_the_card_without_opening_anything() -> void:
	for i in range(_ui._choices.size()):
		if not bool(_ui._choices[i]["amulet"]):
			continue
		assert_true(_text_of(_ui._choices_row.get_child(i)).contains("THE AMULET"),
			"the run's destination is legible from the offering itself")
		return
	pass_test("the Amulet isn't on this offering — nothing to check")

# --- what the card opens onto ----------------------------------------------

func test_the_popup_counts_the_connections_the_game_opens_onto() -> void:
	var slot: StringName = StringName(_ui._choices[0]["slot"])
	var counts: Dictionary = GameChoiceModal.connection_counts(slot)
	var modal = _ui.open_choice(0)
	var text: String = _text_of(modal)
	assert_eq(int(counts["total"]), RunGraph.neighbors(slot).filter(
		func(n): return not GameLoop2.is_bashed(n)).size(),
		"the total is the graph's own, minus anything destroyed")
	if int(counts["total"]) > 0:
		assert_true(text.contains("%d connection" % int(counts["total"])),
			"and the popup prints it")
	else:
		assert_true(text.contains("dead end"), "a game with no way on says so")
	modal._close()

func test_the_connection_line_breaks_out_events_and_shops() -> void:
	# Placement is hashed off the node id, so these counts are stable for a run —
	# which is what makes them safe to show before the neighbour's own card is
	# opened.
	for i in range(_ui._choices.size()):
		var slot: StringName = StringName(_ui._choices[i]["slot"])
		var counts: Dictionary = GameChoiceModal.connection_counts(slot)
		var events: int = 0
		var shops: int = 0
		for n in RunGraph.neighbors(slot):
			if GameLoop2.is_bashed(n):
				continue
			if not GameState.event_nodes_fired.has(n):
				events += 1
			if ShopSystem.is_hub(n):
				shops += 1
		assert_eq(int(counts["events"]), events, "events counted off the same rule")
		assert_eq(int(counts["shops"]), shops, "shops counted off the same hub list")
		var line: String = GameChoiceModal.connection_text(counts)
		if events > 0:
			assert_true(line.contains("%d event" % events), "the line names them: %s" % line)
		if shops > 0:
			assert_true(line.contains("%d shop" % shops), "and the shops: %s" % line)

func test_a_bashed_neighbour_stops_counting_as_a_connection() -> void:
	var slot: StringName = StringName(_ui._choices[0]["slot"])
	var neighbours: Array = RunGraph.neighbors(slot)
	if neighbours.is_empty():
		pass_test("this start has no neighbours to destroy")
		return
	var before: int = int(GameChoiceModal.connection_counts(slot)["total"])
	GameState.bash += 1                       # Bash is a charge, and it is spent here
	assert_true(GameLoop2.bash_game(StringName(neighbours[0])), "the neighbour is destroyed")
	assert_eq(int(GameChoiceModal.connection_counts(slot)["total"]), before - 1,
		"a destroyed game is a door that no longer opens")

func _first_bashable() -> int:
	for i in range(_ui._choices.size()):
		if not bool(_ui._choices[i]["amulet"]):
			return i
	return -1

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

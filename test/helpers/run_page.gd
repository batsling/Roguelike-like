extends RefCounted

# THE GAME PAGE, SET UP ONE WAY FOR EVERY TEST FILE THAT NEEDS IT. Fifteen files
# build `Overworld2` and six of them carried their own copy of the same helpers —
# report the opening game beaten, pick an Enemies card, walk off the haul screen —
# which had drifted: one tidied the board and the event after the opening game,
# two did half of that, the rest none. They all come from here now, so a fix to
# how a test stands on the page lands in every file at once.
#
#   const Page := preload("res://test/helpers/run_page.gd")
#   _ui = Page.build(self)
#   Page.open_at_first_offering(_ui)
#
# Static functions on a preloaded script rather than a base class to extend, so a
# file keeps its own helpers and its own `_ui` without clashing with these. Not
# named `test_*`, so GUT does not run it as a test file.

const SCENE := preload("res://scenes/redesign2/Overworld2.tscn")

# A fresh page, freed with the test. Its `_ready` builds the UI and deals a run,
# leaving it on the choose-your-start panel.
static func build(test: GutTest) -> Node:
	var ui = SCENE.instantiate()
	test.add_child_autofree(ui)
	return ui

# Report the game as completed AND tick the row for the body that walked on with
# it. This is what a bare `report(true)` used to do in one flag, back when that
# body was the game's own enemy and beating the game answered for it; it is spelled
# out now because the flag only records the GAME any more (GameLoop2.arrivals),
# and clearing an enemy is ticking its checklist row like any other.
static func report_beat(ui) -> void:
	var landed: Dictionary = GameLoop2.arrival()
	ui.report(true, [] if landed.is_empty() else [int(landed["instance"])])

# Pick the card at `idx`, having first made sure it is an ordinary fight (§19.1).
#
# What a committed game stands on the board is decided by the NODE'S KIND — two
# bodies on an Enemies node, one boss on a Champion, none at all on an Event or a
# Shop — and the offering deals those at 60/20/10/10. So a test that picks and
# then expects something to be standing there is a test whose subject is a die
# roll. Forcing the kind on the one node about to be picked is the ARRANGE step;
# the rest of the map is left as the run dealt it.
static func pick_enemies(ui, idx: int = 0) -> void:
	if idx >= 0 and idx < ui._choices.size():
		set_kind(ui._choices[idx], RunGraph.NodeKind.ENEMIES)
	ui.pick(idx)

# Force a choice's kind, ON THE SLOT (§19.2).
#
# The kind rides the NODE, not the game standing on it — that is what makes a
# transmuted card play a different game at the same kind — so setting it against
# the game id works for an ordinary card and silently does nothing for a
# transmuted one, where the two differ.
static func set_kind(choice: Dictionary, kind: int) -> void:
	var slot := StringName(choice.get("slot", &""))
	if slot == &"":
		var g: GameData = choice.get("game")
		slot = g.id if g != null else &""
	if slot != &"":
		GameState.node_kinds[slot] = kind

# Walk off the screen a game ended on. Every report hands its haul to one
# PostCombatScreen, and the drops it queued (the game's loot, a relic) are not what
# a test standing on the next screen is about.
static func leave_post_game(ui) -> void:
	if ui._post_screen != null and is_instance_valid(ui._post_screen):
		ui._post_screen.dismiss()
	ui._post_screen = null
	ui._post_snapshot = {}
	ui._drop_queue.clear()
	if ui._drop_modal != null and is_instance_valid(ui._drop_modal):
		ui._drop_modal.queue_free()
		ui._drop_modal = null

# …and close the event that leaving it raised, with any machine it stood up.
static func dismiss_event(ui) -> void:
	if ui._event_modal != null and is_instance_valid(ui._event_modal):
		ui._event_modal._close()
	ui._event_modal = null
	ui._pending_event = null
	ui._pending_event_node = &""
	ObjectSystem.clear()

# Take every body off the board.
static func clear_board() -> void:
	for entry in GameLoop2.stack.duplicate():
		GameLoop2.despawn(int(entry.get("instance", 0)))

# PLAY THE OPENING GAME: take the first start, report it beaten, skip the board's
# playback and walk off the haul screen. What a player does before the first card
# is on the table. False, having done nothing past `choose_start`, when the start
# did not put a game in play.
#
# The playback is cut short deliberately: the board freezes the hero's Health at
# its pre-resolve value for the length of the animation and lets go when the tween
# ends, which in a test that never waits is never.
static func play_opening(ui) -> bool:
	ui.choose_start(0)
	if ui._phase != ui.Phase.PLAYING:
		return false
	report_beat(ui)
	ui._end_resolve()
	ui._board.clear_fx()
	leave_post_game(ui)
	return true

# …and stand at the first offering with nothing left over from it: the event its
# haul screen raised is closed, and the opening game's ESCORT (§7.5), which
# survives it by design, is taken off the board so the bodies a test counts are
# the ones it put there.
static func open_at_first_offering(ui) -> void:
	if not play_opening(ui):
		return
	dismiss_event(ui)
	clear_board()

# Every Label, Button and RichTextLabel's text under `node`, one per line.
static func text_of(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	elif node is Button:
		out += (node as Button).text + "\n"
	elif node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	for c in node.get_children():
		out += text_of(c)
	return out

# Only the Labels' text — for an assertion that a word is NOT on screen, where a
# button's caption would answer for something else.
static func labels_text(node: Node) -> String:
	var out: String = ""
	if node is Label:
		out += (node as Label).text + "\n"
	for child in node.get_children():
		out += labels_text(child)
	return out

# Tick a checklist box the way a player does: the press, then Yes on the confirm
# it raises over `host`.
static func tick(check, host) -> void:
	if check == null or not is_instance_valid(check) or check.disabled:
		return
	check.button_pressed = true
	var panel = host.get_node_or_null("Confirm")
	if panel == null:
		return
	var ok = panel.find_child("OkBtn", true, false)
	if ok != null:
		ok.pressed.emit()

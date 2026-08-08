class_name EventModal2
extends Control

# EventModal2 — the screen an event happens on (docs/event-sheet-authoring.md).
#
# Not to be confused with `scripts/events/EventModal.gd`, which is the combat-era
# one: it rolls a d20 against charisma / dexterity / intelligence, three stats the
# games-first cut deleted. This is its replacement, and it has no dice in it at
# all. What the player spends here is Health, Max Health, a verb charge, or a
# GOAL they take on for the next few games — things the run actually has.
#
# The modal is a small state machine over one EventData2, because an event is not
# always "pick one of three and leave":
#
#   * `Repeat: Again` keeps a choice on the table, and `{X}` in its effects
#     escalates on each press — X is how many times THAT choice has been taken,
#     so one authored row is Slay the Spire 2's whole 4/5/6 damage ladder.
#   * `Repeat: Stay` keeps the event open but takes the choice away, which is how
#     a two-stage event (Immerse, then Linger) fits in one row.
#   * `needs <Choice> <op> <n>` gates a choice on what's already been picked, so
#     the two exits of Abyssal Baths can be offered to different players.
#
# Everything mechanical routes through EventSystem; this file is the view.

# Emitted once when the event closes, with a play_game request or {}.
signal finished(play_request: Dictionary)

const PANEL_SIZE := Vector2(560, 0)

var _event: EventData2 = null
var _layer: CanvasLayer = null
var _done: bool = false
# choice id -> times taken in THIS run of the event. The X of every {expr} hole,
# and what the `needs <Choice>` gates read.
var _picks: Dictionary = {}
# The prose from the last choice taken, shown above the remaining options so a
# repeated dip reads as a sequence rather than a flicker.
var _last_result: String = ""
var _last_text: String = ""
var _play_request: Dictionary = {}

var _box: VBoxContainer = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


static func open(host: Node, event: EventData2) -> EventModal2:
	var modal := EventModal2.new()
	modal._start(host, event)
	return modal


func _start(host: Node, event: EventData2) -> void:
	_event = event
	_layer = CanvasLayer.new()
	_layer.layer = 123
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _event == null:
		_close()
		return
	EventSystem.mark_fired(_event)
	GameLog.add("Event: %s" % _event.display_name, UITheme.ACCENT)
	_build()


func _build() -> void:
	# No click-outside-to-close. An event is a decision with a price on both
	# sides, and a stray click is not an answer to it.
	var panel := ModalScaffold.build_panel(self, UITheme.ACCENT, Callable(), PANEL_SIZE)
	panel.custom_minimum_size = Vector2(PANEL_SIZE.x, 0)
	panel.size = Vector2(PANEL_SIZE.x, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	margin.add_child(_box)
	_render()


func _render() -> void:
	for child in _box.get_children():
		child.queue_free()

	var head := Label.new()
	head.text = "✦  %s" % _event.display_name
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 19)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	_box.add_child(head)

	if _event.source_game != "":
		var from := Label.new()
		from.text = "From: %s" % _event.source_game
		from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		from.add_theme_font_size_override("font_size", 11)
		from.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		_box.add_child(from)

	var art: Texture2D = _art()
	if art != null:
		var rect := UITheme.crisp_tex(art, 140)
		rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_box.add_child(rect)

	# The prompt stays up the whole event; on a repeat the last outcome sits
	# under it, so "you surface changed" reads as the thing that just happened
	# rather than replacing the room you are standing in.
	_box.add_child(_prose(_event.prompt, UITheme.TEXT, 14))
	if _last_result != "":
		_box.add_child(_rule())
		_box.add_child(_prose(_last_result, UITheme.TEXT_DIM, 13))
	if _last_text != "":
		var did := Label.new()
		did.text = _last_text
		did.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		did.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		did.add_theme_font_size_override("font_size", 12)
		did.add_theme_color_override("font_color", UITheme.GOLD)
		_box.add_child(did)

	_box.add_child(_rule())

	var offered: int = 0
	for i in range(_event.choices.size()):
		var choice: Dictionary = _event.choices[i]
		if not EventSystem.choice_available(choice, _picks):
			continue
		_box.add_child(_choice_button(i, choice))
		offered += 1

	if offered == 0:
		# Every remaining choice is gated or spent. Rather than trap the player in
		# a modal with no answer, offer the way out — an event that can't be left
		# is a bug the generator warns about, but the screen should not hang on it.
		var out := Button.new()
		out.text = "Leave"
		out.custom_minimum_size = Vector2(0, 40)
		out.pressed.connect(_close)
		_box.add_child(out)


# One choice: its label, and under it the mechanical line resolved for THIS
# press. The escalation is a pure function of how often the choice has been
# taken, so the button can say "-5 Health" instead of making the player work out
# what {4+X} means. Slay the Spire 2 has to warn you the baths will kill you;
# here the button just says the number.
func _choice_button(index: int, choice: Dictionary) -> Control:
	var taken: int = int(_picks.get(choice.get("id", ""), 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)

	var btn := Button.new()
	btn.text = String(choice.get("text", "…"))
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(func(): _take(index))
	col.add_child(btn)

	var line: String = EventSystem.describe_choice(choice, taken)
	if line != "":
		var lbl := Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		col.add_child(lbl)
	return col


# Public so a test can answer without a click.
func take(index: int) -> void:
	_take(index)


func _take(index: int) -> void:
	if _done or index < 0 or index >= _event.choices.size():
		return
	var choice: Dictionary = _event.choices[index]
	if not EventSystem.choice_available(choice, _picks):
		return
	var cid: String = String(choice.get("id", ""))
	var taken: int = int(_picks.get(cid, 0))

	var out: Dictionary = EventSystem.resolve_choice(_event, choice, taken)
	_picks[cid] = taken + 1
	_last_result = String(out.get("result", ""))
	_last_text = String(out.get("text", ""))
	if _last_text != "":
		GameLog.add("%s — %s: %s" % [_event.display_name, choice.get("text", ""), _last_text],
			UITheme.ACCENT)

	var play: Dictionary = out.get("play", {})
	if not play.is_empty():
		_play_request = play

	if bool(out.get("close", true)) or not _play_request.is_empty():
		# The result of the LAST choice would otherwise never be read, since the
		# modal closes on it. Show it on its own with a dismiss button.
		_show_epilogue()
		return
	_render()


# The closing beat: the prose of the choice that ended it, and one button.
func _show_epilogue() -> void:
	for child in _box.get_children():
		child.queue_free()

	var head := Label.new()
	head.text = "✦  %s" % _event.display_name
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 19)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	_box.add_child(head)

	if _last_result != "":
		_box.add_child(_prose(_last_result, UITheme.TEXT, 14))
	if _last_text != "":
		var did := Label.new()
		did.text = _last_text
		did.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		did.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		did.add_theme_font_size_override("font_size", 13)
		did.add_theme_color_override("font_color", UITheme.GOLD)
		_box.add_child(did)

	if not _play_request.is_empty():
		var note := Label.new()
		note.text = "You head off to a %s game…" % String(_play_request.get("tag", ""))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", UITheme.ACCENT)
		_box.add_child(note)

	var done := Button.new()
	done.text = "Onward"
	done.custom_minimum_size = Vector2(0, 42)
	done.add_theme_font_size_override("font_size", 16)
	done.pressed.connect(_close)
	_box.add_child(done)
	done.grab_focus()


func _art() -> Texture2D:
	var file: String = _event.art_file()
	if file == "":
		return null
	var path: String = "res://images2.0/events/%s.png" % file
	return load(path) if ResourceLoader.exists(path) else null


func _prose(text: String, colour: Color, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", colour)
	return lbl


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = UITheme.BORDER
	line.custom_minimum_size = Vector2(0, 1)
	return line


func _close() -> void:
	if _done:
		return
	_done = true
	finished.emit(_play_request)
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	# Escape does not dismiss an open event — see _build. Swallow it so it does
	# not fall through to whatever is behind and close THAT instead.
	if event.is_action_pressed("ui_cancel"):
		accept_event()

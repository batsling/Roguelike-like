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
# LAYOUT. Two columns whenever there is art: the picture on the left, the words
# and the buttons on the right. It started as one vertical stack and that was
# wrong for this content — a full-height event illustration plus the Abyssal
# Baths prompt plus four choices with a mechanical line each ran off the bottom
# of a 720p viewport before anything was even scrolling. Side by side, the art
# costs no vertical room at all.
#
# The panel SIZES ITSELF TO ITS CONTENT (see _fit) and only starts scrolling once
# that would overflow the window. So a two-option event is a small card and a
# nine-option one is a full-height panel with a scrolling column beside the art,
# and neither is padded out to the other's shape.
#
# Everything mechanical routes through EventSystem; this file is the view.

# Emitted once when the event closes, with a play_game request or {}.
signal finished(play_request: Dictionary)

# The panel wants to be big — it is carrying an illustration and a page of prose
# — but never bigger than the window it opens in.
const PANEL_MAX := Vector2(880, 640)
const VIEW_MARGIN := Vector2(64, 64)
const ART_COLUMN := 280.0
# Below this the art column is dropped and the modal goes back to one column:
# on a narrow window the words matter more than the picture.
const TWO_COLUMN_MIN_WIDTH := 720.0
# Header, margins and separators — everything in the panel that is not the
# scrolling column. Subtracted from the viewport cap so the panel as a whole
# stays inside the window.
const HEADER_ALLOWANCE := 110.0

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

var _panel: PanelContainer = null
var _prose_box: VBoxContainer = null
var _choice_box: VBoxContainer = null
# The right column and the scroll region around it. The panel SIZES ITSELF TO
# THIS: a two-choice event should be a small card, not a half-empty 640px slab,
# and only an event with more to say than fits should start scrolling. See _fit.
var _right: VBoxContainer = null
var _scroll: ScrollContainer = null


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


func _panel_size() -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	return Vector2(
		minf(PANEL_MAX.x, maxf(420.0, view.x - VIEW_MARGIN.x)),
		minf(PANEL_MAX.y, maxf(360.0, view.y - VIEW_MARGIN.y)))


func _build() -> void:
	# No click-outside-to-close. An event is a decision with a price on both
	# sides, and a stray click is not an answer to it.
	#
	# The panel is given a WIDTH and no height: a PanelContainer sizes to its
	# content, and _fit then caps that against the viewport. A fixed height would
	# make every event as tall as the tallest one.
	_panel = ModalScaffold.build_panel(self, UITheme.ACCENT, Callable(),
		Vector2(_panel_size().x, 0))
	_panel.set_anchors_preset(Control.PRESET_CENTER)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	root.add_child(_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var art: Texture2D = _art()
	if art != null and _panel_size().x >= TWO_COLUMN_MIN_WIDTH:
		body.add_child(_art_column(art))

	# ONE scroll region around the words and the buttons together. Two separate
	# ones (prose scrolls, choices scroll) split the height evenly whatever the
	# content was, which left a short prompt floating in a tall empty box. Sharing
	# one region means a long prompt and a long list of options compete for the
	# same space honestly, and a short event simply takes less of it.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)

	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 10)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_right)

	_prose_box = VBoxContainer.new()
	_prose_box.add_theme_constant_override("separation", 8)
	_prose_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_child(_prose_box)
	_right.add_child(_rule())
	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 8)
	_choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_child(_choice_box)

	_render()


func _header() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var title := Label.new()
	title.text = "✦  %s" % _event.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	col.add_child(title)
	if _event.source_game != "":
		var from := Label.new()
		from.text = "From: %s" % _event.source_game
		from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		from.add_theme_font_size_override("font_size", 11)
		from.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		col.add_child(from)
	return col


# The art column. Fixed width, height from the image's own aspect, so a portrait
# illustration and a square one both fill their column instead of one of them
# being letterboxed into the other's box.
func _art_column(tex: Texture2D) -> Control:
	var rect := TextureRect.new()
	rect.texture = tex
	var aspect: float = float(tex.get_height()) / maxf(1.0, float(tex.get_width()))
	rect.custom_minimum_size = Vector2(ART_COLUMN, minf(ART_COLUMN * aspect, 460.0))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Top-aligned, not centred: the illustration and the first line of the prompt
	# should start on the same line. Centred, a short event left a gap above the
	# picture that read as a layout bug.
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_crisp(rect, tex)
	return rect


func _render() -> void:
	for child in _prose_box.get_children():
		child.queue_free()
	for child in _choice_box.get_children():
		child.queue_free()

	# The prompt stays up the whole event; on a repeat the last outcome sits
	# under it, so "you surface changed" reads as the thing that just happened
	# rather than replacing the room you are standing in.
	_prose_box.add_child(_prose(_event.prompt, UITheme.TEXT, 14))
	if _last_result != "":
		_prose_box.add_child(_rule())
		_prose_box.add_child(_prose(_last_result, UITheme.TEXT_DIM, 13))
	if _last_text != "":
		_prose_box.add_child(_did_line(_last_text, 12))

	var offered: int = 0
	for i in range(_event.choices.size()):
		var choice: Dictionary = _event.choices[i]
		if not EventSystem.choice_available(choice, _picks):
			continue
		_choice_box.add_child(_choice_button(i, choice))
		offered += 1

	if offered == 0:
		# Every remaining choice is gated or spent. Rather than trap the player in
		# a modal with no answer, offer the way out — an event that can't be left
		# is a bug the generator warns about, but the screen should not hang on it.
		var out := Button.new()
		out.text = "Leave"
		out.custom_minimum_size = Vector2(0, 40)
		out.pressed.connect(_close)
		_choice_box.add_child(out)

	# The content just changed shape, so the panel has to be re-measured. Deferred
	# because the labels have not wrapped yet this frame and a Label that has not
	# wrapped reports the wrong height.
	_fit.call_deferred()


# Size the panel to what is actually in it, capped at the viewport. Under the cap
# the modal is a card the size of its content; over it, the right column scrolls
# and the art stays put beside it. This is what makes a two-option event and a
# ten-option event both look deliberate.
func _fit() -> void:
	if _panel == null or not is_instance_valid(_panel) or _right == null:
		return
	await get_tree().process_frame
	if _panel == null or not is_instance_valid(_panel):
		return
	var wanted: float = _right.get_combined_minimum_size().y
	var cap: float = _panel_size().y - HEADER_ALLOWANCE
	_scroll.custom_minimum_size.y = clampf(wanted, 90.0, cap)
	_panel.size = _panel.get_combined_minimum_size()
	_recentre()


# Centre the panel by writing its OFFSETS, not its position.
#
# `position` on a centre-anchored Control is stored as an offset from
# anchor × parent_size, and this modal's parent is a Control inside a
# CanvasLayer that has not been given its size yet when _fit first runs. With a
# zero-size parent, `position = -size * 0.5` writes offsets measured from the
# top-left corner, and the panel renders half off the screen — which is exactly
# what it did. Offsets are absolute, so they land the same however the parent is
# sized at the time.
func _recentre() -> void:
	var half: Vector2 = _panel.size * 0.5
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -half.x
	_panel.offset_top = -half.y
	_panel.offset_right = half.x
	_panel.offset_bottom = half.y


# One choice: its label, and under it the mechanical line resolved for THIS
# press. The escalation is a pure function of how often the choice has been
# taken, so the button can say "-5 Health" instead of making the player work out
# what {4+X} means. Slay the Spire 2 has to warn you the baths will kill you;
# here the button just says the number.
func _choice_button(index: int, choice: Dictionary) -> Control:
	var taken: int = int(_picks.get(choice.get("id", ""), 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var btn := Button.new()
	btn.text = String(choice.get("text", "…"))
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_stylebox_override("normal",
		UITheme.flat(UITheme.BG, 6, 6, 1, UITheme.BORDER))
	btn.add_theme_stylebox_override("hover",
		UITheme.flat(UITheme.PANEL_HI, 6, 6, 2, UITheme.ACCENT))
	btn.pressed.connect(func(): _take(index))
	col.add_child(btn)

	var line: String = EventSystem.describe_choice(choice, taken)
	if line != "":
		var lbl := Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


# The closing beat: the prose of the choice that ended it, and one button. Keeps
# the art and the two-column frame — the event should not visibly change shape on
# its last screen.
func _show_epilogue() -> void:
	for child in _prose_box.get_children():
		child.queue_free()
	for child in _choice_box.get_children():
		child.queue_free()

	if _last_result != "":
		_prose_box.add_child(_prose(_last_result, UITheme.TEXT, 14))
	elif _event.prompt != "":
		_prose_box.add_child(_prose(_event.prompt, UITheme.TEXT_DIM, 13))
	if _last_text != "":
		_prose_box.add_child(_did_line(_last_text, 13))

	if not _play_request.is_empty():
		var note := Label.new()
		note.text = "You head off to a %s game…" % String(_play_request.get("tag", ""))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", UITheme.ACCENT)
		_prose_box.add_child(note)
	_fit.call_deferred()

	var done := Button.new()
	done.text = "Onward"
	done.custom_minimum_size = Vector2(0, 42)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.add_theme_font_size_override("font_size", 16)
	done.add_theme_stylebox_override("normal",
		UITheme.flat(UITheme.ACCENT.lerp(UITheme.BG, 0.6), 8, 8, 2, UITheme.ACCENT))
	done.add_theme_stylebox_override("hover",
		UITheme.flat(UITheme.ACCENT.lerp(UITheme.BG, 0.42), 8, 8, 2, UITheme.ACCENT))
	done.pressed.connect(_close)
	_choice_box.add_child(done)
	done.grab_focus()


func _did_line(text: String, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", UITheme.GOLD)
	return lbl


# Art is loaded HERE rather than exported on EventData2, and that is deliberate:
# these illustrations are 1-1.3 MB each and `Data` loads every event at startup.
# An ExtResource would resolve eagerly and decode all of them on every boot and
# every headless test run — the same trap `GameData.cover_image` already sidesteps.
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
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

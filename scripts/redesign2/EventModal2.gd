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
# LAYOUT. Two columns whenever there is art AND prose: the picture on the left,
# the words and the buttons on the right. It started as one vertical stack and
# that was wrong for this content — a full-height event illustration plus the
# Abyssal Baths prompt plus four choices with a mechanical line each ran off the
# bottom of a 720p viewport before anything was even scrolling. Side by side, the
# art costs no vertical room at all.
#
# An event with a BLANK PROMPT stacks instead: the picture sits above the choices
# rather than beside them. Two columns exist to keep a page of prose off the
# bottom of the screen, and a wordless event (the Arcade Room, which is a room
# you walk into and a pair of buttons) has no page — side by side it is a picture
# next to two lonely buttons in a half-empty column. Stacked, the art is the
# event's only voice and sits where you read it first.
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
# Stacked art is bounded by HEIGHT, not width: it is spending the same vertical
# room the choices want, where the side column spent none. Kept well under the
# 460 the column allows so a portrait illustration cannot push the buttons off
# the bottom of a small panel.
const STACKED_ART_HEIGHT := 190.0
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
# HIDDEN state. An event fires the moment a game is beaten, which is also when
# the board is playing its resolve back and when a chest is being offered — three
# things arriving on one screen, two of them covering the third. So the event can
# be put away: the panel goes, a small chip stays in the corner, and the player
# brings it back when they have finished watching the board and taking the drop.
# Nothing about the event resolves while it is hidden; it is only out of the way.
var _hidden: bool = false
var _objects_box: HFlowContainer = null
# The machines that were already standing at this game when the event opened.
# Everything spawned after it is the event's own, and goes when the event does.
var _objects_before: Array = []
# The instances the object row is currently showing, so a rebuild happens when
# the set changes rather than when the count does.
var _objects_drawn: Array = []
var _chip: Button = null
var _backdrop_nodes: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


# `game_id` is the node the event was rolled for. Opening spends it, so that game
# pays no second event this run — passed in rather than read off GameState so the
# dev panel can raise an event without spending the node the run happens to be
# standing on.
static func open(host: Node, event: EventData2, game_id: StringName = &"") -> EventModal2:
	var modal := EventModal2.new()
	modal._start(host, event, game_id)
	return modal


func _start(host: Node, event: EventData2, game_id: StringName = &"") -> void:
	_event = event
	_layer = CanvasLayer.new()
	_layer.layer = 123
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _event == null:
		_close()
		return
	# What was already standing here before this event opened. Everything that
	# appears from now on belongs to the event, and leaves with it (_close).
	_objects_before = ObjectSystem.live.duplicate()
	# A machine can destroy itself mid-event — the Blood Donation Machine bursts,
	# and bombing one is a button on it — and when it does its card has to go with
	# it. The cards repaint themselves off this signal; nothing was watching it for
	# the SET changing, so a blown-up machine stayed on screen until the next
	# choice was pressed.
	if not ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.connect(_on_objects_changed)
	EventSystem.mark_fired(_event, game_id)
	# Roll whatever this event's content depends on the RUN for — the Relic
	# Trader's three offers are built from the player's own pack. Once, here,
	# rather than per repaint, so a button cannot rename itself under the cursor.
	EventSystem.begin_event(_event)
	GameLog.add("Event: %s" % _event.display_name, UITheme.ACCENT)
	_build()


# The screen an event gets to use — the window less the run's header band, which
# is pinned above this layer and would otherwise paint over the event's title and
# the first line of what it is asking (ModalScaffold.reserved_top).
func _panel_size() -> Vector2:
	var free: Rect2 = ModalScaffold.free_rect(self)
	return Vector2(
		minf(PANEL_MAX.x, maxf(420.0, free.size.x - VIEW_MARGIN.x)),
		minf(PANEL_MAX.y, maxf(360.0, free.size.y - VIEW_MARGIN.y)))


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
	# The scaffold's dim + click-blocker are the two children it added before the
	# panel. Hiding has to take them with it, or an invisible modal keeps eating
	# every click meant for the board underneath.
	for child in get_children():
		if child != _panel:
			_backdrop_nodes.append(child)

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
	# Decided once, from the PROMPT, and never revisited: a result printed later
	# must not make the picture jump out of the stack and into a side column
	# mid-event. A wordless event that goes on to say something keeps the layout
	# it opened in.
	var stacked: bool = _event.prompt == ""
	if art != null and not stacked and _panel_size().x >= TWO_COLUMN_MIN_WIDTH:
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

	# Inside the scroll region rather than above it, so the art is part of what
	# _fit measures and what gives way when the panel runs out of window. Outside
	# it, a 190px banner would be added to an already-capped column and push the
	# panel past the viewport.
	if art != null and stacked:
		_right.add_child(_art_banner(art))

	_prose_box = VBoxContainer.new()
	_prose_box.add_theme_constant_override("separation", 8)
	_prose_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_child(_prose_box)
	# Machines the event put in front of you (docs/object-sheet-authoring.md),
	# BETWEEN the prose and the buttons. The Arcade Room is a room you are
	# standing in and the cabinets are in it with you, so they are laid out inside
	# the event rather than under the board — and the event's own `Leave`, below
	# them, is what takes you out of the room and the machines with it.
	_objects_box = HFlowContainer.new()
	_objects_box.add_theme_constant_override("h_separation", 8)
	_objects_box.add_theme_constant_override("v_separation", 8)
	_objects_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objects_drawn = []
	_right.add_child(_objects_box)
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
	# Put-it-away, top right of the panel. Not a close: a closed event is resolved
	# and gone, and this one has not been answered yet.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.alignment = BoxContainer.ALIGNMENT_END
	var hide_btn := Button.new()
	hide_btn.text = "⌄  Hide"
	hide_btn.tooltip_text = "Put the event away and come back to it — nothing is decided."
	hide_btn.custom_minimum_size = Vector2(84, 26)
	hide_btn.add_theme_font_size_override("font_size", 12)
	hide_btn.pressed.connect(_hide_event)
	bar.add_child(hide_btn)
	col.add_child(bar)

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


# The stacked banner: the same illustration, sized to a height the choices can
# live under and centred over them. Width comes from the image's own aspect and
# is capped at the panel's inner width, height recomputed from whichever bound
# bit — a wide image stays wide and short instead of being letterboxed into a
# 190px-tall box it never fills.
func _art_banner(tex: Texture2D) -> Control:
	var rect := TextureRect.new()
	rect.texture = tex
	var aspect: float = float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	var height: float = STACKED_ART_HEIGHT
	var width: float = minf(height * aspect, _panel_size().x - 56.0)
	rect.custom_minimum_size = Vector2(width, minf(height, width / maxf(0.01, aspect)))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.apply_crisp(rect, tex)
	return rect


func _render() -> void:
	for child in _prose_box.get_children():
		child.queue_free()
	for child in _choice_box.get_children():
		child.queue_free()
	_render_objects()

	# The prompt stays up the whole event; on a repeat the last outcome sits
	# under it, so "you surface changed" reads as the thing that just happened
	# rather than replacing the room you are standing in. Skipped when the sheet
	# left it blank — an empty Label still claims a line of height, which read as
	# a stray gap over the choices.
	if _event.prompt != "":
		_prose_box.add_child(_prose(_event.prompt, UITheme.TEXT, 14))
	if _last_result != "":
		# The rule separates the outcome from the prompt above it. With no prompt
		# there is nothing above it to separate, and a line across the top of an
		# empty box is just a line.
		if _prose_box.get_child_count() > 0:
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


# A machine appeared or went. The cards look after their own state off the same
# signal, so this only has to notice the SET changing.
func _on_objects_changed() -> void:
	if _done or not is_inside_tree():
		return
	_render_objects()


# The machines standing in this event, if it spawned any. Rebuilt only when the
# SET changed — each card repaints itself off objects_changed, and tearing them
# down every render would throw away the one the player is mid-click on.
#
# The set is compared by the INSTANCES drawn, not by how many cards are up: a
# machine that bursts in the same beat another spawns leaves the count untouched
# and the room completely different.
func _render_objects() -> void:
	if _objects_box == null:
		return
	if _same_objects(_objects_drawn, ObjectSystem.live):
		return
	_objects_drawn = ObjectSystem.live.duplicate()
	for child in _objects_box.get_children():
		_objects_box.remove_child(child)
		child.queue_free()
	for inst in _objects_drawn:
		_objects_box.add_child(ObjectCard.make(inst))
	_fit.call_deferred()


# Same machines, in the same order. By reference (is_same), because two untouched
# copies of one cabinet are equal dictionaries and are still two cabinets.
func _same_objects(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not is_same(a[i], b[i]):
			return false
	return true


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
	# Delegated, rather than written out again here: the scaffold does exactly this
	# and then shifts the panel clear of the run's header band, and an event that
	# centred itself by hand was the one modal that stayed under the bar.
	ModalScaffold.centre(_panel)


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
	# The label goes through the same name holes the prose does, so a sheet can
	# write `Trade <give>` as a button as readily as it writes it as a result.
	btn.text = EventSystem.fill_trade_names(String(choice.get("text", "…")), choice)
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 15)
	# A press that would end the run wears the warning ITSELF, not only the line
	# under it. An event can kill you — Scrap Ooze's reach on your last point of
	# Health, Abyssal Baths' last dip — and the red text alone sat under a button
	# that looked exactly like the safe one above it.
	if EventSystem.is_deadly(choice, taken):
		btn.add_theme_stylebox_override("normal", UITheme.lethal_box())
		btn.add_theme_stylebox_override("hover", UITheme.lethal_box(true))
		btn.add_theme_color_override("font_color", UITheme.DANGER)
		btn.add_theme_color_override("font_hover_color", UITheme.TEXT)
	else:
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
		# Reddens as the press gets closer to lethal — Abyssal Baths' Linger
		# climbs until it can kill, and the number on the button should look like
		# what it is before the prose gets round to saying so.
		lbl.add_theme_color_override("font_color",
			EventSystem.danger_color(choice, taken))
		col.add_child(lbl)

	var warning: String = EventSystem.lethal_warning(choice, taken)
	if warning != "":
		var warn := Label.new()
		warn.text = warning
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", UITheme.DANGER)
		col.add_child(warn)
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
		# modal closes on it. Show it on its own with a dismiss button — unless
		# there is nothing to read.
		#
		# WALKING OUT IS THE CASE. The Arcade Room's `Leave` costs nothing and pays
		# nothing, so its epilogue was an all-but-blank panel with one button on
		# it — the word "Nothing", which is what the sheet writes for a no-op, and
		# an Onward. You pressed Leave and the event was still there, wanting
		# another click before it would go. An epilogue with nothing in it is not
		# a closing beat, it is a second press, so the event simply ends.
		if _last_result == "" and _play_request.is_empty() \
				and EventSystem.does_nothing(choice):
			_close()
			return
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


# --- hide / show ------------------------------------------------------------

func _hide_event() -> void:
	if _done or _hidden:
		return
	_hidden = true
	_panel.visible = false
	for n in _backdrop_nodes:
		if is_instance_valid(n):
			(n as CanvasItem).visible = false
	# The chip is the whole of the hidden state: without something on screen
	# saying an event is waiting, putting it away would look like losing it.
	_chip = Button.new()
	_chip.text = "✦  %s — resume" % _event.display_name
	_chip.tooltip_text = "Bring the event back."
	# BOTTOM right. Top right is where the Menu button and the notification toasts
	# already live, and a resume chip that covers the menu trades one obstruction
	# for another. The bottom corner is empty on every phase of this screen.
	_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_chip.offset_left = -320
	_chip.offset_top = -58
	_chip.offset_right = -16
	_chip.offset_bottom = -16
	_chip.add_theme_font_size_override("font_size", 13)
	_chip.add_theme_color_override("font_color", UITheme.ACCENT)
	_chip.add_theme_stylebox_override("normal",
		UITheme.flat(UITheme.BG, 8, 8, 2, UITheme.ACCENT))
	_chip.add_theme_stylebox_override("hover",
		UITheme.flat(UITheme.PANEL_HI, 8, 8, 2, UITheme.ACCENT))
	_chip.pressed.connect(_show_event)
	add_child(_chip)
	# Stop swallowing input for the screen behind while put away.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _show_event() -> void:
	if _done or not _hidden:
		return
	_hidden = false
	if _chip != null and is_instance_valid(_chip):
		_chip.queue_free()
	_chip = null
	_panel.visible = true
	for n in _backdrop_nodes:
		if is_instance_valid(n):
			(n as CanvasItem).visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit.call_deferred()


# Public so a test can drive the toggle without a click.
func hide_event() -> void:
	_hide_event()


func show_event() -> void:
	_show_event()


func is_hidden() -> bool:
	return _hidden


func _close() -> void:
	if _done:
		return
	_done = true
	_end_objects()
	finished.emit(_play_request)
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


# The room closes and what was in it goes. See ObjectSystem.clear_spawned_since:
# machines the event spawned are the event's, and leaving the Arcade Room is
# leaving the arcade — the cabinets do not follow you out to the board.
func _end_objects() -> void:
	if ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.disconnect(_on_objects_changed)
	ObjectSystem.clear_spawned_since(_objects_before)


# Take the event off the screen WITHOUT answering it. `finished` is the chain
# that runs when an event is over — refresh, autosave, open the shop the hub
# owes, start the game a `play_game` sent you to — and none of that should
# happen when what ended the event was the run ending under it. The player died
# on a press in here; there is no shop to walk into afterwards and no save to
# write.
func dismiss() -> void:
	if _done:
		return
	_done = true
	_end_objects()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Escape does not dismiss an open event — it has a price on both sides and a
	# stray key is not an answer. It PUTS IT AWAY instead, which is the thing the
	# player actually wants when the board is still animating behind it. While
	# hidden, Escape is none of this modal's business.
	if _hidden:
		return
	accept_event()
	_hide_event()

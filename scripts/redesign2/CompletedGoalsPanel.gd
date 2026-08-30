class_name CompletedGoalsPanel
extends Control

# CompletedGoalsPanel — WHAT YOU HAVE DONE: every goal this run has answered, in
# the order it was answered (docs/games-first-redesign.md §2.1).
#
# The checklist beside the board only ever shows what is still OWED. A row that
# is answered locks, sinks under the open ones, and then goes entirely when the
# game is handed in — which is right for a list you scan to decide what to play
# for, and leaves the run with no memory at all of the work behind it. Eight
# games in, the panel says "three things to do" and nothing whatsoever about the
# twenty already done.
#
# So the ticks are also written to a ledger the run keeps (GameLoop2.completed_goals),
# and this is that ledger read back: grouped by the GAME it was done at, newest
# game first, each line tinted by what kind of goal it was. It is a scoreboard,
# not a control — nothing in here can be claimed, unclaimed or edited, because
# every line in it is already resolved.
#
# Built and dismissed exactly like GraveyardPanel, which is its sibling in every
# respect: the host adds it and calls setup().
#
#     var panel := CompletedGoalsPanel.new()
#     add_child(panel)
#     panel.setup()

signal closed

var _closing: bool = false
var _list: VBoxContainer
var _empty: Label

const PANEL_WIDTH: int = 560
# The panel's own colour — the checklist's "you did it" green, which is what a
# ticked row goes and therefore what this whole list is made of.
const DONE := Color(0.45, 0.85, 0.55)

func setup() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	# A click outside closes; the WHEEL does not. The list scrolls, and a wheel
	# event that runs out of scroll falls through to this handler — see the same
	# note on GraveyardPanel, where reading to the bottom used to shut the panel.
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and _dismissing_button(ev.button_index):
			close())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 14, 0, 2, DONE))
	center.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel",
		UITheme.flat(DONE.lerp(UITheme.BG, 0.78), 12, 14, 0))
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 12)
	header.add_child(head_row)
	var title := Label.new()
	title.text = "✓  Completed"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", DONE.lerp(Color.WHITE, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(close)
	head_row.add_child(close_btn)
	body.add_child(header)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	pad.add_child(inner)
	body.add_child(pad)

	var blurb := Label.new()
	blurb.text = ("Every goal you have ticked this run, under the game you did it "
		+ "at. Nothing here can be claimed again — it is the run's record of the "
		+ "work behind it.")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 0)
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	inner.add_child(blurb)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_empty = Label.new()
	_empty.text = "Nothing ticked yet — the first goal you confirm lands here."
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(PANEL_WIDTH - 40, 0)
	_empty.add_theme_font_size_override("font_size", 13)
	_empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	inner.add_child(_empty)

	refill()

# Rebuild the list from the loop's ledger. Public for the same reason the
# graveyard's is: the host can redraw the panel without tearing it down.
func refill() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	# NEWEST GAME FIRST, and within a game the order the goals were ticked in. The
	# ledger appends, so the tail is the most recent — and what the player is
	# still holding in their head is the game they are on.
	for group in groups():
		_list.add_child(_group_block(group))
	if _empty != null:
		_empty.visible = GameLoop2.completed_goals.is_empty()

# The ledger as blocks of [{game: StringName, rows: Array}], newest game first,
# rows in the order they were done. Consecutive lines at the same game are one
# block — the run can come BACK to a game it already played, and two visits are
# two blocks, because they are two separate sittings and the second one is the
# recent news.
#
# Public so a headless test can ask what the panel is about to draw without
# walking Controls for it.
func groups() -> Array:
	var out: Array = []
	for row in GameLoop2.completed_goals:
		if not (row is Dictionary):
			continue
		var at: StringName = StringName((row as Dictionary).get("game", &""))
		if out.is_empty() or StringName(out[out.size() - 1]["game"]) != at:
			out.append({"game": at, "rows": []})
		(out[out.size() - 1]["rows"] as Array).append(row)
	out.reverse()
	return out

# One game's worth: the game's name as a heading, then its lines.
func _group_block(group: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 8, 8, 1, DONE.lerp(UITheme.BG, 0.62)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	wrap.add_child(col)

	var rows: Array = group.get("rows", [])
	var game: GameData = Data.get_game(StringName(group.get("game", &"")))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var where := Label.new()
	where.text = game.display_name if game != null else "Before the road started"
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.add_theme_font_size_override("font_size", 14)
	where.add_theme_color_override("font_color", UITheme.GOLD)
	head.add_child(where)
	var count := Label.new()
	count.text = "%d done" % rows.size()
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)

	for row in rows:
		col.add_child(_line(row as Dictionary))
	return wrap

# One answered goal, exactly as its checklist row read when it was ticked — with
# a ✓ in front of it and the kind's own colour on it, so a panel of thirty lines
# still separates "an enemy went down" from "a curse was followed" at a glance.
func _line(row: Dictionary) -> Control:
	var l := Label.new()
	l.text = "✓  %s" % String(row.get("text", ""))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", tint_for(String(row.get("kind", ""))))
	return l

# The kinds the ledger records, in the colours the checklist itself uses for
# them, so a line reads the same here as it did on the row it came from.
static func tint_for(kind: String) -> Color:
	match kind:
		"enemy":
			return UITheme.TEXT
		"curse":
			return UITheme.CURSE
		"event":
			return UITheme.ACCENT
		_:
			# Level-ups, player statuses and enemy bonuses — everything the
			# checklist draws in its "something you earned" gold.
			return UITheme.GOLD

# Which mouse buttons mean "I am done with this panel" — the three real ones, and
# none of the four wheel directions (see the gui_input handler in setup()).
func _dismissing_button(button: int) -> bool:
	return button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]

# Dismiss the panel. Safe to call twice — the second call is a no-op.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()

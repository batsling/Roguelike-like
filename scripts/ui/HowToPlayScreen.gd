class_name HowToPlayScreen
extends Control

# The manual. A chapter list down the left, the chapter itself down the right.
#
# It knows nothing about what the manual SAYS — every word lives in
# `HowToPlayText`, and this file only knows how to draw the seven block kinds
# that file emits. That split is the point: the text is the thing that will be
# edited constantly as the build changes, and editing it should never mean
# reading layout code.
#
# Two columns rather than one long scroll, because the manual is thirteen
# chapters and a player opening it mid-run wants ONE of them. A scroll makes you
# hunt; a list of chapters is a question you can answer in a glance. The list
# also doubles as the manual's own table of contents on the main menu (the
# bottom-left panel), so the two entry points can never drift apart — they are
# built from the same array.
#
# Built entirely in code and runs PROCESS_MODE_ALWAYS, mirroring the overlay
# pattern Collection and TierListScreen use, so it works over a paused run.

const SIDEBAR_W := 268.0
const BODY_MAX_W := 720.0

var _chapters: Array = []
var _body: VBoxContainer = null
var _body_scroll: ScrollContainer = null
var _chapter_buttons: Array[Button] = []
var _index: int = 0
var _title_label: Label = null
var _prev_btn: Button = null
var _next_btn: Button = null


# `chapter` is an index into HowToPlayText.chapters(), or an id (&"gold") — the
# main menu's contents panel passes an id, since a panel that hardcoded index 7
# would open the wrong page the day a chapter is inserted above it.
static func open(parent: Node, chapter = 0) -> HowToPlayScreen:
	var s := HowToPlayScreen.new()
	parent.add_child(s)
	s.go_to(chapter)
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.shared()
	_chapters = HowToPlayText.chapters()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(
		func(): set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT))
	_build_shell()
	_show_chapter(_index)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	queue_free()


# Public so a test — or the menu's contents panel — can turn to a page without a
# click. Accepts an index or a chapter id.
func go_to(chapter) -> void:
	var idx: int = chapter if chapter is int else index_of(StringName(chapter))
	_index = clampi(idx, 0, maxi(0, _chapters.size() - 1))
	if _body != null:
		_show_chapter(_index)


func index_of(id: StringName) -> int:
	for i in range(_chapters.size()):
		if StringName(_chapters[i]["id"]) == id:
			return i
	return 0


# --- shell ------------------------------------------------------------------

func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG_DEEP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(_build_header())

	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 16)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body_row)
	body_row.add_child(_build_sidebar())
	body_row.add_child(_build_reader())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "📖  How to Play"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	row.add_child(title)

	var sub := Label.new()
	sub.text = "The dungeon is your backlog."
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	row.add_child(sub)

	var close := Button.new()
	close.text = "✕  Close"
	close.custom_minimum_size = Vector2(110, 34)
	close.pressed.connect(close_screen)
	row.add_child(close)
	return row


# Named rather than passing `close` straight to `pressed`, because Control
# already has a `close` in spirit and a signal bound to a one-word method here is
# the kind of thing that silently binds to the wrong one after a refactor.
func close_screen() -> void:
	close()


func _build_sidebar() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(SIDEBAR_W, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size = Vector2(SIDEBAR_W - 14.0, 0)
	scroll.add_child(col)

	_chapter_buttons.clear()
	for i in range(_chapters.size()):
		var ch: Dictionary = _chapters[i]
		var btn := Button.new()
		btn.text = "%s  %d. %s" % [ch.get("icon", "•"), i + 1, ch["title"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.tooltip_text = String(ch.get("blurb", ""))
		btn.custom_minimum_size = Vector2(0, 34)
		btn.clip_text = true
		var idx: int = i
		btn.pressed.connect(func(): _show_chapter(idx))
		col.add_child(btn)
		_chapter_buttons.append(btn)
	return scroll


func _build_reader() -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG, UITheme.BORDER, 10, 16))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	frame.add_child(col)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", UITheme.ACCENT)
	col.add_child(_title_label)
	col.add_child(HSeparator.new())

	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body_scroll)

	# A reading column, not a page width. Prose set across a 2560px monitor is
	# unreadable however good the words are, so the body is capped and the rest
	# of the room is left empty on purpose.
	var centre := HBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(centre)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	# SHRINK_BEGIN, so the column holds the width it asks for instead of being
	# stretched to the panel. The gutter beside it takes everything left over —
	# that empty strip is the measure working, not a layout bug.
	_body.custom_minimum_size = Vector2(BODY_MAX_W, 0)
	_body.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	centre.add_child(_body)
	var gutter := Control.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_child(gutter)

	col.add_child(_build_pager())
	return frame


func _build_pager() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	_prev_btn = Button.new()
	_prev_btn.text = "◀  Back"
	_prev_btn.custom_minimum_size = Vector2(120, 32)
	_prev_btn.pressed.connect(func(): _show_chapter(_index - 1))
	row.add_child(_prev_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_next_btn = Button.new()
	_next_btn.text = "Next  ▶"
	_next_btn.custom_minimum_size = Vector2(120, 32)
	_next_btn.pressed.connect(func(): _show_chapter(_index + 1))
	row.add_child(_next_btn)
	return row


# --- drawing one chapter ----------------------------------------------------

func _show_chapter(i: int) -> void:
	if _chapters.is_empty():
		return
	_index = clampi(i, 0, _chapters.size() - 1)
	var ch: Dictionary = _chapters[_index]
	_title_label.text = "%s  %s" % [ch.get("icon", ""), ch["title"]]
	# Detached as well as freed. A queue_freed node is still parented until the
	# end of the frame, so turning two pages in one frame would draw the second
	# chapter underneath the first one's corpse.
	for b in _body.get_children():
		_body.remove_child(b)
		b.queue_free()

	var blocks: Array = ch.get("blocks", [])
	var j: int = 0
	while j < blocks.size():
		var block: Dictionary = blocks[j]
		if String(block.get("k", "")) == "row":
			# A run of consecutive rows is ONE grid — that is the only way the
			# columns of a table line up with each other — so the run is taken
			# whole here and the cursor jumps past it.
			var run: Array = []
			while j < blocks.size() \
					and String((blocks[j] as Dictionary).get("k", "")) == "row":
				run.append(blocks[j])
				j += 1
			_body.add_child(_table(run))
			continue
		var drawn: Control = _block(block)
		if drawn != null:
			_body.add_child(drawn)
		j += 1

	for bi in range(_chapter_buttons.size()):
		var on: bool = bi == _index
		_chapter_buttons[bi].add_theme_color_override("font_color",
			UITheme.GOLD if on else UITheme.TEXT_DIM)
		_chapter_buttons[bi].add_theme_stylebox_override("normal",
			UITheme.flat(UITheme.PANEL_HI, 6, 6) if on else StyleBoxEmpty.new())

	_prev_btn.disabled = _index <= 0
	_next_btn.disabled = _index >= _chapters.size() - 1
	_next_btn.text = "Next  ▶" if _index < _chapters.size() - 1 else "The end"
	# A chapter opened from the menu starts at the top of itself, not wherever
	# the last one was scrolled to.
	if _body_scroll != null:
		_body_scroll.set_deferred("scroll_vertical", 0)


func _block(block: Dictionary) -> Control:
	match String(block.get("k", "")):
		"h":
			var h := Label.new()
			h.text = String(block["t"])
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.custom_minimum_size = Vector2(0, 26)
			h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			h.add_theme_font_size_override("font_size", 15)
			h.add_theme_color_override("font_color", UITheme.GOLD)
			return h
		"p":
			return _prose(String(block["t"]), UITheme.TEXT, 0.0)
		"b":
			return _prose("•   " + String(block["t"]), UITheme.TEXT, 10.0)
		"step":
			return _prose("%d.   %s" % [int(block.get("n", 1)), String(block["t"])],
				UITheme.TEXT, 10.0)
		"kv":
			return _definition(String(block["t"]), String(block.get("v", "")))
		"note":
			return _callout(String(block["t"]))
	return null


# One paragraph. `indent` hangs bullets and steps off their marker rather than
# letting the wrap run back under it.
func _prose(text: String, color: Color, indent: float) -> Control:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(BODY_MAX_W - indent, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	if indent <= 0.0:
		return lbl
	var row := MarginContainer.new()
	row.add_theme_constant_override("margin_left", int(indent))
	row.add_child(lbl)
	return row


# Term on the left, meaning on the right. The term column is fixed so a run of
# definitions lines up as a table rather than as ragged prose.
func _definition(term: String, meaning: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var t := Label.new()
	t.text = term
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(170, 0)
	t.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", UITheme.ACCENT)
	row.add_child(t)

	var v := Label.new()
	v.text = meaning
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size = Vector2(BODY_MAX_W - 190.0, 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(v)
	return row


func _callout(text: String) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL, 6, 10, 1, UITheme.ACCENT_DIM))
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(BODY_MAX_W - 24.0, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	frame.add_child(lbl)
	return frame


# A consecutive run of {"k": "row"} blocks, drawn as one grid so the columns of
# a table actually line up with each other.
func _table(rows: Array) -> Control:
	var cols: int = 1
	for r in rows:
		cols = maxi(cols, (r.get("c", []) as Array).size())
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	grid.custom_minimum_size = Vector2(BODY_MAX_W, 0)
	for r in rows:
		var head: bool = bool(r.get("head", false))
		var cells: Array = r.get("c", [])
		for c in range(cols):
			var lbl := Label.new()
			lbl.text = String(cells[c]) if c < cells.size() else ""
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.custom_minimum_size = Vector2(BODY_MAX_W / float(cols) - 16.0, 0)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.add_theme_color_override("font_color",
				UITheme.TEXT_FAINT if head else UITheme.TEXT)
			grid.add_child(lbl)
	return grid

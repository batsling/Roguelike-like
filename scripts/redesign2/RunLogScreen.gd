class_name RunLogScreen
extends Control

# THE RUN'S HISTORY — everything that has happened, in the order it happened,
# grouped by the game the run was standing on at the time.
#
# The run already wrote all of this down: every game taken, every enemy that
# walked on and every goal cleared, every event answered, every item and piece of
# loot taken or spent, every shop purchase, every lost run and what the turn it
# bought cost. It went to `GameLog`, whose only reader was a single-line readout
# in the play panel showing the LAST thing that happened. So the record existed
# and could not be read: a player who looked away during a resolve, or who came
# back to a run the next evening, had no way to find out what had gone on.
#
# GROUPED BY STOP, newest first (`GameLog.by_stop`). A flat list of 300 lines is
# a wall; the same lines under the cover of the game they happened at is a run you
# can scan. A second visit to a game gets a second group rather than being folded
# into the first — going back is a decision the player made and paid a Dash for.
#
# READ-ONLY, and deliberately so. Nothing here is a button: it is the record, and
# a record you can act on is a save-scum.

signal finished

const PANEL_W := 720
const COVER := Vector2(44, 58)

var _layer: CanvasLayer = null
var _rows: VBoxContainer = null

static func open(parent: Node) -> RunLogScreen:
	var s := RunLogScreen.new()
	s._layer = CanvasLayer.new()
	# Over the run's pinned header, the way every other full-screen reference
	# screen in a run is — the header is reporting a run this screen is about.
	s._layer.layer = UITheme.Layer.VERDICT
	s._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(s._layer)
	s._layer.add_child(s)
	return s

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.shared()
	UITheme.dress(self)
	_build()

func close() -> void:
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		close()

# ---------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG, UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 12, 16, 2))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP)
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "🕮  RUN HISTORY"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	head.add_child(title)
	var sub := Label.new()
	sub.text = "newest first"
	sub.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
	sub.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	head.add_child(sub)

	# THE HEIGHT IS FIXED AND THE LIST SCROLLS. A run's log is unbounded (500 lines
	# is the cap GameLog keeps), so a panel sized to its content would grow past the
	# window and take its own Close button with it.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	scroll.add_child(_rows)
	_fill()

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	close_btn.pressed.connect(close)
	box.add_child(close_btn)

func _fill() -> void:
	var stops: Array = GameLog.by_stop()
	if stops.is_empty():
		var empty := Label.new()
		empty.text = "Nothing has happened yet."
		empty.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		empty.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		_rows.add_child(empty)
		return
	for stop in stops:
		_rows.add_child(_stop_block(stop))

# One stretch of the run: the game it was standing on, and the lines written while
# it was there — NEWEST FIRST inside the group as well as between groups, so the
# most recent thing that happened is the first thing on the screen.
func _stop_block(stop: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL, 8, 8, 1, UITheme.BORDER))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	wrap.add_child(box)

	box.add_child(_stop_head(StringName(stop.get("game", &""))))
	var lines: Array = (stop.get("lines", []) as Array).duplicate()
	lines.reverse()
	for entry in lines:
		var l := Label.new()
		l.text = "•  %s" % String(entry.get("text", ""))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		# THE LINE'S OWN COLOUR, which is the category the log already carries: a
		# lost run is DANGER, a shop line is green, a curse is purple. Nothing had
		# to be re-tagged for this screen to be readable by kind.
		l.add_theme_color_override("font_color", entry.get("color", UITheme.TEXT))
		box.add_child(l)
	return wrap

# The heading of one stop: the game's cover and name, or a plain label for the
# lines written before the run had a position at all.
func _stop_head(gid: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	var game: GameData = Data.get_game(gid) if gid != &"" else null
	if game != null and game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = COVER
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(art)
	var name_lbl := Label.new()
	name_lbl.text = game.display_name if game != null else "Before the run set out"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	name_lbl.add_theme_color_override("font_color", UITheme.GOLD)
	row.add_child(name_lbl)
	return row

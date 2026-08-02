class_name RunHistoryScreen
extends Control

# Run History — every finished run as the route it actually walked.
#
# Opens OVER the Atlas, so a run reads at two altitudes at once: the strip here
# is the route in order, and the sky behind it is where that route went. Clicking
# a run frames it on the map underneath.
#
# Each run is one row: cover art left to right in the order the games were
# played, an arrow between each pair, and the Amulet at the end marked won or
# lost. That is the whole point of the screen — a run is a journey through real
# games, and a list of names doesn't read like one.
#
# Runs come from GameStats.runs, written by GameLoop2._finish_run. A run that
# never left its starting game isn't recorded, since there's no route to draw.

signal finished

const COVER := Vector2(84, 112)
const ARROW_W := 26.0

var _atlas: AtlasView = null       # the map underneath, if one was opened with us
var _rows: VBoxContainer = null

static func open(parent: Node, atlas: AtlasView = null) -> RunHistoryScreen:
	var s := RunHistoryScreen.new()
	s._atlas = atlas
	parent.add_child(s)
	return s

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	theme = UITheme.shared()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build()

func _fit_to_viewport() -> void:
	var rect: Rect2 = get_viewport().get_visible_rect()
	set_deferred("size", rect.size)
	position = Vector2.ZERO

func run_count() -> int:
	return GameStats.runs.size()

# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _build() -> void:
	# Only a scrim, not an opaque panel: the Atlas stays visible underneath,
	# which is the point of putting this on top of the map.
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(UITheme.BG_DEEP, 0.84)
	add_child(scrim)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_header())

	var scroller := ScrollContainer.new()
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroller)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroller.add_child(_rows)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.remove_child(_rows)
	margin.add_child(_rows)
	scroller.add_child(margin)

	if GameStats.runs.is_empty():
		var empty := Label.new()
		empty.text = "No finished runs yet.\nWin or lose one and its route shows up here."
		empty.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 15)
		_rows.add_child(empty)
		return

	for run in GameStats.runs:
		_rows.add_child(_run_row(run))

func _header() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 0, 12, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	var title := Label.new()
	title.text = "🕮  Run History"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	row.add_child(title)

	var count := Label.new()
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wins: int = 0
	for run in GameStats.runs:
		if bool(run.get("won", false)):
			wins += 1
	count.text = "%d run%s · %d won" % [
		GameStats.runs.size(), "" if GameStats.runs.size() == 1 else "s", wins]
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(count)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_finish)
	row.add_child(close)
	return bar

# One run: a header line, then its route as covers and arrows left to right.
func _run_row(run: Dictionary) -> Control:
	var won: bool = bool(run.get("won", false))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat(
		UITheme.PANEL, 6, 12, 1, UITheme.SUCCESS if won else UITheme.BORDER))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(_run_caption(run))

	# The route. Horizontally scrollable on its own, because a long run is wider
	# than the screen and the page must never scroll sideways as a whole.
	var strip_scroll := ScrollContainer.new()
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_scroll.custom_minimum_size.y = COVER.y + 34
	strip_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(strip_scroll)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 0)
	strip_scroll.add_child(strip)

	var path: Array = run.get("path", [])
	var amulet := StringName(String(run.get("amulet", "")))
	for i in range(path.size()):
		var id := StringName(String(path[i]))
		strip.add_child(_route_stop(id, id == amulet, won))
		if i < path.size() - 1:
			strip.add_child(_arrow())
	# The Amulet is the goal, so it closes the route even on a run that died
	# before reaching it — that's what makes a loss legible as a loss.
	if amulet != &"" and (path.is_empty() or StringName(String(path[path.size() - 1])) != amulet):
		strip.add_child(_arrow(true))
		strip.add_child(_route_stop(amulet, true, won))
	return panel

func _run_caption(run: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var verdict := Label.new()
	var won: bool = bool(run.get("won", false))
	verdict.text = "★ WON" if won else "DIED"
	verdict.add_theme_font_size_override("font_size", 12)
	verdict.add_theme_color_override("font_color", UITheme.SUCCESS if won else UITheme.DANGER)
	row.add_child(verdict)

	var who: CharacterData = Data.get_character2(StringName(String(run.get("character", ""))))
	var detail := Label.new()
	var parts: Array = []
	if who != null:
		parts.append(who.display_name)
	parts.append("%d game%s" % [int(run.get("beaten", 0)),
		"" if int(run.get("beaten", 0)) == 1 else "s"])
	var when: int = int(run.get("at", 0))
	if when > 0:
		var d: Dictionary = Time.get_datetime_dict_from_unix_time(when)
		parts.append("%04d-%02d-%02d" % [d["year"], d["month"], d["day"]])
	detail.text = "  ·  ".join(parts)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(detail)

	# The map is right behind this screen, so a run can be thrown onto it.
	if _atlas != null:
		var show := Button.new()
		show.text = "✦ Show on map"
		show.add_theme_font_size_override("font_size", 11)
		show.pressed.connect(func(): _show_on_map(run))
		row.add_child(show)
	return row

# One game on the route: its cover, its name, and a marker if it was the goal.
func _route_stop(id: StringName, is_amulet: bool, won: bool) -> Control:
	var game: GameData = Data.get_game(id)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size.x = COVER.x

	var frame := PanelContainer.new()
	var border: Color = UITheme.BORDER
	var border_w: int = 1
	if is_amulet:
		border = UITheme.GOLD if won else UITheme.DANGER
		border_w = 2
	frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG_DEEP, 4, 2, border_w, border))
	col.add_child(frame)

	if game != null and game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = COVER
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(art)
	else:
		var blank := ColorRect.new()
		blank.custom_minimum_size = COVER
		blank.color = UITheme.PANEL
		frame.add_child(blank)

	var label := Label.new()
	label.text = ("🏆 " if is_amulet else "") + (game.display_name if game != null else String(id))
	label.custom_minimum_size.x = COVER.x
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color",
		UITheme.GOLD if is_amulet else UITheme.TEXT_DIM)
	col.add_child(label)
	return col

# The arrow between two stops. `unreached` marks the gap between where a lost run
# stopped and the Amulet it never got to.
func _arrow(unreached: bool = false) -> Control:
	var a := RouteArrow.new()
	a.unreached = unreached
	a.custom_minimum_size = Vector2(ARROW_W, COVER.y)
	return a

func _show_on_map(run: Dictionary) -> void:
	if _atlas == null:
		return
	var path: Array = run.get("path", [])
	if path.is_empty():
		return
	_atlas.frame_games(path)
	_finish()

func _finish() -> void:
	finished.emit()
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_finish()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# RouteArrow — a single left-to-right arrow between two stops.
# ---------------------------------------------------------------------------

class RouteArrow extends Control:
	var unreached: bool = false

	func _draw() -> void:
		var y: float = size.y * 0.5
		var col: Color = UITheme.TEXT_FAINT if unreached else UITheme.ACCENT
		var tip := Vector2(size.x - 4.0, y)
		if unreached:
			# The stretch a lost run never covered, so it reads as a gap.
			draw_dashed_line(Vector2(4, y), tip, col, 2.0, 5.0, true)
		else:
			draw_line(Vector2(4, y), tip, col, 2.0, true)
		draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(-7, -5), tip + Vector2(-7, 5)]), col)

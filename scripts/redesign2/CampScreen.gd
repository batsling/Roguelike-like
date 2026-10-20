extends Control

# CampScreen — the end-of-session camp (scripts/runtime/Camp.gd,
# docs/rest-site-design.md). Two cards, Rest and the one the session's games
# dealt, and a way back to the run. Picking one emits `chose`; what the choice DOES is the
# page's (Overworld2.camp_choose), because two of the five open a pick in the pack
# and one opens the loot offer, and both of those live on the page.
#
# Loaded by path from Overworld2, with no class_name, for the reason OwnedPick is:
# it is on screen once a session, and the page's compile should not pay for it.

signal chose(option: Dictionary)
signal finished

const Camp := preload("res://scripts/runtime/Camp.gd")
const ACCENT := Color(1.0, 0.62, 0.3)
# Two cards and nothing else on the screen, so each is big: the choice is the
# whole of the scene, and on stream it is read across a room. Both are the same
# size, whatever their words, with what is on them centred in it.
const CARD_W := 300.0
const CARD_H := 200.0
const ICON_PX := 64
# The journey: every stop the run has walked, cover to cover with the road's own
# arrow between, wrapping onto a second row on a long run rather than scrolling.
const JOURNEY_W := 900.0
const STOP := Vector2(54, 72)
# …and the size a long road shrinks to before it starts folding its oldest stops
# into "+N earlier": the screen fits a 1280x720 page with the road at two rows.
const STOP_SMALL := Vector2(40, 54)
const ROAD_ROWS := 2
const ARROW_W := 18.0
# A stop from an earlier session is drawn faded, so this session's stand out.
const EARLIER_ALPHA := 0.4
const ROUTE_ARROW := preload("res://scripts/ui/RouteArrow.gd")

var _options: Array = []
var _layer: CanvasLayer = null
var _done: bool = false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

static func open(host: Node, options: Array) -> Control:
	var modal = load("res://scripts/redesign2/CampScreen.gd").new()
	modal._options = options
	modal._layer = CanvasLayer.new()
	modal._layer.layer = UITheme.Layer.EVENT
	modal._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(modal._layer)
	modal._layer.add_child(modal)
	modal._build()
	return modal

# The cards on offer, for tests and the driver, in card order.
func options() -> Array:
	return _options.duplicate()

func _build() -> void:
	var width: float = maxf(JOURNEY_W,
		CARD_W * maxi(1, _options.size()) + UITheme.GAP_LOOSE * (_options.size() + 3))
	var panel := ModalScaffold.build_panel(self, ACCENT, Callable(), Vector2(width, 0))
	panel.custom_minimum_size = Vector2(width, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UITheme.GAP_SECTION)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	margin.add_child(root)

	root.add_child(_line("Make Camp", ACCENT, UITheme.FONT_TITLE_LG, width))
	root.add_child(_line("The journey so far — this session's games are lit, earlier ones faded.",
		UITheme.TEXT_DIM, UITheme.FONT_BODY, width))

	root.add_child(_journey(width - UITheme.GAP_SECTION * 2))
	root.add_child(_stats_row())
	root.add_child(_line("Take one.", UITheme.TEXT_DIM, UITheme.FONT_BODY, width))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	root.add_child(row)
	for opt in _options:
		row.add_child(_card(opt))

	var later := UITheme.confirm_button("Back to the run", Vector2(160, 32))
	later.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	later.tooltip_text = "Don't leave yet. These two cards wait for you on the way out."
	later.pressed.connect(close)
	root.add_child(later)

# THE JOURNEY SO FAR: the road walked, repeats included (GameState.walked_path),
# each stop bordered by how it went — green beaten, orange walked away from, the
# same two colours the header strip and the run-over screen use. The stops walked
# THIS SESSION (since Camp.session_start_index) are drawn full and ringed thicker;
# the earlier ones are faded, so the session reads as the bright end of the road.
func _journey(width: float) -> Control:
	var road := HFlowContainer.new()
	road.custom_minimum_size = Vector2(width, 0)
	road.alignment = FlowContainer.ALIGNMENT_CENTER
	road.add_theme_constant_override("h_separation", UITheme.GAP_TIGHT)
	road.add_theme_constant_override("v_separation", UITheme.GAP_SNUG)
	var stops: Array = GameState.walked_path()
	var won: Array = GameState.walked_outcomes()
	var from: int = Camp.session_start_index()
	# Big stops while the road fits in ROAD_ROWS rows; then small ones; then the
	# oldest fold into one "+N earlier" chip, so the newest — this session's — are
	# always on screen.
	var size: Vector2 = STOP
	if stops.size() > _per_row(width, STOP) * ROAD_ROWS:
		size = STOP_SMALL
	var room: int = _per_row(width, size) * ROAD_ROWS
	var first: int = 0
	if stops.size() > room:
		first = stops.size() - (room - 1)
		var more := _line("+%d\nearlier" % first, UITheme.TEXT_FAINT, UITheme.FONT_SMALL, 0.0)
		more.custom_minimum_size = Vector2(size.x, size.y)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		road.add_child(more)
	for i in range(first, stops.size()):
		road.add_child(_stop(StringName(stops[i]), i < won.size() and bool(won[i]), i >= from, size))
		if i < stops.size() - 1:
			var a := ROUTE_ARROW.new()
			a.custom_minimum_size = Vector2(ARROW_W, size.y)
			a.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if i + 1 < from:
				a.modulate.a = EARLIER_ALPHA
			road.add_child(a)
	return road

# How many stops (with the arrow after each) one row of `width` holds at `size`.
func _per_row(width: float, size: Vector2) -> int:
	var each: float = size.x + 4.0 + ARROW_W + UITheme.GAP_TIGHT * 2
	return maxi(1, int(width / each))

func _stop(id: StringName, beaten: bool, this_session: bool, size: Vector2 = STOP) -> Control:
	var game: GameData = Data.get_game(id)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG_DEEP, 3, 1,
		2 if this_session else 1, UITheme.SUCCESS if beaten else UITheme.UNBEATEN))
	frame.set_meta("stop", id)
	frame.set_meta("this_session", this_session)
	var name_text: String = game.display_name if game != null else String(id)
	frame.tooltip_text = "%s — %s%s" % [name_text, "beaten" if beaten else "walked away from",
		" (this session)" if this_session else ""]
	if not this_session:
		frame.modulate.a = EARLIER_ALPHA
	if game != null and game.cover_image != null:
		var art := TextureRect.new()
		art.texture = game.cover_image
		art.custom_minimum_size = size
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(art)
	else:
		var blank := _line(name_text.substr(0, 2), UITheme.TEXT_DIM, UITheme.FONT_SMALL, 0.0)
		blank.custom_minimum_size = size
		blank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(blank)
	return frame

# The session in numbers (Camp.session_stats), one line of figures over a line of
# what each is, centred under the road.
func _stats_row() -> Control:
	var st: Dictionary = Camp.session_stats()
	var games: int = int(st["games"])
	var hp: int = int(st["hp_change"])
	var cells: Array = [
		[str(games), "game%s played" % ("" if games == 1 else "s")],
		[str(int(st["beaten"])), "beaten"],
		[str(int(st["goals"])), "goals done"],
		[str(int(st["enemies"])), "enemies down"],
		[str(int(st["lost_runs"])), "lost runs"],
		[("+%d" % hp) if hp > 0 else str(hp), "Health"],
		[Camp.duration_text(float(st["seconds"])), "played"],
	]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITheme.GAP_BREAK)
	for c in cells:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", UITheme.GAP_NONE)
		col.add_child(_line(String(c[0]), ACCENT, UITheme.FONT_HEAD, 0.0))
		col.add_child(_line(String(c[1]), UITheme.TEXT_FAINT, UITheme.FONT_SMALL, 0.0))
		row.add_child(col)
	return row

# The session's numbers, for tests: the same dictionary the row draws.
func session_stats() -> Dictionary:
	return Camp.session_stats()

# The stops the journey draws, in order, as {id, this_session}, for tests.
func journey_stops() -> Array:
	var out: Array = []
	_collect_stops(self, out)
	return out

func _collect_stops(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c.has_meta("stop"):
			out.append({"id": c.get_meta("stop"), "this_session": c.get_meta("this_session")})
		else:
			_collect_stops(c, out)

# One option: its mark, what it is, what it does, and — for the dealt one — the
# game whose type dealt it, named under the rest. No cover: the card is about
# what you take, and the game is a line of credit, not the picture.
func _card(opt: Dictionary) -> Control:
	var info: Dictionary = Camp.describe(StringName(opt.get("id", &"")))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG, 8, 8, 1, UITheme.BORDER))
	btn.add_theme_stylebox_override("hover", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("pressed", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.75), 8, 8, 2, ACCENT))
	btn.add_theme_stylebox_override("focus", UITheme.flat(ACCENT.lerp(UITheme.BG, 0.85), 8, 8, 2, ACCENT))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(_pick.bind(opt))

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = UITheme.GAP
	col.offset_right = -UITheme.GAP
	col.offset_top = UITheme.GAP
	col.offset_bottom = -UITheme.GAP
	col.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	if String(info.get("icon", "")) == "":
		var art: TextureRect = UITheme.crisp_tex(UITheme.SHIELD_ART, ICON_PX)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(art)
	else:
		col.add_child(_line(String(info["icon"]), ACCENT, UITheme.FONT_HERO, CARD_W))
	col.add_child(_line(String(info["title"]), ACCENT, UITheme.FONT_DISPLAY, CARD_W))
	col.add_child(_line(String(info["text"]), UITheme.TEXT, UITheme.FONT_LEAD, CARD_W))
	var game: GameData = Data.get_game(StringName(opt.get("game", &"")))
	if game != null:
		col.add_child(_line("from %s" % game.display_name, UITheme.TEXT_FAINT,
			UITheme.FONT_SMALL, CARD_W))
	# A Button does not grow to a child it does not lay out, so a card whose words
	# wrap past CARD_H takes the column's height — never less than CARD_H, so the
	# two stay the same size.
	col.minimum_size_changed.connect(func():
		btn.custom_minimum_size = Vector2(CARD_W, maxf(CARD_H,
			col.get_combined_minimum_size().y + UITheme.GAP * 2)))
	return btn

func _line(text: String, color: Color, size: int, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A width of 0 is a figure that sizes itself and never wraps.
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width - UITheme.GAP * 2, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Public so a test or a driver can answer without clicking.
func pick(opt: Dictionary) -> void:
	_pick(opt)

func _pick(opt: Dictionary) -> void:
	if _done:
		return
	_done = true
	chose.emit(opt)
	close()

func close() -> void:
	_done = true
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

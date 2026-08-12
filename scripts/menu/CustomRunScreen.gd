class_name CustomRunScreen
extends Control

# CustomRunScreen — "build me a run out of THESE games" (RunConfig).
#
# An ordinary run is rolled off the whole catalog with one global switch on it.
# This is the screen for the runs that switch cannot describe: a deckbuilder-only
# map, an opening drawn from games you have never beaten, a run aimed squarely at
# Balatro, a short four-game sprint.
#
# It is built around the fact that there are THREE filters and not one, because
# the three questions are independent (see RunConfig):
#
#   THE MAP     which games the run graph is made of
#   THE START   which of those may be an opening card
#   THE AMULET  which of those may be the game the run is a search for
#
# So the screen is three identical columns. Same four axes in each — library,
# genre, record, years — because a filter that reads differently in each column
# would be three things to learn instead of one, and because the interesting runs
# come from the columns DISAGREEING ("any map, deckbuilder start, an amulet I've
# never won on"). Under each is the count of games that survive it, live, which is
# what turns "is this run even possible" from something you find out by pressing
# Begin into something you read while you are choosing.
#
# Below the columns: the run length, and an optional named target. The target is
# the sharpest tool here and it composes with the band rather than overriding it —
# name Balatro and set 4–5 games and you are offered starts four or five games out
# from Balatro.
#
# Built in code on its own layer, like every other screen in the project.

signal begun(config: Dictionary)     # Begin pressed; carries the RunConfig payload
signal cancelled

const PANEL_SIZE := Vector2(1140, 640)
const COLUMN_MIN := Vector2(320, 0)

# The three columns, by the key they write into the payload.
const COLUMNS: Array = [
	{"key": "map", "title": "THE MAP",
	 "blurb": "Which games the run's graph is made of. Everything else is picked from inside this."},
	{"key": "start", "title": "THE START",
	 "blurb": "Which of those may be offered as an opening card."},
	{"key": "amulet", "title": "THE AMULET",
	 "blurb": "Which of those may be the game the run is a search for."},
]

const LIBRARY_ITEMS: Array = ["Any", "Owned", "Downloaded", "Not owned"]
const RECORD_ITEMS: Array = ["Any", "Beaten", "Never beaten", "Amulet won"]

var _layer: CanvasLayer = null
var _specs: Dictionary = {}          # key -> spec Dictionary
var _counts: Dictionary = {}         # key -> Label
var _min_path: int = RunGraph.MIN_PATH_LENGTH
var _max_path: int = RunGraph.MAX_PATH_LENGTH
var _amulet_id: StringName = &""
var _band_label: Label = null
var _target_label: Label = null
var _target_search: LineEdit = null
var _target_results: VBoxContainer = null
var _verdict: Label = null
var _begin_btn: Button = null

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

static func open(host: Node) -> CustomRunScreen:
	var screen := CustomRunScreen.new()
	screen._layer = CanvasLayer.new()
	screen._layer.layer = 120
	screen._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(screen._layer)
	screen._layer.add_child(screen)
	screen._build()
	return screen

# --- the payload -----------------------------------------------------------

# What Begin hands over — the same shape RunConfig.apply reads.
func config() -> Dictionary:
	return {
		"map": (_specs["map"] as Dictionary).duplicate(true),
		"start": (_specs["start"] as Dictionary).duplicate(true),
		"amulet": (_specs["amulet"] as Dictionary).duplicate(true),
		"min_path": _min_path,
		"max_path": _max_path,
		"amulet_id": String(_amulet_id),
	}

# --- building --------------------------------------------------------------

func _build() -> void:
	for col in COLUMNS:
		_specs[col["key"]] = RunConfig.default_spec()

	theme = UITheme.shared()
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.8)
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	var view: Vector2 = get_viewport_rect().size
	panel.custom_minimum_size = Vector2(
		minf(PANEL_SIZE.x, maxf(640.0, view.x - 40.0)),
		minf(PANEL_SIZE.y, maxf(440.0, view.y - 40.0)))
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG, UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 12, 20, 2))
	centre.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	root.add_child(_header())

	# The three columns. Equal width and the same controls in the same order in
	# each, so the eye compares them across rather than reading three panels.
	#
	# In a scroll box, and with a modest minimum height, for one reason: the panel
	# is sized by what is inside it, and the bottom of this screen is where Begin
	# lives. Left to push, three tall columns run the buttons off a 720 window — so
	# the columns are the part that gives, and the run length, the target, the
	# verdict and the buttons stay pinned to the bottom where they can always be
	# reached.
	var column_room := ScrollContainer.new()
	column_room.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Tall enough that the column's own footer — the live count, the whole reason
	# the column is legible while you are setting it — is above the fold rather than
	# a scroll away.
	column_room.custom_minimum_size.y = 392
	column_room.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(column_room)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column_room.add_child(columns)
	for col in COLUMNS:
		columns.add_child(_filter_column(col))

	root.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 18)
	root.add_child(bottom)
	bottom.add_child(_band_block())
	bottom.add_child(_target_block())

	_verdict = Label.new()
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict.add_theme_font_size_override("font_size", 12)
	root.add_child(_verdict)

	root.add_child(_buttons())
	_refresh()

func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var title := Label.new()
	title.text = "Custom Run"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "Three filters, not one: what the map is made of, where you may start, and what you're looking for."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	col.add_child(sub)

	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Back to the menu — nothing is started."
	close.custom_minimum_size = Vector2(38, 0)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_cancel)
	row.add_child(close)
	return row

# One column: a heading, what the filter is FOR in a sentence, the four axes, and
# the live count of games that survive it.
func _filter_column(col: Dictionary) -> Control:
	var key: String = col["key"]
	var frame := PanelContainer.new()
	frame.custom_minimum_size = COLUMN_MIN
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 8, 12, 1))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	frame.add_child(box)

	var head := Label.new()
	head.text = col["title"]
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(head)

	var blurb := Label.new()
	blurb.text = col["blurb"]
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size.y = 32
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(blurb)

	box.add_child(_axis_label("Library"))
	box.add_child(_option_row(LIBRARY_ITEMS, func(v): _set_axis(key, "library", v)))

	box.add_child(_axis_label("Genre"))
	box.add_child(_genre_row(key))

	box.add_child(_axis_label("Your record"))
	box.add_child(_option_row(RECORD_ITEMS, func(v): _set_axis(key, "record", v)))

	box.add_child(_axis_label("Released"))
	box.add_child(_year_row(key))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var count := Label.new()
	count.add_theme_font_size_override("font_size", 12)
	box.add_child(count)
	_counts[key] = count
	return frame

func _axis_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return l

func _option_row(items: Array, on_pick: Callable) -> OptionButton:
	var opt := OptionButton.new()
	for i in range(items.size()):
		opt.add_item(String(items[i]), i)
	opt.select(0)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.item_selected.connect(func(idx):
		on_pick.call(int(idx))
		_refresh())
	return opt

# Genre is a MULTI-select, so it gets check buttons rather than a dropdown: "Action
# or Deckbuilder" is a run someone wants, and a dropdown cannot say it. Nothing
# ticked means any, which is also what every genre ticked would mean — so the
# cleared state is the one that is drawn.
func _genre_row(key: String) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 2)
	for type_val in RunGraph.TYPE_ORDER:
		var b := CheckBox.new()
		b.text = RunGraph.type_label(int(type_val))
		b.add_theme_font_size_override("font_size", 11)
		b.add_theme_color_override("font_color", RunGraph.type_color(int(type_val)))
		b.toggled.connect(func(on):
			var genres: Array = (_specs[key] as Dictionary)["genres"]
			if on and not genres.has(int(type_val)):
				genres.append(int(type_val))
			elif not on:
				genres.erase(int(type_val))
			_refresh())
		row.add_child(b)
	return row

func _year_row(key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_year_field("from", func(v): _set_axis(key, "year_min", v)))
	var dash := Label.new()
	dash.text = "–"
	dash.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	row.add_child(dash)
	row.add_child(_year_field("to", func(v): _set_axis(key, "year_max", v)))
	return row

# A blank field is "unbounded", which is why this stores 0 rather than refusing
# empty input — a year filter you have half-filled is still a filter.
func _year_field(hint: String, on_change: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = hint
	e.custom_minimum_size.x = 62
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 12)
	e.text_changed.connect(func(txt):
		var digits: String = ""
		for c in txt:
			if c >= "0" and c <= "9":
				digits += c
		if digits != txt:
			e.text = digits
			e.caret_column = digits.length()
		on_change.call(int(digits) if digits != "" else 0)
		_refresh())
	return e

func _set_axis(key: String, field: String, value: int) -> void:
	(_specs[key] as Dictionary)[field] = value

# --- the run length --------------------------------------------------------

func _band_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = 300

	var head := Label.new()
	head.text = "HOW LONG A RUN"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(head)

	var note := Label.new()
	note.text = "Games from the start to the Amulet."
	note.tooltip_text = "The opening cards are drawn from inside this band — a start is offered when it is this far from the Amulet."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(note)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	row.add_child(_band_spin("Shortest", _min_path, func(v):
		_min_path = v
		if _max_path < _min_path:
			_max_path = _min_path))
	row.add_child(_band_spin("Longest", _max_path, func(v):
		_max_path = v
		if _min_path > _max_path:
			_min_path = _max_path))

	_band_label = Label.new()
	_band_label.add_theme_font_size_override("font_size", 12)
	_band_label.add_theme_color_override("font_color", UITheme.GOLD)
	box.add_child(_band_label)
	return box

func _band_spin(label_text: String, value: int, on_change: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	col.add_child(l)
	var spin := SpinBox.new()
	spin.min_value = RunConfig.PATH_FLOOR
	spin.max_value = RunConfig.PATH_CEILING
	spin.value = value
	spin.custom_minimum_size.x = 90
	spin.value_changed.connect(func(v):
		on_change.call(int(v))
		_refresh())
	col.add_child(spin)
	return col

# --- the named target ------------------------------------------------------

# The sharpest setting on the screen, and the one that needs the most care: 845
# games is not a dropdown. It is a search box over display names, showing the
# first few matches as buttons, with a Clear beside whatever is currently picked.
func _target_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head := Label.new()
	head.text = "AIM AT A GAME  (optional)"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	box.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	_target_search = LineEdit.new()
	_target_search.placeholder_text = "Search the catalog…"
	_target_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_search.add_theme_font_size_override("font_size", 12)
	_target_search.text_changed.connect(_on_target_search)
	row.add_child(_target_search)

	var clear := Button.new()
	clear.text = "Clear"
	clear.add_theme_font_size_override("font_size", 11)
	clear.pressed.connect(func():
		_amulet_id = &""
		_target_search.text = ""
		_on_target_search("")
		_refresh())
	row.add_child(clear)

	_target_label = Label.new()
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_target_label)

	_target_results = VBoxContainer.new()
	_target_results.add_theme_constant_override("separation", 2)
	box.add_child(_target_results)
	return box

const MAX_TARGET_RESULTS := 4

func _on_target_search(text: String) -> void:
	for c in _target_results.get_children():
		c.queue_free()
	var needle: String = text.strip_edges().to_lower()
	if needle.length() < 2:
		return
	var shown: int = 0
	for g in Data.all_games():
		if not (g is GameData) or not g.display_name.to_lower().contains(needle):
			continue
		# Only games the MAP filter keeps: a target the run's own graph excludes is
		# a target no route can reach, and offering it would be offering a run that
		# cannot be rolled.
		if not RunConfig.spec_passes(_specs["map"], g):
			continue
		var b := Button.new()
		b.text = "%s  (%d)" % [g.display_name, g.year] if g.year > 0 else g.display_name
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func():
			_amulet_id = g.id
			_target_search.text = ""
			_on_target_search("")
			_refresh())
		_target_results.add_child(b)
		shown += 1
		if shown >= MAX_TARGET_RESULTS:
			break

# --- the verdict -----------------------------------------------------------

func _refresh() -> void:
	for key in _counts.keys():
		var spec: Dictionary = _specs[key]
		var n: int = RunConfig.spec_count(spec)
		var label: Label = _counts[key]
		label.text = "%d game%s" % [n, "" if n == 1 else "s"]
		if not RunConfig.spec_is_clear(spec):
			label.text += "  ·  %s" % RunConfig.describe_spec(spec)
		label.add_theme_color_override("font_color",
			UITheme.DANGER if n == 0 else (UITheme.SUCCESS if n >= 20 else UITheme.GOLD))

	if _band_label != null:
		_band_label.text = ("%d games" % _min_path) if _min_path == _max_path \
			else "%d–%d games" % [_min_path, _max_path]

	if _target_label != null:
		if _amulet_id == &"":
			_target_label.text = "No target — the Amulet is rolled from the filter above."
			_target_label.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		else:
			var target: GameData = Data.get_game(_amulet_id)
			_target_label.text = "🏆  %s" % (target.display_name if target != null else String(_amulet_id))
			_target_label.add_theme_color_override("font_color", UITheme.GOLD)

	_update_verdict()

# What is actually wrong with this configuration, if anything — and Begin is
# disabled only for the things that genuinely cannot produce a run. A filter that
# leaves the map thin is a warning, not a refusal: a nine-game map is a strange
# run and it is a run.
func _update_verdict() -> void:
	var map_n: int = RunConfig.spec_count(_specs["map"])
	var problems: Array = []
	var warnings: Array = []
	if map_n == 0:
		problems.append("The map filter leaves no games at all.")
	elif map_n < 12:
		warnings.append("Only %d games on the map — routes will be short and repetitive." % map_n)

	# Start and amulet are chosen from INSIDE the map, so what matters is the
	# overlap, not each filter's own count.
	var start_in_map: int = 0
	var amulet_in_map: int = 0
	for g in Data.all_games():
		if not (g is GameData) or not RunConfig.spec_passes(_specs["map"], g):
			continue
		if RunConfig.spec_passes(_specs["start"], g):
			start_in_map += 1
		if RunConfig.spec_passes(_specs["amulet"], g):
			amulet_in_map += 1
	if map_n > 0 and start_in_map == 0:
		warnings.append("No game on the map passes the start filter — the opening cards will ignore it.")
	# The opening panel offers one card PER GENRE (RunGraph.NUM_START_OPTIONS over
	# TYPE_ORDER), so a map cut down to a single genre has only one card to give.
	# That is a real run and it is worth knowing before it opens on one card.
	var start_genres: Dictionary = {}
	for g in Data.all_games():
		if g is GameData and RunConfig.spec_passes(_specs["map"], g) \
				and RunConfig.spec_passes(_specs["start"], g):
			start_genres[int(g.type)] = true
	if map_n > 0 and start_in_map > 0 and start_genres.size() < RunGraph.NUM_START_OPTIONS:
		warnings.append("Only %d genre%s can start — the opening panel offers one card per genre, so you'll be given %d."
			% [start_genres.size(), "" if start_genres.size() == 1 else "s", start_genres.size()])
	if map_n > 0 and _amulet_id == &"" and amulet_in_map == 0:
		problems.append("No game on the map passes the Amulet filter.")
	if _amulet_id != &"" and not RunConfig.spec_passes(_specs["map"], Data.get_game(_amulet_id)):
		problems.append("The target game is not on the map its own filter describes.")

	if not problems.is_empty():
		_verdict.text = "⚠  %s" % " ".join(PackedStringArray(problems))
		_verdict.add_theme_color_override("font_color", UITheme.DANGER)
	elif not warnings.is_empty():
		_verdict.text = "•  %s" % " ".join(PackedStringArray(warnings))
		_verdict.add_theme_color_override("font_color", UITheme.GOLD)
	else:
		_verdict.text = "Ready — %d games on the map." % map_n
		_verdict.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	if _begin_btn != null:
		_begin_btn.disabled = not problems.is_empty()

# Public so a test can ask without reading the label.
func is_runnable() -> bool:
	_update_verdict()
	return _begin_btn == null or not _begin_btn.disabled

# --- the answer ------------------------------------------------------------

func _buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var reset := Button.new()
	reset.text = "↺  Reset"
	reset.tooltip_text = "Back to no filters at all."
	reset.pressed.connect(_reset)
	row.add_child(reset)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var back := Button.new()
	back.text = "Cancel"
	back.custom_minimum_size = Vector2(110, 42)
	back.pressed.connect(_cancel)
	row.add_child(back)

	_begin_btn = Button.new()
	_begin_btn.text = "▶  Begin the run"
	_begin_btn.custom_minimum_size = Vector2(240, 42)
	_begin_btn.add_theme_font_size_override("font_size", 16)
	_begin_btn.add_theme_stylebox_override("normal",
		UITheme.flat(UITheme.ACCENT.lerp(UITheme.BG, 0.55), 8, 8, 2, UITheme.ACCENT))
	_begin_btn.add_theme_color_override("font_color", UITheme.GOLD)
	_begin_btn.pressed.connect(_begin)
	row.add_child(_begin_btn)
	return row

# Rebuilt rather than walked: the controls hold their own state (a ticked
# CheckBox, a typed year) and putting all of it back by hand is a second place for
# the two to disagree.
func _reset() -> void:
	_min_path = RunGraph.MIN_PATH_LENGTH
	_max_path = RunGraph.MAX_PATH_LENGTH
	_amulet_id = &""
	_counts.clear()
	for c in get_children():
		c.queue_free()
	_build()

func _begin() -> void:
	begun.emit(config())
	_teardown()

func _cancel() -> void:
	cancelled.emit()
	_teardown()

func _teardown() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_cancel()

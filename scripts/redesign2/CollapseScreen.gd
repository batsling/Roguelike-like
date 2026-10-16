class_name CollapseScreen
extends Control

# FRACTURE 10's TURNAROUND (docs/fracture-design.md §7.2), the one screen the
# Collapse gets: the Amulet is in hand and the road behind fractures.
#
#   1. THE ROAD TURNS ROUND. The games walked are laid out from the Amulet on the
#      RIGHT to the start on the LEFT — the way the player now faces.
#   2. EVERY GAME PLAYED FRACTURES, one after another from the Amulet back: the
#      rift's swirl (UITheme.rift_backdrop, the same one rift cards wear) washes
#      over its cover and leaves the game it became. The start does not.
#   3. THE WAY HOME is drawn underneath: the optimal path from here to the start,
#      over the games it now holds.
#
# It changes nothing itself: GameLoop2.begin_collapse already did the work, and
# this is handed what it did. Leaving it carries on down the report's chain.

signal finished

const COVER := Vector2(78, 104)
const STEP := 0.45              # seconds between one game fracturing and the next
const FADE := 0.6               # how long a cover takes to become the new one

var _layer: CanvasLayer = null
var _changes: Array = []        # [{node, from, to}] from GameLoop2.begin_collapse
var _road: Array = []           # Array[StringName], the nodes walked, start first
var _home: Array = []           # Array[StringName], the way home, start first
var _faces: Dictionary = {}     # node -> {"old": TextureRect, "new": TextureRect, "swirl": ColorRect}
var _tween: Tween = null

static func open(host: Node, changes: Array, road: Array, home: Array) -> CollapseScreen:
	var screen := CollapseScreen.new()
	screen._changes = changes
	screen._road = road
	screen._home = home
	screen._layer = CanvasLayer.new()
	screen._layer.layer = UITheme.Layer.VERDICT
	screen._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(screen._layer)
	screen._layer.add_child(screen)
	return screen

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	theme = UITheme.shared()
	_build()
	_play()

func changed_count() -> int:
	return _changes.size()

func _build() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(UITheme.BG_DEEP, 0.9)
	add_child(scrim)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 40
	frame.offset_right = -40
	frame.offset_top = 30
	frame.offset_bottom = -30
	frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 12, 18, 2, Fracture.COLOR))
	add_child(frame)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	frame.add_child(col)

	var title := Label.new()
	title.text = "%s  THE AMULET IS YOURS — NOW GET OUT" % Fracture.GLYPH
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
	title.add_theme_color_override("font_color", Fracture.COLOR)
	col.add_child(title)

	var start: GameData = Data.get_game(_road[0]) if not _road.is_empty() else null
	var sub := Label.new()
	sub.text = ("Every game you played has fractured into one you have not. Carry the "
		+ "Amulet back to %s: arriving there wins the run.") % (
			start.display_name if start != null else "the game you started on")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	sub.add_theme_color_override("font_color", UITheme.TEXT)
	col.add_child(sub)

	col.add_child(_heading("The road you walked, turned round"))
	col.add_child(_strip(_road, true))
	col.add_child(_heading("The way home: %d game%s" % [maxi(0, _home.size() - 1),
		"" if _home.size() == 2 else "s"]))
	col.add_child(_strip(_home, false))

	var go := Button.new()
	go.name = "HeadHome"
	go.text = "Head home"
	go.custom_minimum_size = Vector2(220, 44)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.add_theme_stylebox_override("normal", UITheme.accent_box(Fracture.COLOR, UITheme.PANEL_HI, 8))
	go.add_theme_color_override("font_color", Fracture.COLOR)
	go.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	go.pressed.connect(close)
	col.add_child(go)

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", UITheme.ACCENT)
	return l

# A row of covers, the start on the LEFT. `fracturing` builds the walked road,
# where each changed node gets the old cover, the new one under it and the swirl
# behind both; the way home just shows what is standing there now.
func _strip(nodes: Array, fracturing: bool) -> Control:
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, COVER.y + 32)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	scroll.add_child(row)
	var was: Dictionary = {}
	for c in _changes:
		was[StringName(c["node"])] = c
	for i in range(nodes.size()):
		var node: StringName = StringName(nodes[i])
		var change: Dictionary = was.get(node, {})
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", UITheme.GAP_HAIR)
		var art := Control.new()
		art.custom_minimum_size = COVER
		cell.add_child(art)
		var now: GameData = GameLoop2.game_at(node)
		var name_lbl := Label.new()
		name_lbl.custom_minimum_size.x = COVER.x
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		name_lbl.add_theme_color_override("font_color",
			UITheme.GOLD if i == 0 else UITheme.TEXT_DIM)
		cell.add_child(name_lbl)
		if fracturing and not change.is_empty():
			var swirl: ColorRect = UITheme.rift_backdrop(float(i) * 1.7)
			swirl.modulate.a = 0.0
			art.add_child(swirl)
			var new_face: TextureRect = _cover(Data.get_game(StringName(change["to"])))
			new_face.modulate.a = 0.0
			art.add_child(new_face)
			var old_face: TextureRect = _cover(Data.get_game(StringName(change["from"])))
			art.add_child(old_face)
			_faces[node] = {"old": old_face, "new": new_face, "swirl": swirl,
				"label": name_lbl, "to": Data.get_game(StringName(change["to"]))}
			var from: GameData = Data.get_game(StringName(change["from"]))
			name_lbl.text = from.display_name if from != null else String(node)
		else:
			art.add_child(_cover(now))
			name_lbl.text = ("🏠 " if i == 0 else "") + (now.display_name if now != null else String(node))
		row.add_child(cell)
	return scroll

func _cover(game: GameData) -> TextureRect:
	var tr := TextureRect.new()
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if game != null:
		tr.texture = game.cover_image
		tr.tooltip_text = game.display_name
	return tr

# The fracture, played from the Amulet backwards — the road the player is about
# to walk, in the order they will meet it.
func _play() -> void:
	var order: Array = _road.duplicate()
	order.reverse()
	_tween = create_tween()
	_tween.set_parallel(false)
	for node in order:
		var face: Dictionary = _faces.get(StringName(node), {})
		if face.is_empty():
			continue
		_tween.tween_interval(STEP)
		_tween.tween_property(face["swirl"], "modulate:a", 1.0, FADE * 0.5)
		_tween.parallel().tween_property(face["old"], "modulate:a", 0.0, FADE)
		_tween.parallel().tween_property(face["new"], "modulate:a", 1.0, FADE)
		var to: GameData = face["to"]
		var label: Label = face["label"]
		_tween.tween_callback(func():
			label.text = to.display_name if to != null else label.text
			label.add_theme_color_override("font_color", Fracture.COLOR))

# Skip to the end, for a player who does not want to wait and for the tests.
func finish_animation() -> void:
	if _tween != null and _tween.is_valid():
		_tween.custom_step(1000.0)

func close() -> void:
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

class_name MapNodeView
extends Control

# Visual for a single DeckbuilderMap node. Draws itself as a coloured
# circle with a glyph centered inside. Reachable nodes pulse a yellow
# outline and accept clicks; visited and out-of-range nodes are dim
# and inert.

const NODE_RADIUS := 30.0

signal clicked(node_data: Dictionary)

var node_data: Dictionary = {}
var reachable: bool = false
var is_current: bool = false

var _glyph_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(NODE_RADIUS * 2.0, NODE_RADIUS * 2.0)
	size = custom_minimum_size
	_glyph_label = Label.new()
	_glyph_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph_label.add_theme_font_size_override("font_size", 26)
	_glyph_label.add_theme_color_override("font_color", Color.WHITE)
	_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph_label)
	_refresh_label()
	queue_redraw()

func setup(node: Dictionary) -> void:
	node_data = node
	if is_inside_tree():
		_refresh_label()
		queue_redraw()

func set_reachable(r: bool) -> void:
	reachable = r
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND if r else Control.CURSOR_ARROW
	)
	queue_redraw()

func set_current(c: bool) -> void:
	is_current = c
	queue_redraw()

func _refresh_label() -> void:
	if _glyph_label == null:
		return
	_glyph_label.text = DeckbuilderMap.type_glyph(int(node_data.get("type", 0)))

func _draw() -> void:
	var center: Vector2 = size / 2.0

	var visited: bool = bool(node_data.get("visited", false))
	var fill: Color = _type_color(int(node_data.get("type", 0)))
	if visited:
		fill = fill.darkened(0.55)
		fill.a = 0.65
	draw_circle(center, NODE_RADIUS - 3.0, fill)

	# Outer ring tints the node based on its role on the map.
	var ring: Color = Color(0.35, 0.35, 0.4, 0.85)
	if is_current:
		ring = Color(0.55, 1.0, 0.65)
	elif reachable:
		ring = Color(1.0, 0.92, 0.35)
	elif visited:
		ring = Color(0.55, 0.55, 0.6, 0.6)
	draw_arc(center, NODE_RADIUS, 0.0, TAU, 36, ring, 3.0, true)

func _gui_input(event: InputEvent) -> void:
	if not reachable:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("clicked", node_data)

func _type_color(t: int) -> Color:
	# Loose colour mapping per node type so the map reads at a glance.
	match t:
		DeckbuilderMap.NodeType.COMBAT: return Color(0.75, 0.30, 0.30)
		DeckbuilderMap.NodeType.EVENT: return Color(0.55, 0.40, 0.85)
		DeckbuilderMap.NodeType.REST: return Color(0.40, 0.70, 0.50)
		DeckbuilderMap.NodeType.MERCHANT: return Color(0.85, 0.70, 0.30)
		DeckbuilderMap.NodeType.TREASURE: return Color(0.95, 0.85, 0.30)
		DeckbuilderMap.NodeType.ELITE: return Color(0.95, 0.30, 0.25)
		_: return Color(0.5, 0.5, 0.5)

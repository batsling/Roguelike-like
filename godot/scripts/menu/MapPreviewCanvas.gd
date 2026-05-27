class_name MapPreviewCanvas
extends Control

# Custom-drawn DAG canvas used by MapPreviewModal. Stays a separate
# Control so we can override `_draw()` directly — Godot's `draw` signal
# fires *after* the frame closes, so it can't be used to issue draw
# commands.

var start_id: StringName = &""
var amulet_id: StringName = &""

var _layers: Array = []
var _edges: Array = []
var _positions: Dictionary = {}

func setup(s_id: StringName, a_id: StringName) -> void:
	start_id = s_id
	amulet_id = a_id
	_recompute()
	queue_redraw()

func _ready() -> void:
	resized.connect(func():
		_recompute()
		queue_redraw()
	)
	_recompute()
	queue_redraw()

func _recompute() -> void:
	if start_id == &"" or amulet_id == &"":
		_layers = []
		_edges = []
		_positions = {}
		return
	var dag := RunGraph.shortest_path_dag(start_id, amulet_id)
	_layers = dag.get("layers", [])
	_edges = dag.get("edges", [])
	_positions.clear()
	if _layers.is_empty():
		return
	var canvas_size: Vector2 = size
	if canvas_size.x <= 0 or canvas_size.y <= 0:
		canvas_size = Vector2(720, 460)
	# Pad inward so labels don't clip.
	var pad_x := 60.0
	var pad_y := 40.0
	var usable_w: float = maxf(50.0, canvas_size.x - pad_x * 2)
	var usable_h: float = maxf(50.0, canvas_size.y - pad_y * 2)

	var n_layers: int = _layers.size()
	var x_step: float = usable_w / float(maxi(1, n_layers - 1)) if n_layers > 1 else 0.0
	for li in range(n_layers):
		var layer: Array = _layers[li]
		var n: int = layer.size()
		var x: float = pad_x + (x_step * li if n_layers > 1 else usable_w * 0.5)
		for ni in range(n):
			var y: float = pad_y + usable_h * (float(ni + 1) / float(n + 1))
			_positions[layer[ni]] = Vector2(x, y)

func _draw() -> void:
	if _layers.is_empty():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(20, 30), "No path between selected games.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
		return
	for e in _edges:
		var a = _positions.get(e["from"], Vector2.ZERO)
		var b = _positions.get(e["to"], Vector2.ZERO)
		draw_line(a, b, Color(0.5, 0.5, 0.55, 0.85), 2.0, true)
	for gid in _positions:
		var pos: Vector2 = _positions[gid]
		var is_start: bool = gid == start_id
		var is_amulet: bool = gid == amulet_id
		var color: Color = Color(0.32, 0.58, 0.86)
		if is_amulet:
			color = Color(1.0, 0.84, 0.2)
		elif not is_start:
			color = Color(0.4, 0.4, 0.45)
		var radius: float = 16.0 if (is_start or is_amulet) else 12.0
		draw_circle(pos, radius, color)
		draw_arc(pos, radius, 0, TAU, 32, Color(0, 0, 0, 0.6), 1.5, true)
		var g: GameData = Data.get_game(gid)
		if g != null:
			var font: Font = ThemeDB.fallback_font
			var font_size := 11
			var text: String = g.display_name
			var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
			var label_color: Color = Color(0.92, 0.92, 0.92)
			if is_amulet:
				label_color = Color(1, 0.85, 0.4)
			elif is_start:
				label_color = Color(0.6, 0.85, 1.0)
			draw_string(font, pos + Vector2(-w * 0.5, radius + 14), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)

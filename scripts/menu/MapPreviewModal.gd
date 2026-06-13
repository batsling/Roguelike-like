extends Control

# Wrapper around a shared MapGraphView. Shows the shortest-path route from a
# start game to the amulet — the exact map that would be generated in-run from
# that start — with zoom. Closes when the player clicks "← Back".

signal closed

@onready var _title: Label = %Title
@onready var _close_btn: Button = %CloseBtn
@onready var _scroll: ScrollContainer = %Scroll
@onready var _graph: MapGraphView = %Graph
@onready var _zoom_label: Label = %ZoomLabel
@onready var _zoom_out: Button = %ZoomOut
@onready var _zoom_in: Button = %ZoomIn
@onready var _zoom_reset_btn: Button = %ZoomReset

var _start_id: StringName = &""
var _amulet_id: StringName = &""

func setup(start_id: StringName, amulet_id: StringName) -> void:
	_start_id = start_id
	_amulet_id = amulet_id

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.pressed.connect(_on_close)
	_zoom_out.pressed.connect(func(): _zoom_by(0.8))
	_zoom_in.pressed.connect(func(): _zoom_by(1.25))
	_zoom_reset_btn.pressed.connect(_zoom_reset)

	var start_g := Data.get_game(_start_id)
	var amulet_g := Data.get_game(_amulet_id)
	if start_g != null and amulet_g != null:
		_title.text = "%s → %s" % [start_g.display_name, amulet_g.display_name]

	# In the preview the start IS the player position; label it START.
	_graph.build(_start_id, _amulet_id, _start_id, "START")
	# Auto-fit to the panel on open (only ever zoom out), like the HTML preview.
	var base := _graph.get_base_size()
	var avail := Vector2(800, 500)
	if base.x > 0.0 and base.y > 0.0:
		var fit: float = minf((avail.x) / base.x, (avail.y) / base.y)
		_graph.set_zoom(clampf(fit, MapGraphView.ZOOM_MIN, 1.0))
	_update_zoom_label()

# Zoom toward a focus point (cursor for the wheel, viewport centre for the
# buttons) so the map grows around what you're looking at. Scroll offset is
# restored deferred since the ScrollContainer recomputes its range next layout.
func _zoom_by(factor: float, focus_global: Vector2 = Vector2(-1, -1)) -> void:
	if _graph == null or _scroll == null:
		return
	var old: float = _graph.get_zoom()
	var target: float = clampf(old * factor, MapGraphView.ZOOM_MIN, MapGraphView.ZOOM_MAX)
	if is_equal_approx(target, old):
		return
	var focus_local: Vector2
	if focus_global.x < 0.0:
		focus_local = _scroll.size * 0.5
	else:
		focus_local = focus_global - _scroll.global_position
		focus_local.x = clampf(focus_local.x, 0.0, _scroll.size.x)
		focus_local.y = clampf(focus_local.y, 0.0, _scroll.size.y)
	var content_pt := Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical) + focus_local
	var base_pt := content_pt / old
	_graph.set_zoom(target)
	_update_zoom_label()
	var new_scroll := base_pt * target - focus_local
	_scroll.set_deferred("scroll_horizontal", int(round(new_scroll.x)))
	_scroll.set_deferred("scroll_vertical", int(round(new_scroll.y)))

func _zoom_reset() -> void:
	_graph.set_zoom(1.0)
	_update_zoom_label()

func _update_zoom_label() -> void:
	_zoom_label.text = "%d%%" % int(round(_graph.get_zoom() * 100.0))

func _on_close() -> void:
	emit_signal("closed")

extends Control

# Wrapper around MapPreviewCanvas. Shows the shortest-path DAG between
# a start game and the amulet game as a static graph. Closes when the
# player clicks "← Back".

signal closed

@onready var _title: Label = %Title
@onready var _close_btn: Button = %CloseBtn
@onready var _canvas: MapPreviewCanvas = %Canvas

var _start_id: StringName = &""
var _amulet_id: StringName = &""

func setup(start_id: StringName, amulet_id: StringName) -> void:
	_start_id = start_id
	_amulet_id = amulet_id

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.pressed.connect(_on_close)
	var start_g := Data.get_game(_start_id)
	var amulet_g := Data.get_game(_amulet_id)
	if start_g != null and amulet_g != null:
		_title.text = "%s → %s" % [start_g.display_name, amulet_g.display_name]
	_canvas.setup(_start_id, _amulet_id)

func _on_close() -> void:
	emit_signal("closed")

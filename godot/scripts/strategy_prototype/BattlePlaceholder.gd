extends CanvasLayer

# Phase 2 stub: placeholder battle overlay. Lets the overworld <-> combat <->
# overworld loop be exercised before the real tactical engine exists.

var _title: Label
var _info: Label
var _btn_win: Button
var _btn_lose: Button

func _ready() -> void:
	layer = 10

	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.02, 0.08, 0.92)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	_title = Label.new()
	_title.text = "[ BATTLE ]"
	_title.position = Vector2(560, 120)
	_title.size = Vector2(200, 40)
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	panel.add_child(_title)

	_info = Label.new()
	_info.position = Vector2(360, 200)
	_info.size = Vector2(560, 240)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(_info)

	_btn_win = Button.new()
	_btn_win.text = "Win combat"
	_btn_win.position = Vector2(440, 480)
	_btn_win.size = Vector2(160, 44)
	_btn_win.pressed.connect(_on_win)
	panel.add_child(_btn_win)

	_btn_lose = Button.new()
	_btn_lose.text = "Lose combat"
	_btn_lose.position = Vector2(680, 480)
	_btn_lose.size = Vector2(160, 44)
	_btn_lose.pressed.connect(_on_lose)
	panel.add_child(_btn_lose)

func set_encounter(room_data, encounter: Array) -> void:
	var rect_str = "(%d,%d %dx%d)" % [room_data.rect.position.x, room_data.rect.position.y, room_data.rect.size.x, room_data.rect.size.y]
	var enc_str = "(empty)"
	if not encounter.is_empty():
		enc_str = ""
		for i in range(encounter.size()):
			if i > 0: enc_str += ", "
			enc_str += str(encounter[i])
	_info.text = "Placeholder tactical battle.\n\nRoom: %s\nEncounter: %s\n\n(Phase 2 stub — the real tactical engine is built in Phases 3-6.)" % [
		rect_str, enc_str
	]

func _on_win() -> void:
	StrategyCombatSession.resolve_combat("victory")

func _on_lose() -> void:
	StrategyCombatSession.resolve_combat("defeat")

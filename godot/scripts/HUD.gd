class_name HUD
extends CanvasLayer

const LOG_LINES = 5
const FONT_SIZE = 14

var _font: Font
var _status_label: Label
var _log_label: RichTextLabel
var _inventory_panel: Panel
var _inventory_label: Label

func _ready() -> void:
	_font = ThemeDB.fallback_font

	# Status bar at top
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.position = Vector2(4, 2)
	_status_label.size = Vector2(1272, 22)
	_status_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_status_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_status_label)

	# Message log at bottom
	_log_label = RichTextLabel.new()
	_log_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_log_label.position = Vector2(4, 620)
	_log_label.size = Vector2(1272, 96)
	_log_label.bbcode_enabled = true
	_log_label.scroll_active = false
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	add_child(_log_label)

	# Inventory panel (hidden by default)
	_inventory_panel = Panel.new()
	_inventory_panel.position = Vector2(300, 150)
	_inventory_panel.size = Vector2(400, 300)
	_inventory_panel.visible = false
	add_child(_inventory_panel)

	_inventory_label = Label.new()
	_inventory_label.position = Vector2(10, 10)
	_inventory_label.size = Vector2(380, 280)
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_inventory_panel.add_child(_inventory_label)

	MessageLog.connect("message_added", _on_message_added)

func _on_message_added(_text: String, _color: Color) -> void:
	_refresh_log()

func _refresh_log() -> void:
	var recent = MessageLog.get_recent(LOG_LINES)
	var lines = ""
	for i in range(recent.size()):
		var m = recent[i]
		var hex = m.color.to_html(false)
		var alpha = 1.0 - (recent.size() - 1 - i) * 0.18
		alpha = clamp(alpha, 0.35, 1.0)
		var a_hex = "%02x" % int(alpha * 255)
		lines += "[color=#%s%s]%s[/color]\n" % [hex, a_hex, m.text]
	_log_label.text = lines

func update_status(player: Entity, floor_num: int) -> void:
	if player == null:
		return
	var hp_bar = _make_bar(player.hp, player.max_hp, 20)
	_status_label.text = "HP: %s %d/%d   ATK: %d   DEF: %d   Floor: %d" % [
		hp_bar, player.hp, player.max_hp,
		player.attack, player.defense, floor_num
	]

func _make_bar(current: int, maximum: int, width: int) -> String:
	var filled = int(float(current) / maximum * width)
	filled = clamp(filled, 0, width)
	return "[" + "|".repeat(filled) + ".".repeat(width - filled) + "]"

func show_inventory(player: Entity) -> void:
	_inventory_panel.visible = true
	if player.inventory.is_empty():
		_inventory_label.text = "--- Inventory ---\n(empty)\n\nPress [i] to close"
		return
	var text = "--- Inventory (press letter to use, [i] to close) ---\n"
	for i in range(player.inventory.size()):
		var letter = char(ord('a') + i)
		text += "[%s] %s\n" % [letter, player.inventory[i].item_name]
	_inventory_label.text = text

func hide_inventory() -> void:
	_inventory_panel.visible = false

func is_inventory_open() -> bool:
	return _inventory_panel.visible

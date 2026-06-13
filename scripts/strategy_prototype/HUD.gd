class_name StrategyHUD
extends CanvasLayer

const LOG_LINES = 5
const FONT_SIZE = 14

var _font: Font
var _status_label: Label
var _log_label: RichTextLabel
var _inventory_panel: Panel
var _inventory_label: Label

# Mouse hover tooltip + click context menu (driven by Main).
var _tooltip: Panel
var _tooltip_label: Label
var _context_menu: Panel
var _context_vbox: VBoxContainer
var _context_catcher: Control
var _context_cb: Callable = Callable()

func _ready() -> void:
	_font = ThemeDB.fallback_font

	# Status bar at top
	_status_label = Label.new()
	_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_label.position = Vector2(4, 2)
	_status_label.size = Vector2(1272, 22)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	add_child(_log_label)

	_build_tooltip()
	_build_context_menu()

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

	StrategyLog.connect("message_added", _on_message_added)

func _on_message_added(_text: String, _color: Color) -> void:
	_refresh_log()

func _refresh_log() -> void:
	var recent = StrategyLog.get_recent(LOG_LINES)
	var lines = ""
	for i in range(recent.size()):
		var m = recent[i]
		var hex = m.color.to_html(false)
		var alpha = 1.0 - (recent.size() - 1 - i) * 0.18
		alpha = clamp(alpha, 0.35, 1.0)
		var a_hex = "%02x" % int(alpha * 255)
		lines += "[color=#%s%s]%s[/color]\n" % [hex, a_hex, m.text]
	_log_label.text = lines

func update_status(player: StrategyEntity, floor_num: int) -> void:
	if player == null:
		return
	var hp_bar = _make_bar(player.hp, player.max_hp, 20)
	_status_label.text = "HP: %s %d/%d   ATK: %d   DEF: %d   Gold: %d   Floor: %d" % [
		hp_bar, player.hp, player.max_hp,
		player.attack, player.defense,
		GameState.gold,
		floor_num
	]

func _make_bar(current: int, maximum: int, width: int) -> String:
	var filled = int(float(current) / maximum * width)
	filled = clamp(filled, 0, width)
	return "[" + "|".repeat(filled) + ".".repeat(width - filled) + "]"

func show_inventory(player: StrategyEntity) -> void:
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

# ------------------------------------------------------------------
# Hover tooltip
# ------------------------------------------------------------------

func _build_tooltip() -> void:
	_tooltip = Panel.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.1, 0.96)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.8, 0.7, 0.4, 0.9)
	_tooltip.add_theme_stylebox_override("panel", sb)
	add_child(_tooltip)

	_tooltip_label = Label.new()
	_tooltip_label.position = Vector2(8, 5)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.98))
	_tooltip.add_child(_tooltip_label)

func show_tooltip(text: String, at: Vector2) -> void:
	if text == "":
		hide_tooltip()
		return
	_tooltip_label.text = text
	var sz: Vector2 = _font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	_tooltip.size = Vector2(sz.x + 16, sz.y + 10)
	var vp := get_viewport().get_visible_rect().size
	var p := at + Vector2(14, 6)
	p.x = clampf(p.x, 4, vp.x - _tooltip.size.x - 4)
	p.y = clampf(p.y, 4, vp.y - _tooltip.size.y - 4)
	_tooltip.position = p
	_tooltip.visible = true

func hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false

# ------------------------------------------------------------------
# Click context menu
# ------------------------------------------------------------------

func _build_context_menu() -> void:
	# Full-screen catcher: a click anywhere off the menu dismisses it.
	_context_catcher = Control.new()
	_context_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_context_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_context_catcher.visible = false
	_context_catcher.gui_input.connect(_on_catcher_input)
	add_child(_context_catcher)

	_context_menu = Panel.new()
	_context_menu.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.14, 0.99)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.8, 0.7, 0.4, 0.95)
	_context_menu.add_theme_stylebox_override("panel", sb)
	add_child(_context_menu)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	_context_menu.add_child(margin)

	_context_vbox = VBoxContainer.new()
	_context_vbox.add_theme_constant_override("separation", 4)
	margin.add_child(_context_vbox)

func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_context_menu()

# options: Array of { "text": String, "id": String }. `cb` is called with the
# chosen id string.
func show_context_menu(options: Array, at: Vector2, cb: Callable) -> void:
	for c in _context_vbox.get_children():
		c.queue_free()
	_context_cb = cb
	var max_w := 140.0
	for opt in options:
		var b := Button.new()
		b.text = str(opt.get("text", "?"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		var id := str(opt.get("id", ""))
		b.pressed.connect(_on_context_pick.bind(id))
		_context_vbox.add_child(b)
		var w: float = _font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 28
		max_w = maxf(max_w, w)
	var h := float(options.size()) * 34.0 + 12.0
	_context_menu.size = Vector2(max_w + 12, h)
	var vp := get_viewport().get_visible_rect().size
	var p := at
	p.x = clampf(p.x, 4, vp.x - _context_menu.size.x - 4)
	p.y = clampf(p.y, 4, vp.y - _context_menu.size.y - 4)
	_context_menu.position = p
	_context_catcher.visible = true
	_context_menu.visible = true

func _on_context_pick(id: String) -> void:
	var cb := _context_cb
	hide_context_menu()
	if cb.is_valid():
		cb.call(id)

func hide_context_menu() -> void:
	if _context_menu != null:
		_context_menu.visible = false
	if _context_catcher != null:
		_context_catcher.visible = false

func is_context_menu_open() -> bool:
	return _context_menu != null and _context_menu.visible

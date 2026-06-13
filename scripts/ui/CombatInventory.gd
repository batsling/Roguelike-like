class_name CombatInventory
extends PanelContainer

# Compact, on-screen inventory used by the three combat modes (deckbuilder,
# action, strategy) and anywhere else a quick item rack is handy. Renders every
# owned item as a small icon tile in a grid; charged actives draw an Isaac-style
# charge bar and can be clicked to fire when full (charged items may be used on
# any screen). Passive items are shown for reference. Refreshes itself on
# GameState.inventory_changed / stats_changed.
#
# Configure before adding to the tree (or via the exported fields):
#   var inv := CombatInventory.new()
#   inv.columns = 6
#   inv.tile_px = 40
#   inv.panel_opacity = 0.85
#   inv.title_text = "Items"

@export var columns: int = 6
@export var tile_px: int = 44
@export var panel_opacity: float = 1.0
@export var show_title: bool = true
@export var title_text: String = "Items"

var _grid: GridContainer
var _title_label: Label
var _empty_label: Label

func _ready() -> void:
	self_modulate.a = panel_opacity
	_build()
	if not GameState.inventory_changed.is_connected(_refresh):
		GameState.inventory_changed.connect(_refresh)
	if not GameState.stats_changed.is_connected(_refresh):
		GameState.stats_changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if GameState.inventory_changed.is_connected(_refresh):
		GameState.inventory_changed.disconnect(_refresh)
	if GameState.stats_changed.is_connected(_refresh):
		GameState.stats_changed.disconnect(_refresh)

func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.05, 0.92)
	style.border_color = Color(0.5, 0.42, 0.28, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.add_theme_font_size_override("font_size", 12)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.83, 0.45))
	_title_label.visible = show_title
	vbox.add_child(_title_label)

	_grid = GridContainer.new()
	_grid.columns = maxi(1, columns)
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "(empty)"
	_empty_label.add_theme_font_size_override("font_size", 11)
	_empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_empty_label)

func _refresh(_a = null, _b = null) -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	var items: Array = []
	for it in GameState.inventory:
		if it is ItemData:
			items.append(it)
	_empty_label.visible = items.is_empty()
	for it in items:
		_grid.add_child(_build_tile(it))

func _build_tile(item: ItemData) -> Control:
	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(tile_px, tile_px)
	var ready_to_fire: bool = GameState.can_fire_item(item)

	# A charged active that is ready glows green; everything else gets a neutral
	# frame so the rack reads as a grid of slots.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.11, 0.1, 0.95)
	box.set_corner_radius_all(3)
	box.set_border_width_all(2)
	box.border_color = Color(0.4, 0.95, 0.5, 0.95) if ready_to_fire \
		else Color(0.32, 0.3, 0.28, 0.9)
	tile.add_theme_stylebox_override("panel", box)

	if item.image != null:
		var icon := TextureRect.new()
		icon.texture = item.image
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 3
		icon.offset_top = 3
		icon.offset_right = -3
		icon.offset_bottom = -3
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Dim a charged active while it is still recharging.
		if item.is_charged() and not item.is_fully_charged():
			icon.modulate = Color(0.55, 0.55, 0.6)
		tile.add_child(icon)

	if item.is_charged():
		var bar := ChargeBar.new()
		bar.position = Vector2(2, 3)
		bar.size = Vector2(4, float(tile_px) - 6.0)
		bar.setup(item.max_charge(), item.current_charge)
		tile.add_child(bar)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = _tooltip(item)
	btn.pressed.connect(_on_tile_pressed.bind(item))
	tile.add_child(btn)
	return tile

func _tooltip(item: ItemData) -> String:
	var lines: Array = [item.display_name]
	if item.description != "":
		lines.append(item.description)
	if item.is_charged():
		if item.is_fully_charged():
			lines.append("Charged (%d/%d) — click to use." % [item.current_charge, item.max_charge()])
		else:
			lines.append("Charging %d/%d." % [item.current_charge, item.max_charge()])
	elif item.kind == ItemData.ItemKind.USABLE:
		lines.append("Click to use.")
	return "\n".join(PackedStringArray(lines))

func _on_tile_pressed(item: ItemData) -> void:
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.85, 0.9, 1.0))
		return
	if item.is_charged() and not item.is_fully_charged():
		Notifications.notify("%s is charging (%d/%d)." % [
			item.display_name, item.current_charge, item.max_charge()],
			Color(0.9, 0.8, 0.5))
	elif item.kind == ItemData.ItemKind.USABLE and not GameState.can_use_items():
		Notifications.notify("%s can only be used in combat or an event." % item.display_name,
			Color(0.9, 0.8, 0.5))

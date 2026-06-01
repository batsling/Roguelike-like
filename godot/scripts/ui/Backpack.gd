class_name Backpack
extends Control

# Global backpack popup. Mounted once on a high CanvasLayer by Main and
# toggled with Tab from anywhere in a run. Two tabs:
#   Items — every ItemData in GameState.inventory. USABLE consumables (pills)
#           get a Use button, enabled only when GameState.can_use_items()
#           (i.e. in combat or while an event roll is open). Sortable by
#           pickup order, rarity, or name.
#   Loot  — the run-scope loot counters (potions / scrolls / keys / fish …).
#
# Built entirely in code so it has no scene-file node dependencies. Runs with
# PROCESS_MODE_ALWAYS and pauses the tree while open so real-time action
# combat freezes behind it.

enum Tab { ITEMS, LOOT }
enum SortMode { PICKUP, RARITY, NAME }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [
	Color(0.78, 0.78, 0.78), Color(0.45, 0.85, 0.5),
	Color(0.4, 0.6, 1.0), Color(0.75, 0.45, 1.0), Color(1.0, 0.8, 0.3),
]
# Friendly labels for known loot kinds; unknown kinds fall back to capitalize.
const LOOT_LABELS := {
	"potion": "Potions", "scroll": "Scrolls", "key": "Keys", "fish": "Fish",
}

var _tab: Tab = Tab.ITEMS
var _sort: SortMode = SortMode.PICKUP

var _panel: PanelContainer
var _tab_items_btn: Button
var _tab_loot_btn: Button
var _sort_bar: HBoxContainer
var _list_vbox: VBoxContainer
var _hint_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()
	GameState.inventory_changed.connect(_on_state_changed)
	GameState.stats_changed.connect(_on_state_changed)

func _on_state_changed() -> void:
	if visible:
		_refresh()

# ------------------------------------------------------------------
# Open / close
# ------------------------------------------------------------------

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	get_tree().paused = true
	_refresh()

func close() -> void:
	visible = false
	get_tree().paused = false

# ------------------------------------------------------------------
# UI construction
# ------------------------------------------------------------------

func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.size = Vector2(760, 580)
	_panel.position = (get_viewport_rect().size - _panel.size) / 2.0
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	# Header row: title + close button.
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Backpack"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close (Tab)"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Tab buttons.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root.add_child(tabs)
	_tab_items_btn = Button.new()
	_tab_items_btn.text = "Items"
	_tab_items_btn.toggle_mode = true
	_tab_items_btn.pressed.connect(func(): _set_tab(Tab.ITEMS))
	tabs.add_child(_tab_items_btn)
	_tab_loot_btn = Button.new()
	_tab_loot_btn.text = "Loot"
	_tab_loot_btn.toggle_mode = true
	_tab_loot_btn.pressed.connect(func(): _set_tab(Tab.LOOT))
	tabs.add_child(_tab_loot_btn)

	# Sort bar (Items tab only).
	_sort_bar = HBoxContainer.new()
	_sort_bar.add_theme_constant_override("separation", 6)
	root.add_child(_sort_bar)
	var sort_lbl := Label.new()
	sort_lbl.text = "Sort:"
	_sort_bar.add_child(sort_lbl)
	_add_sort_button("Pickup", SortMode.PICKUP)
	_add_sort_button("Rarity", SortMode.RARITY)
	_add_sort_button("Name", SortMode.NAME)

	# Scrollable list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(720, 440)
	root.add_child(scroll)
	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 6)
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vbox)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	root.add_child(_hint_label)

func _add_sort_button(text: String, mode: SortMode) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): _set_sort(mode))
	b.set_meta("sort_mode", int(mode))
	_sort_bar.add_child(b)

func _set_tab(t: Tab) -> void:
	_tab = t
	_refresh()

func _set_sort(mode: SortMode) -> void:
	_sort = mode
	_refresh()

# ------------------------------------------------------------------
# Render
# ------------------------------------------------------------------

func _refresh() -> void:
	_tab_items_btn.button_pressed = _tab == Tab.ITEMS
	_tab_loot_btn.button_pressed = _tab == Tab.LOOT
	_sort_bar.visible = _tab == Tab.ITEMS
	for b in _sort_bar.get_children():
		if b is Button and b.has_meta("sort_mode"):
			b.modulate = Color(1, 1, 0.6) if int(b.get_meta("sort_mode")) == int(_sort) else Color.WHITE
	for child in _list_vbox.get_children():
		child.queue_free()
	if _tab == Tab.ITEMS:
		_render_items()
	else:
		_render_loot()

func _render_items() -> void:
	var items: Array = _sorted_items()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Your backpack is empty."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_vbox.add_child(empty)
	else:
		for it in items:
			_list_vbox.add_child(_build_item_row(it))
	var can_use: bool = GameState.can_use_items()
	_hint_label.text = "Click Use to consume a pill." if can_use \
		else "Pills can only be used in combat or during an event."

func _sorted_items() -> Array:
	var items: Array = GameState.inventory.duplicate()
	match _sort:
		SortMode.PICKUP:
			items.sort_custom(_cmp_pickup)
		SortMode.NAME:
			items.sort_custom(_cmp_name)
		SortMode.RARITY:
			items.sort_custom(_cmp_rarity)
	return items

func _cmp_pickup(a: ItemData, b: ItemData) -> bool:
	# instance_id is minted monotonically by GameState.add_item, so it doubles
	# as pickup order.
	return a.instance_id < b.instance_id

func _cmp_name(a: ItemData, b: ItemData) -> bool:
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0

func _cmp_rarity(a: ItemData, b: ItemData) -> bool:
	# Highest rarity first; ties broken by name.
	if int(a.rarity) != int(b.rarity):
		return int(a.rarity) > int(b.rarity)
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0

func _build_item_row(item: ItemData) -> Control:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	if item.image != null:
		var icon := TextureRect.new()
		icon.texture = item.image
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_lbl := Label.new()
	var rarity_idx: int = clampi(int(item.rarity), 0, RARITY_NAMES.size() - 1)
	name_lbl.text = "%s   [%s]" % [item.display_name, RARITY_NAMES[rarity_idx]]
	name_lbl.add_theme_color_override("font_color", RARITY_COLORS[rarity_idx])
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = item.description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(520, 0)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	info.add_child(desc_lbl)

	if item.kind == ItemData.ItemKind.USABLE:
		var use_btn := Button.new()
		use_btn.text = "Use"
		if item.max_uses > 1:
			use_btn.text = "Use (%d)" % item.max_uses
		use_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		use_btn.disabled = not GameState.can_use_items()
		use_btn.pressed.connect(func(): _on_use_pressed(item))
		hbox.add_child(use_btn)

	return row

func _on_use_pressed(item: ItemData) -> void:
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.8, 0.9, 1.0))
	_refresh()

func _render_loot() -> void:
	var any := false
	for kind in GameState.loot.keys():
		var count: int = int(GameState.loot[kind])
		if count <= 0:
			continue
		any = true
		var row := PanelContainer.new()
		var hbox := HBoxContainer.new()
		row.add_child(hbox)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = String(LOOT_LABELS.get(kind, String(kind).capitalize()))
		hbox.add_child(label)
		var count_lbl := Label.new()
		count_lbl.text = "x%d" % count
		count_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		hbox.add_child(count_lbl)
		_list_vbox.add_child(row)
	if not any:
		var empty := Label.new()
		empty.text = "No loot collected yet."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_vbox.add_child(empty)
	_hint_label.text = "Potions, scrolls, keys and other findings."

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

enum Tab { ITEMS, LOOT, GEAR, DECK }
enum SortMode { PICKUP, RARITY, NAME }

# Card-type labels for the Deck tab.
const CARD_TYPE_LABELS := ["Attack", "Skill", "Power", "Dice", "Status", "Curse", "Training"]

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
var _tab_gear_btn: Button
var _tab_deck_btn: Button
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
	GameState.deck_changed.connect(_on_state_changed)

# Tab toggles the backpack from anywhere in a run. Handled here (rather than
# in Main) because the backpack runs PROCESS_MODE_ALWAYS, so it keeps working
# while the tree is paused (i.e. so Tab also closes it once it's open).
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("backpack"):
		toggle()
		get_viewport().set_input_as_handled()

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
	# In action mode the backpack doubles as the equipment screen, but gear is
	# only meant to change between rooms — refuse to open over a live fight.
	var scene = GameState.combat_scene
	if scene != null and scene.has_method("has_live_enemies") and scene.has_live_enemies():
		GameLog.add("Clear the room before opening your backpack.", Color(0.85, 0.7, 0.4))
		return
	visible = true
	get_tree().paused = true
	_refresh()

func close() -> void:
	visible = false
	get_tree().paused = false
	# Re-apply the action loadout so any gear swap made here takes effect
	# immediately (recharges cooldowns too). No-op outside action combat.
	var scene = GameState.combat_scene
	if scene != null and scene.has_method("reload_loadout"):
		scene.reload_loadout()

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
	_tab_gear_btn = Button.new()
	_tab_gear_btn.text = "Gear"
	_tab_gear_btn.toggle_mode = true
	_tab_gear_btn.pressed.connect(func(): _set_tab(Tab.GEAR))
	tabs.add_child(_tab_gear_btn)
	_tab_deck_btn = Button.new()
	_tab_deck_btn.text = "Deck"
	_tab_deck_btn.toggle_mode = true
	_tab_deck_btn.pressed.connect(func(): _set_tab(Tab.DECK))
	tabs.add_child(_tab_deck_btn)

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
	_tab_gear_btn.button_pressed = _tab == Tab.GEAR
	_tab_deck_btn.button_pressed = _tab == Tab.DECK
	_sort_bar.visible = _tab == Tab.ITEMS
	for b in _sort_bar.get_children():
		if b is Button and b.has_meta("sort_mode"):
			b.modulate = Color(1, 1, 0.6) if int(b.get_meta("sort_mode")) == int(_sort) else Color.WHITE
	for child in _list_vbox.get_children():
		child.queue_free()
	match _tab:
		Tab.ITEMS:
			_render_items()
		Tab.LOOT:
			_render_loot()
		Tab.GEAR:
			_render_gear()
		Tab.DECK:
			_render_deck()

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

# ------------------------------------------------------------------
# Deck tab — every card the player currently owns, deduped by card id
# with a count, so the run's whole deck is viewable from anywhere.
# ------------------------------------------------------------------

func _render_deck() -> void:
	# Group the deck by card id, preserving first-seen order, and count copies.
	var counts: Dictionary = {}
	var order: Array = []
	var total := 0
	for c in GameState.deck:
		if not (c is CardInstance) or c.data == null:
			continue
		total += 1
		var id: StringName = c.data.id
		if counts.has(id):
			counts[id] += 1
		else:
			counts[id] = 1
			order.append(c.data)
	if order.is_empty():
		var empty := Label.new()
		empty.text = "Your deck is empty."
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_vbox.add_child(empty)
		_hint_label.text = "Every card in your run deck."
		return
	for data in order:
		_list_vbox.add_child(_build_card_row(data, int(counts[data.id])))
	_hint_label.text = "%d cards across %d unique." % [total, order.size()]

func _build_card_row(card: CardData, count: int) -> Control:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# Cost chip.
	var cost := Label.new()
	cost.text = "X" if card.cost < 0 else str(card.cost)
	cost.custom_minimum_size = Vector2(28, 0)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	hbox.add_child(cost)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_lbl := Label.new()
	var type_idx: int = clampi(int(card.type), 0, CARD_TYPE_LABELS.size() - 1)
	var rarity_idx: int = clampi(int(card.rarity), 0, RARITY_COLORS.size() - 1)
	var copies: String = ("   x%d" % count) if count > 1 else ""
	name_lbl.text = "%s%s   [%s]" % [card.display_name, copies, CARD_TYPE_LABELS[type_idx]]
	name_lbl.add_theme_color_override("font_color", RARITY_COLORS[rarity_idx])
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = card.description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(560, 0)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	info.add_child(desc_lbl)

	return row

# ------------------------------------------------------------------
# Gear tab — action-combat loadout (doubles as the equipment screen).
# Equipment can't be changed mid-combat (the action rule); the rows go
# read-only whenever a combat is live.
# ------------------------------------------------------------------

func _render_gear() -> void:
	# Action combat exposes reload_loadout(); the backpack only opens there
	# between rooms, so gear stays editable. Turn-based card combats keep the
	# action loadout locked while a fight is live.
	var scene = GameState.combat_scene
	var locked: bool = scene != null and not scene.has_method("reload_loadout")
	if locked:
		var note := Label.new()
		note.text = "You can't change equipment during combat."
		note.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
		_list_vbox.add_child(note)
	_list_vbox.add_child(_gear_row(
		"Left click (LMB)", _card_name(GameState.action_left_card_id),
		func(): _cycle_click_slot(0), locked))
	_list_vbox.add_child(_gear_row(
		"Right click (RMB)", _card_name(GameState.action_right_card_id),
		func(): _cycle_click_slot(1), locked))
	_list_vbox.add_child(_gear_row(
		"Active item (Q)", _item_name(GameState.action_active_item_id),
		_cycle_active_item, locked))
	_hint_label.text = "Locked while fighting." if locked \
		else "Set your action-combat click cards and the consumable you pop with Q. Strikes/weapons only in click slots."

func _gear_row(label_text: String, value_text: String, on_change: Callable, locked: bool) -> Control:
	var row := PanelContainer.new()
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	hbox.add_child(lbl)
	var val := Label.new()
	val.text = value_text
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	hbox.add_child(val)
	var btn := Button.new()
	btn.text = "Change"
	btn.disabled = locked
	btn.pressed.connect(on_change)
	hbox.add_child(btn)
	return row

func _card_name(id: StringName) -> String:
	if id == &"":
		return "(none)"
	var c: CardData = Data.get_card(id)
	return c.display_name if c != null else String(id)

func _item_name(id: StringName) -> String:
	if id == &"":
		return "(none)"
	var it: ItemData = Data.get_item(id)
	return it.display_name if it != null else String(id)

func _usable_item_ids() -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.kind == ItemData.ItemKind.USABLE and not out.has(it.id):
			out.append(it.id)
	return out

func _eligible_click_ids() -> Array:
	var out: Array = []
	for c in GameState.deck:
		if c is CardInstance and c.data != null:
			var id: StringName = c.data.id
			if not out.has(id) and GameState.is_click_eligible(id):
				out.append(id)
	return out

func _would_dual_strike(slot: int, cand: StringName) -> bool:
	# Only one Strike across the two click slots (mirrors EquipmentScreen).
	if cand == &"":
		return false
	var cd: CardData = Data.get_card(cand)
	if cd == null or not cd.tags.has("strike"):
		return false
	var other_id: StringName = GameState.action_right_card_id if slot == 0 else GameState.action_left_card_id
	var oc: CardData = Data.get_card(other_id)
	return oc != null and oc.tags.has("strike")

func _cycle_click_slot(slot: int) -> void:
	var ids: Array = _eligible_click_ids()
	if ids.is_empty():
		GameLog.add("No Strikes or weapons in your deck to slot.", Color(0.85, 0.7, 0.4))
		return
	var options: Array = ids.duplicate()
	options.push_front(&"")
	var cur_id: StringName = GameState.action_left_card_id if slot == 0 else GameState.action_right_card_id
	var idx: int = options.find(cur_id)
	if idx == -1:
		idx = 0
	var n: int = options.size()
	for step in range(1, n + 1):
		var cand: StringName = options[(idx + step) % n]
		if _would_dual_strike(slot, cand):
			continue
		if slot == 0:
			GameState.action_left_card_id = cand
		else:
			GameState.action_right_card_id = cand
		break
	_refresh()

func _cycle_active_item() -> void:
	var ids: Array = _usable_item_ids()
	if ids.is_empty():
		GameLog.add("No usable items to slot.", Color(0.85, 0.7, 0.4))
		return
	var options: Array = ids.duplicate()
	options.push_front(&"")
	var cur: int = options.find(GameState.action_active_item_id)
	if cur == -1:
		cur = 0
	GameState.action_active_item_id = options[(cur + 1) % options.size()]
	_refresh()

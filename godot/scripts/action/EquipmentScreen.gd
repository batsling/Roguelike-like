class_name EquipmentScreen
extends Control

# Action-mode equipment screen. Shows the 2 click slots (LMB / RMB) and the
# player's deck; click a slot to select, then click a Strike or weapon card
# to assign it. Everything else in the deck plays automatically and is shown
# under an info header. Continue persists the choices onto
# GameState.action_left_card_id / action_right_card_id and emits `closed`.
#
# Standalone Control like Shop / RestSite / TreasureRoom. The caller
# (action floor map between rooms) free()s it on close.

signal closed

var _selected_slot: int = -1            # -1 = none, 0 = left (LMB), 1 = right (RMB)
var _left_card: CardData = null
var _right_card: CardData = null
var _slot_btns: Array[Button] = []
# Pre-assigned active consumable, fired with Q during action combat. Stored
# by item id; cycled through the player's usable items on the slot button.
var _active_item_id: StringName = &""
var _active_btn: Button = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Standalone bootstrap so the scene runs from the editor.
	if GameState.character_id == &"":
		var ironclad: CharacterData = Data.get_character(&"ironclad")
		if ironclad != null:
			GameState.reset_run()
			GameState.apply_character(ironclad)
	_load_current()
	_build_ui()
	_refresh_slots()

func _load_current() -> void:
	var loadout: Dictionary = GameState.get_action_loadout()
	_left_card = loadout.left
	_right_card = loadout.right
	# Restore the active item only if the player still owns a usable copy.
	_active_item_id = GameState.action_active_item_id
	if _active_item_id != &"" and not _usable_item_ids().has(_active_item_id):
		_active_item_id = &""

# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.85)
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(980, 640)
	panel.position = (get_viewport_rect().size - panel.size) * 0.5
	add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 16)
	title.size = Vector2(940, 28)
	title.text = "Equipment"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var hint := Label.new()
	hint.position = Vector2(20, 48)
	hint.size = Vector2(940, 22)
	hint.text = "Click a click-slot (LMB/RMB), then a Strike or weapon to assign it. All other cards auto-play. The Active Item (Q) slot holds a consumable to pop mid-room. Continue when done."
	hint.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)

	# Slot row at the top
	var slot_row := HBoxContainer.new()
	slot_row.position = Vector2(20, 84)
	slot_row.size = Vector2(940, 150)
	slot_row.add_theme_constant_override("separation", 16)
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(slot_row)

	for i in range(2):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 140)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		var idx: int = i
		btn.pressed.connect(func(): _on_slot_clicked(idx))
		slot_row.add_child(btn)
		_slot_btns.append(btn)

	# Active consumable slot — click to cycle through the usable items the
	# player currently holds (None -> item1 -> item2 -> ... -> None).
	_active_btn = Button.new()
	_active_btn.custom_minimum_size = Vector2(300, 140)
	_active_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	_active_btn.pressed.connect(_on_active_clicked)
	slot_row.add_child(_active_btn)

	# Deck list label
	var deck_lbl := Label.new()
	deck_lbl.position = Vector2(20, 248)
	deck_lbl.size = Vector2(940, 22)
	deck_lbl.text = "Your deck — Strikes/weapons assign to a click slot; everything else auto-plays"
	deck_lbl.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	panel.add_child(deck_lbl)

	# Scrollable deck list (deduped by card id). Strike/weapon cards are
	# clickable (assign to the selected slot); the rest are shown greyed as
	# auto-play so the player can see what's cycling automatically.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 278)
	scroll.size = Vector2(940, 280)
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var seen: Dictionary = {}
	for c in GameState.deck:
		if not (c is CardInstance) or c.data == null:
			continue
		var data: CardData = c.data
		if seen.has(data.id):
			continue
		seen[data.id] = true
		var eligible: bool = GameState.is_click_eligible(data.id)
		var auto_tag: String = "click" if eligible else ("passive" if data.is_power() else "auto")
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(920, 38)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.text = "[%d] %s   (%s, %s)   --  %s" % [
			data.cost, data.display_name, _type_label(data.type), auto_tag, data.description,
		]
		if eligible:
			var data_ref: CardData = data
			btn.pressed.connect(func(): _on_card_clicked(data_ref))
		else:
			btn.disabled = true
		vbox.add_child(btn)

	# Clear-slot + Continue
	var clear_btn := Button.new()
	clear_btn.position = Vector2(220, 580)
	clear_btn.size = Vector2(180, 44)
	clear_btn.text = "Clear selected slot"
	clear_btn.pressed.connect(_on_clear_slot)
	panel.add_child(clear_btn)

	var cont_btn := Button.new()
	cont_btn.position = Vector2(600, 580)
	cont_btn.size = Vector2(180, 44)
	cont_btn.text = "Continue"
	cont_btn.pressed.connect(_on_continue)
	panel.add_child(cont_btn)

# ---------------------------------------------------------------------------

func _refresh_slots() -> void:
	var slot_titles := ["[LMB] Left click", "[RMB] Right click"]
	for i in range(2):
		var card: CardData = _left_card if i == 0 else _right_card
		var content: String = "(empty)" if card == null else "%s\n(%s)" % [
			card.display_name, _type_label(card.type),
		]
		var tail: String = "\n<-- selected" if _selected_slot == i else ""
		_slot_btns[i].text = "%s\n\n%s%s" % [slot_titles[i], content, tail]
		_slot_btns[i].modulate = Color(1.0, 0.85, 0.35) if _selected_slot == i else Color.WHITE
	if _active_btn != null:
		var active_name: String = "(none)"
		if _active_item_id != &"":
			var it: ItemData = Data.get_item(_active_item_id)
			if it != null:
				active_name = it.display_name
		_active_btn.text = "[Q] Active Item\n\n%s\n\nClick to cycle" % active_name

func _usable_item_ids() -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.kind == ItemData.ItemKind.USABLE and not out.has(it.id):
			out.append(it.id)
	return out

func _on_active_clicked() -> void:
	var ids: Array = _usable_item_ids()
	if ids.is_empty():
		GameLog.add("No usable items in your backpack to slot.", Color(0.85, 0.7, 0.4))
		return
	# Cycle: none -> ids[0] -> ids[1] -> ... -> none.
	var options: Array = ids.duplicate()
	options.push_front(&"")
	var cur: int = options.find(_active_item_id)
	if cur == -1:
		cur = 0
	_active_item_id = options[(cur + 1) % options.size()]
	_refresh_slots()

func _on_slot_clicked(idx: int) -> void:
	_selected_slot = idx
	_refresh_slots()

func _on_card_clicked(card: CardData) -> void:
	if _selected_slot < 0:
		GameLog.add("Pick a click slot first.", Color(0.85, 0.7, 0.4))
		return
	if not GameState.is_click_eligible(card.id):
		GameLog.add("Only Strikes or weapons can go in a click slot.", Color(0.85, 0.7, 0.4))
		return
	# Only one Strike across the two click slots — no dual-wielding Strikes.
	if card.tags.has("strike"):
		var other: CardData = _right_card if _selected_slot == 0 else _left_card
		if other != null and other.tags.has("strike"):
			GameLog.add("You can only wield one Strike at a time.", Color(0.85, 0.7, 0.4))
			return
	if _selected_slot == 0:
		_left_card = card
	else:
		_right_card = card
	GameLog.add("Equipped %s to %s." % [
		card.display_name, "LMB" if _selected_slot == 0 else "RMB"], Color(0.7, 1.0, 0.7))
	_refresh_slots()

func _on_clear_slot() -> void:
	if _selected_slot < 0:
		return
	if _selected_slot == 0:
		_left_card = null
	else:
		_right_card = null
	_refresh_slots()

func _on_continue() -> void:
	GameState.action_left_card_id = _left_card.id if _left_card != null else &""
	GameState.action_right_card_id = _right_card.id if _right_card != null else &""
	GameState.action_active_item_id = _active_item_id
	GameLog.add("Loadout saved.", Color(0.7, 0.9, 1.0))
	emit_signal("closed")

func _type_label(t: int) -> String:
	match t:
		0: return "Attack"
		1: return "Skill"
		2: return "Power"
		3: return "Dice"
		4: return "Status"
		5: return "Curse"
		6: return "Training"
		_: return "?"

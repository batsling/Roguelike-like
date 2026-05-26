class_name EquipmentScreen
extends Control

# Action-mode equipment screen. Shows the 4 loadout slots (basic +
# 3 abilities) and the player's deck; click a slot to select, then
# click a card to assign. Continue persists the choices onto
# GameState.action_basic_attack_id + GameState.action_ability_ids and
# emits `closed`.
#
# Standalone Control like Shop / RestSite / TreasureRoom. The caller
# (action floor map between rooms) free()s it on close.

signal closed

var _selected_slot: int = -1            # -1 = none, 0 = basic, 1-3 = abilities
var _basic_card: CardData = null
var _abilities: Array = [null, null, null]
var _slot_btns: Array[Button] = []

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
	_basic_card = loadout.basic
	_abilities = loadout.abilities.duplicate()
	while _abilities.size() < 3:
		_abilities.append(null)

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
	hint.text = "Click a slot, then click a card from your deck to assign it. Continue when done."
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

	for i in range(4):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(212, 140)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		var idx: int = i
		btn.pressed.connect(func(): _on_slot_clicked(idx))
		slot_row.add_child(btn)
		_slot_btns.append(btn)

	# Deck list label
	var deck_lbl := Label.new()
	deck_lbl.position = Vector2(20, 248)
	deck_lbl.size = Vector2(940, 22)
	deck_lbl.text = "Your deck (click a card to assign it to the selected slot)"
	deck_lbl.add_theme_color_override("font_color", Color(0.82, 0.85, 0.92))
	panel.add_child(deck_lbl)

	# Scrollable deck list (deduped by card id)
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
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(920, 38)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.text = "[%d] %s   (%s)   --  %s" % [
			data.cost, data.display_name, _type_label(data.type), data.description,
		]
		var data_ref: CardData = data
		btn.pressed.connect(func(): _on_card_clicked(data_ref))
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
	var slot_titles := ["[LMB] Basic", "[1] Ability", "[2] Ability", "[3] Ability"]
	for i in range(4):
		var card: CardData = _basic_card if i == 0 else _abilities[i - 1]
		var content: String = "(empty)" if card == null else "%s\n(%s)" % [
			card.display_name, _type_label(card.type),
		]
		var tail: String = "\n<-- selected" if _selected_slot == i else ""
		_slot_btns[i].text = "%s\n\n%s%s" % [slot_titles[i], content, tail]
		_slot_btns[i].modulate = Color(1.0, 0.85, 0.35) if _selected_slot == i else Color.WHITE

func _on_slot_clicked(idx: int) -> void:
	_selected_slot = idx
	_refresh_slots()

func _on_card_clicked(card: CardData) -> void:
	if _selected_slot < 0:
		GameLog.add("Pick a slot first.", Color(0.85, 0.7, 0.4))
		return
	if _selected_slot == 0:
		_basic_card = card
	else:
		_abilities[_selected_slot - 1] = card
	GameLog.add("Equipped %s to slot %d." % [card.display_name, _selected_slot], Color(0.7, 1.0, 0.7))
	_refresh_slots()

func _on_clear_slot() -> void:
	if _selected_slot < 0:
		return
	if _selected_slot == 0:
		_basic_card = null
	else:
		_abilities[_selected_slot - 1] = null
	_refresh_slots()

func _on_continue() -> void:
	GameState.action_basic_attack_id = _basic_card.id if _basic_card != null else &""
	var ids: Array[StringName] = []
	for c in _abilities:
		if c != null:
			ids.append(c.id)
	GameState.action_ability_ids = ids
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

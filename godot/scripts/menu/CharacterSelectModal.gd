extends Control

# New-run modal: pick a character, type a save name, hit Begin.
# Single panel for now (Ironclad is the only authored character) but
# the layout is built around a left-side roster + right-side details so
# a second character is just another row to add.
#
# Emits `confirmed(character_id, save_name)` when the player commits and
# `cancelled` if they back out.

signal confirmed(character_id: StringName, save_name: String)
signal cancelled

@onready var _roster: VBoxContainer = %Roster
@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %CharacterName
@onready var _description: Label = %Description
@onready var _stats_label: RichTextLabel = %Stats
@onready var _deck_label: RichTextLabel = %Deck
@onready var _name_input: LineEdit = %SaveNameInput
@onready var _name_warning: Label = %NameWarning
@onready var _begin_btn: Button = %BeginBtn
@onready var _cancel_btn: Button = %CancelBtn

var _selected_id: StringName = &""
var _row_for: Dictionary = {}     # StringName -> Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_begin_btn.pressed.connect(_on_begin)
	_cancel_btn.pressed.connect(_on_cancel)
	_name_input.text_changed.connect(_on_name_changed)
	_populate_roster()
	_name_warning.visible = false
	_name_input.grab_focus()

func _populate_roster() -> void:
	for c in _roster.get_children():
		c.queue_free()
	_row_for.clear()
	var characters: Array = Data.all_characters()
	if characters.is_empty():
		var lbl := Label.new()
		lbl.text = "No characters available."
		_roster.add_child(lbl)
		return
	# Sort by display_name to keep the list stable across runs.
	characters.sort_custom(func(a, b): return String(a.display_name) < String(b.display_name))
	for ch in characters:
		if not (ch is CharacterData):
			continue
		var btn := Button.new()
		btn.text = ch.display_name
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(220, 56)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id_copy: StringName = ch.id
		btn.pressed.connect(func(): _select(id_copy))
		_roster.add_child(btn)
		_row_for[ch.id] = btn
	# Auto-select the first.
	_select((characters[0] as CharacterData).id)

func _select(id: StringName) -> void:
	if id == &"":
		return
	_selected_id = id
	for k in _row_for:
		(_row_for[k] as Button).button_pressed = (k == id)
	var ch: CharacterData = Data.get_character(id)
	if ch == null:
		return
	_portrait.texture = ch.portrait
	_name_label.text = ch.display_name
	_description.text = ch.description
	_stats_label.text = _format_stats(ch)
	_deck_label.text = _format_deck(ch)

func _format_stats(ch: CharacterData) -> String:
	var bits: Array = []
	bits.append("[b]HP[/b]: %d" % ch.base_max_hp)
	bits.append("[b]Energy[/b]: %d" % ch.base_max_energy)
	bits.append("[b]Hand[/b]: %d" % ch.base_hand_size)
	var stat_pairs := [
		["Str", ch.base_strength],
		["Dex", ch.base_dexterity],
		["Int", ch.base_intelligence],
		["Cha", ch.base_charisma],
		["Con", ch.base_constitution],
		["Lck", ch.base_luck],
	]
	var stat_strs: Array = []
	for p in stat_pairs:
		if int(p[1]) != 0:
			stat_strs.append("%s %+d" % [p[0], p[1]])
	if not stat_strs.is_empty():
		bits.append(" ".join(stat_strs))
	return "  •  ".join(bits)

func _format_deck(ch: CharacterData) -> String:
	if ch.starting_deck.is_empty():
		return "(empty deck)"
	var counts: Dictionary = {}
	for cid in ch.starting_deck:
		counts[cid] = int(counts.get(cid, 0)) + 1
	var lines: Array = ["[b]Starting Deck[/b]"]
	for cid in counts:
		var card: CardData = Data.get_card(cid)
		var label := String(cid) if card == null else card.display_name
		lines.append("  %dx %s" % [counts[cid], label])
	if not ch.starting_items.is_empty():
		lines.append("\n[b]Starting Items[/b]")
		for iid in ch.starting_items:
			var it: ItemData = Data.get_item(iid)
			lines.append("  • %s" % (String(iid) if it == null else it.display_name))
	return "\n".join(lines)

func _on_name_changed(_text: String) -> void:
	_name_warning.visible = false

func _on_begin() -> void:
	var name := _name_input.text.strip_edges()
	if name == "":
		_name_warning.text = "Enter a save name."
		_name_warning.visible = true
		return
	if _selected_id == &"":
		_name_warning.text = "Pick a character."
		_name_warning.visible = true
		return
	if SaveSystem.has_named_save(name):
		# Show a confirm dialog for overwrite.
		var confirm := ConfirmationDialog.new()
		confirm.dialog_text = "A save called \"%s\" already exists. Overwrite it?" % name
		confirm.confirmed.connect(func():
			confirm.queue_free()
			emit_signal("confirmed", _selected_id, name)
		)
		confirm.canceled.connect(func(): confirm.queue_free())
		add_child(confirm)
		confirm.popup_centered(Vector2i(440, 160))
		return
	emit_signal("confirmed", _selected_id, name)

func _on_cancel() -> void:
	emit_signal("cancelled")

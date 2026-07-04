extends Control

# New-run modal: pick a deck (left), pick a character (centre), review the
# details panel (right), type a save name, hit Begin. Mirrors the HTML build's
# three-panel character select (legacy-web/js/character-select.js): the deck
# choice is independent of the character and only scopes card rewards for the
# run (see DeckCatalog / GameState.deck_reward_tag).
#
# Emits `confirmed(character_id, deck_id, save_name)` when the player commits
# and `cancelled` if they back out.

signal confirmed(character_id: StringName, deck_id: StringName, save_name: String)
signal cancelled

const GOLD := Color(1.0, 0.85, 0.4)
const DIM_BORDER := Color(0.3, 0.3, 0.34)
const WIN_GREEN := Color(0.3, 0.78, 0.32)
# Card-name colours per CardData.Rarity (STARTER..LEGENDARY), matching
# CardView's rarity stripe palette.
const CARD_RARITY_COLORS := [
	Color(0.7, 0.7, 0.7), Color(0.92, 0.92, 0.92), Color(0.4, 0.75, 1.0),
	Color(1.0, 0.85, 0.3), Color(1.0, 0.5, 1.0),
]
const CARD_TYPE_NAMES := ["Attack", "Skill", "Power", "Dice", "Status", "Curse", "Training"]

@onready var _deck_list: VBoxContainer = %DeckList
@onready var _roster: VBoxContainer = %Roster
@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %CharacterName
@onready var _from_game: Label = %FromGame
@onready var _description: Label = %Description
@onready var _stats_label: RichTextLabel = %Stats
@onready var _details: RichTextLabel = %Details
@onready var _name_input: LineEdit = %SaveNameInput
@onready var _name_warning: Label = %NameWarning
@onready var _begin_btn: Button = %BeginBtn
@onready var _cancel_btn: Button = %CancelBtn

var _selected_id: StringName = &""
var _selected_deck: StringName = DeckCatalog.DEFAULT_DECK_ID
var _row_for: Dictionary = {}     # StringName -> Button
var _deck_tile_for: Dictionary = {}  # StringName -> PanelContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_begin_btn.pressed.connect(_on_begin)
	_cancel_btn.pressed.connect(_on_cancel)
	_name_input.text_changed.connect(_on_name_changed)
	_populate_decks()
	_populate_roster()
	_name_warning.visible = false
	_name_input.grab_focus()

# ---------------------------------------------------------------------------
# Deck panel
# ---------------------------------------------------------------------------

func _populate_decks() -> void:
	for c in _deck_list.get_children():
		c.queue_free()
	_deck_tile_for.clear()
	for deck in DeckCatalog.all():
		var tile := _build_deck_tile(deck)
		_deck_list.add_child(tile)
		_deck_tile_for[deck["id"]] = tile
	_restyle_deck_tiles()

func _build_deck_tile(deck: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	var art: Texture2D = DeckCatalog.image(deck["id"])
	if art != null:
		var tr := TextureRect.new()
		tr.texture = art
		tr.custom_minimum_size = Vector2(150, 56)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tr)
	else:
		# Random deck has no art — a big "?" placeholder like the HTML tile.
		var q := Label.new()
		q.text = "?"
		q.custom_minimum_size = Vector2(150, 56)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.add_theme_font_size_override("font_size", 30)
		q.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(q)

	var name_lbl := Label.new()
	name_lbl.name = "DeckName"
	name_lbl.text = String(deck["name"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)

	var desc := Label.new()
	desc.text = String(deck["description"])
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(150, 0)
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(desc)

	var id_copy: StringName = deck["id"]
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_select_deck(id_copy))
	return panel

func _select_deck(id: StringName) -> void:
	_selected_deck = id
	_restyle_deck_tiles()

func _restyle_deck_tiles() -> void:
	for id in _deck_tile_for:
		var panel: PanelContainer = _deck_tile_for[id]
		var selected: bool = id == _selected_deck
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.85, 0.4, 0.06) if selected else Color(0, 0, 0, 0.3)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(2)
		sb.border_color = GOLD if selected else DIM_BORDER
		sb.set_content_margin_all(8)
		panel.add_theme_stylebox_override("panel", sb)
		var name_lbl: Label = panel.get_child(0).get_node("DeckName")
		name_lbl.add_theme_color_override("font_color", GOLD if selected else Color(0.87, 0.87, 0.9))

# ---------------------------------------------------------------------------
# Character roster + details
# ---------------------------------------------------------------------------

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
		if ch.icon != null:
			btn.icon = ch.icon
			btn.expand_icon = true
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
	_from_game.text = ("From: %s" % ch.source_game) if ch.source_game != "" else ""
	_from_game.visible = ch.source_game != ""
	_description.text = ch.description
	_stats_label.text = _format_stats(ch)
	_details.text = _format_details(ch)

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

# The scrolling details body: level-up, starting deck (rarity-coloured),
# starting items, and the per-deck win checklist — the same sections the HTML
# details panel showed.
func _format_details(ch: CharacterData) -> String:
	var lines: Array = []

	if ch.level_up_condition != "":
		lines.append("[b][color=#ff9800]⬆ Level Up[/color][/b]")
		lines.append(ch.level_up_condition)
		var bonuses: Array = []
		for stat in ch.level_up_stats:
			bonuses.append("[color=#4caf50]+%d %s[/color]" % [int(ch.level_up_stats[stat]), String(stat).capitalize()])
		if not bonuses.is_empty():
			lines.append("Bonuses: %s" % ", ".join(bonuses))
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			lines.append("Reward: %s" % ch.level_up_reward)
		lines.append("")

	lines.append("[b]Starting Deck[/b]")
	if ch.starting_deck.is_empty():
		lines.append("  (empty deck)")
	else:
		var counts: Dictionary = {}
		for cid in ch.starting_deck:
			counts[cid] = int(counts.get(cid, 0)) + 1
		for cid in counts:
			var card: CardData = Data.get_card_for_character(cid, ch.id)
			if card == null:
				lines.append("  %dx %s" % [counts[cid], String(cid)])
				continue
			var col: Color = CARD_RARITY_COLORS[clampi(int(card.rarity), 0, CARD_RARITY_COLORS.size() - 1)]
			var meta: String = CARD_TYPE_NAMES[clampi(int(card.type), 0, CARD_TYPE_NAMES.size() - 1)]
			var cost_str := "X" if card.cost < 0 else str(card.cost)
			lines.append("  [color=#%s]%dx %s[/color]  [color=#8a8a90]%s · Cost %s[/color]" % [
				col.to_html(false), counts[cid], card.display_name, meta, cost_str])

	if not ch.starting_items.is_empty():
		lines.append("")
		lines.append("[b]Starting Item%s[/b]" % ("s" if ch.starting_items.size() > 1 else ""))
		for iid in ch.starting_items:
			var it: ItemData = Data.get_item(iid)
			if it == null:
				lines.append("  • %s" % String(iid))
				continue
			var icol := Color(0.4, 0.85, 0.95) if it.starter else RarityStyle.color(int(it.rarity))
			lines.append("  • [color=#%s]%s[/color]" % [icol.to_html(false), it.display_name])

	lines.append("")
	lines.append("[b]🏆 Beaten With Deck[/b]")
	for deck in DeckCatalog.all():
		var won: bool = GameStats.has_deck_win(ch.id, deck["id"])
		var mark := "✅" if won else "⬜"
		var col: Color = WIN_GREEN if won else Color(0.53, 0.53, 0.58)
		lines.append("  %s [color=#%s]%s Deck[/color]" % [mark, col.to_html(false), String(deck["name"])])

	return "\n".join(lines)

# ---------------------------------------------------------------------------
# Commit / cancel
# ---------------------------------------------------------------------------

func _on_name_changed(_text: String) -> void:
	_name_warning.visible = false

func _on_begin() -> void:
	var save_name := _name_input.text.strip_edges()
	if save_name == "":
		_name_warning.text = "Enter a save name."
		_name_warning.visible = true
		return
	if _selected_id == &"":
		_name_warning.text = "Pick a character."
		_name_warning.visible = true
		return
	if SaveSystem.has_named_save(save_name):
		# Show a confirm dialog for overwrite.
		var confirm := ConfirmationDialog.new()
		confirm.dialog_text = "A save called \"%s\" already exists. Overwrite it?" % save_name
		confirm.confirmed.connect(func():
			confirm.queue_free()
			emit_signal("confirmed", _selected_id, _selected_deck, save_name)
		)
		confirm.canceled.connect(func(): confirm.queue_free())
		add_child(confirm)
		confirm.popup_centered(Vector2i(440, 160))
		return
	emit_signal("confirmed", _selected_id, _selected_deck, save_name)

func _on_cancel() -> void:
	emit_signal("cancelled")

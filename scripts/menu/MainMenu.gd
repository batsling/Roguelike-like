extends Control

# Main menu — the project's startup scene. Post games-first cut
# (docs/games-first-redesign.md §11) "Start Run" opens a 2.0 character picker and
# launches the games-first overworld (Overworld2). The old combat run flow
# (CharacterSelect -> ChooseYourStart -> Main.tscn) is gone.
#
# Collection opens the compendium; Tier List / Settings open their screens. The
# remaining system-less buttons raise a "Coming Soon" stub. The Continue list is
# gated off until the 2.0 save shape is finalized.

const OVERWORLD2_SCENE := "res://scenes/redesign2/Overworld2.tscn"

@onready var _continue_btn: Button = %ContinueBtn
@onready var _save_list_container: VBoxContainer = %SaveList
@onready var _modal_layer: Control = %ModalLayer

func _ready() -> void:
	GameState.phase = GameState.Phase.MENU
	theme = UITheme.shared()
	_style_menu()

	%StartRunBtn.pressed.connect(_on_start_run)
	%ContinueBtn.pressed.connect(_on_continue_toggle)
	%RunHistoryBtn.pressed.connect(_on_run_history)
	%CollectionBtn.pressed.connect(_on_collection)
	%TierListBtn.pressed.connect(_on_tier_list)
	%SettingsBtn.pressed.connect(_on_settings)
	%HowToPlayBtn.pressed.connect(_on_how_to_play)
	%ClearDataBtn.pressed.connect(_on_clear_data)

	# Continue is disabled until the 2.0 save shape lands.
	_continue_btn.disabled = true
	_continue_btn.text = "Continue (unavailable)"
	_save_list_container.visible = false

# ---------------------------------------------------------------------------
# Menu styling
# ---------------------------------------------------------------------------

func _style_menu() -> void:
	var bg := get_node_or_null("Background")
	if bg is ColorRect:
		bg.color = UITheme.BG_DEEP
	# A subtle warm vignette panel behind the button column reads better than a
	# flat page; add it under the centre content if not already present.
	var title := get_node_or_null("Center/Panel/Title")
	if title is Label:
		title.add_theme_color_override("font_color", UITheme.GOLD)
		var sub := get_node_or_null("Center/Panel/Subtitle")
		if sub == null:
			var s := Label.new()
			s.name = "Subtitle"
			s.text = "A games-first roguelike"
			s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s.add_theme_font_size_override("font_size", 14)
			s.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			title.get_parent().add_child(s)
			title.get_parent().move_child(s, title.get_index() + 1)
	# Make the primary action stand out.
	var start := get_node_or_null("Center/Panel/Buttons/StartRunBtn")
	if start is Button:
		start.add_theme_stylebox_override("normal", UITheme.accent_box(UITheme.ACCENT, UITheme.PANEL_HI, 8))
		start.add_theme_color_override("font_color", UITheme.GOLD)
		start.add_theme_font_size_override("font_size", 20)

# ---------------------------------------------------------------------------
# Start Run flow — pick a 2.0 character, then enter Overworld2
# ---------------------------------------------------------------------------

func _on_start_run() -> void:
	for c in _modal_layer.get_children():
		c.queue_free()
	var picker := _build_character_picker()
	_modal_layer.add_child(picker)

# A code-built character-select overlay over the roster in data/characters2.0.
# The roster shows as a grid of portrait cards; click a card to begin the run.
func _build_character_picker() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UITheme.shared()

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 600)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG, UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 12, 22, 2))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Choose Your Character"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var hint := Label.new()
	hint.text = "Each hero opens the run with a different Health pool and set of verbs."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	header.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(736, 470)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for ch in Data.all_characters2():
		if ch is CharacterData:
			grid.add_child(_character_card(ch))

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.custom_minimum_size = Vector2(160, 0)
	cancel.pressed.connect(func(): root.queue_free())
	vbox.add_child(cancel)
	return root

# One character = a clickable portrait card (portrait, name, source, Health, the
# non-zero starting verbs, and a description blurb).
func _character_card(ch: CharacterData) -> Control:
	var accent := UITheme.GOLD
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(228, 0)
	var normal := UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 12, 12, 1)
	var hover := UITheme.accent_box(accent, UITheme.PANEL_HI, 12)
	card.add_theme_stylebox_override("panel", normal)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.mouse_entered.connect(func():
		card.add_theme_stylebox_override("panel", hover)
		card.modulate = Color(1.06, 1.06, 1.06))
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", normal)
		card.modulate = Color.WHITE)
	var cid: StringName = ch.id
	card.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_begin_run(cid))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)

	if ch.portrait != null:
		var portrait := TextureRect.new()
		portrait.texture = ch.portrait
		portrait.custom_minimum_size = Vector2(0, 150)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vb.add_child(portrait)

	var name_lbl := Label.new()
	name_lbl.text = ch.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", accent)
	vb.add_child(name_lbl)

	if ch.source_game != "":
		var src := Label.new()
		src.text = ch.source_game
		src.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		src.add_theme_font_size_override("font_size", 11)
		src.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		vb.add_child(src)

	var hp := Label.new()
	hp.text = "❤ %d Health" % ch.base_max_hp
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.add_theme_font_size_override("font_size", 13)
	hp.add_theme_color_override("font_color", UITheme.DANGER.lerp(UITheme.TEXT, 0.35))
	vb.add_child(hp)

	var chips := _verb_chips(ch)
	if chips != null:
		vb.add_child(chips)

	if ch.description != "":
		vb.add_child(HSeparator.new())
		var desc := Label.new()
		desc.text = ch.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(204, 0)
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		vb.add_child(desc)

	return card

# A centered wrap of the character's non-zero starting verbs as small pills, or
# null when the loadout is all-zero.
func _verb_chips(ch: CharacterData) -> Control:
	var verbs := [
		["Bash", ch.start_bash], ["Dash", ch.start_dash],
		["Transmute", ch.start_transmute], ["Scramble", ch.start_scramble],
		["Bombs", ch.start_bombs], ["Keys", ch.start_keys],
	]
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var any := false
	for v in verbs:
		if int(v[1]) <= 0:
			continue
		any = true
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL_HI, 6, 4, 1, UITheme.BORDER))
		var pl := Label.new()
		pl.text = "%s %d" % [v[0], int(v[1])]
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", UITheme.ACCENT.lerp(UITheme.TEXT, 0.3))
		pill.add_child(pl)
		flow.add_child(pill)
	return flow if any else null

func _begin_run(character_id: StringName) -> void:
	# Overworld2 boots the run itself (rolls the graph, applies the 2.0 loadout);
	# it reads the chosen character from this pending meta on _ready.
	GameState.set_meta("pending_character2", character_id)
	get_tree().change_scene_to_file(OVERWORLD2_SCENE)

# ---------------------------------------------------------------------------
# Continue list (gated off — see _ready)
# ---------------------------------------------------------------------------

func _on_continue_toggle() -> void:
	pass

# ---------------------------------------------------------------------------
# Stub buttons — backing systems land later.
# ---------------------------------------------------------------------------

func _on_run_history() -> void:
	_show_coming_soon("Run History", "Run history will live here once we track finished runs.")

func _on_collection() -> void:
	Collection.open(_modal_layer)

func _on_tier_list() -> void:
	TierListScreen.open(_modal_layer)

func _on_settings() -> void:
	SettingsModal.open(_modal_layer)

func _on_how_to_play() -> void:
	_show_coming_soon("How to Play", "Choose a character, then route the game-graph toward the Amulet — beat each game's goal to defeat its enemy. Full tutorial coming soon.")

func _on_clear_data() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Delete ALL saves? This cannot be undone."
	confirm.confirmed.connect(func():
		SaveSystem.clear_all_saves()
	)
	_modal_layer.add_child(confirm)
	confirm.popup_centered(Vector2i(420, 160))

func _show_coming_soon(title: String, body: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.dialog_text = body
	_modal_layer.add_child(dlg)
	dlg.popup_centered(Vector2i(480, 220))
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())

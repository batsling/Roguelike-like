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
# Start Run flow — pick a 2.0 character, then enter Overworld2
# ---------------------------------------------------------------------------

func _on_start_run() -> void:
	for c in _modal_layer.get_children():
		c.queue_free()
	var picker := _build_character_picker()
	_modal_layer.add_child(picker)

# A code-built character-select overlay over the roster in data/characters2.0.
func _build_character_picker() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 520)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.12, 0.98)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Choose your character"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(520, 400)
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for ch in Data.all_characters2():
		if ch is CharacterData:
			list.add_child(_character_row(ch, root))

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): root.queue_free())
	vbox.add_child(cancel)
	return root

func _character_row(ch: CharacterData, root: Control) -> Control:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 56)
	var desc: String = ch.description if ch.description != "" else ""
	btn.text = "%s   —   Health %d   Bash %d  Dash %d  Transmute %d  Scramble %d  Bombs %d  Keys %d\n%s" % [
		ch.display_name, ch.base_max_hp, ch.start_bash, ch.start_dash,
		ch.start_transmute, ch.start_scramble, ch.start_bombs, ch.start_keys, desc]
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cid: StringName = ch.id
	btn.pressed.connect(func(): _begin_run(cid))
	return btn

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

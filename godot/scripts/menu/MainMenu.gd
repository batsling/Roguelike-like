extends Control

# Main menu — the project's startup scene. Owns the new-run flow
# (CharacterSelectModal -> ChooseYourStartModal -> change_scene into the
# Run scene) plus the Continue list backed by SaveSystem.list_named().
#
# Collection opens the real compendium (Collection.gd). The remaining
# system-less buttons (Run History, Settings, How to Play) raise a simple
# "Coming Soon" stub modal so the layout is feature-complete vs. the HTML
# build without committing to half-built systems.

const CHARACTER_SELECT_SCENE := preload("res://scenes/menu/CharacterSelectModal.tscn")
const CHOOSE_START_SCENE := preload("res://scenes/menu/ChooseYourStartModal.tscn")
const RUN_SCENE_PATH := "res://scenes/Main.tscn"

@onready var _continue_btn: Button = %ContinueBtn
@onready var _save_list_container: VBoxContainer = %SaveList
@onready var _modal_layer: Control = %ModalLayer

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _save_list_visible: bool = false

func _ready() -> void:
	_rng.randomize()
	GameState.phase = GameState.Phase.MENU

	%StartRunBtn.pressed.connect(_on_start_run)
	%ContinueBtn.pressed.connect(_on_continue_toggle)
	%RunHistoryBtn.pressed.connect(_on_run_history)
	%CollectionBtn.pressed.connect(_on_collection)
	%SettingsBtn.pressed.connect(_on_settings)
	%HowToPlayBtn.pressed.connect(_on_how_to_play)
	%ClearDataBtn.pressed.connect(_on_clear_data)

	_refresh_continue_button()
	_save_list_container.visible = false

func _refresh_continue_button() -> void:
	var saves: Array = SaveSystem.list_named()
	_continue_btn.disabled = saves.is_empty()
	if saves.is_empty():
		_continue_btn.text = "Continue (no saves)"
	else:
		_continue_btn.text = "Continue (%d)" % saves.size()

# ---------------------------------------------------------------------------
# Start Run flow
# ---------------------------------------------------------------------------

func _on_start_run() -> void:
	var modal: Node = CHARACTER_SELECT_SCENE.instantiate()
	modal.confirmed.connect(_on_character_confirmed)
	modal.cancelled.connect(func(): modal.queue_free())
	_modal_layer.add_child(modal)

func _on_character_confirmed(character_id: StringName, save_name: String) -> void:
	# Free the character-select modal first; we replace it with the
	# choose-your-start panel.
	for c in _modal_layer.get_children():
		c.queue_free()

	# Overwrite confirmation handled inside the character modal already,
	# so by the time we land here the player has committed.
	var pick: Dictionary = RunGraph.pick_amulet_and_starts(_rng)
	if pick.is_empty():
		_show_coming_soon("Run setup failed", "Could not find a valid start/amulet pair in the current game graph.")
		return

	var modal: Node = CHOOSE_START_SCENE.instantiate()
	modal.setup(pick.amulet_id, pick.options, save_name, character_id)
	modal.chose_start.connect(_on_start_chosen)
	modal.cancelled.connect(_on_start_cancelled)
	_modal_layer.add_child(modal)

func _on_start_cancelled() -> void:
	for c in _modal_layer.get_children():
		c.queue_free()

func _on_start_chosen(start_id: StringName, amulet_id: StringName, start_type: int,
		save_name: String, character_id: StringName) -> void:
	for c in _modal_layer.get_children():
		c.queue_free()
	_begin_run(start_id, amulet_id, start_type, save_name, character_id)

func _begin_run(start_id: StringName, amulet_id: StringName, start_type: int,
		save_name: String, character_id: StringName) -> void:
	var char_data: CharacterData = Data.get_character(character_id)
	if char_data == null:
		push_error("[MainMenu] character missing: %s" % character_id)
		return

	GameState.reset_run()
	GameState.apply_character(char_data)
	GameState.save_name = save_name
	GameState.start_game_id = start_id
	GameState.amulet_game_id = amulet_id
	GameState.set_current_game(start_id)
	# Cache the start type on the global state so the run scene can apply
	# the per-type starting bonus on its first frame.
	GameState.set_meta("pending_start_bonus", int(start_type))

	GameLog.add("---- New run: %s ----" % char_data.display_name, Color(0.7, 0.9, 1.0))
	var start_g := Data.get_game(start_id)
	var amulet_g := Data.get_game(amulet_id)
	if start_g != null and amulet_g != null:
		GameLog.add("Journey: %s -> %s" % [start_g.display_name, amulet_g.display_name],
			Color(0.8, 0.9, 1.0))

	# First save lives on disk so a quit-immediately doesn't lose the run.
	SaveSystem.save_named(save_name)
	get_tree().change_scene_to_file(RUN_SCENE_PATH)

# ---------------------------------------------------------------------------
# Continue list
# ---------------------------------------------------------------------------

func _on_continue_toggle() -> void:
	_save_list_visible = not _save_list_visible
	_save_list_container.visible = _save_list_visible
	if _save_list_visible:
		_populate_save_list()

func _populate_save_list() -> void:
	for c in _save_list_container.get_children():
		c.queue_free()
	var saves: Array = SaveSystem.list_named()
	if saves.is_empty():
		var lbl := Label.new()
		lbl.text = "  (no saves yet)"
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_save_list_container.add_child(lbl)
		return
	for s in saves:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var load_btn := Button.new()
		var game_id: String = s.get("current_game", "")
		var game_name := game_id
		var gd: GameData = Data.get_game(StringName(game_id))
		if gd != null:
			game_name = gd.display_name
		load_btn.text = "  %s  —  %s  •  HP %d/%d  •  Gold %d  •  %d games" % [
			s["name"], game_name, s["hp"], s["max_hp"], s["gold"], s["games_beaten"]
		]
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var name_copy: String = s["name"]
		load_btn.pressed.connect(func(): _on_load_save(name_copy))
		row.add_child(load_btn)
		var del_btn := Button.new()
		del_btn.text = "🗑"
		del_btn.pressed.connect(func(): _on_delete_save(name_copy))
		row.add_child(del_btn)
		_save_list_container.add_child(row)

func _on_load_save(save_name: String) -> void:
	if not SaveSystem.load_named(save_name):
		_show_coming_soon("Load failed", "Could not load save: %s" % save_name)
		return
	get_tree().change_scene_to_file(RUN_SCENE_PATH)

func _on_delete_save(save_name: String) -> void:
	SaveSystem.delete_named(save_name)
	_refresh_continue_button()
	_populate_save_list()

# ---------------------------------------------------------------------------
# Stub buttons — backing systems land later.
# ---------------------------------------------------------------------------

func _on_run_history() -> void:
	_show_coming_soon("Run History", "Run history will live here once we track finished runs in Godot.")

func _on_collection() -> void:
	Collection.open(_modal_layer)

func _on_settings() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -210
	panel.offset_right = 300
	panel.offset_bottom = 210
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var heading := Label.new()
	heading.text = "Games used in path selection"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(heading)

	# Count how many games each filter would allow, shown inline so the player
	# can see how restrictive each choice is.
	var total: int = 0
	var owned_n: int = 0
	var downloaded_n: int = 0
	for g in Data.all_games():
		if not (g is GameData):
			continue
		total += 1
		if g.owned:
			owned_n += 1
		if g.file_location.strip_edges() != "":
			downloaded_n += 1

	var opt := OptionButton.new()
	opt.add_item("Any game (%d)" % total, Settings.GameFilter.ALL)
	opt.add_item("Any owned game (%d)" % owned_n, Settings.GameFilter.OWNED)
	opt.add_item("Downloaded only (%d)" % downloaded_n, Settings.GameFilter.DOWNLOADED)
	opt.select(opt.get_item_index(Settings.game_filter))
	vbox.add_child(opt)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 70)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(hint)

	var refresh_hint := func() -> void:
		match opt.get_selected_id():
			Settings.GameFilter.OWNED:
				hint.text = "Paths will only use games you own. A smaller pool means shorter, sparser paths."
			Settings.GameFilter.DOWNLOADED:
				hint.text = "Paths will only use games you've set a file location for, so every game on the path is launchable from the reward screen."
			_:
				hint.text = "Paths can use any game in the catalog."
	refresh_hint.call()

	opt.item_selected.connect(func(idx: int) -> void:
		Settings.set_game_filter(opt.get_item_id(idx))
		refresh_hint.call())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func() -> void: overlay.queue_free())
	vbox.add_child(close_btn)

	_modal_layer.add_child(overlay)

func _on_how_to_play() -> void:
	_show_coming_soon("How to Play", "The interactive tutorial walks through movement, portals, combat, and verification. Coming soon.")

func _on_clear_data() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Delete ALL saves? This cannot be undone."
	confirm.confirmed.connect(func():
		SaveSystem.clear_all_saves()
		_refresh_continue_button()
		_save_list_container.visible = false
		_save_list_visible = false
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

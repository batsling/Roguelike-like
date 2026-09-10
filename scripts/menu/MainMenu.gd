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

# How far the corner controls sit in from the edge of the screen.
const CORNER_MARGIN := 16.0

@onready var _continue_btn: Button = %ContinueBtn
@onready var _save_list_container: VBoxContainer = %SaveList
@onready var _modal_layer: Control = %ModalLayer

func _ready() -> void:
	GameState.phase = GameState.Phase.MENU
	theme = UITheme.shared()
	_style_menu()

	%StartRunBtn.pressed.connect(_on_start_run)
	%CustomRunBtn.pressed.connect(_on_custom_run)
	%ContinueBtn.pressed.connect(_on_continue_toggle)
	%RunHistoryBtn.pressed.connect(_on_run_history)
	%CollectionBtn.pressed.connect(_on_collection)
	%TierListBtn.pressed.connect(_on_tier_list)
	%SettingsBtn.pressed.connect(_on_settings)
	%HowToPlayBtn.pressed.connect(_on_how_to_play)
	%QuitBtn.pressed.connect(quit_game)

	_save_list_container.visible = false
	_build_profile_row()
	# A switch replaces every save on disk, so the Continue list has to be asked
	# again — it is showing the previous player's runs until it is.
	Profiles.profile_switched.connect(_on_profile_switched)
	Profiles.profile_wiped.connect(_on_profile_switched)
	_refresh_continue_button()
	_move_quit_to_corner()

# ---------------------------------------------------------------------------
# Menu styling
# ---------------------------------------------------------------------------

# FAILS LOUDLY NOW. Every lookup here used to be `get_node_or_null` down a
# hardcoded path (`Center/Panel/TitleBox/Title` and three more) guarded by an
# `is` check, so renaming or moving a node in the editor did not break the
# menu — it silently stopped styling it, and the screen came up in the raw
# `.tscn` colours with nothing said. `StartRunBtn` was the tell: it already had
# a unique name and was already reached as `%StartRunBtn` eleven lines above,
# while this function walked a four-deep path to the same node.
#
# `%Name` is the fix the layout review called the smaller of the two (see
# `docs/layout-review-backlog.md` §6): it does not depend on where the node sits,
# so moving one in the editor is free, and a node that is genuinely GONE raises
# instead of shrugging. `Background`, `Title` and `Subtitle` were given
# `unique_name_in_owner` in the scene to match the nine nodes that already had it.
#
# The bigger half of §6 is still open: these colours are also authored in the
# `.tscn`, so the editor preview shows colours no player ever sees.
func _style_menu() -> void:
	(%Background as ColorRect).color = UITheme.BG_DEEP
	# The name in gold, the old title under it as a subtitle in the dim text
	# colour — one is what the game is called, the other is what it is about, and
	# they were the same 36px line until now.
	(%Title as Label).add_theme_color_override("font_color", UITheme.GOLD)
	(%Subtitle as Label).add_theme_color_override("font_color", UITheme.TEXT_DIM)
	# Make the primary action stand out.
	var start := %StartRunBtn as Button
	start.add_theme_stylebox_override("normal", UITheme.accent_box(UITheme.ACCENT, UITheme.PANEL_HI, 8))
	start.add_theme_color_override("font_color", UITheme.GOLD)
	start.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)

# ---------------------------------------------------------------------------
# Profiles — who is playing
# ---------------------------------------------------------------------------

# A row under the title saying whose game this is, with the way to change it.
# Built in code and inserted into the menu's own column, so it sits with the
# title rather than among the actions — switching player is not a thing you do
# in the middle of choosing a run.
var _profile_lbl: Label = null

func _build_profile_row() -> void:
	var panel := get_node_or_null("Center/Panel")
	if panel == null:
		return
	var row := HBoxContainer.new()
	row.name = "ProfileRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)

	_profile_lbl = Label.new()
	_profile_lbl.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	_profile_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(_profile_lbl)

	var switch_btn := Button.new()
	switch_btn.name = "ProfileBtn"
	switch_btn.text = "Switch"
	switch_btn.custom_minimum_size = Vector2(96, 30)
	switch_btn.pressed.connect(_on_profiles)
	row.add_child(switch_btn)

	panel.add_child(row)
	var title := panel.get_node_or_null("TitleBox")
	panel.move_child(row, (title.get_index() + 1) if title != null else 0)
	_refresh_profile_row()

# Exit Game lives in the bottom-right corner rather than at the foot of the
# button column. It is the one entry that isn't a way INTO the game, and sitting
# last in the same stack made it the neighbour of Settings — a column you scan
# downwards ending in the door out. Anchored, so it stays in the corner at any
# window size instead of moving with the column.
#
# It is mounted UNDER `%ModalLayer`, and that is the important part. The corner
# used to be appended last, which put it above every screen the menu raises — so
# the door out of the application sat on top of the character picker, the
# Collection and the Atlas, live and clickable through their own backdrops. It is
# a MAIN MENU button; anything standing in front of the main menu covers it.
func _move_quit_to_corner() -> void:
	var quit_btn: Button = get_node_or_null("%QuitBtn")
	if quit_btn == null:
		return
	var old_parent: Node = quit_btn.get_parent()
	if old_parent != null:
		old_parent.remove_child(quit_btn)
	var corner := Control.new()
	corner.name = "QuitCorner"
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -CORNER_MARGIN
	corner.offset_bottom = -CORNER_MARGIN
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(corner)
	if _modal_layer != null and is_instance_valid(_modal_layer) \
			and _modal_layer.get_parent() == self:
		move_child(corner, _modal_layer.get_index())

	quit_btn.custom_minimum_size = Vector2(150, 36)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	quit_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quit_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quit_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.add_child(quit_btn)

func _refresh_profile_row() -> void:
	if _profile_lbl != null:
		_profile_lbl.text = "👤  %s" % Profiles.active_name()

func _on_profiles() -> void:
	ProfilePicker.open(_modal_layer)

func _on_profile_switched() -> void:
	_refresh_profile_row()
	_save_list_container.visible = false
	_refresh_continue_button()

# ---------------------------------------------------------------------------
# Start Run flow — pick a 2.0 character, then enter Overworld2
# ---------------------------------------------------------------------------

func _on_start_run() -> void:
	# An ordinary run is an ordinary map: whatever the last custom run configured
	# goes with it, and RunGraph falls back to Settings.game_filter. Done here
	# rather than in _begin_run, which the custom flow also goes through.
	RunConfig.reset()
	_open_character_picker()

# The custom flow is the same flow with a screen in front of it: pick what the run
# is made of, then pick who plays it. RunConfig is applied before the picker opens
# rather than after Confirm, so the character screen — and anything it asks the
# graph — is already looking at the map the run will actually use.
func _on_custom_run() -> void:
	for c in _modal_layer.get_children():
		c.queue_free()
	var screen := CustomRunScreen.open(self)
	screen.begun.connect(func(config: Dictionary):
		RunConfig.apply(config)
		_open_character_picker())

# The picker is its own screen (CharacterPicker), mounted on %ModalLayer like
# every other screen the menu raises. It only says which hero was picked; what
# that means — cancelling a pending resume, parking the choice, swapping scene —
# stays here, in _begin_run.
func _open_character_picker() -> void:
	for c in _modal_layer.get_children():
		c.queue_free()
	var picker := CharacterPicker.open(_modal_layer)
	picker.chosen.connect(_begin_run)

func _begin_run(character_id: StringName) -> void:
	# Overworld2 boots the run itself (rolls the graph, applies the 2.0 loadout);
	# it reads the chosen character from this pending meta on _ready. A save loaded
	# and then backed out of must not hijack this boot.
	SaveSystem.cancel_pending_resume()
	GameState.set_meta("pending_character2", character_id)
	get_tree().change_scene_to_file(OVERWORLD2_SCENE)

# ---------------------------------------------------------------------------
# Continue list — the saved runs, resumable from here
# ---------------------------------------------------------------------------
#
# A row per resumable save: the run's own autosave first (the overworld rewrites
# it every time the run moves), then every named save, newest first. Resuming is
# a two-step handshake: SaveSystem applies the run to GameState / GameLoop2 and
# parks the overworld's view state, then we swap to Overworld2, whose _ready
# claims that view instead of booting a fresh run.

func _refresh_continue_button() -> void:
	var count: int = SaveSystem.list_resumable().size()
	_continue_btn.disabled = count == 0
	_continue_btn.text = "Continue" if count > 0 else "Continue (no saved runs)"

func _on_continue_toggle() -> void:
	_save_list_container.visible = not _save_list_container.visible
	if _save_list_container.visible:
		_populate_save_list()

func _populate_save_list() -> void:
	for c in _save_list_container.get_children():
		_save_list_container.remove_child(c)
		c.queue_free()
	var saves: Array = SaveSystem.list_resumable()
	if saves.is_empty():
		var none := Label.new()
		none.text = "No saved runs yet — the overworld's 💾 Save button makes one."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		none.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_save_list_container.add_child(none)
		_refresh_continue_button()
		return
	for entry in saves:
		_save_list_container.add_child(_save_row(entry))

func _save_row(entry: Dictionary) -> Control:
	var is_auto: bool = bool(entry.get("autosave", false))
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.GOLD.lerp(UITheme.BORDER, 0.6 if is_auto else 0.85), 8, 8, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(190, 0)
	row.add_child(text)
	var title := Label.new()
	title.text = String(entry.get("name", "")) if String(entry.get("name", "")) != "" else "Unnamed run"
	title.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	title.add_theme_color_override("font_color", UITheme.GOLD if is_auto else UITheme.TEXT)
	text.add_child(title)
	var sub := Label.new()
	sub.text = _save_subtitle(entry)
	sub.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	text.add_child(sub)

	# A CUSTOM RUN says so, on its own line and in its own colour. It is the one
	# fact about a save that changes what resuming it means — an ordinary row and a
	# deckbuilder-only row are the same character on the same game otherwise — and
	# it comes off the save's own stored filters rather than off the live RunConfig,
	# which describes whatever run is loaded now.
	var custom: String = SaveSystem.describe_run_config(entry)
	if custom != "":
		var tag := Label.new()
		tag.text = custom
		tag.tooltip_text = "This run was built on the Custom Run screen — resuming it rebuilds that map."
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tag.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		tag.add_theme_color_override("font_color", UITheme.ACCENT)
		text.add_child(tag)

	var load_btn := Button.new()
	load_btn.text = "Resume"
	load_btn.custom_minimum_size = Vector2(84, 32)
	load_btn.pressed.connect(func(): _resume_save(entry))
	row.add_child(load_btn)

	var del := Button.new()
	del.text = "🗑"
	del.tooltip_text = "Delete this save"
	del.custom_minimum_size = Vector2(36, 32)
	del.pressed.connect(func(): _delete_save(entry))
	row.add_child(del)
	return wrap

# "Zagreus · Hades · 12/20 HP · 4 beaten · 3 minutes ago"
func _save_subtitle(entry: Dictionary) -> String:
	var parts: Array = []
	var ch: CharacterData = Data.get_character2(StringName(entry.get("character_id", "")))
	if ch != null:
		parts.append(ch.display_name)
	var g: GameData = Data.get_game(StringName(entry.get("current_game", "")))
	if g != null:
		parts.append(g.display_name)
	if int(entry.get("max_hp", 0)) > 0:
		parts.append("%d/%d HP" % [int(entry.get("hp", 0)), int(entry.get("max_hp", 0))])
	parts.append("%d beaten" % int(entry.get("games_beaten", 0)))
	var when: int = int(entry.get("saved_at", 0))
	if when > 0:
		parts.append(Time.get_datetime_string_from_unix_time(when, true))
	return " · ".join(parts)

func _resume_save(entry: Dictionary) -> void:
	var loaded: bool = SaveSystem.load_autosave() if bool(entry.get("autosave", false)) \
		else SaveSystem.load_named(String(entry.get("name", "")))
	if not loaded:
		_show_coming_soon("Couldn't load", "That save couldn't be read — it may have been deleted or corrupted.")
		_populate_save_list()
		return
	get_tree().change_scene_to_file(OVERWORLD2_SCENE)

func _delete_save(entry: Dictionary) -> void:
	if bool(entry.get("autosave", false)):
		SaveSystem.clear_autosave()
	else:
		SaveSystem.delete_named(String(entry.get("name", "")))
	_populate_save_list()
	_refresh_continue_button()

# ---------------------------------------------------------------------------
# Stub buttons — backing systems land later.
# ---------------------------------------------------------------------------

# Run History sits ON TOP of the Atlas: the strip lists each route in order and
# the sky behind it is where that route went, so one screen answers both.
func _on_run_history() -> void:
	var atlas: AtlasView = null
	if AtlasView.load_layout() != null:
		atlas = AtlasView.open(_modal_layer)
	var history := RunHistoryScreen.open(_modal_layer, atlas)
	if atlas != null:
		# Closing the history closes the map it was laid over.
		history.finished.connect(func():
			if is_instance_valid(atlas):
				atlas._finish())

func _on_collection() -> void:
	Collection.open(_modal_layer)

# THERE IS NO ATLAS BUTTON HERE ANY MORE. The star chart is still in the game and
# still opened from two places that need it — the Collection's own Games tab, and
# Run History, which lays its routes over the sky (_on_run_history above). A third
# door onto the same screen, sitting in the menu column beside the Collection that
# already contains it, was one more row of buttons for no more game.

func _on_tier_list() -> void:
	TierListScreen.open(_modal_layer)

func _on_settings() -> void:
	SettingsModal.open(_modal_layer)

# ---------------------------------------------------------------------------
# How to Play — the manual, and its contents panel in the corner
# ---------------------------------------------------------------------------

# The bottom-left corner of the menu is a BUTTON that opens the manual's table of
# contents: the chapter titles, each opening the manual AT that chapter.
#
# A corner rather than one more entry in the middle column, for two reasons. The
# middle column is the things you DO — start, continue, quit — and a manual is
# not one of them. And a contents list is the part of a manual worth putting in
# front of someone who has not asked for it: a player who does not know they have
# a question about shops will still read the word "shops" and find out that they
# do.
#
# The list starts CLOSED behind that button. Fourteen chapter titles standing
# open in the corner of the title screen is a wall of small text beside the one
# thing the screen is for, and it is a wall the player has read by their second
# run and never again. Behind a button it costs one line until it is wanted.
#
# The list is built from HowToPlayText.chapters(), so it cannot drift out of
# step with the manual — adding a chapter adds its line here. Chapters are
# opened BY ID rather than by index, so inserting one in the middle does not
# quietly repoint every button below it.
func _on_how_to_play() -> void:
	_open_manual(&"start")


# Public-ish seam: one place the manual is opened from, so the corner panel, the
# top button and any future entry point cannot disagree about how it mounts.
func _open_manual(chapter) -> void:
	HowToPlayScreen.open(_modal_layer, chapter)

# Leaving for good. No confirmation here on purpose: nothing is live on the main
# menu, saves are already on disk, and a "are you sure?" between the player and
# the door is a prompt that only ever gets in the way. The in-run exit
# (Overworld2.menu_action) is the one that asks, because there a run is at stake.
# Public so a test can press it without a click.
func quit_game() -> void:
	get_tree().quit()

func _show_coming_soon(title: String, body: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.dialog_text = body
	_modal_layer.add_child(dlg)
	dlg.popup_centered(Vector2i(480, 220))
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())

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

# The menu's text size: the theme's 14 a quarter larger (see _style_menu).
const MENU_FONT := UITheme.FONT_HEAD

@onready var _continue_btn: Button = %ContinueBtn
@onready var _save_list_container: VBoxContainer = %SaveList
@onready var _modal_layer: Control = %ModalLayer

func _ready() -> void:
	GameState.phase = GameState.Phase.MENU
	theme = UITheme.shared()
	_style_menu()
	_paint_vortex()
	_mount_falling_art()
	_build_title()
	_mount_portal()

	%StartRunBtn.pressed.connect(_on_start_run)
	%CustomRunBtn.pressed.connect(_on_custom_run)
	%ContinueBtn.pressed.connect(_on_continue_toggle)
	%RunHistoryBtn.pressed.connect(_on_run_history)
	%CollectionBtn.pressed.connect(_on_collection)
	%TierListBtn.pressed.connect(_on_tier_list)
	%SettingsBtn.pressed.connect(_on_settings)
	%HowToPlayBtn.pressed.connect(_on_how_to_play)
	%QuitBtn.pressed.connect(quit_game)

	_wrap_save_list()
	_show_save_list(false)
	_build_profile_row()
	# A switch replaces every save on disk, so the Continue list has to be asked
	# again — it is showing the previous player's runs until it is.
	Profiles.profile_switched.connect(_on_profile_switched)
	Profiles.profile_wiped.connect(_on_profile_switched)
	_move_quit_to_corner()
	_refresh_continue_button()
	_rearrange_on_visibility()
	_build_radio_corner()
	# The pop-over goes over both corners: nothing on the menu under it is live.
	move_child(_save_overlay, _modal_layer.get_index() - 1)

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
# The background, the title (gold) and the subtitle (dim text) are NOT set here.
# They are authored in MainMenu.tscn at their real UITheme values, so the one
# scene built in the editor previews the way it plays; this used to overwrite all
# three at _ready, and the editor showed colours no player ever saw.
# test_main_menu pins the scene's three colours to UITheme so a theme change
# cannot leave the scene behind.
func _style_menu() -> void:
	# THE MENU IS DRAWN A QUARTER LARGER THAN THE REST OF THE UI. It is the one
	# screen with nothing on it but a column of choices, and at the theme's own
	# 14px on a 1280 canvas it read as a small island in a lot of dark. The scene
	# carries the 1.25x sizes; the fonts go up a step here (14 -> 18), since a
	# button's text size is the theme's until something overrides it.
	for btn in [%HowToPlayBtn, %CustomRunBtn, %ContinueBtn, %RunHistoryBtn,
			%CollectionBtn, %TierListBtn, %SettingsBtn, %QuitBtn]:
		(btn as Button).add_theme_font_size_override("font_size", MENU_FONT)
	# Make the primary action stand out — a stylebox, which a scene cannot share
	# with the theme the way it can a colour.
	var start := %StartRunBtn as Button
	start.add_theme_stylebox_override("normal", UITheme.accent_box(UITheme.ACCENT, UITheme.PANEL_HI, 8))
	start.add_theme_color_override("font_color", UITheme.GOLD)
	start.add_theme_font_size_override("font_size", UITheme.FONT_DISPLAY)

# The game's own art falling past, down both sides of the button column. Mounted
# as the FIRST child so it draws under everything else in the scene — the
# background node it sits with is a flat colour, and this goes over that and
# under the title, the buttons and the save list.
#
# It deliberately keeps running while the modals are up: `%ModalLayer` is a
# sibling above this, so the character picker and the settings panel dim it
# rather than stop it, and the menu behind them still looks alive.
var _art: MenuFallingArt = null

func _mount_falling_art() -> void:
	var art := MenuFallingArt.mount(self)
	# Directly above the Background ColorRect, below Center and %ModalLayer.
	move_child(art, 1)
	# Dimmed behind the buttons; flying into the portal once it is up (_mount_portal).
	art.dim_node = %StartRunBtn.get_parent()
	_art = art

# The vortex behind everything: the red rift across the screen and the blue
# portal the title stands in, one swirl (shaders/menu_vortex.gdshader), on
# %Background, which keeps its colour (what the editor previews, and what shows
# if the shader cannot load). MenuPortal tells it where the portal is.
const VORTEX_SHADER := preload("res://shaders/menu_vortex.gdshader")
const RIFT_RED := Color(1.0, 0.36, 0.30)
const RIFT_RED_DEEP := Color(0.36, 0.03, 0.06)
const RIFT_RED_BASE := Color(0.06, 0.02, 0.02)

func _paint_vortex() -> void:
	var bg := %Background as ColorRect
	var mat := ShaderMaterial.new()
	mat.shader = VORTEX_SHADER
	mat.set_shader_parameter("rift_color", RIFT_RED)
	mat.set_shader_parameter("deep_color", RIFT_RED_DEEP)
	mat.set_shader_parameter("base_color", RIFT_RED_BASE)
	bg.material = mat
	var fit := func() -> void: mat.set_shader_parameter("size", bg.size)
	bg.resized.connect(fit)
	fit.call()

# Where the blue portal is, and its fringe of bats (MenuPortal). UNDER the art,
# which flies into it (MenuFallingArt.sink) and is seen shrinking away over the
# blue; under the letters, which stand on it.
const MenuPortal := preload("res://scripts/menu/MenuPortal.gd")
var portal: Control = null

func _mount_portal() -> void:
	portal = MenuPortal.mount(self, func() -> Array: return [title_row, subtitle_row])
	portal.art = _art
	portal.vortex = (%Background as ColorRect).material
	move_child(portal, _art.get_index())

# The title and subtitle, spelled in letters cut from roguelike logos and drawn
# again every launch (TitleLetters). The scene's two Labels stay as the editor
# preview and the fallback: hidden only once a row has actually been built.
# Clicking either row draws that row again (_reroll), so the player can shuffle
# through the logos without restarting the game.
const TITLE_HEIGHT := 84.0
const SUBTITLE_HEIGHT := 36.0
const TITLE_MAX_WIDTH := 1100.0
# The subtitle's word gap, of its line height: wider than TitleLetters.SPACE,
# since at 36px a mixed-logo subtitle's words otherwise run together.
const SUBTITLE_SPACE := 0.6
# ...and its gap between letters, likewise: at 36px TitleLetters.GAP is about two
# pixels, and a mixed subtitle's glows and outlines ran into each other.
const SUBTITLE_GAP := 0.16

var title_row: TitleLetters = null
var subtitle_row: TitleLetters = null
var _title_rng := RandomNumberGenerator.new()

func _build_title(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	_title_rng = rng
	_reroll(true)
	_reroll(false)

# Draw the title (or the subtitle) again in place of the one showing.
func _reroll(title: bool) -> void:
	var old: TitleLetters = title_row if title else subtitle_row
	var row := _title_row(%Title if title else %Subtitle,
			TITLE_HEIGHT if title else SUBTITLE_HEIGHT, _title_rng, title)
	if old != null:
		if row == null:
			return
		old.queue_free()
	if title:
		title_row = row
	else:
		subtitle_row = row

# `decorated` is true for the title. Both rows take decorations, each from its
# own (TitleLetters.pick_decor): the crab's legs are the subtitle's.
func _title_row(label: Label, height: float, rng: RandomNumberGenerator, decorated: bool) -> TitleLetters:
	var row := TitleLetters.make(label.text, height, rng, true, TITLE_MAX_WIDTH,
			TitleLetters.SPACE if decorated else SUBTITLE_SPACE,
			TitleLetters.GAP if decorated else SUBTITLE_GAP, not decorated)
	if row.placed.is_empty():
		row.free()
		return null
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The row itself asks for no width (TitleLetters), so it is the letters that
	# take the click.
	row.ink.mouse_filter = Control.MOUSE_FILTER_STOP
	row.ink.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.ink.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_reroll(decorated))
	label.add_sibling(row)
	label.visible = false
	return row

# ---------------------------------------------------------------------------
# Profiles — who is playing
# ---------------------------------------------------------------------------

# Whose game this is, with the way to change it, in the top-left corner: the
# scene's TopControls, which already holds How to Play. Out of the middle of the
# screen since the title moved to its centre — switching player is not a thing
# you do in the middle of choosing a run.
var _profile_lbl: Label = null

func _build_profile_row() -> void:
	var row: HBoxContainer = get_node_or_null("TopControls")
	if row == null:
		return
	row.add_theme_constant_override("separation", UITheme.GAP_LOOSE)

	_profile_lbl = Label.new()
	_profile_lbl.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	_profile_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(_profile_lbl)

	var switch_btn := Button.new()
	switch_btn.name = "ProfileBtn"
	switch_btn.text = "Switch"
	switch_btn.custom_minimum_size = Vector2(120, 38)
	switch_btn.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	switch_btn.pressed.connect(_on_profiles)
	row.add_child(switch_btn)

	var how: Button = %HowToPlayBtn
	how.custom_minimum_size = Vector2(0, 38)
	how.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	row.move_child(how, -1)
	_refresh_profile_row()

# THE BUTTONS UNDER THE TITLE: Start Run across the top, the rest two to a row
# beneath it. The title stands in the middle of the screen now, which leaves
# about 270px below it on the 720 canvas, and the old single column of seven
# needed 400. The scene keeps every button in %Buttons in its old order; this
# deals the visible ones after Start Run into rows of two (HBoxes named Row0…),
# and is run again whenever Continue comes or goes, so an odd one out is centred
# on a row of its own rather than leaving a hole.
const GRID_W := 196.0
const GRID_H := 48.0

var _arrange_pending := false
# Set while the rows are being dealt: moving a button between parents can raise
# its own visibility_changed, which must not ask for another deal.
var _arranging := false

# Showing or hiding any of the buttons re-deals the rows at the end of the frame,
# whoever did it — Continue is the one that comes and goes.
func _rearrange_on_visibility() -> void:
	for b in _grid_order:
		b.visibility_changed.connect(func() -> void:
			if not _arrange_pending and not _arranging:
				_arrange_pending = true
				_arrange_buttons.call_deferred())

func _arrange_buttons() -> void:
	_arrange_pending = false
	_arranging = true
	_deal_rows()
	_arranging = false

# The buttons in the scene's order, taken the first time the rows are dealt, so
# Continue always comes back in its own place rather than at the end.
var _grid_order: Array[Button] = []

func _deal_rows() -> void:
	var box: VBoxContainer = %StartRunBtn.get_parent()
	if _grid_order.is_empty():
		for c in box.get_children():
			if c is Button and c != %StartRunBtn:
				_grid_order.append(c)
	var deal: Array[Button] = _grid_order
	for b in deal:
		b.reparent(box, false)
	for c in box.get_children():
		if c is HBoxContainer and String(c.name).begins_with("Row"):
			box.remove_child(c)
			c.queue_free()
	var shown := deal.filter(func(b: Button) -> bool: return b.visible)
	var at := %StartRunBtn.get_index() + 1
	for i in range(0, shown.size(), 2):
		var row := HBoxContainer.new()
		row.name = "Row%d" % (i / 2)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", UITheme.GAP)
		box.add_child(row)
		box.move_child(row, at)
		at += 1
		for b in shown.slice(i, i + 2):
			b.reparent(row, false)
			b.custom_minimum_size = Vector2(GRID_W, GRID_H)
	# Hidden ones stay in the box, out of the rows, until they are shown.
	for b in deal:
		if not b.visible:
			box.move_child(b, -1)

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

	quit_btn.custom_minimum_size = Vector2(188, 45)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	quit_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quit_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quit_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.add_child(quit_btn)

# ROGUELIKE RADIO (docs/roguelike-radio.md) in the top-right corner — the music
# plays from the moment the game opens, so its controls are on the first screen
# too. A corner rather than the button column for the reason Exit is: it is not a
# way into the game.
func _build_radio_corner() -> void:
	var corner := Control.new()
	corner.name = "RadioCorner"
	corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -CORNER_MARGIN
	corner.offset_top = CORNER_MARGIN
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(corner)
	if _modal_layer != null and is_instance_valid(_modal_layer) \
			and _modal_layer.get_parent() == self:
		move_child(corner, _modal_layer.get_index())
	# The 📻 alone — and beside it, while a song is loaded, its game's cover and
	# back / pause / skip (RadioMiniPlayer).
	var player := RadioMiniPlayer.make(func() -> void: RadioScreen.open(_modal_layer),
		45.0, MENU_FONT)
	player.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	player.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	player.alignment = BoxContainer.ALIGNMENT_END
	corner.add_child(player)
	_radio_player = player

var _radio_player: RadioMiniPlayer = null

func _refresh_profile_row() -> void:
	if _profile_lbl != null:
		_profile_lbl.text = "👤  %s" % Profiles.active_name()

func _on_profiles() -> void:
	ProfilePicker.open(_modal_layer)

func _on_profile_switched() -> void:
	_refresh_profile_row()
	_show_save_list(false)
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
	# GONE rather than greyed when there is nothing to continue. It used to stand
	# disabled as "Continue (no saved runs)" — a full row of the menu saying
	# nothing — and a first launch, which has no saves by definition, opened on it.
	_continue_btn.visible = count > 0
	_continue_btn.disabled = count == 0
	_continue_btn.text = "Continue"
	if count == 0:
		_show_save_list(false)
	_arrange_buttons()

func _on_continue_toggle() -> void:
	_show_save_list(not _save_list_container.visible)
	if _save_list_container.visible:
		_populate_save_list()

# THE SAVE LIST IS A POP-OVER. It used to open in the middle of the button
# column; with the buttons in a grid under a centred title there is no column to
# open it in, so Continue raises it over the menu instead: a panel in the middle
# of the screen on a dim backdrop, which a click outside it (or Continue again)
# closes. The scene keeps `%SaveList` among the buttons; this moves it into a
# ScrollContainer in that panel, and `_fit_save_list` gives the scroll only the
# height the screen has left once the panel's own furniture is counted.
var _save_scroll: ScrollContainer = null
var _save_overlay: Control = null
var _save_panel: PanelContainer = null

func _wrap_save_list() -> void:
	_save_overlay = Control.new()
	_save_overlay.name = "SaveOverlay"
	_save_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_save_overlay)
	# Over the menu, under %ModalLayer: a screen raised from a row (a resume
	# asking to confirm) still comes up in front of the list.
	move_child(_save_overlay, _modal_layer.get_index())
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_show_save_list(false))
	_save_overlay.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_overlay.add_child(centre)
	_save_panel = PanelContainer.new()
	_save_panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG, UITheme.GOLD.lerp(UITheme.BORDER, 0.6), 10, 14, 1))
	centre.add_child(_save_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP)
	_save_panel.add_child(col)
	var head := Label.new()
	head.text = "Continue a run"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", MENU_FONT)
	head.add_theme_color_override("font_color", UITheme.GOLD)
	col.add_child(head)
	_save_scroll = ScrollContainer.new()
	_save_scroll.name = "SaveScroll"
	_save_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_save_scroll.custom_minimum_size.x = 400
	col.add_child(_save_scroll)
	_save_list_container.reparent(_save_scroll, false)
	_save_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

# `%SaveList.visible` stays the one flag (the tests and every caller read it); the
# pop-over around it follows.
func _show_save_list(on: bool) -> void:
	_save_list_container.visible = on
	if _save_overlay != null:
		_save_overlay.visible = on
		if on:
			_fit_save_list.call_deferred()

func _fit_save_list() -> void:
	if _save_scroll == null or not _save_overlay.visible:
		return
	_save_scroll.custom_minimum_size.y = 0
	var rest: float = _save_panel.get_combined_minimum_size().y
	var room: float = get_viewport_rect().size.y - rest - 2 * UITheme.GAP_SECTION
	var want: float = _save_list_container.get_combined_minimum_size().y
	_save_scroll.custom_minimum_size.y = clampf(want, 0.0, maxf(room, 90.0))

func _populate_save_list() -> void:
	for c in _save_list_container.get_children():
		_save_list_container.remove_child(c)
		c.queue_free()
	var saves: Array = SaveSystem.list_resumable()
	if saves.is_empty():
		var none := Label.new()
		none.text = "No saved runs yet — the overworld's 💾 Save button makes one."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
		none.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_save_list_container.add_child(none)
		_refresh_continue_button()
		return
	for entry in saves:
		_save_list_container.add_child(_save_row(entry))
	_fit_save_list.call_deferred()

func _save_row(entry: Dictionary) -> Control:
	var is_auto: bool = bool(entry.get("autosave", false))
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.GOLD.lerp(UITheme.BORDER, 0.6 if is_auto else 0.85), 8, 8, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP)
	wrap.add_child(row)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", UITheme.GAP_NONE)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(238, 0)
	row.add_child(text)
	var title := Label.new()
	title.text = String(entry.get("name", "")) if String(entry.get("name", "")) != "" else "Unnamed run"
	title.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	title.add_theme_color_override("font_color", UITheme.GOLD if is_auto else UITheme.TEXT)
	text.add_child(title)
	var sub := Label.new()
	sub.text = _save_subtitle(entry)
	sub.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
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
		tag.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		tag.add_theme_color_override("font_color", UITheme.ACCENT)
		text.add_child(tag)

	var load_btn := Button.new()
	load_btn.text = "Resume"
	load_btn.custom_minimum_size = Vector2(105, 40)
	load_btn.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	load_btn.pressed.connect(func(): _resume_save(entry))
	row.add_child(load_btn)

	var del := Button.new()
	del.text = "🗑"
	del.tooltip_text = "Delete this save"
	del.custom_minimum_size = Vector2(45, 40)
	del.pressed.connect(func(): _delete_save(entry))
	row.add_child(del)
	return wrap

# "Zagreus · Hades · 12/20 HP · 4 beaten · 3 minutes ago"
func _save_subtitle(entry: Dictionary) -> String:
	var parts: Array = []
	var ch: CharacterData = Data.get_character2(StringName(entry.get("character_id", "")))
	if ch != null:
		parts.append(ch.display_name)
	# The level the run is played at (docs/fracture-design.md §6), when it has one.
	if int(entry.get("fracture", 0)) > 0:
		parts.append("Fracture %d" % int(entry.get("fracture", 0)))
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
		# Closing the history closes the map it was laid over. `handed_to_map` is
		# deliberately NOT wired here: that one means the strip stepped aside so the
		# player can read the route on the chart, and closing the chart with it is
		# exactly the bug that made "✦ Show on map" look like a dead button.
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
	dlg.dialog_autowrap = true
	_modal_layer.add_child(dlg)
	dlg.popup_centered(Vector2i(480, 220))
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.close_requested.connect(func(): dlg.queue_free())

extends Control

# Main menu — the project's startup scene. Post games-first cut
# (docs/games-first-redesign.md §11) "Start Run" opens a 2.0 character picker and
# launches the games-first overworld (Overworld2). The old combat run flow
# (CharacterSelect -> ChooseYourStart -> Main.tscn) is gone.
#
# The menu itself is Start Run, Continue (when there is a save), Custom Run,
# Extras and Settings, with the profile, the radio and Exit in three corners.
# Extras is a pop-over holding the screens you look at rather than play: the
# manual, Collection, Run History, Tier List, Achievements, Customization.

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
	# A test profile's letters are all there (Settings -> Profile -> Unlock
	# everything): flipping it with the menu behind the Settings panel draws the
	# title again, so the change shows.
	Settings.unlock_everything_changed.connect(_on_unlock_everything_changed)

	%StartRunBtn.pressed.connect(_on_start_run)
	%CustomRunBtn.pressed.connect(_on_custom_run)
	%ContinueBtn.pressed.connect(_on_continue_toggle)
	%RunHistoryBtn.pressed.connect(_on_run_history)
	%CollectionBtn.pressed.connect(_on_collection)
	%CustomizeBtn.pressed.connect(_on_customize)
	%AchievementsBtn.pressed.connect(_on_achievements)
	%TierListBtn.pressed.connect(_on_tier_list)
	%SettingsBtn.pressed.connect(_on_settings)
	%HowToPlayBtn.pressed.connect(_on_how_to_play)
	%ProfileBtn.pressed.connect(_on_profiles)
	_wire_extras()
	%QuitBtn.pressed.connect(quit_game)

	_wrap_save_list()
	_show_save_list(false)
	_build_profile_row()
	# A switch replaces every save on disk, so the Continue list has to be asked
	# again — it is showing the previous player's runs until it is.
	Profiles.profile_switched.connect(_on_profile_switched)
	Profiles.profile_wiped.connect(_on_profile_switched)
	_move_quit_to_corner()
	_warm_run_page.call_deferred()
	_refresh_continue_button()
	_rearrange_on_visibility()
	_build_radio_corner()
	# The pop-over goes over both corners: nothing on the menu under it is live.
	move_child(_save_overlay, _modal_layer.get_index() - 1)
	_spell_buttons()

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
	for btn in _letter_buttons():
		(btn as Button).add_theme_font_size_override("font_size", MENU_FONT)

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
	# ...and the buttons under it: the main five, or the Extras list in their place.
	portal.holds = func() -> Array: return [_main_buttons, %ExtrasList]
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

func _on_unlock_everything_changed(_on: bool) -> void:
	_reroll(true)
	_reroll(false)
	_spell_buttons()

# ---------------------------------------------------------------------------
# The buttons, spelled like the title
# ---------------------------------------------------------------------------

# EVERY BUTTON ON THE MENU IS SPELLED IN LOGO LETTERS, the way the title is
# (owner, 10 Nov 2026): the same pool (TitleLetters.available — Rogue's own
# letters until a rank has paid others), drawn again every launch, and again
# when the pool changes (Customization closing, Unlock everything).
#
# The Button keeps its `text` — the scene previews it, tests and screen readers
# read it — but draws it transparent, and a TitleLetters row is laid over the
# button in its place. A label the pool cannot spell in full (a profile name
# with a character Rogue's font has not got) keeps its plain text instead.
#
# THERE IS NO BOX. The buttons stand in the portal with the title, straight on
# its blue (the owner, 10 Nov 2026: plates did not look right), and the portal
# reaches round them. The hovered or focused one gets a gold edge and its
# letters at full strength. The two corner buttons (the profile, Exit) are
# outside the portal, over the red, and keep a dark plate so their letters read.
const BUTTON_LETTERS := 24.0     # a letter's height on an ordinary button
const START_LETTERS := 36.0      # ...and on Start Run
const CORNER_PLATE := Color(0, 0, 0, 0.45)
const LETTER_MARGIN := 14.0      # kept clear either side of the word
const LETTERS_REST := Color(0.9, 0.9, 0.9)

var _button_rows: Dictionary = {}    # Button -> its TitleLetters row
var _button_rng := RandomNumberGenerator.new()

# Looked up ONCE, before anything is moved: Exit leaves the scene's tree for its
# corner (_move_quit_to_corner), and a node taken out of its owner no longer
# answers to %QuitBtn.
var _lettered: Array = []

func _letter_buttons() -> Array:
	if _lettered.is_empty():
		_lettered = [%StartRunBtn, %ContinueBtn, %CustomRunBtn, %ExtrasBtn, %SettingsBtn,
			%QuitBtn, %ProfileBtn, %HowToPlayBtn, %CollectionBtn, %RunHistoryBtn,
			%TierListBtn, %AchievementsBtn, %CustomizeBtn, %ExtrasBackBtn]
	return _lettered

func _spell_buttons() -> void:
	_button_rng.randomize()
	for b in _letter_buttons():
		_spell_button(b)

func _spell_button(btn: Button) -> void:
	if not btn.has_meta("lettered"):
		btn.set_meta("lettered", true)
		var plate := CORNER_PLATE if btn.name in [&"ProfileBtn", &"QuitBtn"] else Color(0, 0, 0, 0)
		var rest := UITheme.flat(plate, 8, 6)
		var lit := UITheme.flat(plate, 8, 6, 2, UITheme.GOLD)
		for state in ["normal", "disabled"]:
			btn.add_theme_stylebox_override(state, rest)
		for state in ["hover", "pressed", "focus", "hover_pressed"]:
			btn.add_theme_stylebox_override(state, lit)
		var light := func(on: bool) -> void:
			var r: TitleLetters = _button_rows.get(btn)
			if r != null and is_instance_valid(r):
				r.modulate = Color.WHITE if on else LETTERS_REST
		btn.mouse_entered.connect(light.bind(true))
		btn.mouse_exited.connect(light.bind(false))
		btn.focus_entered.connect(light.bind(true))
		btn.focus_exited.connect(light.bind(false))
	var old: TitleLetters = _button_rows.get(btn)
	if old != null and is_instance_valid(old):
		old.queue_free()
	_button_rows.erase(btn)
	# What the letters spell: the button's text without its glyph (📖 🏆 ⏻ 👤),
	# which no logo has.
	# Only a leading glyph goes: a name with an accent in it is not spelled with
	# the accent dropped, it stays plain text (below).
	var word := btn.text.strip_edges()
	var cut := word.find(" ")
	if cut > 0 and word.unicode_at(0) >= 128:
		word = word.substr(cut).strip_edges()
	var fixed: float = btn.get_meta("fixed_width", btn.custom_minimum_size.x)
	btn.set_meta("fixed_width", fixed)
	var row := TitleLetters.make(word, START_LETTERS if btn.name == &"StartRunBtn" else BUTTON_LETTERS,
		_button_rng, false, maxf(fixed - 2.0 * LETTER_MARGIN, 0.0))
	var spelled := row.placed.size() == word.replace(" ", "").length() and not row.placed.is_empty()
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color", "font_disabled_color"]:
		if spelled:
			btn.add_theme_color_override(state, Color(0, 0, 0, 0))
		else:
			btn.remove_theme_color_override(state)
	if not spelled:
		row.free()
		return
	# A button with no width of its own (the profile's) is as wide as its word.
	if fixed <= 0.0:
		btn.custom_minimum_size.x = row.ink_width + 2.0 * LETTER_MARGIN
	row.modulate = LETTERS_REST
	btn.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button_rows[btn] = row

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

# Whose game this is, in the top-left corner, and the way to change it: ONE
# button, the scene's %ProfileBtn, that carries the player's name and opens the
# profile picker. It was a label and a "Switch" button beside it, in a row with
# How to Play, Customization and Achievements; those three are in Extras now.
func _build_profile_row() -> void:
	_refresh_profile_row()

# ---------------------------------------------------------------------------
# Extras — everything that is not a way to play
# ---------------------------------------------------------------------------

# THE MENU IS FIVE BUTTONS AND A SECOND LIST. Start Run, Continue, Custom Run
# and Settings stay on the menu; the six screens you LOOK at rather than play
# (the manual, the Collection, Run History, the Tier List, Achievements,
# Customization) are behind Extras. They were spread over a grid of six and a
# row of three in the top-left corner (owner, 10 Nov 2026: "minimal amount of
# buttons").
#
# Extras SWAPS THE LIST IN PLACE: the main buttons step out and the scene's
# %ExtrasList stands where they were, in the same portal, which re-measures
# itself round whichever is showing (MenuPortal.holds). It was a pop-over on a
# dark panel first, which had nothing to do with the portal the buttons are in.
# The list stays while one of its screens is open, so closing the Collection
# lands back on it; Back or Esc returns to the main buttons.
@onready var _main_buttons: Control = %StartRunBtn.get_parent()

func _wire_extras() -> void:
	%ExtrasBtn.pressed.connect(show_extras.bind(true))
	%ExtrasBackBtn.pressed.connect(show_extras.bind(false))

func extras_shown() -> bool:
	return %ExtrasList.visible

func show_extras(on: bool) -> void:
	%ExtrasList.visible = on
	_main_buttons.visible = not on
	if on:
		_show_save_list(false)

# Esc leaves Extras, or closes the Continue list — but only with nothing raised over it: a
# screen on %ModalLayer answers its own Esc.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _modal_layer.get_child_count() > 0:
		return
	if extras_shown():
		show_extras(false)
	elif _save_list_container.visible:
		_show_save_list(false)
	else:
		return
	get_viewport().set_input_as_handled()

# THE BUTTONS UNDER THE TITLE: Start Run across the top, the rest (Continue,
# Custom Run, Extras, Settings) two to a row beneath it. The title stands in the middle of the screen now, which leaves
# about 270px below it on the 720 canvas, and the old single column of seven
# needed 400. The scene keeps every button in %Buttons in its old order; this
# deals the visible ones after Start Run into rows of two (HBoxes named Row0…),
# and is run again whenever Continue comes or goes, so an odd one out is centred
# on a row of its own rather than leaving a hole.
const GRID_W := 236.0
const GRID_H := 52.0

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

	quit_btn.custom_minimum_size = Vector2(210, 48)
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
	(%ProfileBtn as Button).text = "👤  %s" % Profiles.active_name()
	if (%ProfileBtn as Button).has_meta("lettered"):
		_spell_button(%ProfileBtn)

func _on_profiles() -> void:
	ProfilePicker.open(_modal_layer)

func _on_profile_switched() -> void:
	_refresh_profile_row()
	_show_save_list(false)
	show_extras(false)
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

# THE RUN PAGE LOADS WHILE THE MENU IS UP. Overworld2 is the game's biggest
# script and loading it (compiling it, mostly) took about a second at the click
# on Start or Continue (owner, 5 Nov 2026: "booting / main menu" slow). Requested
# on a worker thread here, it is usually done before a character is picked;
# `change_scene_to_file` waits for it if not. Not in a headless run (tests),
# which never leaves for the run page from here.
func _warm_run_page() -> void:
	if DisplayServer.get_name() == "headless" or ResourceLoader.has_cached(OVERWORLD2_SCENE):
		return
	ResourceLoader.load_threaded_request(OVERWORLD2_SCENE, "", true)

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
	show_extras(false)
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

# Costumes, icons and which title letters to spell with (docs/customization.md).
# In Extras. Switching letters off draws the title again when the screen closes, so the
# change shows.
func _on_customize() -> void:
	var s := CustomizeScreen.open(_modal_layer)
	s.tree_exited.connect(func() -> void:
		if is_inside_tree():
			_reroll(true)
			_reroll(false)
			_spell_buttons())

# What there is to unlock and how close this profile is (docs/achievements.md).
# In Extras.
func _on_achievements() -> void:
	AchievementsScreen.open(_modal_layer)

func _on_tier_list() -> void:
	TierListScreen.open(_modal_layer)

func _on_settings() -> void:
	SettingsModal.open(_modal_layer)

# ---------------------------------------------------------------------------
# How to Play — the manual, and its contents panel in the corner
# ---------------------------------------------------------------------------

# The manual is the first entry in Extras, and opens at its first chapter.
# Chapters are opened BY ID rather than by index, so inserting one in the middle
# does not quietly repoint anything.
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

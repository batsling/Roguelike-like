class_name SettingsModal
extends Control

# Settings panel, extracted from MainMenu so both the main menu and the in-run
# pause menu open the exact same controls. Built in code; runs
# PROCESS_MODE_ALWAYS so it works on top of a paused run.
#
# ONE ROW PER SETTING: a short label on the left, the control on the right, and
# the explanation in the tooltip of both. It used to be a single column with a
# paragraph under every control, which ran to three screens of scrolling and put
# Close at the bottom of all of it. Two columns of sections now fit a 720p window,
# and Close sits OUTSIDE the scroll, pinned to the panel's bottom-right corner.

const PANEL_MAX_W := 1040
const CONTROL_W := 280   # the right-hand column, so every control lines up
const LABEL_W := 170

static func open(parent: Node) -> SettingsModal:
	var m := SettingsModal.new()
	parent.add_child(m)
	return m

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# In a run this mounts on a CanvasLayer, which the theme does not cross — so
	# without this the in-run Settings came up in Godot's stock grey.
	UITheme.dress(self)
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_build_ui()

# Always cover the whole viewport so the centered panel can never fall off-screen
# on a smaller window; the panel itself is capped and scrolls its own content.
func _fit_to_viewport() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# The window-size dropdown's ids: 0 is "fit the screen", and every other entry
# is its index in Settings.WINDOW_SIZES plus one. Kept as two small functions
# rather than as parallel arrays so the list can grow in one place.
func _size_id(size: Vector2i) -> int:
	for i in range(Settings.WINDOW_SIZES.size()):
		if Settings.WINDOW_SIZES[i] == size:
			return i + 1
	return 0


func _size_for(id: int) -> Vector2i:
	if id <= 0 or id > Settings.WINDOW_SIZES.size():
		return Settings.WINDOWED_SIZE
	return Settings.WINDOW_SIZES[id - 1]

# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

func _section(col: VBoxContainer, title: String) -> GridContainer:
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	heading.add_theme_color_override("font_color", UITheme.ACCENT)
	col.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UITheme.GAP_LOOSE)
	grid.add_theme_constant_override("v_separation", UITheme.GAP_SNUG)
	col.add_child(grid)
	return grid

# One setting: its name, then its control. The tip is on both, so hovering
# either explains it.
func _row(grid: GridContainer, text: String, control: Control, tip: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(LABEL_W, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(label)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, CONTROL_W)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(control)
	_tip(label, control, tip)
	return label

func _tip(label: Control, control: Control, tip: String) -> void:
	label.tooltip_text = tip
	control.tooltip_text = tip
	for c in control.get_children():
		if c is Control and (c as Control).tooltip_text == "":
			(c as Control).tooltip_text = tip

func _toggle(grid: GridContainer, text: String, on: bool, set_fn: Callable, tip: String) -> CheckButton:
	var chk := CheckButton.new()
	chk.button_pressed = on
	chk.toggled.connect(func(v: bool) -> void: set_fn.call(v))
	# The switch sits at the start of its column, under the dropdowns' left edge.
	var holder := HBoxContainer.new()
	holder.add_child(chk)
	_row(grid, text, holder, tip)
	return chk

func _path_field(path: String) -> LineEdit:
	# Selectable rather than a Label: it is there to be copied.
	var field := LineEdit.new()
	field.text = path
	field.editable = false
	field.select_all_on_focus = true
	field.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	return field

# ---------------------------------------------------------------------------
# The page
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 24)
	add_child(outer)

	var center := CenterContainer.new()
	outer.add_child(center)

	var panel := PanelContainer.new()
	var vp: Vector2 = get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(PANEL_MAX_W, vp.x - 48), 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	margin.add_child(page)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	page.add_child(title)

	# Scrolls only if the window is shorter than the page — Close stays put.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", UITheme.GAP_BREAK)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UITheme.GAP)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	cols.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", UITheme.GAP)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	_build_display_section(left)
	_build_runs_section(left)
	_build_stream_section(right)
	_build_tags_section(right)
	_build_wipe_section(right)
	_build_dev_section(right)

	# Fitted once laid out: the scroll claims no height of its own, so it is
	# handed the page's, capped at what the window leaves.
	_fit_scroll.call_deferred(scroll, cols)

	var footer := HBoxContainer.new()
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.pressed.connect(queue_free)
	footer.add_child(close_btn)
	page.add_child(footer)

func _fit_scroll(scroll: ScrollContainer, content: Control) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(content):
		return
	# Title, footer, gaps and margins: what the panel spends that isn't the page.
	var cap: float = get_viewport_rect().size.y - 48 - 40 - 140
	scroll.custom_minimum_size.y = clampf(content.get_combined_minimum_size().y, 120.0, maxf(120.0, cap))

# --- display ----------------------------------------------------------------
#
# First, because it is the only section that changes what the player is looking
# at rather than what the run will do.
func _build_display_section(col: VBoxContainer) -> void:
	var grid := _section(col, "Display")

	var display_opt := OptionButton.new()
	# Default first: an ordinary window is what the game ships in (Settings.gd).
	for mode in [Settings.DisplayMode.WINDOWED, Settings.DisplayMode.WINDOWED_FULLSCREEN,
			Settings.DisplayMode.EXCLUSIVE]:
		display_opt.add_item(Settings.display_mode_name(mode), mode)
	display_opt.select(display_opt.get_item_index(Settings.display_mode))
	var mode_label := _row(grid, "Mode", display_opt)

	# The WINDOW'S SIZE, for windowed mode. The page is a fixed canvas stretched
	# into whatever the window is, so this is how big the same page is drawn.
	# Every entry is a request: a size bigger than the desktop is clamped to what
	# fits (Settings.windowed_fit).
	var size_box := HBoxContainer.new()
	size_box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	var size_opt := OptionButton.new()
	size_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_opt.add_item("Fit the screen", 0)
	for i in range(Settings.WINDOW_SIZES.size()):
		var s: Vector2i = Settings.WINDOW_SIZES[i]
		size_opt.add_item("%d × %d" % [s.x, s.y], i + 1)
	size_opt.select(size_opt.get_item_index(_size_id(Settings.windowed_size)))
	size_box.add_child(size_opt)
	# APPLY. The mode dropdown takes effect the moment it is picked, which means
	# re-picking the same mode does nothing — and "put the window back where I
	# asked for it" is a thing a player wants to be able to say.
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.tooltip_text = "Put the window back at this size and mode."
	size_box.add_child(apply_btn)
	var size_label := _row(grid, "Window size", size_box, "How big the window is drawn, in windowed mode.")

	var refresh_display := func() -> void:
		# The size only means anything to a window: both fullscreens are the size
		# of the screen by definition.
		var windowed: bool = display_opt.get_selected_id() == Settings.DisplayMode.WINDOWED
		size_opt.disabled = not windowed
		size_label.modulate.a = 1.0 if windowed else 0.5
		var tip: String
		match display_opt.get_selected_id():
			Settings.DisplayMode.WINDOWED:
				tip = "An ordinary window, with your taskbar reachable. F11 toggles."
			Settings.DisplayMode.EXCLUSIVE:
				tip = "True fullscreen. Every alt-tab out is a mode switch. F11 toggles."
			_:
				tip = "A borderless window filling the screen. Alt-tab is instant. F11 toggles."
		_tip(mode_label, display_opt, tip)
	refresh_display.call()

	display_opt.item_selected.connect(func(idx: int) -> void:
		Settings.set_display_mode(display_opt.get_item_id(idx))
		refresh_display.call())
	size_opt.item_selected.connect(func(idx: int) -> void:
		Settings.set_windowed_size(_size_for(size_opt.get_item_id(idx))))
	apply_btn.pressed.connect(func() -> void:
		Settings.set_windowed_size(_size_for(size_opt.get_selected_id()))
		Settings.set_display_mode(display_opt.get_selected_id())
		# set_display_mode is a no-op when the mode has not moved, which is the
		# common case here — the point of the button is the second half.
		Settings.apply_display_mode())

	# Takes effect immediately, including from here — this panel opens OVER the
	# menu, so the art behind it starts or stops as it is ticked.
	_toggle(grid, "Menu falling art", Settings.menu_falling_art,
		func(on: bool) -> void: Settings.set_menu_falling_art(on),
		"Enemies, items, loot and covers drifting down the main menu.")

# --- runs ---------------------------------------------------------------------
func _build_runs_section(col: VBoxContainer) -> void:
	var grid := _section(col, "Runs")

	# Count how many games each filter would allow, shown inline so the player
	# can see how restrictive each choice is.
	var total: int = 0
	var downloaded_n: int = 0
	for g in Data.all_games():
		if not (g is GameData):
			continue
		total += 1
		if g.file_location.strip_edges() != "":
			downloaded_n += 1

	var opt := OptionButton.new()
	opt.add_item("Any game (%d)" % total, Settings.GameFilter.ALL)
	opt.add_item("Owned games (%d)" % Ownership.owned_count(), Settings.GameFilter.OWNED)
	opt.add_item("Downloaded only (%d)" % downloaded_n, Settings.GameFilter.DOWNLOADED)
	opt.select(opt.get_item_index(Settings.game_filter))
	var pool_label := _row(grid, "Game pool", opt)

	var refresh_pool := func() -> void:
		var tip: String
		match opt.get_selected_id():
			Settings.GameFilter.OWNED:
				tip = "Paths only use games you own. Fewer games, sparser paths."
			Settings.GameFilter.DOWNLOADED:
				tip = "Paths only use games with a file location, so each is launchable."
			_:
				tip = "Paths can use any game in the catalog."
		_tip(pool_label, opt, tip)
	refresh_pool.call()
	opt.item_selected.connect(func(idx: int) -> void:
		Settings.set_game_filter(opt.get_item_id(idx))
		refresh_pool.call())

	# The owned count above is only as fixed as the ownership source below it, so
	# re-label that one entry whenever the answer moves.
	var refresh_owned_count := func() -> void:
		var i: int = opt.get_item_index(Settings.GameFilter.OWNED)
		if i >= 0:
			opt.set_item_text(i, "Owned games (%d)" % Ownership.owned_count())
	_build_ownership_row(grid, refresh_owned_count)

	_toggle(grid, "Skip won amulets", Settings.exclude_beaten_amulets,
		func(on: bool) -> void: Settings.set_exclude_beaten_amulets(on),
		"Don't target an amulet game you've already beaten. It can still be a stop on the way.")
	_toggle(grid, "Rifts", Settings.rifts_enabled,
		func(on: bool) -> void: Settings.set_rifts_enabled(on),
		"Pull a few unconnected games into the map. Never shortens a route. From the next run.")
	_toggle(grid, "Wide Traditional transmute",
		Settings.traditional_transmute == Settings.TraditionalTransmute.ANY_OTHER,
		func(on: bool) -> void:
			Settings.set_traditional_transmute(Settings.TraditionalTransmute.ANY_OTHER if on
				else Settings.TraditionalTransmute.SAME_TYPE),
		"A Traditional game transmutes into a game of any OTHER type, not another Traditional.")

# Where the "Owned" answer comes from: the shipped spreadsheet column, or a list
# this player builds by ticking games off their covers in the compendium.
# `on_change` re-labels the pool dropdown's owned count.
func _build_ownership_row(grid: GridContainer, on_change: Callable) -> void:
	var sheet_n: int = 0
	for g in Data.all_games():
		if g is GameData and (g as GameData).owned:
			sheet_n += 1

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	var src := OptionButton.new()
	src.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src.add_item("Catalog's list (%d)" % sheet_n, Ownership.Source.SPREADSHEET)
	src.add_item("My own list (%d)" % Ownership.manual_count(), Ownership.Source.MANUAL)
	src.select(src.get_item_index(Ownership.source))
	box.add_child(src)
	var clear_btn := Button.new()
	clear_btn.name = "ClearOwnedBtn"
	clear_btn.text = "Clear"
	clear_btn.tooltip_text = "Empty your own list."
	box.add_child(clear_btn)
	var label := _row(grid, "Owned games", box)

	var refresh := func() -> void:
		var i: int = src.get_item_index(Ownership.Source.MANUAL)
		if i >= 0:
			src.set_item_text(i, "My own list (%d)" % Ownership.manual_count())
		src.select(src.get_item_index(Ownership.source))
		clear_btn.disabled = Ownership.manual_count() == 0
		var tip: String = "Mark a game owned with the tick on its cover in the compendium (Tab)." \
			if Ownership.source == Ownership.Source.MANUAL \
			else "The catalog's own Owned column, the same for everyone."
		label.tooltip_text = tip
		src.tooltip_text = tip
		on_change.call()
	refresh.call()

	src.item_selected.connect(func(idx: int) -> void:
		Ownership.set_source(src.get_item_id(idx))
		refresh.call())
	clear_btn.pressed.connect(func() -> void:
		Ownership.clear_manual()
		refresh.call())

# --- stream -------------------------------------------------------------------
#
# THE STREAM OVERLAY (docs/games-first-redesign.md §9, ObsCompanion). The folder
# is the load-bearing part: OBS needs an absolute file to point a Browser Source
# at, and `user://` is somewhere different on every platform. It is the FOLDER,
# not overlay.html, because there are six pages in it; the tooltip lists them as
# files rather than URL suffixes, since a # cannot be typed into OBS's local-file
# box.
func _build_stream_section(col: VBoxContainer) -> void:
	var grid := _section(col, "Stream")

	_toggle(grid, "OBS overlay", Settings.obs_overlay,
		func(on: bool) -> void: Settings.set_obs_overlay(on),
		"Mirror the run into browser pages for OBS: health, shields, the game in play, the checklist.")

	var pages_tip: String = "In OBS add a Browser Source, tick \"Local file\" and pick a page in this folder:\n" \
		+ "  overlay.html  the run (352 × 680, transform at 100%)\n" \
		+ "  goals.html  the checklist alone\n" \
		+ "  map.html  the road ahead, 2560 × 1440\n" \
		+ "  road.html  the road walked, 352 × 116\n" \
		+ "  top.html / bottom.html  the run card and checklist apart"
	_row(grid, "Overlay folder", _path_field(ObsCompanion.page_dir()), pages_tip)

	# THE CATEGORY REMINDER: the same job as the overlay — things the stream needs
	# that the run cannot do for itself. It only posts a notification; nothing
	# here talks to Twitch.
	var twitch := _toggle(grid, "Twitch reminder", Settings.twitch_reminder,
		func(on: bool) -> void: Settings.set_twitch_reminder(on),
		"Notify you to change the Twitch category when you pick a game.")
	twitch.name = "TwitchChk"

	# ROGUELIKE RADIO's one override (docs/games-first-redesign.md §20.6). Off
	# gives back exactly what the game ranks have drawn.
	var all_songs := _toggle(grid, "Unlock all songs", Radio.unlock_all,
		func(on: bool) -> void: Radio.set_unlock_all(on),
		"Play every Roguelike Radio song, whatever the game ranks have unlocked. Turning it off goes back to what the ranks earned.")
	all_songs.name = "UnlockAllSongsChk"

# --- game tags ----------------------------------------------------------------
#
# THE TAG EXPORT (GameTags). Tags are edited per game, on the Collection's game
# page and the run map's card; getting them into the sheet is one act for the
# whole catalog, so it lives here. tools/apply_tag_edits.py writes the
# differences into the `games` sheet.
func _build_tags_section(col: VBoxContainer) -> void:
	var grid := _section(col, "Game tags")

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP)
	var export_btn := Button.new()
	export_btn.name = "ExportTagsBtn"
	export_btn.text = "Export"
	box.add_child(export_btn)
	var status := Label.new()
	status.name = "TagsHint"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	status.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(status)
	_row(grid, "Tag edits", box,
		"Writes every game's tags to the file below, for tools/apply_tag_edits.py.")

	var path := _path_field(ProjectSettings.globalize_path(GameTags.export_path()))
	path.name = "TagsPath"
	_row(grid, "Export file", path, path.text)

	var refresh := func() -> void:
		var n: int = GameTags.pending_count()
		status.text = ("%d game%s %s tag edits" % [n, "" if n == 1 else "s", "has" if n == 1 else "have"]
			if n > 0 else "All in the sheet")
		status.remove_theme_color_override("font_color")
		status.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	refresh.call()

	export_btn.pressed.connect(func() -> void:
		var written: String = GameTags.export_edits()
		refresh.call()
		if written == "":
			status.text = "Couldn't write the file"
			status.add_theme_color_override("font_color", UITheme.DANGER)
			return
		status.text = "Exported all %d games" % Data.all_games().size()
		status.add_theme_color_override("font_color", UITheme.SUCCESS))

# --- this profile -------------------------------------------------------------
#
# Starting over as yourself: empty the profile you are playing and keep it.
# It lives here rather than on the profile screen because it is about the player
# currently playing; deleting a whole profile is the profile screen's job.
func _build_wipe_section(col: VBoxContainer) -> void:
	var grid := _section(col, "Profile")

	var holder := HBoxContainer.new()
	var wipe := Button.new()
	wipe.name = "WipeBtn"
	wipe.text = "🗑  Wipe"
	wipe.add_theme_color_override("font_color", Color(1, 0.72, 0.68))
	holder.add_child(wipe)
	var label := _row(grid, Profiles.active_name(), holder,
		"Erase this profile's runs, stats, tier list, owned games and run settings. The profile stays.")

	# A run is exactly what a wipe would pull the floor out from under — so the
	# button is only live when there is no run in progress.
	var in_run: bool = GameState.phase != GameState.Phase.MENU
	wipe.disabled = in_run
	if in_run:
		wipe.tooltip_text = "Finish or leave your run first — wiping deletes the save it is running on."
		return

	wipe.pressed.connect(func() -> void:
		ConfirmPanel.ask(self, "Wipe profile",
			"Erase everything saved under \"%s\"?\n\nIts runs, lifetime stats, tier list, owned-game list and run settings are all deleted. The profile itself stays. This cannot be undone." % Profiles.active_name(),
			"Wipe",
			func() -> void:
				if Profiles.wipe(Profiles.active_id):
					wipe.text = "Wiped"
					wipe.disabled = true
					label.add_theme_color_override("font_color", UITheme.SUCCESS)))

# --- developer ----------------------------------------------------------------
func _build_dev_section(col: VBoxContainer) -> void:
	var grid := _section(col, "Developer")
	_toggle(grid, "Developer mode", Settings.dev_mode,
		func(on: bool) -> void: Settings.set_dev_mode(on),
		"Enables the dev overlay (` backtick) to add any card, curse or item.")

class_name CharacterPicker
extends Control

# The character select overlay — the roster in data/characters2.0, and the SECOND
# screen between pressing Start Run and being in a run: the player and its
# Fracture are picked first (PlayerPicker, docs/players-design.md).
#
# It used to be built inline in MainMenu.gd, which made it the only full-screen
# overlay in the project that was not its own class: every other one
# (CustomRunScreen, ProfilePicker, SettingsModal, TierListScreen, Collection,
# HowToPlayScreen, RunHistoryScreen) is a `class_name` with a static `open`, and
# the menu already CALLS four of them. It was also 47% of that file.
#
# Layout (per UI pass): a four-column GRID of small icon tiles on the left, the
# selected hero's FULL portrait beside its full information on the right, and a
# Cancel / 🎲 Random / Confirm row along the bottom. Selecting a tile only
# previews it, and so does the dice; Confirm emits `chosen` and the host starts
# the run.
#
# Mounted as an ordinary Control on the menu's `%ModalLayer` rather than on a
# CanvasLayer of its own, and that matters: the menu's Quit Game corner is drawn
# UNDER that layer on purpose, so the door out of the application cannot sit on
# top of this screen. See MainMenu._move_quit_to_corner.

# Confirm pressed; carries the id of the hero the run should open with.
signal chosen(character_id: StringName)

# The roster board: four tiles per row, and the tile sized to suit that rather
# than the other way round — four 122px tiles ran past the grid's half of the
# panel, so the icon token gives up a little to buy the extra column.
const TILE_COLUMNS := 4
const TILE_SIZE := Vector2(108, 122)
const TILE_GAP := 10

# The portrait's edge in the detail panel. Also the width its name / source /
# Health column is laid out to, so the two columns line up.
const CHAR_PORTRAIT_SIZE := 210

# NO SCROLL BAR, NO DEAD SPACE (the owner, 18 Nov 2026: "condense the
# character/player selection screen so that there's less wasting space. At this
# point there should be no need for a scroll bar"). The grid is as tall as its
# rows, floored at what the detail panel beside it needs, and the panel is as
# tall as that — it used to be a fixed 620 with a 470px scroll the roster
# overflowed by one row of two-line names.
const DETAIL_MIN_H := 340.0

static func grid_height(count: int) -> float:
	var rows: int = maxi(1, ceili(float(count) / float(TILE_COLUMNS)))
	return maxf(DETAIL_MIN_H, rows * TILE_SIZE.y + (rows - 1) * TILE_GAP)

# The roster as CharacterData, in the order the grid draws it, and the selection
# callback every tile click goes through. Both exist so `roll_random` picks a hero
# the same way a click does rather than re-implementing selection beside it.
var _roster: Array[CharacterData] = []
var _select: Callable = Callable()
var _state: Dictionary = {}
var _looks_box: VBoxContainer = null

static func open(parent: Node) -> CharacterPicker:
	var picker := CharacterPicker.new()
	parent.add_child(picker)
	return picker

func _ready() -> void:
	# `set_anchors_and_offsets_preset`, NOT `set_anchors_preset` — the difference
	# is the whole screen. `set_anchors_preset` preserves the control's CURRENT
	# rect by recomputing the offsets against it, and in `_ready` this node is
	# already mounted at 0x0, so it would anchor a 0x0 rect to the full parent and
	# stay 0x0 forever. The inline version got away with the bare call because it
	# ran on a DETACHED Control (no parent, so no offsets to recompute) and only
	# then mounted it. Symptom when it is wrong: the panel draws in the top-left
	# corner instead of centred, and the menu's Quit Game corner shows through.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.shared()
	_build()

# The detail half NEVER scrolls: the portrait takes the left of it and every
# other fact is stacked to the RIGHT of the portrait rather than under it, which
# is what buys the room to fit a hero on one screen. See _fill_char_detail.
func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	# Wide enough for FOUR icon columns on the left and a portrait-beside-facts
	# detail panel on the right, and short enough that both halves are one screen
	# on a 720p window.
	panel.custom_minimum_size = Vector2(1080, 0)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG, UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 12, 22, 2))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	panel.add_child(vbox)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Choose Your Character"
	title.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.tooltip_text = "Each hero opens the run with their own Health, gold, starting loot and level-up goal."
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(title)

	# Body: icon grid (left) | full portrait + info (right).
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# A GridContainer rather than a flow: the roster reads as a fixed four-wide
	# board, so a hero is always in the same place whatever the panel's width does.
	var grid_scroll := ScrollContainer.new()
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Vertical scrolling OFF too: the box then grows to the grid's real height (a
	# tile is taller than TILE_SIZE once its rank badge hangs under the icon), so
	# there is never a bar. grid_height is only the floor.
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.custom_minimum_size = Vector2(TILE_COLUMNS * (TILE_SIZE.x + TILE_GAP),
		grid_height(Data.all_characters2().size()))
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid_scroll)
	var grid := GridContainer.new()
	grid.columns = TILE_COLUMNS
	grid.add_theme_constant_override("h_separation", TILE_GAP)
	grid.add_theme_constant_override("v_separation", TILE_GAP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(grid)

	var detail_wrap := PanelContainer.new()
	detail_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 12, 14, 1))
	detail_wrap.custom_minimum_size = Vector2(520, 0)
	detail_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail_wrap)
	# NO ScrollContainer: the hero has to be readable in one look. The two columns
	# inside are filled by _fill_char_detail — portrait left, facts right.
	var detail_col := VBoxContainer.new()
	detail_col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	detail_wrap.add_child(detail_col)
	var detail_box := HBoxContainer.new()
	detail_box.name = "Detail"
	detail_box.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_col.add_child(detail_box)
	# The CUSTOMIZE BUTTON's place, at the foot of the panel: the hero's costumes
	# open in a popup from it (open_customize).
	_looks_box = VBoxContainer.new()
	_looks_box.name = "Looks"
	detail_col.add_child(_looks_box)

	# NO FRACTURE ROW here any more: the ladder belongs to the PLAYER, picked on the
	# screen before this one (PlayerPicker, docs/players-design.md §2).

	# Footer: Cancel (left) and the Confirm button (right), enabled once a hero is
	# selected.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	vbox.add_child(footer)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(150, 44)
	cancel.pressed.connect(queue_free)
	footer.add_child(cancel)
	# THE DICE PREVIEW, THEY CONFIRM. It rolls a hero into the same `select` every
	# tile click goes through — so the portrait, the facts and the Confirm label all
	# come up as if it had been picked by hand — and stops there. Rolling straight
	# into the run would make this the one button on the screen that starts one
	# without the Confirm beside it, and would leave no way to see what you got and
	# roll again.
	#
	# So it is BESIDE Confirm, which is what that reasoning asks for and what the
	# layout used to contradict: the dice sat next to Cancel with the expanding
	# spacer between it and the button it hands off to, measured at 478px apart on
	# a 1280px canvas. Roll, look, roll again, confirm is now one cluster, and
	# Cancel is alone on the left where the way out belongs.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var random_btn := Button.new()
	random_btn.text = "🎲  Random"
	random_btn.custom_minimum_size = Vector2(150, 44)
	random_btn.tooltip_text = "Pick a hero at random — press again to reroll, Confirm to take it."
	footer.add_child(random_btn)

	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.disabled = true
	confirm.custom_minimum_size = Vector2(220, 44)
	confirm.add_theme_stylebox_override("normal", UITheme.accent_box(UITheme.ACCENT, UITheme.PANEL_HI, 8))
	confirm.add_theme_color_override("font_color", UITheme.GOLD)
	confirm.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	footer.add_child(confirm)

	# Selection state shared between the tiles, the detail panel, and Confirm.
	# Kept on the node as well as in this scope so the dice button — and a test —
	# can drive the very same selection path a tile click takes.
	var state := {"id": &"", "tiles": {}}
	_state = state
	var select := func(ch: CharacterData) -> void:
		state["id"] = ch.id
		for tid in state["tiles"]:
			state["tiles"][tid].call(tid == ch.id)
		_fill_char_detail(detail_box, ch)
		# A LOCKED hero can be looked at, not played (docs/achievements.md): the
		# panel says what unlocks them and Confirm stays dark.
		var locked: bool = Achievements.character_locked(ch.id)
		confirm.disabled = locked
		# The name is the detail panel's heading right beside this; the button
		# carries it on hover rather than saying it twice.
		confirm.tooltip_text = ("%s is locked. See Achievements." if locked
			else "Start as %s") % ch.display_name

	_select = select

	var roster: Array = Data.all_characters2()
	for ch in roster:
		if ch is CharacterData:
			_roster.append(ch)
			# On screen in the picker is seen, for the Collection.
			GameStats.mark_seen("character", ch.id)
	for ch in _roster:
		grid.add_child(_character_tile(ch, state, select))
	# A wrapped name makes its own tile taller, and a GridContainer row is as tall
	# as its tallest cell — so one two-line name ("Antonio Belpaese") made the whole
	# first ROW 15px taller than rows 2 and 3. Levelled once the tiles have a size.
	_equalise_tiles(grid)
	random_btn.pressed.connect(func(): roll_random())
	random_btn.disabled = _playable().size() < 2
	confirm.pressed.connect(func():
		if String(state["id"]) != "":
			_confirm(StringName(state["id"])))

	# Preselect the first hero that can be played, so the panel is never empty and
	# Confirm is live.
	var open_heroes: Array[CharacterData] = _playable()
	if not open_heroes.is_empty():
		select.call(open_heroes[0])
	elif not _roster.is_empty():
		select.call(_roster[0])

# The heroes a run can start as: everyone no unfinished achievement is holding back.
func _playable() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for ch in _roster:
		if not Achievements.character_locked(ch.id):
			out.append(ch)
	return out

# Roll a hero into the preview and answer which one it was. Public because the
# footer's 🎲 is not the only thing that should be able to ask for one, and
# because a headless test can then press it without a mouse.
#
# NEVER THE ONE ALREADY SHOWING, as long as the roster has another to offer: a die
# that can land on the hero you are already looking at reads as a button that did
# nothing, and rerolling is the whole point of previewing rather than starting the
# run. With a one-hero roster there is nothing to say, and the button is disabled.
func roll_random() -> CharacterData:
	if _roster.is_empty() or not _select.is_valid():
		return null
	# Never a locked hero: the dice hands off to Confirm, which would be dark.
	var playable: Array[CharacterData] = _playable()
	if playable.is_empty():
		return null
	var pool: Array[CharacterData] = []
	var showing := String(_state.get("id", &""))
	for ch in playable:
		if String(ch.id) != showing:
			pool.append(ch)
	if pool.is_empty():
		pool = playable
	var pick: CharacterData = pool[randi() % pool.size()]
	_select.call(pick)
	return pick

# Emit and stand down, the same shape CustomRunScreen._begin uses: the screen
# says what was picked and stops existing, and what that MEANS is the host's.
func _confirm(character_id: StringName) -> void:
	chosen.emit(character_id)
	queue_free()

# One roster tile = the character's ICON (small token, falling back to the full
# portrait) with the name below. Clicking previews the hero via `select`; the
# stored callback re-styles the tile for the selected / unselected state.
func _character_tile(ch: CharacterData, state: Dictionary, select: Callable) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 8, 1)
	var selected := UITheme.accent_box(UITheme.GOLD, UITheme.PANEL_HI, 10)
	tile.add_theme_stylebox_override("panel", normal)
	var set_selected := func(is_sel: bool) -> void:
		tile.add_theme_stylebox_override("panel", selected if is_sel else normal)
		tile.modulate = Color(1.08, 1.08, 1.08) if is_sel else Color.WHITE
	state["tiles"][ch.id] = set_selected

	tile.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			select.call(ch))
	tile.mouse_entered.connect(func():
		if String(state["id"]) != String(ch.id):
			tile.modulate = Color(1.06, 1.06, 1.06))
	tile.mouse_exited.connect(func():
		if String(state["id"]) != String(ch.id):
			tile.modulate = Color.WHITE)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(vb)
	var tex: Texture2D = ch.shown_icon()
	if tex != null:
		# The character's rank on its token (§20.9), hung half below it like a
		# game cover's.
		var icon := UITheme.crisp_tex(tex, 76)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		# A locked hero is their silhouette, as on the Achievements screen.
		if Achievements.character_locked(ch.id):
			icon.modulate = Color(0, 0, 0, 0.8)
			tile.tooltip_text = "Locked. %s" % Achievements.for_character(ch.id).description
		# kept so a costume changed in the detail panel shows on the token at once
		(state.get_or_add("icons", {}) as Dictionary)[ch.id] = icon
		vb.add_child(RankBadge.wrap_character(icon, ch.id))
	var name_lbl := Label.new()
	name_lbl.text = ch.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# ONE LINE, so every tile is the same height and three rows fit; a long name
	# ends in an ellipsis and is whole on the hover and in the detail panel.
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.custom_minimum_size = Vector2(TILE_SIZE.x - 16, 0)
	if tile.tooltip_text == "":
		tile.tooltip_text = ch.display_name
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	vb.add_child(name_lbl)
	return tile

# EVERY TILE AS TALL AS THE TALLEST, measured after layout rather than predicted.
# Two predictions were tried and both came up short: `line height × 2` by 7px, and
# the font's own `get_multiline_string_size` by the same 7px — because a wrapped
# Label also carries the theme's line spacing, which font metrics do not report.
# Reading the laid-out tiles cannot be wrong in that way, and it keeps working if
# the roster, the font or the tile width ever change.
func _equalise_tiles(grid: GridContainer) -> void:
	if not is_instance_valid(grid):
		return
	await get_tree().process_frame
	if not is_instance_valid(grid):
		return
	var tallest: float = 0.0
	for tile in grid.get_children():
		tallest = maxf(tallest, (tile as Control).size.y)
	for tile in grid.get_children():
		(tile as Control).custom_minimum_size.y = tallest

# Fill the right-hand detail panel with the selected hero's FULL portrait and all
# of its information (source, Health, verbs, description, starting items, level-up).
#
# Two columns, because one column plus a scrollbar is what this used to be: the
# portrait, the name and the vitals go LEFT, and the prose — verbs, description,
# starting items, level-up — stacks to the RIGHT of them. Nothing here scrolls,
# so everything the pick is made on is on screen at once.
func _fill_char_detail(box: HBoxContainer, ch: CharacterData) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if Achievements.character_locked(ch.id):
		_fill_locked_detail(box, ch)
		return

	# LEFT: who they are — portrait, name, where they're from, how much Health.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	left.custom_minimum_size = Vector2(CHAR_PORTRAIT_SIZE, 0)
	# CENTRED, like the column beside it. This one was SHRINK_BEGIN while `right`
	# was SHRINK_CENTER, so the portrait hung from the top of a 442px panel, the
	# facts floated at its middle, and the leftover — measured at 144px on nine of
	# the eleven heroes — all pooled under the portrait. Centring both splits that
	# space evenly and puts the prose beside the picture it is about, which is what
	# `right`'s comment says it is for. Safe because nothing here scrolls and every
	# hero was measured first: the tallest (Manager, 318px) still leaves 124px.
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(left)
	if ch.shown_portrait() != null:
		var portrait := UITheme.crisp_tex(ch.shown_portrait(), CHAR_PORTRAIT_SIZE)
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		left.add_child(portrait)

	var name_lbl := Label.new()
	name_lbl.text = ch.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(CHAR_PORTRAIT_SIZE, 0)
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	name_lbl.add_theme_color_override("font_color", UITheme.GOLD)
	left.add_child(name_lbl)

	if ch.source_game != "":
		var src := Label.new()
		src.text = "From: %s" % ch.source_game
		src.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		src.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		src.custom_minimum_size = Vector2(CHAR_PORTRAIT_SIZE, 0)
		src.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		src.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		left.add_child(src)

	var hp := Label.new()
	hp.text = "♥ %d Health" % ch.base_max_hp
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	hp.add_theme_color_override("font_color", UITheme.DANGER.lerp(UITheme.TEXT, 0.35))
	left.add_child(hp)

	if _looks_box != null:
		for c in _looks_box.get_children():
			_looks_box.remove_child(c)
			c.queue_free()
		if _has_costumes(ch):
			_looks_box.add_child(CustomizeScreen.customize_button(
				func(): open_customize(box, ch)))

	# RIGHT: what they play like.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Centred against the portrait rather than hung off the top of the panel: a
	# hero with two facts and one with five both sit beside their own picture.
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(right)

	if ch.description != "":
		var desc := Label.new()
		desc.text = ch.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		desc.add_theme_color_override("font_color", UITheme.TEXT.lerp(UITheme.TEXT_DIM, 0.3))
		right.add_child(desc)

	var loadout: PackedStringArray = Data.loadout_names(ch)
	if not loadout.is_empty():
		right.add_child(HSeparator.new())
		right.add_child(_detail_head("Starting Loadout"))
		var items_lbl := Label.new()
		items_lbl.text = ", ".join(loadout)
		items_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		items_lbl.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		items_lbl.add_theme_color_override("font_color", UITheme.TEXT.lerp(Color(0.7, 0.85, 0.95), 0.5))
		right.add_child(items_lbl)

	if ch.level_up_condition != "":
		right.add_child(HSeparator.new())
		right.add_child(_detail_head("Level Up"))
		var lu := Label.new()
		lu.text = ch.level_up_condition
		lu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lu.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		lu.add_theme_color_override("font_color", UITheme.TEXT.lerp(Color(0.7, 0.85, 0.95), 0.5))
		right.add_child(lu)
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			var reward := Label.new()
			reward.text = "→ %s" % ch.level_up_reward
			reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reward.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
			reward.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.35))
			right.add_child(reward)

# A LOCKED HERO (docs/achievements.md): the silhouette, the name, and what unlocks
# them with how close this profile has come — the same words the Achievements
# screen uses. None of what they play like: that is what the unlock is for.
func _fill_locked_detail(box: HBoxContainer, ch: CharacterData) -> void:
	if _looks_box != null:
		for c in _looks_box.get_children():
			_looks_box.remove_child(c)
			c.queue_free()
	var a: AchievementData = Achievements.for_character(ch.id)
	var col := VBoxContainer.new()
	col.name = "Locked"
	col.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(col)
	if ch.shown_portrait() != null:
		var portrait := UITheme.crisp_tex(ch.shown_portrait(), CHAR_PORTRAIT_SIZE)
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		portrait.modulate = Color(0, 0, 0, 0.8)
		col.add_child(portrait)
	var lines := [
		[ch.display_name, UITheme.FONT_TITLE_LG, UITheme.GOLD],
		["Locked", UITheme.FONT_SUB, UITheme.ACCENT],
		[a.description, UITheme.FONT_LEAD, UITheme.TEXT],
		[("Best in one run: %d of %d" if a.is_run_scope() else "So far: %d of %d")
			% [Achievements.progress(a), a.goal], UITheme.FONT_LEAD,
			Achievements.RUN_COLOR if a.is_run_scope() else Achievements.LIFETIME_COLOR],
	]
	for l in lines:
		var lbl := Label.new()
		lbl.text = String(l[0])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", int(l[1]))
		lbl.add_theme_color_override("font_color", l[2])
		col.add_child(lbl)

# THE COSTUMES, in a popup off the Customize button (the owner, 15 Nov 2026; they
# were a band across the foot of the detail panel). One row for the icon and one
# for the full portrait, each the same choices as the Customization screen
# (CustomizeScreen.slot_tiles): the default, 🎲 Random, then every costume, a
# locked one as its silhouette. No button for a hero with no costumes at all.
const LOOK_TILE := 40
var _popup: Control = null

func _costume_slots(ch: CharacterData) -> Array:
	return CosmeticCatalog.SLOTS.filter(func(slot):
		return not CosmeticCatalog.costumes_of(ch.id, slot).is_empty())

func _has_costumes(ch: CharacterData) -> bool:
	return not _costume_slots(ch).is_empty()

# Open the costume popup for `ch`. Public so a test can open it as the button does.
func _after_look_change(box: HBoxContainer, ch: CharacterData) -> void:
	var icons: Dictionary = _state.get("icons", {})
	if icons.has(ch.id) and is_instance_valid(icons[ch.id]):
		(icons[ch.id] as TextureRect).texture = ch.shown_icon()
		UITheme.apply_crisp(icons[ch.id], ch.shown_icon())
	if is_instance_valid(box):
		_fill_char_detail(box, ch)
	if is_instance_valid(_popup):
		(_popup.get_meta(&"refill") as Callable).call()

func open_customize(box: HBoxContainer, ch: CharacterData) -> Control:
	if is_instance_valid(_popup):
		_popup.queue_free()
	# A method, not a lambda, on the deferred queue: see
	# PostCombatScreen._refresh_exit for the crash a freed lambda causes.
	var on_change := func() -> void:
		_after_look_change.call_deferred(box, ch)
	_popup = CustomizeScreen.looks_popup(self, "%s — Costumes" % ch.display_name,
		func(body: VBoxContainer) -> void:
			var col := VBoxContainer.new()
			col.name = "Costumes"
			col.add_theme_constant_override("separation", UITheme.GAP)
			body.add_child(col)
			for slot in _costume_slots(ch):
				col.add_child(CustomizeScreen.look_row("Slot_%s" % slot,
					"Icon" if slot == "icon" else "Full",
					CustomizeScreen.costume_tiles(ch, slot, LOOK_TILE, on_change))))
	return _popup

func _detail_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	l.add_theme_color_override("font_color", UITheme.ACCENT.lerp(UITheme.TEXT, 0.2))
	return l


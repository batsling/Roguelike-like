class_name CharacterPicker
extends Control

# The character select overlay — the roster in data/characters2.0, and the one
# screen between pressing Start Run and being in a run.
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
# CanvasLayer of its own, and that matters: the menu's Exit Game corner is drawn
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

# The roster as CharacterData, in the order the grid draws it, and the selection
# callback every tile click goes through. Both exist so `roll_random` picks a hero
# the same way a click does rather than re-implementing selection beside it.
var _roster: Array[CharacterData] = []
var _select: Callable = Callable()
var _state: Dictionary = {}

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
	# corner instead of centred, and the menu's Exit Game corner shows through.
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
	panel.custom_minimum_size = Vector2(1080, 620)
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

	# Body: icon grid (left) | full portrait + info (right).
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	# A GridContainer rather than a flow: the roster reads as a fixed four-wide
	# board, so a hero is always in the same place whatever the panel's width does.
	var grid_scroll := ScrollContainer.new()
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.custom_minimum_size = Vector2(TILE_COLUMNS * (TILE_SIZE.x + TILE_GAP), 470)
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
	var detail_box := HBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 14)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_wrap.add_child(detail_box)

	# Footer: Cancel (left) and the Confirm button (right), enabled once a hero is
	# selected.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
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
	var random_btn := Button.new()
	random_btn.text = "🎲  Random"
	random_btn.custom_minimum_size = Vector2(150, 44)
	random_btn.tooltip_text = "Pick a hero at random — press again to reroll, Confirm to take it."
	footer.add_child(random_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.disabled = true
	confirm.custom_minimum_size = Vector2(220, 44)
	confirm.add_theme_stylebox_override("normal", UITheme.accent_box(UITheme.ACCENT, UITheme.PANEL_HI, 8))
	confirm.add_theme_color_override("font_color", UITheme.GOLD)
	confirm.add_theme_font_size_override("font_size", 18)
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
		confirm.disabled = false
		confirm.text = "Confirm: %s" % ch.display_name

	_select = select

	var roster: Array = Data.all_characters2()
	for ch in roster:
		if ch is CharacterData:
			_roster.append(ch)
			grid.add_child(_character_tile(ch, state, select))
	random_btn.pressed.connect(func(): roll_random())
	random_btn.disabled = _roster.size() < 2
	confirm.pressed.connect(func():
		if String(state["id"]) != "":
			_confirm(StringName(state["id"])))

	# Preselect the first hero so the panel is never empty and Confirm is live.
	if not roster.is_empty() and roster[0] is CharacterData:
		select.call(roster[0])

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
	var pool: Array[CharacterData] = []
	var showing := String(_state.get("id", &""))
	for ch in _roster:
		if String(ch.id) != showing:
			pool.append(ch)
	if pool.is_empty():
		pool = _roster
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
	vb.add_theme_constant_override("separation", 4)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_child(vb)
	var tex: Texture2D = ch.icon if ch.icon != null else ch.portrait
	if tex != null:
		vb.add_child(UITheme.crisp_tex(tex, 76))
	var name_lbl := Label.new()
	name_lbl.text = ch.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(TILE_SIZE.x - 16, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	vb.add_child(name_lbl)
	return tile

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

	# LEFT: who they are — portrait, name, where they're from, how much Health.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(CHAR_PORTRAIT_SIZE, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	box.add_child(left)
	if ch.portrait != null:
		var portrait := UITheme.crisp_tex(ch.portrait, CHAR_PORTRAIT_SIZE)
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		left.add_child(portrait)

	var name_lbl := Label.new()
	name_lbl.text = ch.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(CHAR_PORTRAIT_SIZE, 0)
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", UITheme.GOLD)
	left.add_child(name_lbl)

	if ch.source_game != "":
		var src := Label.new()
		src.text = "From: %s" % ch.source_game
		src.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		src.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		src.custom_minimum_size = Vector2(CHAR_PORTRAIT_SIZE, 0)
		src.add_theme_font_size_override("font_size", 12)
		src.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		left.add_child(src)

	var hp := Label.new()
	hp.text = "❤ %d Health" % ch.base_max_hp
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.add_theme_font_size_override("font_size", 15)
	hp.add_theme_color_override("font_color", UITheme.DANGER.lerp(UITheme.TEXT, 0.35))
	left.add_child(hp)

	# RIGHT: what they play like.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Centred against the portrait rather than hung off the top of the panel: a
	# hero with two facts and one with five both sit beside their own picture.
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(right)

	var chips := _verb_chips(ch)
	if chips != null:
		right.add_child(_detail_head("Starting Verbs"))
		(chips as FlowContainer).alignment = FlowContainer.ALIGNMENT_BEGIN
		right.add_child(chips)

	if ch.description != "":
		var desc := Label.new()
		desc.text = ch.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", UITheme.TEXT.lerp(UITheme.TEXT_DIM, 0.3))
		right.add_child(desc)

	if ch.starting_items.size() > 0:
		right.add_child(HSeparator.new())
		right.add_child(_detail_head("Starting Items"))
		var items_lbl := Label.new()
		items_lbl.text = ", ".join(Data.item_names(ch.starting_items))
		items_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		items_lbl.add_theme_font_size_override("font_size", 12)
		items_lbl.add_theme_color_override("font_color", UITheme.TEXT.lerp(Color(0.7, 0.85, 0.95), 0.5))
		right.add_child(items_lbl)

	if ch.level_up_condition != "":
		right.add_child(HSeparator.new())
		right.add_child(_detail_head("Level Up"))
		var lu := Label.new()
		lu.text = ch.level_up_condition
		lu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lu.add_theme_font_size_override("font_size", 12)
		lu.add_theme_color_override("font_color", UITheme.TEXT.lerp(Color(0.7, 0.85, 0.95), 0.5))
		right.add_child(lu)
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			var reward := Label.new()
			reward.text = "→ %s" % ch.level_up_reward
			reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reward.add_theme_font_size_override("font_size", 12)
			reward.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.35))
			right.add_child(reward)

func _detail_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UITheme.ACCENT.lerp(UITheme.TEXT, 0.2))
	return l

# A centered wrap of the character's non-zero starting verbs as small pills, or
# null when the loadout is all-zero. The verbs come off CharacterData itself, so
# this and the Collection's stat rows cannot list different ones.
func _verb_chips(ch: CharacterData) -> Control:
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var any := false
	for v in ch.verb_loadout():
		any = true
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL_HI, 6, 4, 1, UITheme.BORDER))
		var pl := Label.new()
		pl.text = "%s %d" % [v[0], int(v[1])]
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", UITheme.ACCENT.lerp(UITheme.TEXT, 0.3))
		pill.add_child(pl)
		flow.add_child(pill)
	# The unrolled part of the loadout gets its own pill, tinted apart from the
	# fixed verbs and saying what it will become — "Random 2" beside a solid
	# "Bash 1" would otherwise read as a verb called Random.
	if ch.start_random > 0:
		any = true
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override("panel",
			UITheme.flat(UITheme.GOLD.lerp(UITheme.BG, 0.78), 6, 4, 1, UITheme.GOLD.lerp(UITheme.BORDER, 0.4)))
		var pl := Label.new()
		pl.text = "🎲 %d random" % ch.start_random
		pl.tooltip_text = ("%d point%s of Bash / Dash / Push / Transmute / Scramble / Bombs, "
			+ "rolled fresh when the run starts.") % [
				ch.start_random, "" if ch.start_random == 1 else "s"]
		pl.add_theme_font_size_override("font_size", 11)
		pl.add_theme_color_override("font_color", UITheme.GOLD)
		pill.add_child(pl)
		flow.add_child(pill)
	return flow if any else null

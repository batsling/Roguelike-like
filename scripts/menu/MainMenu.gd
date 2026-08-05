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
	%AtlasBtn.pressed.connect(_on_atlas)
	%TierListBtn.pressed.connect(_on_tier_list)
	%SettingsBtn.pressed.connect(_on_settings)
	%HowToPlayBtn.pressed.connect(_on_how_to_play)
	%ClearDataBtn.pressed.connect(_on_clear_data)

	_save_list_container.visible = false
	_refresh_continue_button()

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
# Layout (per UI pass): a four-column GRID of small icon tiles on the left, the
# selected hero's FULL portrait beside its full information on the right, and a
# Confirm button along the bottom. Selecting a tile only previews it; Confirm
# starts the run.
#
# The detail half NEVER scrolls: the portrait takes the left of it and every
# other fact is stacked to the RIGHT of the portrait rather than under it, which
# is what buys the room to fit a hero on one screen. See _fill_char_detail.
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
	cancel.pressed.connect(func(): root.queue_free())
	footer.add_child(cancel)
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
	var state := {"id": &"", "tiles": {}}
	var select := func(ch: CharacterData) -> void:
		state["id"] = ch.id
		for tid in state["tiles"]:
			state["tiles"][tid].call(tid == ch.id)
		_fill_char_detail(detail_box, ch)
		confirm.disabled = false
		confirm.text = "Confirm: %s" % ch.display_name

	var roster: Array = Data.all_characters2()
	for ch in roster:
		if ch is CharacterData:
			grid.add_child(_character_tile(ch, state, select))
	confirm.pressed.connect(func():
		if String(state["id"]) != "":
			_begin_run(StringName(state["id"])))

	# Preselect the first hero so the panel is never empty and Confirm is live.
	if not roster.is_empty() and roster[0] is CharacterData:
		select.call(roster[0])
	return root

# The roster board: four tiles per row, and the tile sized to suit that rather
# than the other way round — four 122px tiles ran past the grid's half of the
# panel, so the icon token gives up a little to buy the extra column.
const TILE_COLUMNS := 4
const TILE_SIZE := Vector2(108, 122)
const TILE_GAP := 10

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
		vb.add_child(_char_tex(tex, 76))
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
		var portrait := _char_tex(ch.portrait, CHAR_PORTRAIT_SIZE)
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
		var inames: Array = []
		for iid in ch.starting_items:
			var idd: ItemData = Data.get_item2(iid)
			if idd == null:
				idd = Data.get_item(iid)
			inames.append(idd.display_name if idd != null else String(iid))
		var items_lbl := Label.new()
		items_lbl.text = ", ".join(inames)
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

# The portrait's edge in the detail panel. Also the width its name / source /
# Health column is laid out to, so the two columns line up.
const CHAR_PORTRAIT_SIZE := 210

func _detail_head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UITheme.ACCENT.lerp(UITheme.TEXT, 0.2))
	return l

# A TextureRect that renders `tex` crisply when it's small pixel art scaled up
# (nearest-neighbour, no blur) and smoothly otherwise.
func _char_tex(tex: Texture2D, size: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: int = tex.get_width() if tex != null else 0
	var h: int = tex.get_height() if tex != null else 0
	if w > 0 and h > 0 and (w < size or h < size):
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return tr

# A centered wrap of the character's non-zero starting verbs as small pills, or
# null when the loadout is all-zero.
func _verb_chips(ch: CharacterData) -> Control:
	var verbs := [
		["Bash", ch.start_bash], ["Dash", ch.start_dash], ["Push", ch.start_push],
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
		none.add_theme_font_size_override("font_size", 12)
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
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", UITheme.GOLD if is_auto else UITheme.TEXT)
	text.add_child(title)
	var sub := Label.new()
	sub.text = _save_subtitle(entry)
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	text.add_child(sub)

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

# The Atlas — the whole influence graph as a star chart. Needs the baked layout
# (tools/bake_atlas.py); without it we say so plainly rather than opening an
# empty sky.
func _on_atlas() -> void:
	if AtlasView.load_layout() == null:
		_show_coming_soon("Atlas",
			"The star chart hasn't been generated yet. Run tools/bake_atlas.py to build it.")
		return
	AtlasView.open(_modal_layer)

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
		_populate_save_list()
		_refresh_continue_button()
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

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
# Layout (per UI pass): a GRID of small icon tiles on the left, the selected
# hero's FULL portrait + full information on the right, and a Confirm button along
# the bottom. Selecting a tile only previews it; Confirm starts the run.
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
	panel.custom_minimum_size = Vector2(880, 600)
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

	var grid_scroll := ScrollContainer.new()
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.custom_minimum_size = Vector2(420, 460)
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid_scroll)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(grid)

	var detail_wrap := PanelContainer.new()
	detail_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 12, 14, 1))
	detail_wrap.custom_minimum_size = Vector2(400, 0)
	detail_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail_wrap)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_wrap.add_child(detail_scroll)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 8)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_box.custom_minimum_size = Vector2(372, 0)
	detail_scroll.add_child(detail_box)

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

# One roster tile = the character's ICON (small token, falling back to the full
# portrait) with the name below. Clicking previews the hero via `select`; the
# stored callback re-styles the tile for the selected / unselected state.
func _character_tile(ch: CharacterData, state: Dictionary, select: Callable) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(122, 132)
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
		vb.add_child(_char_tex(tex, 84))
	var name_lbl := Label.new()
	name_lbl.text = ch.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(106, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	vb.add_child(name_lbl)
	return tile

# Fill the right-hand detail panel with the selected hero's FULL portrait and all
# of its information (source, Health, verbs, description, starting items, level-up).
func _fill_char_detail(box: VBoxContainer, ch: CharacterData) -> void:
	for c in box.get_children():
		c.queue_free()
	if ch.portrait != null:
		var portrait := _char_tex(ch.portrait, 220)
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(portrait)

	var name_lbl := Label.new()
	name_lbl.text = ch.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", UITheme.GOLD)
	box.add_child(name_lbl)

	if ch.source_game != "":
		var src := Label.new()
		src.text = "From: %s" % ch.source_game
		src.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		src.add_theme_font_size_override("font_size", 12)
		src.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		box.add_child(src)

	var hp := Label.new()
	hp.text = "❤ %d Health" % ch.base_max_hp
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.add_theme_font_size_override("font_size", 15)
	hp.add_theme_color_override("font_color", UITheme.DANGER.lerp(UITheme.TEXT, 0.35))
	box.add_child(hp)

	var chips := _verb_chips(ch)
	if chips != null:
		box.add_child(chips)

	if ch.description != "":
		box.add_child(HSeparator.new())
		var desc := Label.new()
		desc.text = ch.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", UITheme.TEXT.lerp(UITheme.TEXT_DIM, 0.3))
		box.add_child(desc)

	if ch.starting_items.size() > 0:
		box.add_child(HSeparator.new())
		box.add_child(_detail_head("Starting Items"))
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
		box.add_child(items_lbl)

	if ch.level_up_condition != "":
		box.add_child(HSeparator.new())
		box.add_child(_detail_head("Level Up"))
		var lu := Label.new()
		lu.text = ch.level_up_condition
		lu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lu.add_theme_font_size_override("font_size", 12)
		lu.add_theme_color_override("font_color", UITheme.TEXT.lerp(Color(0.7, 0.85, 0.95), 0.5))
		box.add_child(lu)
		if ch.level_up_reward != "" and ch.level_up_reward.to_upper() != "N/A":
			var reward := Label.new()
			reward.text = "→ %s" % ch.level_up_reward
			reward.add_theme_font_size_override("font_size", 12)
			reward.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT, 0.35))
			box.add_child(reward)

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

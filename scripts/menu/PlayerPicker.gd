class_name PlayerPicker
extends Control

# THE FIRST PICK OF A RUN (docs/players-design.md; the owner, 13 Nov 2026): who is
# playing — the PLAYER, which carries the run's mechanics — and at which FRACTURE,
# because the ladder belongs to the player now. Confirm hands over to the
# character select (CharacterPicker), which is the second pick.
#
# The same shape as CharacterPicker on purpose: a column of tiles on the left, the
# selected player's details on the right, the Fracture row under them, and Cancel /
# Next along the bottom. Selecting a tile only previews it.
#
# A player with no art (the basic player) is drawn as its NAME in the tile and in
# the detail panel's picture box: the owner asked for "Basic" to be said rather
# than drawn until there is art.

# Next pressed; carries the id of the player the run should open as. The Fracture
# was saved as the player's pick when it was clicked, so nothing else is passed.
signal chosen(player_id: StringName)

const TILE_SIZE := Vector2(150, 150)
const PORTRAIT := 200
const TILE_ART := 96
# A tile in the Hat strip (docs/customization.md §7), the character picker's size.
const LOOK_TILE := 48

var _roster: Array[PlayerData] = []
var _select: Callable = Callable()
var _state: Dictionary = {}
var _fracture_row: HBoxContainer = null
var _hat_box: VBoxContainer = null

static func open(parent: Node) -> PlayerPicker:
	var picker := PlayerPicker.new()
	parent.add_child(picker)
	return picker

func _ready() -> void:
	# `set_anchors_and_offsets_preset`, as CharacterPicker._ready says why.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.shared()
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1080, 560)
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG,
		UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 12, 22, 2))
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Choose Your Player"
	title.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)
	var tiles := VBoxContainer.new()
	tiles.add_theme_constant_override("separation", UITheme.GAP)
	body.add_child(tiles)
	var detail_wrap := PanelContainer.new()
	detail_wrap.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.PANEL,
		UITheme.BORDER, 12, 14, 1))
	detail_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail_wrap)
	var detail_col := VBoxContainer.new()
	detail_col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	detail_wrap.add_child(detail_col)
	var detail := HBoxContainer.new()
	detail.name = "Detail"
	detail.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_col.add_child(detail)
	# THE HAT, a band across the foot of the panel like the character picker's
	# costumes (_hat_row): the same tiles as the Customization screen's Hats tab.
	_hat_box = VBoxContainer.new()
	_hat_box.name = "Hats"
	detail_col.add_child(_hat_box)

	# THE FRACTURE ROW (docs/fracture-design.md §4), under the player it belongs to.
	_fracture_row = HBoxContainer.new()
	_fracture_row.name = "FractureRow"
	_fracture_row.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	vbox.add_child(_fracture_row)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	vbox.add_child(footer)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(150, 44)
	cancel.pressed.connect(queue_free)
	footer.add_child(cancel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var confirm := Button.new()
	confirm.name = "Next"
	confirm.text = "Next"
	confirm.custom_minimum_size = Vector2(220, 44)
	confirm.add_theme_stylebox_override("normal", UITheme.accent_box(UITheme.ACCENT, UITheme.PANEL_HI, 8))
	confirm.add_theme_color_override("font_color", UITheme.GOLD)
	confirm.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
	footer.add_child(confirm)

	var state := {"id": &"", "tiles": {}, "arts": {}}
	_state = state
	var select := func(pl: PlayerData) -> void:
		state["id"] = pl.id
		for tid in state["tiles"]:
			state["tiles"][tid].call(tid == pl.id)
		_fill_detail(detail, pl)
		_fill_hat_row(detail, pl)
		_fill_fracture_row(pl)
		var locked: bool = Achievements.player_locked(pl.id)
		confirm.disabled = locked
		confirm.tooltip_text = ("%s is locked. See Achievements." if locked
			else "Play as %s, then choose a character") % pl.display_name
	_select = select
	for pl in Data.all_players():
		if pl is PlayerData:
			_roster.append(pl)
	for pl in _roster:
		tiles.add_child(_tile(pl, state, select))
	confirm.pressed.connect(func():
		if String(state["id"]) != "":
			_confirm(StringName(state["id"])))

	# Preselect the last player played if they can still be, else the first.
	var first: PlayerData = null
	for pl in _roster:
		if not Achievements.player_locked(pl.id):
			first = pl
			break
	var last := StringName(GameStats.last_player)
	for pl in _roster:
		if pl.id == last and not Achievements.player_locked(pl.id):
			first = pl
	if first != null:
		select.call(first)
	elif not _roster.is_empty():
		select.call(_roster[0])

# Select `id`, as a click on its tile would. For tests and the menu.
func select_player(id: StringName) -> void:
	for pl in _roster:
		if pl.id == id and _select.is_valid():
			_select.call(pl)

func selected_id() -> StringName:
	return StringName(_state.get("id", &""))

func _confirm(player_id: StringName) -> void:
	GameStats.last_player = String(player_id)
	chosen.emit(player_id)
	queue_free()

# The player's picture — in their hat, unless they are still locked — or, with no
# art, their NAME in the picture's box.
static func picture(pl: PlayerData, size: int, locked: bool = false) -> Control:
	if pl.portrait != null:
		var tex := UITheme.crisp_tex(pl.portrait if locked else pl.shown_portrait(), size)
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if locked:
			tex.modulate = Color(0, 0, 0, 0.8)
		return tex
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(size, size)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.WELL, UITheme.BORDER, 8, 4, 1))
	var word := Label.new()
	word.name = "NameArt"
	word.text = pl.display_name
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.add_theme_font_size_override("font_size",
		UITheme.FONT_HERO if size >= PORTRAIT else UITheme.FONT_TITLE_LG)
	word.add_theme_color_override("font_color", UITheme.TEXT_FAINT if locked else UITheme.GOLD)
	box.add_child(word)
	return box

func _tile(pl: PlayerData, state: Dictionary, select: Callable) -> Control:
	var tile := PanelContainer.new()
	tile.name = "Tile_%s" % String(pl.id)
	tile.custom_minimum_size = TILE_SIZE
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 8, 1)
	var selected := UITheme.accent_box(UITheme.GOLD, UITheme.PANEL_HI, 10)
	tile.add_theme_stylebox_override("panel", normal)
	state["tiles"][pl.id] = func(is_sel: bool) -> void:
		tile.add_theme_stylebox_override("panel", selected if is_sel else normal)
	tile.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			select.call(pl))
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	tile.add_child(vb)
	var locked: bool = Achievements.player_locked(pl.id)
	var art := picture(pl, TILE_ART, locked)
	vb.add_child(art)
	if art is TextureRect and not locked:
		state["arts"][pl.id] = art
	if pl.portrait != null:
		var name_lbl := Label.new()
		name_lbl.text = pl.display_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		vb.add_child(name_lbl)
	if locked:
		tile.tooltip_text = "Locked. %s" % Achievements.for_player(pl.id).description
	return tile

func _fill_detail(box: HBoxContainer, pl: PlayerData) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var locked: bool = Achievements.player_locked(pl.id)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(left)
	left.add_child(picture(pl, PORTRAIT, locked))
	if pl.portrait != null:
		var name_lbl := Label.new()
		name_lbl.text = pl.display_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
		name_lbl.add_theme_color_override("font_color", UITheme.GOLD)
		left.add_child(name_lbl)

	var right := VBoxContainer.new()
	right.name = "Facts"
	right.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(right)
	if locked:
		var a: AchievementData = Achievements.for_player(pl.id)
		right.add_child(_line("Locked", UITheme.FONT_SUB, UITheme.ACCENT))
		right.add_child(_line(a.description, UITheme.FONT_LEAD, UITheme.TEXT))
		right.add_child(_line(("Best in one run: %d of %d" if a.is_run_scope() else "So far: %d of %d")
			% [Achievements.progress(a), a.goal], UITheme.FONT_LEAD,
			Achievements.RUN_COLOR if a.is_run_scope() else Achievements.LIFETIME_COLOR))
		return
	if pl.description != "":
		right.add_child(_line(pl.description, UITheme.FONT_TEXT,
			UITheme.TEXT.lerp(UITheme.TEXT_DIM, 0.3)))
	right.add_child(HSeparator.new())
	if pl.mechanics.is_empty():
		right.add_child(_line("No extra mechanics: the game as it is.", UITheme.FONT_BODY,
			UITheme.TEXT_DIM))
	for m in pl.mechanics:
		var head := _line(PlayerData.mechanic_name(m), UITheme.FONT_LABEL,
			UITheme.ACCENT.lerp(UITheme.TEXT, 0.2))
		head.name = "Mechanic_%s" % String(m)
		right.add_child(head)
		right.add_child(_line(PlayerData.mechanic_line(m), UITheme.FONT_BODY,
			UITheme.TEXT.lerp(Color(0.7, 0.85, 0.95), 0.5)))

# The Hat strip for `pl`: No hat, 🎲 Random and every hat, locked ones as
# silhouettes. Only for a player who is unlocked and has a spot for one (the basic
# player has no picture to wear it on). A pick redraws the portrait and the tile.
func _fill_hat_row(detail: HBoxContainer, pl: PlayerData) -> void:
	for c in _hat_box.get_children():
		_hat_box.remove_child(c)
		c.queue_free()
	if pl.portrait == null or pl.hat_spot.z <= 0.0 or Achievements.player_locked(pl.id) \
			or CosmeticCatalog.hats().is_empty():
		return
	_hat_box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.name = "Slot_hat"
	row.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	_hat_box.add_child(row)
	var lbl := Label.new()
	lbl.text = "Hat"
	lbl.custom_minimum_size = Vector2(34, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(lbl)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, LOOK_TILE + UITheme.GAP_WIDE)
	row.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	scroll.add_child(strip)
	var on_change := func() -> void:
		(func() -> void:
			var arts: Dictionary = _state.get("arts", {})
			if arts.has(pl.id) and is_instance_valid(arts[pl.id]):
				var tr := arts[pl.id] as TextureRect
				tr.texture = pl.shown_portrait()
				UITheme.apply_crisp(tr, tr.texture)
			var keep: float = scroll.scroll_horizontal
			_fill_detail(detail, pl)
			_fill_hat_row(detail, pl)
			_restore_scroll.call_deferred(keep)).call_deferred()
	for t in CustomizeScreen.hat_tiles(pl, LOOK_TILE, on_change):
		strip.add_child(t)

# A pick rebuilds the strip; put it back where it was scrolled to, not at the start.
func _restore_scroll(x: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame   # once the new strip has been laid out
	if not is_instance_valid(_hat_box):
		return
	for c in _hat_box.find_children("*", "ScrollContainer", true, false):
		(c as ScrollContainer).scroll_horizontal = int(x)

func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# The row of Fracture levels for `pl`: a button per level, the one that will be
# played lit, the locked ones greyed out, and the selected level's changes on the
# right. Each button's hover is the whole ladder up to it. Choosing one saves it
# as the player's pick, which is the level their next run starts at
# (GameLoop2.start_run reads it).
func _fill_fracture_row(pl: PlayerData) -> void:
	if _fracture_row == null:
		return
	for c in _fracture_row.get_children():
		_fracture_row.remove_child(c)
		c.queue_free()
	var unlocked: int = GameStats.player_fracture_unlocked(pl.id)
	var pick: int = GameStats.player_fracture_pick(pl.id)
	var head := Label.new()
	head.text = "%s Fracture" % Fracture.GLYPH
	head.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	head.add_theme_color_override("font_color", Fracture.COLOR)
	head.tooltip_text = ("Harder runs, unlocked one at a time by winning at the "
		+ "highest one this player has. Each level keeps every level below it.")
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	_fracture_row.add_child(head)
	for lv in range(Fracture.MAX + 1):
		var b := Button.new()
		b.name = "Fracture%d" % lv
		b.text = str(lv)
		b.custom_minimum_size = Vector2(34, 32)
		b.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
		b.disabled = lv > unlocked
		b.tooltip_text = Fracture.ladder_text(lv) if lv <= unlocked else (
			"Locked: win a run as %s at Fracture %d to open it." % [pl.display_name, lv - 1]
			if lv == unlocked + 1 else "Locked.")
		if lv == pick:
			b.add_theme_stylebox_override("normal", UITheme.accent_box(Fracture.COLOR, UITheme.PANEL_HI, 6))
			b.add_theme_stylebox_override("hover", UITheme.accent_box(Fracture.COLOR, UITheme.PANEL_HI, 6))
		number_fracture_button(b, lv, lv == pick, lv <= unlocked)
		b.pressed.connect(func():
			GameStats.set_player_fracture_pick(pl.id, lv)
			_fill_fracture_row(pl))
		_fracture_row.add_child(b)
	var what := Label.new()
	what.name = "FractureNote"
	what.text = (Fracture.change_text(pick) if pick > 0 else "The game as it is.") \
		if unlocked > 0 else "Win a run as %s to unlock Fracture 1." % pl.display_name
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	what.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_fracture_row.add_child(what)

# THE NUMBER ON A FRACTURE BUTTON, IN THE NUMBERS THE PLAYER HAS UNLOCKED (the
# owner, 11 Nov 2026): each level spelled from `TitleLetters.available()`, seeded
# by the level so a number keeps its look from one visit to the next. The digits
# are a picture, so the hover only brightens them rather than erasing the text in
# the hover box's own colour; where no picture can be made the text is kept, with
# every state's colour set.
const FRACTURE_DIGIT := 17.0
const FRACTURE_STATES := ["font_color", "font_hover_color", "font_pressed_color",
	"font_focus_color", "font_hover_pressed_color", "font_disabled_color"]

static func number_fracture_button(b: Button, lv: int, picked: bool, open: bool) -> void:
	var rest: Color = Fracture.COLOR if picked else (
		UITheme.TEXT if open else UITheme.TEXT_FAINT)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fracture-number-%d" % lv)
	var word := TitleLetters.make(str(lv), FRACTURE_DIGIT, rng, false,
		b.custom_minimum_size.x - 8.0)
	if word.placed.size() != str(lv).length():
		word.free()
		for state in FRACTURE_STATES:
			b.add_theme_color_override(state, rest)
		b.add_theme_color_override("font_hover_color", rest.lerp(Color.WHITE, 0.5))
		return
	word.name = "Digits"
	word.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(word)
	for state in FRACTURE_STATES:
		b.add_theme_color_override(state, Color(0, 0, 0, 0))
	var dim: Color = Color(1, 1, 1, 1.0 if picked else (0.8 if open else 0.3))
	word.modulate = dim
	if open:
		b.mouse_entered.connect(func(): word.modulate = Color.WHITE)
		b.mouse_exited.connect(func(): word.modulate = dim)

class_name TierListScreen
extends Control

# Full-screen tier-list board, backed by the cross-run TierList store. Opened
# from the main menu and the in-run pause menu. The player drags beaten games
# between S/A/B/C/D/F rows and an "Unranked" tray; tier labels are editable.
#
# CLICKING a game opens it in the detail panel down the right-hand side — the
# score and notes you wrote when you beat it, your lifetime record there, the
# enemies you've killed in it, and the buttons to re-rate it or move it a tier
# without dragging. That panel replaced a hover tooltip: a tooltip could only
# ever hold three lines of text, it couldn't be clicked, and it made the notes
# you wrote about a game the one thing on this screen you had to hunt for.
#
# Built entirely in code (no scene dependency) and runs PROCESS_MODE_ALWAYS so
# it works on top of a paused run. Mirrors Collection.open()'s overlay pattern,
# and dresses in UITheme so it reads as the same application as the Collection
# and the star chart rather than as the flat grey box it used to be.

# Row accent colors, S..F. Cycled if the player adds more tiers than this. This
# is the tier-list idiom and stays loud on purpose — it's the one place in the
# game where the colour IS the content.
const TIER_COLORS := [
	Color(0.95, 0.42, 0.42), Color(0.97, 0.66, 0.4), Color(0.97, 0.85, 0.42),
	Color(0.66, 0.88, 0.5), Color(0.5, 0.78, 0.95), Color(0.76, 0.6, 0.95),
]
const UNRANKED_COLOR := Color(0.36, 0.32, 0.26)

const TILE_SIZE := Vector2(88, 104)
const LABEL_CELL := Vector2(96, 100)
const DETAIL_W := 306.0

# THE WHOLE BOARD, ON ONE SCREEN. A tier list you have to scroll is a tier list
# you cannot compare, which is the only thing it is for: S is a claim about A, and
# an S row you can see while an A row is off the bottom of the window is two lists
# rather than one. So the tiles SHRINK to fit instead — the board is re-fitted
# every time it is rebuilt and every time the window changes size, and the scroll
# is left in place as the floor's safety net rather than as the normal way to read
# the screen.
#
# `MIN_SCALE` is where shrinking stops. A quarter size holds about 300 beaten
# games on a 720p window, which is the whole board for anyone who has not played
# most of the roster; past that a cover is a smudge and shrinking further would
# buy room by making the thing unreadable, so a collection that large scrolls.
const MIN_SCALE := 0.26
const SCALE_STEP := 0.02
# The gaps the fit has to account for, all of them read back out of _build_zone /
# _build_tier_row below rather than guessed: the tile grid's own separation, the
# gap between a row's label cell and its slab, the gap between rows, and the
# slab's inner padding.
const TILE_SEP := 6.0
const ROW_SEP := 8.0
const ROWS_SEP := 8.0
const ZONE_PAD := 5.0
# Under this, the ⚔ / 👑 badge comes off the tile: below about half size it is a
# line of text that has stopped shrinking (the font has a floor) eating the height
# the cover needs to stay recognisable, and the same counts are on the detail panel
# a click away.
const BADGE_MIN_SCALE := 0.45

var _rows_box: VBoxContainer
var _detail_box: VBoxContainer
var _scroll: ScrollContainer
# How much of full size the board is currently drawn at (1.0 = the sizes above).
var _scale: float = 1.0
# The game whose card is open on the right. Kept across refreshes so dropping a
# game into a new tier doesn't close what you were reading.
var _selected: StringName = &""

static func open(parent: Node) -> TierListScreen:
	var s := TierListScreen.new()
	parent.add_child(s)
	return s

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.shared()
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	TierList.changed.connect(_refresh)
	_build_shell()
	_refresh()

func _fit_to_viewport() -> void:
	# Offsets as well as anchors, and no manual size — the same fit Collection
	# uses, which this screen's overlay pattern otherwise mirrors. Setting `size`
	# on a node whose anchors aren't equal-opposite is overridden after _ready
	# anyway, and Godot logs an error for it; that error surfaced the moment this
	# screen was opened as a child of the overworld rather than the main menu.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	queue_free()

# ------------------------------------------------------------------
# Shell
# ------------------------------------------------------------------

func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 36
	panel.offset_top = 32
	panel.offset_right = -36
	panel.offset_bottom = -32
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG_DEEP, UITheme.BORDER, 10, 18, 1))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Tier List"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	header.add_child(title)

	var hint := Label.new()
	hint.text = "Click a game for your notes  •  drag it to move tiers  •  click a tier name to rename"
	hint.add_theme_font_size_override("font_size", 13)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(40, 36)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Board on the left, the clicked game's card on the right — the same
	# master/detail shape the Collection uses, so the two screens read alike.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The board is fitted to the space this container actually got, which is only
	# known after layout — so the first _refresh draws at an estimate and this
	# corrects it, here and on every window resize afterwards.
	_scroll.resized.connect(_refit)
	body.add_child(_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", int(ROWS_SEP))
	_scroll.add_child(_rows_box)

	body.add_child(_build_detail_panel())

func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(DETAIL_W, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 8, 12, 1))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	# A margin inside the scroll, not a narrower box: a ScrollContainer hands its
	# child the FULL width and then draws the scrollbar on top of it, which put
	# every right-aligned value ("S", "3 times") half under the bar.
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_right", 14)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)

	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 7)
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.custom_minimum_size = Vector2(DETAIL_W - 62.0, 0)
	inset.add_child(_detail_box)
	return panel

# ------------------------------------------------------------------
# Population
# ------------------------------------------------------------------

func _refresh() -> void:
	if _rows_box == null:
		return
	_scale = _fit_scale()
	for c in _rows_box.get_children():
		# DETACHED as well as freed: queue_free leaves the node in the tree until
		# the end of the frame, and two refreshes in one frame (a drop that also
		# opens the detail panel) would otherwise draw every row twice.
		_rows_box.remove_child(c)
		c.queue_free()

	for i in TierList.tier_names.size():
		var placed: Array = TierList.tiers[i] if i < TierList.tiers.size() else []
		_rows_box.add_child(_build_tier_row(i, TierList.tier_names[i], placed))

	# Unranked tray sits at the bottom, visually separated.
	_rows_box.add_child(HSeparator.new())
	_rows_box.add_child(_build_unranked_row(TierList.unranked))
	_show_detail(_selected)

# ------------------------------------------------------------------
# Fitting the board to the window (see MIN_SCALE)
# ------------------------------------------------------------------

# Re-fit after a resize. Rebuilds only when the answer actually moved, so dragging
# a window edge doesn't rebuild forty tiles per pixel.
func _refit() -> void:
	if _rows_box == null:
		return
	if absf(_fit_scale() - _scale) > 0.005:
		_refresh()

# The largest scale the whole board fits the space at, down to MIN_SCALE. Walks
# down in fixed steps rather than solving it: the height is a STAIRCASE in the
# scale (one fewer tile per line and a row gains a whole extra line), so there is
# no closed form to solve and a bisection would land on the wrong side of a step.
func _fit_scale() -> float:
	var space: Vector2 = _board_space()
	if space.x < 120.0 or space.y < 120.0:
		return 1.0
	var s: float = 1.0
	while s > MIN_SCALE:
		if _board_height(space.x, s) <= space.y:
			return s
		s -= SCALE_STEP
	return MIN_SCALE

# The room the rows have. The ScrollContainer's own size once it has been laid out
# — it is the thing the rows go inside, so no arithmetic about headers and margins
# can get out of step with the shell. Before the first layout it has no size yet,
# and the viewport-minus-chrome estimate below stands in for one frame.
func _board_space() -> Vector2:
	if _scroll != null and _scroll.size.x > 120.0 and _scroll.size.y > 120.0:
		return _scroll.size
	var vp: Vector2 = get_viewport_rect().size
	# 36/32 panel offsets and 18 of panel padding on each side (see _build_shell),
	# the detail panel and its gap, and about 60px of header above the body.
	return Vector2(vp.x - 108.0 - DETAIL_W - 14.0, vp.y - 100.0 - 60.0)

# How tall the whole board comes out at scale `s` in a `width`-wide space. Mirrors
# what the builders below actually construct: a row is its label cell beside a slab
# of wrapped tiles, and the slab's height is however many lines the tiles wrap onto.
func _board_height(width: float, s: float) -> float:
	var tile: Vector2 = TILE_SIZE * s
	var zone_w: float = width - LABEL_CELL.x * s - ROW_SEP - ZONE_PAD * 2.0
	var per_line: int = maxi(1, int(floor((zone_w + TILE_SEP) / (tile.x + TILE_SEP))))
	var total: float = 0.0
	var rows: Array = []
	for i in TierList.tier_names.size():
		rows.append(TierList.tiers[i] if i < TierList.tiers.size() else [])
	rows.append(TierList.unranked)
	for row in rows:
		var lines: int = maxi(1, ceili(float((row as Array).size()) / float(per_line)))
		var slab: float = lines * tile.y + (lines - 1) * TILE_SEP + ZONE_PAD * 2.0
		total += maxf(slab, LABEL_CELL.y * s)
	# The gap under each row, plus the separator above the Unranked tray.
	return total + ROWS_SEP * (rows.size() + 1) + 8.0

# A scaled font size that never drops below what can be read at all.
func _font(size: float, floor_px: int = 8) -> int:
	return maxi(floor_px, int(round(size * _scale)))

func _build_tier_row(index: int, label_text: String, game_ids: Array) -> Control:
	var color: Color = TIER_COLORS[index % TIER_COLORS.size()]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label_cell := PanelContainer.new()
	label_cell.custom_minimum_size = LABEL_CELL * _scale
	label_cell.add_theme_stylebox_override("panel",
		UITheme.flat(color, 6, maxi(2, _font(4, 2)), 2, color.lightened(0.25)))

	var name_edit := LineEdit.new()
	name_edit.text = label_text
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.flat = true
	name_edit.add_theme_font_size_override("font_size", _font(26, 11))
	name_edit.add_theme_color_override("font_color", Color(0.08, 0.06, 0.05))
	name_edit.add_theme_color_override("caret_color", Color(0.08, 0.06, 0.05))
	name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_edit.tooltip_text = "Rename this tier"
	name_edit.text_submitted.connect(func(t: String):
		name_edit.release_focus()
		TierList.set_tier_name(index, t))
	name_edit.focus_exited.connect(func(): TierList.set_tier_name(index, name_edit.text))
	label_cell.add_child(name_edit)
	row.add_child(label_cell)

	row.add_child(_build_zone(index, game_ids, color))
	return row

func _build_unranked_row(game_ids: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label_cell := PanelContainer.new()
	label_cell.custom_minimum_size = LABEL_CELL * _scale
	label_cell.add_theme_stylebox_override("panel",
		UITheme.flat(UNRANKED_COLOR, 6, maxi(2, _font(4, 2)), 1, UITheme.BORDER))
	var lbl := Label.new()
	lbl.text = "Unranked"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", _font(15, 9))
	lbl.add_theme_color_override("font_color", UITheme.TEXT)
	label_cell.add_child(lbl)
	row.add_child(label_cell)

	row.add_child(_build_zone(-1, game_ids, UITheme.BORDER))
	return row

# The drop target for one row, on its own recessed slab so an empty tier still
# looks like somewhere a game can be put down.
func _build_zone(tier_index: int, game_ids: Array, accent: Color) -> Control:
	var slab := PanelContainer.new()
	slab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slab.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG, 6, int(ZONE_PAD), 1, accent.lerp(UITheme.BG, 0.62)))
	var zone := DropZone.new(self, tier_index, TILE_SIZE.y * _scale)
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in game_ids:
		zone.add_child(_build_tile(StringName(id), tier_index))
	slab.add_child(zone)
	return slab

func _build_tile(game_id: StringName, tier_index: int) -> Control:
	var gd: GameData = Data.get_game(game_id)
	var beaten: int = GameStats.beaten_count(game_id)
	var amulets: int = GameStats.amulet_wins(game_id)
	var chosen: bool = game_id == _selected
	var tile := Tile.new(self, game_id, tier_index)
	var size: Vector2 = TILE_SIZE * _scale
	tile.custom_minimum_size = size

	# Every inner measurement is derived from the tile's own box rather than scaled
	# on its own, so the pieces still ADD UP to the size the fit was computed
	# against: a child whose minimum overflowed would grow the PanelContainer and
	# the board would come out taller than the space it was fitted to.
	var pad: int = maxi(1, int(round(3.0 * _scale)))
	var badge_font: int = _font(10, 8)
	var show_badge: bool = _scale >= BADGE_MIN_SCALE
	var art_h: float = size.y - pad * 2 - (badge_font + 4 + 2 if show_badge else 0)
	var art_w: float = size.x - pad * 2

	# The open card's game is ringed in gold, so the board and the panel agree
	# about which game is being talked about.
	var edge: Color = UITheme.GOLD if chosen else UITheme.BORDER
	tile.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.PANEL_HI if chosen else UITheme.PANEL, 5, pad,
			2 if chosen else 1, edge))

	# A VBox is a Container (legal single child of PanelContainer) holding the
	# cover above a beaten-count badge. All children IGNORE the mouse so the
	# tile itself stays the drag source AND the click target.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)

	if gd != null and gd.cover_image != null:
		var tex := TextureRect.new()
		tex.texture = gd.cover_image
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.custom_minimum_size = Vector2(art_w, art_h)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tex)
	else:
		var name_lbl := Label.new()
		name_lbl.text = gd.display_name if gd != null else String(game_id)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", _font(11, 8))
		name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
		name_lbl.custom_minimum_size = Vector2(art_w, art_h)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(name_lbl)

	# The badge comes off a heavily-shrunk board (BADGE_MIN_SCALE): the cover is
	# what identifies a game and the counts are on the detail panel either way.
	if show_badge:
		var badge := Label.new()
		badge.text = ("⚔ %d  👑 %d" % [beaten, amulets]) if amulets > 0 else ("⚔ %d" % beaten)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.clip_text = true
		badge.add_theme_font_size_override("font_size", badge_font)
		badge.add_theme_color_override("font_color",
			UITheme.GOLD if beaten > 0 or amulets > 0 else UITheme.TEXT_FAINT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(badge)

	tile.tooltip_text = "%s — ⚔ %d beaten%s.\nClick for your notes, drag to re-tier." % [
		gd.display_name if gd != null else String(game_id), beaten,
		"  ·  👑 %d" % amulets if amulets > 0 else ""]
	return tile

# ------------------------------------------------------------------
# The detail panel — what a click on a tile opens
# ------------------------------------------------------------------

# Public: this is what a Tile calls when it's clicked, and what a test calls to
# ask for the same thing.
func select_game(game_id: StringName) -> void:
	if _selected == game_id:
		return
	_selected = game_id
	_refresh()

func selected_game() -> StringName:
	return _selected

func _show_detail(game_id: StringName) -> void:
	if _detail_box == null:
		return
	for c in _detail_box.get_children():
		_detail_box.remove_child(c)
		c.queue_free()
	if game_id == &"":
		var placeholder := Label.new()
		placeholder.text = "Pick a game to see the score and notes you left on it."
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.add_theme_font_size_override("font_size", 13)
		placeholder.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		_detail_box.add_child(placeholder)
		return

	var gd: GameData = Data.get_game(game_id)
	var name_text: String = gd.display_name if gd != null else String(game_id)

	var title := Label.new()
	title.text = name_text
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(title)

	if gd != null and gd.cover_image != null:
		var art := AtlasView.card_art(gd.cover_image, DETAIL_W - 60.0, 210.0)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_detail_box.add_child(art)

	if gd != null:
		var meta: Array = []
		if gd.year > 0:
			meta.append(str(gd.year))
		meta.append(RunGraph.type_label(gd.type))
		var chip := Label.new()
		chip.text = "  •  ".join(meta).to_upper()
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", RunGraph.type_color(gd.type))
		_detail_box.add_child(chip)

	# Where it sits, and what you said about it.
	var tier_i: int = TierList.tier_of(game_id)
	_detail_box.add_child(_fact("Tier",
		TierList.tier_names[tier_i] if tier_i >= 0 and tier_i < TierList.tier_names.size()
		else "Unranked"))
	var rating: Dictionary = TierList.get_rating(game_id)
	if rating.is_empty():
		_detail_box.add_child(_note("You haven't scored this one yet."))
	else:
		_detail_box.add_child(_fact("Your score", "%d / 10" % int(rating.get("score", 0))))
		var notes := String(rating.get("notes", "")).strip_edges()
		if notes != "":
			_detail_box.add_child(_heading("What you wrote"))
			_detail_box.add_child(_note(notes, UITheme.TEXT))

	_detail_box.add_child(HSeparator.new())
	var beaten: int = GameStats.beaten_count(game_id)
	_detail_box.add_child(_fact("⚔ Beaten",
		("%d time%s" % [beaten, "" if beaten == 1 else "s"]) if beaten > 0 else "never"))
	var amulets: int = GameStats.amulet_wins(game_id)
	if amulets > 0:
		_detail_box.add_child(_fact("👑 Amulet won",
			"%d run%s" % [amulets, "" if amulets == 1 else "s"]))

	var fought: Array = GameStats.enemies_for(game_id)
	if not fought.is_empty():
		_detail_box.add_child(_heading("Enemies you've beaten here (%d)" % fought.size()))
		for e in fought:
			var ed: GoalEnemyData = Data.get_goal_enemy_any(StringName(e["id"]))
			_detail_box.add_child(_fact(
				ed.display_name if ed != null else String(e["id"]),
				"x%d" % int(e["beaten"])))

	# Moving a game without dragging it. The board is a drag toy and stays one,
	# but a tier is a decision and shouldn't need a steady hand to record.
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(_heading("Move to"))
	_detail_box.add_child(_tier_buttons(game_id, tier_i))

	var rate := Button.new()
	rate.text = "✎  Score and notes" if rating.is_empty() else "✎  Edit score and notes"
	rate.add_theme_font_size_override("font_size", 12)
	rate.pressed.connect(func(): _open_rating(game_id, gd))
	_detail_box.add_child(rate)

	if gd != null and gd.has_launch_target():
		var play := Button.new()
		play.text = "▶  Play the real game"
		play.add_theme_font_size_override("font_size", 12)
		play.pressed.connect(func(): gd.launch())
		_detail_box.add_child(play)

# One button per tier plus the Unranked tray; the tier the game is already in is
# disabled rather than hidden, so the row doesn't reshuffle as you move it.
func _tier_buttons(game_id: StringName, current_tier: int) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for i in TierList.tier_names.size():
		flow.add_child(_move_button(TierList.tier_names[i], game_id, i, i == current_tier,
			TIER_COLORS[i % TIER_COLORS.size()]))
	flow.add_child(_move_button("Unranked", game_id, -1, current_tier < 0, UNRANKED_COLOR))
	return flow

func _move_button(text: String, game_id: StringName, tier: int, here: bool,
		color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = here
	b.custom_minimum_size = Vector2(0, 28)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", color)
	b.tooltip_text = "Already there" if here else "Move %s to %s" % [
		Data.get_game(game_id).display_name if Data.get_game(game_id) != null
			else String(game_id), text]
	b.pressed.connect(func(): TierList.place(game_id, tier, -1))
	return b

func _open_rating(game_id: StringName, gd: GameData) -> void:
	var modal = preload("res://scripts/ui/RateGameModal.gd").new()
	modal.setup(game_id, gd)
	modal.submitted.connect(func(score: int, notes: String):
		TierList.set_rating(game_id, score, notes)
		modal.queue_free())
	modal.dismissed.connect(func(): modal.queue_free())
	add_child(modal)

func _fact(key: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.clip_text = true
	k.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	k.add_theme_font_size_override("font_size", 12)
	k.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(k)
	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_theme_font_size_override("font_size", 12)
	v.add_theme_color_override("font_color", UITheme.TEXT)
	row.add_child(v)
	return row

func _heading(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.GOLD)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _note(text: String, color: Color = UITheme.TEXT_FAINT) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# ------------------------------------------------------------------
# Drop handling
# ------------------------------------------------------------------

# Called by a Tile/DropZone when a game is dropped. insert_at < 0 appends.
func handle_drop(game_id: StringName, target_tier: int, insert_at: int) -> void:
	TierList.place(game_id, target_tier, insert_at)

# ------------------------------------------------------------------
# Inner controls — drag source (Tile) and drop targets (DropZone, Tile).
# ------------------------------------------------------------------

class DropZone extends HFlowContainer:
	var _screen: TierListScreen
	var _tier_index: int

	func _init(screen: TierListScreen, tier_index: int, row_height: float = TILE_SIZE.y) -> void:
		_screen = screen
		_tier_index = tier_index
		mouse_filter = Control.MOUSE_FILTER_STOP
		# An empty tier still has to look like somewhere a game can be put down, so
		# the zone keeps one tile's height even with nothing in it — at whatever
		# size the board is currently fitted to.
		custom_minimum_size = Vector2(0, row_height)
		add_theme_constant_override("h_separation", int(TILE_SEP))
		add_theme_constant_override("v_separation", int(TILE_SEP))

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("game_id")

	func _drop_data(_pos: Vector2, data) -> void:
		_screen.handle_drop(StringName(data["game_id"]), _tier_index, -1)

class Tile extends PanelContainer:
	var _screen: TierListScreen
	var _game_id: StringName
	var _tier_index: int

	func _init(screen: TierListScreen, game_id: StringName, tier_index: int) -> void:
		_screen = screen
		_game_id = game_id
		_tier_index = tier_index
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		gui_input.connect(_on_gui_input)

	# Select on RELEASE, not on press: a press that turns into a drag is released
	# over the drop target, not here, so dragging a game never also opens it.
	func _on_gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			_screen.select_game(_game_id)

	func _get_drag_data(_pos: Vector2):
		var preview := TextureRect.new()
		var gd: GameData = Data.get_game(_game_id)
		if gd != null and gd.cover_image != null:
			preview.texture = gd.cover_image
		# Without EXPAND_IGNORE_SIZE a TextureRect draws at the texture's native
		# resolution, so a large cover renders huge and ignores the size below.
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.custom_minimum_size = Vector2(64, 64)
		preview.size = Vector2(64, 64)
		preview.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(preview)
		return {"game_id": String(_game_id)}

	func _can_drop_data(_pos: Vector2, data) -> bool:
		return data is Dictionary and data.has("game_id")

	# Dropping onto a tile inserts the dragged game just before it, so the
	# player can reorder within a row, not only move between rows.
	func _drop_data(_pos: Vector2, data) -> void:
		var at: int = get_index()
		_screen.handle_drop(StringName(data["game_id"]), _tier_index, at)

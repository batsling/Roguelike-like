class_name BattlefieldView
extends PanelContainer

# BattlefieldView — the MMBN-style board the overworld fights on, split out of
# Overworld2 so the board's geometry, painting and animation live in one file and
# the overworld itself stays a run-flow screen.
#
# The layout is: the hero on the left, a grid_cols() x grid_rows() grid of cells in
# the middle (column 1 = melee/front nearest the hero, column grid_cols() = spawn),
# and a slim off-field lane on the right for enemies with no room on the board.
# Enemies are not one-per-cell: each covers its GoalEnemyData footprint, so the
# board is a fixed grid of backdrop panels with a free-positioned OVERLAY on top
# holding one node per enemy, spanning that enemy's whole bounding box.
#
# The view owns no run state. It reads GameLoop2 on `refresh()` and reports the
# player's intent back through signals: the host spends the Push / Bomb charge and
# opens the inspect card (which must mount above the page, not inside the board).
#
# It's a PanelContainer so it hugs the board's real size — whatever the host puts
# beside it (the pack column) sits right against the off-field lane instead of being
# pushed to the far edge of the page.

# The player clicked Push / Bomb on the toolbar for `instance`. The host owns the
# charge, so it decides whether the verb actually happens.
signal push_requested(instance: int)
signal bomb_requested(instance: int)
# An enemy was clicked: the host opens the inspect card for it.
signal enemy_inspected(entry: Dictionary, col: int, is_current: bool)
# A repaint finished — the host repaints anything anchored to the board with it.
signal repainted

var _battlefield: HBoxContainer
# The amulet-pressure strip across the top of the board (§7.4): how many turns
# the enemies take per game, why, and how big the board they take them on is.
# This is the mechanic's home — it sits ON the thing it governs, so the pace and
# the field it plays out on are read in one glance.
var _pressure_panel: PanelContainer
var _pressure_turns: Label          # "⏱ ENEMY TURNS ×2"
var _pressure_rungs: Array = []     # the three ladder pips, far -> near
var _pressure_why: Label            # "Amulet 4 hops away — Closing"
var _size_label: Label              # "▦ 5×5 · Medium"
var _hero_icon: TextureRect
var _hero_hp: Label
# Shields — the tries at the game in play (§3), drawn as pips over the hero:
# filled for the ones still standing, hollow for the ones already spent on a lost
# run. This is what the attempt tracker visibly drains.
var _hero_shields: Label
var _field: Control                  # fixed-size board the two layers stack inside
var _cell_layer: Control             # the static backdrop of empty cells
# The board dimensions the backdrop was last drawn at. The grid can GROW mid-run
# (Mine-r Construction), so the panels are rebuilt when this stops matching
# GameLoop2 rather than being laid down once and trusted forever.
var _cells_drawn := Vector2i.ZERO
var _enemy_layer: Control            # free-positioned enemy nodes, drawn over the board
# Health / damage / status badges live on their own layer ABOVE every body, so an
# enemy overlapping another never hides what that other one is about to do to you.
var _badge_layer: Control
var _enemy_nodes: Dictionary = {}    # instance -> the node currently drawing it
var _offgrid_box: VBoxContainer      # overflow queue just off the grid's right edge
var _fx_layer: Control               # overlay for damage numbers + sliding ghosts
# Bodies (and their badges) currently hidden behind a travelling ghost. Held for
# the whole multi-turn playback rather than per slide — an enemy that walks on
# turn 1 and stands still on turn 3 has no last ghost to hand it back.
var _hidden_parts: Array = []
# Whether the game being played right now shows in the off-field lane. Kept from
# the last refresh so a click can repaint without the host passing it again.
var _show_current: bool = false
# The hero portrait, resolved once per character rather than on every repaint.
var _hero_id: StringName = &""
var _hero_tex: Texture2D = null

var selected_instance: int = 0       # clicked enemy the combat verbs target (0 = none)
var push_btn: Button
var bomb_btn: Button
var _target_label: Label

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build()

# The current character's board portrait. Cached against the character id so a
# repaint doesn't re-resolve the CharacterData every time.
func _hero_texture() -> Texture2D:
	var id: StringName = GameState.character_id
	if id != _hero_id:
		_hero_id = id
		var ch: CharacterData = Data.get_character2(id)
		_hero_tex = null
		if ch != null:
			_hero_tex = ch.icon if ch.icon != null else ch.portrait
	return _hero_tex

const CELL: int = 84                # grid cell edge in px
const CELL_SEP: int = 6
const CELL_STEP: int = CELL + CELL_SEP
# Shields (the tries, §3) share the overworld's steel blue.
const SHIELD_BLUE := Color(0.62, 0.78, 0.95)
# Everything on the board layers by TREE ORDER, never z_index: z_index is relative
# to the parent and would punch the board out through anything drawn later in the
# scene — the enemy info card and the reward screens sit above the battlefield
# precisely because they're mounted after it.

# A Control whose clickable area is only the cells its enemy actually FILLS, so
# the empty notch inside an L-shaped body stays clickable for whatever stands
# behind it — the bounding box is for drawing, the mask is for input.
class FootprintControl extends Control:
	var cells: Array = []            # Vector2i(col offset, row offset), solid only
	var cell_size: float = 84.0
	var step: float = 90.0

	func _has_point(point: Vector2) -> bool:
		for c in cells:
			if Rect2(Vector2(c.x, c.y) * step, Vector2(cell_size, cell_size)).has_point(point):
				return true
		return false

# Board size in px: grid_cols() x grid_rows() cells with a gutter between them.
func _field_size() -> Vector2:
	return Vector2(
		GameLoop2.grid_cols() * CELL + (GameLoop2.grid_cols() - 1) * CELL_SEP,
		GameLoop2.grid_rows() * CELL + (GameLoop2.grid_rows() - 1) * CELL_SEP)

# Lay down the backdrop: one empty panel per cell, column 1 nearest the hero.
# Cheap and idempotent — it returns untouched unless the board actually changed
# size, which a difficulty step (§7.3) or a Mine-r Construction does, and then it
# also re-sizes the field so the new column and row have somewhere to be.
#
# When the board GREW, the cells that weren't there a moment ago are lit and
# pulsed in the accent colour. The board silently becoming a size larger is the
# kind of change a player feels ("that took longer to reach me") without ever
# seeing, so the new ground says so itself, wherever the growth came from.
func _rebuild_cells() -> void:
	if _cell_layer == null:
		return
	var dims := Vector2i(GameLoop2.grid_cols(), GameLoop2.grid_rows())
	if dims == _cells_drawn:
		return
	var was: Vector2i = _cells_drawn
	_cells_drawn = dims
	for c in _cell_layer.get_children():
		_cell_layer.remove_child(c)
		c.queue_free()
	_field.custom_minimum_size = _field_size()
	# Every backdrop panel looks the same, so one shared StyleBox does for all of
	# them instead of rows x cols identical copies.
	var empty_style: StyleBox = UITheme.flat(UITheme.BG.lerp(UITheme.PANEL, 0.4), 6, 4, 1, UITheme.BORDER.lerp(UITheme.BG, 0.3))
	# The one exception: ground that is new this repaint gets its own lit style.
	var grew: bool = was != Vector2i.ZERO and (dims.x > was.x or dims.y > was.y)
	var new_style: StyleBox = UITheme.flat(
		UITheme.BG.lerp(UITheme.ACCENT, 0.22), 6, 4, 2, UITheme.ACCENT)
	var fresh: Array = []
	for row in range(dims.y):
		for col in range(1, dims.x + 1):
			var cell := PanelContainer.new()
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.position = _cell_pos(row, col)
			cell.size = Vector2(CELL, CELL)
			var is_new: bool = grew and (col > was.x or row >= was.y)
			cell.add_theme_stylebox_override("panel", new_style if is_new else empty_style)
			_cell_layer.add_child(cell)
			if is_new:
				fresh.append(cell)
	if not fresh.is_empty():
		_pulse_new_ground(fresh, empty_style)

# Breathe the just-appeared cells a couple of times, then settle them into the
# ordinary backdrop. Purely a "look here, this is new" cue — the cells are
# already fully functional ground.
func _pulse_new_ground(cells: Array, settled: StyleBox) -> void:
	if not is_inside_tree():
		return
	for cell: PanelContainer in cells:
		cell.modulate = Color(1, 1, 1, 0.25)
		var t: Tween = cell.create_tween()
		t.set_loops(3)
		t.tween_property(cell, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE)
		t.tween_property(cell, "modulate:a", 0.35, 0.32).set_trans(Tween.TRANS_SINE)
		t.chain().tween_callback(func():
			if is_instance_valid(cell):
				cell.modulate.a = 1.0
				cell.add_theme_stylebox_override("panel", settled))

# Top-left of grid cell (`row`, `col`) inside the board (0-based row, 1-based col).
func _cell_pos(row: int, col: int) -> Vector2:
	return Vector2((col - 1) * CELL_STEP, row * CELL_STEP)

# Pixel size of a footprint `cols` wide and `rows` tall, gutters included — the
# rect an enemy's art is drawn across.
func _span_size(rows: int, cols: int) -> Vector2:
	return Vector2(cols * CELL + (cols - 1) * CELL_SEP,
		rows * CELL + (rows - 1) * CELL_SEP)

# --- the amulet-pressure strip (§7.4) --------------------------------------
#
# The one thing a player has to understand about this board is that the enemies
# on it move faster the closer the run gets to the Amulet. So it is not a
# tooltip and not a number in a HUD row — it is a strip across the top of the
# board itself, in the band's own colour, saying the pace, the ladder it sits on,
# and the distance that put it there. The board's SIZE rides along on the right
# because that is the other half of the same bargain: the difficulty tier that
# makes the enemies heavier also gives you a wider board to see them coming on.

# Pip glyphs for the three-rung ladder — filled to the current band, hollow past it.
const RUNG_ON := "▮"
const RUNG_OFF := "▯"

func _build_pressure_bar() -> Control:
	_pressure_panel = PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_pressure_panel.add_child(row)

	_pressure_turns = Label.new()
	_pressure_turns.add_theme_font_size_override("font_size", 14)
	row.add_child(_pressure_turns)

	# The ladder: three pips, far band on the left. Filled up to where the run
	# stands, so "how much worse can this get?" is answerable without a tooltip.
	var ladder := HBoxContainer.new()
	ladder.add_theme_constant_override("separation", 2)
	_pressure_rungs.clear()
	for i in range(RunDifficulty.TURNS_NEAR):
		var pip := Label.new()
		pip.add_theme_font_size_override("font_size", 15)
		ladder.add_child(pip)
		_pressure_rungs.append(pip)
	row.add_child(ladder)

	_pressure_why = Label.new()
	_pressure_why.add_theme_font_size_override("font_size", 12)
	_pressure_why.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(_pressure_why)

	# Pushes the board size to the far end of the strip.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_size_label = Label.new()
	_size_label.add_theme_font_size_override("font_size", 12)
	_size_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(_size_label)
	return _pressure_panel

# Repaint the strip from the loop. Everything on it is derived — the turn count,
# the rung, the hop count, the board's dimensions — so there is nothing to keep
# in sync by hand.
func _refresh_pressure() -> void:
	if _pressure_turns == null:
		return
	var turns: int = GameLoop2.enemy_turns()
	var hops: int = GameLoop2.hops_to_amulet()
	var band: Color = RunDifficulty.turns_band_color(turns)

	_pressure_panel.add_theme_stylebox_override("panel",
		UITheme.flat(band.lerp(UITheme.BG, 0.82), 6, 6, 1, band.lerp(UITheme.BG, 0.45)))
	_pressure_turns.text = "⏱  ENEMY TURNS ×%d" % turns
	_pressure_turns.add_theme_color_override("font_color", band)

	for i in range(_pressure_rungs.size()):
		var pip: Label = _pressure_rungs[i]
		var lit: bool = i < turns
		pip.text = RUNG_ON if lit else RUNG_OFF
		pip.add_theme_color_override("font_color",
			band if lit else UITheme.TEXT_FAINT)

	# WHY it's that number. Without the hop count the turn count reads as a random
	# difficulty spike rather than as the price of the route the player chose.
	if hops < 0:
		_pressure_why.text = "no route to the Amulet"
	elif hops == 0:
		_pressure_why.text = "standing ON the Amulet — %s" % RunDifficulty.turns_band_name(turns)
	else:
		_pressure_why.text = "Amulet %d hop%s away — %s" % [
			hops, "" if hops == 1 else "s", RunDifficulty.turns_band_name(turns)]

	var ladder_tip: String = ("Every enemy acts %d time%s per game you report.\n"
		+ "A turn is one action: strike from the front column, or step a column closer.\n\n"
		+ "%s\n\nRush the Amulet and they get faster; take the long way and they stay slow.") % [
			turns, "" if turns == 1 else "s", RunDifficulty.turns_ladder_text(turns)]
	_pressure_panel.tooltip_text = ladder_tip
	_pressure_turns.tooltip_text = ladder_tip
	_pressure_why.tooltip_text = ladder_tip

	var tier: int = RunDifficulty.current_tier()
	_size_label.text = "▦ %d×%d · %s" % [
		GameLoop2.grid_cols(), GameLoop2.grid_rows(), RunDifficulty.tier_name(tier)]
	_size_label.tooltip_text = ("The battlefield is %d columns by %d rows.\n"
		+ "It gains a column AND a row on every difficulty step — %d×%d at Low, "
		+ "up to %d×%d at Insane — so the tier that makes the enemies heavier also "
		+ "gives you more ground to lose before they reach you.\n"
		+ "Each Mine-r Construction adds another of each on top.") % [
			GameLoop2.grid_cols(), GameLoop2.grid_rows(),
			GameLoop2.BASE_GRID_COLS, GameLoop2.BASE_GRID_ROWS,
			GameLoop2.BASE_GRID_COLS + RunDifficulty.grid_growth_for(RunDifficulty.MAX_TIER),
			GameLoop2.BASE_GRID_ROWS + RunDifficulty.grid_growth_for(RunDifficulty.MAX_TIER)]

# The combat verbs live with the combat: Push and Bomb sit on a toolbar attached to
# the battlefield and act on the enemy you clicked. Each button explains why it's
# unavailable (no target / no charge / no room behind / boss) rather than vanishing,
# so the rules stay visible.
func _build_battle_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.text = "Click an enemy to inspect it:"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	bar.add_child(hint)

	_target_label = Label.new()
	_target_label.add_theme_font_size_override("font_size", 13)
	# Deliberately not expanding: the verbs must stay packed beside the field they
	# act on, not drift to the far edge of a full-width panel.
	_target_label.custom_minimum_size = Vector2(230, 0)
	bar.add_child(_target_label)

	push_btn = Button.new()
	push_btn.add_theme_font_size_override("font_size", 13)
	push_btn.pressed.connect(func(): push_requested.emit(selected_instance))
	bar.add_child(push_btn)

	bomb_btn = Button.new()
	bomb_btn.add_theme_font_size_override("font_size", 13)
	bomb_btn.pressed.connect(func(): bomb_requested.emit(selected_instance))
	bar.add_child(bomb_btn)
	return bar

# Re-label and enable/disable the combat verbs for the current selection.
func refresh_toolbar() -> void:
	if push_btn == null:
		return
	var entry: Dictionary = _stack_entry(selected_instance)
	var e: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	if e == null:
		_target_label.text = "no target selected"
		_target_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	else:
		_target_label.text = "▸ %s  (col %d, row %d)" % [
			e.display_name, int(entry.get("col", GameLoop2.spawn_col())),
			int(entry.get("row", 0)) + 1]
		_target_label.add_theme_color_override("font_color", UITheme.ACCENT)

	push_btn.text = "⇤  Push (%d)" % GameState.push
	var push_ok: bool = e != null and GameState.push > 0 and GameLoop2.can_push(selected_instance)
	push_btn.disabled = not push_ok
	if e == null:
		push_btn.tooltip_text = "Select an enemy to push."
	elif GameState.push <= 0:
		push_btn.tooltip_text = "No Push charges left."
	elif int(entry.get("col", 0)) + e.footprint_cols() - 1 >= GameLoop2.grid_cols():
		push_btn.tooltip_text = "%s is already against the back edge — nowhere to push it." % e.display_name
	elif not push_ok:
		push_btn.tooltip_text = "Something is parked behind %s — no room to shove it back." % e.display_name
	else:
		push_btn.tooltip_text = "Shove %s back one column, buying the games it takes to close in again." % e.display_name

	# A boss is a legal bomb target even though the damage bounces off it — that
	# is the only way to land Sticky Bombs' stun on one — so the button gates on
	# having a target and a charge, and the tooltip carries the caveat.
	bomb_btn.text = "✸  Bomb (%d)" % GameState.bombs
	bomb_btn.disabled = e == null or GameState.bombs <= 0
	bomb_btn.tooltip_text = GameLoop2.bomb_hint(e)

# The stack entry for an instance, or {} when it's gone / nothing is selected.
func _stack_entry(instance: int) -> Dictionary:
	if instance <= 0:
		return {}
	for entry in GameLoop2.stack:
		if int(entry.get("instance", 0)) == instance:
			return entry
	return {}

# Build the battlefield once: the hero on the left, then a grid_cols() x grid_rows()
# grid of cells (col 1 = melee/front nearest the hero, col grid_cols() = spawn), then
# a slim off-grid overflow lane on the right. Cells are reused each refresh so the
# layout stays put; only their contents change.
func _build() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG, UITheme.BORDER, 10, 12, 1))
	# The view stacks the combat toolbar over the field itself, and hosts the FX
	# layer that floats damage numbers / sliding enemies above both.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	outer.add_child(_build_pressure_bar())
	outer.add_child(_build_battle_toolbar())
	_battlefield = HBoxContainer.new()
	_battlefield.add_theme_constant_override("separation", 14)
	_battlefield.alignment = BoxContainer.ALIGNMENT_BEGIN
	outer.add_child(_battlefield)

	# Animation overlay: ghost sprites and damage numbers are parented here so they
	# can travel across cells without being clipped by a cell's own rect.
	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_layer)

	# Hero column.
	var hero_box := VBoxContainer.new()
	hero_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_box.add_theme_constant_override("separation", 4)
	hero_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Pips ABOVE the portrait: the tries you have left at this game, in the same
	# place the damage numbers land, so ticking a lost run reads as something being
	# taken off the hero.
	_hero_shields = Label.new()
	_hero_shields.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_shields.add_theme_font_size_override("font_size", 18)
	_hero_shields.add_theme_color_override("font_color", SHIELD_BLUE)
	hero_box.add_child(_hero_shields)
	var hero_frame := PanelContainer.new()
	hero_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 8, 8, 2, UITheme.ACCENT))
	_hero_icon = TextureRect.new()
	_hero_icon.custom_minimum_size = Vector2(96, 96)
	_hero_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_frame.add_child(_hero_icon)
	hero_box.add_child(hero_frame)
	_hero_hp = Label.new()
	_hero_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_hp.add_theme_font_size_override("font_size", 14)
	_hero_hp.add_theme_color_override("font_color", UITheme.DANGER.lerp(UITheme.TEXT, 0.35))
	hero_box.add_child(_hero_hp)
	_battlefield.add_child(hero_box)

	# The board: a Control holding two stacked layers, sized to the grid. The lower
	# one is the backdrop — grid_rows() x grid_cols() empty panels, column 1 nearest
	# the hero — and the upper one is where enemies are positioned by hand, because
	# an enemy can span several cells and must be free to overlap its neighbours.
	_field = Control.new()
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_battlefield.add_child(_field)

	_cell_layer = Control.new()
	_cell_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cell_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_cell_layer)
	_rebuild_cells()

	_enemy_layer = Control.new()
	_enemy_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enemy_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_enemy_layer)

	# Stats ride above every body — it's the last layer added to the board, so it
	# draws last. Non-interactive, so it never steals a click from the enemy
	# underneath it.
	_badge_layer = Control.new()
	_badge_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_badge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_badge_layer)

	# Off-field lane: enemies with no cell to stand in — the overflow queue, and the
	# game you're currently playing, whose enemy only steps onto the grid once you
	# report the result.
	var off_col := VBoxContainer.new()
	off_col.add_theme_constant_override("separation", 4)
	off_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var off_lbl := Label.new()
	off_lbl.text = "off field"
	off_lbl.add_theme_font_size_override("font_size", 10)
	off_lbl.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	off_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	off_col.add_child(off_lbl)
	_offgrid_box = VBoxContainer.new()
	_offgrid_box.add_theme_constant_override("separation", CELL_SEP)
	off_col.add_child(_offgrid_box)
	_battlefield.add_child(off_col)

# Repaint the battlefield from the current loop state: place each following enemy
# in its grid cell (by column = distance), the off-grid queue in the side lane,
# and — when `show_current` is set — the just-picked enemy in the off-field lane
# while its game is being played.
func refresh(show_current: bool = false) -> void:
	if _battlefield == null:
		return
	_show_current = show_current
	var hero_tex: Texture2D = _hero_texture()
	_hero_icon.texture = hero_tex
	UITheme.apply_crisp(_hero_icon, hero_tex)
	_hero_hp.text = "♥ %d/%d" % [GameState.hp, GameState.max_hp]
	# Filled pips = shields still standing, hollow = tries already spent on one.
	var left: int = GameState.shields
	var spent: int = GameLoop2.attempts_on_shields()
	_hero_shields.text = "◆".repeat(left) + "◇".repeat(spent)
	_hero_shields.tooltip_text = "%d shield(s) left — one per lost run." % left

	# The pace the enemies below move at, and the size of the board they move on.
	_refresh_pressure()

	# The backdrop only changes when the board does (a difficulty step, or a
	# Mine-r Construction), so this is a no-op on all but the refresh that
	# follows one — and on that one it also lights up the ground that just
	# appeared (see _rebuild_cells).
	_rebuild_cells()

	# Clear the overlays and the overflow lane; the backdrop panels are static.
	for layer in [_enemy_layer, _badge_layer]:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	_enemy_nodes.clear()
	# DETACHED as well as freed, exactly like the two layers above: queue_free
	# alone leaves the old token in the tree until the end of the frame, and
	# capture_positions() reads the overflow lane by walking these children — so a
	# stale token would answer for an enemy that has already walked onto the grid,
	# the advance would measure as "didn't move", and the slide would never play.
	for c in _offgrid_box.get_children():
		_offgrid_box.remove_child(c)
		c.queue_free()

	# Enemies standing on the board, drawn BACK-TO-FRONT: a body lower on the grid
	# is nearer the viewer, so it paints over the ones above it where their
	# bounding boxes overlap. Sorting by the bottom edge of the footprint (then the
	# top edge, then the column) makes a tall enemy hang in front of what it
	# reaches down past.
	var placed: Array = []
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.offgrid_col())) <= GameLoop2.grid_cols():
			placed.append(entry)
	placed.sort_custom(func(a, b): return _draw_order_key(a) < _draw_order_key(b))
	for entry in placed:
		_add_enemy_node(entry, false)

	# Off-field: the overflow queue, plus the game you're playing right now — it
	# isn't on the stack yet and only walks onto the board when you report the
	# result (that entrance is the one-game grace made visible, §7.2).
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.offgrid_col())) > GameLoop2.grid_cols():
			_offgrid_box.add_child(_offgrid_token(entry, false))
	if show_current and GameLoop2.has_current():
		_offgrid_box.add_child(_offgrid_token(GameLoop2.current, true))

	# Drop a selection that died / was bombed, then relabel the combat verbs.
	if selected_instance > 0 and _stack_entry(selected_instance).is_empty():
		selected_instance = 0
	refresh_toolbar()
	repainted.emit()

# Paint an enemy's footprint tiles for its current state. Hovering brightens the
# outline and lifts the fill (the "you can click this" cue); the selected enemy —
# the one the toolbar's Push / Bomb act on — keeps a thick accent ring. `frames`
# is one PanelContainer per cell the enemy fills, so an L reads as an L.
func _style_enemy_cell(frames: Array, accent: Color, is_current: bool, selected: bool, hovered: bool) -> void:
	var border: Color = accent
	var width: int = 3 if is_current else 2
	var fill: Color = UITheme.PANEL
	if selected:
		border = UITheme.ACCENT
		width = 4
		fill = UITheme.PANEL.lerp(UITheme.ACCENT, 0.14)
	if hovered:
		border = border.lerp(Color.WHITE, 0.55)
		width = maxi(width, 3)
		fill = fill.lerp(Color.WHITE, 0.09)
	var box: StyleBox = UITheme.flat(fill, 6, 2, width, border)
	for f in frames:
		if is_instance_valid(f):
			f.add_theme_stylebox_override("panel", box)

# Clicking an enemy targets it for the combat verbs and opens its info card.
func click_enemy(instance: int, entry: Dictionary, col: int, is_current: bool) -> void:
	# The game you're currently playing isn't on the stack, so it can't be targeted
	# by Push / Bomb — but you can still read its card.
	selected_instance = 0 if is_current else instance
	enemy_inspected.emit(entry, col, is_current)
	refresh(_show_current)

# The accent colour for an enemy: red when it strikes on the next game reported,
# amber when it strikes on the one after, gold farther out, orange for a boss.
#
# `games` is how many games away its first strike is (GameLoop2.games_until_
# strike). Callers that don't have it pass nothing, and the colour falls back to
# reading the COLUMN as if enemies moved one square a game — which is true at one
# turn a game and a lie at three, so anything drawing the live board should hand
# the real number in.
static func threat_color(col: int, is_boss: bool, games: int = -1) -> Color:
	if is_boss:
		return Color(0.95, 0.55, 0.2)
	var away: int = games if games >= 0 else maxi(0, col - 1)
	if away <= 0:
		return UITheme.DANGER
	if away == 1:
		return Color(1.0, 0.62, 0.24)
	return UITheme.GOLD

# Sort key for painting order: bodies lower on the board draw over the ones above
# them, so the bottom edge of the footprint leads, then its top edge, then column.
func _draw_order_key(entry: Dictionary) -> int:
	var e: GoalEnemyData = entry.get("enemy")
	var row: int = int(entry.get("row", 0))
	var rows: int = e.footprint_rows() if e != null else 1
	return (row + rows - 1) * 10000 + row * 100 + int(entry.get("col", 1))

# Add one enemy to the overlay, spanning its whole footprint. Each cell it fills
# gets a tinted frame (so a 2x3 L visibly reads as an L), the art is drawn across
# the FULL bounding box — never cropped to the solid cells, so the parts poking
# out of the shape stay visible — and ❤ health / ⚔ damage / status badges sit in
# the corners. The current (now-playing) enemy gets a thicker border.
func _add_enemy_node(entry: Dictionary, is_current: bool) -> Control:
	var e: GoalEnemyData = entry.get("enemy")
	if e == null:
		return null
	var row: int = int(entry.get("row", 0))
	var col: int = int(entry.get("col", 1))
	var rows: int = e.footprint_rows()
	var cols: int = e.footprint_cols()
	var cells: Array = e.footprint_cells()
	var front: int = GameLoop2.grid_cols()
	for off in cells:
		front = mini(front, col + int(off.x))

	var stun: int = int(entry.get("stun", 0))
	var accent: Color = threat_color(front, e.is_boss(), GameLoop2.games_until_strike(entry))
	if stun > 0:
		accent = accent.lerp(Color(0.5, 0.7, 1.0), 0.5)
	var inst: int = int(entry.get("instance", 0))
	var selected: bool = inst > 0 and inst == selected_instance

	# The node covers the bounding box, but only answers the mouse over the cells
	# the enemy really fills — an L's notch belongs to whoever stands in it.
	var node := FootprintControl.new()
	node.cells = cells
	node.cell_size = float(CELL)
	node.step = float(CELL_STEP)
	node.position = _cell_pos(row, col)
	node.size = _span_size(rows, cols)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.tooltip_text = _timing_tip(entry, e)
	node.set_meta("instance", inst)
	_enemy_layer.add_child(node)
	_enemy_nodes[inst] = node

	# One frame per filled cell, positioned inside the node.
	var frames: Array = []
	for off in cells:
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.position = Vector2(off.x, off.y) * float(CELL_STEP)
		frame.size = Vector2(CELL, CELL)
		node.add_child(frame)
		frames.append(frame)
	_style_enemy_cell(frames, accent, is_current, selected, false)

	# Enemies are click-to-inspect: hovering brightens the outline to advertise it
	# and lifts the whole body above its neighbours so an overlapped enemy can be
	# seen in full; clicking selects it and opens its info card. The lift is a
	# reorder within the enemy layer, not a z_index, so a hovered body still stays
	# under the badges and under anything mounted above the battlefield.
	var resting_index: int = node.get_index()
	node.mouse_entered.connect(func():
		_enemy_layer.move_child(node, -1)
		_style_enemy_cell(frames, accent, is_current, inst == selected_instance, true))
	node.mouse_exited.connect(func():
		_enemy_layer.move_child(node, mini(resting_index, _enemy_layer.get_child_count() - 1))
		_style_enemy_cell(frames, accent, is_current, inst == selected_instance, false))
	node.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			click_enemy(inst, entry, front, is_current))

	# One full-rect holder so corner-anchored overlays position correctly. It's
	# also what the resolve animation hides while a ghost slides into place.
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(holder)
	node.set_meta("holder", holder)

	# Art (or a tinted silhouette when the enemy has no image) across the whole
	# bounding box, aspect preserved so nothing is squashed or cut off.
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e.image != null:
		art.texture = e.image
		if e.image.get_width() < CELL or e.image.get_height() < CELL:
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		art.modulate = accent
	holder.add_child(art)

	# Badges go on the layer above every body, but stay pinned to the cells this
	# enemy holds (not to its nudged art), so they read as "this one's stats".
	var badges := Control.new()
	badges.position = node.position
	badges.size = node.size
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_layer.add_child(badges)
	node.set_meta("badges", badges)
	_add_enemy_badges(badges, entry, e, accent, selected)
	return node

# Badges for one enemy, laid out in the corners of the box it holds: boss skull
# top, health bottom-left, damage bottom-right, and the stun marker when frozen.
# `holder` is the enemy's slot on the badge layer, so these always draw in front
# of every body on the board. All non-blocking, so the enemy underneath still
# takes the click and shows its tooltip.
func _add_enemy_badges(holder: Control, entry: Dictionary, e: GoalEnemyData,
		accent: Color, selected: bool) -> void:
	var stun: int = int(entry.get("stun", 0))

	# TOP CENTRE — what this body does to you on the NEXT game reported: "×2" for
	# two swings, "in 2" for two games of walking still to do. Once enemies take
	# more than one turn a game the column alone can't answer that, and this is
	# the number the player is actually deciding on. It shares the strip with the
	# boss skull rather than taking a corner of its own, because the corners are
	# spoken for and a cell is only 84px wide — a wider badge down in the ⚔ corner
	# ran straight into the ❤ one.
	var strikes: int = GameLoop2.attacks_next_game(entry)
	var away: int = GameLoop2.games_until_strike(entry)
	var top_bits: Array = []
	if e.is_boss():
		top_bits.append("☠")
	var timing: Color = accent
	if strikes > 0:
		top_bits.append("×%d" % strikes)
		timing = UITheme.DANGER.lerp(Color.WHITE, 0.3)
	elif away > 0:
		top_bits.append("in %d" % away)
		timing = UITheme.TEXT_DIM
	if not top_bits.is_empty():
		var top := _corner_badge(" ".join(top_bits), timing)
		top.add_theme_color_override("font_color", timing)
		top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 2)
		holder.add_child(top)

	var hp: int = int(entry.get("health", e.health))
	var hp_lbl := _corner_badge("❤%d" % hp, Color(1.0, 0.5, 0.5))
	hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 2)
	holder.add_child(hp_lbl)

	# Damage PER SWING, unchanged — how many swings there are is the badge above.
	var dmg_lbl := _corner_badge("⚔%d" % e.damage, Color(1.0, 0.8, 0.35))
	dmg_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
	holder.add_child(dmg_lbl)

	if stun > 0:
		var frozen := _corner_badge("❄", Color(0.6, 0.8, 1.0))
		frozen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 2)
		holder.add_child(frozen)

	# A selected enemy carries a marker so it's obvious which one the Push / Bomb
	# buttons on the toolbar are aimed at.
	if selected:
		var pin := _corner_badge("▸", UITheme.ACCENT)
		pin.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
		holder.add_child(pin)

# What this enemy does on the next game you report, in a sentence: how many
# swings it gets and for how much, or how many games of walking it still owes.
# The badge is the glance; this is the answer when the glance isn't enough.
func _timing_tip(entry: Dictionary, e: GoalEnemyData) -> String:
	var turns: int = GameLoop2.enemy_turns()
	var strikes: int = GameLoop2.attacks_next_game(entry)
	var away: int = GameLoop2.games_until_strike(entry)
	var pace: String = "Enemies take %d turn%s per game right now (%s)." % [
		turns, "" if turns == 1 else "s",
		RunDifficulty.turns_band_name(turns).to_lower()]
	if int(entry.get("stun", 0)) > 0:
		pace += "\n❄ Stunned: %d of its turns go to nothing." % int(entry.get("stun", 0))
	if strikes > 0:
		return "%s\n%s strikes %d time%s next game — %d damage total." % [
			pace, e.display_name, strikes, "" if strikes == 1 else "s",
			strikes * int(e.damage)]
	if away > 0:
		return "%s\n%s is %d game%s of walking from its first strike." % [
			pace, e.display_name, away, "" if away == 1 else "s"]
	return "%s\n%s is waiting off the field — it can't reach you yet." % [pace, e.display_name]

# A single full-rect Control child of a cell PanelContainer, inside which art and
# corner-anchored overlays lay out freely (the PanelContainer stretches this one
# holder to fill; the holder itself imposes no layout on its children).
func _cell_holder(cell: PanelContainer) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	return holder

# A small pill label used for the health / damage / status badges on a cell.
func _corner_badge(text: String, color: Color, font_size: int = 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# A token for an enemy that has no cell on the field: either the overflow queue,
# or the game you're playing right now (which enters the grid when you report it).
# Clickable like a grid cell, with the same hover cue.
func _offgrid_token(entry: Dictionary, is_current: bool = false) -> Control:
	var e: GoalEnemyData = entry.get("enemy")
	var accent: Color = UITheme.ACCENT if is_current else UITheme.GOLD
	if e != null and e.is_boss():
		accent = Color(0.95, 0.55, 0.2)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(CELL if is_current else 44, CELL if is_current else 44)
	var paint := func(hovered: bool) -> void:
		var border: Color = accent.lerp(Color.WHITE, 0.55) if hovered else accent.lerp(UITheme.BG, 0.25)
		var fill: Color = UITheme.PANEL.lerp(UITheme.BG, 0.3)
		if hovered:
			fill = fill.lerp(Color.WHITE, 0.09)
		cell.add_theme_stylebox_override("panel", UITheme.flat(fill, 5, 2, 2 if is_current else 1, border))
	paint.call(false)
	if e != null:
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.mouse_entered.connect(func(): paint.call(true))
		cell.mouse_exited.connect(func(): paint.call(false))
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				click_enemy(int(entry.get("instance", 0)), entry, GameLoop2.offgrid_col(), is_current))
		cell.set_meta("instance", int(entry.get("instance", 0)))
		var holder := _cell_holder(cell)
		cell.set_meta("holder", holder)
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if e.image != null:
			art.texture = e.image
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			art.modulate = accent
		holder.add_child(art)
		# The game in play is labelled, so it reads as "waiting to enter" rather
		# than as another queued enemy.
		if is_current:
			var tag := _corner_badge("NOW PLAYING", UITheme.ACCENT, 9)
			tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 2)
			holder.add_child(tag)
			var dmg := _corner_badge("⚔%d" % e.damage, Color(1.0, 0.8, 0.35))
			dmg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
			holder.add_child(dmg)
	return cell

# --- resolve animation ----------------------------------------------------

const FX_ATTACK_TIME: float = 0.55   # how long the front-line strike phase runs
const FX_SLIDE_TIME: float = 0.34    # how long the advance slide takes

# A node's rect in the FX LAYER'S OWN SPACE rather than in global coordinates.
#
# Everything the resolve animation draws is positioned this way, and it has to
# be: the page re-lays out between the snapshot and the playback — reporting a
# game hides the whole offering above the board, and the host may scroll the page
# while the ghosts are still in flight — so a global rect captured before that
# shift points hundreds of pixels away from the board by the time something is
# drawn at it. The board's offset INSIDE the view never changes, so a local rect
# survives every one of those moves.
func _local_rect(node: Control) -> Rect2:
	var r: Rect2 = node.get_global_rect()
	if _fx_layer == null:
		return r
	return Rect2(r.position - _fx_layer.get_global_rect().position, r.size)

# Where every enemy is drawn right now: instance -> Rect2 (FX-layer space) of its
# cell or off-field token. Captured before a resolve and again after, so the
# difference is exactly the movement to animate.
func capture_positions() -> Dictionary:
	var out: Dictionary = {}
	if _battlefield == null:
		return out
	for inst in _enemy_nodes:
		var node: Control = _enemy_nodes[inst]
		if is_instance_valid(node):
			out[int(inst)] = _local_rect(node)
	if _offgrid_box != null:
		for tok in _offgrid_box.get_children():
			if tok.has_meta("instance") and int(tok.get_meta("instance")) > 0:
				out[int(tok.get_meta("instance"))] = _local_rect(tok)
	return out

# The holder Control of whichever node currently draws `instance`, so it can be
# hidden while its ghost slides in.
func _holder_for_instance(instance: int) -> Control:
	var node: Variant = _enemy_nodes.get(instance)
	if node != null and is_instance_valid(node) and node.has_meta("holder"):
		return node.get_meta("holder")
	if _offgrid_box != null:
		for tok in _offgrid_box.get_children():
			if tok.has_meta("instance") and int(tok.get_meta("instance")) == instance:
				return tok.get_meta("holder") if tok.has_meta("holder") else null
	return null

# The badge slot for `instance` on the badge layer (off-field tokens carry their
# own badges inline, so they have none here).
func _badges_for_instance(instance: int) -> Control:
	var node: Variant = _enemy_nodes.get(instance)
	if node != null and is_instance_valid(node) and node.has_meta("badges"):
		return node.get_meta("badges")
	return null

func clear_fx() -> void:
	# A playback cut short must not leave a body invisible behind a ghost that
	# will never land, so the reveal happens here too.
	_reveal_hidden()
	if _fx_layer == null:
		return
	for c in _fx_layer.get_children():
		c.queue_free()

# Show every body a ghost was standing in for. Idempotent, and safe against the
# nodes having been rebuilt by a repaint mid-playback.
func _reveal_hidden() -> void:
	for part in _hidden_parts:
		if is_instance_valid(part):
			part.modulate.a = 1.0
	_hidden_parts.clear()

# Play back the resolve the player just triggered: the front line strikes (each
# attacker flashes and throws its damage number at the hero, who recoils), then
# the whole field slides one column closer — including the game you just reported,
# which walks in from off-field onto the spawn column.
#
# Returns HOW LONG the playback runs, in seconds (0.0 when there was nothing to
# show). The host holds the screen on the board for that long before moving on —
# an animation the next screen wipes off mid-flight may as well not exist.
func animate_resolve(before: Dictionary, res: Dictionary) -> float:
	if _fx_layer == null or not is_inside_tree():
		return 0.0
	clear_fx()
	var after: Dictionary = capture_positions()

	# One playback per TURN (§7.4). Each turn is the same beat the board has
	# always played — the front line strikes, then the field closes up — and the
	# whole point of the mechanic is that near the Amulet you watch that beat land
	# three times instead of once. Collapsing it into a single slide would hide
	# exactly the thing the player needs to feel.
	var frames: Array = _turn_rect_frames(before, after, res)
	var turns: int = maxi(1, frames.size() - 1)
	var elapsed: float = 0.0
	for turn in range(turns):
		var from_frame: Dictionary = frames[turn]
		var to_frame: Dictionary = frames[turn + 1]
		var struck: bool = _play_turn_strikes(turn, from_frame, res, elapsed)
		# The slide waits for its own turn's strike to land, and only for that:
		# a turn where nothing attacked starts moving immediately.
		var slide_at: float = elapsed + (FX_ATTACK_TIME if struck else 0.0)
		var slid: bool = _play_turn_slides(from_frame, to_frame, slide_at)
		# A turn nobody acted on costs no time — an empty board resolves as
		# instantly as it always did.
		if struck or slid:
			# The counter only earns its place when there is more than one turn to
			# count; at one turn a game it would be noise over every single report.
			if turns > 1:
				_spawn_turn_counter(turn + 1, turns, elapsed)
			elapsed = slide_at + (FX_SLIDE_TIME if slid else 0.0)
	# Whatever the ghosts were standing in for comes back at the end of the whole
	# playback, not at the end of each turn: a body that moved on turn 1 and then
	# stood still has no turn-3 ghost to hand it back.
	if elapsed > 0.0:
		_after(elapsed, _reveal_hidden)
	else:
		_reveal_hidden()
	return elapsed

# The board's geometry at the start of each turn, as instance -> global Rect2.
# frames[0] is where everyone stood before the resolve and frames[n] where they
# ended up; the ones between are rebuilt from the grid coordinates the loop
# snapshotted per turn (res.turn_frames), because those positions were never
# drawn and so cannot be captured from live nodes.
func _turn_rect_frames(before: Dictionary, after: Dictionary, res: Dictionary) -> Array:
	var snapshots: Array = res.get("turn_frames", [])
	var frames: Array = [before]
	for i in range(snapshots.size()):
		# The last snapshot IS the board as drawn, so use the real rects for it —
		# they carry the off-field lane's layout, which grid maths can't derive.
		if i == snapshots.size() - 1:
			frames.append(after)
			continue
		var frame: Dictionary = {}
		var snap: Dictionary = snapshots[i]
		for inst in snap.keys():
			var rect: Variant = _grid_rect_for(int(inst), snap[inst])
			# No rect (off-grid, or an enemy that has since left the board): hold it
			# wherever it was last seen so it doesn't teleport to the origin.
			frame[int(inst)] = rect if rect != null else (
				after.get(int(inst)) if after.has(int(inst)) else before.get(int(inst)))
		frames.append(frame)
	if frames.size() == 1:
		frames.append(after)
	return frames

# The global Rect2 an enemy's footprint would occupy standing at `at` =
# Vector2i(col, row). Null when that isn't a spot on the board (the off-grid
# queue), since the overflow lane is laid out by a container, not by grid maths.
func _grid_rect_for(instance: int, at: Vector2i):
	if _field == null or at.x > GameLoop2.grid_cols():
		return null
	var entry: Dictionary = _stack_entry(instance)
	var e: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	if e == null:
		return null
	return Rect2(_local_rect(_field).position + _cell_pos(at.y, at.x),
		_span_size(e.footprint_rows(), e.footprint_cols()))

# Play the strikes belonging to one turn, from the positions the attackers held
# when they threw them. Returns whether anything actually connected.
func _play_turn_strikes(turn: int, frame: Dictionary, res: Dictionary,
		delay: float) -> bool:
	var hero_rect: Rect2 = _local_rect(_hero_icon)
	var struck: bool = false
	for a in res.get("attacks", []):
		if not (a is Dictionary) or not a.has("damage"):
			continue
		# Attacks logged before the turn field existed (a restored save, a test
		# building a result by hand) all belong to the first turn.
		if int(a.get("turn", 0)) != turn:
			continue
		var inst: int = int(a.get("instance", 0))
		if not frame.has(inst):
			continue
		struck = true
		var from: Rect2 = frame[inst]
		_after(delay, func():
			_spawn_strike_flash(from)
			_spawn_damage_number(int(a["damage"]), from, hero_rect))
	if struck:
		_after(delay, _punch_hero)
	return struck

# Slide every body whose square changed over one turn, starting `delay` seconds
# into the playback.
func _play_turn_slides(from_frame: Dictionary, to_frame: Dictionary, delay: float) -> bool:
	var slid: bool = false
	for inst in to_frame.keys():
		if not from_frame.has(inst):
			continue
		var from_rect: Rect2 = from_frame[inst]
		var to_rect: Rect2 = to_frame[inst]
		if from_rect.position.distance_to(to_rect.position) < 2.0:
			continue
		slid = true
		_spawn_slide_ghost(int(inst), from_rect, to_rect, delay)
	return slid

# Run `fn` after `delay` seconds of the playback (immediately at delay 0). One
# helper so every phase of a multi-turn resolve is scheduled the same way.
func _after(delay: float, fn: Callable) -> void:
	if delay <= 0.0:
		fn.call()
		return
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_callback(fn)

# "TURN 2 / 3" over the board as each turn opens — the count is the mechanic, so
# it is spelled out rather than left to be inferred from how many times the hero
# flinched.
func _spawn_turn_counter(turn: int, turns: int, delay: float) -> void:
	if _field == null:
		return
	var band: Color = RunDifficulty.turns_band_color(turns)
	var rect: Rect2 = _local_rect(_field)
	_after(delay, func():
		var lbl := Label.new()
		lbl.text = "TURN %d / %d" % [turn, turns]
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", band)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		lbl.add_theme_constant_override("outline_size", 7)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx_layer.add_child(lbl)
		# Inside the board's top edge, not above it: the strip and the verb toolbar
		# live up there, and a counter drawn over them reads as part of the chrome
		# instead of as something happening on the field.
		lbl.position = rect.position + Vector2(rect.size.x * 0.5 - 60, 30)
		var t := lbl.create_tween()
		t.set_parallel(true)
		t.tween_property(lbl, "position", lbl.position - Vector2(0, 22), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(lbl, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.set_parallel(false)
		t.tween_callback(lbl.queue_free))

# A logged attempt, played on the hero (§3): a lost run pops one shield pip off and
# floats what it cost. `cost` is "shield" while any are left, "health" once they're
# gone — and that second case is a real hit, so it recoils the hero like an enemy
# strike would. Called by the host off GameLoop2.attempt_logged.
func play_attempt_fx(cost: String) -> void:
	if _fx_layer == null or not is_inside_tree():
		return
	if cost == "shield":
		_float_over_hero("-1 ◆", SHIELD_BLUE)
		_pop_shield_pips()
	else:
		_float_over_hero("-1 ♥", UITheme.DANGER)
		_punch_hero()

# A number rising off the hero — the attempt tracker's feedback, thrown from the
# portrait rather than from an enemy since the player is the one spending here.
func _float_over_hero(text: String, color: Color) -> void:
	if _hero_icon == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(lbl)
	var from: Rect2 = _local_rect(_hero_icon)
	lbl.position = from.position + Vector2(from.size.x * 0.3, 0)
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position", lbl.position - Vector2(0, 46), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.set_parallel(false)
	t.tween_callback(lbl.queue_free)

# The pip row flinches as one goes out — the row is a single label, so it's the row
# that flashes and settles rather than an individual glyph.
func _pop_shield_pips() -> void:
	if _hero_shields == null:
		return
	_hero_shields.pivot_offset = _hero_shields.size * 0.5
	var t := _hero_shields.create_tween()
	t.tween_property(_hero_shields, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK)
	t.tween_property(_hero_shields, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var f := _hero_shields.create_tween()
	f.tween_property(_hero_shields, "modulate", Color(1, 1, 1, 0.35), 0.08)
	f.tween_property(_hero_shields, "modulate", Color.WHITE, 0.3)

# A white burst over an attacking enemy's cell.
func _spawn_strike_flash(rect: Rect2) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.75)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.size = rect.size
	_fx_layer.add_child(flash)
	flash.position = rect.position
	var t := flash.create_tween()
	t.tween_property(flash, "modulate:a", 0.0, 0.42).set_trans(Tween.TRANS_SINE)
	t.tween_callback(flash.queue_free)

# A damage number thrown from the attacker toward the hero.
func _spawn_damage_number(amount: int, from: Rect2, hero: Rect2) -> void:
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(lbl)
	lbl.position = from.position + Vector2(from.size.x * 0.25, 0)
	var target: Vector2 = hero.position + Vector2(hero.size.x * 0.25, -18)
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position", target, FX_ATTACK_TIME * 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, FX_ATTACK_TIME * 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.set_parallel(false)
	t.tween_callback(lbl.queue_free)

# The hero recoils when the front line connects.
func _punch_hero() -> void:
	if _hero_icon == null:
		return
	_hero_icon.pivot_offset = _hero_icon.size * 0.5
	var t := _hero_icon.create_tween()
	t.tween_property(_hero_icon, "scale", Vector2(1.14, 0.9), 0.09).set_trans(Tween.TRANS_BACK)
	t.tween_property(_hero_icon, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var f := _hero_icon.create_tween()
	f.tween_property(_hero_icon, "modulate", Color(1.0, 0.55, 0.55), 0.09)
	f.tween_property(_hero_icon, "modulate", Color.WHITE, 0.34)

# Slide a copy of an enemy from where it stood to where it now stands, hiding the
# real one until the whole playback is over (_reveal_hidden). `delay` is how far
# into the playback this slide begins — the body stays hidden across every turn
# in between, so the next turn's ghost picks up from an empty square instead of
# sliding past a copy of itself.
func _spawn_slide_ghost(instance: int, from_rect: Rect2, to_rect: Rect2,
		delay: float = 0.0) -> void:
	var entry: Dictionary = _stack_entry(instance)
	var e: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	var ghost := TextureRect.new()
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e != null and e.image != null:
		ghost.texture = e.image
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.size = from_rect.size
	_fx_layer.add_child(ghost)
	ghost.position = from_rect.position

	# Hide the settled body AND its badges while the ghosts travel, so the enemy
	# isn't drawn in two places at once. They come back when the playback ends.
	for part in [_holder_for_instance(instance), _badges_for_instance(instance)]:
		if part != null:
			part.modulate.a = 0.0
			if not _hidden_parts.has(part):
				_hidden_parts.append(part)

	# Invisible until its own turn comes up, so the ghosts of earlier turns aren't
	# all sitting on the board at once.
	ghost.modulate.a = 0.0 if delay > 0.0 else 1.0

	var t := ghost.create_tween()
	t.tween_interval(delay)
	t.tween_callback(func(): ghost.modulate.a = 1.0)
	t.set_parallel(true)
	t.tween_property(ghost, "position", to_rect.position, FX_SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(ghost, "size", to_rect.size, FX_SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.chain().tween_callback(ghost.queue_free)

class_name BattlefieldView
extends PanelContainer

# BattlefieldView — the MMBN-style board the overworld fights on, split out of
# Overworld2 so the board's geometry, painting and animation live in one file and
# the overworld itself stays a run-flow screen.
#
# The layout is: the hero on the left, a GRID_COLS x GRID_ROWS grid of cells in
# the middle (column 1 = melee/front nearest the hero, column GRID_COLS = spawn),
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
var _hero_icon: TextureRect
var _hero_hp: Label
var _field: Control                  # fixed-size board the two layers stack inside
var _enemy_layer: Control            # free-positioned enemy nodes, drawn over the board
# Health / damage / status badges live on their own layer ABOVE every body, so an
# enemy overlapping another never hides what that other one is about to do to you.
var _badge_layer: Control
var _enemy_nodes: Dictionary = {}    # instance -> the node currently drawing it
var _offgrid_box: VBoxContainer      # overflow queue just off the grid's right edge
var _fx_layer: Control               # overlay for damage numbers + sliding ghosts
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

# Board size in px: GRID_COLS x GRID_ROWS cells with a gutter between them.
func _field_size() -> Vector2:
	return Vector2(
		GameLoop2.GRID_COLS * CELL + (GameLoop2.GRID_COLS - 1) * CELL_SEP,
		GameLoop2.GRID_ROWS * CELL + (GameLoop2.GRID_ROWS - 1) * CELL_SEP)

# Top-left of grid cell (`row`, `col`) inside the board (0-based row, 1-based col).
func _cell_pos(row: int, col: int) -> Vector2:
	return Vector2((col - 1) * CELL_STEP, row * CELL_STEP)

# Pixel size of a footprint `cols` wide and `rows` tall, gutters included — the
# rect an enemy's art is drawn across.
func _span_size(rows: int, cols: int) -> Vector2:
	return Vector2(cols * CELL + (cols - 1) * CELL_SEP,
		rows * CELL + (rows - 1) * CELL_SEP)

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
			e.display_name, int(entry.get("col", GameLoop2.SPAWN_COL)),
			int(entry.get("row", 0)) + 1]
		_target_label.add_theme_color_override("font_color", UITheme.ACCENT)

	push_btn.text = "⇤  Push (%d)" % GameState.push
	var push_ok: bool = e != null and GameState.push > 0 and GameLoop2.can_push(selected_instance)
	push_btn.disabled = not push_ok
	if e == null:
		push_btn.tooltip_text = "Select an enemy to push."
	elif GameState.push <= 0:
		push_btn.tooltip_text = "No Push charges left."
	elif int(entry.get("col", 0)) + e.footprint_cols() - 1 >= GameLoop2.GRID_COLS:
		push_btn.tooltip_text = "%s is already against the back edge — nowhere to push it." % e.display_name
	elif not push_ok:
		push_btn.tooltip_text = "Something is parked behind %s — no room to shove it back." % e.display_name
	else:
		push_btn.tooltip_text = "Shove %s back one column, buying the games it takes to close in again." % e.display_name

	bomb_btn.text = "✸  Bomb (%d)" % GameState.bombs
	var bomb_ok: bool = e != null and GameState.bombs > 0 and not e.is_boss()
	bomb_btn.disabled = not bomb_ok
	if e == null:
		bomb_btn.tooltip_text = "Select an enemy to bomb."
	elif GameState.bombs <= 0:
		bomb_btn.tooltip_text = "No Bombs left."
	elif e.is_boss():
		bomb_btn.tooltip_text = "%s is a boss — bombs can't kill it." % e.display_name
	else:
		bomb_btn.tooltip_text = "Destroy %s outright (it drops nothing)." % e.display_name

# The stack entry for an instance, or {} when it's gone / nothing is selected.
func _stack_entry(instance: int) -> Dictionary:
	if instance <= 0:
		return {}
	for entry in GameLoop2.stack:
		if int(entry.get("instance", 0)) == instance:
			return entry
	return {}

# Build the battlefield once: the hero on the left, then a GRID_COLS x GRID_ROWS
# grid of cells (col 1 = melee/front nearest the hero, col GRID_COLS = spawn), then
# a slim off-grid overflow lane on the right. Cells are reused each refresh so the
# layout stays put; only their contents change.
func _build() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.BG, UITheme.BORDER, 10, 12, 1))
	# The view stacks the combat toolbar over the field itself, and hosts the FX
	# layer that floats damage numbers / sliding enemies above both.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
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

	# The board: a fixed-size Control holding two stacked layers. The lower one is
	# the static backdrop — GRID_ROWS x GRID_COLS empty panels, column 1 nearest the
	# hero — and the upper one is where enemies are positioned by hand, because an
	# enemy can span several cells and must be free to overlap its neighbours.
	_field = Control.new()
	_field.custom_minimum_size = _field_size()
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_battlefield.add_child(_field)

	var cell_layer := Control.new()
	cell_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	cell_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(cell_layer)
	# Every backdrop panel looks the same, so one shared StyleBox does for all of
	# them instead of GRID_ROWS x GRID_COLS identical copies.
	var empty_style: StyleBox = UITheme.flat(UITheme.BG.lerp(UITheme.PANEL, 0.4), 6, 4, 1, UITheme.BORDER.lerp(UITheme.BG, 0.3))
	for row in range(GameLoop2.GRID_ROWS):
		for col in range(1, GameLoop2.GRID_COLS + 1):
			var cell := PanelContainer.new()
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.position = _cell_pos(row, col)
			cell.size = Vector2(CELL, CELL)
			cell.add_theme_stylebox_override("panel", empty_style)
			cell_layer.add_child(cell)

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

	# Clear the overlays and the overflow lane; the backdrop panels are static.
	for layer in [_enemy_layer, _badge_layer]:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	_enemy_nodes.clear()
	for c in _offgrid_box.get_children():
		c.queue_free()

	# Enemies standing on the board, drawn BACK-TO-FRONT: a body lower on the grid
	# is nearer the viewer, so it paints over the ones above it where their
	# bounding boxes overlap. Sorting by the bottom edge of the footprint (then the
	# top edge, then the column) makes a tall enemy hang in front of what it
	# reaches down past.
	var placed: Array = []
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.OFFGRID_COL)) <= GameLoop2.GRID_COLS:
			placed.append(entry)
	placed.sort_custom(func(a, b): return _draw_order_key(a) < _draw_order_key(b))
	for entry in placed:
		_add_enemy_node(entry, false)

	# Off-field: the overflow queue, plus the game you're playing right now — it
	# isn't on the stack yet and only walks onto the board when you report the
	# result (that entrance is the one-game grace made visible, §7.2).
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.OFFGRID_COL)) > GameLoop2.GRID_COLS:
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

# The accent colour for an enemy whose front edge is at grid column `col`: red at
# the front (about to strike), amber a column back, gold farther out, orange for
# a boss.
static func threat_color(col: int, is_boss: bool) -> Color:
	if is_boss:
		return Color(0.95, 0.55, 0.2)
	if col <= 1:
		return UITheme.DANGER
	if col == 2:
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
	var front: int = GameLoop2.GRID_COLS
	for off in cells:
		front = mini(front, col + int(off.x))

	var stun: int = int(entry.get("stun", 0))
	var accent: Color = threat_color(front, e.is_boss())
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
	if e.is_boss():
		var skull := _corner_badge("☠", accent)
		skull.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 2)
		holder.add_child(skull)

	var hp: int = int(entry.get("health", e.health))
	var hp_lbl := _corner_badge("❤%d" % hp, Color(1.0, 0.5, 0.5))
	hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 2)
	holder.add_child(hp_lbl)

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
				click_enemy(int(entry.get("instance", 0)), entry, GameLoop2.OFFGRID_COL, is_current))
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

# Where every enemy is drawn right now: instance -> global Rect2 of its cell (or
# off-field token). Captured before a resolve and again after, so the difference
# is exactly the movement to animate.
func capture_positions() -> Dictionary:
	var out: Dictionary = {}
	if _battlefield == null:
		return out
	for inst in _enemy_nodes:
		var node: Control = _enemy_nodes[inst]
		if is_instance_valid(node):
			out[int(inst)] = node.get_global_rect()
	if _offgrid_box != null:
		for tok in _offgrid_box.get_children():
			if tok.has_meta("instance") and int(tok.get_meta("instance")) > 0:
				out[int(tok.get_meta("instance"))] = tok.get_global_rect()
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
	if _fx_layer == null:
		return
	for c in _fx_layer.get_children():
		c.queue_free()

# Play back the resolve the player just triggered: the front line strikes (each
# attacker flashes and throws its damage number at the hero, who recoils), then
# the whole field slides one column closer — including the game you just reported,
# which walks in from off-field onto the spawn column.
func animate_resolve(before: Dictionary, res: Dictionary) -> void:
	if _fx_layer == null or not is_inside_tree():
		return
	clear_fx()
	var after: Dictionary = capture_positions()

	# 1. The strike: flash each attacker where it stood and float its damage.
	var hero_rect: Rect2 = _hero_icon.get_global_rect()
	var struck: bool = false
	for a in res.get("attacks", []):
		if not (a is Dictionary) or not a.has("damage"):
			continue
		var inst: int = int(a.get("instance", 0))
		if not before.has(inst):
			continue
		struck = true
		var from: Rect2 = before[inst]
		_spawn_strike_flash(from)
		_spawn_damage_number(int(a["damage"]), from, hero_rect)
	if struck:
		_punch_hero()

	# 2. The advance: ghost-slide every enemy whose cell changed, after the strike
	#    has played. The real art stays hidden until its ghost lands.
	for inst in after.keys():
		if not before.has(inst):
			continue
		var from_rect: Rect2 = before[inst]
		var to_rect: Rect2 = after[inst]
		if from_rect.position.distance_to(to_rect.position) < 2.0:
			continue
		_spawn_slide_ghost(inst, from_rect, to_rect)

# A white burst over an attacking enemy's cell.
func _spawn_strike_flash(rect: Rect2) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.75)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.size = rect.size
	_fx_layer.add_child(flash)
	flash.global_position = rect.position
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
	lbl.global_position = from.position + Vector2(from.size.x * 0.25, 0)
	var target: Vector2 = hero.position + Vector2(hero.size.x * 0.25, -18)
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "global_position", target, FX_ATTACK_TIME * 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
# real one until it lands.
func _spawn_slide_ghost(instance: int, from_rect: Rect2, to_rect: Rect2) -> void:
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
	ghost.global_position = from_rect.position

	# Hide the settled body AND its badges while the ghost travels, so the enemy
	# isn't drawn in two places at once.
	var hidden: Array = []
	for part in [_holder_for_instance(instance), _badges_for_instance(instance)]:
		if part != null:
			part.modulate.a = 0.0
			hidden.append(part)

	var t := ghost.create_tween()
	t.tween_interval(FX_ATTACK_TIME)
	t.set_parallel(true)
	t.tween_property(ghost, "global_position", to_rect.position, FX_SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(ghost, "size", to_rect.size, FX_SLIDE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.chain().tween_callback(func():
		for part in hidden:
			if is_instance_valid(part):
				part.modulate.a = 1.0
		ghost.queue_free())

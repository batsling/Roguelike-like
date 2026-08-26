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

# The player picked a direction arrow on `instance` (Push), or clicked Bomb for
# it. The host owns the charge, so it decides whether the verb actually happens.
signal push_requested(instance: int, dir: Vector2i)
signal bomb_requested(instance: int)
# An AIMED ITEM was pointed at a body (Staff of Flame). The item is handed back
# with it because the board is only holding it while the aiming lasts — what to do
# with the pair is the overworld's, which owns the pack and the spending.
signal item_aimed(item: ItemData, instance: int)
# An aimed item was pointed at a CELL rather than a body (Red Candle, §17). Its
# own signal rather than a Vector2i squeezed through the one above, because the
# two are answered differently at the far end: a body is an instance handle the
# effect looks up, a cell is ground that may have nothing on it at all.
signal item_aimed_at_cell(item: ItemData, cell: Vector2i)
# A THROWN piece of loot was pointed at a cell (potions-design.md §4.2). Its own
# signal for the same reason again: what comes back is a loot ENTRY and the slot
# it came out of, and spending it is the overworld's — the board only held it
# while the aiming lasted. `index` is the pack slot, or -1 for a loose piece.
signal loot_thrown_at_cell(entry: Dictionary, index: int, cell: Vector2i)
# An armed throw was PUT AWAY without landing — the player pressed Cancel, or the
# board stopped having a square to aim at. Nothing was spent, and the screen that
# armed it needs to know so it can come back rather than leaving the player on a
# board with a bottle that has silently gone nowhere.
signal loot_throw_cancelled(entry: Dictionary, index: int)
# A Bomb was aimed at a CELL rather than at a body. Its own signal for the same
# reason `item_aimed_at_cell` is one: the far end spends the charge on ground
# (GameLoop2.bomb_cell) instead of on an instance handle.
signal bomb_cell_requested(cell: Vector2i)
# An enemy was clicked: the host opens the inspect card for it.
signal enemy_inspected(entry: Dictionary, col: int)
# Loot lying on the board was clicked (§8.2). The board knows where the thing is;
# what taking it costs — a slot in a pack that holds nine — is the host's, so this
# carries the square and nothing else.
signal drop_clicked(cell: Vector2i)
# The mouse moved onto (or off) a body. The host lights the checklist row that
# body's goal is written on, so "which of these lines is that thing" is answered
# by pointing at either half of the pair. `instance` is the body; `hovered` says
# which way it moved.
signal enemy_hovered(instance: int, hovered: bool)
# A repaint finished — the host repaints anything anchored to the board with it.
signal repainted
# The Health the board is showing moved. During a resolve playback that is NOT
# the run's Health (which moved all at once, at report time) but the number the
# strikes have got through so far — the host's HUD follows it so both copies of
# the number say the same thing.
signal shown_hp_changed(hp: int)

var _battlefield: HBoxContainer
# The amulet-pressure strip across the top of the board (§7.4): how many turns
# the enemies take per game, why, and how big the board they take them on is.
# This is the mechanic's home — it sits ON the thing it governs, so the pace and
# the field it plays out on are read in one glance.
var _pressure_panel: HoverPanel
# The full hops-to-turns ladder, as text. The hover draws a condensed card now,
# and this is kept because it is the LONG form the same facts have — the manual
# and any future full readout should quote this rather than re-derive it.
var _pressure_ladder_text: String = ""
var _pressure_turns: Label          # "⏱ EXTRA TURNS 1"
var _pressure_rungs: Array = []     # the three ladder pips, far -> near
var _pressure_why: Label            # "Amulet 4 hops away — Closing"
var _size_label: Label              # "▦ 5×5 · Medium"
var _hero_icon: TextureRect
var _hero_hp: Label
var _hero_statuses: HBoxContainer   # the player's statuses, under the portrait (§13)
# The Health the hero READS AS while a resolve plays back, or -1 when the label
# just says what GameState says. The run's Health moves the instant a game is
# reported — every strike of the resolve has already landed by the time the first
# one is drawn — so a label wired straight to GameState shows the total before
# the animation has shown a single blow. During a playback the label is driven by
# the strikes instead, dropping as each one connects (see animate_resolve).
var _hp_shown: int = -1
# Which playback the scheduled callbacks belong to. A resolve interrupted by the
# next one must not have its leftover timers keep subtracting from the new one's
# Health.
var _fx_gen: int = 0
# Shields — the armour the game in play granted (§3), drawn as pips over the hero:
# one per shield still standing, each of them one whole hit that will not land.
# Nothing hollow beside them any more: a lost run costs a turn of the board, not
# a shield, so they only ever go by being hit.
var _hero_shields: Label
var _field: Control                  # fixed-size board the two layers stack inside
var _cell_layer: Control             # the static backdrop of empty cells
# The board dimensions the backdrop was last drawn at. The grid can GROW mid-run
# (Mine-r Construction), so the panels are rebuilt when this stops matching
# GameLoop2 rather than being laid down once and trusted forever.
var _cells_drawn := Vector2i.ZERO
# The board's FURNITURE (§17), in two layers because the two halves belong on
# opposite sides of the bodies: units stand on the floor UNDER an enemy, and a
# tile effect is drawn as a strip at the foot of its cell OVER one, so that
# burning ground is still readable with something standing on it.
var _ground_layer: Control           # units, and the per-cell hover for both
var _tile_layer: Control             # the tile-effect strips, above every body
var _enemy_layer: Control            # free-positioned enemy nodes, drawn over the board
# Health / damage / status badges live on their own layer ABOVE every body, so an
# enemy overlapping another never hides what that other one is about to do to you.
var _badge_layer: Control
var _enemy_nodes: Dictionary = {}    # instance -> the node currently drawing it
# instance -> a Callable that repaints that body for the current lit/selected
# state. Rebuilt with the bodies on every refresh (a node's paint closes over its
# own frames), and the single way anything lights an enemy up.
var _repaint_fns: Dictionary = {}
# The body the mouse is actually over (0 = none), and the ones something ELSE
# asked to be lit — today the checklist rows beside the board (`highlight`).
# Either one lights a body; they are kept apart so a highlight ending doesn't
# darken a body the mouse is still sitting on.
var _hovered_instance: int = 0
var _highlighted: Dictionary = {}
var _offgrid_box: VBoxContainer      # overflow queue just off the grid's right edge
var _fx_layer: Control               # overlay for damage numbers + sliding ghosts
# Bodies (and their badges) currently hidden behind a travelling ghost. Held for
# the whole multi-turn playback rather than per slide — an enemy that walks on
# turn 1 and stands still on turn 3 has no last ghost to hand it back.
var _hidden_parts: Array = []
# Whether the game being played right now shows in the off-field lane. Kept from
# the last refresh so a click can repaint without the host passing it again.
# The hero portrait, resolved once per character rather than on every repaint.
var _hero_id: StringName = &""
var _hero_tex: Texture2D = null

var selected_instance: int = 0       # clicked enemy the combat verbs target (0 = none)
var push_btn: Button
var bomb_btn: Button
var aim_btn: Button                  # only on screen while an item is aiming
var _target_label: Label
var _hint_label: Label
# PUSH MODE. The verb is armed FIRST and aimed second: pressing Push arms it,
# clicking an enemy picks the body, and an arrow appears on every side of that
# body a shove could actually land on. Nothing is spent until an arrow is
# pressed, so arming and re-aiming are both free and Cancel costs nothing.
#
# It is a mode rather than a button-per-direction on the toolbar because the
# arrows have to be ON the board: "which way" is a question about a position, and
# four toolbar buttons would ask it a metre away from the thing being moved.
var push_mode: bool = false
# BOMB MODE, and the same bargain. Bomb used to fire the instant its button was
# pressed, at whatever body happened to still be selected — which was routinely a
# body clicked several turns earlier to read its card, so a charge went into an
# enemy the player was not looking at. It is armed and aimed like the Push now:
# pressing Bomb clears the selection and lights the bodies it could land on, and
# the CLICK is what spends the charge. One click after arming rather than two,
# because a bomb has no direction to pick.
var bomb_mode: bool = false
# THE AIMED ITEM, on the same bargain again: Staff of Flame is armed from the pack
# and aimed here, and the click on a body is what fires and spends it. Held as the
# item rather than as a bool because the board has to say WHICH relic is waiting —
# the pack is a scroll away from the board, and "something is armed" is not an
# answer the player can act on. null when nothing is aiming.
#
# Nothing is spent while it sits here, which is the whole reason the pack does not
# just fire it: a charged item that emptied its bar on the press would charge the
# player for opening a picker they then cancelled.
var aiming_item: ItemData = null
# THE THROWN PIECE OF LOOT, and the same bargain a third time (potions-design.md
# §4.2). A potion is armed from the use modal and aimed here, and the click on a
# square is what resolves it — the piece is not spent while it sits in this field,
# so backing out of the picker costs the player nothing.
#
# It is a loot ENTRY ({type, id}) rather than a resource, because that is what
# LootSystem spends and what a slot holds; `_throw_index` is the slot it came out
# of, or -1 for a loose piece taken on the spot. Empty when nothing is being
# thrown.
#
# It aims at GROUND like a tile-aimed item and never at a body, which is Red
# Candle's rule (§17.3) and is right here for the same reason: a Fire Potion
# thrown at empty ground two columns in front of the stack is one of the best
# things you can do with one, and a picker that only lit up bodies would make it
# impossible.
var throwing_loot: Dictionary = {}
var _throw_index: int = -1
# The bodies an armed verb can be pointed at, as a set of instance handles.
# Rebuilt at the top of every repaint (`refresh`) rather than asked per body, so
# the whole board is drawn against one answer.
var _armed: Dictionary = {}
var _arrow_layer: Control            # the direction arrows, above every body
# True for the duration of refresh(), and the reason is a real crash rather than
# bookkeeping. refresh() DETACHES every body on the board, and detaching the one
# the mouse happens to be over makes Godot fire that body's `mouse_exited` — from
# inside the loop that is removing it. The handler's job is to put the body back
# in its resting draw order, so it calls move_child on a parent that is mid-
# removal and Godot refuses it ("Parent node is busy setting up children"). The
# hover handlers check this and do nothing: the repaint is about to rebuild every
# node they would have been reordering anyway.
var _repainting: bool = false

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

# The grid cell edge, in px. It is NOT a constant, because the board is not a
# constant size: every difficulty step adds a column and a row (4x4 at Low up to
# 7x7 at Insane, and Mine-r Construction adds more on top), and a board drawn at
# a fixed 84px cell runs off the right of a 1280px page well before it gets
# there. So the cells are fitted to a WIDTH BUDGET instead — big and readable at
# 4x4, tighter as the ground opens up — which keeps the board inside the column
# it shares with the offering at every tier.
const CELL_MAX: int = 84            # cell edge on the smallest board
const CELL_MIN: int = 44            # never smaller than this, whatever the tier
const CELL_SEP: int = 6
# How wide the grid itself (cells + gutters, excluding the hero and the off-field
# lane) is allowed to get. Sized so the whole battlefield panel stays inside the
# right-hand column with the offering beside it — see Overworld2's stage.
const FIELD_WIDTH_BUDGET: int = 410
# …and how TALL. Same idea, other axis, and it exists for the same reason the
# width budget does: the overworld is meant to fit a 720p window without
# scrolling, and a board fitted only across still ran a 7x7 grid off the bottom
# of one. It binds on nothing but the big boards — a 4x4 is capped by CELL_MAX
# long before either budget is the constraint.
const FIELD_HEIGHT_BUDGET: int = 360
# …and what it drops to when something is mounted UNDER the board — a hub's shop,
# or the machines standing at this game. The right column is 626px of a 688px
# page with about five pixels to spare, so a panel below the board has nowhere to
# come from: it has to come out of the board. At 190 a 4x4 still draws at a
# readable cell and the page stays on one screen; the board springs back to the
# full budget the moment the panel goes, which is when you travel on.
const FIELD_HEIGHT_BUDGET_SHARED: int = 190

# The budget in force right now. Static, because `fitted_cell` is what every
# caller measures against and it is a static answer to "how big is a cell on a
# board this wide" — there is only ever one board on screen.
static var _height_budget: int = FIELD_HEIGHT_BUDGET

# Tell the board it is sharing its column (or has stopped). Returns true when the
# budget actually moved, so the caller only rebuilds when there is something to
# rebuild — this runs off a signal that fires for every machine press.
static func set_sharing_column(shared: bool) -> bool:
	var want: int = FIELD_HEIGHT_BUDGET_SHARED if shared else FIELD_HEIGHT_BUDGET
	if want == _height_budget:
		return false
	_height_budget = want
	return true

# The fitted cell edge and its step, recomputed whenever the grid changes size
# (_rebuild_cells). Everything that positions or sizes anything on the board
# reads these rather than a constant.
var _cell: int = CELL_MAX
var _cell_step: int = CELL_MAX + CELL_SEP

# The largest cell that fits a `cols` x `rows` board inside BOTH budgets, clamped
# to the readable range. The tiers add a column and a row together, so a square
# board is the normal case and `rows` defaults to matching; it is only passed
# separately by something that widens one axis on its own.
static func fitted_cell(cols: int, rows: int = -1) -> int:
	if cols <= 0:
		return CELL_MAX
	var r: int = rows if rows > 0 else cols
	var per_w: float = float(FIELD_WIDTH_BUDGET - (cols - 1) * CELL_SEP) / float(cols)
	var per_h: float = float(_height_budget - (r - 1) * CELL_SEP) / float(r)
	return clampi(int(floor(minf(per_w, per_h))), CELL_MIN, CELL_MAX)
# Shields (§3) share the overworld's steel blue.
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

	# A body's hover is the condensed version of the card its click opens: art,
	# name in its threat colour, what is riding on it, and when it next swings.
	func _make_custom_tooltip(_for_text: String) -> Object:
		return HoverCard.of(self)

# Board size in px: grid_cols() x grid_rows() cells with a gutter between them.
func _field_size() -> Vector2:
	return Vector2(
		GameLoop2.grid_cols() * _cell + (GameLoop2.grid_cols() - 1) * CELL_SEP,
		GameLoop2.grid_rows() * _cell + (GameLoop2.grid_rows() - 1) * CELL_SEP)

# Lay down the backdrop: one empty panel per cell, column 1 nearest the hero.
# Cheap and idempotent — it returns untouched unless the board actually changed
# size, which a difficulty step (§7.3) or a Mine-r Construction does, and then it
# also re-sizes the field so the new column and row have somewhere to be.
#
# When the board GREW, the cells that weren't there a moment ago are lit and
# pulsed in the accent colour. The board silently becoming a size larger is the
# kind of change a player feels ("that took longer to reach me") without ever
# seeing, so the new ground says so itself, wherever the growth came from.
# Re-fit the board to the budget in force now, without the grid having changed
# size. `_rebuild_cells` short-circuits on unchanged dimensions — right when the
# trigger is the board gaining a column, wrong when the trigger is the COLUMN IT
# LIVES IN being shared with a shop or a machine.
func refit() -> void:
	_cells_drawn = Vector2i(-1, -1)
	_rebuild_cells()
	refresh()


func _rebuild_cells() -> void:
	if _cell_layer == null:
		return
	var dims := Vector2i(GameLoop2.grid_cols(), GameLoop2.grid_rows())
	if dims == _cells_drawn:
		return
	var was: Vector2i = _cells_drawn
	_cells_drawn = dims
	# A wider board means smaller cells (fitted_cell): this is the one place the
	# board's size changes, so it is the one place the cell edge is re-fitted.
	_cell = fitted_cell(dims.x, dims.y)
	_cell_step = _cell + CELL_SEP
	_scale_hero()
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
			cell.size = Vector2(_cell, _cell)
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

# The hero rides the same scale as the cells: on a wide board the portrait is the
# other thing eating the row's width, and a 96px hero beside 48px cells reads as
# a mistake rather than as scale. Floored well above the cell so the character
# never becomes a thumbnail.
func _scale_hero() -> void:
	if _hero_icon == null:
		return
	var side: int = maxi(_cell, 64)
	_hero_icon.custom_minimum_size = Vector2(side, side)

# Top-left of grid cell (`row`, `col`) inside the board (0-based row, 1-based col).
func _cell_pos(row: int, col: int) -> Vector2:
	return Vector2((col - 1) * _cell_step, row * _cell_step)

# Pixel size of a footprint `cols` wide and `rows` tall, gutters included — the
# rect an enemy's art is drawn across.
func _span_size(rows: int, cols: int) -> Vector2:
	return Vector2(cols * _cell + (cols - 1) * CELL_SEP,
		rows * _cell + (rows - 1) * CELL_SEP)

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
	_pressure_panel = HoverPanel.new()
	# A FLOW row, not an HBox: everything on this strip is a fixed-width label, and
	# an HBox adds their widths up into a minimum the whole battlefield panel then
	# has to honour — which is how the board ended up wider than the page. Flowing
	# lets the strip take a second line on a narrow column instead.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 2)
	_pressure_panel.add_child(row)

	_pressure_turns = Label.new()
	_pressure_turns.add_theme_font_size_override("font_size", 14)
	row.add_child(_pressure_turns)

	# The ladder: one pip per EXTRA turn the end of a game can ever hand the board.
	# Filled up to where the run stands, so "how much worse can this get?" is
	# answerable without a tooltip — and empty out in the wilds, which is the
	# reading that matters: nothing is owed at the end of a game there.
	var ladder := HBoxContainer.new()
	ladder.add_theme_constant_override("separation", 2)
	_pressure_rungs.clear()
	for i in range(RunDifficulty.MAX_EXTRA_TURNS):
		var pip := Label.new()
		pip.add_theme_font_size_override("font_size", 15)
		ladder.add_child(pip)
		_pressure_rungs.append(pip)
	row.add_child(ladder)

	_pressure_why = Label.new()
	_pressure_why.add_theme_font_size_override("font_size", 12)
	_pressure_why.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	row.add_child(_pressure_why)

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
	var extra: int = GameLoop2.enemy_turns()
	var hops: int = GameLoop2.hops_to_amulet()
	var band: Color = RunDifficulty.band_color(extra)

	_pressure_panel.add_theme_stylebox_override("panel",
		UITheme.flat(band.lerp(UITheme.BG, 0.82), 6, 6, 1, band.lerp(UITheme.BG, 0.45)))
	# EXTRA TURNS, and the number is the whole of what the end of a game costs
	# (§7.4). Zero is the normal reading and says so plainly: hand a game in out
	# here and the board does not move. Everything else the stack does, it does
	# because you lost runs at the game (§3.2).
	_pressure_turns.text = "⏱  EXTRA TURNS  %d" % extra
	_pressure_turns.add_theme_color_override("font_color", band)

	for i in range(_pressure_rungs.size()):
		var pip: Label = _pressure_rungs[i]
		var lit: bool = i < extra
		pip.text = RUNG_ON if lit else RUNG_OFF
		pip.add_theme_color_override("font_color",
			band if lit else UITheme.TEXT_FAINT)

	# WHY it's that number. Without the hop count the turn count reads as a random
	# difficulty spike rather than as the price of the route the player chose.
	if hops < 0:
		_pressure_why.text = "no route to the Amulet"
	elif hops == 0:
		_pressure_why.text = "standing ON the Amulet — %s" % RunDifficulty.band_name(extra)
	else:
		_pressure_why.text = "Amulet %d hop%s away — %s" % [
			hops, "" if hops == 1 else "s", RunDifficulty.band_name(extra)]

	# EXTRA TURNS is the one readout on the board that is a CONSEQUENCE of a
	# decision made somewhere else — the route — so its hover has to answer "why is
	# it that number" as well as "what does it mean". The ladder itself is the
	# note: the whole table of hops-to-extra, which is where the answer is.
	var acts: String = ("Reporting a game hands the enemies %s"
		% RunDifficulty.extra_text(extra))
	var ladder_tip: String = ("%s.\n"
		+ "A turn is one action: strike from the front column, or step a column closer.\n"
		+ "Every run of the game you LOSE hands them one as well.\n\n"
		+ "%s\n\nRush the Amulet and the end of a game costs you turns; take the long "
		+ "way and only your own failures do.") % [acts, RunDifficulty.ladder_text(extra)]
	HoverCard.attach(_pressure_panel, {
		"title": "Extra turns %d" % extra,
		"subtitle": RunDifficulty.band_name(extra),
		"accent": band,
		"lines": [
			"%s — a strike from the front column, or a step closer." % acts,
			"A lost run hands them one turn wherever you are standing.",
			_pressure_why.text,
		],
		"note": "Rush the Amulet and the end of a game costs you turns; take the long way and only your own failures do.",
	})
	# The two labels inside it are MOUSE-TRANSPARENT so the panel owns the hover —
	# a card that changed shape depending on which word of the strip the cursor
	# landed on would read as three different cards.
	_pressure_turns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pressure_why.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pressure_turns.tooltip_text = ""
	_pressure_why.tooltip_text = ""
	_pressure_ladder_text = ladder_tip

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
	# Flowing for the same reason the pressure strip is: the hint, the target line
	# and the two verbs add up to more than the board is wide, and as an HBox that
	# sum became the panel's minimum width and pushed the board off the page.
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 4)

	_hint_label = Label.new()
	_hint_label.text = "Click an enemy:"
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	bar.add_child(_hint_label)

	_target_label = Label.new()
	_target_label.add_theme_font_size_override("font_size", 13)
	# Enough width that the usual "no target selected" doesn't make the verbs jump
	# when a name lands in it, but not so much that it sets the panel's width.
	_target_label.custom_minimum_size = Vector2(140, 0)
	_target_label.clip_text = true
	bar.add_child(_target_label)

	push_btn = Button.new()
	push_btn.add_theme_font_size_override("font_size", 13)
	push_btn.pressed.connect(toggle_push_mode)
	bar.add_child(push_btn)

	bomb_btn = Button.new()
	bomb_btn.add_theme_font_size_override("font_size", 13)
	bomb_btn.pressed.connect(toggle_bomb_mode)
	bar.add_child(bomb_btn)

	# The armed ITEM's way out. Hidden the rest of the time rather than greyed:
	# this toolbar is an HFlowContainer inside a board that fits its page to about
	# ten spare pixels (see refresh_toolbar), and a fourth permanent button wraps
	# it onto a second row. An item is armed for a few seconds at a time, and those
	# are the only seconds this needs to exist.
	aim_btn = Button.new()
	aim_btn.add_theme_font_size_override("font_size", 13)
	aim_btn.visible = false
	# One Cancel for whichever ground-aiming verb is up — the button stands in the
	# same place for both, so it disarms whichever one put it there.
	aim_btn.pressed.connect(cancel_aim)
	bar.add_child(aim_btn)
	return bar

# --- armed verbs -----------------------------------------------------------
#
# Push and Bomb are both ARMED first and AIMED second, and neither spends
# anything until the aiming click. The selection is cleared on the way in — a
# body left selected from reading its card is not a target the player just chose
# — and the board says who can be hit by LIGHTING THE BODIES rather than by
# printing an instruction: `armed_targets` is what the cells are drawn against.
#
# Only one can be armed at a time. Arming either puts the other away.

# Arm the Push verb: click a body, then pick one of the arrows that appear on it.
func begin_push() -> void:
	if push_mode or GameState.push <= 0:
		return
	push_mode = true
	bomb_mode = false
	aiming_item = null
	cancel_loot_throw()
	selected_instance = 0
	refresh()

func cancel_push() -> void:
	if not push_mode:
		return
	push_mode = false
	refresh()

func toggle_push_mode() -> void:
	if push_mode:
		cancel_push()
	else:
		begin_push()

# Arm the Bomb verb: the next body clicked is the one it goes off on.
func begin_bomb() -> void:
	if bomb_mode or GameState.bombs <= 0:
		return
	bomb_mode = true
	push_mode = false
	aiming_item = null
	cancel_loot_throw()
	selected_instance = 0
	refresh()

func cancel_bomb() -> void:
	if not bomb_mode:
		return
	bomb_mode = false
	refresh()

func toggle_bomb_mode() -> void:
	if bomb_mode:
		cancel_bomb()
	else:
		begin_bomb()

# Arm an ITEM: the next body clicked is the one it goes off on (Staff of Flame).
# The same shape as the Bomb, and deliberately so — an item that aims is a verb
# the player happens to be holding, and it should not have manners of its own.
# Returns false when there is nothing on the board to point it at, so the caller
# can say so rather than arming a picker over an empty field.
func begin_item_aim(item: ItemData) -> bool:
	if item == null:
		return false
	# A TILE-AIMED item points at GROUND, so an empty board is no obstacle — Red
	# Candle laying fire on an empty column is exactly what it is for, and the
	# "nothing to aim at" refusal below is about bodies. What it does need is a
	# legal cell inside its authored reach, which a board too narrow for the
	# columns it names would not have.
	if item.target_kind() == &"tile":
		if aim_cells(item).is_empty():
			return false
	elif GameLoop2.stack.is_empty():
		return false
	aiming_item = item
	push_mode = false
	bomb_mode = false
	cancel_loot_throw()
	selected_instance = 0
	refresh()
	return true

func cancel_item_aim() -> void:
	if aiming_item == null:
		return
	aiming_item = null
	refresh()

# Arm a THROWN piece of loot: the next square clicked is where the bottle lands.
# `index` is the pack slot it will be spent out of, or -1 for a loose piece.
#
# It aims at ground, so an empty board is no obstacle — throwing Fire at the
# squares in front of the stack is one of the best things you can do with a bottle
# (§4.2). What it does need is a board to aim at, which a run with no battlefield
# up does not have.
#
# NO CONFIRMATION FOLLOWS THE CLICK (decision #27). Arming the picker and clicking
# a square are two deliberate acts, and a dialog between them would sit in front of
# the fastest board verb in the game: a throw cannot land anywhere the player did
# not click.
func begin_loot_throw(entry: Dictionary, index: int = -1) -> bool:
	if entry.is_empty() or aim_cells(throw_request()).is_empty():
		return false
	throwing_loot = entry.duplicate(true)
	_throw_index = index
	aiming_item = null
	push_mode = false
	bomb_mode = false
	selected_instance = 0
	refresh()
	return true

func cancel_loot_throw() -> void:
	if throwing_loot.is_empty():
		return
	var put_back: Dictionary = throwing_loot
	var idx: int = _throw_index
	throwing_loot = {}
	_throw_index = -1
	loot_throw_cancelled.emit(put_back, idx)
	refresh()

# Put away whichever ground-aiming verb is armed. What the toolbar's one Cancel
# calls, so the button does not have to know which of the two it is cancelling.
func cancel_aim() -> void:
	cancel_item_aim()
	cancel_loot_throw()

# The armed item's own version of the charge check the other two verbs get: an
# item sold, dropped, spent elsewhere or emptied of charges is not aiming any
# more, and neither is one left armed over a board that has since been cleared.
func _check_aimed_item() -> void:
	if aiming_item == null:
		return
	if not GameState.can_fire_item(aiming_item):
		aiming_item = null
		return
	# A cleared board disarms a BODY-aimed item and not a tile-aimed one: ground is
	# still there when the last follower dies, and Red Candle laying fire down an
	# empty column is a perfectly good use of it (§17).
	if aiming_item.target_kind() == &"tile":
		if aim_cells(aiming_item).is_empty():
			aiming_item = null
	elif GameLoop2.stack.is_empty():
		aiming_item = null

# The same check for an armed THROW: a bottle sold, spent elsewhere or binned is
# not aiming any more, and neither is one left armed over a board that has no
# legal square left to aim at. A cleared board is NOT one of those cases — ground
# is still there when the last follower dies, and Fire in front of an empty stack
# is a perfectly good throw (§4.2).
func _check_thrown_loot() -> void:
	if throwing_loot.is_empty():
		return
	if aim_cells(throw_request()).is_empty():
		var put_back: Dictionary = throwing_loot
		var idx: int = _throw_index
		throwing_loot = {}
		_throw_index = -1
		loot_throw_cancelled.emit(put_back, idx)

# Whether a verb is waiting to be pointed at something.
func is_aiming() -> bool:
	return push_mode or bomb_mode or aiming_item != null or not throwing_loot.is_empty()

# The bodies an armed verb could actually land on, as instance handles. Empty
# when nothing is armed — this is what the board lights up, and it is the whole
# of the instruction the player gets.
#
# EVERY body on the board, with no exceptions. There used to be one: the enemy of
# the game being played could not be bombed or pushed, because it was that game's
# own and shoving it would have answered the game you had just committed to.
# Nothing belongs to a game any more (GameLoop2.arrivals), so nothing is exempt —
# what walked on this game takes a bomb exactly like what has been chasing you
# since the third. A boss is included too: the damage bounces off it, but that is
# the only way to land Sticky Bombs' stun, and a push moves it like anything else.
func armed_targets() -> Array:
	if not is_aiming():
		return []
	# A tile-aimed item lights up GROUND, not bodies (see aim_cells) — so the
	# bodies stay unlit and a click on one reads its card as usual, which is what
	# stops a picker for the floor from hijacking the board.
	if aiming_item != null and aiming_item.target_kind() == &"tile":
		return []
	# A THROW lights up ground for the same reason and by the same rule.
	if not throwing_loot.is_empty():
		return []
	var out: Array = []
	for entry in GameLoop2.stack:
		var inst: int = int(entry.get("instance", 0))
		if inst > 0:
			out.append(inst)
	return out

# The CELLS a ground-aimed thing could be pointed at right now: every square of
# the board inside the columns it authored, or every square when it authored no
# fence. This is both what the board lights up and what it accepts a click on, so
# the highlight and the rule are the same list.
#
# WIDENED PAST ItemData RATHER THAN FORKED (potions-design.md §4.2). It takes
# either an `ItemData` (Red Candle) or an AIM REQUEST — `{target_kind, col_min,
# col_max}`, which is what a thrown potion produces — because one highlight rule
# and one accepted-click rule is the whole reason this function exists. A second
# copy for the second kind of thing that aims at ground is a second place for the
# two to drift.
func aim_cells(what) -> Array:
	var req: Dictionary = _aim_request(what)
	if String(req.get("target_kind", "")) != "tile":
		return []
	var lo: int = int(req.get("col_min", 0))
	var hi: int = int(req.get("col_max", 0))
	if lo <= 0:
		lo = 1
	if hi <= 0:
		hi = GameLoop2.grid_cols()
	var out: Array = []
	for col in range(maxi(1, lo), mini(hi, GameLoop2.grid_cols()) + 1):
		for row in range(GameLoop2.grid_rows()):
			out.append(Vector2i(col, row))
	return out

# The aim request for whatever was handed in: an item's own authored reach, a
# request passed through unchanged, or the empty one for anything else (which
# lights nothing up).
#
# A THROWN POTION HAS NO FENCE — every square of the board is a legal target,
# because the whole board is where a bottle can be thrown and the potion's own
# `area=` decides what it covers from there.
func _aim_request(what) -> Dictionary:
	if what is ItemData:
		var fence: Vector2i = (what as ItemData).target_columns()
		return {"target_kind": String((what as ItemData).target_kind()),
			"col_min": fence.x, "col_max": fence.y}
	if what is Dictionary:
		return what
	return {}

# The request a thrown piece of loot aims with. Its own function so the answer to
# "where may a bottle land" is written down once.
func throw_request() -> Dictionary:
	return {"target_kind": "tile", "col_min": 0, "col_max": 0}

# Re-label and enable/disable the combat verbs for the current selection.
func refresh_toolbar() -> void:
	if push_btn == null:
		return
	# A charge spent elsewhere (or the last one spent here) disarms the verb — an
	# armed Push with nothing to spend is a board full of arrows that do nothing,
	# and an armed Bomb with none is a board lit up for a click that can't happen.
	if push_mode and GameState.push <= 0:
		push_mode = false
	if bomb_mode and GameState.bombs <= 0:
		bomb_mode = false
	_check_aimed_item()
	_check_thrown_loot()
	var entry: Dictionary = _stack_entry(selected_instance)
	var e: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	if e == null:
		# ARMED AND UNAIMED SAYS NOTHING. The instruction used to be printed here —
		# "click an enemy" — and it is redundant now that the bodies you could click
		# are the ones lit up on the board (ARMED_TINT). A verb that has to caption
		# its own highlight is a highlight that isn't working.
		_target_label.text = "" if is_aiming() else "no target selected"
		_target_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	else:
		_target_label.text = "▸ %s  (col %d, row %d)" % [
			e.display_name, int(entry.get("col", GameLoop2.spawn_col())),
			int(entry.get("row", 0)) + 1]
		_target_label.add_theme_color_override("font_color", UITheme.ACCENT)

	# The hint says which half of the verb the player is in. Both armed strings are
	# kept SHORTER than the idle one, and so is the button below: this is an
	# HFlowContainer inside a board that already fits its page to about ten spare
	# pixels, so a wordier armed state wraps the toolbar onto a second row and
	# pushes the bottom of the board off the window.
	if _hint_label != null:
		if push_mode:
			_hint_label.text = "⇤ Push:"
		elif bomb_mode:
			_hint_label.text = "✸ Bomb:"
		elif aiming_item != null:
			# The relic's own name, because the pack it was armed from is a scroll
			# away from here: "something is armed" is not an answer the player can
			# act on, and the lit bodies say everything else.
			_hint_label.text = "%s:" % aiming_item.display_name
		elif not throwing_loot.is_empty():
			# The bottle's own name for the same reason — and for a potion it is
			# doing a second job, since an UNKNOWN one is named by its colour and
			# that colour is the thing the player is about to learn.
			_hint_label.text = "🧪 Throw %s:" % LootSystem.display_name(throwing_loot)
		else:
			_hint_label.text = "Click an enemy:"
		_hint_label.add_theme_color_override("font_color",
			UITheme.ACCENT if is_aiming() else UITheme.TEXT_DIM)

	# The armed item's Cancel, on screen only while one is aiming — and while it is,
	# it stands in the OTHER TWO VERBS' place rather than beside them. Three buttons
	# plus this one wrap this HFlowContainer onto a second row and push the bottom
	# of the board off the window, which is the whole reason the armed strings above
	# are kept shorter than the idle ones. Nothing is lost by hiding them: arming
	# Push or Bomb would put the item away anyway (begin_push / begin_bomb), so
	# while a relic is aiming they are two buttons whose only effect is to cancel
	# it, and Cancel is right there saying so.
	# A THROW borrows the same Cancel, and the same standing-in for the other two
	# verbs: the bottle is not spent while the picker is up, so backing out costs
	# nothing and the button has to say so.
	var armed_aside: bool = aiming_item != null or not throwing_loot.is_empty()
	if aim_btn != null:
		aim_btn.visible = armed_aside
		if aiming_item != null:
			aim_btn.text = "✕  Cancel"
			aim_btn.tooltip_text = "Put %s away — nothing has been spent yet." \
				% aiming_item.display_name
		elif not throwing_loot.is_empty():
			aim_btn.text = "✕  Cancel"
			aim_btn.tooltip_text = "Put %s back in the pack — nothing has been spent yet." \
				% LootSystem.display_name(throwing_loot)
	push_btn.visible = not armed_aside
	bomb_btn.visible = not armed_aside

	push_btn.text = ("✕  Cancel" if push_mode else "⇤  Push (%d)" % GameState.push)
	push_btn.disabled = not push_mode and GameState.push <= 0
	if push_mode:
		push_btn.tooltip_text = "Put the Push away — nothing has been spent yet."
	elif GameState.push <= 0:
		push_btn.tooltip_text = "No Push charges left."
	else:
		push_btn.tooltip_text = "Shove one enemy a single cell — back, forward, or across into another lane. Press this, then click the enemy, then pick an arrow."

	# BOMB IS ARMED, NOT FIRED. It used to go off on the button press, at whatever
	# was still selected — so a body clicked three turns ago to read its card took
	# the charge. Now the press only arms it and the CLICK on a body spends it, so
	# the button gates on having a charge rather than on having a target.
	#
	# A boss is a legal target even though the damage bounces off it — that is the
	# only way to land Sticky Bombs' stun on one — and the tooltip carries the
	# caveat for whichever body is currently selected.
	bomb_btn.text = ("✕  Cancel" if bomb_mode else "✸  Bomb (%d)" % GameState.bombs)
	bomb_btn.disabled = not bomb_mode and GameState.bombs <= 0
	if bomb_mode:
		bomb_btn.tooltip_text = "Put the Bomb away — nothing has been spent yet."
	elif GameState.bombs <= 0:
		bomb_btn.tooltip_text = "No Bomb charges left."
	else:
		# A bomb goes off on a SQUARE, whether or not anything is standing on it, so
		# the promise names the ground when nothing is selected rather than telling
		# the player to select an enemy first (which is no longer true).
		bomb_btn.tooltip_text = ("Blow up any tile on the board — press this, then "
			+ "click the square. A body standing there takes 1 damage.") if e == null \
			else GameLoop2.bomb_hint(e)

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
	# Pips ABOVE the portrait: the hits you can still shrug off, in the same place
	# the damage numbers land, so a swing that a shield eats reads as the two
	# things meeting.
	_hero_shields = Label.new()
	_hero_shields.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_shields.add_theme_font_size_override("font_size", 18)
	_hero_shields.add_theme_color_override("font_color", SHIELD_BLUE)
	hero_box.add_child(_hero_shields)
	var hero_frame := PanelContainer.new()
	hero_frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 8, 8, 2, UITheme.ACCENT))
	_hero_icon = TextureRect.new()
	_hero_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_frame.add_child(_hero_icon)
	hero_box.add_child(hero_frame)
	_scale_hero()
	# Statuses BETWEEN the portrait and the health, so the hero column reads
	# top-to-bottom as "hits you can take / who you are / what is riding you / what is
	# left of you" (§13). Hidden entirely when nothing is on the player.
	_hero_statuses = HBoxContainer.new()
	_hero_statuses.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero_statuses.add_theme_constant_override("separation", 3)
	_hero_statuses.visible = false
	hero_box.add_child(_hero_statuses)
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

	# THE GROUND (§17): units, and the hover that reads whatever is on a cell.
	# BELOW the bodies, because that is where it is — a unit stands on the floor
	# and a body walks over it — and because tree order is input order here: an
	# enemy control mounted later gets the click first, so a hover region under it
	# only ever answers for ground nobody is standing on.
	_ground_layer = Control.new()
	_ground_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ground_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_ground_layer)

	_enemy_layer = Control.new()
	_enemy_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enemy_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_enemy_layer)

	# TILE EFFECTS, above the bodies and hugging the BOTTOM EDGE of their cell.
	# Above, because a fire tile under a 2x2 would be a fire tile nobody can see;
	# a shallow strip at the foot of the cell, because the point is to read the
	# ground WITHOUT losing the body standing on it. Never clickable — it overlaps
	# the bodies, and a strip that ate their clicks would make the front row
	# unselectable exactly when it matters.
	_tile_layer = Control.new()
	_tile_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_tile_layer)

	# Stats ride above every body — it's the last layer added to the board, so it
	# draws last. Non-interactive, so it never steals a click from the enemy
	# underneath it.
	_badge_layer = Control.new()
	_badge_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_badge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_badge_layer)

	# The push arrows go above even the badges — while the verb is armed they are
	# the only thing on the board that can be pressed, and an arrow half-hidden
	# under a health badge is an arrow that gets mis-clicked. Empty (and so
	# invisible and unclickable) whenever a push isn't being aimed.
	_arrow_layer = Control.new()
	_arrow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_field.add_child(_arrow_layer)

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
# in its grid cell (by column = distance) and the off-grid queue in the side lane.
#
# It takes no argument. It used to take `show_current`, which drew the enemy of
# the game being played in its own accent — a washed fill, a heavier ring and a
# NOW PLAYING tag in the overflow lane. There is no such body (GameLoop2.arrivals):
# every enemy on this board is a follower on the same terms, and drawing one of
# them differently was the board arguing with its own rules.
func refresh() -> void:
	if _battlefield == null:
		return
	# A verb that has run out of charges is not armed any more, whatever the last
	# click left set — asked here, before anything is drawn against it.
	if push_mode and GameState.push <= 0:
		push_mode = false
	if bomb_mode and GameState.bombs <= 0:
		bomb_mode = false
	_check_aimed_item()
	_check_thrown_loot()
	# Who an armed verb could be pointed at, answered once and drawn against by
	# every body below (see _style_enemy_cell). Empty whenever nothing is armed.
	_armed = {}
	for inst in armed_targets():
		_armed[int(inst)] = true
	# Detaching the body the mouse is over fires its own mouse_exited, and that
	# handler reorders the layer being torn down. See _repainting.
	_repainting = true
	refresh_hero()

	# The pace the enemies below move at, and the size of the board they move on.
	_refresh_pressure()

	# The backdrop only changes when the board does (a difficulty step, or a
	# Mine-r Construction), so this is a no-op on all but the refresh that
	# follows one — and on that one it also lights up the ground that just
	# appeared (see _rebuild_cells).
	_rebuild_cells()

	# Clear the overlays and the overflow lane; the backdrop panels are static.
	for layer in [_ground_layer, _tile_layer, _enemy_layer, _badge_layer, _arrow_layer]:
		for c in layer.get_children():
			layer.remove_child(c)
			c.queue_free()
	_enemy_nodes.clear()
	# The paint callables close over the frames of nodes that have just been freed,
	# so they go with them; the bodies below register fresh ones. `_highlighted`
	# does NOT reset — a checklist row the mouse is still on wants its enemies lit
	# on the other side of a repaint too.
	_repaint_fns.clear()
	_hovered_instance = 0
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
	# The enemy of the game being played right now stands on the board with
	# everything else (§7.2) — drawn with a thicker ring and a washed fill rather
	# than parked in a lane of its own, so "the thing I am playing for" is a body on
	# the field taking its turns like the rest.
	# The ground goes down before the bodies do, in both directions: the units and
	# the cell hovers into the layer under them, the tile strips into the layer
	# over them (see _rebuild_ground).
	_rebuild_ground()

	var placed: Array = []
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.offgrid_col())) <= GameLoop2.grid_cols():
			placed.append(entry)
	placed.sort_custom(func(a, b): return _draw_order_key(a) < _draw_order_key(b))
	for entry in placed:
		_add_enemy_node(entry)

	# Off-field: the overflow queue — bodies with nowhere on the board to stand,
	# which the current game's enemy can be one of when the back of the board is
	# already full.
	for entry in GameLoop2.stack:
		if int(entry.get("col", GameLoop2.offgrid_col())) > GameLoop2.grid_cols():
			_offgrid_box.add_child(_offgrid_token(entry))

	# Drop a selection that died / was bombed, then relabel the combat verbs.
	if selected_instance > 0 and _stack_entry(selected_instance).is_empty():
		selected_instance = 0
	refresh_toolbar()
	# After the toolbar, which is what can disarm the verb (no charges left).
	_refresh_push_arrows()
	_refresh_aim_cells()
	_repainting = false
	repainted.emit()

# --- the ground: tile effects and units (§17) ------------------------------

# How much of a cell's height the tile-effect art takes, measured from the BOTTOM
# edge up: exactly half, so the top of the art lands on the middle of the cell. The
# body standing there keeps its whole top half — its head and whatever the art
# uses to be recognisable — and the ground reads across its feet.
const TILE_STRIP_FRACTION: float = 0.5
# The unit's art, as a fraction of the cell. Smaller than a body on purpose: a
# Landmine is something lying ON the floor, and one drawn at full cell size reads
# as another enemy.
const UNIT_ART_FRACTION: float = 0.62

# Paint everything on the board that is not a body: units into `_ground_layer`
# (under the enemies), tile-effect strips into `_tile_layer` (over them), and one
# hover region per furnished cell into the ground layer so the player can read
# what is on a square they can see.
#
# The hover lives in the LOWER layer deliberately. Tree order is input order, so
# an enemy control mounted afterwards takes the click first: a cell with a body on
# it answers with the body's own card, and only bare ground answers with the
# ground. That is the right precedence and it costs no branching to get.
func _rebuild_ground() -> void:
	if _ground_layer == null or _tile_layer == null:
		return
	var furnished: Dictionary = {}
	for cell in GameLoop2.units.keys():
		furnished[cell] = true
	for cell in GameLoop2.tiles.keys():
		furnished[cell] = true
		var tile: TileEffectData = GameLoop2.tile_at(cell)
		if tile != null:
			_tile_layer.add_child(_tile_strip(cell, tile))
	for cell in GameLoop2.units.keys():
		var unit: UnitData = GameLoop2.unit_at(cell)
		if unit != null:
			_ground_layer.add_child(_unit_node(cell, unit))
	for cell in furnished.keys():
		_ground_layer.add_child(_ground_hover(cell))
	# The drops LAST, so they take the press on a square that also has ground under
	# them: tree order is input order here (see the header above), and loot is the
	# one thing on bare floor that answers a click rather than a hover. Bodies are
	# mounted in the layer above and would still win — which never comes up, because
	# a body moving onto a piece shoves it aside (GameLoop2._move_entry).
	for cell in GameLoop2.drop_cells():
		_ground_layer.add_child(_drop_node(cell))

# The tile's art, sitting on the bottom half of its cell. THE ART AND NOTHING
# ELSE — no panel behind it and no outline around it, so whatever the art doesn't
# cover stays see-through and the body underneath reads through the gaps. A wash
# would have made every furnished cell a solid block; a border would have drawn a
# box the effect does not actually have edges at.
#
# `KEEP_ASPECT` rather than `KEEP_ASPECT_COVERED`, so the WHOLE image is shown —
# covered fills the box by cropping whatever overflows, which quietly ate the top
# and bottom of a square flame in a half-height box. Fitted and centred, the art
# is as tall as the half-cell and the top of it lands on the cell's midline.
func _tile_strip(cell: Vector2i, tile: TileEffectData) -> Control:
	var height: int = maxi(10, int(round(_cell * TILE_STRIP_FRACTION)))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = _cell_pos(cell.y, cell.x) + Vector2(0, _cell - height)
	holder.size = Vector2(_cell, height)
	if tile.image != null:
		var art := UITheme.crisp_tex(tile.image, height)
		art.custom_minimum_size = Vector2(_cell, height)
		art.size = Vector2(_cell, height)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(art)
	return holder

# A unit lying on the floor: its art, centred in the cell and drawn small.
func _unit_node(cell: Vector2i, unit: UnitData) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = _cell_pos(cell.y, cell.x)
	holder.size = Vector2(_cell, _cell)
	if unit.image != null:
		var side: int = maxi(16, int(round(_cell * UNIT_ART_FRACTION)))
		var art := UITheme.crisp_tex(unit.image, side)
		art.position = Vector2((_cell - side) * 0.5, (_cell - side) * 0.5)
		art.size = Vector2(side, side)
		holder.add_child(art)
	return holder

# --- loot on the floor (§8.2) -----------------------------------------------

# The glyph the floor is drawn with when its art will not load, and the gold a
# drop is ringed in. The ring stayed gold when the contents became loot: it is the
# board saying "this is a thing you can pick up", and it is the same colour on the
# haul screen's heading.
const CHEST_GLYPH := "✦"
const CHEST_GOLD := Color(1.0, 0.83, 0.36)
# How much of the cell the token takes. Smaller than a body for the reason a unit
# is: this is something LYING on the square, not standing on it.
const CHEST_ART_FRACTION: float = 0.58

# Loot lying on `cell`: a pressable token in the middle of the square. Pressing it
# asks the host to open it (`drop_clicked`), which is the same LootDropModal the
# haul screen would have asked with — the floor is a place a piece can be answered
# EARLIER, not a second kind of reward.
#
# IT WEARS ITS OWN ART (§8.2). What fell used to be a relic chest, and a chest is
# a question the board is not allowed to answer, so the square could only show a
# gold glyph. A scroll, a pill or a potion IS a thing: it is drawn as the picture
# the pack and the loot window draw it as, so a piece is recognised across the
# board — and an unidentified one still shows only the anonymous vial or capsule
# it shows everywhere else, which is the whole of what the player is allowed to
# know.
#
# THE HORSE DOSE COMES BACK BIGGER here too (LootSystem.art_box, §4.3): the token
# takes its size from the art rather than from a constant, so the one tell that
# distinguishes a horse pill survives being drawn on a battlefield. It still fits
# inside the square — 0.58 of a cell at 1.3x is under three quarters of one.
func _drop_node(cell: Vector2i) -> Control:
	var held: Dictionary = GameLoop2.drop_at(cell)
	var entry = held.get("loot")
	var loot: Dictionary = entry if entry is Dictionary else {}
	var base: int = maxi(20, int(round(_cell * CHEST_ART_FRACTION)))
	var side: int = maxi(base, LootSystem.art_box(loot, base)) if not loot.is_empty() else base
	var btn := Button.new()
	btn.position = _cell_pos(cell.y, cell.x) + Vector2((_cell - side) * 0.5, (_cell - side) * 0.5)
	btn.size = Vector2(side, side)
	btn.custom_minimum_size = Vector2(side, side)
	# A boss's drop is ringed thicker, the same way its body is: what fell there is
	# worth crossing the board for.
	var ring: int = 3 if bool(held.get("boss", false)) else 2
	btn.add_theme_stylebox_override("normal",
		UITheme.flat(Color(CHEST_GOLD, 0.16), 6, 0, ring, CHEST_GOLD))
	btn.add_theme_stylebox_override("hover",
		UITheme.flat(Color(CHEST_GOLD, 0.40), 6, 0, ring, Color.WHITE))
	btn.add_theme_stylebox_override("pressed",
		UITheme.flat(Color(CHEST_GOLD, 0.58), 6, 0, ring, Color.WHITE))
	btn.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 6, 0, 0))
	var art: Texture2D = LootSystem.art_texture(loot) if not loot.is_empty() else null
	if art != null:
		# Inset by the ring so the picture sits inside the frame rather than under
		# it, and mouse-transparent (crisp_tex already is) so the press belongs to
		# the button underneath.
		var pad: int = ring + 1
		var tex: TextureRect = UITheme.crisp_tex(art, side - pad * 2)
		tex.position = Vector2(pad, pad)
		tex.size = Vector2(side - pad * 2, side - pad * 2)
		btn.add_child(tex)
	else:
		# No art to draw — an empty square, or a kind whose picture is missing. The
		# glyph is what the floor wore before loot landed on it, and it still says
		# "something is here" rather than leaving a bare ring.
		btn.text = CHEST_GLYPH
		btn.add_theme_color_override("font_color", CHEST_GOLD)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_font_size_override("font_size", maxi(12, int(side * 0.5)))
	HoverCard.attach(btn, drop_hover(cell))
	btn.pressed.connect(func(): drop_clicked.emit(cell))
	return btn

# What loot on the floor says when you point at it: the SAME card the pack, the
# loot window and the drop modal show for that piece (LootSystem.hover_card), plus
# the two things that are only true of a piece lying on a battlefield — where it
# is, and what happens to it if you leave it there.
#
# Which is the change of heart the floor's contents bought. A chest's card
# deliberately said nothing about what was inside, because reading the answer off
# a tooltip would have made opening it a formality; loot has no such secret to
# keep. An unidentified piece still keeps its own — it reads "Unidentified Pill"
# here exactly as it does in the pack.
func drop_hover(cell: Vector2i) -> Dictionary:
	var held: Dictionary = GameLoop2.drop_at(cell)
	if held.is_empty():
		return {}
	var entry = held.get("loot")
	if not (entry is Dictionary) or (entry as Dictionary).is_empty():
		return {}
	var card: Dictionary = LootSystem.hover_card(entry)
	card["subtitle"] = "%s  ·  on the floor, column %d, row %d" \
		% [String(card.get("subtitle", "")), cell.x, cell.y + 1]
	var lines: Array = (card.get("lines", []) as Array).duplicate()
	lines.append("Click to pick it up — or use it, or bin it.")
	lines.append("Left lying when you report the game, it goes to the haul screen with everything else.")
	if bool(held.get("boss", false)):
		lines.append("A boss left this.")
	card["lines"] = lines
	return card

# The invisible hover region that reads a furnished cell. One per cell, carrying
# the same HoverCard an enemy, an item and a status get — the ground used to
# answer with Godot's grey system tooltip, which is the one thing on this board
# that looked like it belonged to another program.
#
# A HoverBox rather than a bare Control because the card only appears on a class
# that defines `_make_custom_tooltip` (see HoverCard's header), and a VBoxContainer
# with no children draws nothing, which is what an invisible hot spot has to do.
func _ground_hover(cell: Vector2i) -> Control:
	var hot := HoverBox.new()
	hot.mouse_filter = Control.MOUSE_FILTER_STOP
	hot.position = _cell_pos(cell.y, cell.x)
	hot.size = Vector2(_cell, _cell)
	HoverCard.attach(hot, ground_hover(cell))
	return hot

# The hover model for whatever is on `cell`. Public, so a test can ask what a
# square would say without going near the mouse.
#
# ONE CARD for a square with both a unit and a tile effect on it: "what is on this
# square" is one question and two cards stacked on one cell would be two answers
# to it. The UNIT heads the card — it is the thing standing there, and the thing
# whose Health is about to matter — and the tile joins it as a pip and a line, the
# same way a status rides an enemy's card rather than opening one of its own.
func ground_hover(cell: Vector2i) -> Dictionary:
	var tile: TileEffectData = GameLoop2.tile_at(cell)
	var unit: UnitData = GameLoop2.unit_at(cell)
	if unit == null:
		return tile.hover_card(GameLoop2.tile_games_left(cell)) if tile != null else {}
	var held = GameLoop2.units.get(cell, {})
	var card: Dictionary = unit.hover_card(int(held.get("health", unit.health)))
	if tile != null:
		var ground: Dictionary = tile.hover_card(GameLoop2.tile_games_left(cell))
		card["pips"] = (card.get("pips", []) as Array) + (ground.get("pips", []) as Array)
		card["lines"] = (card.get("lines", []) as Array) + [
			"Standing on %s." % tile.display_name] + (ground.get("lines", []) as Array)
	return card

# What an armed verb's legal targets are ringed in. Deliberately the ACCENT the
# selection already uses rather than a new colour: "the verb is pointed at this"
# and "this is one of the things it could be pointed at" are the same idea one
# step apart, and a third hue on a board that already carries four threat colours
# is one more thing to learn.
const ARMED_TINT := Color(1.0, 0.72, 0.30)

# Paint an enemy's footprint tiles for its current state. Hovering brightens the
# outline and lifts the fill (the "you can click this" cue); the selected enemy —
# the one the toolbar's Push / Bomb act on — keeps a thick accent ring. `frames`
# is one PanelContainer per cell the enemy fills, so an L reads as an L.
#
# The tiles sit UNDER the art and nowhere else. There was briefly a second set of
# outline-only tiles drawn ON TOP of it, so that a sprite filling its square edge
# to edge still showed a border — but a grid line ruled across every enemy's
# picture costs more than the border buys, and the threat colour, the selection
# ring and the hover cue all still read off the fill and the parts of the frame
# the art doesn't cover.
func _style_enemy_cell(frames: Array, accent: Color, selected: bool,
		hovered: bool, aimable: bool = false) -> void:
	var border: Color = accent
	var width: int = 2
	var fill: Color = UITheme.PANEL
	# ARMED. A verb is waiting to be pointed at something, and this body is one of
	# the things it could be pointed at — so the board says so, instead of a line of
	# toolbar text saying "click an enemy". The bodies that are NOT targets (the
	# enemy of the game being played) are left exactly as they were, so the lit set
	# reads as a set rather than as a colour change across the whole field.
	if aimable:
		border = ARMED_TINT
		width = 3
		fill = fill.lerp(ARMED_TINT, 0.28)
	# There used to be a washed fill here for "the enemy of the game being played",
	# so that body was tellable from its neighbours. It isn't one any more — every
	# body on this board is a follower on the same terms (GameLoop2.arrivals) — and
	# a treatment that says one of them is different would be a lie about the rules.
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

# --- lighting a body up from outside the board -----------------------------

# Is this body currently lit — because the mouse is on it, or because something
# else asked for it (a checklist row being hovered)?
func _is_lit(instance: int) -> bool:
	return instance > 0 and (_hovered_instance == instance or _highlighted.has(instance))

# Light exactly `instances` (an Array of instance handles) and darken everything
# else. The board is one half of a pair — the goals on the checklist beside it are
# the other — and pointing at either half should light both, so the host calls
# this as the mouse crosses a row. Pass [] to clear.
#
# Repaints only the bodies whose state actually changed, so a mouse dragged down
# a checklist doesn't restyle the whole board on every row.
func highlight(instances: Array = []) -> void:
	var want: Dictionary = {}
	for inst in instances:
		if int(inst) > 0:
			want[int(inst)] = true
	if want == _highlighted:
		return
	var touched: Dictionary = {}
	for inst in _highlighted:
		touched[inst] = true
	for inst in want:
		touched[inst] = true
	_highlighted = want
	for inst in touched:
		var fn: Variant = _repaint_fns.get(inst)
		if fn is Callable and (fn as Callable).is_valid():
			(fn as Callable).call()

# Clicking an enemy. What that means depends on whether a verb is armed: with a
# Push armed it AIMS, with a Bomb armed it FIRES, and with neither it selects the
# body and opens its info card.
func click_enemy(instance: int, entry: Dictionary, col: int) -> void:
	# EVERY body answers this the same way. There used to be an exemption for the
	# enemy of the game in play — it could not be selected, bombed or pushed,
	# because it was that game's own and shoving it would have answered the game
	# you had just committed to. Nothing belongs to a game now
	# (GameLoop2.arrivals), so nothing is exempt.
	selected_instance = instance
	# An armed BOMB goes off here. This click is the whole of the aiming — a bomb
	# has no direction to pick — so it is also what spends the charge, which is why
	# nothing was spent when the button was pressed. The verb disarms itself either
	# way: one press, one bomb.
	if bomb_mode:
		bomb_mode = false
		bomb_requested.emit(instance)
		return
	# An armed ITEM fires here for the same reason and on the same click. The board
	# lets go of it first: what it costs and whether it lands are the overworld's
	# to decide, and a board still holding an armed relic afterwards would be a
	# second press away from firing a spent one.
	if aiming_item != null:
		var armed: ItemData = aiming_item
		aiming_item = null
		item_aimed.emit(armed, instance)
		return
	# WHILE A THROW IS ARMED, a click on a body is not a request to read its card —
	# the picker's squares are drawn over the board and the body under one of them
	# is exactly what the player is aiming at. Swallowed here rather than routed,
	# because the lit square above it already took the press.
	if not throwing_loot.is_empty():
		refresh()
		return
	# While a push is being aimed the click is the AIM, not a request to read the
	# card: a full-screen info card over the board would bury the arrows the same
	# click just put there.
	if push_mode:
		refresh()
		return
	enemy_inspected.emit(entry, col)
	refresh()

# --- aiming at the ground (§17) --------------------------------------------

# EVERY SQUARE AN ARMED VERB COULD BE POINTED AT, as one list. Two verbs aim at
# ground: a tile-aimed item inside the columns it authored (Red Candle), and the
# BOMB, which can be spent on any square of the board — an empty one included,
# because with Hot Bombs that is how fire gets laid in front of the stack and with
# Brimstone it is how a cross is aimed down a lane rather than off whoever happens
# to be standing in one.
#
# Empty when no ground-aiming verb is armed, which is what the picker draws
# against.
func target_cells() -> Array:
	if bomb_mode:
		return GameLoop2.target_cells("all")
	if not throwing_loot.is_empty():
		return aim_cells(throw_request())
	return aim_cells(aiming_item)

# The cell picker a ground-aiming verb arms. Buttons over every legal square, in
# the topmost layer — the same place and for the same reason the push arrows live
# there: while a verb is armed, the things it can be pointed at should be the only
# things on the board that take a press.
#
# THE FILLS ARE TRANSLUCENT (alpha, not a lerp toward the background) and the
# buttons are NOT `flat`. Both matter: `flat` makes a Button skip its stylebox
# entirely, so the picker used to be eight invisible squares — legal, clickable,
# and completely unmarked — and an opaque wash would hide the body standing on the
# square the bomb is about to go off on.
#
# Nothing is drawn unless such a verb is armed, so the board is unchanged the rest
# of the time.
func _refresh_aim_cells() -> void:
	if _arrow_layer == null:
		return
	for cell in target_cells():
		var btn := Button.new()
		btn.position = _cell_pos(cell.y, cell.x)
		btn.size = Vector2(_cell, _cell)
		btn.custom_minimum_size = Vector2(_cell, _cell)
		btn.tooltip_text = _target_cell_hint(cell)
		btn.add_theme_stylebox_override("normal",
			UITheme.flat(Color(ARMED_TINT, 0.16), 6, 0, 2, ARMED_TINT))
		btn.add_theme_stylebox_override("hover",
			UITheme.flat(Color(ARMED_TINT, 0.38), 6, 0, 2, Color.WHITE))
		btn.add_theme_stylebox_override("pressed",
			UITheme.flat(Color(ARMED_TINT, 0.55), 6, 0, 2, Color.WHITE))
		btn.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 6, 0, 0))
		btn.pressed.connect(_click_cell.bind(cell))
		_arrow_layer.add_child(btn)

# What one lit square promises, for its own tooltip. The bomb's version is asked
# of the loop (`bomb_cell_hint`) so the picker and the rule can't drift; an item's
# is its own name, since what it does is written on its card.
func _target_cell_hint(cell: Vector2i) -> String:
	if bomb_mode:
		var entry: Dictionary = _entry_at(cell)
		if not entry.is_empty():
			return GameLoop2.bomb_hint(entry.get("enemy"))
		return GameLoop2.bomb_cell_hint(cell)
	if aiming_item != null:
		return "Aim %s here (column %d, row %d)." % [
			aiming_item.display_name, cell.x, cell.y + 1]
	if not throwing_loot.is_empty():
		return "Throw %s here (column %d, row %d)." % [
			LootSystem.display_name(throwing_loot), cell.x, cell.y + 1]
	return ""

# The stack entry whose footprint covers `cell`, or {} for bare ground. First
# match wins — footprints don't overlap (`occupancy`), so there is only ever one.
func _entry_at(cell: Vector2i) -> Dictionary:
	for entry in GameLoop2.stack:
		if GameLoop2.entry_cells(entry).has(cell):
			return entry
	return {}

# A cell picked while a ground-aiming verb was armed. The board lets go of the
# verb first, exactly as `click_enemy` does with a body-aimed one: what it costs
# and whether it lands is the overworld's, and a board still holding a spent relic
# would be one press from firing it again.
#
# A BOMB CLICKED ON AN OCCUPIED SQUARE is still a bomb aimed at that BODY, routed
# through `bomb_requested` like a click on the body itself. The two are the same
# press to the player, and only the body-aimed path carries the target through to
# the blast — which is what a boss (immune to the damage, stunnable by Sticky
# Bombs) and the `bomb_used` trigger read.
func _click_cell(cell: Vector2i) -> void:
	if bomb_mode:
		bomb_mode = false
		var entry: Dictionary = _entry_at(cell)
		if not entry.is_empty():
			bomb_requested.emit(int(entry.get("instance", 0)))
		else:
			bomb_cell_requested.emit(cell)
		refresh()
		return
	# A THROWN BOTTLE lands here, and the board lets go of it first for the reason
	# every other armed verb does: what it costs and what it does are the
	# overworld's, and a board still holding a spent piece would be one press from
	# throwing it twice.
	if not throwing_loot.is_empty():
		var thrown: Dictionary = throwing_loot
		var idx: int = _throw_index
		throwing_loot = {}
		_throw_index = -1
		loot_thrown_at_cell.emit(thrown, idx, cell)
		refresh()
		return
	if aiming_item == null:
		return
	var armed: ItemData = aiming_item
	aiming_item = null
	item_aimed_at_cell.emit(armed, cell)
	refresh()

# --- the push arrows -------------------------------------------------------

# Edge of an arrow button, and the gap between it and the body it belongs to.
const ARROW_SIZE: int = 30
const ARROW_GAP: int = 3

# One arrow per direction the selected body could actually be shoved in, laid
# against the matching side of its footprint's bounding box. Nothing is drawn
# unless a push is armed AND a target is picked, so the board is unchanged the
# rest of the time.
#
# A target with no legal direction at all (boxed in on all four sides) says so in
# words instead — an empty board around a selected enemy would otherwise read as
# "the arrows haven't appeared yet".
func _refresh_push_arrows() -> void:
	if _arrow_layer == null:
		return
	if not push_mode or selected_instance <= 0:
		return
	var entry: Dictionary = _stack_entry(selected_instance)
	var e: GoalEnemyData = entry.get("enemy") if not entry.is_empty() else null
	if e == null:
		return
	var row: int = int(entry.get("row", 0))
	var col: int = int(entry.get("col", GameLoop2.spawn_col()))
	var span: Vector2 = _span_size(e.footprint_rows(), e.footprint_cols())
	var centre: Vector2 = _cell_pos(row, col) + span * 0.5
	var dirs: Array = GameLoop2.push_directions(selected_instance)
	if dirs.is_empty():
		_arrow_layer.add_child(_no_room_note(centre, e))
		return
	for dir: Vector2i in dirs:
		# Never both axes at once, so each side of the box is offset on its own.
		var at := Vector2(
			centre.x + float(dir.x) * (span.x * 0.5 + ARROW_SIZE * 0.5 + ARROW_GAP),
			centre.y + float(dir.y) * (span.y * 0.5 + ARROW_SIZE * 0.5 + ARROW_GAP))
		_arrow_layer.add_child(_push_arrow(dir, at, e))

# Column 1 is the lane nearest the hero and the hero is drawn to the LEFT of the
# board, so a push BACK (col + 1) travels right across the screen. These glyphs
# are the screen directions, not the grid's.
func push_arrow_glyph(dir: Vector2i) -> String:
	if dir == GameLoop2.PUSH_FORWARD:
		return "◀"
	if dir == GameLoop2.PUSH_UP:
		return "▲"
	if dir == GameLoop2.PUSH_DOWN:
		return "▼"
	return "▶"

# What spending the charge this way actually buys, per direction — the arrows are
# the only place the four are told apart, so each one says what it is for.
func push_arrow_tip(dir: Vector2i, e: GoalEnemyData) -> String:
	var who: String = e.display_name if e != null else "it"
	if dir == GameLoop2.PUSH_FORWARD:
		return "Shove %s one column CLOSER. It gets a free step toward you — but it clears the space behind it." % who
	if dir == GameLoop2.PUSH_UP or dir == GameLoop2.PUSH_DOWN:
		return "Shove %s %s a lane. Enemies never change lanes on their own, so this is the only way to move one out of the row it's coming down." % [
			who, "up" if dir == GameLoop2.PUSH_UP else "down"]
	return "Shove %s one column BACK, buying the games it takes to close in again." % who

func _push_arrow(dir: Vector2i, at: Vector2, e: GoalEnemyData) -> Button:
	var b := Button.new()
	b.text = push_arrow_glyph(dir)
	b.tooltip_text = push_arrow_tip(dir, e)
	b.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	b.position = at - Vector2(ARROW_SIZE, ARROW_SIZE) * 0.5
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", UITheme.ACCENT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal",
		UITheme.flat(UITheme.BG.lerp(UITheme.ACCENT, 0.3), 6, 0, 2, UITheme.ACCENT))
	b.add_theme_stylebox_override("hover",
		UITheme.flat(UITheme.ACCENT.lerp(UITheme.BG, 0.35), 6, 0, 2, Color.WHITE))
	b.add_theme_stylebox_override("pressed",
		UITheme.flat(UITheme.ACCENT.lerp(UITheme.BG, 0.2), 6, 0, 2, Color.WHITE))
	b.set_meta("push_dir", dir)
	var inst: int = selected_instance
	b.pressed.connect(func():
		# Disarmed on the way out, so one press of Push spends at most one charge
		# and the arrows don't linger over a body that has already moved.
		push_mode = false
		push_requested.emit(inst, dir))
	return b

func _no_room_note(centre: Vector2, e: GoalEnemyData) -> Control:
	var l := Label.new()
	l.text = "boxed in"
	l.tooltip_text = "%s has no free cell on any side — nowhere to shove it." % e.display_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(90, 16)
	l.position = centre - Vector2(45, 8)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.DANGER)
	return l

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
func _add_enemy_node(entry: Dictionary) -> Control:
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
	var accent: Color = threat_color(front, e.is_boss(), GameLoop2.lost_runs_until_strike(entry))
	if stun > 0:
		accent = accent.lerp(Color(0.5, 0.7, 1.0), 0.5)
	var inst: int = int(entry.get("instance", 0))
	var selected: bool = inst > 0 and inst == selected_instance

	# The node covers the bounding box, but only answers the mouse over the cells
	# the enemy really fills — an L's notch belongs to whoever stands in it.
	var node := FootprintControl.new()
	node.cells = cells
	node.cell_size = float(_cell)
	node.step = float(_cell_step)
	node.position = _cell_pos(row, col)
	node.size = _span_size(rows, cols)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	HoverCard.attach(node, enemy_hover(entry, e))
	node.set_meta("instance", inst)
	_enemy_layer.add_child(node)
	_enemy_nodes[inst] = node

	# One frame per filled cell, positioned inside the node.
	var frames: Array = []
	for off in cells:
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.position = Vector2(off.x, off.y) * float(_cell_step)
		frame.size = Vector2(_cell, _cell)
		node.add_child(frame)
		frames.append(frame)

	# Repainting this body is one callable, registered by instance, because the
	# board is no longer the only thing that lights an enemy up: the checklist
	# beside it highlights the bodies whose goals a row belongs to (see
	# `highlight`), and both routes have to end at the same paint.
	var repaint := func() -> void:
		_style_enemy_cell(frames, accent, inst == selected_instance, _is_lit(inst),
			_armed.has(inst))
	_repaint_fns[inst] = repaint
	repaint.call()

	# Enemies are click-to-inspect: hovering brightens the outline to advertise it
	# and lifts the whole body above its neighbours so an overlapped enemy can be
	# seen in full; clicking selects it and opens its info card. The lift is a
	# reorder within the enemy layer, not a z_index, so a hovered body still stays
	# under the badges and under anything mounted above the battlefield.
	var resting_index: int = node.get_index()
	# Both guards matter. `_repainting` catches the exit fired BY the repaint that
	# is deleting this node; the parent check catches a node already detached by
	# anything else, since move_child on a foster parent is equally invalid.
	var can_reorder := func() -> bool:
		return not _repainting and is_instance_valid(node) \
			and node.get_parent() == _enemy_layer
	node.mouse_entered.connect(func():
		if not can_reorder.call():
			return
		_hovered_instance = inst
		_enemy_layer.move_child(node, -1)
		repaint.call()
		enemy_hovered.emit(inst, true))
	node.mouse_exited.connect(func():
		if not can_reorder.call():
			return
		if _hovered_instance == inst:
			_hovered_instance = 0
		_enemy_layer.move_child(node, mini(resting_index, _enemy_layer.get_child_count() - 1))
		repaint.call()
		enemy_hovered.emit(inst, false))
	node.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			click_enemy(inst, entry, front))

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
		if e.image.get_width() < _cell or e.image.get_height() < _cell:
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

# Badges for one enemy, laid out around the box it holds: health bottom-left,
# damage bottom-right, statuses under them, and the stun marker when frozen.
# `holder` is the enemy's slot on the badge layer, so these always draw in front
# of every body on the board. All non-blocking, so the enemy underneath still
# takes the click and shows its tooltip.
#
# NOTHING is drawn over the TOP of the box any more. A boss skull and an "in 2"
# (how many games of walking a body that can't reach you yet still owes) used to
# sit across the head of the art, and between them they covered the part of the
# picture that identifies the enemy — on a 7x7 board's 46px cells, most of it.
# Neither fact is lost: a boss is already drawn in the boss's own orange
# (threat_color) and carries its portrait beside its name on the checklist, and
# the walking still owed is the timing line of the body's own hover (enemy_hover).
func _add_enemy_badges(holder: Control, entry: Dictionary, e: GoalEnemyData,
		_accent: Color, selected: bool) -> void:
	var stun: int = int(entry.get("stun", 0))
	# What ONE LOST RUN would buy it (§3.2) — the live threat, since reporting a
	# game hands the board nothing out in the wilds.
	var strikes: int = GameLoop2.attacks_in_turns(entry)

	# ❤ health and ⚔ damage sit on the box's bottom EDGE rather than inside it, and
	# small: printed over the art at full size they covered the enemy you were
	# trying to recognise. Straddling the border puts them clear of the picture
	# while still obviously belonging to this body.
	# A FRACTION ONLY WHEN THERE IS ONE (docs/potions-design.md §4.6). Almost every
	# body on this board is at full Health and "❤1/1" is a badge saying the same
	# thing twice; a chipped one — or one a thrown Fruit Juice has GROWN — is
	# exactly the case the second number is for, and it was unreadable while the
	# ceiling was never written down.
	var hp: int = int(entry.get("health", e.health))
	var ceiling: int = GameLoop2.entry_max_health(entry)
	var hp_lbl := _corner_badge("❤%d" % hp if hp >= ceiling else "❤%d/%d" % [hp, ceiling],
		Color(1.0, 0.5, 0.5), STAT_BADGE_FONT)

	# Damage per swing, and — on the rare body that gets more than one swing out of
	# a single turn — how many that is: "⚔3 ×2". The two numbers are one fact ("it
	# hits you twice for 3"), so they read as one badge instead of the count
	# sitting over the art.
	var dmg_lbl := _corner_badge(_damage_badge_text(entry, strikes), Color(1.0, 0.8, 0.35),
		STAT_BADGE_FONT)
	if strikes > 1:
		dmg_lbl.add_theme_color_override("font_color", UITheme.DANGER.lerp(Color.WHITE, 0.45))

	# The two go in ONE ROW, not one in each bottom corner, and that is a bug fix.
	# Anchored separately, each badge grew from its own corner inwards — so the
	# moment an enemy got a second swing, "⚔3 ×2" grew left across the box and
	# printed itself straight over the ❤ in the other corner. The health, which is
	# the number you are reading to decide whether it dies this game, was the one
	# that lost. It happened exactly when it mattered most: multi-swing means the
	# Amulet is close and the board is at its widest, so the cells are at their
	# SMALLEST (46px at 7x7) and the damage badge is at its LONGEST.
	#
	# A row can't overlap itself. Health takes the left, an expanding spacer eats
	# whatever is left over, damage takes the right — identical to the old corners
	# whenever both fit, and when they don't they sit side by side and overhang
	# the box together instead of one erasing the other.
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 2)
	stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_row.add_child(hp_lbl)
	# A Dexterity shield goes next to the Health it is standing in front of, and
	# only when there is one to spend (§13.4). It is the number that decides
	# whether meeting this body's goal kills it, so it belongs beside the ❤ rather
	# than under the status pips — the pip says the body HAS Dexterity, this says
	# how much of it is left.
	var shield: int = GameLoop2.enemy_shield(entry)
	if shield > 0:
		stat_row.add_child(_corner_badge("◆%d" % shield, SHIELD_BLUE, STAT_BADGE_FONT))
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_row.add_child(gap)
	stat_row.add_child(dmg_lbl)
	# BOTTOM_WIDE: the row spans the body's full width, so "left corner" and
	# "right corner" are still where the two numbers land on anything roomy.
	stat_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE,
		Control.PRESET_MODE_MINSIZE, -STAT_BADGE_DROP)
	holder.add_child(stat_row)

	# Statuses BELOW the box, under the health/damage row (§13) — the one piece of
	# an enemy's state that is not a number and does not belong over its picture.
	# Drawn on the badge layer, which is above every body, so the overhang into the
	# gutter stays legible.
	var statuses: Array = GameLoop2.enemy_statuses(entry)
	if not statuses.is_empty():
		var strip := HBoxContainer.new()
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		strip.add_theme_constant_override("separation", 2)
		_fill_status_strip(strip, statuses, StatusData.ENEMY, STATUS_PIP_ENEMY,
			_nullified_ids(entry))
		strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM,
			Control.PRESET_MODE_MINSIZE, -STATUS_STRIP_DROP)
		holder.add_child(strip)

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

# The ⚔ badge: damage per swing, with the count appended when one turn of the
# board gives this body more than one. One swing needs no "x1" — that's the
# normal case and printing it everywhere is noise.
func _damage_badge_text(entry: Dictionary, strikes: int) -> String:
	# GameLoop2.enemy_damage, not the enemy's authored damage: a Strength stack is
	# a real +1 on every swing (§13.4), and a badge quoting the base stat would be
	# telling the player the board is safer than it is.
	var dmg: int = GameLoop2.enemy_damage(entry)
	# "×" and no space: on a 46px cell every character of this badge is width the
	# health beside it doesn't get.
	if strikes > 1:
		return "⚔%d×%d" % [dmg, strikes]
	return "⚔%d" % dmg

# What this enemy does on the next game you report, in a sentence: how many
# swings it gets and for how much, or how many games of walking it still owes.
# The badge is the glance; this is the answer when the glance isn't enough.
# The hover model for one body on the board: the condensed version of the card
# its click opens (EnemyInfoCard).
#
# What survives the condensing is what changes a decision in the next few
# seconds: WHO it is (the art and the name, in its threat colour), WHAT IS ON IT
# (its statuses, as pips — three of them are three lines of prose and one glance
# of icons), and WHEN IT SWINGS. Its goal rides along because that is the thing
# you are being asked to go and do. Everything else — the full stat block, the
# position, the verbs — is a click away and stays there.
func enemy_hover(entry: Dictionary, e: GoalEnemyData) -> Dictionary:
	var strikes: int = GameLoop2.attacks_in_turns(entry)
	var away: int = GameLoop2.lost_runs_until_strike(entry)
	var timing: String = ""
	if strikes > 0:
		timing = "Strikes %d time%s per lost run — %d damage." % [
			strikes, "" if strikes == 1 else "s", strikes * GameLoop2.enemy_damage(entry)]
	elif away > 0:
		timing = "%d lost run%s of walking from its first strike." % [
			away, "" if away == 1 else "s"]
	else:
		timing = "Waiting off the field — it can't reach you yet."

	var pips: Array = []
	for row in GameLoop2.enemy_statuses(entry):
		var status: StatusData = row["status"]
		if status == null:
			continue
		pips.append({
			"art": status.image,
			"text": "%s %d" % [status.display_name, int(row["stacks"])],
			"good": status.is_bonus(StatusData.ENEMY) or status.is_goal(StatusData.ENEMY),
		})
	var stun: int = int(entry.get("stun", 0))
	if stun > 0:
		pips.append({"text": "❄ %d" % stun, "good": true})

	var sub: String = "☠ boss" if e.is_boss() else ""

	return {
		"title": e.display_name,
		"subtitle": sub,
		"accent": threat_color(int(entry.get("col", GameLoop2.spawn_col())), e.is_boss()),
		"art": e.image,
		"pips": pips,
		"lines": [e.goal, timing],
		"note": "Click for the full card.",
	}

# A single full-rect Control child of a cell PanelContainer, inside which art and
# corner-anchored overlays lay out freely (the PanelContainer stretches this one
# holder to fill; the holder itself imposes no layout on its children).
func _cell_holder(cell: PanelContainer) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	return holder

# A small pill label used for the health / damage / status badges on a cell.
# Just the hero block: the portrait, the health line, the status pips and the
# shield pips. Split out of refresh() and public, because this is now the ONLY
# place the player's own state is drawn — the overworld used to print it a second
# time in a HUD strip, and that strip repainted on every stat / vitals / pickup
# signal while the board waited for a full refresh. The signals come here now, and
# a pickup that moves Max Health shows on the hero the instant it lands.
func refresh_hero() -> void:
	if _hero_hp == null:
		return
	var hero_tex: Texture2D = _hero_texture()
	_hero_icon.texture = hero_tex
	UITheme.apply_crisp(_hero_icon, hero_tex)
	_paint_hp()
	_fill_status_strip(_hero_statuses, GameState.status_list(), StatusData.PLAYER,
		STATUS_PIP_HERO)
	# One pip per shield: each is one INSTANCE of damage it stops dead, whatever
	# that instance was for (§3). Nothing is drawn hollow any more — a lost run
	# doesn't spend them, so there is no "already used" state to show; a shield is
	# there until something hits it.
	#
	# THE POOL THAT STAYS SITS CLOSEST TO THE PLAYER (§4.3), at the head of the row
	# and in its own glyph ◈: the ◆ ones are TEMPORARY SHIELDS and expire with this
	# game, and drawing the two alike would promise armour next game that isn't
	# coming. Their position is the reading — the further from the portrait a pip
	# is, the sooner it goes.
	var left: int = GameState.shields
	var bonus: int = GameState.bonus_shields
	_hero_shields.text = "◈".repeat(bonus) + "◆".repeat(left)
	_hero_shields.tooltip_text = ("◆ %s — each stops one hit outright, however "
		+ "big, and they go when you report this game.") % GameState.temp_shields_text(left)
	if bonus > 0:
		_hero_shields.tooltip_text += ("\n◈ %s — used after those, and they stay: "
			+ "nothing takes one but a hit.") % GameState.shields_text(bonus)

# --- status pips (§13) ----------------------------------------------------
#
# A status is art plus a stack count, on the body it is riding: under the hero's
# portrait for the player's own, under an enemy's box for its own. Both are the
# same chip so "what is on me" and "what is on that" read identically, and both
# carry the full StatusData tooltip rather than a truncated version of it.

# Icon edge for the hero's strip and for an enemy's, in px. The enemy board scales
# with the tier (fitted_cell) but the pips do not: a status is read, not measured,
# and shrinking it with the board makes it unreadable exactly when the board is
# busiest.
const STATUS_PIP_HERO := 22
const STATUS_PIP_ENEMY := 16

# How far the ❤ / ⚔ badges hang BELOW an enemy's box, and how far under them the
# status strip sits. Both are negative insets on a bottom-anchored preset, so the
# badges straddle the border and the statuses clear it entirely — the art keeps
# the whole cell to itself.
const STAT_BADGE_DROP := 7
const STAT_BADGE_FONT := 10
const STATUS_STRIP_DROP := 20

# One status chip: the art (or the name's first letter when art is missing) with
# its stack count, tinted by what this SIDE does — a `bonus` is an opportunity and
# reads gold, anything that taxes reads red.
func _status_pip(status: StatusData, stacks: int, which: StringName, size: int,
		nullified: bool = false, games: int = 0) -> Control:
	var good: bool = status.is_bonus(which) or status.is_goal(which)
	var tint: Color = UITheme.GOLD if good else UITheme.DANGER
	var chip := HoverPanel.new()
	chip.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.75), 3, 1, 1, tint.lerp(UITheme.BORDER, 0.35)))
	HoverCard.attach(chip, status_hover(status, stacks, which, nullified, games))
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	if status.image != null:
		var art := UITheme.crisp_tex(status.image, size)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
	var count := Label.new()
	count.text = str(stacks)
	count.add_theme_font_size_override("font_size", maxi(9, size - 6))
	count.add_theme_color_override("font_color", tint)
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	count.add_theme_constant_override("outline_size", 3)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	return chip

# The statuses this body is CARRYING AND IGNORING, as a set of ids. Only a boss
# has any: its goal is the only way it comes off the board, so an `instead` on one
# buys nothing (§7.1) — and the pip is drawn either way, because the stacks are
# real and the player put them there.
func _nullified_ids(entry: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for row in GameLoop2.nullified_alternatives_for(entry):
		var sd: StatusData = row["status"]
		if sd != null:
			out[sd.id] = true
	return out

# The hover model for one status pip. A thin wrapper over StatusData's own
# `hover_card`, so the board, the enemy card and the hero strip cannot describe
# the same status differently.
func status_hover(status: StatusData, stacks: int, which: StringName,
		nullified: bool = false, games: int = 0) -> Dictionary:
	return status.hover_card(which, stacks, nullified, games)

# Fill `strip` with one pip per status in `rows` ([{status, stacks}]). Returns how
# many were drawn, so a caller can hide an empty strip rather than leave a gap.
# `dead` names the statuses this BODY nullifies — an `instead` on a boss (§7.1) —
# so the pip's hover says the way out is void here rather than promising one.
func _fill_status_strip(strip: HBoxContainer, rows: Array, which: StringName,
		size: int, dead: Dictionary = {}) -> int:
	# remove_child BEFORE queue_free: queue_free only marks a node, leaving it a
	# child until the frame ends, so two refreshes in one frame (a status applied
	# during a resolve) would draw every pip twice.
	for child in strip.get_children():
		strip.remove_child(child)
		child.queue_free()
	for row in rows:
		var sd: StatusData = row["status"]
		# `games` rides the row from GameLoop2.enemy_statuses / GameState.status_list
		# (docs/potions-design.md §5.3), so a borrowed status's pip says so without
		# this strip knowing the timed layer exists.
		strip.add_child(_status_pip(sd, int(row["stacks"]), which, size,
			sd != null and dead.has(sd.id), int(row.get("games", 0))))
	strip.visible = not rows.is_empty()
	return rows.size()

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
func _offgrid_token(entry: Dictionary) -> Control:
	var e: GoalEnemyData = entry.get("enemy")
	var accent: Color = UITheme.GOLD
	if e != null and e.is_boss():
		accent = Color(0.95, 0.55, 0.2)
	var cell := HoverPanel.new()
	cell.custom_minimum_size = Vector2(44, 44)
	var inst: int = int(entry.get("instance", 0))
	var paint := func() -> void:
		var lit: bool = _is_lit(inst)
		var border: Color = accent.lerp(Color.WHITE, 0.55) if lit else accent.lerp(UITheme.BG, 0.25)
		var fill: Color = UITheme.PANEL.lerp(UITheme.BG, 0.3)
		if lit:
			fill = fill.lerp(Color.WHITE, 0.09)
		cell.add_theme_stylebox_override("panel", UITheme.flat(fill, 5, 2, 1, border))
	if e != null and inst > 0:
		_repaint_fns[inst] = paint
	paint.call()
	if e != null:
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# A body in the overflow lane gets the same card as one on the board — it is
		# the same enemy and the same question, and "why can't this one reach me" is
		# answered by the timing line either way.
		HoverCard.attach(cell, enemy_hover(entry, e))
		cell.mouse_entered.connect(func():
			_hovered_instance = inst
			paint.call()
			enemy_hovered.emit(inst, true))
		cell.mouse_exited.connect(func():
			if _hovered_instance == inst:
				_hovered_instance = 0
			paint.call()
			enemy_hovered.emit(inst, false))
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				click_enemy(inst, entry, GameLoop2.offgrid_col()))
		cell.set_meta("instance", inst)
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
		# No "NOW PLAYING" tag. A body waiting in the overflow lane is a body
		# waiting in the overflow lane, whichever game walked it on.
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

# The Health the board is currently SHOWING: the playback's number while one is
# running, the run's own the rest of the time. The host quotes this in its HUD so
# the two copies of the number never disagree mid-animation.
func shown_hp() -> int:
	return _hp_shown if _hp_shown >= 0 else GameState.hp

# The hero's Health line, and the HUD that follows it.
func _paint_hp() -> void:
	if _hero_hp == null:
		return
	_hero_hp.text = "♥ %d/%d" % [shown_hp(), GameState.max_hp]
	shown_hp_changed.emit(shown_hp())

# One strike connected: take it off the number the hero is reading as, and flash
# the line so the drop is seen rather than just noticed later.
func _drop_shown_hp(amount: int) -> void:
	if _hp_shown < 0 or amount <= 0:
		return
	_hp_shown = maxi(0, _hp_shown - amount)
	_paint_hp()
	if _hero_hp == null:
		return
	var t := _hero_hp.create_tween()
	t.tween_property(_hero_hp, "modulate", Color(1.0, 0.45, 0.4), 0.08)
	t.tween_property(_hero_hp, "modulate", Color.WHITE, 0.3)

# The playback is over (or was cut short): the label goes back to the run's real
# Health, which by now includes anything that healed after the resolve.
func _end_hp_playback() -> void:
	if _hp_shown < 0:
		return
	_hp_shown = -1
	_paint_hp()

func clear_fx() -> void:
	# A playback cut short must not leave a body invisible behind a ghost that
	# will never land, so the reveal happens here too.
	_reveal_hidden()
	_end_hp_playback()
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
# The hero's Health comes down WITH it: `hp_before` is what the run had before
# the report, and each strike takes its own bite out of that number as it lands
# (see _drop_shown_hp). Pass -1 and it's reconstructed by adding the resolve's
# damage back onto the current Health — near enough for a caller that didn't
# snapshot, exact for one that did.
#
# Returns HOW LONG the playback runs, in seconds (0.0 when there was nothing to
# show). The end-of-run screen waits that long before landing — a killing blow
# the verdict wipes off mid-flight may as well not exist.
func animate_resolve(before: Dictionary, res: Dictionary, hp_before: int = -1) -> float:
	if _fx_layer == null or not is_inside_tree():
		return 0.0
	clear_fx()
	_fx_gen += 1
	var after: Dictionary = capture_positions()
	_hp_shown = hp_before if hp_before >= 0 else GameState.hp + _health_damage_in(res)
	_paint_hp()

	# One playback per TURN (§7.4). Each turn is the same beat the board has
	# always played — the front line strikes, then the field closes up — and the
	# whole point of the mechanic is that near the Amulet you watch that beat land
	# twice over for having handed a game in at all. Collapsing it into a single
	# slide would hide exactly the thing the player needs to feel.
	var frames: Array = _turn_rect_frames(before, after, res)
	var turns: int = maxi(1, frames.size() - 1)
	# How many of those were the game's OWN, as against the Amulet's EXTRA ones
	# (§7.4). A reported game has none of its own now — every turn at the end of
	# one is the road charging you — but a LOST RUN'S playback is the other way
	# round: its single turn is the tick's, not the Amulet's. Read off the result
	# rather than the frame count, which a run that ended mid-playback cuts short.
	var base_turns: int = maxi(0, int(res.get("turns", turns)) - int(res.get("extra_turns", 0)))
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
				_spawn_turn_counter(turn + 1, turns, base_turns,
					int(res.get("extra_turns", 0)), elapsed)
			elapsed = slide_at + (FX_SLIDE_TIME if slid else 0.0)
	# Whatever the ghosts were standing in for comes back at the end of the whole
	# playback, not at the end of each turn: a body that moved on turn 1 and then
	# stood still has no turn-3 ghost to hand it back. The Health line stops being
	# the playback's and goes back to the run's at the same moment.
	var gen: int = _fx_gen
	if elapsed > 0.0:
		_after(elapsed, func():
			_reveal_hidden()
			if gen == _fx_gen:
				_end_hp_playback())
	else:
		_reveal_hidden()
		_end_hp_playback()
	return elapsed

# How much HEALTH a resolve cost, as opposed to how much damage was thrown at it:
# shields eat the difference, and a hit a shield swallowed moves no Health.
func _health_damage_in(res: Dictionary) -> int:
	var total: int = 0
	for a in res.get("attacks", []):
		if a is Dictionary and a.has("damage"):
			total += maxi(0, int(a["damage"]) - int(a.get("blocked", 0)))
	return total

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
		# What this one blow actually cost in Health — the rest of it was eaten by a
		# shield, and the hero's number shouldn't move for the part that was.
		var to_health: int = maxi(0, int(a["damage"]) - int(a.get("blocked", 0)))
		var gen: int = _fx_gen
		_after(delay, func():
			_spawn_strike_flash(from)
			_spawn_damage_number(int(a["damage"]), from, hero_rect)
			if gen == _fx_gen:
				_drop_shown_hp(to_health))
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

# "TURN 1 / 2" over the board as each turn opens — the count is the mechanic, so
# it is spelled out rather than left to be inferred from how many times the hero
# flinched. The ones the AMULET bought say so ("EXTRA TURN 1 / 2"): they are the
# last `extra` of the run, and a player watching the board move after handing a
# game in is owed the reason why.
func _spawn_turn_counter(turn: int, turns: int, base: int, extra_turns: int,
		delay: float) -> void:
	if _field == null:
		return
	var band: Color = RunDifficulty.band_color(extra_turns)
	var rect: Rect2 = _local_rect(_field)
	var extra: int = turn - base                 # 1-based index into the extra turns
	_after(delay, func():
		var lbl := Label.new()
		lbl.text = ("EXTRA TURN %d / %d" % [extra, extra_turns] if extra > 0
			else "TURN %d / %d" % [turn, turns])
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

# A logged attempt, played on the hero (§3): a lost run pops one shield pip off
# and floats what it cost. `cost` is "shield" or "bonus" while either pool lasts —
# both are a pip, since both are shields.
#
# "turn" plays NOTHING here. Once the pools are gone a lost run hands the board a
# turn instead, and that turn is shown the way every other turn in the game is:
# the host replays it with animate_resolve, which throws the real damage numbers
# from the bodies that threw them and recoils the hero for what actually landed.
# A "-1 ♥" floated from here on top of that would be a second, invented number.
func play_attempt_fx(cost: String) -> void:
	if _fx_layer == null or not is_inside_tree():
		return
	if cost == "shield" or cost == "bonus":
		_float_over_hero("-1 ◆", SHIELD_BLUE)
		_pop_shield_pips()

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

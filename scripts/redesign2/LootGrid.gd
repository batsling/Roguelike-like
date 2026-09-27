class_name LootGrid
extends Container

# The pack's loot, as a GRID YOU CAN REARRANGE (§4.3) — the fixed 3x3 and every
# bag attached to it (docs/loot-passives.md §6).
#
# The grid is always the CAPACITY, never the count: the empty slots are how the
# window says how much room is left, which is the fact the cap makes interesting,
# and three tiles in a 3x3 read as three of nine where three tiles in a row that
# wraps read as all there is.
#
# THREE SURFACES DRAW THIS SAME GRID, which is why it is a class rather than a
# method on one of them:
#
#   the LOOT WINDOW  — `allow_reorder`, `show_use`. Pieces can be dragged between
#                      slots, bags can be moved and turned, and each piece
#                      carries the button that spends it.
#   the DROP MODAL   — `allow_take`. The pack as it stands, with every slot a
#                      target for the piece the game just paid out — and the
#                      pack's edge a target for a bag it paid out.
#   the DRAG PACK    — `allow_floor_take`, for the length of a drag off the floor.
#
# WHAT AN ARRANGEMENT CAN BE: ANY OF THEM. A piece goes wherever it is dropped —
# onto another piece, which swaps the two, or onto any empty slot, which leaves a
# hole behind it. `GameState.loot_items` stays dense because indices are what
# `use_loot` is addressed by; the SLOT rides on the entry instead, and
# `GameState.loot_layout()` is the one place the two are put back together. The
# grid redraws from that afterwards — so where a piece lands is where the run says
# it is, never a position the view is remembering on its own.
#
# WHERE A SLOT IS DRAWN IS ASKED OF THE RUN TOO (GameState.pack_cell_of). The
# grid used to be a GridContainer three wide; a pack with bags on it is a shape,
# not a rectangle, so this is a Container that places each slot on its own cell
# and shrinks every cell alike when the shape outgrows the room it is given
# (`fit_scale`). THE CHILDREN ARE STILL THE SLOTS, IN SLOT ORDER — child `i` is
# slot `i`, which every caller and test relies on. The bag handles and the drop
# ghost are INTERNAL children, so they are not among them.
#
# TWO NUMBERS, AND THEY ARE NOT THE SAME NUMBER. Every signal below that names a
# piece hands over its INDEX in `GameState.loot_items` (what `use_loot`,
# `remove_loot_at` and the info card all take); `moved` alone deals in SLOTS,
# because moving is the one thing that is about where a piece is drawn.

# A piece was dropped into a slot from outside the pack (the drop modal's payload).
# `slot` is which one it was dropped on, and `offer` says WHICH of the offers on
# the table it was — a payout of four identical unidentified capsules cannot be
# told apart by its entry.
signal take_requested(entry: Dictionary, slot: int, offer: int)
# A carried piece moved between slots (swapping with whatever was there).
signal moved(from: int, to: int)
# The Use button on a carried piece.
signal use_requested(index: int)
# A carried piece was dragged onto the bin (LootTrash).
signal discard_requested(index: int)
# One of the pieces a drop modal is offering was dragged onto the bin — which is
# the same answer as "Leave it", said with the hands.
signal offer_discarded(offer: int)
# A piece was dragged in OFF THE BATTLEFIELD FLOOR (§8.2). `cell` is the square it
# was lying on, which the page needs to clear — and to put the displaced piece
# back on, when the slot it landed in already had one. Separate from
# `take_requested` for exactly that: a floor take is the only one with somewhere
# to put what it evicts, so it is the only one that can land on a full pack.
signal floor_take_requested(entry: Dictionary, slot: int, cell: Vector2i)
# …and the same piece dragged onto the bin instead. Its square is emptied and the
# piece is gone — unlike leaving it lying there, which keeps it for the haul.
signal floor_discarded(cell: Vector2i)
# A BAG off a modal's table was dropped on the pack's edge: attach it at `origin`,
# turned `rot` (docs/loot-passives.md §6). Already checked against
# GameState.can_place_bag; the host places it and crosses the offer off.
signal bag_take_requested(entry: Dictionary, origin: Vector2i, rot: int, offer: int)
# …and a bag dragged in off the FLOOR, with the square it was lying on.
signal floor_bag_take_requested(entry: Dictionary, origin: Vector2i, rot: int, cell: Vector2i)
# An attached bag was dragged onto the bin. Only ever emitted for a bag that can
# come off (empty, holding up nothing); the host asks first and removes it.
signal bag_discard_requested(bag: int)
# An attached bag was moved or turned. The grid has already done it (moving a bag
# changes nothing but the drawing, so there is nothing for a host to decide) and
# rebuilt itself; this is for a host that draws something else off the pack.
signal bag_moved(bag: int)

const ACCENT := Color(0.72, 0.62, 0.86)
# The leather every bag is drawn on — the 3x3 wears the pack's own accent, so the
# part that is fixed and the parts that move read as two different things.
const BAG_TINT := Color(0.66, 0.48, 0.30)
# The width of the 3x3, which is still the width the pack starts at. Kept for the
# surfaces that size a column to "a pack's worth" of cells (DragPackPanel,
# LootUseModal) — with no bags on, that is still exactly right.
const COLS := 3
# The z the piece in your hand is drawn at — see `preview_cell`. Well clear of
# anything the page sets on itself, and under the 4096 ceiling Godot allows.
const DRAG_Z := 500
# The gutter between two cells. The GridContainer this used to be was set to the
# same step, so a pack with no bags on it draws to the pixel as it did.
const GAP := UITheme.GAP_SNUG
# How far the cells may shrink to fit a big pack. Below this the names under the
# art stop being readable, and the window grows instead.
const MIN_SCALE := 0.5
# The handle a bag is dragged by, at full scale.
const HANDLE := 20

# Pieces already in the pack can be dragged between slots, and bags moved.
var allow_reorder: bool = false
# Slots accept a piece from OUTSIDE the pack (a drop modal's offer).
var allow_take: bool = false
# Slots accept a piece dragged in OFF THE BOARD (§8.2, `FloorLoot`). Its own flag
# rather than `allow_take`'s, because the two takes obey different rules about a
# full pack — see `can_accept`.
var allow_floor_take: bool = false
# Each filled cell carries the button that spends it.
var show_use: bool = false
# The bin will take a piece from this grid (LootTrash).
var allow_discard: bool = false
# MOVING is off while a game is mid-report — the report step is between "played
# the game" and "said what happened", and the pack cannot be rearranged, taken from
# or binned in that gap.
#
# SPENDING is not, and that is the narrower rule this used to get wrong (§4.3). A
# piece of loot is spent for what it does to the run, and mid-game is exactly when
# the player knows what they want: a Scare Monster on the body walking toward them,
# a Fire on the front column, a capsule they are willing to gamble on. Being told
# to finish their paperwork first is the run refusing the thing it wants them to
# risk. A piece whose effect cannot land in that gap FIZZLES instead of being
# refused — Teleportation and Telepills do not move a run halfway through a game
# (Overworld2.loot_teleport). A FIZZLE TEACHES NOTHING, though: a piece is
# identified by using it only when the use actually landed, so a piece spent into
# a gap where its effect had nowhere to go is still an unknown piece.
var locked: bool = false
# The box the pack is shrunk to fit, at full scale. Wide and tall enough that the
# 3x3 alone is never shrunk — every surface was fitted to it at full size — and a
# bag or two beside it costs a little size rather than a relayout of the page.
var max_fit: Vector2 = Vector2.ZERO

# The scale every cell is drawn at right now, and the cell drawn in the top-left.
var _scale: float = 1.0
var _top_left: Vector2i = Vector2i.ZERO
# A ring of empty cells around the pack, one deep, drawn while a BAG is in the
# air over a grid that would take it: the pack's edge is where a bag goes, so the
# grid has to reach past it for there to be anything to drop on.
var _ring: bool = false
# Where the bag in the air would land: {cells: Array, ok: bool, origin, rot}, or {}.
var _ghost: Dictionary = {}
var _overlay: Control = null
var _handles: Array = []

func _init() -> void:
	# The gutters are part of the drop target: a bag goes on the pack's EDGE, which
	# is exactly where there is no slot to catch it.
	mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_ghost)
	add_child(_overlay, false, Node.INTERNAL_MODE_BACK)

# The width of the 3x3, still asked by name by older callers.
func grid_columns() -> int:
	return GameState.pack_bounds().size.x

# Draw the pack. Called on every change rather than patched in place: the pack is
# a few dozen cells at most and rebuilding it is cheaper than keeping a view in
# sync with an array that four systems can write to.
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for h in _handles:
		if is_instance_valid(h):
			remove_child(h)
			h.queue_free()
	_handles.clear()
	# THE EMPTY SLOTS ARE PART OF THE DRAWING: "the grid is always the cap" is what
	# makes the room left readable, so this is the capacity and never the count.
	var layout: Array = GameState.loot_layout()
	for slot in range(GameState.loot_capacity()):
		var index: int = int(layout[slot])
		var entry = GameState.loot_items[index] if index >= 0 else null
		add_child(_slot(slot, index, entry if entry is Dictionary else {}))
	# A HANDLE ON EVERY BAG, where the pack can be rearranged. An empty cell of a
	# bag drags the bag too, but a full bag has none, and a bag you cannot pick up
	# is not one you can move.
	if allow_reorder:
		for i in range(GameState.pack_bags.size()):
			var h := BagHandle.new()
			h.grid = self
			h.bag = i
			_handles.append(h)
			add_child(h, false, Node.INTERNAL_MODE_BACK)
	_ring = _wants_ring(_drag_data())
	_relayout()

# ---------------------------------------------------------------------------
# Layout: cells on their own coordinates, shrunk alike to fit
# ---------------------------------------------------------------------------

# One cell's size at full scale — every cell stands the same, full or empty (see
# LootSlot.cell_height), so the first slot answers for all of them.
func cell_size() -> Vector2:
	for c in get_children():
		if c is Control:
			var m: Vector2 = (c as Control).get_combined_minimum_size()
			return Vector2(maxf(m.x, LootSlot.CELL_W), m.y)
	return Vector2(LootSlot.CELL_W, LootSlot.cell_height(show_use))

func _pitch() -> Vector2:
	return cell_size() + Vector2(GAP, GAP)

# The cells drawn: the pack's bounds, and the ring around them while a bag is in
# the air.
func _span() -> Rect2i:
	var r: Rect2i = GameState.pack_bounds()
	return r.grow(1) if _ring else r

func _natural(cells: Vector2i) -> Vector2:
	return Vector2(cells) * _pitch() - Vector2(GAP, GAP)

func _fit_box() -> Vector2:
	if max_fit != Vector2.ZERO:
		return max_fit
	# Four columns and three and a half rows of full-size cells: room for the 3x3
	# plus a bag's worth either way before anything shrinks.
	return Vector2(4.0, 3.5) * _pitch() - Vector2(GAP, GAP)

# THE SCALE A PACK THIS BIG IS DRAWN AT — 1 for anything that fits the box, less
# for a pack that has grown past it, never less than MIN_SCALE. Every cell shrinks
# alike, so the pack is one picture at one size rather than a 3x3 with small bags
# hanging off it.
func fit_scale() -> float:
	var need: Vector2 = _natural(_span().size)
	var box: Vector2 = _fit_box()
	return clampf(minf(box.x / need.x, box.y / need.y), MIN_SCALE, 1.0)

func _get_minimum_size() -> Vector2:
	return _natural(_span().size) * fit_scale()

func _relayout() -> void:
	update_minimum_size()
	queue_sort()
	queue_redraw()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_place()
		NOTIFICATION_READY:
			# A grid built mid-drag (the drag-time pack is built BY the drag) never
			# hears DRAG_BEGIN, so it looks for itself.
			_set_ring(_wants_ring(_drag_data()))
			set_process(_ring)
		NOTIFICATION_DRAG_BEGIN:
			_set_ring(_wants_ring(_drag_data()))
			set_process(_ring)
		NOTIFICATION_DRAG_END:
			_ghost = {}
			_set_ring(false)
			set_process(false)
			_overlay.queue_redraw()

func _set_ring(on: bool) -> void:
	if on == _ring:
		return
	_ring = on
	_relayout()

# Where cell `cell` is drawn, grid-local.
func cell_position(cell: Vector2i) -> Vector2:
	return Vector2(cell - _top_left) * _pitch() * _scale

func _place() -> void:
	_scale = fit_scale()
	_top_left = _span().position
	var cs: Vector2 = cell_size()
	for c in get_children():
		if c is LootSlot and (c as LootSlot).slot_index >= 0:
			var slot: LootSlot = c
			slot.position = cell_position(GameState.pack_cell_of(slot.slot_index))
			slot.size = cs
			slot.scale = Vector2(_scale, _scale)
	for h in _handles:
		if not is_instance_valid(h) or h.bag >= GameState.pack_bags.size():
			continue
		var cells: Array = GameState.bag_cells(GameState.pack_bags[h.bag])
		var corner: Vector2i = cells[0]
		for cc in cells:
			if cc.y < corner.y or (cc.y == corner.y and cc.x < corner.x):
				corner = cc
		h.position = cell_position(corner) + Vector2(2, 2) * _scale
		h.size = Vector2(HANDLE, HANDLE)
		h.scale = Vector2(_scale, _scale)
	_overlay.position = Vector2.ZERO
	_overlay.size = size
	queue_redraw()
	_overlay.queue_redraw()

# ---------------------------------------------------------------------------
# Drawing the bags — behind the cells, so an empty cell shows the leather
# ---------------------------------------------------------------------------

func _cells_rect(cells: Array) -> Rect2:
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var pad: float = GAP * 0.5 * _scale
	var at: Vector2 = cell_position(lo) - Vector2(pad, pad)
	var end: Vector2 = cell_position(hi) + cell_size() * _scale + Vector2(pad, pad)
	return Rect2(at, end - at)

func _draw() -> void:
	var base: Array = []
	for y in range(GameState.PACK_BASE.y):
		for x in range(GameState.PACK_BASE.x):
			base.append(Vector2i(x, y))
	if not GameState.pack_bags.is_empty():
		draw_style_box(UITheme.flat(ACCENT.lerp(UITheme.BG, 0.88), 6, 0, 1,
			ACCENT.lerp(UITheme.BG, 0.6)), _cells_rect(base))
	for bag in GameState.pack_bags:
		var def: BagData = GameState.bag_def(bag)
		var rect: Rect2 = _cells_rect(GameState.bag_cells(bag))
		draw_style_box(UITheme.flat(BAG_TINT.lerp(UITheme.BG, 0.7), 6, 0, 2,
			BAG_TINT.lerp(UITheme.BG, 0.2)), rect)
		_draw_bag_art(self, LootPassives.load_bag_art(def), rect,
			int(bag.get("rot", 0)), Color(1, 1, 1, 0.45))

# The bag's picture, fitted inside `rect` and turned with the bag. Static so the
# piece in your hand draws it the same way.
static func _draw_bag_art(ci: CanvasItem, tex: Texture2D, rect: Rect2, rot: int,
		tint: Color) -> void:
	if tex == null:
		return
	var turned: bool = posmod(rot, 2) == 1
	var box: Vector2 = Vector2(rect.size.y, rect.size.x) if turned else rect.size
	var ts: Vector2 = tex.get_size()
	var k: float = minf(box.x / ts.x, box.y / ts.y)
	var drawn: Vector2 = ts * k
	ci.draw_set_transform(rect.get_center(), posmod(rot, 4) * PI * 0.5, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(-drawn * 0.5, drawn), false, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Where the bag in the air would land, over everything else.
func _draw_ghost() -> void:
	if _ghost.is_empty():
		return
	var ok: bool = bool(_ghost.get("ok", false))
	var tint: Color = UITheme.SUCCESS if ok else UITheme.DANGER
	var cs: Vector2 = cell_size() * _scale
	for c in _ghost.get("cells", []):
		_overlay.draw_style_box(UITheme.flat(Color(tint, 0.28), 6, 0, 2, tint),
			Rect2(cell_position(c), cs))

# ---------------------------------------------------------------------------
# What a slot is allowed to do — asked by LootSlot, answered here, so the rules
# live in one place rather than in every cell.
# ---------------------------------------------------------------------------

func can_drag_from(slot: LootSlot) -> bool:
	if locked:
		return false
	# The loose piece a modal is offering is always draggable when it is drawn at
	# all — it is the offer. Pieces in the pack move only where reordering is on.
	return true if slot.slot_index < 0 else allow_reorder

func can_accept(slot: LootSlot, data: Dictionary) -> bool:
	if locked:
		return false
	# A BAG IS DROPPED ON THE PACK, not in a slot: over a slot it is asking where
	# the bag would go if it were dropped here, which is the grid's question.
	if is_bag_payload(data):
		return can_accept_bag_at(slot.position + slot.get_local_mouse_position() * slot.scale, data)
	match String(data.get("kind", "")):
		"loot_move":
			# ANY SLOT BUT ITS OWN. Onto a piece swaps the two, onto an empty one moves
			# it there and leaves a hole — both are arrangements the pack can hold now
			# that a slot is a fact about the entry rather than its place in an array.
			return allow_reorder and int(data.get("from", -1)) != slot.slot_index
		"loot_take":
			# OFF THE FLOOR: ANY SLOT. A free one takes it; a filled one SWAPS, and the
			# piece that was there goes back to the square this one came off
			# (Overworld2.take_floor_loot). That is the answer to a full pack the
			# modal's take cannot give — the pack is full, the board is right there,
			# and a trade is a decision rather than a wall. It is also the grammar the
			# grid already speaks: dropping onto a piece has meant "swap these two"
			# since the pack was allowed to have holes in it.
			if data.has("floor"):
				return allow_floor_take
			# OFF A MODAL'S TABLE: INTO A FREE SLOT. "Put it here" onto an occupied one
			# has no answer that isn't a guess about which of the two the player meant
			# to move — there is nowhere to evict the loser TO.
			return allow_take and not slot.is_filled() and not GameState.loot_is_full()
	return false

# --- The bin ---------------------------------------------------------------
#
# Asked by LootTrash, answered here for the same reason the slots' rules are: the
# screens that draw a grid differ in the grid they build, not in a second copy
# of what a drop means.

func can_trash(data: Dictionary) -> bool:
	if locked or not allow_discard:
		return false
	match String(data.get("kind", "")):
		"loot_move":
			return int(data.get("index", -1)) >= 0
		"loot_take":
			# The offer — or the piece off the floor — thrown away rather than taken.
			# Always allowed: a full pack is exactly when you most want to say no to a
			# piece with your hands.
			return true
		"bag_move":
			# A BAG COMES OFF EMPTY, and only if nothing else is hanging off it —
			# binning one with loot in it would bin the loot, and one holding up
			# another bag would leave that one attached to nothing.
			return GameState.can_remove_bag(int(data.get("bag", -1)))
	return false

func trash(data: Dictionary) -> void:
	if not can_trash(data):
		return
	match String(data.get("kind", "")):
		"loot_move":
			# The bin destroys a PIECE, so it is handed the array index the payload
			# carries alongside the slot — `remove_loot_at` has never dealt in slots.
			discard_requested.emit(int(data.get("index", -1)))
		"loot_take":
			if data.has("floor"):
				floor_discarded.emit(data["floor"] as Vector2i)
			else:
				offer_discarded.emit(int(data.get("offer", -1)))
		"bag_move":
			bag_discard_requested.emit(int(data.get("bag", -1)))

func accept(slot: LootSlot, data: Dictionary) -> void:
	if is_bag_payload(data):
		accept_bag_at(slot.position + slot.get_local_mouse_position() * slot.scale, data)
		return
	match String(data.get("kind", "")):
		"loot_move":
			moved.emit(int(data.get("from", -1)), slot.slot_index)
		"loot_take":
			var entry = data.get("entry", {})
			if not (entry is Dictionary) or (entry as Dictionary).is_empty():
				return
			if data.has("floor"):
				floor_take_requested.emit(entry, maxi(0, slot.slot_index),
					data["floor"] as Vector2i)
			else:
				take_requested.emit(entry, maxi(0, slot.slot_index),
					int(data.get("offer", -1)))

# ---------------------------------------------------------------------------
# Bags in the air (docs/loot-passives.md §6)
# ---------------------------------------------------------------------------
#
# Two payloads carry a bag: `bag_move` — {bag, id, rot}, a bag already on the
# pack, picked up by its handle or an empty cell of it — and the ordinary
# `loot_take` whose entry is a bag, off a modal's table or the floor, which is
# kept as a `loot_take` so every surface that reacts to "a piece of loot is in the
# air" (the drag-time pack, the bin) reacts to a bag too. Both carry `rot`, and
# the piece in your hand turns it (BagPreview).

static func is_bag_payload(data) -> bool:
	if not (data is Dictionary):
		return false
	if String(data.get("kind", "")) == "bag_move":
		return true
	return String(data.get("kind", "")) == "loot_take" \
		and GameState.is_bag_entry(data.get("entry", {}))

func _drag_data():
	var vp: Viewport = get_viewport()
	return vp.gui_get_drag_data() if vp != null and vp.gui_is_dragging() else null

# Would this grid take this bag at all — the flag half of the question, before
# where. A grid that would not is not handed a ring either.
func _takes_bag(data) -> bool:
	if locked or not is_bag_payload(data):
		return false
	if String(data.get("kind", "")) == "bag_move":
		return allow_reorder
	return allow_floor_take if data.has("floor") else allow_take

func _wants_ring(data) -> bool:
	return _takes_bag(data)

func _bag_payload_size(data: Dictionary) -> Vector2i:
	var id: StringName
	if String(data.get("kind", "")) == "bag_move":
		id = StringName(data.get("id", ""))
	else:
		id = StringName((data.get("entry", {}) as Dictionary).get("id", ""))
	var def: BagData = Data.get_bag(id)
	return def.size if def != null else Vector2i.ONE

# WHERE A BAG DROPPED AT `at` (grid-local) WOULD GO.
#
# The bag covers the cell under the pointer; of the placements that do, the one
# taken is the VALID one whose middle is nearest the pointer. That is what lets
# one ring of cells around the pack be enough for any bag: point just past the
# edge and a Potion Belt runs outward from there, rather than being centred on
# the pointer and landing half on top of the 3x3. With nowhere valid, the centred
# placement is shown in red, so the player sees what is in the way.
func bag_target(at: Vector2, data: Dictionary) -> Dictionary:
	var size: Vector2i = _bag_payload_size(data)
	var rot: int = int(data.get("rot", 0))
	var ext: Vector2i = GameState.bag_extent(size, rot)
	var moving: int = int(data.get("bag", -1)) if String(data.get("kind", "")) == "bag_move" else -1
	var p: Vector2 = at / (_pitch() * _scale) + Vector2(_top_left)
	var under := Vector2i(floori(p.x), floori(p.y))
	var best: Dictionary = {}
	var best_d: float = INF
	for dy in range(ext.y):
		for dx in range(ext.x):
			var origin: Vector2i = under - Vector2i(dx, dy)
			if not GameState.can_place_bag(size, origin, rot, moving):
				continue
			var d: float = (Vector2(origin) + Vector2(ext) * 0.5).distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = {"origin": origin, "rot": rot, "ok": true}
	if best.is_empty():
		best = {"origin": Vector2i(roundi(p.x - ext.x * 0.5), roundi(p.y - ext.y * 0.5)),
			"rot": rot, "ok": false}
	best["cells"] = GameState.bag_cells_at(size, best["origin"], rot)
	return best

func can_accept_bag_at(at: Vector2, data: Dictionary) -> bool:
	if not _takes_bag(data):
		return false
	_ghost = bag_target(at, data)
	_overlay.queue_redraw()
	return bool(_ghost["ok"])

func accept_bag_at(at: Vector2, data: Dictionary) -> void:
	if not _takes_bag(data):
		return
	var t: Dictionary = bag_target(at, data)
	_ghost = {}
	_overlay.queue_redraw()
	if not bool(t["ok"]):
		return
	var origin: Vector2i = t["origin"]
	var rot: int = int(t["rot"])
	match String(data.get("kind", "")):
		"bag_move":
			# THE GRID DOES THIS ONE ITSELF. A move changes where cells are drawn and
			# nothing else — the pieces in the bag keep their slots — so there is no
			# decision in it for a host to make.
			var i: int = int(data.get("bag", -1))
			if GameState.move_bag(i, origin, rot):
				rebuild()
				bag_moved.emit(i)
		"loot_take":
			var entry: Dictionary = data.get("entry", {})
			if data.has("floor"):
				floor_bag_take_requested.emit(entry, origin, rot, data["floor"] as Vector2i)
			else:
				bag_take_requested.emit(entry, origin, rot, int(data.get("offer", -1)))

# Over the gutters and the ring — anywhere on the grid that is not a slot.
func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return data is Dictionary and can_accept_bag_at(at, data)

func _drop_data(at: Vector2, data: Variant) -> void:
	if data is Dictionary:
		accept_bag_at(at, data)

# THE GHOST FOLLOWS A TURN WITHOUT A MOVE. `_can_drop_data` is only asked when
# the pointer moves, and turning the bag in your hand (R) is not a move — so while
# a bag is in the air, the ghost is re-read every frame, and cleared when the
# pointer leaves.
func _process(_delta: float) -> void:
	var data = _drag_data()
	if not _takes_bag(data):
		return
	var at: Vector2 = get_local_mouse_position()
	var inside: bool = Rect2(Vector2.ZERO, size).has_point(at)
	if not inside:
		if not _ghost.is_empty():
			_ghost = {}
			_overlay.queue_redraw()
		return
	var t: Dictionary = bag_target(at, data)
	if t != _ghost:
		_ghost = t
		_overlay.queue_redraw()

# Can a bag be picked up off this grid right now?
func can_drag_bag() -> bool:
	return allow_reorder and not locked

func bag_payload(bag: int) -> Dictionary:
	var row: Dictionary = GameState.pack_bags[bag]
	return {"kind": "bag_move", "bag": bag, "id": StringName(row.get("id", "")),
		"rot": int(row.get("rot", 0))}

# The piece in your hand for a bag: its footprint at this grid's scale, turnable.
func bag_preview(data: Dictionary) -> Control:
	var p := BagPreview.new()
	p.data = data
	p.pitch = _pitch() * _scale
	p.cell = cell_size() * _scale
	return p

# The same for a bag that is not on any grid yet (the floor, a modal's table).
static func loose_bag_preview(data: Dictionary) -> Control:
	var p := BagPreview.new()
	p.data = data
	var k: float = 0.7
	p.cell = Vector2(LootSlot.CELL_W, LootSlot.cell_height(false)) * k
	p.pitch = p.cell + Vector2(GAP, GAP) * k
	return p


# THE BAG IN YOUR HAND. Its footprint, cell by cell, with its picture over it —
# and R or a right-click TURNS it, a quarter turn clockwise. The turn is written
# into the payload itself (Godot hands the same Dictionary to every drop target),
# so whatever it is let go over sees the bag the way it is now held.
class BagPreview extends Control:
	var data: Dictionary = {}
	var pitch: Vector2 = Vector2(94, 100)
	var cell: Vector2 = Vector2(88, 94)

	func _init() -> void:
		z_index = DRAG_Z
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _size() -> Vector2i:
		var def: BagData = Data.get_bag(_id())
		return def.size if def != null else Vector2i.ONE

	func _id() -> StringName:
		if String(data.get("kind", "")) == "bag_move":
			return StringName(data.get("id", ""))
		return StringName((data.get("entry", {}) as Dictionary).get("id", ""))

	func _input(event: InputEvent) -> void:
		var turn: bool = (event is InputEventKey and event.pressed and not event.echo
				and (event as InputEventKey).keycode == KEY_R) \
			or (event is InputEventMouseButton and event.pressed
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT)
		if not turn:
			return
		data["rot"] = posmod(int(data.get("rot", 0)) + 1, 4)
		queue_redraw()
		get_viewport().set_input_as_handled()

	func _draw() -> void:
		var size_cells: Vector2i = _size()
		var rot: int = int(data.get("rot", 0))
		var ext: Vector2i = GameState.bag_extent(size_cells, rot)
		var span: Vector2 = Vector2(ext) * pitch - (pitch - cell)
		var at: Vector2 = -span * 0.5
		for y in range(ext.y):
			for x in range(ext.x):
				draw_style_box(UITheme.flat(Color(BAG_TINT, 0.55), 6, 0, 2, BAG_TINT),
					Rect2(at + Vector2(x, y) * pitch, cell))
		LootGrid._draw_bag_art(self, LootPassives.load_bag_art(Data.get_bag(_id())),
			Rect2(at, span), rot, Color(1, 1, 1, 0.85))


# THE HANDLE A BAG IS PICKED UP BY — a small leather tab in its top-left cell.
# Where the pack can be rearranged it is a drag source; it is also a drop target
# that hands the question to the grid, so a drop that happens to land on a handle
# still lands.
class BagHandle extends Control:
	var grid: LootGrid = null
	var bag: int = -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		tooltip_text = "Drag to move this bag — what is in it comes too.\n" \
			+ "R or right-click while dragging turns it. Drop it on the bin to take it off (empty only)."

	func _draw() -> void:
		draw_style_box(UITheme.flat(BAG_TINT, 4, 0, 1, BAG_TINT.lerp(Color.WHITE, 0.4)),
			Rect2(Vector2.ZERO, size))
		# Six dots: the grip every drag handle wears.
		for y in range(3):
			for x in range(2):
				draw_circle(Vector2(size.x * (0.35 + 0.3 * x), size.y * (0.25 + 0.25 * y)),
					1.5, Color(1, 1, 1, 0.85))

	func _get_drag_data(_at: Vector2) -> Variant:
		if grid == null or not grid.can_drag_bag() or bag < 0 \
				or bag >= GameState.pack_bags.size():
			return null
		var data: Dictionary = grid.bag_payload(bag)
		if get_viewport() != null and get_viewport().gui_is_dragging():
			set_drag_preview(grid.bag_preview(data))
		return data

	func _can_drop_data(at: Vector2, data: Variant) -> bool:
		return grid != null and data is Dictionary \
			and grid.can_accept_bag_at(position + at * scale, data)

	func _drop_data(at: Vector2, data: Variant) -> void:
		if grid != null and data is Dictionary:
			grid.accept_bag_at(position + at * scale, data)

# WHAT FOLLOWS THE CURSOR: THE WHOLE CELL. It used to be the bare capsule, which
# made a drag look like the art had come loose from its tile — and against a grid
# of bordered cells there was nothing to line up the thing in your hand with the
# slot you were aiming it at. So the preview is the cell: same border, same art,
# same name, drawn at the loose-piece weight so it reads as picked up rather than
# as a second copy sitting in the grid.
#
# Built here rather than on LootSlot because the cell's box and body are this
# class's, and a LootSlot that named LootGrid back would be two class_names naming
# each other — a cycle Godot resolves badly. The slot asks its grid for it instead.
func drag_preview(slot: LootSlot) -> Control:
	return preview_cell(slot.entry)

# The same cell, for a drag that starts somewhere that is not a slot at all — a
# piece picked up off the BATTLEFIELD FLOOR (§8.2, `FloorLoot`). Static, and the
# reason it is worth sharing rather than letting the board draw its own: the
# argument above is exactly as true there. A bare capsule dragged off a board
# square onto a grid of bordered cells has nothing to line up with, and the thing
# in your hand is on its way to being a cell in the pack — so it may as well
# already look like one.
static func preview_cell(entry: Dictionary, face_up: bool = true) -> Control:
	var holder := Control.new()
	# ABOVE WHATEVER THE DRAG SUMMONED. Godot parents the drag preview to the
	# topmost Control over the one the drag started on and moves it to the front of
	# that node's children — and then DRAG_BEGIN reaches the page, which hangs the
	# transient pack (`DragPackPanel`) off the very same node, AFTER it. Child order
	# is draw order, so the piece in your hand went behind the panel it was being
	# carried into: you dragged a loot cell at the pack and it vanished under it.
	#
	# Fixed on the preview rather than on the panel, because the panel is not the
	# only thing that can arrive mid-drag and the rule is the same for all of them:
	# the thing following the cursor is the thing on top. z_index outranks child
	# order within the canvas layer, and the cell's own children are relative to the
	# holder, so one write covers the whole preview.
	holder.z_index = DRAG_Z
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", _filled_box(entry, true))
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size = Vector2(LootSlot.CELL_W, LootSlot.cell_height(false))
	# Centred on the pointer, so the cell you are holding covers the slot you are
	# pointing at rather than hanging off one corner of it.
	cell.position = -cell.size * 0.5
	cell.modulate = Color(1, 1, 1, 0.9)
	# FACE DOWN WHILE IT IS STILL A FLOOR PIECE (docs/cards-design.md §3). A card
	# picked up off the board and then dropped back on it has to end where it
	# started, and a preview that turned it face up would make drag-and-cancel a
	# free look at every card on the board — the one thing the mask exists to
	# prevent. It turns over when it lands in a slot, which is where "in the pack"
	# begins.
	cell.add_child(_cell_body(entry, Callable(), false, true, face_up))
	holder.add_child(cell)
	return holder

# ---------------------------------------------------------------------------
# Building one cell
# ---------------------------------------------------------------------------

func _slot(slot_index: int, index: int, entry: Dictionary) -> LootSlot:
	var slot := LootSlot.new()
	slot.grid = self
	slot.slot_index = slot_index
	slot.loot_index = index
	slot.entry = entry
	slot.custom_minimum_size = Vector2(LootSlot.CELL_W, 0)
	if entry.is_empty():
		slot.add_theme_stylebox_override("panel", _empty_box())
		# The count, said as a picture — and said in the right number of words. It
		# used to promise "room for one more" on all six free slots at once.
		var free: int = GameState.loot_space()
		slot.tooltip_text = "Empty — room for %d more piece%s." % [free, "" if free == 1 else "s"]
		if allow_reorder and GameState.loot_items.size() > 0:
			slot.tooltip_text += "  Drag a piece here to put it in this slot."
		if allow_take and not GameState.loot_is_full():
			slot.tooltip_text = "Drop the piece here to take it."
		# AN EMPTY CELL OF A BAG IS A HANDLE ON THE BAG, where bags can move.
		if allow_reorder and GameState.bag_at_slot(slot_index) >= 0:
			slot.tooltip_text += "  Drag this empty cell to move its bag."
			slot.mouse_default_cursor_shape = Control.CURSOR_DRAG
		slot.add_child(_empty_body(show_use))
		return slot

	slot.add_theme_stylebox_override("panel", _filled_box(entry, false))
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	HoverCard.attach(slot, LootSystem.hover_card(entry))
	var use_cb: Callable = Callable()
	if show_use:
		use_cb = func(): use_requested.emit(slot.loot_index)
	# `false`: the lock holds the pack STILL, it does not stop a piece being spent
	# (see `locked`). Kept as an argument rather than dropped, because the cell body
	# is shared with the loose-offer layout and a future rule may want it back.
	slot.add_child(_cell_body(entry, use_cb, false))
	# HOVER READS, DRAG MOVES, THE BUTTON SPENDS — and a click does nothing.
	#
	# A cell used to open a reading card on click (LootInfoCard), which meant two
	# screens said the same things about one piece: that card, and the Use screen
	# the button opens, which already leads with the art, the kind, the Preference
	# and what the piece does before it asks whether to spend it. The one that only
	# read was the one nothing was decided on, so it is gone; the hover card is the
	# fast read on the way past, and Use is where the piece is actually looked at.
	return slot

# The art band, the name, the preference chip and (when the grid spends) the Use
# button. Static so the loose piece a modal offers is built by the same code as a
# slot in the pack — the thing being dragged and the thing it becomes have to look
# like each other or the drag reads as a swap.
# `with_name` is false for the loose piece a drop modal offers: the modal writes
# the name underneath at 18px, and the same words twice, 20 pixels apart, at two
# sizes, reads as a mistake rather than as emphasis.
static func _cell_body(entry: Dictionary, use_cb: Callable, locked_now: bool,
		with_name: bool = true, face_up: bool = true) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", LootSlot.GAP)

	# A FIXED BAND, with the art centred in it at ITS OWN SIZE. This is what lets a
	# horse dose draw oversized without making its row taller than the other two.
	var band := Control.new()
	band.custom_minimum_size = Vector2(0, LootSlot.ART_BAND)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(centre)
	var art: TextureRect = LootSystem.art_tex(entry, LootSlot.ART, face_up)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(art)

	var known: bool = LootSystem.is_identified(entry)
	# THE PREFERENCE, IN ITS OWN COLOUR, ON THE ART — the corner the pack strip draws
	# a relic's counter in, for the same reason: the fact belongs to the picture of
	# the thing, so a grid can be read in one glance without any cell growing a
	# caption row. It is the fact that decides whether a piece is worth spending, and
	# it used to be grey body text on every surface that showed it. An unknown piece
	# gets "?" instead — the absence of a preference IS the gamble, so the badge says
	# which of the two this is rather than going missing.
	#
	# A CARD GETS NO BADGE AT ALL (docs/cards-design.md §2). It has no Preference —
	# there is no gamble for one to hint at — and the fallback "?" would say the one
	# thing that is not true of it: that this is a piece you do not know yet.
	#
	# A TRINKET GETS NONE EITHER, for the card's reason: it is not a gamble.
	var passive: bool = LootPassives.is_passive(entry)
	# A BAG IS NOT A GAMBLE EITHER, and is not spent: no badge, no button.
	var bag: bool = LootSystem.is_bag(entry)
	if String(entry.get("type", "")) != "card" and not passive and not bag:
		var badge := UITheme.chip(pref_glyph(entry) if known else "?",
			UITheme.preference_color(LootSystem.preference(entry)) if known else UITheme.TEXT_FAINT,
			9)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		band.add_child(badge)
	# A WAND WEARS ITS COUNT IN THE OTHER CORNER (docs/wands-design.md §6.2).
	# Bottom-LEFT, because bottom-right is the Preference's and the two answer
	# different questions: what this would do to you, and how much of it there is
	# left. An UNKNOWN stick wears a `?` in the same plate rather than nothing at
	# all: the corner is how a tile reads as a wand at 40px, and a blank one would
	# say this stick has no charges rather than that you have not counted them.
	if LootSystem.is_wand(entry):
		var counted: bool = LootSystem.charges_known(entry)
		var bar: Array = LootSystem.charges(entry)
		var count := UITheme.chip("%d" % int(bar[0]) if counted else "?",
			WandSystem.WAND_COLOR if counted else UITheme.TEXT_FAINT, 9)
		count.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		count.grow_horizontal = Control.GROW_DIRECTION_END
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.tooltip_text = "%d of %d charges left." % [int(bar[0]), int(bar[1])] \
			if counted else "Zap it to find out what it is — and how much of it is left."
		band.add_child(count)
	# A PASSIVE THAT GROWS WEARS ITS GROWTH in the same corner (Rocket's payout,
	# docs/loot-passives.md §4) — the relic strip draws an incremental relic's
	# count there too, so a number in the bottom-left reads as "how far along".
	var grown: int = int(entry.get("counter", 0))
	if passive and grown != 0:
		var tally := UITheme.chip("%+d" % grown, UITheme.GOLD, 9)
		tally.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		tally.grow_horizontal = Control.GROW_DIRECTION_END
		tally.grow_vertical = Control.GROW_DIRECTION_BEGIN
		tally.tooltip_text = "Grown by %+d so far." % grown
		band.add_child(tally)
	col.add_child(band)

	if not with_name:
		return col

	var name := Label.new()
	name.text = LootSystem.display_name(entry, face_up)
	name.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	name.add_theme_color_override("font_color", UITheme.TEXT if known else UITheme.TEXT_FAINT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Two lines' worth, reserved whether the name needs them or not — see
	# LootSlot.NAME_H. This is the fix for the ragged rows, and `max_lines_visible`
	# is the other half of it: a name that ran to three lines would push its own Use
	# button down and put the raggedness back from the other direction.
	name.custom_minimum_size = Vector2(0, LootSlot.NAME_H)
	name.max_lines_visible = 2
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name)

	# A PASSIVE PIECE HAS NOTHING TO SPEND (docs/loot-passives.md §1), so where the
	# Use button would be it says what it is instead — at the button's own height,
	# so a row holding a trinket is exactly as tall as a row holding a scroll.
	if bag:
		pass
	elif use_cb.is_valid() and passive:
		var plate := Label.new()
		var copier: bool = LootPassives.copies(LootPassives.def_for(entry)) != ""
		plate.text = "Copies >" if copier else "Passive"
		plate.custom_minimum_size = Vector2(0, LootSlot.USE_H)
		plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plate.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		plate.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		plate.tooltip_text = "Works while it is in your pack. Copies the piece to its right." \
			if copier else "Works while it is in your pack — never spent."
		col.add_child(plate)
	elif use_cb.is_valid():
		# "Zap" ON A WAND AND "Use" ON EVERYTHING ELSE. The word is the one place a
		# 40px tile can say that pressing this does not empty the slot — every other
		# kind's button is a goodbye and a wand's usually is not.
		var wand: bool = LootSystem.is_wand(entry)
		var use := UITheme.confirm_button("Zap" if wand else "Use",
			Vector2(0, LootSlot.USE_H), 10)
		use.disabled = locked_now
		# NOT "this is how an unknown one gets identified" any more: a use only
		# identifies a piece when it actually DID something (LootSystem's spend
		# paths), so a tooltip promising the lesson would be promising a lesson a
		# zap into an empty square does not buy.
		use.tooltip_text = "Spend a charge." if wand else "Spend it."
		use.pressed.connect(use_cb)
		col.add_child(use)
	return col

# The Preference as ONE CHARACTER, for the badge on the art. The word itself is
# still on the hover, the card and both modals — this is the corner of a 40px tile,
# and "Positive" does not go there. Deliberately ASCII: a new glyph in the source
# has to be baked into the subsetted fonts (tools/build_glyph_font.py), and a
# plus sign is not worth a font rebuild.
static func pref_glyph(entry: Dictionary) -> String:
	match LootSystem.preference(entry):
		"Positive":
			return "+"
		"Negative":
			return "-"
		"Neutral":
			return "="
	return "?"

static func _empty_body(with_use: bool) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, LootSlot.cell_height(with_use))
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer

# A known piece wears its accent at full strength; an unknown one is dimmed to the
# panel, which is the same "you have not learned this yet" the name says.
static func _filled_box(entry: Dictionary, loose: bool) -> StyleBoxFlat:
	var known: bool = LootSystem.is_identified(entry)
	return UITheme.flat(
		ACCENT.lerp(UITheme.BG, 0.78 if loose else 0.86), 6, 4,
		2 if loose else 1,
		ACCENT if loose else ACCENT.lerp(UITheme.BG, 0.3 if known else 0.65))

static func _empty_box() -> StyleBoxFlat:
	return UITheme.flat(Color(0, 0, 0, 0.20), 6, 4, 1, ACCENT.lerp(UITheme.BG, 0.85))

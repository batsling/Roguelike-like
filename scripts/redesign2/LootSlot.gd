class_name LootSlot
extends PanelContainer

# ONE CELL of the loot grid (docs/games-first-redesign.md §4.3) — a piece of loot
# you are carrying, an empty space you could put one in, or the piece a game has
# just paid out and is waiting to be dragged in.
#
# WHY THE WHOLE CELL IS ONE CONTROL. The art, its preference badge, the name and
# the Use button all belong to the same object, and the cell is a DRAG HANDLE:
# Godot starts a drag from whichever Control is under the cursor when the mouse
# moves with the button down, so anything that is meant to be grabbable has to be
# one node rather than a column of them. The Use button inside it consumes its own
# press, so it still clicks rather than starting a drag — which is the behaviour
# you want anyway: the button is the one part of the cell that isn't a handle.
#
# It is also the DROP TARGET, for the same reason in reverse — Godot walks up from
# the Control under the cursor looking for one that will take the payload, so a
# cell that accepts drops accepts them anywhere in its own footprint, the Use
# button included. An 88x105 target is a thing you can hit; a 34px tile is not.
#
# The two payloads it deals in:
#
#   {"kind": "loot_move", "from": int,      a piece already in the pack, being
#    "index": int}                          rearranged (LootGrid.allow_reorder).
#                                           `from` is the SLOT it is leaving and
#                                           `index` is where it sits in
#                                           GameState.loot_items — moving is about
#                                           slots, binning is about the piece, and
#                                           the two stopped being the same number
#                                           when a pack was allowed to have holes
#                                           in it.
#   {"kind": "loot_take", "entry": {...}}   a piece being taken INTO the pack from
#                                           a drop modal (LootGrid.allow_take) —
#                                           with `rot` when the piece is a bag
#   {"kind": "bag_move", "bag": int,        a bag already on the pack, picked up
#    "id": StringName, "rot": int}          by an empty cell of it (or its handle)
#
# Everything it decides is asked of the grid rather than answered here, so the two
# screens that draw a grid (the loot window and the drop modal) differ in the grid
# they build and not in nine copies of a rule.

# The grid this cell belongs to. Typed loosely because LootGrid names LootSlot and
# two class_names that name each other are a cyclic reference Godot resolves badly.
var grid: Node = null
# Where this cell sits in the 3x3, or -1 for a loose piece a drop modal is
# offering — it is draggable but it is not IN the pack yet, so it has no slot.
var slot_index: int = -1
# Where the piece in this cell sits in `GameState.loot_items`, or -1 when the cell
# is empty (or is a loose offer, which is in no array yet). NOT the same number as
# `slot_index`: the array is pickup order and the grid is an arrangement, and a
# pack with a hole in it is exactly where the two come apart.
var loot_index: int = -1
# WHICH offer this loose piece is, when a payout hands over several at once (Mom's
# Coin Purse pays four pills). Only meaningful while `slot_index` is -1, and it is
# what lets the modal cross the right one off when a piece lands in the pack: with
# four identical unidentified capsules on the table, the entry alone cannot say
# which of them the player just dragged.
var offer_index: int = -1
# What is in it. Empty for a free slot.
var entry: Dictionary = {}

# Art edge for a filled cell, against the 34 loot used to be drawn at. The old size
# came from the pack strip's relic token on the reasoning that a pill and a relic
# are both "a thing you are carrying" — right about parity, wrong about where
# parity is measured: 34px is what fits in a strip of twelve tokens, and in a panel
# with its own 240px of room it is a debug widget with 9px names under it.
#
# WHY NOT BIGGER. The window floats over the board inside a 720p canvas, and three
# rows of cell plus the panel's own furniture has to clear the header and still
# start below the top of the board (test_overworld2 asserts exactly that). 40 is
# what the height budget buys once the horse dose's extra third is paid for.
const ART := 40
# …and in the PACK, where the name and the Use button are laid over the picture
# instead of under it (LootGrid._overlaid), the picture takes the cell: 64, which
# leaves a horse dose's extra third (~84) inside the 96px body.
const ART_BIG := 64
# EVERY CELL IS A SQUARE, this many pixels a side, full or empty, with or without
# a Use button. It used to be 88 wide and 116 tall — a column of art, two lines of
# name and a button — and a grid of tall cards read as a list of tiles rather than
# as a grid, which is what the pack is now that bags give it a shape
# (docs/loot-passives.md §6): a 2x2 bag should look square. 104 is the smallest
# square that holds the art band, one line of name and the Use button, whose
# styled minimum is 26 tall (4 + 49 + 3 + 15 + 3 + 26 + 4 = 104).
const CELL := 104
# The width every cell keeps — the square's side, and still WIDE ENOUGH FOR THE
# WORD "Unidentified". At the 74px this started at, the longest name in the game
# broke mid-word.
const CELL_W := CELL
# The panel's own inner margin on every side (LootGrid._filled_box/_empty_box).
const PAD := 4
# The art sits in a band tall enough for the BIGGEST dose rather than being sized
# to its own piece. That is what lets a horse pill draw oversized (§4.3) without
# the row it is in growing taller than the other two: the capsule fills more of
# its band, the grid stays a grid, and the tell survives. It was sized for ART
# times the widest scale PillSystem.art_scale can report (~1.32, so 53) plus air;
# the square cell took 5px back, so the biggest capsule now overhangs its band by
# two pixels either side — into the GAP above and below it, never into the name.
const ART_BAND := 49
# Room for two lines of name — what the Use modal's piece grid still reserves
# (LootUseModal), where there is height to spare.
const NAME_H := 30
# The pack's square cell has room for ONE line, always reserved whether the name
# needs it or not (a name that sized itself would pull its Use button out of line
# with its neighbours'). A longer name ends in an ellipsis; the hover card carries
# the whole of it.
const NAME_LINE := 15
const USE_H := 18
# The Use / Zap / Swing pill laid over a pack cell's art: its least width, and how
# far it sits up off the cell's bottom edge (LootGrid._overlaid).
const USE_W := 38
const USE_INSET := 3
const GAP := 3

# How tall a cell's BODY stands, inside the panel's margin: the square, whatever
# the cell holds. `with_use` no longer changes it — a pack without Use buttons (the
# drag-time pack) is the same grid of squares as one with them.
static func cell_height(_with_use: bool = true) -> int:
	return CELL - PAD * 2

func _init() -> void:
	# Explicit, because everything this class is for depends on it: a drag begins on
	# the Control under the cursor and a drop is offered to the Control under the
	# cursor, so a cell that let mouse events through would be neither a handle nor a
	# target.
	mouse_filter = Control.MOUSE_FILTER_STOP

func _make_custom_tooltip(_for_text: String) -> Object:
	return HoverCard.of(self)

func is_filled() -> bool:
	return not entry.is_empty()

# ---------------------------------------------------------------------------
# Drag and drop
# ---------------------------------------------------------------------------

func _get_drag_data(_at: Vector2) -> Variant:
	if grid == null:
		return null
	# AN EMPTY CELL OF A BAG PICKS UP THE BAG (docs/loot-passives.md §6) — the
	# bag's handle does too, but a cell you can see is empty is the bigger target.
	if not is_filled():
		var bag: int = GameState.bag_at_slot(slot_index) if slot_index >= 0 else -1
		if bag < 0 or not grid.can_drag_bag():
			return null
		var move: Dictionary = grid.bag_payload(bag)
		if get_viewport() != null and get_viewport().gui_is_dragging():
			set_drag_preview(grid.bag_preview(move))
		return move
	if not grid.can_drag_from(self):
		return null
	# A BAG OFF A MODAL'S TABLE is a take like any other piece, plus the turn the
	# piece in your hand can put on it; what follows the cursor is its footprint.
	if slot_index < 0 and GameState.is_bag_entry(entry):
		var take: Dictionary = {"kind": "loot_take", "entry": entry.duplicate(true),
			"offer": offer_index, "rot": 0}
		if get_viewport() != null and get_viewport().gui_is_dragging():
			set_drag_preview(grid.loose_bag_preview(take))
		return take
	# GUARDED, because `set_drag_preview` is only legal while the viewport is
	# actually starting a drag — it fails outright otherwise. Godot itself only ever
	# calls this method in that state, so the guard costs a real drag nothing; what
	# it buys is that the method can also be called DIRECTLY, which is how the drag
	# is tested (test_overworld2) without an OS mouse to move.
	# EVERY PIECE CAN BE TURNED on its way (docs/loot-passives.md §2): the payload
	# carries the turn it has now, and the piece in your hand adds to it.
	var rot: int = int(entry.get("rot", 0))
	var data: Dictionary = {"kind": "loot_take", "entry": entry.duplicate(true),
		"offer": offer_index, "rot": rot} if slot_index < 0 \
		else {"kind": "loot_move", "from": slot_index, "index": loot_index, "rot": rot}
	if get_viewport() != null and get_viewport().gui_is_dragging():
		set_drag_preview(grid.drag_preview(self, data))
	return data

# What follows the cursor: THE WHOLE CELL, built by the grid — see
# LootGrid.drag_preview for why it is the cell and not the bare capsule, and why it
# is built there. A horse dose still drags at ITS size, because the cell it is drawn
# in draws it that way (LootSystem.art_box): the whole point of the oversized
# capsule is that you can tell which dose you are holding.
func _drag_preview() -> Control:
	return grid.drag_preview(self)

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if grid == null or not (data is Dictionary):
		return false
	# A bag is dropped on the PACK, so a slot under it hands the question to the
	# grid, in the grid's own coordinates. A loose offer is on no grid at all.
	if grid.is_bag_payload(data):
		return slot_index >= 0 and grid.can_accept_bag_at(position + at * scale, data)
	# A piece covering several cells is one target; the drop means the cell under
	# the pointer (docs/loot-passives.md §10).
	grid.drop_slot = _pointer_slot(at)
	var ok: bool = grid.can_accept(self, data)
	grid.drop_slot = -1
	return ok

func _drop_data(at: Vector2, data: Variant) -> void:
	if grid == null or not (data is Dictionary):
		return
	if grid.is_bag_payload(data):
		if slot_index >= 0:
			grid.accept_bag_at(position + at * scale, data)
		return
	grid.drop_slot = _pointer_slot(at)
	grid.accept(self, data)
	grid.drop_slot = -1

# The cell under the pointer, when it is one of the cells THIS slot covers — which
# only a big piece's anchor, stretched over its footprint, has more than one of.
# Anything else (a 1x1 cell, a grid not laid out yet) means this slot itself: -1.
func _pointer_slot(at: Vector2) -> int:
	if slot_index < 0 or grid == null or not is_filled():
		return -1
	var under: int = grid.slot_at_point(position + at * scale)
	if under < 0 or under == slot_index or GameState.loot_index_at_slot(under) != loot_index:
		return -1
	return under

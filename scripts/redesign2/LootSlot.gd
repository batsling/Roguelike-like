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
#   {"kind": "loot_move", "from": int}      a piece already in the pack, being
#                                           rearranged (LootGrid.allow_reorder)
#   {"kind": "loot_take", "entry": {...}}   a piece being taken INTO the pack from
#                                           a drop modal (LootGrid.allow_take)
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
# The width every cell keeps whether or not it has anything in it — a column that
# sized itself to its contents would jog left and right as pills are spent — and
# WIDE ENOUGH FOR THE WORD "Unidentified". At the 74px this started at, the longest
# name in the game breaks mid-word — "Unidentifie / d Scroll" — and the piece whose
# name is a mask is the one the grid is full of early on.
const CELL_W := 88
# The art sits in a band tall enough for the BIGGEST dose rather than being sized
# to its own piece. That is what lets a horse pill draw oversized (§4.3) without
# the row it is in growing taller than the other two: the capsule fills more of
# its band, the grid stays a grid, and the tell survives. Sized for ART times the
# widest scale PillSystem.art_scale can report (~1.32), plus a little air.
const ART_BAND := 54
# Room for two lines of name under the art, ALWAYS — and it has to be room for two
# REAL lines at the cell's font size, not merely more than one. The name used to
# size itself, which meant a one-line name ("Scroll of Fire") pulled its Use button
# above the two-line names either side of it and made a full row read as broken;
# reserving too little just moves the same fault to the cells that overflow it.
const NAME_H := 30
const USE_H := 18
const GAP := 3

# How tall one cell stands. An EMPTY slot is given the same, because a
# GridContainer sizes each row to its own tallest cell — so a bottom row with
# nothing in it would otherwise be visibly shorter than the two above it, and a
# half-full pack would read as a broken layout rather than as a half-full pack.
static func cell_height(with_use: bool) -> int:
	var h: int = ART_BAND + NAME_H + GAP
	return h + USE_H + GAP if with_use else h

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
	if not is_filled() or grid == null or not grid.can_drag_from(self):
		return null
	# GUARDED, because `set_drag_preview` is only legal while the viewport is
	# actually starting a drag — it fails outright otherwise. Godot itself only ever
	# calls this method in that state, so the guard costs a real drag nothing; what
	# it buys is that the method can also be called DIRECTLY, which is how the drag
	# is tested (test_overworld2) without an OS mouse to move.
	if get_viewport() != null and get_viewport().gui_is_dragging():
		set_drag_preview(_drag_preview())
	if slot_index < 0:
		return {"kind": "loot_take", "entry": entry.duplicate(true), "offer": offer_index}
	return {"kind": "loot_move", "from": slot_index}

# What follows the cursor: the art at the size the cell drew it, centred on the
# pointer. A horse dose drags at ITS size (LootSystem.art_box) — the whole point of
# the oversized capsule is that you can tell which dose you are holding, and a
# preview that normalised it would be the one place the tell went missing.
func _drag_preview() -> Control:
	var holder := Control.new()
	var art: TextureRect = LootSystem.art_tex(entry, ART)
	var box: float = float(LootSystem.art_box(entry, ART))
	art.position = Vector2(-box * 0.5, -box * 0.5)
	art.modulate = Color(1, 1, 1, 0.85)
	holder.add_child(art)
	return holder

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if grid == null or not (data is Dictionary):
		return false
	return grid.can_accept(self, data)

func _drop_data(_at: Vector2, data: Variant) -> void:
	if grid == null or not (data is Dictionary):
		return
	grid.accept(self, data)

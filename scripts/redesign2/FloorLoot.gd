class_name FloorLoot
extends PanelContainer

# ONE PIECE OF LOOT LYING ON A BATTLEFIELD SQUARE (§8.2) — and it is a DRAG
# HANDLE, not a button.
#
# WHY THERE IS NO CLICK. Picking a piece up used to be: click the square, wait for
# a modal to open over the board, find the pack inside it, drag the piece into a
# slot, close the modal. Four of those five steps exist to get the pack onto the
# screen — and the pack is nine cells that could simply BE on the screen for as
# long as you are holding something. So the piece is picked up directly, the pack
# appears beside the board while it is in the air (`DragPackPanel`, mounted by
# Overworld2 off NOTIFICATION_DRAG_BEGIN), and both the carry and the screen it
# needs end when you let go.
#
# That leaves a click doing nothing, deliberately. There is no second way to take
# a piece, because a second way would be a second set of rules about a full pack —
# and the drag has the good answer to that one (drop it on a carried piece and the
# two trade places, the evicted one landing on the square this one came off).
# READING a piece is still free: the hover card is the same one the pack, the loot
# window and the drop modal show, and it costs no gesture at all.
#
# The payload is the pack's own `loot_take`, plus the square: a floor take is the
# only one with somewhere to put what it evicts, and `cell` is that somewhere.
# LootGrid.can_accept keys off the presence of "floor" rather than off a second
# payload kind, so every rule about taking loot stays in the one place that
# already holds them.

# The piece. Empty is never drawn — BattlefieldView draws the ✦ fallback instead.
var entry: Dictionary = {}
# The square it is lying on, and the payload's `floor`.
var cell: Vector2i = Vector2i.ZERO
# Ring weight and colour, handed in by the board so a boss's drop stays the
# heavier one and the token keeps looking like the board drew it.
var ring: int = 2
var tint: Color = Color(1.0, 0.83, 0.36)

func _init() -> void:
	# Explicit, and everything this class is for depends on it: a drag begins on the
	# Control under the cursor, so a token that let mouse events through would not be
	# a handle at all.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG

func _ready() -> void:
	_repaint(false)
	mouse_entered.connect(func(): _repaint(true))
	mouse_exited.connect(func(): _repaint(false))

func _make_custom_tooltip(_for_text: String) -> Object:
	return HoverCard.of(self)

# Lit under the cursor, because a thing you can pick up has to say so before you
# try. The same two weights the pressable token wore, minus the pressed one — there
# is no press any more.
func _repaint(hot: bool) -> void:
	add_theme_stylebox_override("panel", UITheme.flat(
		Color(tint, 0.40 if hot else 0.16), 6, 0, ring,
		Color.WHITE if hot else tint))

# ---------------------------------------------------------------------------
# Drag
# ---------------------------------------------------------------------------

func _get_drag_data(_at: Vector2) -> Variant:
	if entry.is_empty():
		return null
	# GUARDED for the reason LootSlot's is: `set_drag_preview` is only legal while
	# the viewport is actually starting a drag, and this method is also called
	# DIRECTLY by the tests, which have no OS mouse to move.
	if get_viewport() != null and get_viewport().gui_is_dragging():
		# FACE DOWN, because it is still on the floor until it lands (cards-design
		# §3). A preview that turned the card over would make drag-and-cancel a free
		# look at every card on the board.
		set_drag_preview(LootGrid.preview_cell(entry, false))
	return {"kind": "loot_take", "entry": entry.duplicate(true), "offer": -1,
		"floor": cell}

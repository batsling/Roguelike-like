class_name DragPackPanel
extends PanelContainer

# THE PACK, FOR AS LONG AS YOU ARE HOLDING SOMETHING (§8.2).
#
# It exists only mid-drag. Pick a piece up off the battlefield floor (`FloorLoot`)
# and this appears to the LEFT of the board; let go — anywhere, on a slot or on
# nothing — and it is gone. Nothing about the page moves to make room for it and
# nothing has to be closed afterwards, because the gesture that summons it is the
# gesture that dismisses it.
#
# WHY IT IS TRANSIENT RATHER THAN A SCREEN. Taking a piece off the floor used to
# open the whole LootDropModal: a backdrop, a heading, an offer column, the pack,
# the bin, a fold of what the run has learned, and two buttons. Every one of those
# is worth having when a REPORT hands over a handful of loot and the player is
# deciding between them. None of it is worth having when one piece is on one square
# and the question is only "where does it go". What that question actually needs is
# the nine slots and the bin, in front of the player, at the moment their hand is
# full — which is a panel that arrives and leaves with the drag.
#
# WHY TO THE LEFT. The piece is on the board and the pack is where it is going, so
# the drag runs right-to-left across the page and the panel is at the end of it,
# not on top of where it started. Over the board it would cover the very square
# the piece came off — and the squares beside it, which is where the drag has to
# be able to end harmlessly when the answer is "not this one".
#
# THE GRID IS LootGrid, the same class the loot window and the drop modal draw, so
# the pack you drop into here is the pack you rearrange there — same cells, same
# swap rule, same bin. Two flags are off that the drop modal sets: `show_use`,
# because there is no clicking a button while the mouse is down, and `allow_take`,
# because there is no modal table here to take FROM. What is on instead is
# `allow_floor_take`, whose rule about a full pack is the whole reason a drag can
# answer one (LootGrid.can_accept).

const ACCENT := Color(0.72, 0.62, 0.86)
# Wide enough for three 88px cells plus the grid's two 6px gutters and the panel's
# own margins — the same three columns the pack is nine in everywhere else.
const PACK_W := LootSlot.CELL_W * LootGrid.COLS + 6 * (LootGrid.COLS - 1) + 20
# The gap between the panel's right edge and the board's left.
const BOARD_GAP := 10.0

var grid: LootGrid = null

# `on_take(entry, slot, cell)` and `on_bin(cell)` are the page's — this panel owns
# the drawing and the drop rules, and the run's state is somebody else's business.
static func build(on_take: Callable, on_bin: Callable) -> DragPackPanel:
	var panel := DragPackPanel.new()
	panel._build(on_take, on_bin)
	return panel

func _init() -> void:
	# The panel is a backdrop for the cells, not a target: the slots and the bin are
	# what take a drop, and a PanelContainer that swallowed the drop between them
	# would make the gutters dead. PASS lets the cursor through to whatever is under
	# it while its children still answer for themselves.
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(PACK_W, 0)
	add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG.lerp(ACCENT, 0.10), 8, 10, 2, ACCENT))

func _build(on_take: Callable, on_bin: Callable) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(col)

	# It says how full it is, because that is the fact the drag is about to run into.
	# A full pack is not an error here — it is a trade — so the line says which of
	# the two is happening rather than warning about one of them.
	var head := Label.new()
	head.text = "Your pack — %d / %d" % [
		GameState.loot_items.size(), GameState.loot_capacity()]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	grid = LootGrid.new()
	grid.allow_floor_take = true
	grid.allow_discard = true
	grid.floor_take_requested.connect(func(entry: Dictionary, slot: int, cell: Vector2i):
		on_take.call(entry, slot, cell))
	grid.floor_discarded.connect(func(cell: Vector2i): on_bin.call(cell))
	grid.rebuild()
	col.add_child(grid)

	var bin := LootTrash.new()
	bin.grid = grid
	col.add_child(bin)

	var hint := Label.new()
	hint.text = "Drop it in a slot." if not GameState.loot_is_full() \
		else "No room — drop it on a piece to trade."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color",
		UITheme.TEXT_FAINT if not GameState.loot_is_full() else UITheme.GOLD)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hint)

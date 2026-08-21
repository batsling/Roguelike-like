class_name LootGrid
extends GridContainer

# The pack's loot, as a 3x3 GRID YOU CAN REARRANGE (§4.3).
#
# Nine is the cap, so the grid is always nine: the empty slots are how the window
# says how much room is left, which is the fact the cap makes interesting, and
# three tiles in a 3x3 read as three of nine where three tiles in a row that wraps
# read as all there is.
#
# TWO SCREENS DRAW THIS SAME GRID, which is why it is a class rather than a method
# on the window:
#
#   the LOOT WINDOW  — `allow_reorder`, `show_use`. Pieces can be dragged between
#                      slots, and each one carries the button that spends it.
#   the DROP MODAL   — `allow_take`. The pack as it stands, with every slot a
#                      target for the piece the game just paid out. Showing the
#                      pack at the moment a drop is being decided is the entire
#                      point: "your pack is full" is a sentence, and nine slots
#                      with nothing free in them is the same thing said in one
#                      look.
#
# WHAT AN ARRANGEMENT CAN BE: ANY OF THEM. A piece goes wherever it is dropped —
# onto another piece, which swaps the two, or onto any empty slot, which leaves a
# hole behind it. `GameState.loot_items` stays dense because indices are what
# `use_loot` is addressed by; the SLOT rides on the entry instead, and
# `GameState.loot_layout()` is the one place the two are put back together. The
# grid redraws from that afterwards — so where a piece lands is where the run says
# it is, never a position the view is remembering on its own.
#
# TWO NUMBERS, AND THEY ARE NOT THE SAME NUMBER. Every signal below that names a
# piece hands over its INDEX in `GameState.loot_items` (what `use_loot`,
# `remove_loot_at` and the info card all take); `moved` alone deals in SLOTS,
# because moving is the one thing that is about where a piece is drawn.

# A piece was dropped into a slot from outside the pack (the drop modal's payload).
# `slot` is which of the nine it was dropped on, and `offer` says WHICH of the
# offers on the table it was — a payout of four identical unidentified capsules
# cannot be told apart by its entry.
signal take_requested(entry: Dictionary, slot: int, offer: int)
# A carried piece moved between slots of the 3x3 (swapping with whatever was there).
signal moved(from: int, to: int)
# The Use button on a carried piece.
signal use_requested(index: int)
# A carried piece was clicked — read it, don't spend it.
signal inspect_requested(index: int)
# A carried piece was dragged onto the bin (LootTrash).
signal discard_requested(index: int)
# One of the pieces a drop modal is offering was dragged onto the bin — which is
# the same answer as "Leave it", said with the hands.
signal offer_discarded(offer: int)

const ACCENT := Color(0.72, 0.62, 0.86)
const COLS := 3

# Pieces already in the pack can be dragged between slots.
var allow_reorder: bool = false
# Slots accept a piece from OUTSIDE the pack (a drop modal's offer).
var allow_take: bool = false
# Each filled cell carries the button that spends it.
var show_use: bool = false
# The bin will take a piece from this grid (LootTrash).
var allow_discard: bool = false
# Everything that spends or rearranges is off while a game is mid-report — the
# report step is between "played the game" and "said what happened", and loot
# cannot move in that gap.
var locked: bool = false

func _init() -> void:
	columns = COLS
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)

# Draw the nine. Called on every change rather than patched in place: the pack is
# at most nine cells and rebuilding it is cheaper than keeping a view in sync with
# an array that four systems can write to.
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var layout: Array = GameState.loot_layout()
	for slot in range(GameState.LOOT_CAPACITY):
		var index: int = int(layout[slot])
		var entry = GameState.loot_items[index] if index >= 0 else null
		add_child(_slot(slot, index, entry if entry is Dictionary else {}))

# A loose piece, drawn as a cell but belonging to no slot — the thing a drop modal
# offers up to be dragged in. Public because the modal builds it beside the grid
# rather than inside it.
static func loose_piece(entry: Dictionary, draggable: bool, host: LootGrid,
		with_name: bool = true, offer_index: int = -1,
		use_cb: Callable = Callable()) -> LootSlot:
	var slot := LootSlot.new()
	slot.grid = host
	slot.slot_index = -1
	slot.offer_index = offer_index
	slot.entry = entry
	slot.custom_minimum_size = Vector2(LootSlot.CELL_W, 0)
	slot.add_theme_stylebox_override("panel", _filled_box(entry, true))
	slot.mouse_default_cursor_shape = Control.CURSOR_DRAG if draggable \
		else Control.CURSOR_ARROW
	HoverCard.attach(slot, LootSystem.hover_card(entry))
	slot.add_child(_cell_body(entry, use_cb, false, with_name))
	return slot

# ---------------------------------------------------------------------------
# What a slot is allowed to do — asked by LootSlot, answered here, so the rules
# live in one place rather than in nine cells.
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
	match String(data.get("kind", "")):
		"loot_move":
			# ANY SLOT BUT ITS OWN. Onto a piece swaps the two, onto an empty one moves
			# it there and leaves a hole — both are arrangements the pack can hold now
			# that a slot is a fact about the entry rather than its place in an array.
			return allow_reorder and int(data.get("from", -1)) != slot.slot_index
		"loot_take":
			# INTO A FREE SLOT. "Put it here" onto an occupied one has no answer that
			# isn't a guess about which of the two the player meant to move.
			return allow_take and not slot.is_filled() and not GameState.loot_is_full()
	return false

# --- The bin ---------------------------------------------------------------
#
# Asked by LootTrash, answered here for the same reason the slots' rules are: the
# two screens that draw a grid differ in the grid they build, not in a second copy
# of what a drop means.

func can_trash(data: Dictionary) -> bool:
	if locked or not allow_discard:
		return false
	match String(data.get("kind", "")):
		"loot_move":
			return int(data.get("index", -1)) >= 0
		"loot_take":
			# The offer, thrown away rather than taken. Always allowed — a full pack
			# is exactly when you most want to say no to a piece with your hands.
			return true
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
			offer_discarded.emit(int(data.get("offer", -1)))

func accept(slot: LootSlot, data: Dictionary) -> void:
	match String(data.get("kind", "")):
		"loot_move":
			moved.emit(int(data.get("from", -1)), slot.slot_index)
		"loot_take":
			var entry = data.get("entry", {})
			if entry is Dictionary and not (entry as Dictionary).is_empty():
				take_requested.emit(entry, maxi(0, slot.slot_index),
					int(data.get("offer", -1)))

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
	var holder := Control.new()
	var cell := PanelContainer.new()
	cell.add_theme_stylebox_override("panel", _filled_box(slot.entry, true))
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.size = Vector2(LootSlot.CELL_W, LootSlot.cell_height(false))
	# Centred on the pointer, so the cell you are holding covers the slot you are
	# pointing at rather than hanging off one corner of it.
	cell.position = -cell.size * 0.5
	cell.modulate = Color(1, 1, 1, 0.9)
	cell.add_child(_cell_body(slot.entry, Callable(), false))
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
		slot.add_child(_empty_body(show_use))
		return slot

	slot.add_theme_stylebox_override("panel", _filled_box(entry, false))
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	HoverCard.attach(slot, LootSystem.hover_card(entry))
	var use_cb: Callable = Callable()
	if show_use:
		use_cb = func(): use_requested.emit(slot.loot_index)
	slot.add_child(_cell_body(entry, use_cb, locked))
	# CLICK READS, DRAG MOVES, THE BUTTON SPENDS. A relic in the pack opens its card
	# on a click and spends only from its own button, and loot answered a click with
	# nothing at all — the same object class with two different gestures. Now it
	# opens the same kind of card.
	#
	# ON RELEASE, and only if no drag came of it. A cell is both a click target and
	# a drag handle, and a drag necessarily begins with a press: reading the press
	# would open a card under every drag the player started, which is the one way to
	# make both gestures feel broken at once.
	slot.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and not ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT \
				and not slot.get_viewport().gui_is_dragging():
			inspect_requested.emit(slot.loot_index))
	return slot

# The art band, the name, the preference chip and (when the grid spends) the Use
# button. Static so the loose piece a modal offers is built by the same code as a
# slot in the pack — the thing being dragged and the thing it becomes have to look
# like each other or the drag reads as a swap.
# `with_name` is false for the loose piece a drop modal offers: the modal writes
# the name underneath at 18px, and the same words twice, 20 pixels apart, at two
# sizes, reads as a mistake rather than as emphasis.
static func _cell_body(entry: Dictionary, use_cb: Callable, locked_now: bool,
		with_name: bool = true) -> Control:
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
	var art: TextureRect = LootSystem.art_tex(entry, LootSlot.ART)
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
	var badge := UITheme.chip(pref_glyph(entry) if known else "?",
		UITheme.preference_color(LootSystem.preference(entry)) if known else UITheme.TEXT_FAINT,
		9)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	band.add_child(badge)
	col.add_child(band)

	if not with_name:
		return col

	var name := Label.new()
	name.text = LootSystem.display_name(entry)
	name.add_theme_font_size_override("font_size", 10)
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

	if use_cb.is_valid():
		var use := UITheme.confirm_button("Use", Vector2(0, LootSlot.USE_H), 10)
		use.disabled = locked_now
		use.tooltip_text = "Finish reporting this game first." if locked_now \
			else "Spend it — this is how an unknown one gets identified."
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

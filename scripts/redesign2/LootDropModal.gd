class_name LootDropModal
extends Control

# LootDropModal — "the game paid out a piece of loot, where do you want it?"
# (§4.3).
#
# Beating a game pays one random piece of loot, a straight 50/50 between a scroll
# and a pill. It ARRIVES THE WAY A KILL DROP DOES rather than as a toast, and the
# reason is the nine-piece cap: a pack that is already full turns the payout into
# a decision, and a decision needs a question.
#
# THE PACK IS ON THE SCREEN THAT ASKS. The modal used to show the piece alone and
# say "Your pack is full (9/9)" in red when it wasn't going to fit — a sentence
# about a thing the player could not see, on the one screen where what you are
# already carrying is the whole basis of the answer. So the 3x3 comes with it, and
# the piece is DRAGGED INTO THE SLOT it should live in: taking it and placing it
# are one gesture, the empty slots are the room left, and a pack with nothing free
# says so by having nowhere to drop.
#
# The buttons stay. Drag is the good gesture, not the only one — "Take it" puts the
# piece in the first free slot and "Leave it" is still the answer the cap makes
# interesting, and a decision this final should not depend on a drag landing.
#
# AND THE PACK IT SHOWS IS A LIVE ONE. Every piece on this screen can be spent
# from it, the offered one included:
#
#   * a carried piece has its Use button, the same one the loot window draws. A
#     full pack used to leave exactly two answers — leave the payout, or close the
#     modal, go and spend something, and never get the payout back — and the first
#     was the only one the screen offered. Spending one here frees the slot the
#     offer needs, in front of the offer, which is where the decision is.
#   * the OFFER can be used where it stands, without ever being carried
#     (LootSystem.use_entry). A Full Health you cannot fit in the pack is not a
#     piece of loot you should have to throw away, and "drink it now" is the answer
#     every roguelike gives to a full bag.
#   * anything can be dragged onto the BIN (LootTrash) and destroyed. Spending is
#     not the same as discarding: a pack of three known-Negative pills is full of
#     loot the run will never willingly use, and reading the Amnesia scroll to make
#     room is a worse answer than throwing it away.
#
# What it shows is what the player is allowed to know. An unidentified piece is
# its art, "Unidentified Pill", and nothing else — the whole point of taking one
# is finding out — while a colour the run has already learned says what it is and
# what it does, because by then it is a decision rather than a gamble.
#
# The queue behind it is the kill drops' own (Overworld2._drop_queue), so a game
# that paid loot AND left a relic asks twice, in the order they landed, rather than
# stacking two modals. Built in code on its own CanvasLayer, like every other 2.0
# modal.

# taken = the player kept it, and `slot` is WHERE they put it — the slot they
# dragged it into, or the end of the pack when they pressed the button. Emitted
# exactly once. The page does the taking (it owns the pack and the log line); this
# screen only ever reports the answer, slot included.
signal answered(taken: bool, slot: int)

var _entry: Dictionary = {}
var _layer: CanvasLayer = null
var _answered: bool = false
var _grid: LootGrid = null
# Whether loot can be spent from this screen at all. True in every real drop — by
# the time the modal opens the report has resolved and the phase is SELECT (see
# Overworld2._open_next_drop, which is deferred for exactly that reason) — but the
# page passes its own answer rather than this screen assuming one, so the rule
# about when loot can be spent lives in one place.
var _spendable: bool = true

const ACCENT := Color(0.72, 0.62, 0.86)
const PANEL_SIZE := Vector2(600, 0)
# The use modal opens on TOP of this one, so it needs a layer above this layer.
const LAYER := 122
const USE_LAYER := 130

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point: mount over `host` and ask about one rolled loot entry.
static func open(host: Node, entry: Dictionary, spendable: bool = true) -> LootDropModal:
	var modal := LootDropModal.new()
	modal._spendable = spendable
	modal._start(host, entry)
	return modal

func _start(host: Node, entry: Dictionary) -> void:
	_entry = entry.duplicate(true)
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _entry.is_empty():
		_answer(false, -1)
		return
	_build()

# Redrawn in place whenever the pack changes under it — spending a carried piece
# from this screen frees a slot, which turns "your pack is full" and a dead Take
# button into a live one. Rebuilding the whole panel rather than patching it is the
# same call the loot window makes for the same reason: nine cells is cheap, and a
# view kept in sync by hand is a view that eventually disagrees with the array.
func _rebuild() -> void:
	if _answered:
		return
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build()

func _build() -> void:
	# No click-outside-to-close: leaving loot on the ground is a decision, and it
	# should be made on a button rather than by a stray click.
	var panel := ModalScaffold.build_panel(self, ACCENT, Callable(), PANEL_SIZE)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	box.add_child(_line("✦  The game paid out", UITheme.TEXT_DIM, 15))

	# The pack, as a grid whose every slot will take the offer AND whose every piece
	# can be spent or thrown away without leaving this screen. Built FIRST because
	# the loose piece in the offer column hangs its drag rules off it.
	_grid = LootGrid.new()
	_grid.allow_take = true
	_grid.show_use = _spendable
	_grid.allow_discard = true
	_grid.take_requested.connect(func(_entry_in: Dictionary, index: int):
		_answer(true, index))
	_grid.use_requested.connect(_use_carried)
	_grid.discard_requested.connect(_discard_carried)
	# Throwing the OFFER in the bin is "Leave it" said with the hands.
	_grid.offer_discarded.connect(func(): _answer(false, -1))
	_grid.rebuild()

	# The offer on the left, the pack on the right, and the drag goes between them
	# in the direction you read.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	row.add_child(_offer_column())
	row.add_child(_pack_column())

	var full: bool = GameState.loot_is_full()
	if full:
		# The cap, said where it bites — and now beside the nine full slots that are
		# the reason, and beside the three things that can be done about it. A player
		# who cannot see why the button is dead reads it as a bug.
		box.add_child(_line("Your pack is full (%d/%d) — use or bin something to make room, "
			% [GameState.loot_items.size(), GameState.LOOT_CAPACITY]
			+ "use this one where you stand, or leave it.", UITheme.DANGER, 12))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var leave := UITheme.quiet_button("Leave it", Vector2(150, 40))
	leave.pressed.connect(func(): _answer(false, -1))
	buttons.add_child(leave)
	var take := UITheme.confirm_button("✓  Take it", Vector2(190, 40), 16)
	take.disabled = full
	take.tooltip_text = "No room — spend something first, or leave this." if full \
		else "Put it in the first free slot. Or drag it into the one you want."
	take.pressed.connect(func(): _answer(true, GameState.loot_items.size()))
	buttons.add_child(take)
	if not full:
		take.grab_focus()

# The piece being offered, drawn as the same cell it is about to become and
# draggable out of. `loose_piece` hangs it off the grid so the drag rules are the
# grid's rather than a second copy of them.
func _offer_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var holder := CenterContainer.new()
	holder.add_child(LootGrid.loose_piece(
		_entry, not GameState.loot_is_full(), _grid, false))
	col.add_child(holder)

	col.add_child(_line(LootSystem.display_name(_entry), ACCENT, 18))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UITheme.chip(LootSystem.kind_name(_entry), LootSystem.LOOT_COLOR))
	var pref: String = LootSystem.preference(_entry)
	if LootSystem.is_identified(_entry) and pref != "":
		chips.add_child(UITheme.chip(pref, UITheme.preference_color(pref)))
	else:
		chips.add_child(UITheme.chip("Unidentified", UITheme.TEXT_DIM))
	col.add_child(chips)

	var desc := _line(LootSystem.description(_entry), UITheme.TEXT, 13)
	desc.custom_minimum_size = Vector2(210, 0)
	col.add_child(desc)

	# USE IT WHERE YOU STAND. The offer is not in the pack and does not need to be:
	# a Full Health that will not fit is not a piece of loot you should have to
	# throw away, and drinking it now is the answer every roguelike gives to a full
	# bag. It costs no slot, so it is offered whether the pack is full or not —
	# spending a piece you were not going to carry is a real choice even with eight
	# slots free, and an unidentified one is still the gamble it always was.
	if _spendable:
		var use_now := UITheme.confirm_button(
			"Take it now" if _is_pill() else "Read it now", Vector2(0, 30), 12)
		use_now.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		use_now.tooltip_text = "Spend it on the spot, without carrying it.\n" \
			+ "It never enters your pack, so it costs you no room."
		use_now.pressed.connect(_use_offer)
		col.add_child(use_now)
	return col

func _is_pill() -> bool:
	return String(_entry.get("type", "")) == "pill"

# The pack as it stands, with every slot a target. Built before the offer column
# asks for it, since `loose_piece` needs the grid to ask about its own drag.
func _pack_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(_line("Your pack — %d / %d" % [
		GameState.loot_items.size(), GameState.LOOT_CAPACITY], UITheme.TEXT_DIM, 12))
	col.add_child(_grid)
	# The bin, under the grid it empties. Anything on this screen can go in it, the
	# offer included — see LootTrash.
	var bin := LootTrash.new()
	bin.grid = _grid
	col.add_child(bin)
	col.add_child(_line("Drag it into a slot, or onto the bin."
		if not GameState.loot_is_full() else "No room — make some, or use it now.",
		UITheme.TEXT_FAINT, 10))
	return col

# ---------------------------------------------------------------------------
# Spending and binning, without leaving the screen
# ---------------------------------------------------------------------------

# Spend a piece already in the pack. The use modal opens ABOVE this one (see
# USE_LAYER — a CanvasLayer's order is global, so a modal opened from on top of
# another has to be told to clear it), and when it closes the pack has changed:
# a slot is free, so the rebuild is what turns a dead Take button live.
func _use_carried(index: int) -> void:
	if _answered or not _spendable:
		return
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.layer_index = USE_LAYER
	modal.finished.connect(_after_use)
	modal.start(_page(), index, _page())

# Spend the OFFER itself, which was never in the pack and never will be. The drop
# is answered the moment it resolves: the piece is gone, and "taken" would be a lie
# — nothing was put in the pack, so the page has nothing to collect.
func _use_offer() -> void:
	if _answered or not _spendable:
		return
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.layer_index = USE_LAYER
	var spent := [false]
	# `finished` fires whether the piece was spent or the player backed out, and the
	# two mean different things here: backing out leaves the offer still on the
	# table, so the drop stays open.
	modal.used.connect(func(): spent[0] = true)
	modal.finished.connect(func():
		if spent[0]:
			_answer(false, -1)
		else:
			_rebuild())
	modal.start_entry(_page(), _entry, _page())

# Bin a piece already in the pack, once the player has said so twice — see
# LootTrash.confirm. The OFFER is the exception (LootGrid.can_trash lets it through
# unasked): binning that is "Leave it", which is already a one-click answer.
func _discard_carried(index: int) -> void:
	if _answered or index < 0 or index >= GameState.loot_items.size():
		return
	var piece_name: String = LootSystem.display_name(GameState.loot_items[index])
	LootTrash.confirm(_page(), piece_name, func():
		GameState.remove_loot_at(index)
		GameLog.add("Threw away %s." % piece_name, UITheme.DANGER)
		_after_use())

# One place for "the pack changed under this screen": redraw it, and let the page
# redraw the strip and window behind it.
func _after_use() -> void:
	if _answered:
		return
	var page: Node = _page()
	if page != null and page.has_method("_refresh_items"):
		page._refresh_items()
	_rebuild()

# The node this modal was mounted over — the Overworld2 page, which is the
# CanvasLayer's parent.
func _page() -> Node:
	return _layer.get_parent() if _layer != null and is_instance_valid(_layer) else null

func _line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# Public so a test can answer without a click, the way the relic drop's do.
func take() -> void:
	_answer(true, GameState.loot_items.size())

func leave() -> void:
	_answer(false, -1)

func _answer(taken: bool, slot: int) -> void:
	if _answered:
		return
	_answered = true
	answered.emit(taken, slot)
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

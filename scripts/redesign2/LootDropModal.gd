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

const ACCENT := Color(0.72, 0.62, 0.86)
const PANEL_SIZE := Vector2(560, 0)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point: mount over `host` and ask about one rolled loot entry.
static func open(host: Node, entry: Dictionary) -> LootDropModal:
	var modal := LootDropModal.new()
	modal._start(host, entry)
	return modal

func _start(host: Node, entry: Dictionary) -> void:
	_entry = entry.duplicate(true)
	_layer = CanvasLayer.new()
	_layer.layer = 122
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _entry.is_empty():
		_answer(false, -1)
		return
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

	# The pack, as a grid whose every slot will take the offer. Built FIRST because
	# the loose piece in the offer column hangs its drag rules off it.
	_grid = LootGrid.new()
	_grid.allow_take = true
	_grid.take_requested.connect(func(_entry_in: Dictionary, index: int):
		_answer(true, index))
	_grid.inspect_requested.connect(func(_i: int): pass)
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
		# the reason. A player who cannot see why the button is dead reads it as a bug.
		box.add_child(_line("Your pack is full (%d/%d). Spend something first, or leave this."
			% [GameState.loot_items.size(), GameState.LOOT_CAPACITY], UITheme.DANGER, 12))

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
	return col

# The pack as it stands, with every slot a target. Built before the offer column
# asks for it, since `loose_piece` needs the grid to ask about its own drag.
func _pack_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(_line("Your pack — %d / %d" % [
		GameState.loot_items.size(), GameState.LOOT_CAPACITY], UITheme.TEXT_DIM, 12))
	col.add_child(_grid)
	col.add_child(_line("Drag it into a slot." if not GameState.loot_is_full()
		else "No room.", UITheme.TEXT_FAINT, 10))
	return col

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

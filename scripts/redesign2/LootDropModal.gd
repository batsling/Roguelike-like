class_name LootDropModal
extends Control

# LootDropModal — "the game paid out, where do you want it?" (§4.3).
#
# Beating a game pays one random piece of loot, a straight 50/50 between a scroll
# and a pill. It ARRIVES THE WAY A KILL DROP DOES rather than as a toast, and the
# reason is the nine-piece cap: a pack that is already full turns the payout into
# a decision, and a decision needs a question.
#
# IT ASKS ABOUT A HANDFUL, not only about one. A game's own payout is a single
# piece, but Mom's Coin Purse is four pills at once and Sacred Bark doubles what a
# grant pays — and a screen built around exactly one offer answered that by
# shovelling the rest straight into the pack and silently dropping whatever did not
# fit. So the offer is a LIST: one cell per piece, each one taken, used or binned
# on its own terms, and the screen closes when there is nothing left on the table.
#
# THE PACK IT SHOWS IS THE INVENTORY, not a picture of it. The 3x3 on the right is
# the same LootGrid the loot window draws, with the same everything: pieces drag
# between slots, each carries the button that spends it, clicking one opens its
# card, and the bin under it takes anything. The only thing this screen has that
# the loot window does not is the offer on the left.
#
# What that buys is the answer to a full pack. It used to leave exactly two: leave
# the payout, or close the modal, go and spend something, and never get the payout
# back. Now:
#
#   * spending a carried piece frees the slot the offer needs, in front of the
#     offer, which is where the decision is being made. The drop stays on the table
#     while you do it — spending is not answering.
#   * an offered piece can be used WHERE IT STANDS, without ever being carried
#     (LootSystem.use_entry). A Full Health that will not fit is not loot anyone
#     should have to throw away, and it costs no slot.
#   * anything can go in the bin, offers included — which is "Leave it" said with
#     the hands.
#
# WHY THIS SCREEN COMMITS ITS OWN TAKES. Every other drop reports an answer and
# lets the page act on it. This one cannot: with several offers, and uses and bins
# interleaved between them, the slot the player chose is only meaningful at the
# instant they choose it — one use later every index behind it has moved. So each
# offer is placed as it is resolved, and `answered` reports the finished list for
# the page to log.
#
# What it shows is what the player is allowed to know. An unidentified piece is
# its art, "Unidentified Pill", and nothing else — the whole point of taking one is
# finding out — while a colour the run has already learned says what it is and what
# it does, because by then it is a decision rather than a gamble.
#
# The queue behind it is the kill drops' own (Overworld2._drop_queue). Built in
# code on its own CanvasLayer, like every other 2.0 modal.
#
# IT ALSO EMBEDS (`embed`). A payout that arrives with a REPORT is now a column of
# the post-combat screen (`PostCombatScreen`) rather than a popup over an
# animating board — the relics, the loot and the numbers are one haul and are read
# as one. Embedded it builds the same offer, the same live 3x3 and the same bin
# into somebody else's container; what it skips is the backdrop, the centring and
# the layer. The standalone modal stays for every payout that does NOT arrive with
# a report — `GameState.offer_loot` fires from EffectSystem, so an item, an event
# or a machine can hand loot over at any moment — and the two share every pixel.

# Emitted exactly once, when the screen closes. `taken` is the entries that ended
# up in the pack, in the order they were placed — the page logs them and refreshes.
signal answered(taken: Array)

# The pieces still on the table. Resolving one takes it out of here; empty closes
# the screen.
var _offers: Array = []
# What was actually placed in the pack, for the page's log.
var _taken: Array = []
var _layer: CanvasLayer = null
var _answered: bool = false
var _grid: LootGrid = null
var _panel: PanelContainer = null
var _body_scroll: ScrollContainer = null
# Whether loot can be spent from this screen at all. True in every real drop — by
# the time the modal opens the report has resolved and the phase is SELECT (see
# Overworld2._open_next_drop, which is deferred for exactly that reason) — but the
# page passes its own answer rather than this screen assuming one, so the rule
# about when loot can be spent lives in one place.
var _spendable: bool = true
# EMBEDDED MODE. `_slot` is the container this payout is a section of, `_body` is
# what it put there (rebuilt in place, taken down on the answer), and `_page_node`
# is the overworld the use modal and the info card mount over — as a modal that is
# reachable through `_layer.get_parent()`, and embedded there is no layer to ask.
var _slot: Container = null
var _body: Control = null
var _page_node: Node = null

const ACCENT := Color(0.72, 0.62, 0.86)
# The pack column is a 3x3 of LootSlot plus the panel's own padding.
const PACK_W := 300
const ROW_GAP := 18
const MARGIN := 18
# The rich single-offer column: art at full size with room for its description.
const SINGLE_W := 232
# How many rows of offers stand beside the pack before the rest scroll.
const OFFER_ROWS := 3
# The "Known this run" fold gets a shorter slice here than in the loot window: this
# panel carries the offer beside the pack as well, and an unfolded record must not
# push the answer buttons off a 720p screen.
const DISCOVERIES_H := 76
# What the panel leaves clear of the top and bottom of the screen before its body
# starts scrolling instead of growing.
const SCREEN_MARGIN := 16.0
# What the panel spends outside the scrolling body — its own margins, the
# scaffold's padding, and the pinned answer buttons. Subtracted from the room a
# modal is allowed so the cap applies to the panel and not just to the part that
# scrolls.
const CHROME_H := 92.0
# How wide a column this wants when embedded: the single offer, the gutter, the
# pack, and the panel's own margins either side. Anything narrower puts the pack
# under the offer instead of beside it, and the drag between them — which is what
# this screen is FOR — stops reading as a direction.
const EMBED_W := SINGLE_W + ROW_GAP + PACK_W + MARGIN * 2
# The least room the offer and the pack are ever squeezed into when embedded. The
# host's column decides the rest (see _fit_body); this is only the floor that
# stops a short column from collapsing the scroll to nothing and hiding the
# question entirely.
const EMBED_BODY_MIN_H := 200.0
# The use modal opens on TOP of this one, so it needs a layer above this layer.
const LAYER := 122
const USE_LAYER := 130

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point: mount over `host` and ask about one rolled entry, or about a whole
# handful. A bare Dictionary is accepted so the single-payout call site — which is
# nine drops in ten — reads the way it always has.
static func open(host: Node, offer, spendable: bool = true) -> LootDropModal:
	var modal := LootDropModal.new()
	modal._spendable = spendable
	modal._start(host, offer)
	return modal

func _start(host: Node, offer) -> void:
	for entry in (offer if offer is Array else [offer]):
		if entry is Dictionary and not (entry as Dictionary).is_empty():
			_offers.append((entry as Dictionary).duplicate(true))
	_layer = CanvasLayer.new()
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _offers.is_empty():
		_close()
		return
	_build()

# Entry point for the post-combat screen: put this payout INSIDE `slot` rather
# than over the page. `page` is the overworld — the use modal, the info card and
# the pack-strip refresh all still go to it — and `host` is the node the
# controller parks on, drawing nothing and taking no room.
static func embed(page: Node, host: Node, slot: Container, offer, spendable: bool = true) -> LootDropModal:
	var modal := LootDropModal.new()
	modal._spendable = spendable
	modal._slot = slot
	modal._page_node = page
	modal.set_anchors_preset(Control.PRESET_TOP_LEFT)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in (offer if offer is Array else [offer]):
		if entry is Dictionary and not (entry as Dictionary).is_empty():
			modal._offers.append((entry as Dictionary).duplicate(true))
	host.add_child(modal)
	if modal._offers.is_empty():
		modal._close()
		return modal
	modal._build()
	return modal

# Redrawn in place whenever anything on it changes — an offer resolved, a carried
# piece spent, a slot emptied. Rebuilding the whole panel rather than patching it
# is the call the loot window makes for the same reason: nine cells is cheap, and a
# view kept in sync by hand is a view that eventually disagrees with the array.
func _rebuild() -> void:
	if _answered:
		return
	if _offers.is_empty():
		_close()
		return
	# Embedded, what has to go is the section in the HOST's container — the rest of
	# that column belongs to somebody else. As a modal it is everything under self.
	# Unparented BEFORE it is freed, the way the modal path below does it: a
	# `queue_free` alone leaves the old panel in the column for a frame, and the
	# replacement built two lines later would sit under a ghost of itself.
	_drop_body()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build()

func _build() -> void:
	var multi: bool = _offers.size() > 1
	var offer_w: int = _offer_columns() * (LootSlot.CELL_W + 6) if multi else SINGLE_W
	var width: float = float(offer_w + ROW_GAP + PACK_W + MARGIN * 2)

	if _slot != null:
		# A section of the host's page: bordered like the panels around it, as wide
		# as the column it stands in, and with no backdrop of its own — the screen
		# under it is already the host's.
		_panel = PanelContainer.new()
		_panel.add_theme_stylebox_override("panel",
			UITheme.panel_box(UITheme.PANEL, ACCENT.lerp(UITheme.BORDER, 0.45), 10, 0, 1))
		_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Takes the column's height as well as its width, so the body below can be
		# handed the leftover rather than guessing at a number (see _fit_body).
		_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_slot.add_child(_panel)
		_body = _panel
	else:
		# No click-outside-to-close: leaving loot on the ground is a decision, and it
		# should be made on a button rather than by a stray click.
		_panel = ModalScaffold.build_panel(self, ACCENT, Callable(), Vector2(width, 0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", MARGIN)
	margin.add_theme_constant_override("margin_right", MARGIN)
	# Tighter top and bottom when embedded. As a modal this panel owns the screen
	# and can spend the air; on the post-combat screen it is one column of five
	# sections, and every row it gives back is a row the BIN gets to stay above the
	# fold in — which matters, because the bin is one of the three answers.
	var pad: int = 8 if _slot != null else 14
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	_panel.add_child(margin)
	# THE BODY SCROLLS IF IT HAS TO. Eight offers beside a pack with the "Known this
	# run" fold open is 700px of content in a 720px canvas, and a modal whose answer
	# buttons are off the bottom of the screen is a modal that cannot be answered.
	# It is only clamped when it actually overflows (see `_clamp_height`), so every
	# ordinary payout still sizes itself to its contents and shows no scrollbar.
	# THE ANSWERS STAY OUT OF THE SCROLL. Only what the player is deciding ABOUT
	# scrolls; "Leave the rest" and "Take" are pinned under it, because a modal whose
	# answer buttons are somewhere below the fold is a modal that looks unanswerable.
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	margin.add_child(shell)
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(_body_scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(box)

	# "The game paid out" — said once, by whoever owns the screen. Embedded, the
	# host has already put a verdict and a game's name across the top of the page
	# and this column is plainly the payout on it; a second announcement costs a row
	# the pack needs and tells the reader nothing they are not looking at.
	if _slot == null:
		box.add_child(_line("✦  The game paid out" if not multi
			else "✦  The game paid out %d pieces" % _offers.size(), UITheme.TEXT_DIM, 15))

	# The pack, built FIRST because every offer cell hangs its drag rules off it.
	# EVERYTHING THE LOOT WINDOW'S GRID DOES, because it is the same grid: rearrange,
	# inspect, spend, bin — plus taking what is on the table.
	_grid = LootGrid.new()
	_grid.allow_take = true
	_grid.allow_reorder = true
	_grid.show_use = _spendable
	_grid.allow_discard = true
	_grid.take_requested.connect(_take_offer)
	_grid.use_requested.connect(_use_carried)
	_grid.discard_requested.connect(_discard_carried)
	_grid.inspect_requested.connect(_inspect_carried)
	_grid.moved.connect(func(from: int, to: int):
		if GameState.move_loot(from, to):
			_rebuild())
	_grid.offer_discarded.connect(_leave_offer)
	_grid.rebuild()

	# The offer on the left, the pack on the right, and the drag goes between them
	# in the direction you read.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var offer_col: Control = _offer_column(multi)
	row.add_child(offer_col)
	row.add_child(_pack_column())
	# THE FOLD CHANGES SIDES WHEN EMBEDDED. "Known this run" is not a fact about the
	# pack — it is what the RUN has learned — and under the pack it was the row that
	# pushed the bin off the bottom of the post-combat screen's column. The offer
	# side is the short one there (one piece against nine slots), so the fold goes
	# where the space already is. As a modal it stays under the pack, which is where
	# it has always been and where there is room for it.
	if _slot != null and offer_col is VBoxContainer:
		(offer_col as VBoxContainer).add_child(
			LootDiscoveries.build(_rebuild, DISCOVERIES_H))

	if GameState.loot_is_full():
		# The cap, said where it bites — beside the nine full slots that are the
		# reason, and beside the three things that can be done about it.
		box.add_child(_line("Your pack is full (%d/%d) — use or bin something to make room, "
			% [GameState.loot_items.size(), GameState.LOOT_CAPACITY]
			+ "use these where you stand, or leave them.", UITheme.DANGER, 12))

	shell.add_child(_buttons(multi))
	_fit_body(box)

# How wide the offer grid runs. Two abreast is the shape of a four-pill payout;
# three only once there are more than four, so a handful never becomes a wall.
func _offer_columns() -> int:
	return 2 if _offers.size() <= 4 else 3

# ---------------------------------------------------------------------------
# The offer side
# ---------------------------------------------------------------------------

func _offer_column(multi: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	if multi:
		col.add_child(_line("On the table — %d" % _offers.size(), UITheme.TEXT_DIM, 12))
		col.add_child(_offer_grid())
		col.add_child(_line("Drag each one into a slot, or use it where it stands.",
			UITheme.TEXT_FAINT, 10))
		return col
	_build_single(col)
	return col

# SEVERAL OFFERS, as the same cells they would be in the pack — art, name,
# preference badge, hover card and the button that spends them. There is no room
# for four descriptions side by side and no need for them: the cell IS the
# description at this size, and the hover carries the rest.
func _offer_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = _offer_columns()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in range(_offers.size()):
		var idx: int = i
		grid.add_child(LootGrid.loose_piece(_offers[i], not GameState.loot_is_full(),
			_grid, true, idx,
			(func(): _use_offer(idx)) if _spendable else Callable()))
	# Three rows fit beside the pack without the panel outgrowing a 720p canvas,
	# which covers everything the game can currently pay at once — Mom's Coin Purse
	# is four and Sacred Bark doubles it to eight. Anything bigger scrolls rather
	# than pushing the buttons off the bottom of the screen: a payout that cannot be
	# answered is worse than one you have to scroll.
	if _offers.size() <= _offer_columns() * OFFER_ROWS:
		return grid
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(
		_offer_columns() * (LootSlot.CELL_W + 6),
		LootSlot.cell_height(_spendable) * OFFER_ROWS + 6 * (OFFER_ROWS - 1))
	scroll.add_child(grid)
	return scroll

# ONE offer, at full size — nine payouts in ten, and the layout this screen has
# always had: the piece, what it is, what it does, and the two ways to spend it.
func _build_single(col: VBoxContainer) -> void:
	var entry: Dictionary = _offers[0]
	var holder := CenterContainer.new()
	holder.add_child(LootGrid.loose_piece(
		entry, not GameState.loot_is_full(), _grid, false, 0))
	col.add_child(holder)

	col.add_child(_line(LootSystem.display_name(entry), ACCENT, 18))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_child(UITheme.chip(LootSystem.kind_name(entry), LootSystem.LOOT_COLOR))
	var pref: String = LootSystem.preference(entry)
	if LootSystem.is_identified(entry) and pref != "":
		chips.add_child(UITheme.chip(pref, UITheme.preference_color(pref)))
	else:
		chips.add_child(UITheme.chip("Unidentified", UITheme.TEXT_DIM))
	col.add_child(chips)

	var desc := _line(LootSystem.description(entry), UITheme.TEXT, 13)
	desc.custom_minimum_size = Vector2(SINGLE_W - 16, 0)
	col.add_child(desc)

	# USE IT WHERE YOU STAND. The offer is not in the pack and does not need to be.
	# Offered whether the pack is full or not — spending a piece you were not going
	# to carry is a real choice even with eight slots free, and an unidentified one
	# is still the gamble it always was.
	if _spendable:
		var use_now := UITheme.confirm_button(
			"Take it now" if _is_pill(entry) else "Read it now", Vector2(0, 30), 12)
		use_now.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		use_now.tooltip_text = "Spend it on the spot, without carrying it.\n" \
			+ "It never enters your pack, so it costs you no room."
		use_now.pressed.connect(func(): _use_offer(0))
		col.add_child(use_now)

func _is_pill(entry: Dictionary) -> bool:
	return String(entry.get("type", "")) == "pill"

# ---------------------------------------------------------------------------
# The pack side
# ---------------------------------------------------------------------------

func _pack_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(PACK_W, 0)
	col.add_child(_line("Your pack — %d / %d" % [
		GameState.loot_items.size(), GameState.LOOT_CAPACITY], UITheme.TEXT_DIM, 12))
	col.add_child(_grid)
	var bin := LootTrash.new()
	bin.grid = _grid
	col.add_child(bin)
	# The instruction line goes when the panel is embedded, and the bin it was
	# explaining is what it goes FOR: on the post-combat screen this column shares
	# a 720p page with four other sections, and a caption under a labelled bin was
	# the cheapest row to spend to keep the bin itself above the fold. The full-pack
	# warning is kept in both — that one says something the picture doesn't.
	if _slot == null:
		col.add_child(_line("Drag into a slot, rearrange, or bin what you don't want."
			if not GameState.loot_is_full() else "No room — make some, or use them now.",
			UITheme.TEXT_FAINT, 10))
	elif GameState.loot_is_full():
		col.add_child(_line("No room — make some, or use them now.", UITheme.DANGER, 10))
	# WHAT THE RUN HAS LEARNED, the same fold the loot window carries and sharing its
	# state (LootDiscoveries.open) — the pack this screen shows is the inventory, so
	# it answers "what does green do again" in the same place. Given a shorter slice
	# than the window gets: this panel already has the offer beside it, and the fold
	# must not push the answer buttons off a 720p screen.
	#
	# Embedded it is added to the OFFER column instead (see _build), which is the
	# short side there — this column has the bin to keep above the fold.
	if _slot == null:
		col.add_child(LootDiscoveries.build(_rebuild, DISCOVERIES_H))
	return col

func _buttons(multi: bool) -> Control:
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var leave := UITheme.quiet_button(
		"Leave the rest" if multi else "Leave it", Vector2(160, 38))
	leave.tooltip_text = "Walk away from what is still on the table."
	leave.pressed.connect(_close)
	buttons.add_child(leave)

	var room: int = GameState.loot_space()
	var take := UITheme.confirm_button(
		"✓  Take it" if not multi else "✓  Take %d" % mini(room, _offers.size()),
		Vector2(190, 38), 16)
	take.disabled = room <= 0
	take.tooltip_text = "No room — use or bin something first, or use these where you stand." \
		if room <= 0 else "Put them in the first free slots. Or drag each into the one you want."
	take.pressed.connect(_take_all)
	buttons.add_child(take)
	# DEFERRED: this row is built before it is parented, and `grab_focus` on a
	# Control that is not yet in the tree fails outright. GUARDED at the other end
	# too, now that this panel can be a section of somebody else's screen: that
	# screen can be opened and left inside one frame (every headless test of it
	# does), and the deferred call would then land on a button that is gone.
	if room > 0:
		var btn: Button = take
		(func():
			if is_instance_valid(btn) and btn.is_inside_tree():
				btn.grab_focus()).call_deferred()
	return buttons

# ---------------------------------------------------------------------------
# Resolving an offer
# ---------------------------------------------------------------------------

# Dropped into a slot of the 3x3. `offer` says which of the pieces on the table it
# was — with four identical unidentified capsules the entry alone cannot say.
func _take_offer(entry: Dictionary, slot: int, offer: int) -> void:
	if _answered:
		return
	if not GameState.take_loot_entry_at(entry, slot):
		return
	_taken.append(entry.duplicate(true))
	_forget_offer(offer, entry)
	_after_change()

func _take_all() -> void:
	if _answered:
		return
	while not _offers.is_empty() and not GameState.loot_is_full():
		var entry: Dictionary = _offers[0]
		# The FIRST FREE SLOT, which is what the button's own tooltip promises — the
		# per-piece answer is the drag, and this is the one for "just take them".
		if not GameState.take_loot_entry(entry):
			break
		_taken.append(entry.duplicate(true))
		_offers.remove_at(0)
	_after_change()

func _leave_offer(offer: int) -> void:
	if _answered:
		return
	_forget_offer(offer, {})
	_after_change()

# Spend one of the offers where it stands. It never enters the pack, so it is off
# the table either way once the use resolves; backing out of the use modal leaves
# it exactly where it was.
func _use_offer(offer: int) -> void:
	if _answered or not _spendable or offer < 0 or offer >= _offers.size():
		return
	var entry: Dictionary = _offers[offer]
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.layer_index = USE_LAYER
	var spent := [false]
	modal.used.connect(func(): spent[0] = true)
	modal.finished.connect(func():
		if spent[0]:
			_forget_offer(offer, entry)
		_after_change())
	modal.start_entry(_page(), entry, _page())

# Take an offer off the table BY INDEX, falling back to the first matching entry
# when the index is missing — a payload from an older drag, or the single-offer
# path, can arrive without one.
func _forget_offer(offer: int, entry: Dictionary) -> void:
	if offer >= 0 and offer < _offers.size():
		_offers.remove_at(offer)
		return
	if entry.is_empty():
		return
	for i in range(_offers.size()):
		if _offers[i] == entry:
			_offers.remove_at(i)
			return

# ---------------------------------------------------------------------------
# Spending and binning from the pack, without leaving the screen
# ---------------------------------------------------------------------------

# The use modal opens ABOVE this one (see USE_LAYER — a CanvasLayer's order is
# global, so a modal opened from on top of another has to be told to clear it), and
# when it closes the pack has changed: a slot is free, which is what turns a dead
# Take button live.
func _use_carried(index: int) -> void:
	if _answered or not _spendable:
		return
	var modal = preload("res://scripts/redesign2/LootUseModal.gd").new()
	modal.layer_index = USE_LAYER
	modal.finished.connect(_after_change)
	modal.start(_page(), index, _page())

# Bin a piece already in the pack, once the player has said so twice — see
# LootTrash.confirm. The OFFERS are the exception (LootGrid.can_trash lets them
# through unasked): binning one of those is "Leave it", already a one-click answer.
func _discard_carried(index: int) -> void:
	if _answered or index < 0 or index >= GameState.loot_items.size():
		return
	var piece_name: String = LootSystem.display_name(GameState.loot_items[index])
	LootTrash.confirm(_page(), piece_name, func():
		GameState.remove_loot_at(index)
		GameLog.add("Threw away %s." % piece_name, UITheme.DANGER)
		_after_change())

# Reading a carried piece, on the same terms the loot window offers it: the card
# opens above this screen, and firing from it goes back through the same use path.
func _inspect_carried(index: int) -> void:
	if _answered or index < 0 or index >= GameState.loot_items.size():
		return
	var entry = GameState.loot_items[index]
	if not (entry is Dictionary):
		return
	var layer := CanvasLayer.new()
	layer.layer = USE_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_page().add_child(layer)
	var card := LootInfoCard.new()
	card.use_requested.connect(_use_carried)
	card.closed.connect(func():
		if is_instance_valid(layer):
			layer.queue_free())
	layer.add_child(card)
	card.setup(entry, index, _spendable)

# One place for "something on this screen changed": redraw it, let the page redraw
# the strip and window behind it, and close if the table is empty.
func _after_change() -> void:
	if _answered:
		return
	var page: Node = _page()
	if page != null and page.has_method("_refresh_items"):
		page._refresh_items()
	_rebuild()

# Size the scrolling body to its own contents, and cap it at what the screen has
# room for. A ScrollContainer has no natural height of its own — left alone it
# collapses to nothing and takes the panel with it — so it is always told how tall
# to be; the only question is whether the contents or the screen decides.
#
# The cap is what stops eight offers beside a full pack with the "Known this run"
# fold open (about 700px of content in a 720px canvas) from putting the answer
# buttons off the bottom of the screen. A modal that cannot be answered is worse
# than one you have to scroll. Everything smaller sizes to its contents exactly and
# never shows a scrollbar.
func _fit_body(box: Control) -> void:
	if _body_scroll == null or not is_instance_valid(_body_scroll):
		return
	# EMBEDDED, THE COLUMN DECIDES. The host has a header and a footer of its own
	# on this screen, so the viewport is not this panel's to measure — it takes the
	# height left over in the column instead, and the floor is only there so a
	# short column cannot collapse the scroll to nothing and hide the question.
	if _slot != null:
		_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_body_scroll.custom_minimum_size.y = EMBED_BODY_MIN_H
		return
	var content: float = box.get_combined_minimum_size().y
	# Against the room a modal is actually ALLOWED (ModalScaffold.free_rect), not
	# against the screen: the run's header bar is opaque and drawn over every modal,
	# so the top of the screen is not this panel's to use. Measuring against the
	# whole 720 left the panel ending 19px below the window.
	var room: float = ModalScaffold.free_rect(self).size.y - SCREEN_MARGIN * 2.0 - CHROME_H
	_body_scroll.custom_minimum_size.y = minf(content, maxf(240.0, room))

# The overworld: what the use modal, the info card and the pack-strip refresh are
# mounted on and asked of. Handed in when embedded, and reached through the layer
# this modal mounted itself on otherwise.
func _page() -> Node:
	if _page_node != null and is_instance_valid(_page_node):
		return _page_node
	return _layer.get_parent() if _layer != null and is_instance_valid(_layer) else null

func _line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# Take this payout's section out of the host's column and free it. Unparented
# first so the column is genuinely empty the moment this returns — the rebuild
# adds its replacement immediately, and `queue_free` alone would leave the two
# stacked for a frame.
func _drop_body() -> void:
	if _body == null or not is_instance_valid(_body):
		_body = null
		return
	if _body.get_parent() != null:
		_body.get_parent().remove_child(_body)
	_body.queue_free()
	_body = null

# How many pieces are still on the table. The post-combat screen reads it to say
# what its way out is about to bin, so leaving a Legendary on the ground stays a
# decision rather than a side effect of pressing Continue.
func remaining() -> int:
	return _offers.size()

# Public so a test can answer without a click, the way the relic drop's do.
func take() -> void:
	_take_all()

func leave() -> void:
	_close()

func _close() -> void:
	if _answered:
		return
	_answered = true
	answered.emit(_taken.duplicate(true))
	# Its own layer as a modal; embedded, only its section of the host's column —
	# the rest of that column is somebody else's and outlives the answer.
	_drop_body()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

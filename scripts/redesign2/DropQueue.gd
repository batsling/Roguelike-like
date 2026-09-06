class_name DropQueue
extends RefCounted

# EVERYTHING THE RUN PAYS OUT, AND THE ORDER IT IS ASKED ABOUT (§8, §8.2).
#
# Three different things drop loot at the player and they must not stack modals on
# top of each other: a body defeated mid-game leaves a piece on the square it fell
# in, a game reported pays its own piece and its relic chests, and a relic or an
# event can hand over a fistful at any moment. This is the one queue all of them
# land in, the rules about when it is allowed to ask, and the two gestures that
# get a piece off the floor.
#
# WHY LOOT ON THE FLOOR AND RELICS AT THE REPORT. A body used to drop a chest, and
# a chest is a question the board is not allowed to answer — its card deliberately
# does not say what is inside, so what stood on the square was a gold glyph
# standing in for an offer you could only read by opening it. A scroll, a pill or a
# potion IS a thing: it can be drawn as itself, on its own square, and recognised
# across the board while a body is still walking at you. So the floor pays loot and
# the relics moved to the reward screen where the choosing belongs.
#
# Split out of Overworld2 (docs/performance-backlog.md §1), which named this seam
# when it was 230 lines; it had doubled. It owns the QUEUE, the modal in front of
# it and the drag pack — nothing else. The page still owns the board, the phase and
# every screen these hand off to, and everything this class does to the run goes
# back through the page's public verbs or through GameLoop2/GameState directly,
# which is what keeps the existing tests working through the move.
#
# `_page` is the Overworld2 that owns this queue, typed loosely because Overworld2
# names DropQueue and two class_names that name each other are a cyclic reference
# Godot resolves badly.
var _page: Node = null

# The drops waiting to be asked about, oldest first. Each entry is either
# `{loot: [...]}` (scrolls, pills, potions, cards — LootDropModal) or
# `{items: [ItemData]}` (a relic chest — ItemDropModal). The single-item
# `{item: ItemData}` shorthand is still read so a save written before chests had a
# size, and the tests that hand-build a drop, keep working.
#
# The page publishes this as `_drop_queue`, which is the name the tests already
# reach for.
var queue: Array = []

# The modal standing in front of the queue, or null when nothing is being asked.
# Published by the page as `_drop_modal` — with a SETTER, because unlike the other
# two the tests do assign this one (they stand a modal up by hand and take it down
# again).
var modal: Node = null

# The pack, mounted only for the length of a drag off the floor. Published as
# `_drag_pack`.
var drag_pack: DragPackPanel = null

func _init(page: Node) -> void:
	_page = page

# ---------------------------------------------------------------------------
# Kill-drops (§8)
# ---------------------------------------------------------------------------

# A defeated enemy dropped LOOT: roll the piece it left and lay it on the square
# it died in. Skipped once the run is over (win/lose screens take over the board).
#
# One piece per body, rolled on the same four-way scroll/pill/potion/card split as
# a game's own payout (§4.3, docs/cards-design.md §4) — a boss included. What a
# body is worth in RELICS is its difficulty, and that is banked rather than dropped
# (GameLoop2._defeat).
func on_enemy_defeated(enemy: GoalEnemyData, cell: Vector2i) -> void:
	if GameLoop2.run_over:
		return
	var from_boss: bool = enemy != null and enemy.is_boss()
	var entry: Dictionary = GameState.roll_loot_entry("loot")
	if entry.is_empty():
		return
	# ON THE FLOOR, where the body fell (§8.2). A kill you make mid-game puts its
	# payout on the board in front of you rather than behind a screen you have not
	# reached yet — that is what makes clearing a goal DURING a game worth doing.
	# What nobody picks up is swept onto the haul screen when the game is reported
	# (sweep_floor).
	if cell == GameLoop2.OFF_FIELD \
			or GameLoop2.place_drop(cell, entry, from_boss) == GameLoop2.OFF_FIELD:
		# Nowhere on the board for it — a body still in the off-grid queue has no
		# square to fall in, and a full floor has no room left. It goes straight to
		# the screen the game ends on, which is where an unclaimed piece ends up
		# anyway.
		queue.append({"loot": [entry]})
		pump()
	_page.refresh_board()

# ---------------------------------------------------------------------------
# Picking a piece up off the floor (§8.2)
# ---------------------------------------------------------------------------
#
# THE GESTURE IS THE WHOLE INTERACTION. Dragging a token off a board square
# (`FloorLoot`) puts the pack on screen beside the board for as long as the piece
# is in the air (`DragPackPanel`), and letting go — in a slot, on the bin, or on
# nothing at all — ends both.
#
# It replaces a click that opened the LootDropModal, whose entire contribution to
# a one-piece decision was drawing the nine slots this drag now drops straight
# into. The modal is still what a REPORT's handful is answered on; it is no longer
# the toll on picking one thing up.

# A piece dragged off the floor and into slot `slot` of the 3x3.
#
# TWO OUTCOMES, and which one it is depends on whether that slot was occupied:
#   free   — the piece goes in and the square is cleared.
#   filled — the two TRADE: the carried piece comes out and lands on the square
#            this one came off, which is the answer to a full pack that only a
#            floor take can give (LootGrid.can_accept). The square is never left
#            empty by a swap, so a mistake costs a drag rather than a piece.
func take_floor_loot(entry: Dictionary, slot: int, cell: Vector2i) -> void:
	if GameLoop2.run_over or entry.is_empty():
		return
	var held: Dictionary = GameLoop2.drop_at(cell)
	# The square is what says the piece is still there to be taken. A payload from a
	# drag whose square has since been swept (a report resolving underneath it) is
	# refused rather than minting a second copy of the piece.
	if held.is_empty() or floor_loot(held) != entry:
		return
	var displaced: Dictionary = GameState.swap_loot_entry_at(entry, slot)
	if displaced.is_empty() and not GameState.take_loot_entry_at(entry, slot):
		return
	GameLoop2.take_drop(cell)
	if not displaced.is_empty():
		# Back onto the square the new piece came off — and NOT as a boss's drop
		# whatever was on that square before, because a piece out of your own pack
		# was not left there by anything.
		GameLoop2.place_drop(cell, displaced)
		GameLog.add("Traded %s for %s." % [LootSystem.display_name(displaced),
			LootSystem.display_name(entry)], Color(0.72, 0.62, 0.86))
	else:
		GameLog.add("Picked up %s." % LootSystem.display_name(entry),
			Color(0.72, 0.62, 0.86))
	_page.refresh_board()
	_page.refresh_loot_window()

# A piece dragged off the floor and onto the bin. It ASKS FIRST, on the same terms
# a carried piece binned in the loot window does (LootTrash.confirm): this is the
# one gesture on the board that destroys something and gives nothing back, and it
# is a strictly worse outcome than the thing that happens if you do nothing at all
# — a piece left lying is swept onto the haul screen and is still yours.
func bin_floor_loot(cell: Vector2i) -> void:
	if GameLoop2.run_over:
		return
	var entry: Dictionary = floor_loot(GameLoop2.drop_at(cell))
	if entry.is_empty():
		return
	LootTrash.confirm(_page, LootSystem.display_name(entry), func():
		# Re-read on the way through: the confirmation is a screen the player spends
		# time on, and the square may have been swept by a report behind it.
		if floor_loot(GameLoop2.drop_at(cell)) != entry:
			return
		GameLoop2.take_drop(cell)
		GameLog.add("Threw away %s." % LootSystem.display_name(entry),
			Color(0.8, 0.8, 0.8))
		_page.refresh_board())

# THE PACK, MOUNTED FOR THE LENGTH OF A DRAG. The page's `_notification` hands the
# two ends over — `NOTIFICATION_DRAG_BEGIN` reaches every Control in the tree the
# moment a drag starts anywhere in the viewport, which is the one signal that means
# "the player's hand is full", and it is a Godot virtual so it has to stay on the
# Node.
#
# Only for a piece off the FLOOR. Dragging inside the loot window or the drop
# modal already has a pack in front of it, and a second one arriving beside the
# board would be the page answering a question nobody asked.
func mount_drag_pack() -> void:
	unmount_drag_pack()
	if GameLoop2.run_over:
		return
	drag_pack = DragPackPanel.build(take_floor_loot, bin_floor_loot)
	drag_pack.top_level = true
	_page.add_child(drag_pack)
	place_drag_pack()

func unmount_drag_pack() -> void:
	if drag_pack != null and is_instance_valid(drag_pack):
		drag_pack.queue_free()
	drag_pack = null

# TO THE LEFT OF THE BOARD, vertically centred on it. The piece is on the board
# and the pack is where it is going, so the drag runs right-to-left across the
# page and the panel sits at the end of that run rather than on top of where it
# started — covering the square the piece came off, and the squares around it,
# which is where a drag has to be able to end harmlessly.
#
# Placed once: the panel lives for the length of one drag, and the board does not
# move during one. Clamped to the screen so a page that has been squeezed puts it
# somewhere reachable rather than off an edge, and held below the header the way
# every other floating surface is.
func place_drag_pack() -> void:
	if drag_pack == null or not is_instance_valid(drag_pack):
		return
	var anchor: Control = _page.drag_pack_anchor()
	if anchor == null or not is_instance_valid(anchor):
		return
	drag_pack.set_anchors_preset(Control.PRESET_TOP_LEFT)
	drag_pack.size = drag_pack.get_combined_minimum_size()
	var on: Rect2 = anchor.get_global_rect()
	var size: Vector2 = drag_pack.size
	var screen: Vector2 = _page.get_viewport_rect().size
	var x: float = clampf(on.position.x - size.x - DragPackPanel.BOARD_GAP,
		4.0, maxf(4.0, screen.x - size.x - 4.0))
	var y: float = clampf(on.position.y + (on.size.y - size.y) * 0.5,
		ModalScaffold.reserved_top + 4.0, maxf(ModalScaffold.reserved_top + 4.0,
			screen.y - size.y - 4.0))
	drag_pack.global_position = Vector2(x, y)

# One floor square's payload as the loot entry the modals deal in. The loop stores
# the entry whole (it is scene-free and JSON-safe already), so this is only the
# unwrapping — and the guard for a save written when the floor still held relics.
func floor_loot(held: Dictionary) -> Dictionary:
	var entry = held.get("loot")
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}

# Everything still lying on the board when a game is reported goes onto the haul
# screen (§8.2/§18): the floor belongs to the game being played, and what the
# player did not stop to pick up is still theirs to answer for once.
#
# ONE TABLE, not one question per square. Three bodies leaving three pieces is a
# handful of loot, and LootDropModal has always taken a list — asking about them
# one modal at a time would put the ninth-slot decision to the player three times
# over with a different third of the answer each time.
#
# Swept whatever the report said. The loot was earned by the KILL, which already
# happened; only the relic chest is a reward for beating the game (claim_chests).
func sweep_floor() -> void:
	var swept: Array = []
	for held in GameLoop2.sweep_drops():
		var entry: Dictionary = floor_loot(held)
		if not entry.is_empty():
			swept.append(entry)
	if not swept.is_empty():
		queue.append({"loot": swept})

# THE RELICS THE EVENING EARNED (§8.2), spent and queued for the haul screen.
#
# A game beaten is worth one chest point on its own — a Small chest for a win with
# nothing standing on the board — and every non-boss body defeated since the last
# report adds its own difficulty on top: Low 1, Medium 2, High 3, Insane 4. The
# total is spent on the SAME ladder every scaling payout in the game walks
# (`Data.chest_reward_sizes`): the chest grows Small → Medium → Large → Huge, and
# past Huge it splits into a second chest rather than running off the end. Three
# High kills on a game you beat is 10 points — two Huge chests and a Medium.
#
# Which is the whole reason the relics left the floor. Paid a body at a time they
# were N Small chests, each worth less than the last and each its own question;
# paid at the report they are one growing reward that describes the evening.
#
# NOTHING FOR A GAME YOU DIDN'T BEAT. The loot the bodies dropped is already on
# the floor and stays yours (it was earned by the kill) — the chest is what
# beating the game buys, and GameLoop2.claim_chests is where that gate lives.
# A BOSS chest is the exception it always was: it is paid whether or not the game
# went your way, rolled from the boss pool, and kept as a chest OF ITS OWN beside
# the kill chest rather than folded into its points — There's Options buys size on
# that chest, not on this one.
#
# Queued rather than granted through `GameState.grant_chests`: a grant fires
# `chest_granted`, which opens a RewardScreen on the next idle frame — over the
# top of a board still playing the resolve back. The queue is the path that waits
# (see pump), and it is where a defeated body's chest always went.
func queue_report_chests(beaten: bool) -> void:
	if GameLoop2.run_over:
		# The run ended on this report; the win/lose screen owns the page now, and
		# the pool goes with the run rather than being carried into a screen that
		# will never ask about it.
		GameLoop2.claim_chests(false)
		return
	var granted: Array = []
	for chest in GameLoop2.claim_chests(beaten):
		var from_boss: bool = bool((chest as Dictionary).get("boss", false))
		for size in Data.chest_reward_sizes(int((chest as Dictionary).get("points", 0))):
			var offer: Array = roll_chest(from_boss, int(Data.CHEST_SIZE_CHOICES[size]))
			if offer.is_empty():
				continue
			queue.append({"items": offer})
			granted.append(size)
	if granted.is_empty():
		return
	# ONE LINE for the lot (§8.2). A reward promised as one line has to arrive as
	# one line, so a win that paid a Huge and a Medium says so once rather than
	# toasting twice — the two are still two chests, separately rolled and
	# separately answered, on the screen itself.
	Notifications.notify("Gained %s!" % Data.chest_sizes_text(granted),
		Color(1.0, 0.85, 0.4))
	GameLog.add("Gained %s." % Data.chest_sizes_text(granted), Color(1.0, 0.85, 0.4))

# Roll the game's loot payout and queue the question (§4.3). Queued rather than
# granted so the nine-piece cap can be answered by the player: a full pack turns
# the payout into "spend something or leave this", and that is a decision the run
# should be making out loud.
func queue_loot_drop() -> void:
	if GameLoop2.run_over:
		return
	var entry: Dictionary = GameState.roll_loot_entry("loot")
	if entry.is_empty():
		return
	queue.append({"loot": entry})
	pump()

# A GRANT of loot, asked about rather than pushed into the pack (§4.3). Mom's Coin
# Purse pays four pills at once and Sacred Bark doubles what a grant pays;
# shovelled straight in, the surplus over the nine-piece cap used to vanish without
# a word. GameState.offer_loot rolls the pieces and calls here, and they arrive as
# ONE question with all of them on the table rather than as four modals in a row.
#
# Behind the same queue as everything else, so a game that paid its own piece AND
# fired a relic asks in the order they landed.
func on_loot_offered(entries: Array) -> void:
	if GameLoop2.run_over or entries.is_empty():
		return
	# ONTO THE HAUL SCREEN when one is up. A relic taken from a chest ON that
	# screen can pay loot the instant it is picked up, and the table it belongs on
	# is six inches to the right of the card that paid it — queueing it behind a
	# screen the player has not left yet would hide the payout until after the
	# decision that earned it.
	#
	# AND ONTO THE EVENT when one is open, for the same reason. An event that pays
	# loot — the Woman in Blue's shelf, `gain_potion 3` — used to queue a drop
	# modal, so buying three potions in a shop handed you a second window on top of
	# the shop you were standing in. The bottles belong where the decision was
	# made: they land on the event's own table (EventModal2.add_loot), which is the
	# same embedded drop screen the Potion Lab opens with. A hidden or closing
	# event refuses them and they fall through to the queue below.
	if _page.offer_loot_to_open_screen(entries):
		return
	queue.append({"loot": entries.duplicate(true)})
	pump()

# ---------------------------------------------------------------------------
# Asking, one at a time
# ---------------------------------------------------------------------------

# Ask about the next waiting drop, if nothing else is already asking. Several
# defeats in one report queue behind each other rather than stacking modals.
#
# Deferred, because a defeat lands in the MIDDLE of GameLoop2.beat_game: the run
# is still mid-resolve, the board hasn't repainted and the report step hasn't
# handed over yet. Opening on the next idle frame puts the question after all of
# that, over a screen that has finished moving.
func pump() -> void:
	if not _may_open():
		return
	# NOT WHILE A REPORT IS RESOLVING. Everything a report drops belongs to the
	# post-combat screen, which opens when the board has finished playing the
	# resolve back (_open_post_game) and takes the whole queue with it. Pumping
	# here is what used to put "do you want this relic" over the top of the strike
	# that had just taken eight Health off the player.
	#
	# A REPORT and A LOST RUN'S TURN (§3) both hold the page mid-resolve, and both
	# for the same reason: a board mid-playback is not a place to put a modal. The
	# turn has no post-combat screen behind it to hand the queue to, so _end_resolve
	# pumps it itself the moment the playback lands. An offer that arrives at any
	# OTHER moment — a relic firing on the overworld, a machine, an event's payout —
	# still asks for itself, on its own modal, immediately.
	if _page.drops_are_held():
		return
	open_next.call_deferred()

func open_next() -> void:
	if not _may_open():
		return
	var drop: Dictionary = queue[0]
	# A LOOT payout rides the same queue as the relics a body left (§4.3), because
	# they are the same question asked about different things and a game can hand
	# over both. It asks in its own modal — a scroll is not an ItemData and the
	# nine-piece cap is a sentence only this one has to say.
	if drop.has("loot"):
		# Spendable, always. There is no longer a condition under which loot cannot
		# be used (§4.3): the mid-report lock holds the pack still, and a piece whose
		# effect cannot land right now fizzles rather than being refused. The flag
		# stays on the call because this screen must not assume the rule — the day
		# something else CAN forbid a use, it comes in here.
		var loot_modal := LootDropModal.open(_page, drop["loot"], true)
		modal = loot_modal
		# `taken` is what ended up in the pack. THE SCREEN PLACES ITS OWN takes
		# (§4.3): with several offers, and uses and bins interleaved between them,
		# the slot the player chose is only meaningful at the instant they choose it.
		# So the page's job here is the log and the refresh, not the taking.
		loot_modal.answered.connect(func(taken: Array):
			modal = null
			queue.pop_front()
			note_taken(taken)
			pump())
		return
	var item_modal = ItemDropModal.open(_page, drop_items(drop))
	modal = item_modal
	item_modal.answered.connect(func(taken: bool, chosen: ItemData):
		modal = null
		if taken:
			collect_drop(drop, chosen)
		else:
			skip_drop(drop)
		# Whatever is behind it in the queue is the next question.
		pump())

# The three conditions `pump` and `open_next` share: nothing already asking,
# something to ask about, and a page that is still in a state to be asked on.
func _may_open() -> bool:
	if modal != null and is_instance_valid(modal):
		return false
	if queue.is_empty() or not _page.is_inside_tree():
		return false
	return not _page.drops_are_done()

# ---------------------------------------------------------------------------
# Rolling and taking
# ---------------------------------------------------------------------------

# Roll one drop item from the games-first reward pool, weighted by rarity the same
# way the RewardScreen chest roll is (§8) — minus the luck advantage, which is the
# chest's own bonus.
#
# A BOSS pays out of the boss pool instead, with no rarity roll at all: a boss
# relic is not a rung on the ladder, it is a thing only a boss drops, so "which
# rarity did the boss roll" is not a question with an answer (§7.1). Falls back to
# the ordinary roll if no boss relics are authored, because a boss that drops
# nothing would read as a bug rather than as a thin catalogue.
func roll_drop(from_boss: bool = false) -> ItemData:
	var rng: RandomNumberGenerator = _page.drop_rng()
	if from_boss:
		var boss_pool: Array = Data.boss_item2_pool()
		if not boss_pool.is_empty():
			return boss_pool[rng.randi_range(0, boss_pool.size() - 1)]
	var bucket: Array = Data.reward_item2_pool_of(Data.roll_item_rarity(rng))
	if bucket.is_empty():
		return null
	return bucket[rng.randi_range(0, bucket.size() - 1)]

# `count` DISTINCT items for one chest, each rolled by roll_drop. Distinct is a
# preference and not a rule, the same way the shop shelf treats it: two of the
# same relic side by side is not a choice, but a thin pool still owes a full
# chest, so the draw gives up after a few tries rather than shrinking the offer.
# Fewer than `count` only when the pool itself is empty.
func roll_chest(from_boss: bool, count: int) -> Array:
	var out: Array = []
	var tries: int = 0
	while out.size() < maxi(1, count) and tries < 40:
		tries += 1
		var item: ItemData = roll_drop(from_boss)
		if item == null:
			break
		if not out.has(item):
			out.append(item)
	return out

# The items one queued chest is offering. `items` is the canonical shape; the
# single-item `{item: …}` shorthand is still read so a save written before chests
# had a size — and the tests that hand-build a drop — keep working.
func drop_items(drop: Dictionary) -> Array:
	var items: Array = drop.get("items", [])
	if not items.is_empty():
		return items
	var one = drop.get("item")
	return [one] if one is ItemData else []

func collect_drop(drop: Dictionary, chosen: ItemData = null) -> void:
	if not queue.has(drop):
		return
	queue.erase(drop)
	var offered: Array = drop_items(drop)
	# Defaults to the first thing offered, so a caller that doesn't care which —
	# a test, a one-item chest — doesn't have to name it.
	collect_drop_item(chosen if chosen != null and offered.has(chosen)
		else (offered[0] if not offered.is_empty() else null))

# TAKING ONE RELIC, wherever the chest was asked about. The queue bookkeeping above
# belongs to the page's own modal; this is the half that touches the run, and the
# post-combat screen — which holds its chests itself, off the queue — calls it
# directly so a relic taken there is granted, logged and announced identically.
func collect_drop_item(item: ItemData) -> void:
	if item == null:
		return
	GameState.add_item(item)
	GameLog.add("Collected %s." % item.display_name, Color(0.7, 1.0, 0.7))
	Notifications.notify("Took %s." % item.display_name, UITheme.item_color(item))

# …and leaving them, on the same terms.
func skip_drop_items(items: Array) -> void:
	var names: Array = []
	for it in items:
		if it is ItemData:
			names.append(String((it as ItemData).display_name))
	if not names.is_empty():
		GameLog.add("Left %s behind." % ", ".join(names), Color(0.8, 0.8, 0.8))

# What the player kept off a payout, written down. The pieces are ALREADY in the
# pack — the drop screen places each one as it is resolved, because with several
# offers on the table and uses and bins between them, the slot a piece was dropped
# into stops meaning anything the moment the next one moves (§4.3). So this is the
# log and the redraw, and nothing else.
func note_taken(taken: Array) -> void:
	for entry in taken:
		if entry is Dictionary:
			GameLog.add("Collected %s." % LootSystem.display_name(entry),
				Color(0.7, 1.0, 0.7))
	if not taken.is_empty():
		_page._refresh_items()

func skip_drop(drop: Dictionary) -> void:
	if not queue.has(drop):
		return
	queue.erase(drop)
	skip_drop_items(drop_items(drop))

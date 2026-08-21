class_name PostCombatScreen
extends Control

# The screen a game ENDS on — everything the report just earned, in one place,
# with one way out (docs/games-first-redesign.md §4.3 / §8.2 / §14.4).
#
# Reporting a game used to fire six unrelated surfaces at the player, none of
# which knew about the others: one ItemDropModal per defeated enemy, then the
# LootDropModal, then the event, then the shop appearing under the board, then
# the boss notice, with the toasts running underneath all of it. Five popups in a
# row on a boss round, each re-centring on the same spot, each with its own
# Take/Leave, and nothing tying any of them to the game they came out of.
#
# Worse, the first two opened ON TOP OF THE RESOLVE ANIMATION. The drops are
# queued in the middle of `GameLoop2.beat_game` and pumped on the next idle frame,
# while `Overworld2._hold_for_resolve` is still playing the strike and the advance
# back — the one place the run's consequences are ever SHOWN — so the player
# answered "do you want this relic" over the top of the blow that took eight
# Health off them.
#
# So the haul is a screen, and it opens when the board has finished moving.
#
#   THE VERDICT   — the game, its cover, and which of the three reports this was:
#                   beaten, goal missed, or walked away.
#   THE FIGHT     — what it cost: damage taken and blocked, the bodies that fell,
#                   what is still following, the tries that expired, and the
#                   difficulty step if the board just grew. All of it comes out of
#                   `beat_game`'s result, which until now was thrown away as soon
#                   as the animation had played it.
#   THE SPOILS    — the relic chests down the left and the loot payout down the
#                   right, at the same time rather than one after another. Both
#                   are the real modals embedded (`ItemDropModal.embed` /
#                   `LootDropModal.embed`), so a chest and a pack behave here
#                   exactly as they do anywhere else — same cards, same drag, same
#                   bin, same "use it where you stand".
#   THE SHOP      — a hub's shelf, if this game was one of the ten (§14). It is
#                   mounted here and then HANDED BACK to the page on the way out
#                   (`release_shop`), because §14's decision that a shop blocks
#                   nothing and stays for the whole visit is still right; what was
#                   missing was it being seen at the moment you arrive.
#   THE WARNING   — the boss notice as a banner rather than a sixth popup, since
#                   a boss round is announced between two games and this screen is
#                   what is standing between them.
#
# And one button out. It is the EVENT when the node owes one — clicking it is what
# opens the event, so the player leaves this screen into the next thing rather
# than having the next thing dropped on them — and "travel on" when it doesn't.
#
# Built in code on its own CanvasLayer, BELOW the run's header bar (135) so Health
# and Gold stay readable over it, and below the loot use modal (130) so spending a
# piece from the pack still opens on top. Its page is inset under the bar the same
# way every other modal is (ModalScaffold.reserved_top).

# The player is done with the haul. The page resumes the chain from here: the
# event, then the shop, then the detour question.
signal finished

const LAYER := 128
const ACCENT := UITheme.ACCENT
# The frame's inset from the room it is allowed. Small, because this screen is
# the page for as long as it is up and the loot column alone wants 586 of the
# 1280 the canvas has.
const INSET_X := 24.0
const INSET_Y := 10.0
# The cover is a reminder, not a picture to look at — the player has been staring
# at this game all evening. Every row it gives back goes to the loot column, whose
# 3x3 and bin are the tightest thing on the page.
const COVER := Vector2(44, 58)
# The gutter between the two columns, and the width the right one is pinned to —
# the loot section's own, so the offer and the pack stay side by side (that drag
# is what the section is for).
const COLUMN_GAP := 14

# What the report was, as handed over by Overworld2.report. See `open`.
var _snap: Dictionary = {}
# The relic chests still to be asked about, in the order they fell. Drained one at
# a time into `_chest_slot`, exactly as the page's own queue used to drain into
# one modal after another.
var _chests: Array = []
# The loot pieces this report paid, all of them on the table at once.
var _loot: Array = []
# Whether an event is queued behind this screen, which is what the way out says.
var _event_pending: bool = false
# The hub whose shelf belongs on this screen, and the panel once it is mounted.
var _shop_id: StringName = &""
var _shop: ShopPanel2 = null
# The boss round this screen is warning about: the tier it steps to and the
# bosses about to be on the table. Empty when the next round is an ordinary one.
var _boss_tier: String = ""
var _bosses: Array = []
# The overworld under this screen — the loot section's use modal, info card and
# pack-strip refresh all still belong to it.
var _page: Node = null

var _layer: CanvasLayer = null
var _done: bool = false
var _chest_slot: VBoxContainer = null
var _chest_note: Label = null
var _loot_slot: VBoxContainer = null
var _shop_slot: VBoxContainer = null
var _boss_slot: VBoxContainer = null
var _exit_btn: Button = null
# The two embedded sections, held so the way out can answer them for the player
# rather than binning what is still on the table without a word.
var _chest: ItemDropModal = null
var _loot_section: LootDropModal = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


# Mount over `page` (the overworld) and show it the haul.
#
# `snapshot` is what the report was, taken in Overworld2.report before anything
# could move on from it:
#   game            GameData     — what was played
#   beaten/escaped  bool         — which of the three reports this was
#   amulet          bool         — whether that game was the Amulet
#   res             Dictionary   — GameLoop2.beat_game's result
#   tier_before     int          — the difficulty tier before this game counted
#   board_before    Vector2i     — and the board size, so a step can be named
#
# `drops` is the page's drop queue: entries carrying "items" (a chest) or "loot"
# (a payout), in the order they landed.
static func open(page: Node, snapshot: Dictionary, drops: Array,
		event_pending: bool, shop_id: StringName = &"",
		boss_tier: String = "", bosses: Array = []) -> PostCombatScreen:
	var screen := PostCombatScreen.new()
	screen._page = page
	screen._snap = snapshot.duplicate(true)
	screen._event_pending = event_pending
	screen._shop_id = shop_id
	screen._boss_tier = boss_tier
	screen._bosses = bosses.duplicate()
	# The queue is SORTED into the screen's two halves rather than replayed in
	# order. It arrived as a queue because it was drained one modal at a time; the
	# whole point of this screen is that the relics and the loot are one haul, so
	# every payout goes on the table together and the chests stack up on their own
	# side.
	for drop in drops:
		if not (drop is Dictionary):
			continue
		if drop.has("loot"):
			var loot = drop["loot"]
			for entry in (loot if loot is Array else [loot]):
				if entry is Dictionary and not (entry as Dictionary).is_empty():
					screen._loot.append((entry as Dictionary).duplicate(true))
		else:
			var items: Array = drop.get("items", [])
			if items.is_empty() and drop.get("item") is ItemData:
				items = [drop.get("item")]
			if not items.is_empty():
				screen._chests.append(items.duplicate())
	screen._layer = CanvasLayer.new()
	screen._layer.layer = LAYER
	screen._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	page.add_child(screen._layer)
	screen._layer.add_child(screen)
	return screen


func _ready() -> void:
	theme = UITheme.shared()
	_build()


# ---------------------------------------------------------------------------
# What the screen says — every line of it readable without a pixel on screen, so
# a headless test asserts what the report earned rather than how it was drawn.
# ---------------------------------------------------------------------------

func game() -> GameData:
	return _snap.get("game") as GameData

# Which of the three reports this was. Not a win/lose: you can beat a game and
# clear nothing, or clear three goals in a game you never finished, and walking
# away is its own answer (Overworld2.report).
func verdict() -> String:
	if bool(_snap.get("escaped", false)):
		return "escaped"
	return "beaten" if bool(_snap.get("beaten", false)) else "missed"

func headline() -> String:
	match verdict():
		"escaped":
			return "YOU WALKED AWAY"
		"beaten":
			return "GAME BEATEN"
		_:
			return "GAME OVER"

func subtitle() -> String:
	var g: GameData = game()
	var name: String = g.display_name if g != null else "that game"
	match verdict():
		"escaped":
			return "You left %s unfinished. The evening still counted." % name
		"beaten":
			if bool(_snap.get("amulet", false)):
				return "%s — the Amulet game — is done." % name
			return "You saw %s through." % name
		_:
			return "%s is behind you, goal unmet." % name

# The fight in numbers, as {label: value} in the order the screen prints them.
func tally() -> Array:
	var res: Dictionary = _snap.get("res", {})
	var out: Array = []
	var damage: int = int(res.get("damage_taken", 0))
	var blocked: int = int(res.get("blocked", 0))
	out.append(["Damage taken", str(damage) if blocked <= 0
		else "%d  (%d blocked)" % [damage, blocked],
		UITheme.DANGER if damage > 0 else UITheme.TEXT_DIM])
	out.append(["Health", "%d / %d" % [GameState.hp, GameState.max_hp],
		UITheme.SUCCESS if GameState.hp > GameState.max_hp / 2 else UITheme.DANGER])
	var felled: int = (res.get("defeats", []) as Array).size()
	out.append(["Goals cleared", str(felled),
		UITheme.SUCCESS if felled > 0 else UITheme.TEXT_DIM])
	var following: int = int(res.get("stack_size", 0))
	out.append(["Still following", str(following),
		UITheme.DANGER if following > 0 else UITheme.TEXT_DIM])
	# The tries that went unused. Barricade banks them instead, and a relic that is
	# about the tries you didn't need should say so where they are counted.
	var banked: int = int(res.get("shields_banked", 0))
	if banked > 0:
		out.append(["Tries banked", str(banked), UITheme.GOLD])
	else:
		var expired: int = int(res.get("shields_expired", 0))
		if expired > 0:
			out.append(["Tries left over", str(expired), UITheme.TEXT_DIM])
	out.append(["Difficulty", RunDifficulty.tier_name(_tier_now()), UITheme.TEXT])
	return out

# The difficulty step, in the words the screen prints, or "" when the run stayed
# on the tier it was already on. Both halves of it, because they pull in opposite
# directions and a player who only notices one will misread the other: the
# enemies get heavier, and the ground you have to lose gets deeper (§7.3).
func step_line() -> String:
	var before: int = int(_snap.get("tier_before", _tier_now()))
	var now: int = _tier_now()
	if now == before:
		return ""
	var line: String = "Difficulty up — %s." % RunDifficulty.tier_name(now)
	var board_before: Vector2i = _snap.get("board_before", Vector2i.ZERO)
	var board_now := Vector2i(GameLoop2.grid_cols(), GameLoop2.grid_rows())
	if board_now != board_before and board_now.x > 0:
		line += " The battlefield grows to %d×%d." % [board_now.x, board_now.y]
	return line

func _tier_now() -> int:
	return RunDifficulty.tier_for(GameState.games_played)

# The chest currently being asked about, and the payout on the table — the two
# embedded sections, named so a headless test can answer them the way a player
# does (`take` / `leave`) rather than reaching into the layout for a button.
# Either is null once it has been answered, and `chest` is null when a report
# felled nothing.
func chest() -> ItemDropModal:
	return _chest if _chest != null and is_instance_valid(_chest) else null

func payout() -> LootDropModal:
	return _loot_section if _loot_section != null and is_instance_valid(_loot_section) else null

# How many chests are still queued behind the one on screen.
func chests_waiting() -> int:
	return _chests.size()

# What the way out says. The EVENT when the node owes one, because clicking it is
# what opens the event — the player leaves this screen into the next thing rather
# than having the next thing dropped on top of them.
func exit_text() -> String:
	var left: int = _unanswered()
	var base: String = "⚑  See what's here" if _event_pending else "→  Travel on"
	if left <= 0:
		return base
	return "%s   (leaving %d behind)" % [base, left]

# How much is still on the table. The way out bins it, so the button says so
# first: a Legendary left on the ground should be a decision and not a side
# effect of pressing Continue.
func _unanswered() -> int:
	var left: int = 0
	if _loot_section != null and is_instance_valid(_loot_section):
		left += _loot_section.remaining()
	if _chest != null and is_instance_valid(_chest):
		left += 1
	left += _chests.size()
	return left


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------

func _build() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(UITheme.BG_DEEP, 0.92)
	add_child(scrim)

	# Inset under the run's header bar, which is opaque and drawn above this layer
	# — the same rule every other modal on this page follows.
	var top: float = ModalScaffold.free_rect(self).position.y
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = INSET_X
	frame.offset_right = -INSET_X
	frame.offset_top = top + INSET_Y
	frame.offset_bottom = -INSET_Y
	frame.add_theme_stylebox_override("panel", UITheme.flat(UITheme.BG, 12, 14, 2, _accent()))
	add_child(frame)

	var col := VBoxContainer.new()
	# Tight, deliberately: the loot column's 3x3 and its bin are the least
	# compressible thing on this page, and every gap spent up here is a row they
	# have to find by scrolling.
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)
	col.add_child(_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", COLUMN_GAP)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	# THE FRAME FIRST, THE SECTIONS SECOND. Every section is a real modal building
	# itself into one of these containers, and a modal built into a container that
	# is not yet in the tree measures a viewport it cannot reach and grabs focus on
	# a node that is nowhere — Godot answers both with
	# `Condition "!is_inside_tree()" is true`. So the columns are parented empty and
	# filled afterwards, when there is a screen under them to measure against.
	body.add_child(_left_column())
	body.add_child(_right_column())
	col.add_child(_footer())
	_fill_sections()

func _accent() -> Color:
	match verdict():
		"beaten":
			return UITheme.SUCCESS
		"escaped":
			return UITheme.TEXT_DIM
		_:
			return UITheme.ACCENT

func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var g: GameData = game()
	if g != null and g.cover_image != null:
		var art := TextureRect.new()
		art.texture = g.cover_image
		art.custom_minimum_size = COVER
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(art)

	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	words.add_child(_line(headline(), _accent(), 22))
	words.add_child(_line(subtitle(), UITheme.TEXT, 13, true))
	var step: String = step_line()
	if step != "":
		words.add_child(_line(step, UITheme.GOLD, 12, true))
	return row

# The left column: the numbers, the chests, the warning and the shelf, in the
# order they answer "what just happened". It scrolls, because a boss round at a
# hub with a Huge chest is more than a 720p canvas holds — the loot column beside
# it does not, since the drag between its two halves is the one thing on this
# screen that a scrollbar would get in the way of.
func _left_column() -> Control:
	var scroller := ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(col)

	col.add_child(_tally_panel())

	_chest_slot = VBoxContainer.new()
	_chest_slot.add_theme_constant_override("separation", 6)
	_chest_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_chest_slot)
	_chest_note = _line("", UITheme.TEXT_FAINT, 11)
	_chest_note.visible = false
	col.add_child(_chest_note)

	_boss_slot = VBoxContainer.new()
	_boss_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_boss_slot)

	_shop_slot = VBoxContainer.new()
	_shop_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_shop_slot)
	return scroller

# Everything that goes INSIDE the columns, once the columns are on the screen.
# Kept apart from building them for the reason spelled out in _build: a section is
# a modal, and a modal cannot measure or focus itself out of the tree.
func _fill_sections() -> void:
	if not _bosses.is_empty() or _boss_tier != "":
		BossNoticeModal.embed(self, _boss_slot, _boss_tier, _bosses)
	_mount_shop()
	_fill_payout()
	_next_chest()
	_refresh_exit()

func _tally_panel() -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 12, 1))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 22)
	flow.add_theme_constant_override("v_separation", 8)
	wrap.add_child(flow)
	for entry in tally():
		flow.add_child(_tile(String(entry[0]), String(entry[1]), entry[2]))
	return wrap

func _tile(key: String, value: String, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(_line(key.to_upper(), UITheme.TEXT_FAINT, 10))
	box.add_child(_line(value, color, 16))
	return box

# The right column: the payout, at the width its own offer-and-pack row needs.
# Empty when the game paid nothing (an escape earns none), and then it says so
# rather than leaving a hole where the loot would have been.
func _right_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(LootDropModal.EMBED_W, 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_loot_slot = col
	return col

# The payout, once its column is on the screen (see _fill_sections). Loot can
# always be SPENT from here: this screen only opens once the report has resolved
# and the run is back on its offering, which is the same condition the pack strip
# and the loot window spend by.
func _fill_payout() -> void:
	if _loot_slot == null or not is_instance_valid(_loot_slot):
		return
	if _loot.is_empty():
		_loot_slot.add_child(_empty_note("Nothing dropped for your pack."))
		return
	_loot_section = LootDropModal.embed(_page, self, _loot_slot, _loot, true)
	_loot_section.answered.connect(func(taken: Array):
		_loot_section = null
		_on_loot_answered(taken)
		_refresh_exit()
		# DEFERRED, because the section frees its own panel with `queue_free` — the
		# column still holds it on this frame, so a check for "is this column empty
		# now" run here answers no and the note never appears.
		_loot_cleared.call_deferred())

# The payout is off the table: say so where it was, rather than leaving a hole in
# the column the rest of the screen is still laid out around.
func _loot_cleared() -> void:
	if _done or _loot_slot == null or not is_instance_valid(_loot_slot):
		return
	for c in _loot_slot.get_children():
		if not c.is_queued_for_deletion():
			return
	_loot_slot.add_child(_empty_note("The table is clear."))

func _empty_note(text: String) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.BORDER, 10, 16, 1))
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var l := _line(text, UITheme.TEXT_FAINT, 13, true)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(l)
	return wrap

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var hint := _line(
		"Take what you want, spend what you like — then see what's waiting."
		if _event_pending else "Take what you want, then pick where the run goes next.",
		UITheme.TEXT_FAINT, 12)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	_exit_btn = UITheme.confirm_button(exit_text(), Vector2(260, 42), 16)
	_exit_btn.pressed.connect(dismiss)
	row.add_child(_exit_btn)
	# Deferred, because this row is built before it is parented and `grab_focus` on
	# a Control outside the tree fails outright — and GUARDED for the same reason
	# at the other end: a headless test opens this screen and leaves it inside one
	# frame, so by the time the deferred call lands the button can be gone.
	_focus_exit.call_deferred()
	return row

func _focus_exit() -> void:
	if _exit_btn != null and is_instance_valid(_exit_btn) and _exit_btn.is_inside_tree():
		_exit_btn.grab_focus()

func _refresh_exit() -> void:
	if _exit_btn != null and is_instance_valid(_exit_btn):
		_exit_btn.text = exit_text()


# ---------------------------------------------------------------------------
# The chests, one at a time
# ---------------------------------------------------------------------------

# Ask about the next chest, if any. They queue rather than stack for the same
# reason they always did — a chest is "which one", and two of those side by side
# is two questions wearing one answer — but the queue now drains inside a screen
# the player can see the rest of the haul on.
func _next_chest() -> void:
	if _done or _chest_slot == null or not is_instance_valid(_chest_slot):
		return
	if _chests.is_empty():
		if _chest_note != null and is_instance_valid(_chest_note):
			_chest_note.visible = false
		_refresh_exit()
		return
	var items: Array = _chests.pop_front()
	_chest = ItemDropModal.embed(self, _chest_slot, items)
	_chest.answered.connect(func(taken: bool, item: ItemData):
		_chest = null
		if taken and item != null:
			_collect(item)
		else:
			_leave(items)
		_next_chest())
	_note_chests_behind()
	_refresh_exit()

func _note_chests_behind() -> void:
	if _chest_note == null or not is_instance_valid(_chest_note):
		return
	var behind: int = _chests.size()
	_chest_note.visible = behind > 0
	if behind > 0:
		_chest_note.text = "…and %d more chest%s behind this one." % [
			behind, "" if behind == 1 else "s"]

# Taking and leaving go back through the page, which owns the inventory, the log
# and the toast — this screen decides nothing about a relic beyond which one was
# picked.
func _collect(item: ItemData) -> void:
	if _page != null and _page.has_method("collect_drop_item"):
		_page.collect_drop_item(item)

func _leave(items: Array) -> void:
	if _page != null and _page.has_method("skip_drop_items"):
		_page.skip_drop_items(items)

func _on_loot_answered(taken: Array) -> void:
	if _page != null and _page.has_method("note_loot_taken"):
		_page.note_loot_taken(taken)


# ---------------------------------------------------------------------------
# The shop
# ---------------------------------------------------------------------------

func _mount_shop() -> void:
	if _shop_id == &"" or _shop_slot == null:
		return
	_shop = ShopPanel2.mount(_shop_slot, _shop_id)
	if _shop == null:
		return
	# The panel is handed back to the page on the way out (release_shop), so its
	# `finished` is the page's to wire up — not this screen's, which is about to
	# stop existing.
	_shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL

# Give the shelf back to the page, unparented and unfinished. §14's decision that
# a shop blocks nothing and stays for the whole visit still holds — this screen
# only borrowed it for the moment of arrival, which is the one moment it was
# never seen. Returns null when this game had no shop.
func release_shop() -> ShopPanel2:
	var panel: ShopPanel2 = _shop
	_shop = null
	if panel == null or not is_instance_valid(panel):
		return null
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	return panel


# ---------------------------------------------------------------------------
# Leaving
# ---------------------------------------------------------------------------

# The way out. Anything still on the table is ANSWERED before the screen goes,
# through the sections' own "leave it" — so a piece the player never got round to
# is discarded by the same path that logs it, rather than vanishing with the node
# that was holding it.
#
# Public so a headless test can leave without a click.
func dismiss() -> void:
	if _done:
		return
	_done = true
	if _loot_section != null and is_instance_valid(_loot_section):
		_loot_section.leave()
		_loot_section = null
	if _chest != null and is_instance_valid(_chest):
		_chest.leave()
		_chest = null
	for items in _chests:
		_leave(items)
	_chests.clear()
	finished.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


# Take the screen down without answering anything and without resuming the chain
# behind it — what starting a new run does to whatever the last one left standing.
# `dismiss` is the player's way out; this is the page pulling the screen off the
# wall, and it must not fire `finished` or the reset would find itself opening the
# dead run's event.
func abandon() -> void:
	if _done:
		return
	_done = true
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _line(text: String, color: Color, size: int, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

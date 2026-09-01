class_name PostCombatScreen
extends Control

# The screen a game ENDS on — everything the report just earned, in one place,
# with one way out (docs/games-first-redesign.md §4.3 / §8.2 / §14.4).
#
# Reporting a game used to fire six unrelated surfaces at the player, none of
# which knew about the others: one ItemDropModal per defeated enemy (the drops
# were relic chests then, one per body), then the
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
#   THE SPOILS    — the relic chests down the left (what BEATING the game paid,
#                   sized by the bodies that fell to it, §8.2) and the loot payout
#                   down the right — the pieces the bodies themselves dropped on
#                   the board, plus the game's own — at the same time rather than
#                   one after another. Both
#                   are the real modals embedded (`ItemDropModal.embed` /
#                   `LootDropModal.embed`), so a chest and a pack behave here
#                   exactly as they do anywhere else — same cards, same drag, same
#                   bin, same "use it where you stand".
#   THE WARNING   — the boss notice as a banner rather than a sixth popup, since
#                   a boss round is announced between two games and this screen is
#                   what is standing between them.
#
# THE SHOP IS NOT ONE OF ITS SECTIONS, and briefly was: a hub's shelf was mounted
# into the left column and handed back to the page on the way out. It is off again
# — see `shop_id` for why the button naming it is the reason.
#
# And one button out, which NAMES WHERE IT GOES: "Go to Event" when the node owes
# one (clicking it is what opens the event, so the player leaves this screen into
# the next thing rather than having the next thing dropped on them), "Go to Shop"
# at a hub that owes no event, and "Travel on" when it owes neither.
#
# Built in code on its own CanvasLayer, BELOW the run's header bar (135) so Health
# and Gold stay readable over it, and below the loot use modal (130) so spending a
# piece from the pack still opens on top. Its page is inset under the bar the same
# way every other modal is (ModalScaffold.reserved_top).

# The player is done with the haul. The page resumes the chain from here: the
# event, then the shop, then the detour question.
signal finished

const LAYER := 128
# Where a card raised BY one of this screen's sections goes: above the screen and
# still below the run's header bar (135). Nothing on the screen needs it since the
# shelf came off, but a section that raises a card of its own will, and 131 is the
# only value between this screen and the bar.
const CARD_LAYER := 131
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
# How wide the verdict's words are allowed to be before they wrap. It is what
# keeps the ★ Rate button beside the game's name instead of out at the frame's
# edge — see _header.
const TITLE_W := 520
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
# The hub this screen's exit leads to, when the game was one of the ten. Only ever
# read for the button's wording — the shelf itself is the page's (see `shop_id`).
var _shop_id: StringName = &""
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
var _chest_head: Label = null
# The one-row sum under that heading: why the chest is the size it is.
var _chest_why: Control = null
var _loot_slot: VBoxContainer = null
var _boss_slot: VBoxContainer = null
var _exit_btn: Button = null
# The chest sections on screen, one per chest the report dropped — ALL of them at
# once (see _build_chests), held so the way out can answer whatever is left rather
# than binning it without a word.
var _chest_sections: Array = []
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
	# The Temporary Shields nothing hit. They expire here (§3.2) — Barricade banks
	# them as the pool that stays instead, and a relic that is about the cover you
	# didn't need should say so where it is counted.
	var banked: int = int(res.get("shields_banked", 0))
	if banked > 0:
		out.append(["Banked as %ss" % GameState.SHIELD_NAME, str(banked), UITheme.GOLD])
	else:
		var expired: int = int(res.get("shields_expired", 0))
		if expired > 0:
			out.append(["%ss left over" % GameState.TEMP_SHIELD_NAME, str(expired),
				UITheme.TEXT_DIM])
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

# ---------------------------------------------------------------------------
# Why the chest is the size it is
# ---------------------------------------------------------------------------
#
# THE CHEST USED TO ARRIVE AS AN ASSERTION. A Large one turned up over the words
# "what the evening earned" and nothing anywhere said why it was Large rather than
# Small — so the one reward that scales with how hard you fought was also the one
# the player had no way to read as a consequence of their fighting. The rule
# (§8.2) is simple enough to show: beating the game is worth a point, every body
# you cleared is worth its own difficulty (Low 1 … Insane 4), and the total is
# spent up the size ladder.
#
# So the screen shows the SUM, with the faces in it: [win +1] + [face +2] +
# [face +1] = Large Chest. Rows, not prose — a player who has just fought those
# bodies recognises them faster than any sentence about them.
#
# `chest_sources` comes off the snapshot, read before the claim emptied the pool
# (Overworld2.report). Returns [] when this report earned no kill chest — an
# escape, a missed goal — and the section is not drawn at all.
func chest_terms() -> Array:
	if verdict() != "beaten":
		return []
	var out: Array = [{"label": "Beat the game", "points": 1, "enemy": null}]
	for row in _snap.get("chest_sources", []):
		if not (row is Dictionary):
			continue
		var enemy: GoalEnemyData = (row as Dictionary).get("enemy")
		if enemy == null:
			continue
		out.append({"label": enemy.display_name,
			"points": int((row as Dictionary).get("points", 0)), "enemy": enemy})
	return out

# The point total those terms come to, and the chest it buys — the right-hand side
# of the sum. Read off Data.chest_reward_sizes, the same function that actually
# spent the points, so the explanation and the payout can never disagree.
func chest_total() -> int:
	var sum: int = 0
	for term in chest_terms():
		sum += int(term.get("points", 0))
	return sum

func chest_result_text() -> String:
	var total: int = chest_total()
	return Data.chest_reward_text(total) if total > 0 else ""

# The whole line in words, for a headless test and for anyone who would rather
# read it than count the faces: "Beat the game +1, Leprechaun +2 = 1 Large Chest".
func chest_reason() -> String:
	var terms: Array = chest_terms()
	if terms.is_empty():
		return ""
	var parts: Array = []
	for term in terms:
		parts.append("%s +%d" % [String(term.get("label", "")), int(term.get("points", 0))])
	return "%s = %s" % [", ".join(PackedStringArray(parts)), chest_result_text()]

# The chest currently being asked about, and the payout on the table — the two
# embedded sections, named so a headless test can answer them the way a player
# does (`take` / `leave`) rather than reaching into the layout for a button.
# Either is null once it has been answered, and `chest` is null when a report
# felled nothing.
func chest() -> ItemDropModal:
	for c in _live_chests():
		return c
	return null

# Every chest still waiting to be answered, oldest first.
func _live_chests() -> Array:
	var out: Array = []
	for c in _chest_sections:
		if c != null and is_instance_valid(c) and not c.answered_already():
			out.append(c)
	return out

func payout() -> LootDropModal:
	return _loot_section if _loot_section != null and is_instance_valid(_loot_section) else null

# How many chests are still unanswered besides the one `chest` hands back. They
# are all ON the screen now rather than queued behind it — this is what is left to
# decide, not what is left to see.
func chests_waiting() -> int:
	return maxi(0, _live_chests().size() - 1)

# What the way out says. The EVENT when the node owes one, because clicking it is
# what opens the event — the player leaves this screen into the next thing rather
# than having the next thing dropped on top of them.
# IT NAMES THE PLACE IT GOES. It used to say "See what's here" for an event and
# "Travel on" for nothing, and the first of those describes a feeling rather than
# a destination — the player could not tell from it whether they were about to be
# handed an event, dropped at a shop, or simply moved on.
#
# THE EVENT WINS WHEN BOTH ARE OWED, because the event is what happens next: the
# page resumes the chain event-first (`finished`), and the shelf is still under
# the board on the far side of it. A button promising the shop would be naming the
# thing after the thing that actually opens.
func exit_text() -> String:
	var left: int = _unanswered()
	var base: String = "→  Travel on"
	if _event_pending:
		base = "⚑  Go to Event"
	elif _shop_id != &"":
		base = "🛒  Go to Shop"
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
	left += _live_chests().size()
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
	# SHRINK, not expand, so the rate button below sits BESIDE the name rather than
	# being shoved to the far end of a 1200px row by a title block that grew to
	# fill it. The spacer after the button is what takes the slack instead.
	#
	# WIDTH PINNED, because two of the three lines autowrap: with nothing to wrap
	# AGAINST, a shrink-sized block reports the whole sentence on one line and
	# pushes the button back out to the edge this is here to bring it in from.
	# The subtitle and the difficulty step wrap at TITLE_W instead.
	words.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.custom_minimum_size = Vector2(TITLE_W, 0)
	row.add_child(words)
	words.add_child(_line(headline(), _accent(), 22))
	words.add_child(_wrapped(subtitle(), UITheme.TEXT, 13))
	var step: String = step_line()
	if step != "":
		words.add_child(_wrapped(step, UITheme.GOLD, 12))

	# ★ RATE, BESIDE THE COVER AND THE NAME, because this is the moment there is
	# anything to say. It used to live on the play panel's checklist — offered
	# while the game was still in front of you, which is the one time the player
	# has not finished forming the opinion the button is asking for. Here the game
	# is over, its cover is right there, and the score is the last thing the
	# evening produces. (The select screen keeps its own "★ Rate <game>" for a
	# game reported earlier; that one is about a different moment and stays.)
	if g != null:
		row.add_child(_rate_button(g))
	# …and the slack goes here, past the button, so the header still spans the
	# frame without pushing the score away from the game it is about.
	var tail := Control.new()
	tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tail)
	return row

# The rating entry point for this screen. It does NOT go through
# Overworld2._prompt_rating: that one opens the tier-list board on submit, which
# is the right follow-through from the select screen and the wrong one here — it
# would drop a full-screen board over a haul the player has not finished taking.
# So the score is saved and the screen stays put.
#
# Parented to THIS screen rather than to the page, because the page's tree is
# under this CanvasLayer (128) and a modal added there opens behind the very
# screen whose button asked for it.
func _rate_button(g: GameData) -> Button:
	var btn := Button.new()
	var existing: Dictionary = TierList.get_rating(g.id)
	btn.text = "★  Rated %d/10" % int(existing.get("score", 0)) \
		if not existing.is_empty() else "★  Rate this game"
	btn.tooltip_text = "Score %s out of 10 — optional, and you can change it later." \
		% g.display_name
	btn.custom_minimum_size = Vector2(150, 34)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_color_override("font_color", UITheme.GOLD)
	btn.pressed.connect(func(): _open_rating(g, btn))
	return btn

func _open_rating(g: GameData, btn: Button) -> void:
	var modal := RateGameModal.new()
	modal.setup(g.id, g)
	modal.submitted.connect(func(score: int, notes: String):
		TierList.set_rating(g.id, score, notes)
		modal.queue_free()
		# The button carries the score back, so pressing it again reads as an edit
		# rather than as a rating that did not take.
		if btn != null and is_instance_valid(btn):
			btn.text = "★  Rated %d/10" % score)
	modal.dismissed.connect(func(): modal.queue_free())
	add_child(modal)

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

	# THE LEVEL-UP, WHEN THE REPORT TOOK ONE. Above the chests, because its chest
	# is one of the ones below and this is the line that says where that one came
	# from. See _level_up_panel.
	var lvl: Control = _level_up_panel()
	if lvl != null:
		col.add_child(lvl)

	# One heading over all the chests rather than one apiece: three bodies each
	# leaving a single relic is three panels that would otherwise each announce "it
	# dropped something" over the picture that already says it.
	_chest_head = _line("✦  What the evening earned", UITheme.TEXT_DIM, 12)
	_chest_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chest_head.visible = false
	col.add_child(_chest_head)

	# …and directly under it, the sum that produced the chest below (chest_terms).
	# Hidden and shown with the heading, since it is describing the same thing.
	_chest_why = _chest_sum_row()
	if _chest_why != null:
		_chest_why.visible = false
		col.add_child(_chest_why)

	_chest_slot = VBoxContainer.new()
	_chest_slot.add_theme_constant_override("separation", 6)
	_chest_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_chest_slot)

	_boss_slot = VBoxContainer.new()
	_boss_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_boss_slot)

	return scroller

# Everything that goes INSIDE the columns, once the columns are on the screen.
# Kept apart from building them for the reason spelled out in _build: a section is
# a modal, and a modal cannot measure or focus itself out of the tree.
func _fill_sections() -> void:
	if not _bosses.is_empty() or _boss_tier != "":
		BossNoticeModal.embed(self, _boss_slot, _boss_tier, _bosses)
	_fill_payout()
	_build_chests()
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
	# THE WAY OUT COUNTS WHAT IS STILL ON THE GROUND, so it has to hear about every
	# piece the player takes, leaves, spends or bins — not just about the section
	# finishing. `answered` fires once, on the way out, which is after the button
	# has stopped mattering; `changed` is the live one.
	_loot_section.changed.connect(_refresh_exit)
	# The section stays put once its table is clear (it says so itself) and reports
	# only when the screen goes, so this fires on the way out and is the log of what
	# the player ended up keeping.
	_loot_section.answered.connect(func(taken: Array):
		_loot_section = null
		_on_loot_answered(taken)
		_refresh_exit())

# Loot granted while this screen is up — a relic taken from one of its own chests
# paying out (§4.3). It goes on the table the player is looking at rather than
# into the page's queue, which would not be drained until they had left.
# Returns false when there is no payout column to put it on, so the page can fall
# back to its own queue.
func add_loot(entries: Array) -> bool:
	if _done or entries.is_empty():
		return false
	if _loot_section != null and is_instance_valid(_loot_section):
		_loot_section.add_offers(entries)
		_refresh_exit()
		return true
	if _loot_slot == null or not is_instance_valid(_loot_slot):
		return false
	# The column was empty — this report paid nothing of its own — so the grant
	# builds the section that was never needed until now.
	for c in _loot_slot.get_children():
		_loot_slot.remove_child(c)
		c.queue_free()
	_loot = entries.duplicate(true)
	_fill_payout()
	_refresh_exit()
	return _loot_section != null

# The pack changed under one of the other sections — a chest's relic firing an
# `offer_loot`, a use freeing a slot — so the payout redraws against it.
func refresh_payout() -> void:
	if _loot_section != null and is_instance_valid(_loot_section):
		_loot_section.redraw()

# WHAT THE LEVEL-UP PAID, or null when this report took none.
#
# A level-up is the one reward on this screen with no picture of its own. A chest
# it granted lands in the chest column below and a piece of loot it granted lands
# on the payout table to the right, but the +1 Scramble and the +1 Gold went
# straight onto the header bar and said nothing anywhere — and on the one screen
# that exists to answer "what did the evening earn", a reward that arrives
# silently is a reward the player has to take on trust.
#
# So: the condition they met, the sheet's own wording for what it is worth, and
# every stat line the chain actually granted. THE CHAIN, not the level — a Crown
# doubling it paid twice, and quoting the character sheet instead of what was
# applied would under-report the relic that caused it (Overworld2._apply_level_up
# collects them across the whole while-loop for exactly this).
func _level_up_panel() -> Control:
	var lvl: Dictionary = _snap.get("level_up", {})
	if lvl.is_empty():
		return null
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG_DEEP, UITheme.GOLD.lerp(UITheme.BORDER, 0.4), 8, 10, 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	wrap.add_child(col)
	var levels: int = maxi(1, int(lvl.get("levels", 1)))
	# "LEVELLED UP ×2" only when the Crown actually chained one. A count on the
	# common case is a number the player has to read to learn it says one.
	# ✦, not an up-arrow: the glyph font is a subset (see tools/build_glyph_font.py)
	# and a symbol it does not carry costs a host font search every time a Label
	# wearing it is built. ✦ is already in it, and already means "the evening earned
	# something" on the heading below this panel.
	col.add_child(_line("✦  LEVELLED UP" + ("" if levels == 1 else "  ×%d" % levels),
		UITheme.GOLD, 10))
	col.add_child(_line(String(lvl.get("condition", "")), UITheme.TEXT, 13, true))
	var stats: Array = lvl.get("stats", [])
	if not stats.is_empty():
		col.add_child(_line(", ".join(PackedStringArray(stats)), UITheme.SUCCESS, 12, true))
	# The sheet's wording is the FALLBACK, not the headline: it is a promise, and
	# the stat lines above are what was actually paid. It is still worth printing
	# when there are none, because a chest-only or loot-only level has nothing else
	# to show here — the thing it bought is in another column.
	var reward: String = String(lvl.get("reward", ""))
	if stats.is_empty() and reward != "" and reward.to_upper() != "N/A":
		col.add_child(_line(reward, UITheme.SUCCESS, 12, true))
	return wrap

# Is there a payout table on this screen at all? A report that earned nothing says
# so with a note where the loot would have been, and this is how a caller tells
# the two apart without reaching into the section.
func has_loot_section() -> bool:
	return _loot_section != null and is_instance_valid(_loot_section)

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

# The line beside the way out, which names the same destination the button does —
# the two are read together and used to disagree once the button stopped saying
# "see what's waiting".
func _hint_text() -> String:
	if _event_pending:
		return "Take what you want, spend what you like — then on to the event."
	if _shop_id != &"":
		return "Take what you want — the shop is waiting under the board."
	return "Take what you want, then pick where the run goes next."

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var hint := _line(_hint_text(), UITheme.TEXT_FAINT, 12)
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

# EVERY CHEST AT ONCE. They used to be drained one at a time, which is how the
# page's queue had always worked — but a queue hides the thing the player most
# needs when several relics land together, which is what the OTHER ones are. There
# is often an order: a relic that changes what a chest is worth should be taken
# before the chest it changes, and a Charged active you are about to fire is worth
# more than one you are not. None of that can be reasoned about a card at a time.
#
# Each chest is still its own question — "which one of these" — and answering one
# leaves the rest exactly where they were.
func _build_chests() -> void:
	if _done or _chest_slot == null or not is_instance_valid(_chest_slot):
		return
	while not _chests.is_empty():
		_mount_chest(_chests.pop_front())
	_refresh_exit()

func _mount_chest(items: Array) -> void:
	var section := ItemDropModal.embed(self, _chest_slot, items)
	_chest_sections.append(section)
	section.answered.connect(func(taken: bool, item: ItemData):
		if taken and item != null:
			_collect(item)
		else:
			_leave(items)
		# A relic can pay out loot the moment it is picked up (Sacred Bark, Mom's
		# Coin Purse), so the pack beside these cards may have just changed.
		refresh_payout()
		_refresh_exit()
		_sync_chest_head.call_deferred())
	_sync_chest_head()

# The heading stands exactly while there is a chest under it — the sections free
# their own panels, so this is asked again after each answer (deferred, because
# the freed panel is still a child on the frame it is answered).
func _sync_chest_head() -> void:
	var showing: bool = not _live_chests().is_empty()
	if _chest_head != null and is_instance_valid(_chest_head):
		_chest_head.visible = showing
	if _chest_why != null and is_instance_valid(_chest_why):
		_chest_why.visible = showing

# The sum, as one wrapping row of small chips: the win, then a face per body with
# what it was worth, `+` between them, `=` and the chest at the end. Null when
# this report earned no chest to explain.
#
# DELIBERATELY SMALL AND DELIBERATELY ONE ROW. The left column already scrolls,
# and this is a footnote to the chest under it rather than a section of its own —
# it earns its space by being read in a glance and not by being thorough. The
# faces are 22px, the numbers ride on them, and the whole thing wraps rather than
# growing a scrollbar when a big evening put eight bodies in it.
const REASON_FACE := 22

func _chest_sum_row() -> Control:
	var terms: Array = chest_terms()
	if terms.is_empty():
		return null
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG_DEEP, UITheme.BORDER, 6, 8, 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	wrap.add_child(col)
	# WHAT THE SUM IS FOR, said before the sum. A row of faces and numbers is
	# arithmetic without a subject until something names the quantity it totals to.
	col.add_child(_line("ITEM CHEST SIZE", UITheme.TEXT_FAINT, 10))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 3)
	col.add_child(flow)
	for i in range(terms.size()):
		if i > 0:
			flow.add_child(_sum_glyph("+"))
		flow.add_child(_sum_term(terms[i]))
	flow.add_child(_sum_glyph("="))
	# The answer sits on the FACES' line, like the operators — centring it against a
	# term that is now two rows tall would float it between the pictures and their
	# values, which is the one place it does not belong.
	var result := _line(chest_result_text(), UITheme.GOLD, 13)
	result.custom_minimum_size = Vector2(0, REASON_FACE)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	flow.add_child(result)
	return wrap

# One term, stacked: the face on top and what it was worth UNDER it. Side by side
# the numbers read as part of the next picture along at this size; under them each
# value is unmistakably the caption of the thing above it.
func _sum_term(term: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var enemy: GoalEnemyData = term.get("enemy")
	var tip: String = ""
	if enemy != null and enemy.image != null:
		var art := TextureRect.new()
		art.texture = enemy.image
		art.custom_minimum_size = Vector2(REASON_FACE, REASON_FACE)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# The name is the tooltip rather than a caption: eight of these across a
		# 600px column is a row of labels, and the picture is the point.
		tip = "%s — %s, worth %d" % [enemy.display_name,
			RunDifficulty.tier_name(enemy.tier_index()), int(term.get("points", 0))]
		art.tooltip_text = tip
		box.add_child(art)
	else:
		# The win's own point (§8.2): a game beaten with a clear board is still a
		# Small chest, and the sum has to show where that came from.
		tip = "Beating the game is worth 1 on its own."
		var w := _line("🏆", UITheme.GOLD, 16)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		w.custom_minimum_size = Vector2(REASON_FACE, REASON_FACE)
		w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		w.tooltip_text = tip
		box.add_child(w)
	var pts := _line("+%d" % int(term.get("points", 0)), UITheme.TEXT, 11)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts.custom_minimum_size = Vector2(REASON_FACE, 0)
	# The same tooltip on both halves, so the number explains itself as readily as
	# the picture does — they are one term and the mouse should not have to know
	# which half of it carries the words.
	pts.tooltip_text = tip
	box.add_child(pts)
	return box

# The `+` and `=` between terms, lifted onto the faces' own line rather than
# centred against a term that is now two rows tall.
func _sum_glyph(text: String) -> Control:
	var l := _line(text, UITheme.TEXT_FAINT, 12)
	l.custom_minimum_size = Vector2(0, REASON_FACE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return l

# A chest banked AFTER this screen opened — a level-up's reward, Unstable Genome,
# a status's payout — put on the screen rather than behind it. Without this it
# opens a RewardScreen on the page's own layer, underneath this one, and the
# player sees nothing until they have already left (§8.2).
func add_chest(items: Array) -> void:
	if _done or items.is_empty():
		return
	if _chest_slot == null or not is_instance_valid(_chest_slot):
		_chests.append(items)
		return
	_mount_chest(items)
	_refresh_exit()

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

# THE SHELF IS NOT ON THIS SCREEN ANY MORE. It used to be mounted into the left
# column and handed back to the page on the way out, on the reasoning that §14's
# "a shop blocks nothing and stays for the whole visit" was right but that the
# moment of ARRIVAL was never seen.
#
# What that produced was a screen with four sections competing for a 720p canvas
# and a way out that could not honestly name where it went: the button now says
# "Go to Shop", and a button pointing at a shelf the player is already looking at
# is a button describing nothing. So the shelf stays where §14 put it — under the
# board, for the rest of the visit — and this screen keeps only the id, to know
# that is where its exit leads. The page never claims `_pending_shop` for this
# screen now, so its own chain mounts the shelf after the event exactly as it
# does when no haul screen was involved (Overworld2._open_pending_shop).
func shop_id() -> StringName:
	return _shop_id


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
	for section in _live_chests():
		section.leave()
	_chest_sections.clear()
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


# A wrapping line pinned to TITLE_W. An autowrap Label reports its minimum size
# by wrapping against `custom_minimum_size.x`, so setting that is what actually
# makes it wrap inside a shrink-sized column rather than reporting one long line.
func _wrapped(text: String, color: Color, size: int) -> Label:
	var l := _line(text, color, size, true)
	l.custom_minimum_size = Vector2(TITLE_W, 0)
	return l

func _line(text: String, color: Color, size: int, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

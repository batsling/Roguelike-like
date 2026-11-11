class_name ItemDropModal
extends Control

# ItemDropModal — "here is a chest, which one do you want out of it?" (§8).
#
# A relic reward used to land in a LOOT TRAY beside the board and wait there to be
# claimed. It waited too well: the tray is a quiet row on a busy page and a relic
# could sit in it for three games without being noticed. So the chest asks
# instead — one modal, the item at full size with everything it does, and the two
# answers the tray had (Take it / Leave it) as buttons.
#
# A CHEST'S SIZE is how many things it offers (§8.2): a Small chest is "choose 1
# of 1" and reads exactly as the single item this modal has always shown, and at
# 2 or more the layout becomes a row of cards you pick from — still one relic
# taken, still one "Leave it", because the answer to a chest is which one and not
# how many. (Embedded on the reward screen there is no "Leave it" at all: a chest
# you don't want is one you don't take — see `_build`.)
#
# WHERE THE CHESTS COME FROM is the report (§8.2): a game you beat pays one point
# plus each defeated body's difficulty, spent on the size ladder, so a heavy
# evening is a bigger chest rather than a longer queue of Small ones. A boss adds
# a chest of its own, and a level-up, a status or an event can hand one over at any
# moment.
#
# Overworld2 owns the queue behind it: several chests at one report open one modal
# each, in the order they were banked (see _pump_drops there). This screen only
# ever knows about the one chest in front of it, and reports the answer back
# through `answered`.
#
# Built in code on its own CanvasLayer, like every other 2.0 modal, so it centres
# over the overworld whatever mounted it.
#
# IT ALSO EMBEDS (`embed`). After a game is reported the chests are not raised one
# popup at a time any more — they are a section of the post-combat screen
# (`PostCombatScreen`), beside the loot and the numbers, because they are one
# haul rather than a queue of unrelated questions. Embedded, this class builds the
# same cards, runs the same selection and answers through the same signal; what it
# skips is the backdrop, the centring and the CanvasLayer. The standalone modal
# stays for the chests that DON'T arrive with a report — an item or an event can
# hand one over at any moment — so the two paths share every pixel of the card and
# differ only in what is drawn around it.

# taken = the player took something, and `item` is which (null when they didn't).
# Emitted exactly once, before `finished`.
signal answered(taken: bool, item: ItemData)
signal finished

# What the chest is offering, in the order it was rolled. Never empty once the
# modal is up — an empty chest answers "left it" and closes before it builds.
var _items: Array = []
# The card the player has clicked, or the only one there is. Never null while the
# Take button is enabled.
var _selected: ItemData = null
var _layer: CanvasLayer = null
var _answered: bool = false
# EMBEDDED MODE. `_slot` is the container whose contents this chest is, and
# `_body` is what it put there — the one thing an answer takes back down. When
# both are null this is the ordinary modal and `_layer` is what goes.
var _slot: Container = null
var _body: Control = null
# Redrawn on every selection change so the chosen card is the one wearing the
# highlight; kept as fields because the panel is rebuilt in place.
var _cards: Array = []
var _take_btn: Button = null
# COMPACT is the card, EMBEDDED is the frame, and they were one flag until the
# banked-chest screen (RewardScreen) needed the frame without the small card: it
# hosts chests in its own panel, but a single chest there is the only thing on
# screen and wears the full-size card the pop-up does.
var _compact: bool = false
# The word a tagged chest is named with ("Devilish"), or "" for the ordinary pool.
var _pool: String = ""
# The gift in the heading, the one-item layout's body, and the tween that opens
# the chest (see _play_open).
var _gift: Control = null
var _stars: Array = []
var _single: Control = null
# The row the answers sit in. A host that has answers of its own for this chest
# (the banked-chest screen's Reroll and Leave) puts them here, beside Take, so the
# buttons under a chest are one row wherever the chest is.
var _row: BoxContainer = null
# How to roll this chest again, or an invalid Callable for a chest that cannot be
# (one offering named items, or one whose host re-rolls it itself). Returns the
# new offer. Only the pop-up draws a Reroll button off it; an embedded chest is
# re-rolled by its host, which has one button for every chest on the screen.
var _reroll: Callable = Callable()
var _reroll_btn: Button = null
var _open_tween: Tween = null

const PANEL_SIZE := Vector2(460, 0)
# A chest of N is this much wider per extra card, capped so a Huge (5) still fits
# a small window. The single-item layout keeps PANEL_SIZE exactly.
const CARD_W := 168
const MULTI_MAX_W := 920
# The compact card the post-combat screen's chests wear: wider than the modal's,
# because the art moved beside the words and the words now have the whole card to
# wrap in rather than a column under a picture.
const COMPACT_CARD_W := 262
const COMPACT_ART := 44
# The compact card says what it does in this many lines and the hover card says
# the rest. Two, because one line cuts most relics off mid-clause and three makes
# a chest of three as tall as the column it sits in.
const COMPACT_DESC_LINES := 2

# THE ONE ICON AND THE ONE COLOUR A CHEST IS DRAWN WITH, on every screen that
# shows one. A chest used to be a ✦ on the pop-up, bare gold words on the banked
# screen and nothing at all on the haul.
const CHEST_GLYPH := "🎁"
const CHEST_GOLD := UITheme.GOLD
# A chest's SIZE, drawn: this many stars arc over the gift, and the gift glows in
# the colour of the rarity that sits on the same rung of the ladder (the four
# sizes and the four rarities share one 75/20/4/1 roll, Data.ChestSize).
const STAR_GLYPH := "★"
# How far round the gift the stars spread, end to end, at four of them.
const STAR_ARC_DEG := 110.0

# Which rung a chest of `count` stands on: 0 Small … 3 Huge. A count between two
# rungs is the rung below it.
static func chest_rank(count: int) -> int:
	var rank: int = 0
	for size in Data.CHEST_SIZE_CHOICES:
		if count >= int(Data.CHEST_SIZE_CHOICES[size]):
			rank = maxi(rank, int(size))
	return rank

# How the chest opens: the gift lands, then the cards are dealt one after another.
const OPEN_GIFT_SECS := 0.18
const OPEN_CARD_SECS := 0.16
const OPEN_CARD_STAGGER := 0.07

# What a chest of `count` is CALLED — "Small Chest", "Devilish Large Chest" — the
# same words the checklist promised it in (Data.CHEST_SIZE_NAMES). A count that is
# not a rung of the ladder (starting gear's "1 of 4", a Discovery-widened default)
# has no size name, so it says the count instead.
static func chest_name(count: int, pool: String = "") -> String:
	var size_word: String = ""
	for size in Data.CHEST_SIZE_CHOICES:
		if int(Data.CHEST_SIZE_CHOICES[size]) == count:
			size_word = String(Data.CHEST_SIZE_NAMES[size])
	var prefix: String = (pool.capitalize() + " ") if pool != "" else ""
	if size_word == "":
		return "%sChest of %d" % [prefix, count]
	return "%s%s Chest" % [prefix, size_word]

# …and the heading every chest wears: the gift, its name, and what is being asked
# when there is something to choose between.
static func chest_heading(count: int, pool: String = "") -> String:
	if count <= 1:
		return "%s  %s" % [CHEST_GLYPH, chest_name(count, pool)]
	return "%s  %s — take 1 of %d" % [CHEST_GLYPH, chest_name(count, pool), count]

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Entry point: mount over `host` and ask about a chest. `offer` is either the one
# item a body left or the list a bigger chest is offering — a bare ItemData is
# accepted so the single-drop call site reads the way it always has.
#
# `reroll` makes the chest re-rollable: called when a Reroll charge is spent, it
# returns what the chest offers now.
static func open(host: Node, offer, reroll: Callable = Callable()) -> ItemDropModal:
	var modal := ItemDropModal.new()
	modal._reroll = reroll
	modal._start(host, offer)
	return modal

# ONE REROLL, EVERYWHERE. A charge re-rolls every chest still open on the screen
# it is spent on — the one chest of a pop-up, all of them on the banked screen and
# on the haul. These two are the whole of the rule, so the three screens cannot
# disagree about what the button says or what it costs.
static func dress_reroll(btn: Button) -> void:
	btn.text = "🎲  Reroll (%d)" % GameState.reroll_charges
	btn.disabled = GameState.reroll_charges <= 0
	btn.tooltip_text = "Spend a Reroll to roll every chest here again." \
		if GameState.reroll_charges > 0 else "No Rerolls left."

static func spend_reroll() -> bool:
	if GameState.reroll_charges <= 0:
		return false
	GameState.reroll_charges -= 1
	return true

# What this chest is offering right now.
func offer() -> Array:
	return _items.duplicate()

# OFFER SOMETHING ELSE, in place: the same chest, where it stood, opened again.
# What a re-roll does to a chest — the host rolls, this redraws. An offer of a
# different size is refused, since a chest's size is not what a Reroll re-rolls.
func reoffer(items: Array) -> void:
	if _answered or items.is_empty():
		return
	var fresh: Array = items.filter(func(it): return it is ItemData)
	if fresh.is_empty():
		return
	_items = fresh
	_selected = _items[0]
	for it in _items:
		GameStats.mark_seen("item", (it as ItemData).id)
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	var at: int = -1
	if _body != null and is_instance_valid(_body):
		at = _body.get_index()
		_body.get_parent().remove_child(_body)
		_body.queue_free()
		_body = null
	else:
		# The pop-up: everything under this node is the chest's own.
		for child in get_children():
			remove_child(child)
			child.queue_free()
	_cards.clear()
	_stars.clear()
	_single = null
	_gift = null
	_row = null
	_reroll_btn = null
	_build()
	if at >= 0 and _body != null:
		_slot.move_child(_body, at)

func _on_reroll() -> void:
	if _answered or not _reroll.is_valid() or not spend_reroll():
		return
	var fresh = _reroll.call()
	if fresh is Array:
		reoffer(fresh)

func _start(host: Node, offer) -> void:
	_items = []
	for entry in (offer if offer is Array else [offer]):
		if entry is ItemData:
			_items.append(entry)
			GameStats.mark_seen("item", entry.id)
	_layer = CanvasLayer.new()
	_layer.layer = UITheme.Layer.DROP
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _items.is_empty():
		_answer(false)
		return
	_selected = _items[0]
	_build()

# Entry point for the post-combat screen: put this chest INSIDE `slot` rather
# than over the page. `host` is the node the controller parks on for its lifetime
# — it draws nothing itself and takes no room, so a Control root is as good a
# perch as a container. Answers through the same `answered` / `finished` signals.
#
# `compact` is the small sideways card the haul uses, where a chest is one of
# several; false keeps the pop-up's full-size cards inside the host's own frame.
# `pool` names a tagged chest in its heading.
static func embed(host: Node, slot: Container, offer, compact: bool = true,
		pool: String = "") -> ItemDropModal:
	var modal := ItemDropModal.new()
	modal._slot = slot
	modal._compact = compact
	modal._pool = pool
	# The controller is a parked logic node, not part of the picture: no size, no
	# mouse, nothing to lay out. Everything it draws goes into `slot`.
	modal.set_anchors_preset(Control.PRESET_TOP_LEFT)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in (offer if offer is Array else [offer]):
		if entry is ItemData:
			modal._items.append(entry)
	host.add_child(modal)
	if modal._items.is_empty():
		modal._answer(false)
		return modal
	modal._selected = modal._items[0]
	modal._build()
	return modal

func _build() -> void:
	var multi: bool = _items.size() > 1
	var compact: bool = _compact
	var embedded: bool = _slot != null
	# A ONE-ITEM CHEST ON SOMEBODY ELSE'S PAGE lays out sideways: the card on the
	# left, its answer on the right. Everything else — the modal, and any chest
	# offering a choice — keeps the column it has always had.
	var sideways: bool = compact and not multi
	var tint: Color = UITheme.item_color(_selected)
	var box: VBoxContainer = _build_shell(multi)

	# EVERY CHEST SAYS WHAT IT IS, in the same words and with the same gift, on
	# every screen. A one-item chest on the haul used to go without a heading at
	# all (the host wrote one above them), which is how a Small chest came to look
	# like a loose relic there and like a chest everywhere else.
	box.add_child(_heading_row(compact))

	# Where the cards go and where the answers go. Stacked, a compact chest is
	# ~135px, and three of those is more than the post-combat screen's column holds
	# — which puts the third relic behind a scrollbar on the one screen built so
	# every relic can be weighed against the others. Sideways it is half that.
	var beside: HBoxContainer = null
	if sideways:
		beside = HBoxContainer.new()
		beside.add_theme_constant_override("separation", UITheme.GAP_WIDE)
		beside.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(beside)

	_cards.clear()
	# EMBEDDED, EVERY CHEST IS A SHELF — a one-item chest included. As a modal a
	# single relic is drawn at full size, which is right when it is the only thing
	# on screen; here it is one of several sections, and uniform compact cards mean
	# every relic the report dropped is readable at once. That is what lets the
	# player pick an ORDER — take the one that changes what the others are worth
	# first.
	if compact or multi:
		var host: Container = beside
		if host == null:
			# A FLOW, not a row. As a modal the panel is widened to fit the whole
			# chest (see _build_shell) so it lays out as the single row it always
			# was; embedded, the column decides the width and a Huge chest wraps
			# instead of running off the side of somebody else's screen.
			var shelf := HFlowContainer.new()
			shelf.add_theme_constant_override("h_separation", UITheme.GAP_WIDE)
			shelf.add_theme_constant_override("v_separation", UITheme.GAP_WIDE)
			shelf.alignment = FlowContainer.ALIGNMENT_CENTER
			box.add_child(shelf)
			host = shelf
		for item in _items:
			var card: Control = _offer_card(item)
			host.add_child(card)
			_cards.append({"item": item, "node": card})
	else:
		_build_single(box, tint)

	# Stacked beside the card when sideways, where the two buttons read as the two
	# answers to the one thing on their left; a row under the cards otherwise.
	# BUILT as the container it needs to be rather than flipped afterwards: an
	# HBoxContainer is a FIXED BoxContainer and refuses `vertical`.
	var row: BoxContainer = VBoxContainer.new() if sideways else HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_TIGHT if sideways else 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if sideways:
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		beside.add_child(row)
	else:
		box.add_child(row)
	_row = row

	# NO "LEAVE IT" ON THE REWARD SCREEN. Embedded, a chest you do not want is a
	# chest you do not take: the screen's own way out answers everything still on
	# it as left (PostCombatScreen.dismiss), so a button saying the same thing was
	# a second, smaller way to decline. The standalone modal keeps it, because
	# there it is the only way out.
	if not embedded:
		var leave := Button.new()
		leave.text = "Skip"
		leave.custom_minimum_size = Vector2(150, 42)
		leave.pressed.connect(func(): _answer(false))
		row.add_child(leave)
		if _reroll.is_valid():
			_reroll_btn = Button.new()
			_reroll_btn.custom_minimum_size = Vector2(150, 42)
			_reroll_btn.pressed.connect(_on_reroll)
			dress_reroll(_reroll_btn)
			row.add_child(_reroll_btn)

	_take_btn = Button.new()
	_take_btn.custom_minimum_size = Vector2(150, 26) if compact else Vector2(190, 42)
	_take_btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY if compact else UITheme.FONT_SUB)
	_take_btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.5), 8, 8, 2, UITheme.SUCCESS))
	# FOCUSED IS STILL GREEN. The pop-up gives Take the focus, and the theme's focus
	# ring is orange — so the one Take button that had it was the one that did not
	# look like the others.
	_take_btn.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 8, 8, 2, UITheme.SUCCESS.lerp(Color.WHITE, 0.35)))
	_take_btn.add_theme_color_override("font_focus_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.45))
	_take_btn.add_theme_color_override("font_hover_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.6))
	_take_btn.add_theme_stylebox_override("hover", UITheme.flat(UITheme.SUCCESS.lerp(UITheme.BG, 0.32), 8, 8, 2, UITheme.SUCCESS))
	_take_btn.add_theme_color_override("font_color", UITheme.SUCCESS.lerp(Color.WHITE, 0.45))
	_take_btn.pressed.connect(func(): _answer(true))
	row.add_child(_take_btn)
	# Focus is the HOST's to give when this is one section among several — grabbing
	# it here would pull it off the way out every time another chest is answered.
	if not embedded:
		_take_btn.grab_focus()
	_refresh_selection()
	_play_open()

# The heading: the gift under its stars, and the chest's name in gold, as one
# centred row.
func _heading_row(compact: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITheme.GAP)
	var words: PackedStringArray = _heading().split("  ", false, 1)
	_gift = _gift_badge(words[0], compact)
	row.add_child(_gift)
	var head := Label.new()
	head.text = words[1] if words.size() > 1 else ""
	head.add_theme_font_size_override("font_size", UITheme.FONT_BODY if compact else UITheme.FONT_SUB)
	head.add_theme_color_override("font_color", CHEST_GOLD)
	# On the gift's line, not the middle of the badge: the stars stand above it.
	head.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(head)
	return row

const GOLD_TEXT := Color(1.0, 0.9, 0.3)

# "+6 gold from 3 chests" — the ONE line a screen of chests says its gold in, over
# the chests rather than on each. The gold is paid as the chests open, taken or
# skipped, so it is a fact about the screen and not something a chest is holding:
# on each heading it read as a thing you got by taking that chest.
static func gold_text(gold: int, chests: int = 1) -> String:
	if chests <= 1:
		return "+%d gold" % gold
	return "+%d gold from %d chests" % [gold, chests]

# The gift, the glow behind it and the stars over it. Built from plain Labels on a
# fixed-size Control so the whole badge can be bounced as one thing.
func _gift_badge(glyph: String, compact: bool) -> Control:
	var rank: int = chest_rank(_items.size())
	var tint: Color = RarityStyle.color(rank)
	var font: int = UITheme.FONT_TITLE_LG if compact else UITheme.FONT_HERO
	var star_font: int = UITheme.FONT_TINY if compact else UITheme.FONT_BODY
	var side: float = font * 1.5
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(side * 1.5, side + star_font)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := Vector2(side * 0.75, star_font + side * 0.5)
	# THE GLOW: soft rings of the size's colour, drawn rather than a texture so it
	# takes any tint and costs no art.
	badge.draw.connect(func():
		for i in range(6):
			badge.draw_circle(centre, side * (0.62 - 0.08 * i), Color(tint.r, tint.g, tint.b, 0.1)))
	var gift := Label.new()
	gift.text = glyph
	gift.add_theme_font_size_override("font_size", font)
	gift.add_theme_color_override("font_color", CHEST_GOLD.lerp(tint, 0.25))
	gift.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gift.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gift.position = centre - Vector2(side, side) * 0.5
	gift.size = Vector2(side, side)
	gift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(gift)
	_stars.clear()
	var count: int = rank + 1
	var step: float = STAR_ARC_DEG / 3.0
	for i in range(count):
		var deg: float = -90.0 + (i - (count - 1) * 0.5) * step
		var at: Vector2 = centre + Vector2.from_angle(deg_to_rad(deg)) * side * 0.66
		var star := Label.new()
		star.text = STAR_GLYPH
		star.add_theme_font_size_override("font_size", star_font)
		star.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.25))
		star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		star.size = Vector2(star_font, star_font) * 1.4
		star.position = at - star.size * 0.5
		star.pivot_offset = star.size * 0.5
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(star)
		_stars.append(star)
	return badge

# THE CHEST OPENS. The gift lands with a bounce and the cards are dealt after it,
# left to right — about half a second for a Large, and the same on every screen a
# chest is drawn on. Nothing waits for it: a card can be clicked and the answer
# given while it is still arriving, and a click anywhere finishes it at once.
#
# Scale and alpha only, never position: the cards sit in containers, which own
# where they are.
func _play_open() -> void:
	if not is_inside_tree():
		return
	_open_tween = create_tween()
	# A chest opens over a paused page as readily as a running one.
	_open_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_open_tween.set_parallel(true)
	if _gift != null:
		_centre_pivot(_gift)
		_gift.scale = Vector2(0.3, 0.3)
		_open_tween.tween_property(_gift, "scale", Vector2.ONE, OPEN_GIFT_SECS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# …the stars light one after another as it lands…
	for i in range(_stars.size()):
		var star: Control = _stars[i]
		star.modulate.a = 0.0
		star.scale = Vector2(0.2, 0.2)
		var at: float = OPEN_GIFT_SECS * 0.5 + 0.05 * i
		_open_tween.tween_property(star, "modulate:a", 1.0, 0.1).set_delay(at)
		_open_tween.tween_property(star, "scale", Vector2.ONE, 0.14) \
			.set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var dealt: Array = _cards.map(func(c): return c["node"])
	if dealt.is_empty() and _single != null:
		dealt = [_single]
	for i in range(dealt.size()):
		var node: Control = dealt[i]
		var delay: float = OPEN_GIFT_SECS * 0.6 + OPEN_CARD_STAGGER * i
		_centre_pivot(node)
		node.modulate.a = 0.0
		node.scale = Vector2(0.86, 0.86)
		_open_tween.tween_property(node, "modulate:a", 1.0, OPEN_CARD_SECS).set_delay(delay)
		_open_tween.tween_property(node, "scale", Vector2.ONE, OPEN_CARD_SECS) \
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Scale about the middle. A Control's pivot is in pixels and its size is not known
# until the container has laid it out, so it is set now and again on every resize.
func _centre_pivot(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
	node.resized.connect(func(): node.pivot_offset = node.size * 0.5)

# Jump the opening to its end. Public so a host (and a test) can ask for the
# finished picture.
func finish_opening() -> void:
	if _open_tween != null and _open_tween.is_valid() and _open_tween.is_running():
		_open_tween.custom_step(10.0)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		finish_opening()

# A RELIC IS ALWAYS A PICTURE, even when the catalogue has no art for it. Every
# item in items2.0 ships with an image today, and both card layouts used to draw
# one only when `item.image` was non-null — so the day a row is authored without
# art (or with a path that stops resolving) the card comes up with a silent gap
# where the relic should be, on the screen where the player is deciding whether to
# take it. A tinted tile with the item's initial on it is not the art, but it is
# unmistakably a thing, and it is the size of the picture it stands in for so
# nothing reflows behind it.
func _item_art(item: ItemData, size: int) -> Control:
	var art: Control = _bare_item_art(item, size)
	var badge: Control = charge_badge(item)
	if badge != null:
		art.add_child(badge)
	return art

# HOW MANY CHARGES AN ITEM IN A CHEST HOLDS (the owner, 11 Nov 2026), as a pip on
# the corner of its art — the same pip the pack hangs a counter on. A chest shows
# a TEMPLATE, so the number is what the item is: the charges a charged item's bar
# has, or the uses a limited one comes with. Null for an item with neither.
# Static and public so a test can ask it.
static func charge_count(item: ItemData) -> int:
	if item == null:
		return 0
	if item.is_charged():
		return item.max_charge()
	if item.kind == ItemData.ItemKind.USABLE and item.max_uses > 0:
		return item.max_uses
	return 0

static func charge_badge(item: ItemData) -> Control:
	var count: int = charge_count(item)
	if count <= 0:
		return null
	var wrap := PanelContainer.new()
	wrap.name = "ChargeBadge"
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	wrap.offset_right = 3
	wrap.offset_bottom = 3
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.tooltip_text = "%d %s" % [count, Plural.word(count, "charge" if item.is_charged() else "use")]
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(UITheme.WELL, 0.92), 8, 0, 1, UITheme.GOLD))
	var label := Label.new()
	label.text = " ⚡%d " % count
	label.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	label.add_theme_color_override("font_color", UITheme.GOLD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(label)
	return wrap

func _bare_item_art(item: ItemData, size: int) -> Control:
	if item != null and item.image != null:
		return UITheme.crisp_tex(item.image, size)
	var tint: Color = UITheme.item_color(item) if item != null else UITheme.TEXT_DIM
	var stand_in := PanelContainer.new()
	stand_in.custom_minimum_size = Vector2(size, size)
	stand_in.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.7), 6, 0, 1, tint.lerp(UITheme.BORDER, 0.4)))
	var glyph := Label.new()
	glyph.text = String(item.display_name).left(1).to_upper() if item != null else "?"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", maxi(10, size / 2))
	glyph.add_theme_color_override("font_color", tint)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stand_in.add_child(glyph)
	return stand_in

# What this chest calls itself. A chest of one has nothing to choose between, so
# it names the thing rather than the choice; more than one IS the choice, and the
# count is the part the player is deciding against.
func _heading() -> String:
	return chest_heading(_items.size(), _pool)

# The frame the cards go in — the ONE thing the two modes disagree about, so it
# is the one thing with a branch in it. As a modal: a dimmed backdrop and a panel
# of its own, centred and widened to hold the whole chest on one row. Embedded: a
# bordered section of somebody else's column, as wide as that column makes it.
# Returns the box everything else is built into, which is identical either way.
func _build_shell(multi: bool) -> VBoxContainer:
	var panel: PanelContainer
	if _slot != null:
		panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slot.add_child(panel)
		_body = panel
		# FULL-SIZE CARDS IN SOMEBODY ELSE'S FRAME draw no frame of their own: the
		# host's panel is the chest's panel, and a border inside it would be a box
		# in a box.
		if not _compact:
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			var bare := VBoxContainer.new()
			bare.add_theme_constant_override("separation", UITheme.GAP_WIDE)
			panel.add_child(bare)
			return bare
		# The frame is the chest's gold, not the first item's rarity: the cards
		# inside carry their own, and a frame that changed colour with whatever
		# happened to be rolled first said nothing about the chest.
		panel.add_theme_stylebox_override("panel",
			UITheme.panel_box(UITheme.PANEL, CHEST_GOLD.lerp(UITheme.BORDER, 0.6), 10, 0, 1))
	else:
		var width: float = PANEL_SIZE.x
		if multi:
			width = minf(MULTI_MAX_W, 80.0 + CARD_W * _items.size())
		# No click-outside-to-close: leaving a Legendary on the ground is a decision,
		# and it should be made on a button rather than by a stray click.
		panel = ModalScaffold.build_panel(self, CHEST_GOLD, Callable(), Vector2(width, 0))
		panel.custom_minimum_size = Vector2(width, 0)
		panel.size = Vector2(width, 0)
		panel.set_anchors_preset(Control.PRESET_CENTER)

	var margin := MarginContainer.new()
	var side_pad: int = UITheme.GAP_LOOSE if _compact else 18
	margin.add_theme_constant_override("margin_left", side_pad)
	margin.add_theme_constant_override("margin_right", side_pad)
	var pad: int = 10 if _slot != null else 16
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP if _slot != null else 10)
	margin.add_child(box)
	return box

# The one-item chest: the item at full size, which is what a drop has always
# looked like and what nine drops in ten still are.
func _build_single(outer: VBoxContainer, tint: Color) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	outer.add_child(box)
	_single = box
	var art: Control = _item_art(_selected, 108)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)

	var name_lbl := Label.new()
	name_lbl.text = _selected.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	name_lbl.add_theme_color_override("font_color", tint)
	box.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line(_selected)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	box.add_child(kind)

	var desc := Label.new()
	desc.text = _selected.description if String(_selected.description) != "" else "A dropped relic."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(desc)
	# The KEYWORD STRIP (§17). This is the moment the item is being decided on, so
	# it is the moment "what is a Fire Tile?" most needs an answer. Only on the
	# SINGLE-item layout — the shelf cards below are five abreast and have no room.
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	if Keywords.attach(keys, _selected.description) > 0:
		box.add_child(keys)
	else:
		keys.queue_free()

# One pickable card on a chest's shelf — THE card, on every screen a chest is
# drawn on: the art, the name in its rarity's colour, what kind of thing it is and
# what it does, in a panel that clicking selects.
#
# COMPACT (the haul, and several banked chests at once) is the same four things
# laid SIDEWAYS: the art beside the words rather than over them, so a card is as
# tall as its words and three chests fit a column. The description is held to
# COMPACT_DESC_LINES there and the hover card carries the whole of it. For a while
# the compact card was the picture alone with every word on hover, which made the
# haul the one screen where a relic had to be pointed at to be read.
func _offer_card(item: ItemData) -> Control:
	var compact: bool = _compact
	var tint: Color = UITheme.item_color(item)
	var card := HoverPanel.new()
	card.custom_minimum_size = Vector2(COMPACT_CARD_W if compact else CARD_W, 0)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	HoverCard.attach(card, {
		"title": item.display_name,
		"subtitle": _kind_line(item),
		"accent": tint,
		"art": item.image,
		"lines": [item.description if String(item.description) != "" else "A dropped relic."],
	})

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, UITheme.GAP_SNUG if compact else UITheme.GAP_WIDE)
	card.add_child(margin)

	var art: Control = _item_art(item, COMPACT_ART if compact else 72)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_HAIR if compact else UITheme.GAP_SNUG)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if compact:
		var side_by_side := HBoxContainer.new()
		side_by_side.add_theme_constant_override("separation", UITheme.GAP)
		side_by_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(side_by_side)
		side_by_side.add_child(art)
		side_by_side.add_child(col)
	else:
		margin.add_child(col)
		col.add_child(art)

	var align: int = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
	var name_lbl := Label.new()
	name_lbl.text = item.display_name
	name_lbl.horizontal_alignment = align
	if compact:
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.clip_text = true
	else:
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_TEXT if compact else UITheme.FONT_LEAD)
	name_lbl.add_theme_color_override("font_color", tint)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_lbl)

	var kind := Label.new()
	kind.text = _kind_line(item)
	kind.horizontal_alignment = align
	if compact:
		kind.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		kind.clip_text = true
	else:
		kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kind.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
	kind.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(kind)

	var desc := Label.new()
	desc.text = item.description if String(item.description) != "" else "A dropped relic."
	desc.horizontal_alignment = align
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if compact:
		desc.max_lines_visible = COMPACT_DESC_LINES
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	desc.add_theme_color_override("font_color", UITheme.TEXT)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc)

	var target: ItemData = item
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			select(target))
	return card

# Pick one of the offered items. Public so a test can choose without a click.
func select(item: ItemData) -> void:
	if not _items.has(item):
		return
	_selected = item
	_refresh_selection()

# Repaint the shelf and the Take button against whatever is currently selected —
# the one place the selection becomes pixels, so the highlight and the button's
# wording can never disagree about which relic is about to be taken.
func _refresh_selection() -> void:
	for card in _cards:
		var chosen: bool = card["item"] == _selected
		var tint: Color = UITheme.item_color(card["item"])
		(card["node"] as PanelContainer).add_theme_stylebox_override("panel",
			UITheme.flat(tint.lerp(UITheme.BG, 0.80 if chosen else 0.92), 8, 8,
				2 if chosen else 1, tint if chosen else UITheme.BORDER))
	if _take_btn != null and is_instance_valid(_take_btn):
		_take_btn.text = "✓  Take it" if _cards.is_empty() \
			else "✓  Take %s" % _selected.display_name

# The one line the tray never had room for: what kind of thing this is, so
# "passive" and "click it on the overworld" aren't left to be discovered.
func _kind_line(item: ItemData) -> String:
	var rarity: String = UITheme.item_class_name(item)
	match item.kind:
		ItemData.ItemKind.USABLE:
			return "%s · active — usable from your pack" % rarity
		ItemData.ItemKind.TRIGGERED:
			return "%s · triggered" % rarity
		_:
			if item.is_charged():
				return "%s · charges as you play" % rarity
			return "%s · passive" % rarity

# WHAT WAS TAKEN, said where the chest was. An answered chest used to vanish in
# one frame, and on a screen with three of them the only evidence of which was
# picked was that there were now two. The line stands in the chest's place, then
# fades and closes up; it owns its own tween, because this controller is freed on
# the same line that puts it there.
const TAKEN_HOLD_SECS := 0.55
const TAKEN_FADE_SECS := 0.35

func _flash_taken(body: Control) -> void:
	var slot: Node = body.get_parent()
	if slot == null or not slot.is_inside_tree():
		return
	var tint: Color = UITheme.item_color(_selected)
	var flash := Label.new()
	flash.text = "✓  Took %s" % _selected.display_name
	flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	flash.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	flash.add_theme_color_override("font_color", UITheme.SUCCESS.lerp(tint, 0.35))
	flash.custom_minimum_size = Vector2(0, body.size.y)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(flash)
	slot.move_child(flash, body.get_index())
	var tw := flash.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(TAKEN_HOLD_SECS)
	tw.tween_property(flash, "modulate:a", 0.0, TAKEN_FADE_SECS)
	tw.parallel().tween_property(flash, "custom_minimum_size:y", 0.0, TAKEN_FADE_SECS)
	tw.tween_callback(flash.queue_free)

# Public so a test can answer without a click.
# Whether this chest has been answered. The post-combat screen keeps every chest
# it mounted and asks each one, rather than dropping the answered ones from a list
# — the section frees its own body, so what is left on screen and what is left to
# decide have to be the same question asked of the same object.
func answered_already() -> bool:
	return _answered

# The row the answer buttons sit in, for a host with answers of its own to add.
func answer_row() -> BoxContainer:
	return _row

# Take this chest down WITHOUT an answer — a host re-rolling what it offers.
# Nothing is emitted: the chest was not left, it was replaced.
func discard() -> void:
	if _answered:
		return
	_answered = true
	if _body != null and is_instance_valid(_body):
		if _body.get_parent() != null:
			_body.get_parent().remove_child(_body)
		_body.queue_free()
		_body = null
	queue_free()

func take() -> void:
	_answer(true)

func leave() -> void:
	_answer(false)

func _answer(taken: bool) -> void:
	if _answered:
		return
	_answered = true
	answered.emit(taken, _selected if taken else null)
	finished.emit()
	# Take down whatever this chest actually put on screen: its own layer as a
	# modal, or just its section of the host's column when embedded — where the
	# rest of the column is somebody else's and must survive the answer.
	# Unparented before it is freed, because the NEXT chest in the queue is built
	# into that column on the very next line of the host's handler, and a
	# `queue_free` alone would stack the two for a frame.
	if _body != null and is_instance_valid(_body):
		if _body.get_parent() != null:
			if taken and _selected != null:
				_flash_taken(_body)
			_body.get_parent().remove_child(_body)
		_body.queue_free()
		_body = null
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

class_name PackStrip
extends RefCounted

# The pack, as a STRIP of small tokens above the board rather than a list of
# named rows beside it. A run ends up carrying a dozen relics and a dozen named
# rows is a column taller than the battlefield; at 34px a whole pack is two rows
# of art. The name, the rarity, what it does and how to fire it all move into the
# tooltip, which is where they were being read from anyway.
#
# An ACTIVE (USABLE / CHARGED) token is the button: clicking it fires the item
# when it can fire, and it wears a gold ring to say so. Passive and triggered
# items are just art. Actives are locked while a game is being reported — the
# report step is mid-resolve, so firing an item there would land between "played
# the game" and "said what happened".
#
# Split out of Overworld2 (docs/performance-backlog.md §1). It owns the strip's
# CONTENTS and nothing else: the page still owns the container it fills, still
# decides when to rebuild, and still owns the reading card a token opens —
# ItemInfoCard is a page-level modal, not strip furniture. Everything a token
# does on click goes back through one of the page's public verbs (`use_item`,
# `open_item_card`), which is what keeps the existing tests working through the
# move.
#
# `_page` is the Overworld2 that owns this strip, typed loosely because
# Overworld2 names PackStrip and two class_names that name each other are a
# cyclic reference Godot resolves badly.
var _page: Node = null
var _box: Control = null

const ITEM_TOKEN := 34
# Height of the Use button / charge battery that sits above an active item's tile.
const ITEM_USE_H := 14

func _init(page: Node, box: Control) -> void:
	_page = page
	_box = box

# Redraw the whole strip. `reporting` is passed in rather than read off the page
# because it is the page's phase to know — the strip only needs the one bit of it
# (an active item cannot be fired mid-report).
func rebuild(reporting: bool) -> void:
	if _box == null or not is_instance_valid(_box):
		return
	_page._clear(_box)
	# RELICS ONLY. Scrolls used to ride this strip beside them, which was right
	# while a scroll or two was all the loot in the game; pills and a per-game drop
	# made nine pieces ordinary (§4.3), and nine more tiles in a strip is a second
	# inventory wearing the first one's clothes. Loot has its own window now, opened
	# from the toggle at the end of this row.
	if GameState.inventory.is_empty():
		_box.add_child(_empty_note("nothing carried yet"))
		return
	for item in GameState.inventory:
		if not (item is ItemData):
			continue
		_box.add_child(_item_token(item, reporting))

# One item in the pack: the art tile, with its FIRING control above it when the
# item has one. Reading and spending are deliberately separate gestures — clicking
# the tile opens the item's card (§ItemInfoCard), and only the control above it
# ever spends a charge, so inspecting an item can't cost you one.
#
# A USABLE item gets a plain Use button. A CHARGED item gets a battery: one
# rectangle per charge, filling as it recharges, and at full it becomes the same
# Use button — so the bar answers "how long until I can" and "can I now" in the
# same strip of pixels.
func _item_token(item: ItemData, reporting: bool) -> Control:
	var tint: Color = UITheme.item_color(item)
	var active: bool = item.kind == ItemData.ItemKind.USABLE or item.is_charged()
	var ready: bool = active and GameState.can_fire_item(item) and fires_while_reporting(item, reporting)

	# Bottom-aligned so every art tile sits on one baseline whether or not the item
	# above it grew a Use button — a ragged row of tiles reads as a bug.
	var col := HoverBox.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	# The whole column answers the hover, not only the art tile — the Use button
	# and the battery override it with their own, so every pixel of an item says
	# something rather than the gap above the tile saying nothing.
	var card: Dictionary = item_hover(item, active, ready, reporting)
	HoverCard.attach(col, card)
	if active:
		col.add_child(_item_fire_control(item, ready, reporting))

	var tile := HoverPanel.new()
	var border: Color = UITheme.GOLD if ready else tint.lerp(UITheme.BG, 0.45)
	tile.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.86), 5, 3, 2 if ready else 1, border))
	HoverCard.attach(tile, card)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	col.add_child(tile)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(ITEM_TOKEN, ITEM_TOKEN)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(stack)
	var art := UITheme.crisp_tex(item.image, ITEM_TOKEN)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(art)
	var badge: Control = _counter_badge(item)
	if badge != null:
		stack.add_child(badge)

	var target_item: ItemData = item
	tile.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_page.open_item_card(target_item))
	return col

# An INCREMENTAL relic's counter, drawn in the bottom-right corner of its own art
# — Slay the Spire's relic counters, in the same corner and for the same reason:
# the number belongs to the picture of the thing, so a row of relics can be read
# in one glance without any of them growing a caption.
#
# Just the number it is ON, not "2/3". The threshold is what the item's text says
# and does not change; the count is the only part that moves, and a fraction
# doubles the pixels to say the same thing. Returns null for everything that is
# not incremental, which is almost every item.
#
# Public in spirit — the drop modal and the shop shelf draw the same tiles — but
# they show TEMPLATES, whose counter is always 0, so only the pack calls it.
func _counter_badge(item: ItemData) -> Control:
	var spec: Dictionary = item.incremental_spec()
	if spec.is_empty():
		return null
	var count: int = maxi(0, item.counter_value)
	var wrap := PanelContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Its own dark plate rather than bare text on the art: item art is 852 games'
	# worth of colours and a naked glyph is illegible over half of them.
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.06, 0.06, 0.09, 0.88), 3, 3, 1, UITheme.GOLD))
	var label := Label.new()
	label.text = str(count)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UITheme.GOLD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(label)
	return wrap

# CAN THIS ITEM FIRE WHILE A GAME IS IN PLAY? Every active used to be held back
# until the game had been reported, which is right for a USABLE consumable — those
# want a combat or an event around them (GameState.can_use_items) and there is
# neither while the player is off playing the real thing.
#
# It was wrong for a CHARGED active, and wrong in the way that shows: a full bar
# is the game telling you the thing is ready, and the strip then refused to fire
# it and offered "finish reporting this game first" as the reason. D6, Staff of
# Flame and Mom's Bottle of Pills are all charged, and all three do something the
# player wants precisely WHILE the board is live — a Scramble before the next
# offering, a Burn on the body walking toward them, a pill in hand for the run
# ahead. A charge that cannot be spent when it is full is a charge that is
# permanently one game behind.
#
# So a full bar means ready, on every screen. Nothing about the charge economy
# changes: it still empties on firing and refills on the same hooks.
static func fires_while_reporting(item: ItemData, reporting: bool) -> bool:
	return item.is_charged() or not reporting

# The control above an active item's tile. Full charge (or a Usable item, which
# has none) reads "Use" and fires; a partial charge is the battery, showing how
# many beats are left before it does.
func _item_fire_control(item: ItemData, ready: bool, reporting: bool) -> Control:
	if ready:
		var btn := Button.new()
		btn.text = "Use"
		btn.custom_minimum_size = Vector2(ITEM_TOKEN + 6, ITEM_USE_H)
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_stylebox_override("normal",
			UITheme.flat(Color(0.10, 0.22, 0.16, 0.95), 4, 1, 1, Color(0.4, 0.9, 0.6)))
		btn.add_theme_stylebox_override("hover",
			UITheme.flat(Color(0.14, 0.30, 0.21, 1.0), 4, 1, 1, Color(0.55, 1.0, 0.75)))
		btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = "Use %s" % item.display_name
		var target_item: ItemData = item
		btn.pressed.connect(func(): _page.use_item(target_item))
		return btn
	if item.is_charged():
		# `reporting` no longer holds a full bar back (see fires_while_reporting), so
		# the battery here is only ever a PARTIAL charge and says nothing about the
		# report step.
		return _charge_battery(item, false)
	# A Usable item that can't fire right now (mid-report) — the slot stays, greyed,
	# so the row doesn't reflow the moment a game is picked up.
	var idle := Button.new()
	idle.text = "Use"
	idle.disabled = true
	idle.custom_minimum_size = Vector2(ITEM_TOKEN + 6, ITEM_USE_H)
	idle.add_theme_font_size_override("font_size", 10)
	idle.tooltip_text = "Finish reporting this game first."
	return idle

# A charged item's meter: one rectangle per charge, filled left to right. Isaac's
# active-item bar turned on its side — the shape answers "how many beats left"
# without reading a number, and it sits where the Use button will be so the swap
# at full charge is the same strip changing state rather than a new control.
func _charge_battery(item: ItemData, reporting: bool) -> Control:
	var maxc: int = maxi(1, item.max_charge())
	var have: int = clampi(item.current_charge, 0, maxc)
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(ITEM_TOKEN + 6, ITEM_USE_H)
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.10, 0.10, 0.13, 0.9), 2, 2, 1, UITheme.BORDER))
	wrap.tooltip_text = "%s — %d/%d charged%s" % [item.display_name, have, maxc,
		"; finish reporting this game to use it" if reporting else ""]
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 1)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(cells)
	for i in range(maxc):
		var seg := PanelContainer.new()
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.custom_minimum_size = Vector2(3, ITEM_USE_H - 6)
		var filled: bool = i < have
		seg.add_theme_stylebox_override("panel", UITheme.flat(
			UITheme.GOLD.lerp(UITheme.BG, 0.15) if filled else Color(0.18, 0.18, 0.22, 0.9),
			1, 0, 0))
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cells.add_child(seg)
	return wrap

# Everything the old named row said, in the tooltip the token carries.
# The hover model for a carried item: the condensed version of the card its click
# opens (ItemInfoCard). Its art, its name in its class colour, what it does, and
# — for an active item — whether it can be fired right now, which is the one fact
# about a relic that changes what you do in the next second.
#
# Static, and named for the thing rather than for the tooltip, because the shop's
# shelf and the drop modal describe the same items and should come through here
# without needing a strip to ask. Overworld2.item_hover forwards to it.
static func item_hover(item: ItemData, active: bool, ready: bool, reporting: bool) -> Dictionary:
	var sub: String = UITheme.item_class_name(item)
	if item.is_charged():
		sub += "  ·  %d/%d charged" % [item.current_charge, item.max_charge()]
	var counter: Dictionary = item.incremental_spec()
	if not counter.is_empty():
		sub += "  ·  %d/%d" % [item.counter_value, int(counter["every"])]
	var note: String = ""
	if active:
		if ready:
			note = "▸ Click the tile above to use it."
		elif item.is_charged():
			note = "▸ Charging."
		elif reporting:
			note = "▸ Report this game first."
	var lines: Array = [String(item.description)]
	# ECHO CHAMBER NAMES WHAT IT IS HOLDING (§4.3). Its description says "the last
	# 3 Loot you used" and the hover is where "which three" belongs — a relic that
	# changes what spending loot MEANS is unreadable while the three are invisible.
	# The card its click opens draws them with art; this is the fast version.
	if int(item.echo_loot) > 0:
		lines.append(_echo_line(item))
	return {
		"title": item.display_name,
		"subtitle": sub,
		"accent": UITheme.item_color(item),
		"art": item.image,
		"lines": lines,
		"note": note,
	}

# The remembered loot, newest first — the order the echoes fire in.
static func _echo_line(item: ItemData) -> String:
	var memory: Array = LootSystem.used_memory()
	if memory.is_empty():
		return "Holding: nothing used yet."
	var names: Array = []
	for i in range(memory.size() - 1, maxi(0, memory.size() - maxi(1, int(item.echo_loot))) - 1, -1):
		names.append(LootSystem.display_name(memory[i]))
	return "Holding: %s." % ", ".join(PackedStringArray(names))

# The dim "there's nothing here" line the strip shows when the pack is empty.
func _empty_note(text: String) -> Label:
	var l := Label.new()
	l.text = "  (%s)" % text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return l

extends Control
# FullInventory — EVERYTHING THE RUN IS CARRYING, ON ONE SCREEN (the owner, 11 Nov
# 2026): the items, the loot pack, the stats and the resources.
#
# The page shows each of these where it is SPENT — relics above the board, the
# pack in its window, the verbs under the offering, Health and Gold in the header
# — which is right for playing and wrong for taking stock: there was no one place
# to look at a build. This is that place. Opened from the "Full" button beside
# the mini pack on the run page (`Overworld2.show_full_inventory`).
#
# It is the page's own state drawn again, so everything on it still works: an
# item opens its card, a piece of loot can be moved, turned and spent. Acting on
# one closes the screen first, because the item card and the Use screen are
# modals of their own and would open underneath it.
#
# Built in code and loaded BY PATH with no class_name, like every screen the page
# only opens on demand (test_page_load.gd).

signal closed

const WIDTH := 980.0
const ITEM_ART := 40
const ACCENT := Color(0.72, 0.62, 0.86)

var _page: Node = null
var _closing: bool = false
var _body: HBoxContainer = null

func setup(page: Node) -> void:
	_page = page
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Above the page's pinned header and the loot window, below the modals an
	# item or a piece of loot opens.
	z_index = 60
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	# A click on the dimmer closes; a wheel does not (it is a mouse button too).
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			close())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 14, 14, 2, ACCENT))
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	card.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Full Inventory"
	title.add_theme_font_size_override("font_size", UITheme.FONT_TITLE_LG)
	title.add_theme_color_override("font_color", ACCENT.lerp(Color.WHITE, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := UITheme.quiet_button("✕", Vector2.ZERO, UITheme.FONT_LEAD)
	x.tooltip_text = "Close (Esc)."
	x.pressed.connect(close)
	head.add_child(x)

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	box.add_child(_body)
	refill()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("backpack"):
		close()
		get_viewport().set_input_as_handled()

# Rebuild every column from the run's state. Public so a move in the pack can
# redraw the screen in place.
func refill() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_body.add_child(_character_column())
	_body.add_child(_items_column())
	_body.add_child(_loot_column())

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()

# --- pieces ---------------------------------------------------------------

func _section(text: String, tint: Color = ACCENT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	l.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.4))
	return l

func _line(text: String, tint: Color = UITheme.TEXT, tip: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	l.add_theme_color_override("font_color", tint)
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l

func _faint(text: String) -> Label:
	return _line(text, UITheme.TEXT_FAINT)

func _column(width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	col.custom_minimum_size = Vector2(width, 0)
	return col

# WHO, HOW STRONG, AND WHAT THEY HAVE TO SPEND: the character and level, the
# stats, the resources, then the statuses and curses on the player.
func _character_column() -> Control:
	var col := _column(250)
	var ch: CharacterData = Data.get_character2(GameState.character_id)
	if ch != null:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITheme.GAP)
		row.add_child(UITheme.crisp_tex(ch.shown_portrait(), 64))
		var who := VBoxContainer.new()
		who.add_theme_constant_override("separation", UITheme.GAP_HAIR)
		var name := Label.new()
		name.text = ch.display_name
		name.add_theme_font_size_override("font_size", UITheme.FONT_HEAD)
		who.add_child(name)
		who.add_child(_line("Level %d" % maxi(1, GameState.player_level), UITheme.GOLD))
		if Fracture.level() > 0:
			who.add_child(_line("Fracture %d" % Fracture.level(), Fracture.COLOR))
		row.add_child(who)
		col.add_child(row)
		if ch.level_up_condition != "":
			var how := _line("Levels up by: %s" % ch.level_up_condition, UITheme.TEXT_DIM)
			how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			how.custom_minimum_size = Vector2(250, 0)
			col.add_child(how)

	col.add_child(_section("Stats"))
	col.add_child(_line("♥  Health  %d / %d" % [GameState.hp, GameState.max_hp],
		Color(1.0, 0.62, 0.62), "Health. At zero the run ends."))
	if GameState.bonus_shields > 0:
		col.add_child(_line("◆  %s" % GameState.shields_text(GameState.bonus_shields),
			BattlefieldView.SHIELD_BLUE, "Shields that never expire."))
	var luck: int = Stats.get_value(&"luck")
	col.add_child(_line("🍀  Luck  %d" % luck, Color(0.5, 0.85, 0.5),
		"Every roll in the run gets that many coin flips, and the better result is kept."))

	col.add_child(_section("Resources"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UITheme.GAP_SECTION)
	grid.add_theme_constant_override("v_separation", UITheme.GAP_TIGHT)
	col.add_child(grid)
	for r in resources():
		grid.add_child(_line("%s  %s  %d" % [r["glyph"], r["name"], int(r["count"])],
			r["tint"] if int(r["count"]) > 0 else UITheme.TEXT_FAINT, String(r["tip"])))

	col.add_child(_section("Statuses"))
	var held: Array = GameState.status_list()
	if held.is_empty():
		col.add_child(_faint("None."))
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", UITheme.GAP_TIGHT)
		flow.add_theme_constant_override("v_separation", UITheme.GAP_TIGHT)
		col.add_child(flow)
		for row in held:
			flow.add_child(_status_chip(row))

	col.add_child(_section("Curses"))
	if GameState.curse_goals.is_empty():
		col.add_child(_faint("None."))
	for c in GameState.curse_goals:
		var cd: CurseData2 = Data.get_curse2(StringName(c.get("curse", &"")))
		if cd == null:
			continue
		var left: int = int(c.get("games_left", -1))
		var text: String = cd.display_name if left < 0 \
			else "%s  (%d %s left)" % [cd.display_name, left, Plural.word(left, "game")]
		col.add_child(_line(text, UITheme.DANGER.lerp(Color.WHITE, 0.3),
			"%s\n%s" % [cd.condition, cd.penalty_text]))
	return col

# Every counted thing the run spends, in one list. Static and public so a test can
# hold the screen to it.
static func resources() -> Array:
	return [
		{"glyph": "◉", "name": "Gold", "count": GameState.gold, "tint": UITheme.COIN_GOLD,
			"tip": "Spent at shops. It does not carry over."},
		{"glyph": "🗝", "name": "Keys", "count": GameState.keys, "tint": UITheme.RIFT,
			"tip": "Rift Keys. Taking a rift card spends one."},
		{"glyph": "✸", "name": "Bombs", "count": GameState.bombs, "tint": UITheme.DANGER,
			"tip": "Blow up an enemy, or a square of the board."},
		{"glyph": "💨", "name": "Push", "count": GameState.push, "tint": UITheme.ACCENT,
			"tip": "Shove an enemy back across the board."},
		{"glyph": "⛏", "name": "Bash", "count": GameState.bash, "tint": Color(0.95, 0.6, 0.3),
			"tip": "Destroy an offered game outright."},
		{"glyph": "⚡", "name": "Dash", "count": GameState.dash_charges, "tint": Color(0.45, 0.7, 1.0),
			"tip": "Travel to any connected game."},
		{"glyph": "⚗", "name": "Transmute", "count": GameState.transmute, "tint": UITheme.ACCENT,
			"tip": "Swap an offered game for one off the map."},
		{"glyph": "🎲", "name": "Scramble", "count": GameState.scramble, "tint": UITheme.GOLD,
			"tip": "Redraw the whole offering."},
	]

func _status_chip(row: Dictionary) -> Control:
	var sd: StatusData = row["status"]
	var stacks: int = int(row["stacks"])
	var good: bool = sd.is_bonus(StatusData.PLAYER) or sd.is_goal(StatusData.PLAYER)
	var tint: Color = UITheme.GOLD if good else UITheme.DANGER
	var chip := HoverPanel.new()
	chip.add_theme_stylebox_override("panel",
		UITheme.flat(tint.lerp(UITheme.BG, 0.75), 4, 3, 1, tint.lerp(UITheme.BORDER, 0.35)))
	HoverCard.attach(chip, sd.hover_card(StatusData.PLAYER, stacks, false,
		int(row.get("games", 0)), false))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(r)
	if sd.image != null:
		r.add_child(UITheme.crisp_tex(sd.image, 18))
	var l := _line("%s %d" % [sd.display_name, stacks], tint)
	l.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	r.add_child(l)
	return chip

# EVERY ITEM, with its name beside its art — the strip on the page is art only.
func _items_column() -> Control:
	var col := _column(330)
	var count: int = GameState.inventory.size() + GameState.smelted_loot.size()
	col.add_child(_section("Items  (%d)" % count))
	if count == 0:
		col.add_child(_faint("No relics yet."))
		return col
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(330, 440)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UITheme.GAP_TIGHT)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for item in GameState.inventory:
		if item is ItemData:
			list.add_child(_item_row(item))
	for entry in GameState.smelted_loot:
		if entry is Dictionary:
			list.add_child(_smelted_row(entry))
	return col

func _item_row(item: ItemData) -> Control:
	var tint: Color = UITheme.item_color(item)
	var active: bool = item.kind == ItemData.ItemKind.USABLE or item.is_charged()
	var row := HoverButton.new()
	row.custom_minimum_size = Vector2(0, ITEM_ART + 8)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("normal",
		UITheme.flat(tint.lerp(UITheme.BG, 0.88), 5, 4, 1, tint.lerp(UITheme.BG, 0.55)))
	row.add_theme_stylebox_override("hover",
		UITheme.flat(tint.lerp(UITheme.BG, 0.74), 5, 4, 1, tint))
	row.add_theme_stylebox_override("pressed",
		UITheme.flat(tint.lerp(UITheme.BG, 0.74), 5, 4, 1, tint))
	HoverCard.attach(row, PackStrip.item_hover(item, active,
		active and GameState.can_fire_item(item), false))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", UITheme.GAP)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	row.add_child(inner)
	var art := UITheme.crisp_tex(item.image, ITEM_ART)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(art)
	var name := _line(item.display_name, tint.lerp(Color.WHITE, 0.45))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	inner.add_child(name)
	if item.is_charged():
		var c := _line("%d / %d" % [clampi(item.current_charge, 0, item.max_charge()), item.max_charge()], UITheme.GOLD)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(c)
	var target: ItemData = item
	row.pressed.connect(func():
		close()
		_page.open_item_card(target))
	return row

func _smelted_row(entry: Dictionary) -> Control:
	var row := HoverPanel.new()
	row.add_theme_stylebox_override("panel",
		UITheme.flat(Color(1.0, 0.7, 0.35).lerp(UITheme.BG, 0.86), 5, 4, 1,
			Color(1.0, 0.7, 0.35).lerp(UITheme.BG, 0.5)))
	HoverCard.attach(row, LootSystem.hover_card(entry))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", UITheme.GAP)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(inner)
	inner.add_child(LootSystem.art_tex(entry, ITEM_ART))
	inner.add_child(_line("%s  (smelted)" % LootSystem.display_name(entry)))
	return row

# THE PACK, at full size and live: drag to move, R to turn, and each piece
# carries the button that spends it.
func _loot_column() -> Control:
	var col := _column(0)
	col.add_child(_section("Loot  %d / %d" % [GameState.loot_items.size(),
		GameState.loot_capacity()]))
	var grid := LootGrid.new()
	grid.allow_reorder = true
	grid.show_use = true
	grid.use_requested.connect(func(i: int):
		close()
		_page.use_loot(i))
	grid.moved.connect(func(from: int, to: int, rot: int):
		if GameState.move_loot(from, to, rot):
			_page.refresh_loot_window()
			refill.call_deferred())
	grid.rebuild()
	col.add_child(grid)
	return col

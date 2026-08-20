class_name LootWindow
extends RefCounted

# The LOOT WINDOW — the pack's nine pieces of loot, as a 3x3 grid that opens
# OVER THE LEFT COLUMN (docs/games-first-redesign.md §4.3).
#
# Loot used to ride the pack strip as tokens, one per scroll, which worked while
# a scroll or two was all there was. Pills doubled the kinds and the per-game
# drop made carrying nine of them ordinary, and nine tiles wedged in beside a
# run's relics is not a strip — it is a second inventory pretending to be one.
#
# IT IS A PANEL OVER THE PAGE, NOT A ROW INSIDE THE PACK. Opening it used to grow
# the pack panel downward, which pushed the board and re-flowed the right column
# every time the player looked at what they were carrying — the window cost the
# page a relayout for the crime of being opened. It floats over the LEFT column
# now, on top of the offering: that half of the page is the one you are not
# reading while you decide which pill to take, and nothing under it moves.
#
# THE GRID IS ALWAYS NINE. Nine is the cap, and an inventory that only draws what
# is in it says nothing about the room left — the empty slots are the count. They
# are also what keeps the thing a GRID rather than a row that wraps: three tiles
# in a 3x3 read as three of nine, while three tiles in a flow row read as all
# there is.
#
# Each filled cell draws the art, the name, and a Use button, and carries the same
# hover card an item or an enemy does. Use goes back through the page's `use_loot`,
# which opens the one modal both kinds share (LootUseModal).
#
# Split out of Overworld2 the way PackStrip was (docs/performance-backlog.md §1):
# it owns the CONTENTS of the toggle and the panel, and the page owns the mounting
# and the positioning (`mount_loot_overlay` / `unmount_loot_overlay`). `_page` is
# the Overworld2 that owns them, typed loosely because Overworld2 names this class
# and two class_names that name each other are a cyclic reference Godot resolves
# badly.
var _page: Node = null
var _button_host: Control = null

# Open across rebuilds, and across a report: the window is a place the player is
# looking, and slamming it shut every time the page refreshes would make it
# unusable exactly when loot matters.
var open: bool = false

const COLS := 3
# The same tile as a relic's on the pack strip (PackStrip.ITEM_TOKEN). A piece of
# loot and a relic are both "a thing you are carrying", and two art sizes for them
# read as two different kinds of importance rather than as two kinds of thing.
const CELL_ART := PackStrip.ITEM_TOKEN
# Every cell is this wide, filled or empty, so the grid stays a grid: a column
# that sized itself to its contents would jog left and right as pills are spent.
const CELL_W := CELL_ART + 26
const ACCENT := Color(0.72, 0.62, 0.86)

func _init(page: Node, button_host: Control) -> void:
	_page = page
	_button_host = button_host

# Redraw the toggle and, when open, the panel. `reporting` is passed in rather
# than read off the page for the same reason PackStrip takes it: it is the page's
# phase to know, and the window needs exactly one bit of it — loot cannot be spent
# mid-report, when the run is between "played the game" and "said what happened".
func rebuild(reporting: bool) -> void:
	if _button_host == null or not is_instance_valid(_button_host):
		return
	_page._clear(_button_host)
	_button_host.add_child(_toggle_button())
	# Rebuilt from scratch rather than refreshed in place: the page mounts and
	# positions it, and a panel that survived a rebuild would have to be re-measured
	# against a left column that may have changed size anyway.
	_page.unmount_loot_overlay()
	if open:
		_page.mount_loot_overlay(_panel(reporting))

# The toggle. It carries the COUNT because that is the number the player is
# actually tracking — nine is the cap, and a drop that cannot be taken is the
# thing the count is warning about.
func _toggle_button() -> Button:
	var btn := Button.new()
	var held: int = GameState.loot_items.size()
	btn.text = "%s Loot %d/%d %s" % [
		"💊" if _has_pills() else "📜", held, GameState.LOOT_CAPACITY,
		"▾" if open else "▸"]
	btn.add_theme_font_size_override("font_size", 12)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "Scrolls and pills you're carrying (max %d).\nClick to %s." % [
		GameState.LOOT_CAPACITY, "close" if open else "open"]
	btn.add_theme_stylebox_override("normal",
		UITheme.flat(ACCENT.lerp(UITheme.BG, 0.72), 5, 6, 1, ACCENT.lerp(UITheme.BG, 0.4)))
	btn.add_theme_stylebox_override("hover",
		UITheme.flat(ACCENT.lerp(UITheme.BG, 0.55), 5, 6, 1, ACCENT))
	btn.pressed.connect(func():
		open = not open
		_page.refresh_loot_window())
	return btn

func _has_pills() -> bool:
	return not GameState.loot_pills().is_empty()

# The floating panel: a heading with its own close button, then the 3x3.
# Opaque (not the page's translucent PANEL) because it is standing on top of the
# offering — a see-through inventory over a wall of cover art is unreadable.
func _panel(reporting: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG.lerp(ACCENT, 0.06), 12, 12, 2, ACCENT.lerp(UITheme.BG, 0.35)))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title := Label.new()
	title.text = "%s  Loot  —  %d / %d carried" % [
		"💊" if _has_pills() else "📜", GameState.loot_items.size(), GameState.LOOT_CAPACITY]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", ACCENT.lerp(Color.WHITE, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 13)
	close.tooltip_text = "Close the loot window."
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(func():
		open = false
		_page.refresh_loot_window())
	head.add_child(close)

	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	# ALWAYS nine, filled then empty. The empties are how the window says how much
	# room is left, which is the fact the cap makes interesting.
	for i in range(GameState.LOOT_CAPACITY):
		var entry = GameState.loot_items[i] if i < GameState.loot_items.size() else null
		grid.add_child(_cell(i, entry, reporting) if entry is Dictionary else _empty_cell())

	if reporting:
		var note := Label.new()
		note.text = "Finish reporting this game before spending any."
		note.add_theme_font_size_override("font_size", 10)
		note.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)
	return panel

# One piece of loot: art, name, Use. The whole cell answers the hover, so the gap
# under the name says something rather than nothing.
func _cell(index: int, entry: Dictionary, reporting: bool) -> Control:
	var col := HoverBox.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(CELL_W, 0)
	HoverCard.attach(col, hover_card(entry))

	var tile := HoverPanel.new()
	# SHRINK_CENTER so the tile hugs the art at exactly CELL_ART. Without it the
	# panel stretches to the cell's width and drags the art with it, and a pill ends
	# up bigger than a relic while both are asking for the same number.
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var known: bool = LootSystem.is_identified(entry)
	# A known piece wears its accent at full strength; an unknown one is dimmed to
	# the panel, which is the same "you have not learned this yet" the name says.
	tile.add_theme_stylebox_override("panel", UITheme.flat(
		ACCENT.lerp(UITheme.BG, 0.86), 5, 3, 1,
		ACCENT.lerp(UITheme.BG, 0.35 if known else 0.7)))
	HoverCard.attach(tile, hover_card(entry))
	col.add_child(tile)
	var art := UITheme.crisp_tex(LootSystem.art_texture(entry), CELL_ART)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(art)

	var name := Label.new()
	name.text = LootSystem.display_name(entry)
	name.add_theme_font_size_override("font_size", 9)
	name.add_theme_color_override("font_color",
		UITheme.TEXT if known else UITheme.TEXT_FAINT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size = Vector2(CELL_W, 0)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name)

	var use := Button.new()
	use.text = "Use"
	use.disabled = reporting
	use.custom_minimum_size = Vector2(CELL_W, 14)
	use.add_theme_font_size_override("font_size", 9)
	use.tooltip_text = "Finish reporting this game first." if reporting \
		else "Spend it — this is how an unknown one gets identified."
	use.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	use.pressed.connect(func(): _page.use_loot(index))
	col.add_child(use)
	return col

# An empty slot: the same footprint as a filled cell, drawn as the outline of one.
# Room left, said as a picture rather than as a fraction.
func _empty_cell() -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(CELL_W, CELL_ART + 8)
	# FILL, so an empty slot is as tall as the filled cells sharing its row. Left to
	# shrink it hugged its own minimum and sat against the top of the row, which
	# made a half-full grid look ragged rather than half full.
	slot.size_flags_vertical = Control.SIZE_FILL
	slot.add_theme_stylebox_override("panel", UITheme.flat(
		Color(0, 0, 0, 0.18), 5, 3, 1, ACCENT.lerp(UITheme.BG, 0.85)))
	slot.tooltip_text = "Empty — room for one more."
	return slot

# The hover model for a carried piece of loot, in the shape every other hover on
# the page uses. Static and public because the drop modal describes the same
# piece and should come through here rather than growing its own wording.
static func hover_card(entry: Dictionary) -> Dictionary:
	var known: bool = LootSystem.is_identified(entry)
	var kind: String = "Pill" if String(entry.get("type", "")) == "pill" else "Scroll"
	if bool(entry.get("horse", false)):
		kind = "Horse Pill"
	var sub: String = kind
	if known and LootSystem.preference(entry) != "":
		sub += "  ·  %s" % LootSystem.preference(entry)
	return {
		"title": LootSystem.display_name(entry),
		"subtitle": sub,
		"accent": ACCENT,
		"art": LootSystem.art_texture(entry),
		"lines": [LootSystem.description(entry)],
		"note": "" if known else "▸ Using it is how you learn what it is.",
	}

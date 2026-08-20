class_name LootWindow
extends RefCounted

# The LOOT WINDOW — the pack's nine pieces of loot, in a 3x3 grid behind a
# toggle beside the relics (docs/games-first-redesign.md §4.3).
#
# Loot used to ride the pack strip as tokens, one per scroll, which worked while
# a scroll or two was all there was. Pills doubled the kinds and the per-game
# drop made carrying nine of them ordinary, and nine tiles wedged in beside a
# run's relics is not a strip — it is a second inventory pretending to be one.
# So loot moved out into a window of its own, and the strip went back to being
# the relics.
#
# THE TOGGLE IS A LABEL AND AN ARROW, not a bar: the button says how full the
# pack is (`💊 Loot 4/9`) and which way the window is about to go, and that is the
# whole control. Opening it is free and closing it costs nothing, so it does not
# need to be a panel that is always in the way.
#
# Each cell draws the art, the name, and a Use button, and carries the same hover
# card an item or an enemy does — an unidentified piece says so there rather than
# lying about what it does. Use goes back through the page's `use_loot`, which
# opens the one modal both kinds share (LootUseModal).
#
# Split out of Overworld2 the way PackStrip was (docs/performance-backlog.md §1):
# it owns the CONTENTS of the toggle and the grid, and nothing else. `_page` is
# the Overworld2 that owns them, typed loosely because Overworld2 names this class
# and two class_names that name each other are a cyclic reference Godot resolves
# badly.
var _page: Node = null
var _button_host: Control = null
var _grid_host: Control = null

# Open across rebuilds, and across a report: the window is a place the player is
# looking, and slamming it shut every time the page refreshes would make it
# unusable exactly when loot matters.
var open: bool = false

const COLS := 3
const CELL_ART := 40
const ACCENT := Color(0.72, 0.62, 0.86)

func _init(page: Node, button_host: Control, grid_host: Control) -> void:
	_page = page
	_button_host = button_host
	_grid_host = grid_host

# Redraw the toggle and (when open) the grid. `reporting` is passed in rather than
# read off the page for the same reason PackStrip takes it: it is the page's phase
# to know, and the window needs exactly one bit of it — loot cannot be spent
# mid-report, when the run is between "played the game" and "said what happened".
func rebuild(reporting: bool) -> void:
	if _button_host == null or not is_instance_valid(_button_host):
		return
	_page._clear(_button_host)
	_button_host.add_child(_toggle_button())
	if _grid_host == null or not is_instance_valid(_grid_host):
		return
	_page._clear(_grid_host)
	_grid_host.visible = open
	if not open:
		return
	if GameState.loot_items.is_empty():
		_grid_host.add_child(_empty_note())
		return
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_grid_host.add_child(grid)
	for i in range(GameState.loot_items.size()):
		var entry = GameState.loot_items[i]
		if entry is Dictionary:
			grid.add_child(_cell(i, entry, reporting))

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

# One piece of loot: art, name, Use. The whole cell answers the hover, so the gap
# under the name says something rather than nothing.
func _cell(index: int, entry: Dictionary, reporting: bool) -> Control:
	var col := HoverBox.new()
	col.add_theme_constant_override("separation", 2)
	HoverCard.attach(col, hover_card(entry))

	var tile := HoverPanel.new()
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
	name.custom_minimum_size = Vector2(CELL_ART + 22, 0)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name)

	var use := Button.new()
	use.text = "Use"
	use.disabled = reporting
	use.custom_minimum_size = Vector2(CELL_ART + 22, 14)
	use.add_theme_font_size_override("font_size", 9)
	use.tooltip_text = "Finish reporting this game first." if reporting \
		else "Spend it — this is how an unknown one gets identified."
	use.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	use.pressed.connect(func(): _page.use_loot(index))
	col.add_child(use)
	return col

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

func _empty_note() -> Label:
	var l := Label.new()
	l.text = "  (no loot carried)"
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return l

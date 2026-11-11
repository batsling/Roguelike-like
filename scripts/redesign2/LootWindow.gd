class_name LootWindow
extends RefCounted

# The LOOT WINDOW — the pack's nine pieces of loot, as a 3x3 grid that opens
# OVER THE BOARD (docs/games-first-redesign.md §4.3).
#
# Loot used to ride the pack strip as tokens, one per scroll, which worked while
# a scroll or two was all there was. Pills doubled the kinds and the per-game
# drop made carrying nine of them ordinary, and nine tiles wedged in beside a
# run's relics is not a strip — it is a second inventory pretending to be one.
#
# IT IS A PANEL OVER THE PAGE, NOT A ROW INSIDE THE PACK. Opening it used to grow
# the pack panel downward, which pushed the board and re-flowed the right column
# every time the player looked at what they were carrying — the window cost the
# page a relayout for the crime of being opened. It floats over the BOARD now: the
# pack strip stands on top of the board, so the window drops out of its own button
# rather than appearing across the page from it, and the board is a picture of what
# is chasing you, which does not change while you decide which pill to take.
#
# THE GRID IS ALWAYS NINE, and it is LootGrid — the same class the drop modal
# draws, so the pack you rearrange and the pack you drop a new piece into are one
# widget rather than two that have to be kept looking alike. Pieces drag between
# slots, each carries the button that spends it, and clicking one opens its card.
#
# WHAT YOU HAVE LEARNED lives here too, behind the "Known this run" line at the
# foot. A pill's identity belongs to a COLOUR and only for this run, and until now
# the only place that knowledge existed was a toast that had already scrolled away
# — so a player who learned that green is Bad Trip on game three had nowhere to go
# and check on game eleven. That is the whole identification minigame with no
# record of itself. It is folded shut by default: it is a thing you consult, not a
# thing you read every time you open the pack.
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
# Whether the "Known this run" fold at the foot is unfolded. It lives on
# LootDiscoveries because the reward screen draws the same section, and a fold that
# was shut here and open there would be two answers to one question; this stays as
# the window's own name for it.
var discoveries_open: bool:
	get:
		return LootDiscoveries.open
	set(value):
		LootDiscoveries.open = value

const ACCENT := Color(0.72, 0.62, 0.86)

func _init(page: Node, button_host: Control) -> void:
	_page = page
	_button_host = button_host

# Redraw the toggle and, when open, the panel. `reporting` is passed in rather
# than read off the page for the same reason PackStrip takes it: it is the page's
# phase to know, and the window needs exactly one bit of it — loot cannot be binned
# mid-report, when the run is between "played the game" and "said what happened".
func rebuild(reporting: bool) -> void:
	if _button_host == null or not is_instance_valid(_button_host):
		return
	_page._clear(_button_host)
	_button_host.add_child(_toggle_button())
	_button_host.add_child(_side_column())
	# Rebuilt from scratch rather than refreshed in place: the page mounts and
	# positions it, and a panel that survived a rebuild would have to be re-measured
	# against a board that may have changed size anyway.
	_page.unmount_loot_overlay()
	if open:
		_page.mount_loot_overlay(_panel(reporting))

# THE MINI PACK (the owner, 11 Nov 2026): the loot inventory, drawn small, beside
# the item inventory — the pack's real shape (the 3x3 and every bag) with each
# piece's art where it sits. It replaced the purple "Loot" bar that used to be the
# foot of the pack panel. It is a picture, not a surface: clicking it opens the
# window, where pieces are moved and spent. The count rides beside it, and it is
# still THE ONLY THING ON THE PAGE THAT SAYS YOU ARE CARRYING LOOT while the
# window is shut.
func _toggle_button() -> Control:
	var held: int = GameState.loot_items.size()
	var full: bool = GameState.loot_is_full()
	# Full is a state worth colouring: a pack with no room turns the next payout
	# into "leave it", and the moment to know that is before the drop asks.
	var tint: Color = UITheme.DANGER if full else ACCENT

	var btn := Button.new()
	btn.name = "MiniPackButton"
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.size_flags_vertical = Control.SIZE_SHRINK_END
	btn.tooltip_text = "Scrolls and pills you're carrying (%d of %d).\nClick or Tab to %s." % [
		held, GameState.loot_capacity(), "close" if open else "open"]
	if full:
		btn.tooltip_text += "\nFull — the next piece of loot has nowhere to go."
	btn.add_theme_stylebox_override("normal",
		UITheme.flat(tint.lerp(UITheme.BG, 0.8 if not open else 0.6), 5, 2, 1, tint.lerp(UITheme.BG, 0.4)))
	btn.add_theme_stylebox_override("hover",
		UITheme.flat(tint.lerp(UITheme.BG, 0.55), 5, 2, 1, tint))
	btn.add_theme_stylebox_override("pressed",
		UITheme.flat(tint.lerp(UITheme.BG, 0.55), 5, 2, 1, tint))
	btn.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 5, 2, 0))
	btn.pressed.connect(func():
		open = not open
		_page.refresh_loot_window())
	var mini := MiniPack.new()
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini.position = Vector2(MINI_PAD, MINI_PAD)
	btn.add_child(mini)
	btn.custom_minimum_size = mini.wanted() + Vector2(MINI_PAD, MINI_PAD) * 2.0
	return btn

# What stands beside the mini pack: how full it is, and the way into the FULL
# INVENTORY — items, loot, stats and resources on one screen.
func _side_column() -> Control:
	var full: bool = GameState.loot_is_full()
	var tint: Color = UITheme.DANGER if full else ACCENT
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.add_child(_bar_label("Loot %d/%d" % [GameState.loot_items.size(),
		GameState.loot_capacity()], tint, full))
	var all := UITheme.quiet_button("Full ▸", Vector2.ZERO, UITheme.FONT_SMALL)
	all.name = "FullInventoryButton"
	all.tooltip_text = "Full inventory: every item, your loot, your stats and your resources."
	all.pressed.connect(func(): _page.show_full_inventory())
	col.add_child(all)
	return col

const MINI_PAD := 3.0

# The pack at thumbnail size. Drawn rather than built out of LootSlots: a slot is
# a panel, a body, a name and a button, and none of that survives being 11px wide.
class MiniPack extends Control:
	# Tall enough for the 3x3 at CELL, and a pack that has grown bags shrinks its
	# cells to stay inside the same box, down to CELL_MIN.
	const CELL := 11.0
	const CELL_MIN := 4.0
	const SEP := 1.0
	const BOX := Vector2(84.0, 35.0)

	func cell_px() -> float:
		var n: Vector2i = GameState.pack_bounds().size
		var by_h: float = (BOX.y + SEP) / maxf(1.0, n.y) - SEP
		var by_w: float = (BOX.x + SEP) / maxf(1.0, n.x) - SEP
		return clampf(floorf(minf(by_h, by_w)), CELL_MIN, CELL)

	func wanted() -> Vector2:
		var n: Vector2i = GameState.pack_bounds().size
		var c: float = cell_px()
		return Vector2(n) * (c + SEP) - Vector2(SEP, SEP)

	func _ready() -> void:
		size = wanted()
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	func _rect_of(cell: Vector2i, origin: Vector2i, c: float) -> Rect2:
		return Rect2(Vector2(cell - origin) * (c + SEP), Vector2(c, c))

	func _draw() -> void:
		var bounds: Rect2i = GameState.pack_bounds()
		var c: float = cell_px()
		var layout: Array = GameState.loot_layout()
		var done: Dictionary = {}
		for slot in range(GameState.loot_capacity()):
			var r: Rect2 = _rect_of(GameState.pack_cell_of(slot), bounds.position, c)
			var in_bag: bool = GameState.bag_at_slot(slot) >= 0
			var base: Color = LootGrid.BAG_TINT if in_bag else LootWindow.ACCENT
			var index: int = int(layout[slot]) if slot < layout.size() else -1
			draw_rect(r, base.lerp(UITheme.BG, 0.55 if index >= 0 else 0.78))
			if index < 0 or done.has(index) or index >= GameState.loot_items.size():
				continue
			done[index] = true
			var entry = GameState.loot_items[index]
			if not (entry is Dictionary):
				continue
			# A big piece is drawn once, over every cell it covers.
			var span: Rect2 = r
			for s in GameState.loot_slots_of(index):
				span = span.merge(_rect_of(GameState.pack_cell_of(int(s)), bounds.position, c))
			var tex: Texture2D = LootSystem.art_texture(entry)
			if tex == null:
				draw_rect(span.grow(-1.0), base.lerp(Color.WHITE, 0.5))
				continue
			var ts: Vector2 = tex.get_size()
			var k: float = minf(span.size.x / maxf(1.0, ts.x), span.size.y / maxf(1.0, ts.y))
			var fit: Vector2 = ts * k
			draw_texture_rect(tex, Rect2(span.position + (span.size - fit) * 0.5, fit), false)

func _bar_label(text: String, tint: Color, loud: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	l.add_theme_color_override("font_color", tint.lerp(Color.WHITE, 0.6 if loud else 0.4))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _has_pills() -> bool:
	return not GameState.loot_pills().is_empty()

# Destroy the piece at `index`, once the player has said so twice — see
# LootTrash.confirm for why it is asked at all and why it is asked from a layer of
# its own rather than from this panel.
func _discard(index: int) -> void:
	if index < 0 or index >= GameState.loot_items.size():
		return
	var piece_name: String = LootSystem.display_name(GameState.loot_items[index])
	LootTrash.confirm(_page, piece_name, func():
		GameState.discard_loot_at(index)
		GameLog.add("Destroyed %s." % piece_name, UITheme.DANGER)
		_page._refresh_items())

# An attached bag dragged onto the bin (docs/loot-passives.md §6): only an empty
# one that holds up no other bag gets this far, and it asks first like a piece.
func _discard_bag(bag: int) -> void:
	if not GameState.can_remove_bag(bag):
		return
	var bag_name: String = LootSystem.display_name(
		{"type": "bag", "id": GameState.pack_bags[bag].get("id", "")})
	LootTrash.confirm(_page, bag_name, func():
		if GameState.remove_bag(bag).is_empty():
			return
		GameLog.add("Destroyed %s." % bag_name, UITheme.DANGER)
		_page._refresh_items())

# The floating panel: a heading with its own close button, the 3x3, and the
# foldable record of what the run has learned. Opaque (not the page's translucent
# PANEL) because it is standing on top of the board — a see-through inventory over
# a battlefield is unreadable.
func _panel(reporting: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(UITheme.BG.lerp(ACCENT, 0.06), 12, 12, 2, ACCENT.lerp(UITheme.BG, 0.35)))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UITheme.GAP)
	box.add_child(head)
	var title := Label.new()
	title.text = "%s  Loot  %d/%d" % [
		"💊" if _has_pills() else "📜", GameState.loot_items.size(), GameState.loot_capacity()]
	# HOW TO USE IT, ON HOVER. It used to be up to three paragraphs under the grid,
	# read once and then in the way every time the pack was opened after.
	title.tooltip_text = _how_to(reporting)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	title.add_theme_color_override("font_color", ACCENT.lerp(Color.WHITE, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UITheme.quiet_button("✕", Vector2.ZERO, UITheme.FONT_TEXT)
	close.tooltip_text = "Close the loot window."
	close.pressed.connect(func():
		open = false
		_page.refresh_loot_window())
	head.add_child(close)

	var grid := LootGrid.new()
	# A PICK UNDER WAY (OwnedPick.gd) turns the pack into the answer: the pieces it
	# can take light up, a click chooses, and nothing moves, spends or is binned
	# until it is answered.
	var pick = _page.owned_pick() if _page.has_method("owned_pick") else null
	grid.pick = pick
	grid.allow_reorder = pick == null
	grid.show_use = pick == null
	# REARRANGING IS NEVER LOCKED, only BINNING is (§4.3). The report step can be an
	# hour of someone else's game, and it is exactly when a player wants to sort a
	# pack they cannot spend out of in the order it is in. Moving and turning a piece
	# changes nothing the report reads; throwing one away is a decision about the run
	# and still waits until the game has been said to be over.
	grid.allow_discard = not reporting and pick == null
	grid.use_requested.connect(func(i: int): _page.use_loot(i))
	grid.moved.connect(func(from: int, to: int, rot: int):
		if GameState.move_loot(from, to, rot):
			_page.refresh_loot_window())
	grid.discard_requested.connect(_discard)
	grid.bag_discard_requested.connect(_discard_bag)
	grid.rebuild()
	box.add_child(grid)

	# THE BIN, on the same terms as the drop modal's (§4.3). Spending a piece is not
	# the same as being rid of one: a pack holding three known-Negative pills is full
	# of loot the run will never willingly use, and reading the Amnesia scroll to
	# make room is a worse answer than throwing it away. Hidden mid-report —
	# nothing can leave the pack then, even though it can be rearranged.
	if not reporting and pick == null \
			and (not GameState.loot_items.is_empty() or not GameState.pack_bags.is_empty()):
		var bin := LootTrash.new()
		bin.grid = grid
		box.add_child(bin)

	# WHAT YOU HAVE LEARNED, on both surfaces that draw the pack — the reward screen
	# builds the same section, and the fold is shared so it cannot be shut here and
	# open there (LootDiscoveries.open).
	box.add_child(LootDiscoveries.build(func(): _page.refresh_loot_window()))
	return panel

# The panel's instructions, as its title's tooltip.
func _how_to(reporting: bool) -> String:
	var lines: Array = ["Drag a piece to move it; onto another to swap. R or right-click turns it."]
	if not GameState.pack_bags.is_empty():
		lines.append("Drag a bag by its tab to move it with what is in it.")
	# SPENDING AND MOVING ARE NOT LOCKED mid-game, only binning (§4.3).
	if reporting:
		lines.append("Nothing can be binned until you've reported this game.")
	return "\n".join(lines)

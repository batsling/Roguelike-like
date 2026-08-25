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
# The capsules the toggle carries when the window is shut — see `_toggle_button`.
const TOGGLE_PEEK := 3
const TOGGLE_ART := 16
# The bar's height at the foot of the pack panel. The page is fitted to a 720p
# canvas with a handful of pixels spare, so this is deliberately the smallest
# height that still reads as a control rather than as a caption.
const TOGGLE_H := 18

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
	# against a board that may have changed size anyway.
	_page.unmount_loot_overlay()
	if open:
		_page.mount_loot_overlay(_panel(reporting))

# The toggle, which is also THE ONLY THING ON THE PAGE THAT SAYS YOU ARE CARRYING
# LOOT while the window is shut. It used to be a 12px text label at the far right
# of the pack strip — eight relics drew eight pieces of art and six consumables
# drew the word "Loot", which is backwards: the consumables are what you spend
# turn to turn. So it carries the art of the first few pieces as well as the
# count, and it stands at the HEAD of the strip rather than its tail, out from
# under the toast column that was drawing over it.
func _toggle_button() -> Control:
	var held: int = GameState.loot_items.size()
	var full: bool = GameState.loot_is_full()
	# Full is a state worth colouring: a pack with no room turns the next payout
	# into "leave it", and the moment to know that is before the drop asks.
	var tint: Color = UITheme.DANGER if full else ACCENT

	var btn := Button.new()
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.tooltip_text = "Scrolls and pills you're carrying (%d of %d).\nClick or Tab to %s." % [
		held, GameState.loot_capacity(), "close" if open else "open"]
	if full:
		btn.tooltip_text += "\nFull — the next piece of loot has nowhere to go."
	# Margin 1, not the theme's: this is a full-width BAR at the foot of the pack
	# panel, and a button's usual padding would make it twice as tall as it needs to
	# be on a page with a handful of spare pixels.
	btn.add_theme_stylebox_override("normal",
		UITheme.flat(tint.lerp(UITheme.BG, 0.72), 5, 1, 1, tint.lerp(UITheme.BG, 0.4)))
	btn.add_theme_stylebox_override("hover",
		UITheme.flat(tint.lerp(UITheme.BG, 0.55), 5, 1, 1, tint))
	btn.add_theme_stylebox_override("focus", UITheme.flat(Color(0, 0, 0, 0), 5, 1, 0))
	btn.pressed.connect(func():
		open = not open
		_page.refresh_loot_window())

	# The label and the peek at what's in it, laid over the button rather than in
	# it: a Button draws one string, and this needs art. IGNORE on the row so every
	# click lands on the button underneath.
	#
	# EVERYTHING PACKED TO THE LEFT — the name, the count, then the peek at what is
	# in it — and the bar's right half left empty on purpose. The notification toasts
	# are a right-anchored column drawn over the page, and they cross this panel: a
	# count sitting at the far end of a full-width bar is a count behind "Acquired
	# Anchor." for most of every report, which is the exact fault that moved this
	# control off the end of the relic row in the first place.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 7
	row.offset_right = -7
	row.add_child(_bar_label("%s  Loot" % ("▾" if open else "▸"), tint, false))
	row.add_child(_bar_label("%d/%d" % [held, GameState.loot_capacity()], tint, full))
	for entry in GameState.loot_items.slice(0, TOGGLE_PEEK):
		if entry is Dictionary:
			var art: TextureRect = LootSystem.art_tex(entry, TOGGLE_ART)
			art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(art)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	btn.add_child(row)
	# The button has no text of its own, so it has to be told how tall the row it is
	# carrying makes it. Width comes from the panel — it fills.
	btn.custom_minimum_size = Vector2(0, TOGGLE_H)
	return btn

func _bar_label(text: String, tint: Color, loud: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
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
		GameState.remove_loot_at(index)
		GameLog.add("Threw away %s." % piece_name, UITheme.DANGER)
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
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title := Label.new()
	title.text = "%s  Loot  —  %d / %d carried" % [
		"💊" if _has_pills() else "📜", GameState.loot_items.size(), GameState.loot_capacity()]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", ACCENT.lerp(Color.WHITE, 0.45))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := UITheme.quiet_button("✕", Vector2.ZERO, 13)
	close.tooltip_text = "Close the loot window."
	close.pressed.connect(func():
		open = false
		_page.refresh_loot_window())
	head.add_child(close)

	var grid := LootGrid.new()
	grid.allow_reorder = true
	grid.show_use = true
	grid.allow_discard = true
	grid.locked = reporting
	grid.use_requested.connect(func(i: int): _page.use_loot(i))
	grid.inspect_requested.connect(func(i: int): _page.open_loot_card(i))
	grid.moved.connect(func(from: int, to: int):
		if GameState.move_loot(from, to):
			_page.refresh_loot_window())
	grid.discard_requested.connect(_discard)
	grid.rebuild()
	box.add_child(grid)

	# THE BIN, on the same terms as the drop modal's (§4.3). Spending a piece is not
	# the same as being rid of one: a pack holding three known-Negative pills is full
	# of loot the run will never willingly use, and reading the Amnesia scroll to
	# make room is a worse answer than throwing it away. Hidden while the pack is
	# locked — nothing can leave it mid-report either.
	if not reporting and not GameState.loot_items.is_empty():
		var bin := LootTrash.new()
		bin.grid = grid
		box.add_child(bin)

	# The one line of instruction the grid needs, and only while there is something
	# to rearrange — a single piece has nowhere to go.
	if not GameState.loot_items.is_empty() and not reporting:
		box.add_child(_note("Drag a piece into any slot to rearrange the pack — "
			+ "onto another piece to swap the two, onto an empty one to move it there."))
	if reporting:
		# SPENDING IS NOT LOCKED, only moving (§4.3, LootGrid.locked). Mid-game is
		# exactly when the player knows what they want out of a piece — the body
		# walking toward them is right there — and anything that cannot land in that
		# gap fizzles rather than being refused.
		box.add_child(_note("Mid-game: spend what you like. The pack can't be "
			+ "rearranged or binned until you've reported this one."))

	# WHAT YOU HAVE LEARNED, on both surfaces that draw the pack — the reward screen
	# builds the same section, and the fold is shared so it cannot be shut here and
	# open there (LootDiscoveries.open).
	box.add_child(LootDiscoveries.build(func(): _page.refresh_loot_window()))
	return panel

func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(LootSlot.CELL_W * 3, 0)
	return l

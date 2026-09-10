class_name StartPicker
extends Control

# THE OPENING SCREEN OF A RUN: what the Amulet is, and which road you open on.
#
# This used to be drawn into the overworld's own left column as `Phase.START_SELECT`
# — the ordinary two-column stage, with the offering panel swapped for a row of
# start cards. Three things were wrong with that, and they were all the same thing:
# the page is built for a run that has started, and at this moment none has.
#
#   * THE RIGHT-HAND HALF WAS DEAD. The board drew an empty 4x4 grid, a hero with
#     no run behind them, `EXTRA TURNS 0`, `no route to the Amulet` and a Push /
#     Bomb toolbar that cannot be pressed — roughly 600x560 of furniture, at the
#     moment of the run's first decision, none of which could be read or used.
#   * THE HALF THAT MATTERED DID NOT FIT. The left column carried a four-line
#     wrapped heading, the cards, the hover line, the verb chips and the standing
#     checklist, and measured 647-675px of the 630 a 720p window leaves — so the
#     first screen of every run opened with a scrollbar and its last line sliced in
#     half. It was also the ONE phase with no fit test on it: every guard in
#     `test_overworld2.gd` runs after `choose_start`, on the phase with 58px spare.
#   * THE AMULET WAS A CLAUSE. The run's destination — the thing both roads end on
#     and the whole reason one road differs from another — was the opening phrase
#     of a wrapped sentence above two covers.
#
# So it is its own screen: the Amulet gets the top of it, with its art and its
# name at the size a destination deserves, and the roads are laid out under it as
# a choice between two named journeys rather than two covers in a strip.
#
# HOW IT IS SELECTED. Click a road to select it, Confirm to take it — the same
# preview-then-commit shape as `CharacterPicker`, and for the same reason: this is
# a screen whose job is to inform, and a card that commits on the first click
# cannot be read before it is answered. A road's own card (the enemy standing
# there, the shields it grants, its record) is still one click away on `⚙ Details`,
# which opens the ordinary `GameChoiceModal` every other game in the run opens.

# Confirm pressed; carries the INDEX into the host's start options.
signal chosen(index: int)
# The way out with no run taken — the host decides what that means.
signal cancelled

# The layer this screen mounts on. Above the run's pinned header (135), which is
# reporting a Health pool, a purse and a road walked that no run has yet — the
# screen stands the bar down while it is up, and this is the belt to that braces.
const LAYER := UITheme.Layer.START
# …and what it opens on top of ITSELF. The ladder window is 130 and the game-card
# popup is 124 by default, both of which are under this screen: without lifting
# them, `→ Optimal Path` and `⚙ Details` open perfectly and are never seen.
const MODAL_LAYER := UITheme.Layer.START_MODAL

# The Amulet's banner art, and a road card's cover. Both are deliberately smaller
# than the covers the offering draws: this screen has to hold a banner, two road
# cards and a footer inside 720p, and the art is the part that gives most room
# back per pixel. See `test_screens_fit.gd`.
const AMULET_ART := Vector2(104, 104)
const ROAD_ART := Vector2(184, 138)
const ROAD_WIDTH := 300

var _page: Node = null              # the Overworld2 this is choosing a start for
var _options: Array = []            # its `_start_options`, verbatim
var _selected: int = -1
var _cards: Array = []              # [{panel: PanelContainer, accent: Color}]
var _confirm: Button = null
var _layer: CanvasLayer = null

# `page` is the Overworld2: this screen reads its rolled start options and calls
# back into it for the two popups a road can open. It never chooses anything
# itself — `chosen` is the whole of what it reports.
static func open(page: Node) -> StartPicker:
	var picker := StartPicker.new()
	picker._page = page
	picker._options = page._start_options.duplicate()
	picker._layer = CanvasLayer.new()
	picker._layer.layer = LAYER
	picker._layer.process_mode = Node.PROCESS_MODE_ALWAYS
	page.add_child(picker._layer)
	picker._layer.add_child(picker)
	return picker

func _ready() -> void:
	# `set_anchors_and_offsets_preset`, not `set_anchors_preset` — see the note in
	# CharacterPicker._ready. This node is mounted at 0x0, so preserving its
	# current rect would anchor a 0x0 box to the layer and stay that size forever.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.shared()
	UITheme.dress(self)     # a theme does not cross the CanvasLayer above
	_build()

# Free the layer as well as the screen. Mounted the way `open` mounts it, freeing
# only the Control leaves an empty CanvasLayer on the page for every run started.
func close() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build() -> void:
	# OPAQUE, not a dim. Every other full-screen overlay in the project dims the
	# thing behind it because that thing is still the subject — the menu behind the
	# character picker, the run behind the map. Here what is behind is the empty
	# board and the un-started page, and letting it show through is the whole of
	# what was wrong with drawing this into the page in the first place.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UITheme.BG_DEEP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1000, 0)
	panel.add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.BG, UITheme.ACCENT.lerp(UITheme.BORDER, 0.4), 12, 20, 2))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.GAP_LOOSE)
	panel.add_child(vbox)

	vbox.add_child(_amulet_banner())
	vbox.add_child(_roads_heading())
	vbox.add_child(_roads_row())
	vbox.add_child(_footer())

	# Preselect the first road, so the screen is never showing a live Confirm with
	# nothing chosen and never showing a dead one either.
	if not _options.is_empty():
		select(0)

# THE AMULET, at the top and at the size of the thing the whole run is about. It
# is named here and on every card and every ladder rung (see `Overworld2.amulet_name`)
# — the run's destination stopped being a secret when the picker started quoting
# distances TO it, and a `???` you are asked to route towards is a worse question
# than a name.
func _amulet_banner() -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.accent_box(UITheme.GOLD, UITheme.PANEL, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	wrap.add_child(row)

	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	if amulet != null and amulet.cover_image != null:
		var art := TextureRect.new()
		art.custom_minimum_size = AMULET_ART
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = amulet.cover_image
		row.add_child(art)

	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(facts)

	var eyebrow := Label.new()
	eyebrow.text = "🏆  THE AMULET — WHERE THIS RUN ENDS"
	eyebrow.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	eyebrow.add_theme_color_override("font_color", UITheme.GOLD.lerp(UITheme.TEXT_DIM, 0.4))
	facts.add_child(eyebrow)

	var name_lbl := Label.new()
	name_lbl.text = _page.amulet_name()
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_HERO)
	name_lbl.add_theme_color_override("font_color", UITheme.GOLD)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.add_child(name_lbl)

	if amulet != null:
		var meta := Label.new()
		var bits: Array = [RunGraph.type_label(amulet.type)]
		if amulet.year > 0:
			bits.append(str(amulet.year))
		meta.text = "  ·  ".join(bits)
		meta.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
		meta.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		facts.add_child(meta)

	var blurb := Label.new()
	blurb.text = "Reach it and clear the goal standing on it, and the run is won."
	blurb.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	blurb.add_theme_color_override("font_color", UITheme.TEXT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.add_child(blurb)
	return wrap

func _roads_heading() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_HAIR)
	var head := Label.new()
	# COUNTED, not asserted. This line said "three genres" for as long as
	# `RunGraph.NUM_START_OPTIONS` has been 2, because it was a hardcoded sentence
	# describing a number that had moved underneath it.
	head.text = "Choose the road you open on — %d %s, all ending on %s:" % [
		_options.size(),
		"genre" if _options.size() == 1 else "genres",
		_page.amulet_name()]
	head.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	head.add_theme_color_override("font_color", UITheme.ACCENT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head)
	var sub := Label.new()
	sub.text = ("The game you take is the run's first game, enemy and all — "
		+ "not a free move onto the board.")
	sub.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	sub.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	return box

func _roads_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_SECTION)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _options.is_empty():
		var l := Label.new()
		l.text = "No start could be rolled — check the game filter in Settings."
		l.add_theme_color_override("font_color", UITheme.DANGER)
		row.add_child(l)
		return row
	for i in range(_options.size()):
		row.add_child(_road_card(i, _options[i]))
	return row

# One road: its genre, its cover, its name, how far it stands from the Amulet, and
# what is waiting on it. The enemy is on the FACE of the card rather than behind a
# hover, because on this screen there are two cards and all the room in the world
# — the offering's cards hide it because there are three of them in a 150px strip.
func _road_card(index: int, opt: Dictionary) -> Control:
	var game: GameData = opt["game"]
	var accent: Color = RunGraph.type_color(int(opt["type"]))

	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(ROAD_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	wrap.add_child(box)

	var genre := Label.new()
	genre.text = RunGraph.type_label(int(opt["type"])).to_upper()
	genre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	genre.add_theme_font_size_override("font_size", UITheme.FONT_TEXT)
	genre.add_theme_color_override("font_color", accent)
	box.add_child(genre)

	# The cover is the button: clicking anywhere on the art selects the road.
	var btn := Button.new()
	btn.custom_minimum_size = ROAD_ART
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func(): select(index))
	if game.cover_image != null:
		var art := TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = game.cover_image
		btn.add_child(art)
	else:
		btn.text = game.display_name
	box.add_child(btn)

	var name_lbl := Label.new()
	name_lbl.text = game.display_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	box.add_child(name_lbl)

	var dist := Label.new()
	dist.text = _page._start_distance_text(int(opt["path_len"]))
	dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dist.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	dist.add_theme_color_override("font_color", UITheme.GOLD)
	box.add_child(dist)

	var enemy: GoalEnemyData = opt.get("enemy")
	var waiting := Label.new()
	waiting.text = ("☠  %s — %s" % [enemy.display_name, enemy.goal]) if enemy != null \
		else "No enemy — a free game."
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	waiting.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	waiting.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(waiting)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	box.add_child(tools)
	var path_btn := Button.new()
	# OPTIMAL PATH, not `Map`. The ladder is the one shortest road drawn rung by
	# rung; the star chart is the Map, and it is a header button in a run. Three
	# buttons on the old start panel said `Map` for two different destinations.
	path_btn.text = "→  Optimal Path"
	path_btn.tooltip_text = "The shortest route to %s if you open on %s." % [
		_page.amulet_name(), game.display_name]
	path_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	path_btn.pressed.connect(func(): _page.preview_map(game.id))
	tools.add_child(path_btn)
	var card_btn := Button.new()
	card_btn.text = "⚙  Details"
	card_btn.tooltip_text = "The full card: the enemy, its goal, the shields this game grants, your record in it."
	card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_btn.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	card_btn.pressed.connect(func(): _page.open_start_choice(index))
	tools.add_child(card_btn)

	_cards.append({"panel": wrap, "accent": accent})
	return wrap

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.GAP_WIDE)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(150, 42)
	cancel.tooltip_text = "Back to the main menu — no run is started."
	cancel.pressed.connect(func(): cancelled.emit())
	row.add_child(cancel)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_confirm = Button.new()
	_confirm.text = "Begin the run"
	_confirm.disabled = true
	_confirm.custom_minimum_size = Vector2(280, 42)
	_confirm.add_theme_stylebox_override("normal", UITheme.accent_box(UITheme.ACCENT, UITheme.PANEL_HI, 8))
	_confirm.add_theme_color_override("font_color", UITheme.GOLD)
	_confirm.add_theme_font_size_override("font_size", UITheme.FONT_SUB)
	_confirm.pressed.connect(func():
		if _selected >= 0:
			chosen.emit(_selected))
	row.add_child(_confirm)
	return row

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

# Public so a test can drive the same path a click takes, and so the host can
# preselect one. Out-of-range is a no-op rather than an error: the roads come from
# a random graph and a caller should not have to bounds-check the roster.
func select(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	_selected = index
	for i in range(_cards.size()):
		var accent: Color = _cards[i]["accent"]
		var on: bool = i == index
		_cards[i]["panel"].add_theme_stylebox_override("panel", UITheme.panel_box(
			UITheme.PANEL_HI if on else UITheme.PANEL,
			accent if on else UITheme.BORDER, 10, 10, 2 if on else 1))
	if _confirm != null:
		_confirm.disabled = false
		var game: GameData = _options[index]["game"]
		_confirm.text = "Begin: %s" % game.display_name

# Which road is selected, or -1. Read by the tests and by nothing else.
func selected_index() -> int:
	return _selected

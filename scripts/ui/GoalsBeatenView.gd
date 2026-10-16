class_name GoalsBeatenView
extends RefCounted

# EVERY GOAL COMPLETED AT ONE GAME, as pictures: one header per kind (in
# GameStats.GOAL_KINDS order — Character, Enemies, Bosses, Weapons, Statuses,
# Bonuses, Curses) and a flow of square tiles under it, each with the number of
# times it was done in its corner and its goal (and your note) on the hover.
#
# The Collection's game page drew this first (`Collection._add_goals_section`).
# The route map's game card listed the same record as rows of text — "Enemies you
# have beaten here", a name and a ×N per line — which took the card's whole height
# on a game you had played a lot. It is a "Goals Beaten" button there now, and the
# button opens THIS, so the card and the Collection show one record one way.
#
# Static builders plus a popup (`open`). Kept out of Collection.gd because the run's
# page must not compile the Collection (test_page_load), and it is reached from the
# card BY PATH, at the moment the button is pressed, for the same reason.

# The square a goal's art is drawn in.
const TILE := 56
# The frame behind a picture — the Collection's IMAGE_BG.
const IMAGE_BG := Color(0.16, 0.17, 0.22, 1.0)
const POPUP_W := 520.0

# The headers and tile flows for every kind done at `g`, added to `box`. Returns
# how many kinds there were (0: nothing done here yet). `host` is the node a
# note's editor opens over; `redraw` is called after a note is saved.
static func add_kinds(box: Container, host: Node, g: GameData, redraw: Callable) -> int:
	var all: Dictionary = GameStats.goals_at(g.id)
	for kind in all.keys():
		var rows: Array = all[kind]
		var head: String = "%s (%d)" % [GameStats.GOAL_KIND_NAMES[kind], rows.size()]
		# The enemy pool, from the game's side: how much of what CAN appear here
		# has actually been cleared here — the same record as the Atlas card.
		if kind == "enemy":
			var can_appear: int = GameLoop2.possible_enemies_at(g).size()
			head = "%s (%d / %d)" % [GameStats.GOAL_KIND_NAMES[kind], rows.size(),
				maxi(can_appear, rows.size())]
		box.add_child(kind_header(head))
		var flow := tile_flow()
		for row in rows:
			flow.add_child(goal_tile(host, g, String(kind), row, redraw))
		box.add_child(flow)
	return all.size()

# THE CHARACTER PAGE'S RECORD, drawn the way a game's is: every goal beaten
# playing as `ch`, wherever, as tiles by kind (GameStats.character_goals). The
# enemies and bosses show the WHOLE roster, beaten first and the rest dimmed, so
# the page says what is left as well as what is done. No notes: a note belongs to
# a (game, goal) pair and is edited on the game's page.
static func add_character_kinds(box: Container, ch: CharacterData) -> int:
	var all: Dictionary = GameStats.character_goals(ch.id)
	var shown: int = 0
	for kind in GameStats.GOAL_KINDS:
		var rows: Array = all.get(kind, [])
		var roster: Array = []
		if kind == "enemy":
			roster = Data.all_goal_enemies()
		elif kind == "boss":
			roster = Data.all_bosses()
		if rows.is_empty() and roster.is_empty():
			continue
		var head: String = "%s (%d)" % [GameStats.GOAL_KIND_NAMES[kind], rows.size()]
		if not roster.is_empty():
			head = "%s (%d / %d)" % [GameStats.GOAL_KIND_NAMES[kind], rows.size(),
				maxi(roster.size(), rows.size())]
		box.add_child(kind_header(head))
		var flow := tile_flow()
		var done: Dictionary = {}
		for row in rows:
			done[String(row["key"])] = true
			flow.add_child(goal_tile(box, null, String(kind), row, Callable()))
		var rest: Array = roster.filter(func(e): return not done.has(String(e.id)))
		rest.sort_custom(func(a, b): return a.display_name < b.display_name)
		for e in rest:
			flow.add_child(goal_tile(box, null, String(kind),
				{"key": String(e.id), "label": e.display_name, "done": 0, "missing": true,
					"missing_text": "not beaten yet as %s" % ch.display_name}, Callable()))
		box.add_child(flow)
		shown += 1
	return shown

static func kind_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UITheme.FONT_LABEL)
	l.add_theme_color_override("font_color", UITheme.GOLD)
	l.set_meta(&"goal_kind_header", true)
	return l

static func tile_flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UITheme.GAP_SNUG)
	flow.add_theme_constant_override("v_separation", UITheme.GAP_SNUG)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return flow

# One goal: its picture, the times done in the corner, the goal and your note on
# the hover — and a click that edits the note, for the kinds that carry one.
static func goal_tile(host: Node, g: GameData, kind: String, row: Dictionary,
		redraw: Callable) -> Control:
	var name: String = String(row["label"])
	var goal: String = ""
	var tex: Texture2D = null
	var edit: Callable = Callable()
	var key: String = String(row["key"])
	var accent: Color = UITheme.GOLD
	match kind:
		"enemy", "boss":
			var e: GoalEnemyData = Data.get_goal_enemy_any(StringName(key))
			if e != null:
				tex = e.image
				goal = e.goal
				if e.is_boss():
					accent = UITheme.DANGER
				if g != null:
					edit = func(): EnemyNoteModal.open(host, g, e, redraw)
		"character":
			var ch: CharacterData = Data.get_character2(StringName(key))
			if ch != null:
				tex = ch.icon if ch.icon != null else ch.portrait
				goal = ch.level_up_condition
				if g != null:
					edit = func(): EnemyNoteModal.open_level_up(host, g, ch, redraw)
		"weapon":
			var w: WeaponData = Data.get_weapon(StringName(key))
			if w != null:
				tex = LootPassives.load_weapon_art(w)
		"status", "bonus":
			var st: StatusData = Data.get_status(StringName(key))
			if st != null:
				tex = st.image
		"curse":
			var cd: CurseData2 = Data.get_curse2(StringName(key))
			if cd != null:
				tex = cd.image
	# The label of the other kinds is already "Name — the goal"; split it so the
	# hover reads the same for every kind.
	if goal == "" and name.contains(" — "):
		goal = name.get_slice(" — ", 1)
		name = name.get_slice(" — ", 0)
	var verb: String = {"enemy": "beaten", "boss": "beaten", "character": "levelled",
		"curse": "followed"}.get(kind, "done")
	var tip: PackedStringArray = PackedStringArray(
		["%s — %s ×%d" % [name, verb, int(row["done"])]])
	if goal != "":
		tip.append(goal)
	var note: String = String(row.get("note", "")).strip_edges()
	if note != "":
		tip.append("Note: " + note)
	if edit.is_valid():
		tip.append("Click to %s your note." % ("edit" if note != "" else "add"))
	var border: Color = UITheme.CURSE if kind == "curse" else (
		UITheme.GOLD if note != "" else UITheme.BORDER)
	if kind == "curse":
		accent = UITheme.CURSE
	# THE CARD, not a line of system text: the art, the name in its colour, how
	# often, then the goal and your note. `row["missing"]` is a roster entry
	# never done (the character page shows the whole roster, dimmed).
	var done: int = int(row["done"])
	var missing: bool = bool(row.get("missing", false))
	var lines: Array = []
	if goal != "":
		lines.append(goal)
	if note != "":
		lines.append("Note: " + note)
	var card := {"title": name, "accent": UITheme.TEXT_DIM if missing else accent,
		"art": tex,
		"subtitle": String(row.get("missing_text", "not done yet")) if missing \
			else "%s ×%d" % [verb, done],
		"lines": lines}
	if edit.is_valid():
		card["note"] = "Click to %s your note." % ("edit" if note != "" else "add")
	var tile := picture_tile(tex, Vector2(TILE, TILE),
		"\n".join(tip), done, border, true, name, card)
	if missing:
		tile.modulate = Color(1, 1, 1, 0.35)
	tile.set_meta(&"goal_key", key)
	if edit.is_valid():
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				tile.accept_event()
				edit.call_deferred())
	return tile

# A picture in a frame, with its tooltip, an optional count in the top-right
# corner, and the NAME written in when there is no picture to show — a goal
# whose art is missing is still a goal on the record.
static func picture_tile(tex: Texture2D, size: Vector2, tip: String, count: int,
		border: Color, crisp: bool, fallback: String = "", card: Dictionary = {}) -> Control:
	# A HoverPanel, so the hover is a HoverCard (`card`) or, without one, the
	# tip in HoverCard's wrapped box — never Godot's stock grey tooltip.
	var tile := HoverPanel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = IMAGE_BG.lerp(border, 0.12)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(2)
	sb.set_border_width_all(1)
	sb.border_color = Color(border.r, border.g, border.b, 0.6)
	tile.add_theme_stylebox_override("panel", sb)
	tile.tooltip_text = tip
	if not card.is_empty():
		HoverCard.attach(tile, card)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	var stack := Control.new()
	stack.custom_minimum_size = size
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(stack)
	# No picture AND no name means the picture is still coming (a cover filled
	# in after), so the frame for it goes up empty.
	if tex != null or fallback == "":
		var art := TextureRect.new()
		art.texture = tex
		tile.set_meta(&"art", art)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if crisp and tex != null:
			UITheme.apply_crisp(art, tex)
		stack.add_child(art)
	else:
		var name := Label.new()
		name.text = fallback
		name.set_anchors_preset(Control.PRESET_FULL_RECT)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.add_theme_font_size_override("font_size", UITheme.FONT_TINY)
		name.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(name)
	if count > 0:
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel",
			UITheme.flat(UITheme.BG, 6, 2, 1, UITheme.GOLD.lerp(UITheme.BORDER, 0.3)))
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_meta(&"count_badge", true)
		var n := Label.new()
		n.text = str(count)
		n.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		n.add_theme_color_override("font_color", UITheme.GOLD)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(n)
		stack.add_child(badge)
	return tile

# THE POPUP the card's "Goals Beaten" button opens: a shade over `host` (a
# full-rect Control on its own layer — the map window, the choice popup), the
# record in the middle of the room below the run's header, and a Close. Clicking
# the shade closes it too. Returns the shade, which is what closes it.
static func open(host: Control, g: GameData) -> Control:
	var shade := ColorRect.new()
	shade.name = "GoalsBeatenView"
	shade.color = Color(UITheme.BG_DEEP, 0.85)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			shade.accept_event()
			shade.queue_free())
	host.add_child(shade)

	var free: Rect2 = ModalScaffold.free_rect(host)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.flat(UITheme.PANEL, 8, 14, 2, UITheme.GOLD))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Goals beaten at %s (%d)" % [g.display_name, GameStats.distinct_goals_count(g.id)]
	title.add_theme_font_size_override("font_size", UITheme.FONT_LEAD)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_right", 14)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", UITheme.GAP_SNUG)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(POPUP_W - 28.0 - 14.0, 0)
	inset.add_child(list)
	# A note saved from a tile redraws the list in place.
	var redraw := func():
		if not is_instance_valid(list):
			return
		for c in list.get_children():
			list.remove_child(c)
			c.queue_free()
		if add_kinds(list, host, g, Callable()) == 0:
			list.add_child(_empty_note())
	if add_kinds(list, host, g, redraw) == 0:
		list.add_child(_empty_note())
	var close := Button.new()
	close.name = "Close"
	close.text = "Close"
	close.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	close.pressed.connect(shade.queue_free)
	col.add_child(close)

	# Sized to the list, capped at the room below the header, and centred in it.
	var max_h: float = maxf(200.0, free.size.y - 32.0)
	var w: float = minf(POPUP_W, free.size.x - 32.0)
	panel.custom_minimum_size = Vector2(w, 0)
	var fit := func():
		if not is_instance_valid(panel):
			return
		var chrome: float = 28.0 + title.get_combined_minimum_size().y \
			+ close.get_combined_minimum_size().y + UITheme.GAP_SNUG * 2
		scroll.custom_minimum_size = Vector2(0,
			clampf(list.get_combined_minimum_size().y, 60.0, maxf(60.0, max_h - chrome)))
		var h: float = minf(panel.get_combined_minimum_size().y, max_h)
		panel.size = Vector2(w, h)
		panel.position = Vector2(free.position.x + (free.size.x - w) * 0.5,
			free.position.y + maxf(16.0, (free.size.y - h) * 0.5))
	fit.call()
	# Again once the flows have laid out: a flow's height is only true once it
	# knows its width, which is a layout pass after it is added.
	if host.is_inside_tree():
		host.get_tree().process_frame.connect(fit, CONNECT_ONE_SHOT)
	fit.call_deferred()
	return shade

static func _empty_note() -> Label:
	var l := Label.new()
	l.text = "No goals completed here yet."
	l.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	l.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	return l

extends Node

# Developer panel: press ` (backtick) to open. Gated on Settings.dev_mode, built
# entirely in code, and living on an autoload so it floats above whatever scene is
# running and survives scene changes.
#
# Four tabs, in the order you reach for them:
#
#   GRANT   put content into the run — 2.0/1.0 items, scrolls, and statuses (§13)
#           with a target picker, since a status can land on the player or on any
#           body on the board.
#   RUN     move the run's numbers — Health / Max Health, every board verb, gold,
#           banked chests, level, and the difficulty tier.
#   BOARD   spawn a goal-enemy or a boss, and act on what is already standing:
#           stun / push / bomb / defeat / remove, or hang a status on one.
#   FLOW    move the run itself — jump to any game, reveal the amulet, force the
#           win or the loss.
#
# Everything here goes through the SAME public API the game does (GameState.
# apply_status, GameLoop2.spawn_to_stack, Overworld2.travel_to_game …) so a thing
# that works in the panel works in the game, and the panel can't drift into
# testing a path nothing else takes.

const TOGGLE_KEY := KEY_QUOTELEFT     # the ` / ~ key
const MAX_RESULTS := 120

const TABS := ["grant", "run", "board", "flow"]
const TAB_LABELS := {"grant": "Grant", "run": "Run", "board": "Board", "flow": "Flow"}
# What the Grant tab is granting.
const GRANT_KINDS := ["items", "scrolls", "statuses"]
const GRANT_LABELS := {"items": "Items", "scrolls": "Scrolls", "statuses": "Statuses"}
# Where a granted status lands (GameLoop2's own target words, plus the player).
const STATUS_TARGETS := ["player", "current", "all", "random"]

var _layer: CanvasLayer = null
var _search: LineEdit = null
var _body: VBoxContainer = null       # the active tab's contents
var _hint: Label = null
var _search_row: Control = null

var _tab: String = "grant"
var _grant_kind: String = "items"
var _status_target: String = "player"
var _stacks: int = 1
# Board tab: what a spawn rolls, and the amount a Run-tab nudge moves.
var _spawn_boss: bool = false
var _step: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == TOGGLE_KEY and Settings.dev_mode:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _is_open():
		_close()
		get_viewport().set_input_as_handled()

func _is_open() -> bool:
	return _layer != null and _layer.visible

func _toggle() -> void:
	if _layer == null:
		_build()
		# _build leaves the layer HIDDEN. A CanvasLayer is visible by default, so
		# building it here and then flipping `visible` would turn the panel off on
		# the very first press — the first ` did nothing and the second opened it.
		_layer.visible = false
	_layer.visible = not _layer.visible
	if _layer.visible:
		_rebuild()
		_search.grab_focus()

func _close() -> void:
	if _layer != null:
		_layer.visible = false

# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 200
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_top = -340
	panel.offset_right = 340
	panel.offset_bottom = 340
	# Its own opaque ground. Without this the panel takes the theme's default
	# (transparent here) and the whole overworld reads straight through the tool
	# you are trying to use.
	panel.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.08, 0.08, 0.11, 0.99), 0, 0, 2, UITheme.ACCENT))
	_layer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Dev Tools"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vbox.add_child(tabs)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.text = TAB_LABELS[t]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t == _tab
		var key: String = t
		b.pressed.connect(func() -> void:
			_tab = key
			_rebuild())
		tabs.add_child(b)

	_search = LineEdit.new()
	_search.placeholder_text = "Search a name…"
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_body())
	_search_row = _search
	vbox.add_child(_search)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 430)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 3)
	scroll.add_child(_body)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	vbox.add_child(bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close (`)"
	close_btn.pressed.connect(_close)
	bar.add_child(close_btn)

# Repaint everything: the hint, whether the search box applies, and the body.
func _rebuild() -> void:
	if _body == null:
		return
	_hint.text = _hint_text()
	# RUN has nothing to search — every control is on screen at once.
	_search_row.visible = _tab != "run"
	_rebuild_body()

func _hint_text() -> String:
	match _tab:
		"run":
			return "Nudge the run's numbers. The step size applies to every ± below."
		"board":
			return "Spawn a body, or act on one already standing. Instance ids are the handles the loop uses."
		"flow":
			return "Move the run itself. Jumping does not resolve a game or touch the board."
		_:
			match _grant_kind:
				"scrolls":
					return "Click a scroll to add it (unidentified) to your loot."
				"statuses":
					return "Click a status to apply it. 'Player' is your own side; the rest land on bodies (§13)."
				_:
					return "Click an item to add it to your inventory."

func _rebuild_body() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		child.queue_free()
	match _tab:
		"run":
			_build_run_tab()
		"board":
			_build_board_tab()
		"flow":
			_build_flow_tab()
		_:
			_build_grant_tab()

func _query() -> String:
	return _search.text.strip_edges().to_lower() if _search != null else ""

# ---------------------------------------------------------------------------
# Shared widgets
# ---------------------------------------------------------------------------

# A radio row: [{label, value}], calling `on_pick` with the chosen value.
func _radio_row(title: String, options: Array, current: String, on_pick: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if title != "":
		var l := Label.new()
		l.text = title
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.78))
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	var group := ButtonGroup.new()
	for opt in options:
		var b := Button.new()
		b.text = String(opt["label"])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = String(opt["value"]) == current
		var v: String = String(opt["value"])
		b.pressed.connect(func() -> void: on_pick.call(v))
		row.add_child(b)
	return row

# A labelled number with − / + buttons. `get_value` is read every repaint so the
# row always shows the live figure rather than a snapshot.
func _stepper(label: String, get_value: Callable, apply: Callable,
		suffix: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.custom_minimum_size = Vector2(150, 0)
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_lbl)
	var value := Label.new()
	value.text = "%s%s" % [str(get_value.call()), suffix]
	value.custom_minimum_size = Vector2(70, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	for spec in [{"t": "−", "d": -1}, {"t": "+", "d": 1}]:
		var b := Button.new()
		b.text = String(spec["t"])
		b.custom_minimum_size = Vector2(34, 0)
		var dir: int = int(spec["d"])
		b.pressed.connect(func() -> void:
			apply.call(dir * _step)
			_rebuild_body())
		row.add_child(b)
	return row

# One clickable result line with an optional right-hand detail column.
func _row_button(label: String, detail: String, on_press: Callable) -> Control:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = label if detail == "" else "%s      %s" % [label, detail]
	btn.pressed.connect(on_press)
	return btn

func _section(title: String) -> Control:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	return l

func _note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _say(text: String, color: Color = Color(0.8, 1.0, 0.8)) -> void:
	Notifications.notify(text, color)
	GameLog.add("[dev] %s" % text, color)

# ---------------------------------------------------------------------------
# GRANT
# ---------------------------------------------------------------------------

func _build_grant_tab() -> void:
	var kinds: Array = []
	for k in GRANT_KINDS:
		kinds.append({"label": GRANT_LABELS[k], "value": k})
	_body.add_child(_radio_row("", kinds, _grant_kind, func(v: String) -> void:
		_grant_kind = v
		_rebuild()))

	# Statuses need to know WHERE they land and HOW MANY stacks before the list is
	# any use, so those controls sit above it rather than per row.
	if _grant_kind == "statuses":
		var targets: Array = []
		for t in STATUS_TARGETS:
			targets.append({"label": t.capitalize(), "value": t})
		_body.add_child(_radio_row("Target:", targets, _status_target,
			func(v: String) -> void:
				_status_target = v
				_rebuild_body()))
		_body.add_child(_stepper("Stacks to apply", func(): return _stacks,
			func(d: int) -> void: _stacks = maxi(1, _stacks + d)))

	match _grant_kind:
		"scrolls":
			_list_scrolls()
		"statuses":
			_list_statuses()
		_:
			_list_items()

func _list_items() -> void:
	var query: String = _query()
	var pool: Array = Data.all_items2()
	pool.append_array(Data.all_items())
	var rows: Array = []
	for it in pool:
		if not (it is ItemData):
			continue
		var label: String = String(it.display_name)
		if query != "" and not label.to_lower().contains(query):
			continue
		var item: ItemData = it
		rows.append({"label": label,
			"detail": "%s · %s" % [UITheme.rarity_name(int(it.rarity)), it.source_game],
			"press": func() -> void:
				GameState.add_item(item)
				_say("Added item: %s" % item.display_name)})
	_emit_rows(rows)

func _list_scrolls() -> void:
	var query: String = _query()
	var rows: Array = []
	for s in Data.all_scrolls():
		if not (s is ScrollData):
			continue
		var label: String = String(s.display_name)
		if query != "" and not label.to_lower().contains(query):
			continue
		var scroll: ScrollData = s
		rows.append({"label": label, "detail": String(s.rarity),
			"press": func() -> void:
				GameState.add_scroll_loot(scroll.id)
				_say("Added scroll: %s" % scroll.display_name, Color(0.61, 0.35, 0.71))})
	_emit_rows(rows)

func _list_statuses() -> void:
	var query: String = _query()
	var rows: Array = []
	for s in Data.all_statuses():
		if not (s is StatusData):
			continue
		var label: String = String(s.display_name)
		if query != "" and not label.to_lower().contains(query):
			continue
		var status: StatusData = s
		# What it will DO once applied, on the side it is about to land on — the
		# panel names the consequence rather than making you remember the sheet.
		var which: StringName = StatusData.PLAYER if _status_target == "player" \
			else StatusData.ENEMY
		rows.append({"label": label,
			"detail": "%s · %s" % [String(status.mode_for(which)).capitalize(),
				String(status.kind).capitalize()],
			"press": _grant_status.bind(status)})
	_emit_rows(rows)

func _grant_status(status: StatusData) -> void:
	if _status_target == "player":
		GameState.apply_status(status.id, _stacks)
		_say("%s %d on the player." % [status.display_name, _stacks], Color(0.9, 0.8, 1.0))
		return
	var hit: int = GameLoop2.apply_enemy_status(status.id, _stacks, _status_target)
	if hit == 0:
		_say("No body to put %s on (target: %s)." % [status.display_name, _status_target],
			Color(1.0, 0.7, 0.5))
	else:
		_say("%s %d on %d enem%s." % [status.display_name, _stacks, hit,
			"y" if hit == 1 else "ies"], Color(0.9, 0.8, 1.0))

func _emit_rows(rows: Array) -> void:
	rows.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
	var shown: int = 0
	for r in rows:
		if shown >= MAX_RESULTS:
			break
		_body.add_child(_row_button(String(r["label"]), String(r.get("detail", "")),
			r["press"]))
		shown += 1
	if rows.is_empty():
		_body.add_child(_note("Nothing matches."))
	elif rows.size() > shown:
		_body.add_child(_note("…and %d more — refine the search." % (rows.size() - shown)))

# ---------------------------------------------------------------------------
# RUN
# ---------------------------------------------------------------------------

func _build_run_tab() -> void:
	var steps: Array = []
	for n in [1, 5, 10]:
		steps.append({"label": "±%d" % n, "value": str(n)})
	_body.add_child(_radio_row("Step:", steps, str(_step), func(v: String) -> void:
		_step = int(v)
		_rebuild_body()))

	_body.add_child(_section("Vitals"))
	_body.add_child(_stepper("Health", func(): return GameState.hp,
		func(d: int) -> void: GameState.change_hp(d)))
	_body.add_child(_stepper("Max Health", func(): return GameState.max_hp,
		func(d: int) -> void: GameState.set_max_hp(maxi(1, GameState.max_hp + d), false)))
	_body.add_child(_stepper("Gold", func(): return GameState.gold,
		func(d: int) -> void: GameState.change_gold(d)))

	_body.add_child(_section("Board verbs"))
	# Routed through grant_run_stat, the same call an item's gain_stat makes, so a
	# verb nudged here goes through every amplifier a real grant would.
	for spec in [{"label": "Shields", "stat": "shields"}, {"label": "Bash", "stat": "bash"},
			{"label": "Dash", "stat": "dash"}, {"label": "Push", "stat": "push"},
			{"label": "Transmute", "stat": "transmute"}, {"label": "Scramble", "stat": "scramble"},
			{"label": "Bombs", "stat": "bombs"}, {"label": "Keys", "stat": "keys"}]:
		var stat: String = String(spec["stat"])
		_body.add_child(_stepper(String(spec["label"]),
			func(): return GameState.verb_value(stat),
			func(d: int) -> void: GameState.grant_run_stat(stat, d)))

	_body.add_child(_section("Progress"))
	_body.add_child(_stepper("Player level", func(): return GameState.player_level,
		func(d: int) -> void: GameState.player_level = maxi(1, GameState.player_level + d)))
	_body.add_child(_stepper("Banked chests", func(): return GameState.pending_chests,
		func(d: int) -> void:
			if d > 0:
				GameState.grant_chest(d)
			else:
				for i in range(-d):
					GameState.take_pending_chest()))
	# The tier is DERIVED from games_played (RunDifficulty.tier_for), so the panel
	# moves the count rather than pretending the tier is a field.
	_body.add_child(_stepper("Games played", func(): return GameState.games_played,
		func(d: int) -> void:
			GameState.games_played = maxi(0, GameState.games_played + d)
			GameLoop2.loop_changed.emit()))
	_body.add_child(_note("Difficulty tier is derived from games played — currently %s."
		% RunDifficulty.tier_name(RunDifficulty.current_tier())))

# ---------------------------------------------------------------------------
# BOARD
# ---------------------------------------------------------------------------

func _build_board_tab() -> void:
	_body.add_child(_section("Standing on the board"))
	var bodies: Array = GameLoop2.stack.duplicate()
	if not GameLoop2.current.is_empty():
		bodies.append(GameLoop2.current)
	if bodies.is_empty():
		_body.add_child(_note("Nothing on the board."))
	for entry in bodies:
		_body.add_child(_board_row(entry))

	_body.add_child(_section("Spawn"))
	var kinds: Array = [{"label": "Goal-enemy", "value": "enemy"},
		{"label": "Boss", "value": "boss"}]
	_body.add_child(_radio_row("Pool:", kinds, "boss" if _spawn_boss else "enemy",
		func(v: String) -> void:
			_spawn_boss = v == "boss"
			_rebuild_body()))
	var query: String = _query()
	var rows: Array = []
	for e in (Data.all_bosses() if _spawn_boss else Data.all_goal_enemies()):
		if not (e is GoalEnemyData):
			continue
		var label: String = String(e.display_name)
		if query != "" and not label.to_lower().contains(query):
			continue
		var enemy: GoalEnemyData = e
		rows.append({"label": label,
			"detail": "%s · %s · dmg %d" % [String(e.game_type).capitalize(),
				RunDifficulty.tier_name(e.tier_index()), e.damage],
			"press": func() -> void:
				GameLoop2.spawn_to_stack(enemy)
				_say("Spawned %s." % enemy.display_name, Color(1.0, 0.7, 0.6))
				_rebuild_body()})
	_emit_rows(rows)

# One body on the board: who it is, where it stands, and every action aimed at it.
func _board_row(entry: Dictionary) -> Control:
	var e: GoalEnemyData = entry.get("enemy")
	var inst: int = int(entry.get("instance", 0))
	var is_current: bool = not GameLoop2.current.is_empty() \
		and int(GameLoop2.current.get("instance", 0)) == inst

	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		UITheme.flat(Color(0.11, 0.11, 0.14, 0.85), 6, 5, 1, UITheme.BORDER))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	wrap.add_child(col)

	var head := Label.new()
	var where: String = "current game" if is_current \
		else "col %d, row %d" % [int(entry.get("col", 0)), int(entry.get("row", 0))]
	head.text = "#%d  %s   (%s, ❤%d, ⚔%d)" % [inst, e.display_name, where,
		int(entry.get("health", e.health)), e.damage]
	head.add_theme_font_size_override("font_size", 13)
	col.add_child(head)
	var statuses: Array = GameLoop2.enemy_statuses(entry)
	if not statuses.is_empty():
		var names: Array = []
		for row in statuses:
			names.append("%s %d" % [(row["status"] as StatusData).display_name,
				int(row["stacks"])])
		col.add_child(_note("statuses: %s" % ", ".join(names)))

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 4)
	col.add_child(acts)
	# Stun / push / bomb only mean anything for a body actually ON the grid; the
	# current game's enemy hasn't walked on yet (§7.2).
	if not is_current:
		acts.add_child(_mini("Stun", func() -> void:
			GameLoop2.stun(inst)
			_rebuild_body()))
		acts.add_child(_mini("Push", func() -> void:
			GameLoop2.push(inst)
			_rebuild_body()))
		acts.add_child(_mini("Bomb", func() -> void:
			GameState.bombs += 1     # the panel pays for its own charge
			GameLoop2.bomb(inst)
			_rebuild_body()))
		acts.add_child(_mini("Defeat (drops)", func() -> void:
			GameLoop2.fulfill(inst)
			_rebuild_body()))
	acts.add_child(_mini("Remove", func() -> void:
		GameLoop2.despawn(inst)
		_rebuild_body()))
	# Hanging a status on THIS body, whatever the Grant tab's target says — the
	# common case here is "that one", and picking it by instance beats switching
	# tabs to aim at it.
	for s in Data.all_statuses():
		var status: StatusData = s
		acts.add_child(_mini("+%s" % status.display_name, func() -> void:
			GameLoop2.apply_status_to(inst, status.id, _stacks)
			_say("%s %d on #%d." % [status.display_name, _stacks, inst],
				Color(0.9, 0.8, 1.0))
			_rebuild_body()))
	return wrap

func _mini(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(on_press)
	return b

# ---------------------------------------------------------------------------
# FLOW
# ---------------------------------------------------------------------------

func _build_flow_tab() -> void:
	_body.add_child(_section("Run state"))
	var here: GameData = Data.get_game(GameState.current_game_id)
	var amulet: GameData = Data.get_game(GameState.amulet_game_id)
	_body.add_child(_note("Standing on: %s\nAmulet: %s\nHops to amulet: %d\nBoard: %dx%d, tier %s" % [
		here.display_name if here != null else "(nowhere)",
		amulet.display_name if amulet != null else "(unrolled)",
		GameLoop2.hops_to_amulet(),
		GameLoop2.grid_cols(), GameLoop2.grid_rows(),
		RunDifficulty.tier_name(RunDifficulty.current_tier())]))

	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	_body.add_child(acts)
	acts.add_child(_mini("Heal to full", func() -> void:
		GameState.change_hp(GameState.max_hp - GameState.hp)
		_say("Healed to full.")))
	acts.add_child(_mini("Win the run", func() -> void:
		GameLoop2.clear_amulet()
		_say("Forced the win.", Color(0.7, 1.0, 0.7))
		_close()))
	acts.add_child(_mini("Lose the run", func() -> void:
		GameState.change_hp(-GameState.hp)
		_say("Forced the loss.", Color(1.0, 0.6, 0.6))
		_close()))
	acts.add_child(_mini("Clear the board", func() -> void:
		for entry in GameLoop2.stack.duplicate():
			GameLoop2.despawn(int(entry.get("instance", 0)))
		_say("Cleared the board.")))

	_body.add_child(_section("Jump to a game"))
	var scene = GameState.overworld_scene
	if scene == null or not scene.has_method("travel_to_game"):
		_body.add_child(_note("No overworld mounted — start a run first."))
		return
	var query: String = _query()
	if query == "":
		_body.add_child(_note("Type a game's name to list jump targets."))
		return
	var rows: Array = []
	for g in Data.all_games():
		if not (g is GameData) or g.id == GameState.current_game_id:
			continue
		var label: String = String(g.display_name)
		if not label.to_lower().contains(query):
			continue
		var gid: StringName = g.id
		rows.append({"label": label, "detail": String(GameLoop2.game_type_key(g)),
			"press": func() -> void:
				scene.travel_to_game(gid)
				_say("Jumped to %s." % label, Color(0.5, 0.85, 1.0))
				_close()})
	_emit_rows(rows)

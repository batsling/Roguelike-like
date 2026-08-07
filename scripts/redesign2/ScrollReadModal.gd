extends Control

# The games-first (2.0) "read a scroll" flow, as a self-contained full-screen
# modal (docs/games-first-redesign.md §4.1). The Overworld2 scroll panel
# instantiates one and calls start(host, loot_index); the modal owns the rest:
#   1. show the scroll (mystery art + masked name when unidentified — reading it
#      is the Preference gamble; identified art + real name once known).
#   2. on Read: ScrollSystem.read_scroll (which identifies it), remove it from
#      loot, then walk any returned `requests` (identify-which / stun-which /
#      teleport) through small pickers.
#   3. emit `finished` and free itself so the panel refreshes.
#
# Built entirely in code (no scene file), on its own CanvasLayer so it always
# centers over the overworld regardless of what opened it.

signal finished

var _scroll: ScrollData = null
var _loot_index: int = -1
var _requests: Array = []
var _panel: PanelContainer = null
var _body: VBoxContainer = null
var _layer: CanvasLayer = null
var _overworld: Node = null
var _rng := RandomNumberGenerator.new()

const ACCENT := Color(0.61, 0.35, 0.71)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()

# Entry point. `overworld` is the Overworld2 scene (for teleport fulfilment).
func start(host: Node, loot_index: int, overworld: Node) -> void:
	_overworld = overworld
	_layer = CanvasLayer.new()
	_layer.layer = 120
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if loot_index < 0 or loot_index >= GameState.loot_items.size():
		_finish()
		return
	var entry = GameState.loot_items[loot_index]
	if not (entry is Dictionary) or String(entry.get("type", "")) != "scroll" or not entry.has("id"):
		_finish()
		return
	_scroll = Data.get_scroll(StringName(entry.get("id", "")))
	if _scroll == null:
		_finish()
		return
	_loot_index = loot_index
	_show_intro()

# ---------------------------------------------------------------------------
# Intro screen — show the scroll and offer Read.
# ---------------------------------------------------------------------------

func _show_intro() -> void:
	_rebuild_panel()
	var identified: bool = ScrollSystem.is_identified(_scroll.id)
	var art := TextureRect.new()
	art.texture = ScrollSystem.art_texture(_scroll)
	art.custom_minimum_size = Vector2(96, 96)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(art)
	_body.add_child(_heading("📜 " + ScrollSystem.display_name(_scroll), ACCENT, 22))
	if identified:
		_body.add_child(_muted("%s Preference" % _scroll.preference))
		_body.add_child(_muted(_effect_summary()))
	else:
		_body.add_child(_muted("Unidentified — reading it is a gamble. Its Preference could be Positive, Negative, or Neutral."))
	var read_btn := Button.new()
	read_btn.text = "Read Scroll →"
	read_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	read_btn.pressed.connect(_on_read)
	_body.add_child(read_btn)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_finish)
	_body.add_child(cancel)

func _on_read() -> void:
	var result: Dictionary = ScrollSystem.read_scroll(_scroll, {"rng": _rng})
	# The scroll is consumed on read.
	GameState.remove_loot_at(_loot_index)
	for line in result.get("logs", []):
		GameLog.add(String(line), ACCENT)
	_requests = result.get("requests", [])
	_process_next_request()

# ---------------------------------------------------------------------------
# Requests — interactive follow-ups returned by read_scroll
# ---------------------------------------------------------------------------

func _process_next_request() -> void:
	if _requests.is_empty():
		_finish()
		return
	var req: Dictionary = _requests.pop_front()
	match String(req.get("kind", "")):
		"identify_scrolls":
			_pick_identify(req)
		"stun_enemies":
			_pick_stun(req)
		"teleport":
			_do_teleport(req)
		_:
			_process_next_request()

# --- Identify which scrolls (choose up to N) -------------------------------
func _pick_identify(req: Dictionary) -> void:
	var candidates: Array = req.get("candidates", [])
	var max_pick: int = int(req.get("count", 1))
	var selected: Dictionary = {}
	_rebuild_panel()
	_body.add_child(_heading("Identify Scrolls", ACCENT, 20))
	_body.add_child(_muted("Choose up to %d to identify." % max_pick))
	for id in candidates:
		var s: ScrollData = Data.get_scroll(id)
		var nm: String = s.display_name if s != null else String(id)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "📜 " + nm
		btn.toggled.connect(func(on): _toggle_select(selected, id, on, max_pick, btn))
		_body.add_child(btn)
	var confirm := Button.new()
	confirm.text = "Identify Selected"
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(func():
		ScrollSystem.identify_scrolls_chosen(selected.keys())
		_process_next_request())
	_body.add_child(confirm)

# --- Stun which following enemy (choose up to N) ---------------------------
func _pick_stun(req: Dictionary) -> void:
	var max_pick: int = int(req.get("count", 1))
	var selected: Dictionary = {}   # instance -> true
	_rebuild_panel()
	_body.add_child(_heading("Scare a Monster", ACCENT, 20))
	if GameLoop2.stack.is_empty():
		_body.add_child(_muted("No following enemies to Stun."))
		_body.add_child(_continue_button())
		return
	_body.add_child(_muted("Choose up to %d following enemy to Stun (it loses its next turn — %s)."
		% [max_pick, _stun_worth()]))
	for entry in GameLoop2.stack:
		var e: GoalEnemyData = entry["enemy"]
		var inst: int = int(entry["instance"])
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s — %s" % [e.display_name, GameLoop2.goal_text_for(entry)]
		btn.toggled.connect(func(on): _toggle_select(selected, inst, on, max_pick, btn))
		_body.add_child(btn)
	var confirm := Button.new()
	confirm.text = "Stun Selected"
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(func():
		ScrollSystem.stun_enemies_chosen(selected.keys())
		_process_next_request())
	_body.add_child(confirm)

func _toggle_select(selected: Dictionary, key, on: bool, max_pick: int, btn: Button) -> void:
	if on:
		if selected.size() >= max_pick:
			btn.set_pressed_no_signal(false)
			return
		selected[key] = true
	else:
		selected.erase(key)

# --- Teleport — fulfilled by the overworld --------------------------------
func _do_teleport(req: Dictionary) -> void:
	if _overworld != null and _overworld.has_method("scroll_teleport"):
		_overworld.scroll_teleport(String(req.get("dir", "same")), int(req.get("spread", 1)))
	else:
		GameLog.add("The Scroll of Teleportation fizzles.", ACCENT)
	_process_next_request()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _effect_summary() -> String:
	var parts: Array = []
	for e in _scroll.effect:
		if not (e is Dictionary):
			continue
		match String(e.get("op", "")):
			"buff_enemies":
				parts.append("Enemies deal +%d damage for %d game(s)." % [int(e.get("damage", 1)), int(e.get("games", 1))])
			"forget":
				parts.append("Forget %d random scroll(s)." % int(e.get("count", 1)))
			"spawn_enemy":
				parts.append("Spawn a random enemy that follows you.")
			"identify_scrolls":
				parts.append("Choose %d scroll(s) to identify." % int(e.get("count", 1)))
			"stun_enemies":
				parts.append("Choose %d following enemy to Stun." % int(e.get("count", 1)))
			"teleport":
				parts.append("Teleport ~the same distance from the Amulet.")
	return " ".join(parts)

func _continue_button() -> Button:
	var b := Button.new()
	b.text = "Continue"
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_process_next_request)
	return b

func _finish() -> void:
	finished.emit()
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()

func _rebuild_panel() -> void:
	for c in get_children():
		c.queue_free()
	_panel = ModalScaffold.build_panel(self, ACCENT, Callable(), Vector2(440, 460))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(404, 420)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(scroll)
	_panel.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

# What one stun is actually worth where the run is standing (§7.4). A stun costs
# the target one TURN, and a turn is the whole game out in the wilds but only a
# third of one on the Amulet's doorstep — so the scroll has to price itself
# against the current pace rather than promising "skips its next attack", which
# stopped being true the moment enemies started taking more than one turn.
func _stun_worth() -> String:
	var turns: int = GameLoop2.enemy_turns()
	if turns <= 1:
		return "its whole game, at 1 turn per game here"
	return "1 of the %d turns it gets per game here" % turns

func _heading(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

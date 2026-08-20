extends Control

# The games-first (2.0) "spend a piece of loot" flow, as a self-contained
# full-screen modal (§4.1 scrolls, §4.3 pills). The loot window opens one with
# start(host, loot_index, overworld); the modal owns the rest:
#   1. show the piece — its art and, when the type is UNIDENTIFIED, a masked name
#      and no Preference, because that mask is the gamble the player is taking.
#   2. on Use: LootSystem.use_loot, which consumes the entry, resolves it through
#      whichever system owns it, and fires Echo Chamber's copies of the last three
#      used. Then walk the returned `requests` (identify-which / stun-which /
#      teleport) through small pickers.
#   3. emit `finished` and free itself so the page refreshes.
#
# IT IS ONE MODAL FOR BOTH KINDS deliberately. A pill needs fewer words than a
# scroll, but the two need the same THREE things — a look at what you are about
# to spend, a confirm, and somewhere for a follow-up choice to be made — and the
# echo means either kind can hand back a request that belongs to the other.
#
# Built entirely in code (no scene file), on its own CanvasLayer so it always
# centers over the overworld regardless of what opened it.

signal finished

# The carried entry being spent: {"type": "scroll"|"pill", "id": …, "horse": …}.
var _entry: Dictionary = {}
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
	if not (entry is Dictionary) or not entry.has("id"):
		_finish()
		return
	_entry = (entry as Dictionary).duplicate(true)
	_loot_index = loot_index
	_show_intro()

func _is_pill() -> bool:
	return String(_entry.get("type", "")) == "pill"

# ---------------------------------------------------------------------------
# Intro screen — show the scroll and offer Read.
# ---------------------------------------------------------------------------

func _show_intro() -> void:
	_rebuild_panel()
	var identified: bool = LootSystem.is_identified(_entry)
	var art := TextureRect.new()
	art.texture = LootSystem.art_texture(_entry)
	art.custom_minimum_size = Vector2(96, 96)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_body.add_child(art)
	_body.add_child(_heading("%s %s" % [LootSystem.glyph(_entry), LootSystem.display_name(_entry)],
		ACCENT, 22))
	var summary: String = LootSystem.description(_entry)
	if identified:
		_body.add_child(_muted("%s Preference" % LootSystem.preference(_entry)))
		_body.add_child(_muted(summary))
		# The KEYWORD STRIP (§17), on the same terms an item card carries one: what
		# a Scroll of Fire does is written in the names of three mechanics, and the
		# reader is about to spend it on the strength of that sentence. Only on an
		# IDENTIFIED piece — an unidentified one deliberately says nothing about what
		# it does, and a strip naming Burn and Fire under "this is a gamble" would
		# give the whole thing away.
		Keywords.attach(_body, summary)
	elif _is_pill():
		# A pill hides its NAME, never its capsule (§4.3) — the art above is the
		# thing being learned, so the gamble line says what is unknown rather than
		# pretending the tile is a mystery.
		_body.add_child(_muted("You have never taken this one. Its Preference could be Positive, Negative, or Neutral — taking it is how you find out what the colour means."))
	else:
		_body.add_child(_muted("Unidentified — reading it is a gamble. Its Preference could be Positive, Negative, or Neutral."))
	if _echo_note() != "":
		_body.add_child(_muted(_echo_note()))
	var read_btn := Button.new()
	read_btn.text = "Take Pill →" if _is_pill() else "Read Scroll →"
	read_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	read_btn.pressed.connect(_on_read)
	_body.add_child(read_btn)

# What Echo Chamber is about to add, named rather than left as a surprise: the
# relic changes what SPENDING one piece of loot means, and a player who cannot see
# the three copies coming cannot plan around them (§4.3).
func _echo_note() -> String:
	var depth: int = GameState.loot_echo_depth()
	if depth <= 0:
		return ""
	var memory: Array = LootSystem.used_memory()
	if memory.is_empty():
		return "Echo Chamber: nothing used yet for it to copy."
	var names: Array = []
	for i in range(memory.size() - 1, maxi(0, memory.size() - depth) - 1, -1):
		names.append(LootSystem.display_name(memory[i]))
	return "Echo Chamber will also use: %s." % ", ".join(PackedStringArray(names))
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_finish)
	_body.add_child(cancel)

func _on_read() -> void:
	# Through LootSystem rather than straight into ScrollSystem: consuming the
	# entry, Echo Chamber's replay of the last three pieces used, and the memory
	# this use joins are all things that happen AROUND a use and belong to neither
	# consumable system (§4.3). What comes back is the merged result — this scroll's
	# logs and requests plus every echo's — so a teleport fired twice is fulfilled
	# twice rather than silently once.
	var result: Dictionary = LootSystem.use_loot(_loot_index, {"rng": _rng})
	for line in result.get("logs", []):
		GameLog.add(String(line), ACCENT)
	_requests = result.get("requests", [])
	_process_next_request()

# ---------------------------------------------------------------------------
# Requests — interactive follow-ups returned by the use (and by its echoes)
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
	if _overworld != null and _overworld.has_method("loot_teleport"):
		_overworld.loot_teleport(req)
	else:
		GameLog.add("The Scroll of Teleportation fizzles.", ACCENT)
	_process_next_request()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

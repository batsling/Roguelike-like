class_name ScrollUseModal
extends Control

# The out-of-combat "read a scroll" flow, as a self-contained full-screen modal.
# The Backpack (the single scroll entry point) instantiates one, adds it as a
# child, and calls start(loot_index); the modal owns everything after that:
#   1. identify the scroll, roll the outcome (auto-roll, mirroring the legacy
#      web build), and show the result screen (dice math + outcome prose).
#   2. on Apply, run ScrollSystem.apply_outcome and walk any returned `requests`
#      (identify-which / pick-weapon / pick-food / teleport) through small
#      pickers, calling the matching ScrollSystem fulfilment helper.
#   3. emit `finished` and free itself so the Backpack can refresh.
#
# Built entirely in code (no scene file) and PROCESS_MODE_ALWAYS so it works
# over the paused Backpack.

signal finished

var _scroll: ScrollData = null
var _tier: String = "good"
var _roll: Dictionary = {}
var _requests: Array = []
var _panel: PanelContainer = null
var _body: VBoxContainer = null
var _rng := RandomNumberGenerator.new()
# Own top CanvasLayer so the modal is always centered on the full viewport,
# regardless of the host's size/position (the Backpack panel isn't full-screen,
# which pushed the modal off-screen when it was parented straight to it).
var _layer: CanvasLayer = null

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()

# Entry point. Mounts on its own layer over `host`, then resolves the scroll at
# loot_index, identifies + rolls it, removes it from loot, and shows the result
# screen. Aborts (and finishes) if the entry isn't a usable scroll or enemies are
# near.
func start(host: Node, loot_index: int) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if not GameState.can_use_scrolls():
		Notifications.notify("You can't read scrolls with enemies nearby.", ScrollSystem.SCROLL_COLOR)
		_finish()
		return
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
	ScrollSystem.identify(_scroll.id)
	_roll = ScrollSystem.resolve_outcome(_rng)
	_tier = String(_roll.get("tier", "good"))
	GameState.remove_loot_at(loot_index)
	_show_result()

# ---------------------------------------------------------------------------
# Result screen
# ---------------------------------------------------------------------------

func _show_result() -> void:
	var accent: Color = ScrollSystem.TIER_COLORS.get(_tier, Color.WHITE)
	_rebuild_panel(accent)

	var title := _heading("📜 " + _scroll.display_name, ScrollSystem.SCROLL_COLOR, 24)
	_body.add_child(title)

	var label := _heading(String(ScrollSystem.TIER_LABELS.get(_tier, "")), accent, 20)
	_body.add_child(label)

	var dc: int = ScrollSystem.SCROLL_DC
	var ok: bool = bool(_roll.get("success", false))
	var sline := "%d + %d INT = %d  %s  DC %d  %s" % [
		int(_roll.get("roll1", 0)), int(_roll.get("int_stat", 0)), int(_roll.get("total1", 0)),
		"≥" if ok else "<", dc, "✓" if ok else "✗"]
	_body.add_child(_muted(sline))
	var crit: bool = bool(_roll.get("is_crit", false))
	_body.add_child(_muted("Crit die: %d — %s" % [int(_roll.get("roll2", 0)),
		"Critical!" if crit else "Not Critical"]))

	var desc := _scroll.outcome_text(_tier)
	if desc != "":
		var box := _outcome_box(desc)
		_body.add_child(box)

	var apply_btn := Button.new()
	apply_btn.text = "Apply Effect →"
	apply_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apply_btn.pressed.connect(_on_apply)
	_body.add_child(apply_btn)

func _on_apply() -> void:
	var result: Dictionary = ScrollSystem.apply_outcome(_scroll, _tier, {"rng": _rng})
	for line in result.get("logs", []):
		GameLog.add(String(line), ScrollSystem.SCROLL_COLOR)
	_requests = result.get("requests", [])
	_process_next_request()

# ---------------------------------------------------------------------------
# Requests — interactive follow-ups returned by apply_outcome
# ---------------------------------------------------------------------------

func _process_next_request() -> void:
	if _requests.is_empty():
		_finish()
		return
	var req: Dictionary = _requests.pop_front()
	match String(req.get("kind", "")):
		"identify_scrolls":
			_pick_identify(req)
		"pick_weapon":
			_pick_weapon(req)
		"create_food":
			_pick_food(req)
		"teleport":
			_do_teleport(req)
		_:
			_process_next_request()

# --- Identify which scrolls (choose up to N) -------------------------------
func _pick_identify(req: Dictionary) -> void:
	var candidates: Array = req.get("candidates", [])
	var max_pick: int = int(req.get("count", 1))
	var selected: Dictionary = {}
	_rebuild_panel(ScrollSystem.SCROLL_COLOR)
	_body.add_child(_heading("Identify Scrolls", ScrollSystem.SCROLL_COLOR, 20))
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

func _toggle_select(selected: Dictionary, key, on: bool, max_pick: int, btn: Button) -> void:
	if on:
		if selected.size() >= max_pick:
			btn.set_pressed_no_signal(false)
			return
		selected[key] = true
	else:
		selected.erase(key)

# --- Pick a weapon card to enchant / vorpalize -----------------------------
func _pick_weapon(req: Dictionary) -> void:
	var op := String(req.get("op", "enchant"))
	var dmg: int = int(req.get("dmg", 0))
	var retain: bool = bool(req.get("retain", false))
	var cards: Array = req.get("cards", [])
	_rebuild_panel(Color(0.90, 0.55, 0.16))
	var verb := "Enchant" if op == "enchant" else "Vorpalize"
	_body.add_child(_heading("%s a Weapon Attack Card" % verb, Color(0.90, 0.55, 0.16), 20))
	for ci in cards:
		var btn := Button.new()
		btn.text = "⚔️ " + ci.data.display_name
		btn.pressed.connect(func():
			if op == "enchant":
				ScrollSystem.enchant_card(ci, dmg, retain)
			else:
				ScrollSystem.vorpalize_card(ci, dmg, _rng)
			_process_next_request())
		_body.add_child(btn)

# --- Pick one of N food items ----------------------------------------------
func _pick_food(req: Dictionary) -> void:
	var choices: Array = req.get("choices", [])
	_rebuild_panel(Color(0.3, 0.75, 0.35))
	_body.add_child(_heading("🍎 Choose a Food Item", Color(0.3, 0.75, 0.35), 20))
	for item in choices:
		var btn := Button.new()
		btn.text = "%s (%s)" % [item.display_name, _rarity_name(item)]
		btn.pressed.connect(func():
			ScrollSystem.give_food_item(item)
			_process_next_request())
		_body.add_child(btn)

# --- Teleport — fulfilled by the overworld if we're on it ------------------
func _do_teleport(req: Dictionary) -> void:
	var ow = GameState.overworld_scene
	if ow != null and ow.has_method("scroll_teleport"):
		ow.scroll_teleport(String(req.get("dir", "random")), int(req.get("max_steps", 0)))
	else:
		GameLog.add("The Scroll of Teleportation fizzles — you must be on the overworld.",
			ScrollSystem.SCROLL_COLOR)
	_process_next_request()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _finish() -> void:
	finished.emit()
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()

# Clears and rebuilds the centered panel + a fresh scrolling body VBox.
func _rebuild_panel(accent: Color) -> void:
	for c in get_children():
		c.queue_free()
	_panel = ModalScaffold.build_panel(self, accent, Callable(), Vector2(440, 460))
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
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return l

func _outcome_box(text: String) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.06)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	box.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.87, 0.87, 0.87))
	box.add_child(l)
	return box

func _rarity_name(item: ItemData) -> String:
	var names := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
	var idx: int = int(item.rarity)
	return names[idx] if idx >= 0 and idx < names.size() else "Common"

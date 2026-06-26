class_name StunPickerModal
extends Control

# Combat-start "choose up to N enemies to Stun" picker for Scroll of Scare
# Monster's good / bad (choose) tiers. Reused by every combat mode: it operates
# on a list of living enemy actors that each expose add_status(&"stun", 1) and a
# name (CombatActor.display_name / BattleUnit.unit_name), so deckbuilder,
# strategy and action all drive the same UI.
#
# If there are no more enemies than the cap, it stuns them all immediately
# without showing UI (mirroring the legacy _showCombatStunPicker shortcut).
# Built in code on ModalScaffold; PROCESS_MODE_ALWAYS so it works over a paused
# action room.

signal finished

var _enemies: Array = []
var _max: int = 1
var _selected: Dictionary = {}
var _on_done: Callable = Callable()
var _body: VBoxContainer = null
# Own high CanvasLayer so the picker always draws over the combat UI, whether the
# host is a plain Control (deckbuilder/action) or a CanvasLayer (strategy).
var _layer: CanvasLayer = null

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

# Mounts over `host` on a dedicated top layer, then either auto-stuns all (when
# count >= living enemies) or shows the picker. `on_done` fires after the choice
# resolves (e.g. for action to unpause). Caller:
#   StunPickerModal.new().start(host, enemies, n, on_done)
func start(host: Node, living: Array, max_count: int, on_done: Callable = Callable()) -> void:
	_enemies = living.filter(func(e): return _is_alive(e))
	_max = maxi(1, max_count)
	_on_done = on_done
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_layer)
	_layer.add_child(self)
	if _enemies.size() <= _max:
		for e in _enemies:
			e.add_status(&"stun", 1)
		if not _enemies.is_empty():
			GameLog.add("Scroll of Scare Monster: %d enem%s Stunned!" % [
				_enemies.size(), "y" if _enemies.size() == 1 else "ies"], Color(0.9, 0.85, 0.5))
		_finish()
		return
	_build()

func _build() -> void:
	var accent := Color(0.945, 0.769, 0.059)
	var panel := ModalScaffold.build_panel(self, accent, Callable(), Vector2(380, 440))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	var title := Label.new()
	title.text = "😱 Scare Monster"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", accent)
	_body.add_child(title)
	var sub := Label.new()
	sub.text = "Choose up to %d enem%s to Stun." % [_max, "y" if _max == 1 else "ies"]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_body.add_child(sub)

	for e in _enemies:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "👹 " + _name(e)
		btn.toggled.connect(func(on): _toggle(e, on, btn))
		_body.add_child(btn)

	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(_on_confirm)
	_body.add_child(confirm)

func _toggle(enemy, on: bool, btn: Button) -> void:
	if on:
		if _selected.size() >= _max:
			btn.set_pressed_no_signal(false)
			return
		_selected[enemy] = true
	else:
		_selected.erase(enemy)

func _on_confirm() -> void:
	for e in _selected.keys():
		e.add_status(&"stun", 1)
	if not _selected.is_empty():
		GameLog.add("Scroll of Scare Monster: %d enem%s Stunned!" % [
			_selected.size(), "y" if _selected.size() == 1 else "ies"], Color(0.9, 0.85, 0.5))
	_finish()

func _finish() -> void:
	if _on_done.is_valid():
		_on_done.call()
	finished.emit()
	if _layer != null:
		_layer.queue_free()
	else:
		queue_free()

func _is_alive(e) -> bool:
	return e != null and e.has_method("is_alive") and e.is_alive()

func _name(e) -> String:
	if e == null:
		return "Enemy"
	if "display_name" in e and String(e.display_name) != "":
		return String(e.display_name)
	if "unit_name" in e and String(e.unit_name) != "":
		return String(e.unit_name).capitalize()
	return "Enemy"

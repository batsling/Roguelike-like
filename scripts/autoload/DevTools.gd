extends Node

# THE DEVELOPER PANEL'S DOOR. Press ` (backtick) with Settings.dev_mode on and the
# panel (scripts/dev/DevPanel.gd) opens over whatever scene is running.
#
# A STUB, ON PURPOSE (27 Nov 2026). The panel is a thousand lines, and as an
# autoload it was compiled on every boot — ~170 ms of every launch and every test
# run — for a tool a normal session never opens. This keeps the key and loads the
# panel BY PATH the first time it is wanted, so nothing names it at boot.
#
# The handful of members the tests reach for are forwarded to the panel, which
# is built on the first of them to be asked for.

const PANEL_SCRIPT := "res://scripts/dev/DevPanel.gd"
const TOGGLE_KEY := KEY_QUOTELEFT     # the ` / ~ key

var _panel: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == TOGGLE_KEY and Settings.dev_mode:
		panel()._toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _is_open():
		_close()
		get_viewport().set_input_as_handled()

# The panel, built the first time anything asks for it.
func panel() -> Node:
	if _panel == null or not is_instance_valid(_panel):
		_panel = load(PANEL_SCRIPT).new()
		_panel.name = "DevPanel"
		add_child(_panel)
	return _panel

func is_loaded() -> bool:
	return _panel != null and is_instance_valid(_panel)

# --- forwarded to the panel ------------------------------------------------------

func _is_open() -> bool:
	return is_loaded() and _panel._is_open()

func _toggle() -> void:
	panel()._toggle()

func _close() -> void:
	if is_loaded():
		_panel._close()

func _rebuild() -> void:
	panel()._rebuild()

func item_pool() -> Array:
	return panel().item_pool()

var TABS: Array:
	get: return panel().TABS
var GRANT_KINDS: Array:
	get: return panel().GRANT_KINDS
var _body: VBoxContainer:
	get: return panel()._body
var _tab: String:
	get: return panel()._tab
	set(v): panel()._tab = v
var _grant_kind: String:
	get: return panel()._grant_kind
	set(v): panel()._grant_kind = v
var _grant_horse: bool:
	get: return panel()._grant_horse
	set(v): panel()._grant_horse = v

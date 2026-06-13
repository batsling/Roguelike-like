class_name PauseMenu
extends Control

# In-run pause menu. Mounted once by Main on a high CanvasLayer (like the
# backpack) and toggled with the "pause_menu" action (Enter). Opening it pauses
# the tree; closing unpauses. Offers Resume, Open Tier List, Settings, and Save
# & Exit to Menu.
#
# Runs PROCESS_MODE_ALWAYS so it keeps receiving input while the tree is paused.
# Uses _unhandled_input (not _input) for the toggle so a focused text field
# elsewhere — e.g. the rate-game notes box — keeps Enter for itself.

const MAIN_MENU_SCENE := "res://scenes/menu/MainMenu.tscn"

var _panel: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Anchored to the top-left and sized explicitly to the viewport every frame
	# the window resizes. Relying on PRESET_FULL_RECT alone left the root Control
	# at size (0,0) on some layouts, which pushed the centre-anchored panel into
	# the top-left corner (half of it off-screen). Sizing it ourselves keeps the
	# panel reliably centred.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()

func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size

func _unhandled_input(event: InputEvent) -> void:
	# Defer to any open sub-overlay (tier list / settings) — it handles its own
	# Esc/Enter and frees itself first.
	if _overlay_open():
		return
	if event.is_action_pressed("pause_menu"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _overlay_open() -> bool:
	for c in get_children():
		if c is TierListScreen or c is SettingsModal:
			return true
	return false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

# ------------------------------------------------------------------
# UI
# ------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# A full-rect CenterContainer centres the panel at its own minimum size,
	# independent of any anchor/viewport quirks.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_menu_button("Resume", close))
	vbox.add_child(_menu_button("Tier List", _on_tier_list))
	vbox.add_child(_menu_button("⚙ Settings", _on_settings))
	vbox.add_child(_menu_button("Save & Exit to Menu", _on_save_exit))

func _menu_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 48)
	b.pressed.connect(handler)
	return b

func _on_tier_list() -> void:
	TierListScreen.open(self)

func _on_settings() -> void:
	SettingsModal.open(self)

func _on_save_exit() -> void:
	# Mirror Overworld._save_run: prefer the named save, fall back to slot 0
	# for debug-bootstrapped runs.
	if GameState.save_name != "":
		SaveSystem.save_named(GameState.save_name)
	else:
		SaveSystem.save(0)
	GameLog.add("Run saved. Returning to menu.", Color(0.7, 0.8, 1.0))
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

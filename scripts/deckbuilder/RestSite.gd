class_name RestSite
extends Control

# Rest-node modal: pick Heal / Smith / Skip. Standalone so it can be
# reused from map rest nodes or future event outcomes. Emits `closed`
# once the player commits to a choice; the caller free()s.

signal closed

const HEAL_PERCENT := 0.33

var _heal_amount: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	@warning_ignore("integer_division")
	_heal_amount = int(GameState.max_hp * HEAL_PERCENT)
	_build_ui()

# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(640, 380)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 20)
	title.size = Vector2(600, 32)
	title.text = "Rest Site"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var hint := Label.new()
	hint.position = Vector2(20, 60)
	hint.size = Vector2(600, 24)
	hint.text = "Pick one. You may take only one option at a rest site."
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)

	var row := HBoxContainer.new()
	row.position = Vector2(20, 110)
	row.size = Vector2(600, 200)
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	var heal_btn := Button.new()
	heal_btn.custom_minimum_size = Vector2(180, 180)
	heal_btn.text = "Heal\n\n+%d HP\n(33%% of max)" % _heal_amount
	heal_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	heal_btn.pressed.connect(_on_heal)
	row.add_child(heal_btn)

	var smith_btn := Button.new()
	smith_btn.custom_minimum_size = Vector2(180, 180)
	smith_btn.text = "Smith\n\nUpgrade 1 card\nfor the rest of\nthe run"
	smith_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	smith_btn.pressed.connect(_on_smith)
	row.add_child(smith_btn)

	var skip_btn := Button.new()
	skip_btn.custom_minimum_size = Vector2(180, 180)
	skip_btn.text = "Skip\n\n(nothing)"
	skip_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	skip_btn.pressed.connect(_on_skip)
	row.add_child(skip_btn)

# ---------------------------------------------------------------------------
# Choice handlers
# ---------------------------------------------------------------------------

func _on_heal() -> void:
	GameState.change_hp(_heal_amount)
	GameLog.add("You rest. (+%d HP)" % _heal_amount, Color(0.7, 1.0, 0.7))
	emit_signal("closed")

func _on_skip() -> void:
	GameLog.add("You skip the rest site.", Color(0.7, 0.7, 0.7))
	emit_signal("closed")

func _on_smith() -> void:
	_show_smith_picker()

# ---------------------------------------------------------------------------
# Smith sub-modal — pick a single upgradeable deck card.
# ---------------------------------------------------------------------------

func _show_smith_picker() -> void:
	var picker := Control.new()
	picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	picker.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(680, 520)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	picker.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 16)
	title.size = Vector2(640, 28)
	title.text = "Pick a card to upgrade"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 60)
	scroll.size = Vector2(640, 400)
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var picked_any := false
	for c in GameState.deck:
		if not (c is CardInstance):
			continue
		var inst: CardInstance = c
		if not inst.can_take_upgrade():
			continue
		picked_any = true
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(620, 40)
		btn.text = "[%d] %s   --  %s" % [
			inst.get_cost(), inst.get_display_name(), inst.get_description(),
		]
		var inst_ref: CardInstance = inst
		var picker_ref: Control = picker
		btn.pressed.connect(func(): _commit_smith(inst_ref, picker_ref))
		vbox.add_child(btn)

	if not picked_any:
		var empty := Label.new()
		empty.text = "No upgradeable cards in your deck."
		empty.add_theme_color_override("font_color", Color(0.85, 0.7, 0.5))
		vbox.add_child(empty)

	var cancel_btn := Button.new()
	cancel_btn.position = Vector2(280, 470)
	cancel_btn.size = Vector2(120, 40)
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): picker.queue_free())
	panel.add_child(cancel_btn)

	add_child(picker)

func _commit_smith(inst: CardInstance, picker: Control) -> void:
	inst.apply_upgrade()
	GameLog.add("Smith: %s upgraded." % inst.get_display_name(), Color(1.0, 0.85, 0.4))
	GameState.emit_signal("deck_changed")
	picker.queue_free()
	emit_signal("closed")

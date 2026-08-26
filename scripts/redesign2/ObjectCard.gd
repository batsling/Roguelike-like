class_name ObjectCard
extends PanelContainer

# ONE MACHINE, drawn (docs/object-sheet-authoring.md).
#
# The same card in both places an object can appear, which is the point of it
# being its own class:
#
#   * inside the EVENT MODAL, when an event spawned it — the Arcade Room is a
#     room you are standing in and the cabinets are in the room with you, so
#     they are laid out inside the modal and the room's own `Leave` is what
#     takes you out;
#   * UNDER THE BOARD, in the shop's space, when anything else spawned it. There
#     is no Leave there because there is nothing to leave: you walk away from a
#     machine by travelling on, and that is what clears it.
#
# The card is a VIEW. Every rule it draws — whether a button is offered, why it
# is greyed, what a press does — is asked of ObjectSystem, which asks
# EventSystem, which is the same code an event's buttons go through. A machine
# and a room disagreeing about what `needs bombs 1` means is the bug this
# arrangement exists to make impossible.

const ART_PX := 96
# Wide enough for two machines side by side inside the event modal at its normal
# width, and to sit under the board without pushing the right column wider.
const CARD_WIDTH := 268.0

# The instance dictionary from ObjectSystem.live — { id, picks }. Held by
# reference, so a press recorded there is a press this card sees.
var _inst: Dictionary = {}
var _data: ObjectData = null

var _prose_box: VBoxContainer = null
var _choice_box: VBoxContainer = null
var _last_result: String = ""
var _last_text: String = ""


static func make(inst: Dictionary) -> ObjectCard:
	var card := ObjectCard.new()
	card._inst = inst
	card._data = ObjectSystem.data_for(inst)
	return card


func _ready() -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel",
		UITheme.panel_box(UITheme.PANEL, UITheme.ACCENT.lerp(UITheme.BORDER, 0.5), 10, 10, 1))
	if not ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.connect(_on_objects_changed)
	if not GameState.stats_changed.is_connected(_on_objects_changed):
		GameState.stats_changed.connect(_on_objects_changed)
	if not GameState.gold_changed.is_connected(_on_objects_changed):
		GameState.gold_changed.connect(_on_objects_changed)
	# Health has its own signal, and this card reads it twice over: a Health cost
	# is what reddens a button, and losing Health elsewhere can make a machine
	# lethal without the machine being touched.
	if not GameState.hp_changed.is_connected(_on_objects_changed):
		GameState.hp_changed.connect(_on_objects_changed)
	_build()


func _exit_tree() -> void:
	if ObjectSystem.objects_changed.is_connected(_on_objects_changed):
		ObjectSystem.objects_changed.disconnect(_on_objects_changed)
	if GameState.stats_changed.is_connected(_on_objects_changed):
		GameState.stats_changed.disconnect(_on_objects_changed)
	if GameState.gold_changed.is_connected(_on_objects_changed):
		GameState.gold_changed.disconnect(_on_objects_changed)
	if GameState.hp_changed.is_connected(_on_objects_changed):
		GameState.hp_changed.disconnect(_on_objects_changed)


# Every button on the card is gated on something that moves — the purse, the
# bomb count, the bank, the jam — so the whole card repaints rather than trying
# to work out which button the last press invalidated.
func _on_objects_changed() -> void:
	if _data != null and is_inside_tree():
		_render()


func _build() -> void:
	if _data == null:
		return
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var title := Label.new()
	title.text = _data.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	root.add_child(title)

	var tex: Texture2D = _art()
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		var aspect: float = float(tex.get_height()) / maxf(1.0, float(tex.get_width()))
		rect.custom_minimum_size = Vector2(ART_PX, ART_PX * aspect)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UITheme.apply_crisp(rect, tex)
		root.add_child(rect)

	_prose_box = VBoxContainer.new()
	_prose_box.add_theme_constant_override("separation", 4)
	root.add_child(_prose_box)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 5)
	root.add_child(_choice_box)
	_render()


func _art() -> Texture2D:
	var file: String = _data.art_file()
	if file == "":
		return null
	var path: String = "res://images2.0/objects/%s.png" % file
	return load(path) if ResourceLoader.exists(path) else null


func _render() -> void:
	if _prose_box == null or _choice_box == null:
		return
	for child in _prose_box.get_children():
		child.queue_free()
	for child in _choice_box.get_children():
		child.queue_free()

	# Most machines say nothing — the Blood Donation Machine keeps Isaac's
	# silence — so the prompt is only drawn when there is one.
	if _data.prompt != "":
		_prose_box.add_child(_prose(_data.prompt, UITheme.TEXT, 12))
	# The Donation Machine's bank is the one piece of machine state worth showing
	# unprompted: it is the number every press moves and the reason to bomb it.
	var bank_line: String = _bank_line()
	if bank_line != "":
		_prose_box.add_child(_prose(bank_line, UITheme.COIN_GOLD, 12))
	if _last_result != "":
		_prose_box.add_child(_prose(_last_result, UITheme.TEXT_DIM, 12))
	if _last_text != "":
		_prose_box.add_child(_prose(_last_text, UITheme.TEXT_FAINT, 11))

	for i in range(_data.choices.size()):
		_choice_box.add_child(_choice_button(i, _data.choices[i]))


# "Holds 37 of 999 gold" — only for a machine that actually banks, which is
# every machine carrying a `donate_gold` or `bank_payout` button. Read off the
# authored effects rather than off the object's id, so a second banking machine
# gets the line without this file learning its name.
func _bank_line() -> String:
	if not _has_effect(["donate_gold", "bank_payout"]):
		return ""
	return "Holds %d of %d gold." % [ObjectSystem.bank(), ObjectSystem.BANK_CAP]


func _has_effect(types: Array) -> bool:
	for choice in _data.choices:
		for eff in choice.get("effects", []):
			if eff is Dictionary and types.has(String(eff.get("type", ""))):
				return true
	return false


# A machine's button. Unlike an event's, an unavailable one is DRAWN AND GREYED
# rather than dropped: a machine is a physical thing standing in front of you and
# its buttons do not vanish because you cannot afford them. The refusal goes on
# the button itself — "Jammed", "Full", "Needs 1 Bomb" — because the reason is
# the whole of what the player wants to know.
func _choice_button(index: int, choice: Dictionary) -> Control:
	var taken: int = int((_inst.get("picks", {}) as Dictionary).get(String(choice.get("id", "")), 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)

	var refusal: String = ObjectSystem.choice_refusal(_inst, choice)
	var offered: bool = ObjectSystem.choice_available(_inst, choice)

	var btn := Button.new()
	btn.text = String(choice.get("text", "…"))
	if not offered and refusal != "":
		btn.text = "%s  —  %s" % [btn.text, refusal]
	btn.disabled = not offered
	btn.custom_minimum_size = Vector2(0, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 14)
	# The lever that would kill you wears the warning itself, the same as an
	# event's fatal choice does. Only while the button is actually OFFERED — a
	# jammed machine cannot take your last point of Health, and painting its
	# greyed-out button red would be a threat it can no longer carry out.
	if offered and EventSystem.is_deadly(choice, taken):
		btn.add_theme_stylebox_override("normal", UITheme.lethal_box())
		btn.add_theme_stylebox_override("hover", UITheme.lethal_box(true))
		btn.add_theme_color_override("font_color", UITheme.DANGER)
		btn.add_theme_color_override("font_hover_color", UITheme.TEXT)
	else:
		btn.add_theme_stylebox_override("normal", UITheme.flat(UITheme.BG, 6, 6, 1, UITheme.BORDER))
		btn.add_theme_stylebox_override("hover",
			UITheme.flat(UITheme.PANEL_HI, 6, 6, 2, UITheme.ACCENT))
	# A red lever asks again before it is pulled — the same catch an event's fatal
	# choice wears (EventSystem.confirm_deadly). The Blood Donation Machine is not
	# gated on having Health to spare, so this is the last thing between a stray
	# click and the end of the run.
	btn.pressed.connect(func(): _confirm_then_take(index))
	col.add_child(btn)

	var line: String = EventSystem.describe_choice(choice, taken)
	if line != "":
		var lbl := Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 11)
		# The cost line reddens as the press gets closer to lethal. The Blood
		# Donation Machine is not gated on having Health to spare — you may kill
		# yourself on it, exactly as in Isaac — so this and the warning below are
		# the whole of what stands between the player and that.
		lbl.add_theme_color_override("font_color",
			EventSystem.danger_color(choice, taken) if offered else UITheme.TEXT_FAINT)
		col.add_child(lbl)

	var warning: String = EventSystem.lethal_warning(choice, taken)
	if warning != "" and offered:
		var warn := Label.new()
		warn.text = warning
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", UITheme.DANGER)
		col.add_child(warn)
	return col


# The click path: a press that can end the run is asked about first. `take` stays
# the direct entry, for the tests and anything else pressing a lever in code.
func _confirm_then_take(index: int) -> void:
	if _data == null or index < 0 or index >= _data.choices.size():
		return
	var choice: Dictionary = _data.choices[index]
	var taken: int = int((_inst.get("picks", {}) as Dictionary).get(String(choice.get("id", "")), 0))
	if EventSystem.confirm_deadly(self, choice, taken, func(): take(index)):
		return
	take(index)

# Public so a headless test can press a button without a click.
func take(index: int) -> void:
	if _data == null or index < 0 or index >= _data.choices.size():
		return
	var choice: Dictionary = _data.choices[index]
	var out: Dictionary = ObjectSystem.take(_inst, choice)
	if out.is_empty():
		return
	_last_result = String(out.get("result", ""))
	_last_text = String(out.get("text", ""))
	if _last_text != "":
		GameLog.add("%s — %s: %s" % [_data.display_name, choice.get("text", ""), _last_text],
			UITheme.ACCENT)
	# The press may have destroyed the machine, in which case ObjectSystem has
	# already dropped it from `live` and the host will take this card down on the
	# objects_changed it emitted. Repainting a card mid-removal is harmless, but
	# there is nothing left to say.
	if is_inside_tree():
		_render()


func _prose(text: String, color: Color, size: int) -> Control:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl

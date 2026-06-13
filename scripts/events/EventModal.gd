class_name EventModal
extends Control

# Pre-combat event modal. Shows the event prompt + choices; on a
# stat-check choice runs the two-roll D20 system from the JS event
# engine, then displays the outcome and applies its effects.
#
# Two-roll D20:
#   Roll 1 = D20 + stat-bonus vs difficulty threshold (Easy/Med/Hard/Insane)
#   Roll 2 = D20 (no stat). On Roll 1 pass: 18-20 = crit_good.
#                            On Roll 1 fail: 1-3  = crit_bad.
#   Both rolls get Luck-advantage independently (10% per luck point).
#
# Outcome dict (from EventData.choices[*].outcomes):
#   { "crit_good": { description, effects[] },
#     "good":      { description, effects[] },
#     "bad":       { description, effects[] },
#     "crit_bad":  { description, effects[] } }
# Simple choices use the "outcome" field instead.

signal closed(should_continue: bool)

# Difficulty thresholds match the JS event engine.
const DIFFICULTY_DC := {
	"easy": 11, "medium": 13, "hard": 15, "insane": 17,
}

var _event: EventData
var _difficulty: String = "easy"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# True while the choice buttons are showing — pills may only be used before a
# choice is locked in. Flipped off the moment a choice resolves.
var _choosing: bool = true

# UI refs (built in code).
var _title_label: Label
var _prompt_label: RichTextLabel
var _use_bar: HBoxContainer
var _choices_vbox: VBoxContainer
var _outcome_panel: PanelContainer
var _outcome_label: RichTextLabel
var _roll_label: Label
var _continue_btn: Button

func _ready() -> void:
	_rng.randomize()
	# Mark the event open so the backpack / use-bar allow consuming pills, and
	# so a temp buff used here lasts until the event closes.
	GameState.event_active = true
	_build_ui()
	if _event != null:
		_refresh()

func _exit_tree() -> void:
	# Safety net: whatever path closes the modal, the event is over.
	GameState.event_active = false
	GameState.clear_temp_buffs()

func setup(event: EventData, difficulty: String = "easy") -> void:
	_event = event
	_difficulty = difficulty
	if is_inside_tree():
		_refresh()

# ------------------------------------------------------------------
# UI construction
# ------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.size = Vector2(760, 520)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	# Inner margin via empty MarginContainer would be cleaner but the
	# direct VBox with a fixed offset works for the slice.

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	vbox.add_child(_title_label)

	_prompt_label = RichTextLabel.new()
	_prompt_label.bbcode_enabled = true
	_prompt_label.fit_content = true
	_prompt_label.custom_minimum_size = Vector2(720, 120)
	_prompt_label.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(_prompt_label)

	# Consumable use-bar — pills the player can pop before committing to a
	# choice. A stat pill raises the matching roll for the rest of the event.
	_use_bar = HBoxContainer.new()
	_use_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(_use_bar)

	_choices_vbox = VBoxContainer.new()
	_choices_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_choices_vbox)

	_outcome_panel = PanelContainer.new()
	_outcome_panel.visible = false
	vbox.add_child(_outcome_panel)

	var ovbox := VBoxContainer.new()
	ovbox.add_theme_constant_override("separation", 8)
	_outcome_panel.add_child(ovbox)

	_roll_label = Label.new()
	_roll_label.add_theme_font_size_override("font_size", 12)
	_roll_label.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	ovbox.add_child(_roll_label)

	_outcome_label = RichTextLabel.new()
	_outcome_label.bbcode_enabled = true
	_outcome_label.fit_content = true
	_outcome_label.custom_minimum_size = Vector2(700, 100)
	_outcome_label.add_theme_font_size_override("normal_font_size", 14)
	ovbox.add_child(_outcome_label)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(160, 36)
	_continue_btn.pressed.connect(_on_continue)
	ovbox.add_child(_continue_btn)

# ------------------------------------------------------------------
# Render + interaction
# ------------------------------------------------------------------

func _refresh() -> void:
	_choosing = true
	_title_label.text = _event.display_name
	_prompt_label.text = _event.prompt
	_outcome_panel.visible = false
	for child in _choices_vbox.get_children():
		child.queue_free()
	for choice in _event.choices:
		var btn := Button.new()
		btn.text = _format_choice_text(choice)
		btn.custom_minimum_size = Vector2(720, 44)
		var c: Dictionary = choice
		btn.pressed.connect(func(): _on_choice_selected(c))
		_choices_vbox.add_child(btn)
	_refresh_use_bar()

# Rebuilds the pill use-bar. Visible only during the choosing phase and only
# when the player actually holds usable consumables.
func _refresh_use_bar() -> void:
	for c in _use_bar.get_children():
		c.queue_free()
	var usables: Array = _usable_pills()
	if not _choosing or usables.is_empty():
		_use_bar.visible = false
		return
	_use_bar.visible = true
	var lbl := Label.new()
	lbl.text = "Use:"
	lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	_use_bar.add_child(lbl)
	for item in usables:
		var b := Button.new()
		b.text = item.display_name
		b.tooltip_text = item.description
		var it: ItemData = item
		b.pressed.connect(func(): _on_event_use(it))
		_use_bar.add_child(b)

func _usable_pills() -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.kind == ItemData.ItemKind.USABLE:
			out.append(it)
	return out

func _on_event_use(item: ItemData) -> void:
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.8, 0.9, 1.0))
	# Re-render: a stat pill changes the roll a choice needs, so the choice
	# labels and the use-bar both refresh.
	_refresh()

func _format_choice_text(choice: Dictionary) -> String:
	var text: String = String(choice.get("text", "?"))
	if String(choice.get("type", "simple")) == "stat_check":
		var stat_name: String = String(choice.get("stat", "?"))
		var dc: int = DIFFICULTY_DC.get(_difficulty, 11)
		var stat_value: int = _get_stat_value(stat_name)
		text += "   [%s   need %d+]" % [stat_name.capitalize(), maxi(1, dc - stat_value)]
	return text

func _on_choice_selected(choice: Dictionary) -> void:
	# Lock in the choice: no more pill use past this point.
	_choosing = false
	_refresh_use_bar()
	for btn in _choices_vbox.get_children():
		btn.queue_free()
	if String(choice.get("type", "simple")) == "stat_check":
		_resolve_stat_check(choice)
	else:
		_resolve_simple(choice)

func _resolve_simple(choice: Dictionary) -> void:
	var outcome: Dictionary = choice.get("outcome", {})
	_show_outcome(outcome, "")

func _resolve_stat_check(choice: Dictionary) -> void:
	var stat_name: String = String(choice.get("stat", ""))
	var stat_value: int = _get_stat_value(stat_name)
	var dc: int = DIFFICULTY_DC.get(_difficulty, 11)

	var roll1: int = _roll_d20_with_luck()
	var total1: int = roll1 + stat_value
	var passed: bool = total1 >= dc

	var roll2: int = _roll_d20_with_luck()
	var outcome_key: String
	if passed:
		outcome_key = "crit_good" if roll2 >= 18 else "good"
	else:
		outcome_key = "crit_bad" if roll2 <= 3 else "bad"

	var roll_details := "Roll 1: %d + %d %s = %d vs DC %d  -> %s\nRoll 2: %d  -> %s" % [
		roll1, stat_value, stat_name.substr(0, 3).to_upper(), total1, dc,
		"PASS" if passed else "FAIL",
		roll2, _crit_label(passed, roll2),
	]

	var outcomes: Dictionary = choice.get("outcomes", {})
	var outcome: Dictionary = outcomes.get(outcome_key, outcomes.get("good", {}))
	_show_outcome(outcome, roll_details)

func _crit_label(passed: bool, roll2: int) -> String:
	if passed and roll2 >= 18:
		return "CRITICAL SUCCESS"
	if not passed and roll2 <= 3:
		return "CRITICAL FAILURE"
	return "no crit"

func _roll_d20_with_luck() -> int:
	return Stats.roll_d20_with_luck(_rng)

func _get_stat_value(stat_name: String) -> int:
	# Delegated to Stats so adding a new rollable stat
	# (e.g. constitution events) is a .tres edit, not a code change.
	return Stats.event_roll_bonus(StringName(stat_name.to_lower()))

# ------------------------------------------------------------------
# Outcome resolution
# ------------------------------------------------------------------

func _show_outcome(outcome: Dictionary, roll_details: String) -> void:
	_outcome_panel.visible = true
	_outcome_label.text = String(outcome.get("description", "(no outcome)"))
	_roll_label.text = roll_details
	_roll_label.visible = roll_details != ""
	for effect in outcome.get("effects", []):
		_apply_event_effect(effect)

# Event-time effects don't go through EffectSystem (no combat scene
# to call into). They mutate GameState directly or queue pending data
# for the next combat to drain.
func _apply_event_effect(effect: Dictionary) -> void:
	var t: String = String(effect.get("type", ""))
	match t:
		"heal":
			var n: int = int(effect.get("value", 0))
			GameState.change_hp(n)
			GameLog.add("You heal %d HP." % n, Color(0.6, 1.0, 0.6))
		"lose_hp":
			var n2: int = int(effect.get("value", 0))
			# Percs (event block) soaks damage before it reaches HP.
			var dealt: int = GameState.absorb_event_damage(n2)
			if dealt < n2:
				GameLog.add("Block absorbs %d damage." % (n2 - dealt), Color(0.7, 0.85, 1.0))
			if dealt > 0:
				GameState.change_hp(-dealt)
				GameLog.add("You take %d damage." % dealt, Color(1.0, 0.5, 0.5))
		"gain_gold":
			var n3: int = int(effect.get("value", 0))
			GameState.change_gold(n3)
			GameLog.add("You gain %d gold." % n3, Color(1.0, 0.9, 0.3))
		"lose_gold":
			var n4: int = int(effect.get("value", 0))
			GameState.change_gold(-n4)
			GameLog.add("You lose %d gold." % n4, Color(0.85, 0.7, 0.3))
		"combat_status":
			GameState.pending_combat_statuses.append({
				"status": StringName(String(effect.get("status", ""))),
				"stacks": int(effect.get("stacks", 1)),
			})
			GameLog.add("You go into combat with %d %s." % [
				int(effect.get("stacks", 1)),
				String(effect.get("status", "")).capitalize(),
			], Color(0.8, 0.85, 1.0))
		_:
			GameLog.add("(unhandled event effect: %s)" % t, Color(0.6, 0.6, 0.6))

func _on_continue() -> void:
	# Event is over: pill buffs end here (also handled in _exit_tree as a
	# safety net for any other close path).
	GameState.event_active = false
	GameState.clear_temp_buffs()
	emit_signal("closed", true)
	queue_free()

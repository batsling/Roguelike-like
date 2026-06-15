class_name EventModal
extends Control

# Pre-combat event modal. A small screen state machine that mirrors the JS
# event engine:
#   1. Choice screen   — event art + prompt + choices + pill use-bar, plus a
#                        "Show Outcomes" toggle that previews every branch.
#   2. Success roll    — click a d20: D20 + stat vs difficulty DC -> SUCCESS/FAIL.
#   3. Critical roll   — click a d20: 18+ on a success = crit_good, 1-3 on a
#                        failure = crit_bad (no stat bonus).
#   4. Outcome screen  — tier label + flavour + effect summary, applies effects.
# Simple (no-roll) choices skip straight to the outcome screen.
#
# Luck gives advantage/disadvantage on each roll (two dice, keep best/worst);
# the player may spend reroll_charges to re-roll a die.
#
# Outcome dict (from EventData.choices[*].outcomes):
#   { "crit_good": { description, effects[] }, "good": {...},
#     "bad": {...}, "crit_bad": {...} }
# Simple choices use the "outcome" field instead.

signal closed(should_continue: bool)

# Difficulty thresholds match the JS event engine.
const DIFFICULTY_DC := {
	"easy": 11, "medium": 13, "hard": 15, "insane": 17,
}

# Outcome-tier presentation, matching the JS OUTCOME_COLORS / OUTCOME_LABELS.
const TIER_ORDER := ["crit_good", "good", "bad", "crit_bad"]
const TIER_LABELS := {
	"crit_good": "Critical Success", "good": "Success",
	"bad": "Failure", "crit_bad": "Critical Failure",
}
const TIER_COLORS := {
	"crit_good": Color(0.945, 0.769, 0.059),
	"good": Color(0.180, 0.800, 0.443),
	"bad": Color(0.902, 0.494, 0.133),
	"crit_bad": Color(0.906, 0.298, 0.235),
}

const DieView := preload("res://scripts/events/D20DieView.gd")

var _event: EventData
var _difficulty: String = "easy"
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Persistent UI: a title + art header above a `_body` that each screen rebuilds.
var _title_label: Label
var _image_rect: TextureRect
var _body: VBoxContainer
var _outcomes_popup: Control = null

# Active roll-screen state (success or crit). Reset by each roll screen.
var _roll_choice: Dictionary = {}
var _roll_phase: String = ""          # "success" | "crit"
var _roll_mode: String = "normal"
var _roll_was_success: bool = false
var _roll_dc: int = 11
var _roll_stat_val: int = 0
var _roll_stat_name: String = ""
var _roll_started: bool = false
var _dice: Array = []
var _dice_pending: int = 0
var _roll_result: Dictionary = {}
var _roll_prompt: Label
var _roll_result_box: VBoxContainer

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
# UI scaffold
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
	panel.size = Vector2(760, 600)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	vbox.add_child(_title_label)

	# Event art, centred above the body. Hidden when the event has no image and
	# on the outcome screen (matching the JS flow).
	_image_rect = TextureRect.new()
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_rect.custom_minimum_size = Vector2(720, 160)
	_image_rect.visible = false
	vbox.add_child(_image_rect)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body)

func _refresh() -> void:
	_title_label.text = _event.display_name
	_show_choice_screen()

func _clear_body() -> void:
	_close_outcomes_popup()
	for child in _body.get_children():
		child.queue_free()

# Small helper: append a centred Label to the body and return it.
func _body_label(text: String, font_size: int, color: Color, bold_center := true) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if bold_center else HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	_body.add_child(lbl)
	return lbl

# ------------------------------------------------------------------
# Screen 1 — choices
# ------------------------------------------------------------------

func _show_choice_screen() -> void:
	_clear_body()
	_image_rect.texture = _event.image
	_image_rect.visible = _event.image != null

	var prompt := RichTextLabel.new()
	prompt.bbcode_enabled = true
	prompt.fit_content = true
	prompt.custom_minimum_size = Vector2(720, 90)
	prompt.add_theme_font_size_override("normal_font_size", 14)
	prompt.text = _sub(_event.prompt)
	_body.add_child(prompt)

	_build_use_bar()

	for choice in _event.choices:
		var btn := Button.new()
		btn.text = _format_choice_text(choice)
		btn.custom_minimum_size = Vector2(720, 42)
		var c: Dictionary = choice
		btn.pressed.connect(func(): _on_choice_selected(c))
		_body.add_child(btn)

	var toggle := Button.new()
	toggle.text = "Show Outcomes"
	toggle.pressed.connect(_toggle_outcomes_popup)
	_body.add_child(toggle)

# Pill use-bar — consumables the player can pop before committing to a choice.
# A stat pill raises the matching roll for the rest of the event.
func _build_use_bar() -> void:
	var usables: Array = _usable_pills()
	if usables.is_empty():
		return
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = "Use:"
	lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	bar.add_child(lbl)
	for item in usables:
		var b := Button.new()
		b.text = item.display_name
		b.tooltip_text = item.description
		var it: ItemData = item
		b.pressed.connect(func(): _on_event_use(it))
		bar.add_child(b)
	_body.add_child(bar)

func _usable_pills() -> Array:
	var out: Array = []
	for it in GameState.inventory:
		if it is ItemData and it.kind == ItemData.ItemKind.USABLE:
			out.append(it)
	return out

func _on_event_use(item: ItemData) -> void:
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.8, 0.9, 1.0))
	# Re-render: a stat pill changes the roll a choice needs.
	_show_choice_screen()

func _format_choice_text(choice: Dictionary) -> String:
	var text: String = String(choice.get("text", "?"))
	if String(choice.get("type", "simple")) == "stat_check":
		var stat_name: String = String(choice.get("stat", "?"))
		var dc: int = DIFFICULTY_DC.get(_difficulty, 11)
		var stat_value: int = _get_stat_value(stat_name)
		text += "   [%s   need %d+]" % [stat_name.capitalize(), maxi(1, dc - stat_value)]
	return text

func _on_choice_selected(choice: Dictionary) -> void:
	if String(choice.get("type", "simple")) == "stat_check":
		_show_success_roll_screen(choice)
	else:
		_show_outcome_screen(choice, "", choice.get("outcome", {}))

func _get_stat_value(stat_name: String) -> int:
	# Delegated to Stats so adding a new rollable stat (e.g. constitution
	# events) is a .tres edit, not a code change.
	return Stats.event_roll_bonus(StringName(stat_name.to_lower()))

# ------------------------------------------------------------------
# Screens 2 & 3 — dice rolls
# ------------------------------------------------------------------

func _show_success_roll_screen(choice: Dictionary) -> void:
	_clear_body()
	_roll_choice = choice
	_roll_phase = "success"
	_roll_started = false
	_roll_stat_name = String(choice.get("stat", ""))
	_roll_stat_val = _get_stat_value(_roll_stat_name)
	_roll_dc = DIFFICULTY_DC.get(_difficulty, 11)
	_roll_mode = Stats.event_luck_mode(_rng)
	var needed: int = maxi(1, _roll_dc - _roll_stat_val)

	_body_label("SUCCESS CHECK", 12, Color(0.902, 0.494, 0.133))
	_body_label("Roll %d+ to succeed" % needed, 20, Color(1, 1, 1))
	_body_label("%s: +%d bonus | need %d total%s" % [
		_roll_stat_name.capitalize(), _roll_stat_val, _roll_dc, _luck_hint(_roll_mode),
	], 12, Color(0.7, 0.7, 0.7))
	_build_dice_area()
	_roll_prompt = _body_label(_click_prompt(_roll_mode), 12, Color(0.7, 0.7, 0.75))
	_build_result_box()

func _show_crit_roll_screen(choice: Dictionary, was_success: bool) -> void:
	_clear_body()
	_roll_choice = choice
	_roll_phase = "crit"
	_roll_was_success = was_success
	_roll_started = false
	_roll_mode = Stats.event_luck_mode(_rng)

	var badge_color: Color = TIER_COLORS["good"] if was_success else TIER_COLORS["crit_bad"]
	_body_label("SUCCESS" if was_success else "FAILURE", 12, badge_color)
	_body_label("CRITICAL CHECK", 12, Color(0.765, 0.608, 0.827))
	_body_label("Roll 18+ for Critical Success" if was_success else "Roll 1-3 for Critical Failure",
		20, Color(1, 1, 1))
	_body_label(("need 18, 19, or 20" if was_success else "need 1, 2, or 3") + _luck_hint(_roll_mode),
		12, Color(0.7, 0.7, 0.7))
	_build_dice_area()
	_roll_prompt = _body_label(_click_prompt(_roll_mode), 12, Color(0.7, 0.7, 0.75))
	_build_result_box()

func _build_dice_area() -> void:
	_dice = []
	var count: int = 2 if _roll_mode != "normal" else 1
	var die_size: float = 110.0 if count == 2 else 132.0
	var area := HBoxContainer.new()
	area.alignment = BoxContainer.ALIGNMENT_CENTER
	area.add_theme_constant_override("separation", 22)
	_body.add_child(area)
	for i in range(count):
		var d := DieView.new()
		d.setup(die_size, true)
		d.set_static(20)
		d.clicked.connect(_on_dice_clicked)
		area.add_child(d)
		_dice.append(d)

func _build_result_box() -> void:
	_roll_result_box = VBoxContainer.new()
	_roll_result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_roll_result_box.add_theme_constant_override("separation", 6)
	_roll_result_box.visible = false
	_body.add_child(_roll_result_box)

func _on_dice_clicked() -> void:
	if _roll_started:
		return
	_roll_started = true
	for d in _dice:
		d.interactive = false
	_perform_roll()

func _perform_roll() -> void:
	if _roll_prompt != null:
		_roll_prompt.text = "Rolling..."
		_roll_prompt.visible = true
	_roll_result_box.visible = false
	for d in _dice:
		d.set_highlight("normal")
	_roll_result = Stats.roll_d20_event(_rng, _roll_mode)
	var rolls: Array = _roll_result["rolls"]
	_dice_pending = _dice.size()
	for i in range(_dice.size()):
		var face: int = int(rolls[i]) if i < rolls.size() else int(rolls[0])
		_dice[i].roll_to(face, Callable(self, "_on_one_die_done"))

func _on_one_die_done(_v: int) -> void:
	_dice_pending -= 1
	if _dice_pending <= 0:
		_on_roll_settled()

func _on_roll_settled() -> void:
	var rolls: Array = _roll_result["rolls"]
	var used: int = int(_roll_result["used"])
	if _roll_mode != "normal":
		for i in range(_dice.size()):
			_dice[i].set_highlight("winner" if int(rolls[i]) == used else "loser")
	if _roll_prompt != null:
		_roll_prompt.visible = false

	if _roll_phase == "success":
		var success: bool = (used + _roll_stat_val) >= _roll_dc
		var col: Color = TIER_COLORS["good"] if success else TIER_COLORS["crit_bad"]
		_fill_result_box(
			"SUCCESS" if success else "FAILURE", col,
			"Rolled %d + %d = %d  vs  %d" % [used, _roll_stat_val, used + _roll_stat_val, _roll_dc],
			func(): _show_crit_roll_screen(_roll_choice, success))
	else:
		var is_crit_good: bool = _roll_was_success and used >= 18
		var is_crit_bad: bool = (not _roll_was_success) and used <= 3
		var is_crit: bool = is_crit_good or is_crit_bad
		var key: String = "good"
		if is_crit_good:
			key = "crit_good"
		elif _roll_was_success:
			key = "good"
		elif is_crit_bad:
			key = "crit_bad"
		else:
			key = "bad"
		var col: Color = Color(0.945, 0.769, 0.059) if is_crit else Color(0.7, 0.7, 0.7)
		var outcomes: Dictionary = _roll_choice.get("outcomes", {})
		var outcome: Dictionary = outcomes.get(key, {})
		_fill_result_box(
			"⚡ CRITICAL" if is_crit else "NOT CRITICAL", col,
			"Rolled %d  (%s)" % [used, "need 18+" if _roll_was_success else "need 1-3"],
			func(): _show_outcome_screen(_roll_choice, key, outcome))

# Builds the post-roll result label + Continue (and Reroll, if charges remain).
func _fill_result_box(main_text: String, main_color: Color, detail: String, on_continue: Callable) -> void:
	for c in _roll_result_box.get_children():
		c.queue_free()
	_roll_result_box.visible = true

	var head := Label.new()
	head.text = main_text
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", main_color)
	_roll_result_box.add_child(head)

	var det := Label.new()
	det.text = detail
	det.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	det.add_theme_font_size_override("font_size", 12)
	det.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	_roll_result_box.add_child(det)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_roll_result_box.add_child(row)

	if GameState.reroll_charges > 0:
		var reroll := Button.new()
		reroll.text = "Reroll (%d left)" % GameState.reroll_charges
		reroll.pressed.connect(_on_reroll)
		row.add_child(reroll)

	var cont := Button.new()
	cont.text = "Continue →"
	cont.custom_minimum_size = Vector2(140, 34)
	cont.pressed.connect(on_continue)
	row.add_child(cont)

func _on_reroll() -> void:
	if GameState.reroll_charges <= 0:
		return
	GameState.reroll_charges -= 1
	# Same luck mode and dice; just roll again.
	_perform_roll()

func _luck_hint(mode: String) -> String:
	match mode:
		"advantage":
			return " | Luck: Advantage"
		"disadvantage":
			return " | Luck: Disadvantage"
		_:
			return ""

func _click_prompt(mode: String) -> String:
	match mode:
		"advantage":
			return "Click a die to roll both — best of two"
		"disadvantage":
			return "Click a die to roll both — worst of two"
		_:
			return "Click the die to roll"

# ------------------------------------------------------------------
# Screen 4 — outcome
# ------------------------------------------------------------------

func _show_outcome_screen(choice: Dictionary, outcome_key: String, outcome: Dictionary) -> void:
	_clear_body()
	_image_rect.visible = false

	if outcome_key != "":
		_body_label(String(TIER_LABELS.get(outcome_key, "")), 16,
			TIER_COLORS.get(outcome_key, Color(0.8, 0.8, 0.8)))

	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.custom_minimum_size = Vector2(700, 90)
	desc.add_theme_font_size_override("normal_font_size", 14)
	desc.text = _sub(String(outcome.get("description", "")))
	_body.add_child(desc)

	# Apply the effects, then summarise them for the player.
	for effect in outcome.get("effects", []):
		_apply_event_effect(effect)
	var fx: String = _describe_effects(outcome.get("effects", []))
	if fx != "Nothing":
		_body_label(fx, 13, Color(0.85, 0.9, 0.8))

	var cont := Button.new()
	cont.text = "Continue to Combat"
	cont.custom_minimum_size = Vector2(180, 38)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(cont)
	_body.add_child(row)
	cont.pressed.connect(_on_continue)

# ------------------------------------------------------------------
# "Show Outcomes" preview
# ------------------------------------------------------------------

func _toggle_outcomes_popup() -> void:
	if _outcomes_popup != null:
		_close_outcomes_popup()
	else:
		_build_outcomes_popup()

func _close_outcomes_popup() -> void:
	if _outcomes_popup != null:
		_outcomes_popup.queue_free()
		_outcomes_popup = null

# Click outside the preview panel dismisses it.
func _on_outcomes_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		_close_outcomes_popup()

func _build_outcomes_popup() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_outcomes_popup = overlay

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	dim.gui_input.connect(_on_outcomes_dim_input)
	overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.size = Vector2(620, 500)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var header := Label.new()
	header.text = "Possible Outcomes"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.765, 0.608, 0.827))
	vb.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 400)
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for choice in _event.choices:
		_add_choice_preview(list, choice)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_outcomes_popup)
	vb.add_child(close)

func _add_choice_preview(list: VBoxContainer, choice: Dictionary) -> void:
	var head := Label.new()
	head.text = String(choice.get("text", "?"))
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", Color(0.902, 0.62, 0.30))
	list.add_child(head)

	if String(choice.get("type", "simple")) != "stat_check":
		var outcome: Dictionary = choice.get("outcome", {})
		_add_outcome_row(list, "Direct Effect", Color(0.18, 0.8, 0.443), outcome)
		return

	var outcomes: Dictionary = choice.get("outcomes", {})
	for key in TIER_ORDER:
		if not outcomes.has(key):
			continue
		_add_outcome_row(list, String(TIER_LABELS[key]), TIER_COLORS[key], outcomes[key])

func _add_outcome_row(list: VBoxContainer, label: String, color: Color, outcome: Dictionary) -> void:
	var fx: String = _describe_effects(outcome.get("effects", []))
	var tier := Label.new()
	tier.text = "  %s  —  %s" % [label, fx]
	tier.add_theme_font_size_override("font_size", 12)
	tier.add_theme_color_override("font_color", color)
	list.add_child(tier)
	var desc_text: String = _sub(String(outcome.get("description", "")))
	if desc_text != "":
		var d := RichTextLabel.new()
		d.bbcode_enabled = true
		d.fit_content = true
		d.custom_minimum_size = Vector2(540, 0)
		d.add_theme_font_size_override("normal_font_size", 12)
		d.add_theme_color_override("default_color", Color(0.8, 0.8, 0.82))
		d.text = "    " + desc_text
		list.add_child(d)

# Human-readable one-line effect summary, mirroring the JS _describeEffects but
# over this project's effect vocabulary. Used by the preview and outcome screen.
func _describe_effects(effects: Array) -> String:
	if effects.is_empty():
		return "Nothing"
	var parts: Array = []
	for e in effects:
		var s: String = _describe_one_effect(e)
		if s != "":
			parts.append(s)
	return ", ".join(parts) if not parts.is_empty() else "Nothing"

func _describe_one_effect(e: Dictionary) -> String:
	var t: String = String(e.get("type", ""))
	match t:
		"none":
			return ""
		"heal":
			return "+%d HP" % int(e.get("value", 0))
		"heal_percent":
			return "+%d%% Max HP" % int(e.get("value", 0))
		"lose_hp":
			return "-%d HP" % int(e.get("value", 0))
		"gain_gold":
			return "+%d Gold" % int(e.get("value", 0))
		"gold_range":
			return "+%d-%d Gold" % [int(e.get("min", 0)), int(e.get("max", 0))]
		"lose_gold":
			return "-%d Gold" % int(e.get("value", 0))
		"combat_status":
			return "%d× %s" % [int(e.get("stacks", 1)), String(e.get("status", "")).capitalize()]
		"item_tagged":
			return "Random %s item" % String(e.get("tag", ""))
		"curse_card":
			var card: CardData = Data.get_card(StringName(String(e.get("card", ""))))
			return "Curse card: %s" % (card.display_name if card != null else String(e.get("card", "")))
		"active_curse":
			var curse: CurseData = Data.get_curse(StringName(String(e.get("curse", ""))))
			return "Curse: %s" % (curse.display_name if curse != null else String(e.get("curse", "")))
		"combat_flag":
			var f: String = String(e.get("flag", ""))
			if f == "ambush":
				return "Ambush — draw +2 cards turn 1"
			if f == "ambushed":
				return "Ambushed — draw -2 cards turn 1"
			return f
		"spawn_enemies":
			var lo: int = int(e.get("min", 1))
			var hi: int = int(e.get("max", lo))
			var rng_txt: String = str(lo) if lo == hi else "%d-%d" % [lo, hi]
			return "+%s %s next fight" % [rng_txt, String(e.get("enemy", "")).capitalize()]
		"note_for_yourself":
			return "Retrieve %s | store a card" % _stored_card_name()
		_:
			return ""

# Event-time effects don't go through EffectSystem (no combat scene
# to call into). They mutate GameState directly or queue pending data
# for the next combat to drain.
func _apply_event_effect(effect: Dictionary) -> void:
	var t: String = String(effect.get("type", ""))
	match t:
		"none":
			pass
		"heal":
			var n: int = int(effect.get("value", 0))
			GameState.change_hp(n)
			GameLog.add("You heal %d HP." % n, Color(0.6, 1.0, 0.6))
		"heal_percent":
			# Heal a percentage of the max HP pool (rounded up so small
			# pools still feel something), matching the JS heal_percent.
			var pct: int = int(effect.get("value", 0))
			var amount: int = int(ceil(GameState.max_hp * pct / 100.0))
			GameState.change_hp(amount)
			GameLog.add("You heal %d HP." % amount, Color(0.6, 1.0, 0.6))
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
		"gold_range":
			# Roll a gold reward in [min, max] inclusive at resolution time.
			var lo: int = int(effect.get("min", 0))
			var hi: int = int(effect.get("max", lo))
			var g: int = _rng.randi_range(mini(lo, hi), maxi(lo, hi))
			GameState.change_gold(g)
			GameLog.add("You gain %d gold." % g, Color(1.0, 0.9, 0.3))
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
		"item_tagged":
			_grant_tagged_item(StringName(String(effect.get("tag", ""))))
		"curse_card":
			# Add a CURSE-type card (e.g. Greed) to the run deck.
			var card: CardData = Data.get_card(StringName(String(effect.get("card", ""))))
			if card != null:
				GameState.add_card_to_deck(card)
				GameLog.add("A curse worms into your deck: %s." % card.display_name,
					Color(0.85, 0.6, 0.85))
			else:
				GameLog.add("(missing curse card: %s)" % effect.get("card", ""),
					Color(0.6, 0.6, 0.6))
		"active_curse":
			# Attach a persistent run curse (e.g. Curse of Ocular Trauma).
			var curse: CurseData = Data.get_curse(StringName(String(effect.get("curse", ""))))
			if curse != null:
				GameState.add_active_curse(curse)
			else:
				GameLog.add("(missing curse: %s)" % effect.get("curse", ""),
					Color(0.6, 0.6, 0.6))
		"combat_flag":
			# Carry an ambush state into the next combat the player enters.
			var flag: String = String(effect.get("flag", ""))
			if flag == "ambush" or flag == "ambushed":
				GameState.pending_ambush = flag
				if flag == "ambush":
					GameLog.add("You have the drop on your next foe!", Color(0.7, 1.0, 0.7))
				else:
					GameLog.add("Something has the drop on you...", Color(1.0, 0.6, 0.6))
		"spawn_enemies":
			# Queue extra enemies for the next combat. Roll the count now.
			var emin: int = int(effect.get("min", 1))
			var emax: int = int(effect.get("max", emin))
			var count: int = _rng.randi_range(mini(emin, emax), maxi(emin, emax))
			GameState.pending_spawn_enemies.append({
				"enemy": StringName(String(effect.get("enemy", ""))),
				"count": count,
			})
			GameLog.add("%d %s will be waiting for you!" % [
				count, String(effect.get("enemy", "")).capitalize(),
			], Color(1.0, 0.6, 0.6))
		"note_for_yourself":
			_resolve_note_for_yourself(StringName(String(effect.get("default_card", "iron_wave"))))
		_:
			GameLog.add("(unhandled event effect: %s)" % t, Color(0.6, 0.6, 0.6))

# ------------------------------------------------------------------
# Effect helpers
# ------------------------------------------------------------------

func _grant_tagged_item(tag: StringName) -> void:
	var template: ItemData = Data.random_item_by_tag(tag, _rng)
	if template == null:
		GameLog.add("(no item tagged '%s')" % tag, Color(0.6, 0.6, 0.6))
		return
	GameState.add_item(template)
	GameLog.add("You find %s." % template.display_name, Color(0.8, 1.0, 0.8))

# "A Note For Yourself": hand back the previously stored card (or a default the
# first time), add it to the run deck, then let the player pick a card from
# their current deck to store for next time.
func _resolve_note_for_yourself(default_card: StringName) -> void:
	var stored_id: StringName = GameState.note_for_yourself_card
	if stored_id == &"":
		stored_id = default_card
	var stored: CardData = Data.get_card(stored_id)
	if stored != null:
		GameState.add_card_to_deck(stored)
		GameLog.add("You retrieve %s." % stored.display_name, Color(0.8, 0.9, 1.0))
	# Now choose which card to leave for the next visit.
	var candidates: Array = GameState.deck.duplicate()
	if candidates.is_empty():
		return
	var picker := CardPickerModal.new()
	add_child(picker)
	picker.show_picker({
		"title": "Store a card for next time",
		"candidates": candidates,
		"count": 1,
		"accent": Color(0.70, 0.80, 0.95),
		"confirm_label": "Store",
		"on_picked": Callable(self, "_on_note_card_picked"),
	})

func _on_note_card_picked(picks: Array) -> void:
	if picks.is_empty():
		return
	var inst = picks[0]
	if inst != null and inst.data != null:
		GameState.note_for_yourself_card = inst.data.id
		GameLog.add("You stash a note about %s." % inst.data.display_name,
			Color(0.8, 0.9, 1.0))

# Replaces {name} / {storedCard} placeholders in event flavour text.
func _sub(text: String) -> String:
	if text.find("{") == -1:
		return text
	var out: String = text
	out = out.replace("{name}", _player_name())
	out = out.replace("{storedCard}", _stored_card_name())
	return out

func _player_name() -> String:
	var ch: CharacterData = Data.get_character(GameState.character_id)
	if ch != null and String(ch.display_name) != "":
		return String(ch.display_name)
	return "You"

func _stored_card_name() -> String:
	# The note shows the card the player will RECEIVE next — i.e. the one
	# currently stored, or the default if nothing has been stored yet.
	var id: StringName = GameState.note_for_yourself_card
	if id == &"":
		id = &"iron_wave"
	var card: CardData = Data.get_card(id)
	return String(card.display_name) if card != null else "Iron Wave"

func _on_continue() -> void:
	# Event is over: pill buffs end here (also handled in _exit_tree as a
	# safety net for any other close path).
	GameState.event_active = false
	GameState.clear_temp_buffs()
	emit_signal("closed", true)
	queue_free()

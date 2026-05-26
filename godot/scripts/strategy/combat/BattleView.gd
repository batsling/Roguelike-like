extends CanvasLayer

# Phase 5: the tactical battle UI. Replaces the earlier ASCII placeholder.
# Hosts the `BattleGridView` plus an action bar, initiative panel, and
# stub pickers for the Phase-6 Ability and Spellbook flows.
#
# Player turn rules (from STRATEGY_COMBAT_PLAN.md):
#   - Move up to `unit.speed` tiles (chained moves allowed).
#   - One of Attack OR Defend (mutually exclusive, `_action_used`).
#   - One non-basic Ability (Phase 6; `_ability_used`).
#   - Any number of Spells while mana lasts (Phase 6).
#   - Dash once per combat: spends `dash_available` for a bonus turn
#     appended after this one.
#   - End Turn closes out the turn.
# Enemy turns auto-end on a short timer until Phase 7 lands enemy AI.

const BattleGridViewScript := preload("res://scripts/strategy/combat/BattleGridView.gd")

const ENEMY_TURN_DELAY := 0.45
const DEFAULT_BASIC_ATTACK := 6
const DEFAULT_BASIC_DEFEND := 6

var _battle_map = null
var _turn_manager = null
var _units: Array = []

var _grid_view: BattleGridView
var _initiative_label: Label
var _status_label: Label
var _info_label: Label

var _btn_move: Button
var _btn_attack: Button
var _btn_defend: Button
var _btn_ability: Button
var _btn_spell: Button
var _btn_dash: Button
var _btn_end: Button
var _btn_win: Button
var _btn_lose: Button

var _ability_dialog: Panel
var _spell_dialog: Panel

var _enemy_turn_timer: Timer

# Per-turn state.
var _action_used: bool = false
var _ability_used: bool = false
var _move_remaining: int = 0

func _ready() -> void:
	layer = 10
	_build_ui()

func set_encounter(room_data, encounter: Array, battle_map = null, turn_manager = null) -> void:
	_battle_map = battle_map
	_turn_manager = turn_manager
	_units = turn_manager.units if turn_manager != null else []
	_grid_view.set_battle(battle_map, _units)

	_info_label.text = _format_info(room_data, encounter)

	if turn_manager != null:
		turn_manager.unit_turn_started.connect(_on_unit_turn_started)
		turn_manager.unit_turn_ended.connect(_on_unit_turn_ended)
		turn_manager.battle_ended.connect(_on_battle_ended)

	_refresh_initiative()
	_status_label.text = "Waiting for first turn..."
	_set_player_buttons_enabled(false)

# ----------------------------------------------------------------------
# UI construction
# ----------------------------------------------------------------------

func _build_ui() -> void:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.02, 0.07, 0.96)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var title := Label.new()
	title.text = "[ TACTICAL BATTLE ]"
	title.position = Vector2(20, 8)
	title.size = Vector2(420, 30)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	panel.add_child(title)

	_info_label = Label.new()
	_info_label.position = Vector2(20, 40)
	_info_label.size = Vector2(820, 50)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	panel.add_child(_info_label)

	_grid_view = BattleGridViewScript.new()
	_grid_view.position = Vector2(20, 100)
	_grid_view.move_requested.connect(_on_move_requested)
	_grid_view.attack_requested.connect(_on_attack_requested)
	panel.add_child(_grid_view)

	_initiative_label = Label.new()
	_initiative_label.position = Vector2(580, 100)
	_initiative_label.size = Vector2(340, 420)
	_initiative_label.add_theme_font_size_override("font_size", 13)
	_initiative_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	panel.add_child(_initiative_label)

	_status_label = Label.new()
	_status_label.position = Vector2(580, 530)
	_status_label.size = Vector2(340, 60)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	panel.add_child(_status_label)

	_build_action_bar(panel)
	_build_pickers()

	_enemy_turn_timer = Timer.new()
	_enemy_turn_timer.one_shot = true
	_enemy_turn_timer.wait_time = ENEMY_TURN_DELAY
	_enemy_turn_timer.timeout.connect(_auto_end_enemy_turn)
	add_child(_enemy_turn_timer)

func _build_action_bar(panel: Panel) -> void:
	var bar_y := 620
	var x := 20
	var spacing := 6
	var btn_h := 36

	_btn_move = _make_button("Move", x, bar_y, 80, btn_h, _on_move_button)
	panel.add_child(_btn_move); x += 80 + spacing
	_btn_attack = _make_button("Attack", x, bar_y, 90, btn_h, _on_attack_button)
	panel.add_child(_btn_attack); x += 90 + spacing
	_btn_defend = _make_button("Defend", x, bar_y, 90, btn_h, _on_defend_button)
	panel.add_child(_btn_defend); x += 90 + spacing
	_btn_ability = _make_button("Ability", x, bar_y, 90, btn_h, _on_ability_button)
	panel.add_child(_btn_ability); x += 90 + spacing
	_btn_spell = _make_button("Spellbook", x, bar_y, 110, btn_h, _on_spell_button)
	panel.add_child(_btn_spell); x += 110 + spacing
	_btn_dash = _make_button("Dash", x, bar_y, 80, btn_h, _on_dash_button)
	panel.add_child(_btn_dash); x += 80 + spacing
	_btn_end = _make_button("End Turn", x, bar_y, 100, btn_h, _on_end_turn_button)
	panel.add_child(_btn_end); x += 100 + spacing

	_btn_win = _make_button("(debug) Win", 1080, 620, 90, btn_h, _on_force_win)
	panel.add_child(_btn_win)
	_btn_lose = _make_button("(debug) Lose", 1180, 620, 90, btn_h, _on_force_lose)
	panel.add_child(_btn_lose)

func _make_button(text: String, x: int, y: int, w: int, h: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.pressed.connect(cb)
	return b

func _build_pickers() -> void:
	_ability_dialog = _make_dialog(
		"Abilities",
		"No abilities yet — non-basic deck cards plug in during Phase 6.",
		_close_ability_dialog,
	)
	add_child(_ability_dialog)
	_ability_dialog.visible = false

	_spell_dialog = _make_dialog(
		"Spellbook",
		"No spells yet — SPELLS_DATA is ported into a Godot resource in Phase 6.",
		_close_spell_dialog,
	)
	add_child(_spell_dialog)
	_spell_dialog.visible = false

func _make_dialog(title_text: String, body_text: String, close_cb: Callable) -> Panel:
	var p := Panel.new()
	p.position = Vector2(360, 200)
	p.size = Vector2(560, 240)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.07, 0.14, 0.98)
	bg.border_color = Color(0.6, 0.5, 0.3)
	bg.border_width_left = 2; bg.border_width_right = 2
	bg.border_width_top = 2; bg.border_width_bottom = 2
	p.add_theme_stylebox_override("panel", bg)

	var t := Label.new()
	t.text = title_text
	t.position = Vector2(20, 14)
	t.size = Vector2(520, 30)
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	p.add_child(t)

	var b := Label.new()
	b.text = body_text
	b.position = Vector2(20, 60)
	b.size = Vector2(520, 120)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(b)

	var close := _make_button("Close", 230, 190, 100, 36, close_cb)
	p.add_child(close)
	return p

# ----------------------------------------------------------------------
# Turn flow
# ----------------------------------------------------------------------

func _on_unit_turn_started(unit) -> void:
	_grid_view.set_active_unit(unit, unit.speed)
	_refresh_initiative()
	if unit.is_player:
		_action_used = false
		_ability_used = false
		_move_remaining = unit.speed
		_status_label.text = "Your turn. Move %d  |  Mana %d/%d" % [
			_move_remaining, unit.mana, unit.max_mana,
		]
		_set_player_buttons_enabled(true)
		_refresh_button_states()
	else:
		_status_label.text = "%s acts..." % unit.unit_name
		_set_player_buttons_enabled(false)
		_enemy_turn_timer.start()

func _on_unit_turn_ended(_unit) -> void:
	_refresh_initiative()

func _auto_end_enemy_turn() -> void:
	if _turn_manager == null or _turn_manager.current_unit == null:
		return
	if _turn_manager.current_unit.is_player:
		return
	_turn_manager.end_current_turn()

func _on_battle_ended(result) -> void:
	_status_label.text = "Battle ended: %s" % result
	_set_player_buttons_enabled(false)

# ----------------------------------------------------------------------
# Player actions
# ----------------------------------------------------------------------

func _on_move_button() -> void:
	if not _is_player_turn():
		return
	if _move_remaining <= 0:
		_status_label.text = "No movement left."
		return
	_grid_view.enter_move_mode()
	_status_label.text = "Click a highlighted tile to move (%d tiles left)." % _move_remaining

func _on_attack_button() -> void:
	if not _is_player_turn() or _action_used:
		return
	_grid_view.enter_attack_mode()
	_status_label.text = "Click an adjacent enemy to attack."

func _on_defend_button() -> void:
	if not _is_player_turn() or _action_used:
		return
	var u = _turn_manager.current_unit
	u.block += DEFAULT_BASIC_DEFEND
	_action_used = true
	_grid_view.enter_idle()
	_status_label.text = "You brace. +%d block (now %d)." % [DEFAULT_BASIC_DEFEND, u.block]
	_grid_view.notify_units_changed()
	_refresh_button_states()

func _on_ability_button() -> void:
	if not _is_player_turn() or _ability_used:
		return
	_grid_view.enter_idle()
	_ability_dialog.visible = true

func _on_spell_button() -> void:
	if not _is_player_turn():
		return
	_grid_view.enter_idle()
	_spell_dialog.visible = true

func _on_dash_button() -> void:
	if not _is_player_turn():
		return
	if _turn_manager.consume_dash():
		_status_label.text = "Dash! Bonus turn queued."
		_refresh_initiative()
		_refresh_button_states()

func _on_end_turn_button() -> void:
	if not _is_player_turn():
		return
	_grid_view.enter_idle()
	_set_player_buttons_enabled(false)
	_turn_manager.end_current_turn()

func _close_ability_dialog() -> void:
	_ability_dialog.visible = false

func _close_spell_dialog() -> void:
	_spell_dialog.visible = false

func _on_force_win() -> void:
	StrategyCombatSession.resolve_combat("victory")

func _on_force_lose() -> void:
	StrategyCombatSession.resolve_combat("defeat")

# ----------------------------------------------------------------------
# Grid-view callbacks
# ----------------------------------------------------------------------

func _on_move_requested(path: Array) -> void:
	if not _is_player_turn() or path.is_empty():
		return
	var u = _turn_manager.current_unit
	var cost: int = path.size()
	if cost > _move_remaining:
		return
	u.position = path[-1]
	_move_remaining -= cost
	_grid_view.set_active_unit(u, _move_remaining)
	if _move_remaining > 0:
		_grid_view.enter_move_mode()
	else:
		_grid_view.enter_idle()
	_status_label.text = "Moved %d. %d move left." % [cost, _move_remaining]
	_refresh_initiative()
	_refresh_button_states()

func _on_attack_requested(target) -> void:
	if not _is_player_turn() or _action_used:
		return
	var attacker = _turn_manager.current_unit
	var dmg := DEFAULT_BASIC_ATTACK
	if attacker.basic_attack_def.has("damage"):
		dmg = int(attacker.basic_attack_def["damage"])
	_apply_damage(target, dmg)
	_action_used = true
	_grid_view.enter_idle()
	_status_label.text = "You strike %s for %d." % [target.unit_name, dmg]
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_button_states()

func _apply_damage(target, raw_dmg: int) -> void:
	var absorbed := mini(target.block, raw_dmg)
	target.block -= absorbed
	var landed := raw_dmg - absorbed
	target.hp = maxi(0, target.hp - landed)
	if not target.is_alive():
		# Let the engine wrap up immediately if the kill ended combat.
		_turn_manager.check_battle_end_now()

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

func _is_player_turn() -> bool:
	return (
		_turn_manager != null
		and _turn_manager.current_unit != null
		and _turn_manager.current_unit.is_player
	)

func _set_player_buttons_enabled(enabled: bool) -> void:
	_btn_move.disabled = not enabled
	_btn_attack.disabled = not enabled
	_btn_defend.disabled = not enabled
	_btn_ability.disabled = not enabled
	_btn_spell.disabled = not enabled
	_btn_dash.disabled = not enabled
	_btn_end.disabled = not enabled
	if enabled:
		_refresh_button_states()

func _refresh_button_states() -> void:
	if not _is_player_turn():
		return
	var u = _turn_manager.current_unit
	_btn_move.disabled = _move_remaining <= 0
	_btn_attack.disabled = _action_used
	_btn_defend.disabled = _action_used
	_btn_ability.disabled = _ability_used
	_btn_dash.disabled = not u.dash_available

func _refresh_initiative() -> void:
	if _turn_manager == null:
		_initiative_label.text = ""
		return
	var lines: Array = ["Round %d" % _turn_manager.round_num, ""]
	var cur = _turn_manager.current_unit
	for u in _turn_manager.units:
		var marker = ">" if u == cur else " "
		var dead = "" if u.is_alive() else " [DEAD]"
		var mana = ""
		if u.is_player:
			mana = "  mana %d/%d" % [u.mana, u.max_mana]
		var block = ""
		if u.block > 0:
			block = "  blk %d" % u.block
		lines.append("%s %-8s hp %d/%d  spd %d  ctr %d%s%s%s" % [
			marker, u.unit_name, u.hp, u.max_hp, u.speed,
			u.act_counter, mana, block, dead,
		])
	_initiative_label.text = "\n".join(lines)

func _format_info(room_data, encounter: Array) -> String:
	var rect_str := "(%d,%d %dx%d)" % [
		room_data.rect.position.x, room_data.rect.position.y,
		room_data.rect.size.x, room_data.rect.size.y,
	]
	var enc_str := "(empty)"
	if not encounter.is_empty():
		enc_str = ""
		for i in range(encounter.size()):
			if i > 0: enc_str += ", "
			enc_str += str(encounter[i])

	var size_name := "?"
	var dims := "?"
	if _battle_map != null:
		size_name = ["S", "M", "L"][_battle_map.size_class]
		dims = "%dx%d" % [_battle_map.width, _battle_map.height]

	return (
		"Room: %s  |  Encounter: %s  |  Field: %s (%s)\n"
		+ "Move highlighted tiles, attack adjacent enemies. Abilities and "
		+ "spells are stubbed until Phase 6 (enemy AI lands in Phase 7)."
	) % [rect_str, enc_str, size_name, dims]

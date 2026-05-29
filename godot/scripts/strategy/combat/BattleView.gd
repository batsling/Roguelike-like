extends CanvasLayer

# The tactical battle UI. Hosts a pre-combat loadout screen, the
# BattleGridView, an action bar, an initiative panel, and the
# Cards/Spellbook pickers.
#
# Pre-combat: the player sees the enemy + telegraphed intents and slots up
# to 3 cards from the deck into a `CombatLoadout`. Confirming kicks the
# initiative engine (StrategyCombatSession.begin_battle).
#
# Player turn rules:
#   - Move up to `unit.speed` tiles, ONE move action per turn (no chaining).
#   - One of Attack OR Defend (`_action_used`).
#   - One slotted card play per turn baseline (`_card_plays_remaining`);
#     each play spends one of the card's run-persistent uses (GameState).
#     gain-energy effects grant extra plays this turn; draw effects recharge
#     a use; discard effects cost a play (tempo).
#   - Any number of Spells while mana lasts.
#   - Dash once per combat: spends `dash_available` for a bonus turn.
#   - End Turn closes out the turn.
#
# Effect resolution: card and spell effects route through the autoloaded
# `EffectSystem`, with `self` as the `scene` ctx so the tactical
# implementations of deal_damage/gain_block/heal handle the actual mutations.

const BattleGridViewScript := preload("res://scripts/strategy/combat/BattleGridView.gd")
const CombatLoadoutScript := preload("res://scripts/strategy/combat/CombatLoadout.gd")
const SpellbookScript := preload("res://scripts/strategy/combat/Spellbook.gd")
const SpellsCatalogScript := preload("res://scripts/strategy/combat/SpellsCatalog.gd")

const ENEMY_TURN_DELAY := 0.45
const DEFAULT_BASIC_ATTACK := 6
const DEFAULT_BASIC_DEFEND := 6

# Phase 8: per-archetype drop weights. Rolled when an enemy dies; the
# spawned items go onto the battlefield and persist back to the source
# room on combat end (see `CombatSession._sync_loot_back`).
const ENEMY_LOOT_TABLE := {
	"rat":   { "gold_chance": 0.50, "gold_min":  2, "gold_max":  6, "item_chance": 0.05 },
	"snake": { "gold_chance": 0.50, "gold_min":  3, "gold_max":  8, "item_chance": 0.10 },
	"orc":   { "gold_chance": 0.70, "gold_min":  6, "gold_max": 14, "item_chance": 0.20 },
	"troll": { "gold_chance": 0.90, "gold_min": 12, "gold_max": 24, "item_chance": 0.35 },
}

# What the player is currently selecting in the grid view.
enum Pending { NONE, ABILITY, SPELL }

var _battle_map = null
var _turn_manager = null
var _units: Array = []
var _room_data = null
var _encounter: Array = []

var _loadout = null        # CombatLoadout (the 3 chosen cards)
var _available_cards: Array = []  # choosable pool for the loadout screen
var _selected_cards: Array = []   # mid-selection on the loadout screen
var _spellbook = null      # Spellbook

# Mid-action state: which card/spell is mid-cast while we wait for a target click.
var _pending_kind: int = Pending.NONE
var _pending_card = null     # CardData (slotted loadout card)
var _pending_spell = null    # Spellbook.Entry

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
var _ability_list_container: VBoxContainer
var _spell_dialog: Panel
var _spell_list_container: VBoxContainer

# Pre-combat loadout screen.
var _loadout_overlay: Panel
var _loadout_enemy_label: Label
var _loadout_slots_label: Label
var _loadout_pool_container: VBoxContainer
var _loadout_start_btn: Button

var _enemy_turn_timer: Timer

# Per-turn state.
var _action_used: bool = false
var _move_used: bool = false   # one Move action per turn (no chaining)
var _move_remaining: int = 0

# Card plays left this turn. Baseline 1 (one card per turn); gain-energy
# effects add plays, discard effects subtract them. Each card play also
# spends one of the card's run-persistent uses (GameState.spend_card_use).
var _card_plays_remaining: int = 0

var _loot_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	layer = 10
	_loot_rng.randomize()
	_build_ui()

func set_encounter(room_data, encounter: Array, battle_map = null, turn_manager = null) -> void:
	_battle_map = battle_map
	_turn_manager = turn_manager
	_units = turn_manager.units if turn_manager != null else []
	_room_data = room_data
	_encounter = encounter
	_grid_view.set_battle(battle_map, _units)

	_available_cards = CombatLoadoutScript.available_from_deck(GameState.deck)
	_loadout = CombatLoadoutScript.new()
	_selected_cards = []
	_spellbook = SpellbookScript.build_from_ids(GameState.learned_spells)

	_info_label.text = _format_info(room_data, encounter)

	if turn_manager != null:
		turn_manager.unit_turn_started.connect(_on_unit_turn_started)
		turn_manager.unit_turn_ended.connect(_on_unit_turn_ended)
		turn_manager.battle_ended.connect(_on_battle_ended)

	_refresh_initiative()
	_set_player_buttons_enabled(false)
	# Show the pre-combat loadout screen; battle starts on confirm.
	_open_loadout_screen()

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
	_grid_view.target_requested.connect(_on_target_requested)
	_grid_view.target_cancelled.connect(_on_target_cancelled)
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
	_build_loadout_overlay()

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
	_btn_ability = _make_button("Cards", x, bar_y, 90, btn_h, _on_ability_button)
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
	_ability_dialog = _make_picker_dialog("Abilities", _close_ability_dialog)
	_ability_list_container = _ability_dialog.get_meta("list")
	add_child(_ability_dialog)
	_ability_dialog.visible = false

	_spell_dialog = _make_picker_dialog("Spellbook", _close_spell_dialog)
	_spell_list_container = _spell_dialog.get_meta("list")
	add_child(_spell_dialog)
	_spell_dialog.visible = false

func _make_picker_dialog(title_text: String, close_cb: Callable) -> Panel:
	var p := Panel.new()
	p.position = Vector2(280, 140)
	p.size = Vector2(640, 420)
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

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 56)
	scroll.size = Vector2(600, 290)
	p.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)
	p.set_meta("list", vbox)

	var close := _make_button("Close", 270, 366, 100, 36, close_cb)
	p.add_child(close)
	return p

# ----------------------------------------------------------------------
# Pre-combat loadout screen
# ----------------------------------------------------------------------

func _build_loadout_overlay() -> void:
	_loadout_overlay = Panel.new()
	_loadout_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loadout_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.03, 0.09, 0.98)
	_loadout_overlay.add_theme_stylebox_override("panel", bg)

	var title := Label.new()
	title.text = "[ PREPARE FOR BATTLE ]"
	title.position = Vector2(40, 30)
	title.size = Vector2(700, 34)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_loadout_overlay.add_child(title)

	_loadout_enemy_label = Label.new()
	_loadout_enemy_label.position = Vector2(40, 74)
	_loadout_enemy_label.size = Vector2(900, 70)
	_loadout_enemy_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_loadout_enemy_label.add_theme_font_size_override("font_size", 14)
	_loadout_enemy_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	_loadout_overlay.add_child(_loadout_enemy_label)

	var instr := Label.new()
	instr.text = "Slot up to 3 cards. Each play spends one of the card's uses (uses carry over between fights)."
	instr.position = Vector2(40, 150)
	instr.size = Vector2(900, 40)
	instr.autowrap_mode = TextServer.AUTOWRAP_WORD
	instr.add_theme_font_size_override("font_size", 13)
	instr.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_loadout_overlay.add_child(instr)

	_loadout_slots_label = Label.new()
	_loadout_slots_label.position = Vector2(40, 190)
	_loadout_slots_label.size = Vector2(900, 30)
	_loadout_slots_label.add_theme_font_size_override("font_size", 15)
	_loadout_slots_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_loadout_overlay.add_child(_loadout_slots_label)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 226)
	scroll.size = Vector2(900, 330)
	_loadout_overlay.add_child(scroll)
	_loadout_pool_container = VBoxContainer.new()
	_loadout_pool_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_pool_container.add_theme_constant_override("separation", 4)
	scroll.add_child(_loadout_pool_container)

	_loadout_start_btn = _make_button("Start Battle", 40, 566, 160, 40, _on_confirm_loadout)
	_loadout_overlay.add_child(_loadout_start_btn)

	add_child(_loadout_overlay)
	_loadout_overlay.visible = false

func _open_loadout_screen() -> void:
	var names: Array = []
	for e in _encounter:
		names.append(str(e))
	var enemy_lines: Array = ["Enemy: " + (", ".join(names) if not names.is_empty() else "(none)")]
	for u in _units:
		if u.is_player or not u.is_alive():
			continue
		var tel: String = ""
		if not u.intent_telegraph.is_empty():
			var t: Dictionary = u.intent_telegraph
			var val: int = int(t.get("value", 0))
			tel = "  intends: %s%s" % [str(t.get("name", "")), (" (%d)" % val) if val > 0 else ""]
		enemy_lines.append("  %s — hp %d/%d  spd %d%s" % [u.unit_name, u.hp, u.max_hp, u.speed, tel])
	_loadout_enemy_label.text = "\n".join(enemy_lines)
	_populate_loadout_pool()
	_loadout_overlay.visible = true

func _populate_loadout_pool() -> void:
	for child in _loadout_pool_container.get_children():
		child.queue_free()
	_loadout_slots_label.text = "Slots: %d / %d filled" % [_selected_cards.size(), CombatLoadout.MAX_SLOTS]
	if _available_cards.is_empty():
		_loadout_pool_container.add_child(_picker_note(
			"No cards available. You'll fight with basic Attack/Defend and spells."
		))
		return
	for card in _available_cards:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chosen: bool = _selected_cards.has(card)
		var uses: int = GameState.get_card_uses(card)
		var cap: int = GameState.max_card_uses(card)
		var lbl := Label.new()
		var prefix: String = "[SLOTTED] " if chosen else ""
		lbl.text = "%s%s  (uses %d/%d)  —  %s" % [prefix, card.display_name, uses, cap, card.description]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(700, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		if uses <= 0 and not chosen:
			lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Remove" if chosen else "Slot"
		# Can't slot a 4th card; can always remove an already-chosen one.
		btn.disabled = (not chosen) and _selected_cards.size() >= CombatLoadout.MAX_SLOTS
		btn.pressed.connect(_on_toggle_loadout_card.bind(card))
		row.add_child(btn)
		_loadout_pool_container.add_child(row)

func _on_toggle_loadout_card(card) -> void:
	if _selected_cards.has(card):
		_selected_cards.erase(card)
	elif _selected_cards.size() < CombatLoadout.MAX_SLOTS:
		_selected_cards.append(card)
	_populate_loadout_pool()

func _on_confirm_loadout() -> void:
	_loadout.cards = _selected_cards.duplicate()
	_loadout_overlay.visible = false
	_info_label.text = _format_info(_room_data, _encounter)
	_status_label.text = "Waiting for first turn..."
	StrategyCombatSession.begin_battle()

# ----------------------------------------------------------------------
# Turn flow
# ----------------------------------------------------------------------

func _on_unit_turn_started(unit) -> void:
	_grid_view.set_active_unit(unit, unit.speed)
	_refresh_initiative()
	if unit.is_player:
		_action_used = false
		_move_used = false
		_move_remaining = unit.speed
		_card_plays_remaining = 1
		_pending_kind = Pending.NONE
		_pending_card = null
		_pending_spell = null
		_status_label.text = "Your turn. Move %d  |  Plays %d  |  Mana %d/%d" % [
			_move_remaining, _card_plays_remaining, unit.mana, unit.max_mana,
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
	var enemy = _turn_manager.current_unit
	if enemy.is_player:
		return
	if enemy.ai != null:
		var msg: String = enemy.ai.execute_turn(self, _units, _battle_map)
		_status_label.text = msg
		_grid_view.notify_units_changed()
		_refresh_initiative()
		# Bail before re-telegraphing if the action ended the battle.
		if _turn_manager.check_battle_end_now():
			return
		# Pick the next intent now so the player sees the updated
		# telegraph for any survivor before their own turn starts.
		enemy.ai.plan_next(_units)
		_grid_view.notify_units_changed()
	_turn_manager.end_current_turn()

func _on_battle_ended(result) -> void:
	_status_label.text = "Battle ended: %s" % result
	_set_player_buttons_enabled(false)

# ----------------------------------------------------------------------
# Player actions — basic
# ----------------------------------------------------------------------

func _on_move_button() -> void:
	if not _is_player_turn():
		return
	if _move_used:
		_status_label.text = "You've already moved this turn."
		return
	if _move_remaining <= 0:
		_status_label.text = "No movement left."
		return
	_clear_pending()
	_grid_view.enter_move_mode()
	_status_label.text = "Click a tile to move (up to %d tiles, one move per turn)." % _move_remaining

func _on_attack_button() -> void:
	if not _is_player_turn() or _action_used:
		return
	_clear_pending()
	_grid_view.enter_attack_mode()
	_status_label.text = "Click an adjacent enemy to attack."

func _on_defend_button() -> void:
	if not _is_player_turn() or _action_used:
		return
	_clear_pending()
	var u = _turn_manager.current_unit
	u.block += DEFAULT_BASIC_DEFEND
	_action_used = true
	_grid_view.enter_idle()
	_status_label.text = "You brace. +%d block (now %d)." % [DEFAULT_BASIC_DEFEND, u.block]
	_grid_view.notify_units_changed()
	_refresh_button_states()

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
	_clear_pending()
	_grid_view.enter_idle()
	_set_player_buttons_enabled(false)
	_turn_manager.end_current_turn()

func _on_force_win() -> void:
	StrategyCombatSession.resolve_combat("victory")

func _on_force_lose() -> void:
	StrategyCombatSession.resolve_combat("defeat")

# ----------------------------------------------------------------------
# Player actions — Cards (slotted loadout)
# ----------------------------------------------------------------------

func _on_ability_button() -> void:
	if not _is_player_turn():
		return
	if _card_plays_remaining <= 0:
		_status_label.text = "No card plays left this turn."
		return
	_clear_pending()
	_grid_view.enter_idle()
	_populate_ability_picker()
	_ability_dialog.visible = true
	_spell_dialog.visible = false

func _populate_ability_picker() -> void:
	for child in _ability_list_container.get_children():
		child.queue_free()
	if _loadout == null or _loadout.cards.is_empty():
		_ability_list_container.add_child(_picker_note(
			"No cards slotted. Pick a loadout before combat to bring cards."
		))
		return
	for card in _loadout.cards:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		var uses: int = GameState.get_card_uses(card)
		var cap: int = GameState.max_card_uses(card)
		var castable: bool = uses > 0 and _card_plays_remaining > 0
		lbl.text = "%s  (uses %d/%d)  —  %s" % [card.display_name, uses, cap, card.description]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(440, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		if uses <= 0:
			lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Play"
		btn.disabled = not castable
		btn.pressed.connect(_on_pick_ability.bind(card))
		row.add_child(btn)
		_ability_list_container.add_child(row)

func _on_pick_ability(card) -> void:
	_ability_dialog.visible = false
	# Re-check: the picker may have been left open across state changes.
	if _card_plays_remaining <= 0 or GameState.get_card_uses(card) <= 0:
		_status_label.text = "%s can't be played right now." % card.display_name
		return
	_pending_kind = Pending.ABILITY
	_pending_card = card
	if CombatLoadout.wants_enemy_target(card):
		_grid_view.enter_unit_target_mode(BattleGridView.TargetFilter.ENEMY)
		_status_label.text = "Playing %s — click an enemy (right-click to cancel)." % card.display_name
	else:
		_resolve_ability_against(null)

func _resolve_ability_against(target) -> void:
	if _pending_card == null:
		return
	var u = _turn_manager.current_unit
	var card = _pending_card
	# Spend one of the card's run-persistent uses; bail if somehow empty.
	if not GameState.spend_card_use(card):
		_status_label.text = "%s is out of uses." % card.display_name
		_pending_kind = Pending.NONE
		_pending_card = null
		_grid_view.enter_idle()
		return
	_card_plays_remaining -= 1
	_apply_card_or_spell_effects(card.effects, u, target, card)
	_pending_kind = Pending.NONE
	_pending_card = null
	_grid_view.enter_idle()
	_status_label.text = "Played %s. (%d uses left, %d plays left)" % [
		card.display_name, GameState.get_card_uses(card), _card_plays_remaining,
	]
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_button_states()
	_check_battle_end_after_effect()

# ----------------------------------------------------------------------
# Player actions — Spell
# ----------------------------------------------------------------------

func _on_spell_button() -> void:
	if not _is_player_turn():
		return
	_clear_pending()
	_grid_view.enter_idle()
	_populate_spell_picker()
	_spell_dialog.visible = true
	_ability_dialog.visible = false

func _populate_spell_picker() -> void:
	for child in _spell_list_container.get_children():
		child.queue_free()
	if _spellbook == null or _spellbook.spells.is_empty():
		_spell_list_container.add_child(_picker_note(
			"No spells learned. Learn spells from card rewards to populate."
		))
		return
	var u = _turn_manager.current_unit
	for entry in _spellbook.spells:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		var affordable: bool = _spellbook.can_cast(u, entry)
		lbl.text = "%s  (%d mana)  —  %s" % [
			entry.data.display_name, entry.data.cost, entry.data.description,
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(440, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Cast"
		btn.disabled = not affordable
		btn.pressed.connect(_on_pick_spell.bind(entry))
		row.add_child(btn)
		_spell_list_container.add_child(row)

func _on_pick_spell(entry) -> void:
	_spell_dialog.visible = false
	var u = _turn_manager.current_unit
	if not _spellbook.can_cast(u, entry):
		_status_label.text = "Not enough mana for %s." % entry.data.display_name
		return
	_pending_kind = Pending.SPELL
	_pending_spell = entry
	if entry.wants_target:
		var filter: int = BattleGridView.TargetFilter.ENEMY
		if entry.data.target_kind == "friendly":
			filter = BattleGridView.TargetFilter.ALLY
		_grid_view.enter_unit_target_mode(filter)
		_status_label.text = "Casting %s — pick a target (right-click to cancel)." % entry.data.display_name
	else:
		_resolve_spell_against(null)

func _resolve_spell_against(target) -> void:
	if _pending_spell == null:
		return
	var u = _turn_manager.current_unit
	var entry = _pending_spell
	_spellbook.spend_mana(u, entry)
	_apply_card_or_spell_effects(entry.data.effects, u, target, entry.data)
	_pending_kind = Pending.NONE
	_pending_spell = null
	_grid_view.enter_idle()
	_status_label.text = "Cast %s (mana now %d/%d)." % [
		entry.data.display_name, u.mana, u.max_mana,
	]
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_button_states()
	_check_battle_end_after_effect()

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
	# One move action per turn (no chaining): lock movement once committed,
	# even if tiles remain in the budget.
	_move_used = true
	# Phase 8: walking over an item collects it (auto-pickup goes to
	# run-scope counters; non-auto goes to the overworld inventory while
	# there's room). Each path step is checked so passing-by loot grabs.
	var pickup_msgs: Array = []
	for step in path:
		_try_pickup_at(step, pickup_msgs)
	_grid_view.set_active_unit(u, _move_remaining)
	_grid_view.enter_idle()
	var line: String = "Moved %d." % cost
	if not pickup_msgs.is_empty():
		line += "  " + ", ".join(pickup_msgs)
	_status_label.text = line
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_button_states()

func _try_pickup_at(pos: Vector2i, messages: Array) -> void:
	if _battle_map == null:
		return
	# Snapshot first — `_collect_item` mutates `_battle_map.items`.
	var hits: Array = []
	for entry in _battle_map.items:
		if entry.pos == pos:
			hits.append(entry)
	for entry in hits:
		var msg: String = _collect_item(entry)
		if msg != "":
			messages.append(msg)

# Returns a short message describing the pickup (empty string if nothing
# happened, e.g. pack-full on a non-auto item). Battle items live only in
# `_battle_map.items` during combat (CombatSession removes room originals
# at combat start), so removing the entry there is enough to drop them
# from the persistence-back pass.
func _collect_item(entry: Dictionary) -> String:
	var item = entry.item
	var player_entity = StrategyState.player
	if item.auto_pickup:
		match item.item_type:
			StrategyItem.ItemType.GOLD:
				# Gold persists across sections — write straight to GameState.
				GameState.change_gold(int(item.amount))
				_battle_map.remove_item_entry(entry)
				return "+%d gold" % int(item.amount)
			StrategyItem.ItemType.KEY:
				StrategyState.keys += 1
				_battle_map.remove_item_entry(entry)
				return "+key"
			_:
				_battle_map.remove_item_entry(entry)
				return "+%s" % str(item.item_name)
	if player_entity == null:
		return ""
	if player_entity.inventory.size() >= StrategyEntity.MAX_INVENTORY:
		return "(pack full: %s)" % str(item.item_name)
	player_entity.inventory.append(item)
	_battle_map.remove_item_entry(entry)
	return "picked up %s" % str(item.item_name)

func _on_attack_requested(target) -> void:
	if not _is_player_turn() or _action_used:
		return
	var attacker = _turn_manager.current_unit
	var dmg := DEFAULT_BASIC_ATTACK
	if attacker.basic_attack_def.has("damage"):
		dmg = int(attacker.basic_attack_def["damage"])
	_apply_damage(attacker, target, dmg)
	_action_used = true
	_grid_view.enter_idle()
	_status_label.text = "You strike %s for %d." % [target.unit_name, dmg]
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_button_states()

func _on_target_requested(target) -> void:
	if not _is_player_turn():
		return
	match _pending_kind:
		Pending.ABILITY:
			_resolve_ability_against(target)
		Pending.SPELL:
			_resolve_spell_against(target)
		_:
			pass

func _on_target_cancelled() -> void:
	if _pending_kind == Pending.NONE:
		return
	_clear_pending()
	_grid_view.enter_idle()
	_status_label.text = "Cancelled."

func _clear_pending() -> void:
	_pending_kind = Pending.NONE
	_pending_card = null
	_pending_spell = null

# ----------------------------------------------------------------------
# Effect resolution (called by EffectSystem handlers via this scene)
# ----------------------------------------------------------------------

# Public entry point used by both player flows (_apply_card_or_spell_effects)
# and EnemyAI.execute_turn — keeps targeting + dispatch in one place.
# `card` is the CardData driving the effects (ability/spell card or
# null for enemy AI moves); used by Stats.apply_addons_to_effect to
# fold compute-addon bonuses (Fishing Weight et al) into dmg values.
func apply_effects(effects: Array, source, target, card = null) -> void:
	_apply_card_or_spell_effects(effects, source, target, card)

func _apply_card_or_spell_effects(effects: Array, source, target, card = null) -> void:
	for raw_effect in effects:
		var effect: Dictionary = Stats.apply_addons_to_effect(raw_effect, card)
		var resolved_targets: Array = _resolve_effect_targets(effect, source, target)
		if resolved_targets.is_empty():
			# self-only effects with no explicit target — treat source as target.
			resolved_targets = [source]
		for t in resolved_targets:
			EffectSystem.apply(effect, {
				"source": source,
				"target": t,
				"scene": self,
				"card": card,
			})

func _resolve_effect_targets(effect: Dictionary, source, picked) -> Array:
	var kind: String = str(effect.get("target", "self"))
	match kind:
		"self":
			return [source]
		"enemy":
			return [picked] if picked != null else []
		"all_enemies":
			var out: Array = []
			for u in _units:
				if u.is_alive() and u.is_player != source.is_player:
					out.append(u)
			return out
		"all_allies":
			var out2: Array = []
			for u in _units:
				if u.is_alive() and u.is_player == source.is_player:
					out2.append(u)
			return out2
		_:
			return [picked] if picked != null else [source]

# --- EffectSystem callbacks (named exactly as deckbuilder combat). ---

func deal_damage(source, target, value: int, effect: Dictionary = {}) -> void:
	if target == null:
		return
	var raw: int = int(value)
	if effect.get("type", "") == "dmg_fraction_max_hp":
		raw = int(round(target.max_hp * float(effect.get("value", 0))))
	_apply_damage(source, target, raw, effect)

func gain_block(target, value: int) -> void:
	if target == null:
		return
	target.block = maxi(0, target.block) + int(value)

func heal(target, value: int) -> void:
	if target == null:
		return
	target.hp = mini(target.max_hp, target.hp + int(value))

func gain_energy(n: int) -> void:
	# No per-turn energy pool in strategy: "gain energy" grants extra card
	# plays this turn (one card play is the baseline). Lets gain-energy
	# cards set up a multi-card turn.
	if n <= 0:
		return
	_card_plays_remaining += n
	_status_label.text = "+%d card play this turn (%d total)." % [n, _card_plays_remaining]
	_refresh_button_states()

func lose_energy(n: int) -> void:
	# Symmetric to gain_energy: removes card plays this turn (tempo cost),
	# floored at 0.
	if n <= 0:
		return
	_card_plays_remaining = maxi(0, _card_plays_remaining - n)
	_refresh_button_states()

func draw_cards(n: int) -> void:
	# Strategy mode has no hand to draw into. Per design, each "draw" event
	# RECHARGES a use on a slotted card — restoring the card with the fewest
	# current uses first so it lands meaningfully. Stops if every slotted
	# card is already at max.
	if _loadout == null or n <= 0:
		return
	var restored_any: bool = false
	for _i in range(n):
		var best_card = null
		var best_uses: int = 1 << 30
		for card in _loadout.cards:
			var uses: int = GameState.get_card_uses(card)
			if uses < GameState.max_card_uses(card) and uses < best_uses:
				best_uses = uses
				best_card = card
		if best_card == null:
			break
		if GameState.recharge_card_use(best_card, 1) > 0:
			restored_any = true
	if restored_any:
		_status_label.text = "Recharged a card use."
		_refresh_button_states()

func discard_cards(n: int, _source_card = null, _random: bool = false) -> void:
	# No hand to discard. Strategy treats discard as a tempo cost: it spends
	# card plays this turn (same as lose_energy), floored at 0.
	if n <= 0:
		return
	_card_plays_remaining = maxi(0, _card_plays_remaining - n)
	_refresh_button_states()

# ----------------------------------------------------------------------
# Damage / death helpers
# ----------------------------------------------------------------------

func _apply_damage(source, target, raw_dmg: int, effect: Dictionary = {}) -> void:
	if target == null or raw_dmg <= 0:
		return
	var was_alive: bool = target.is_alive()
	var absorbed := mini(target.block, raw_dmg)
	target.block -= absorbed
	var landed := raw_dmg - absorbed
	target.hp = maxi(0, target.hp - landed)
	if was_alive and not target.is_alive() and not target.is_player:
		# Infuse: strategy mirrors deckbuilder — every killing blow with
		# infuse > 0 grants the player Max HP equal to the stack count.
		var infuse_stacks: int = int(effect.get("infuse", 0))
		if infuse_stacks > 0 and source != null and "is_player" in source and source.is_player:
			GameState.set_max_hp(GameState.max_hp + infuse_stacks, false)
		# Phase 8: enemy death -> roll loot onto the tile it fell on.
		_drop_enemy_loot(target)

func _drop_enemy_loot(unit) -> void:
	if _battle_map == null:
		return
	var table = ENEMY_LOOT_TABLE.get(str(unit.unit_name))
	if table == null:
		return
	var pos: Vector2i = unit.position
	if _loot_rng.randf() < float(table.gold_chance):
		var amt: int = _loot_rng.randi_range(int(table.gold_min), int(table.gold_max))
		_battle_map.add_dropped_item(StrategyItem.make_gold(pos, amt), pos)
	if _loot_rng.randf() < float(table.item_chance):
		var roll: int = _loot_rng.randi() % 10
		var it
		if roll < 6:
			it = StrategyItem.make_health_potion(pos)
		elif roll < 9:
			it = StrategyItem.make_strength_scroll(pos)
		else:
			it = StrategyItem.make_lightning_scroll(pos)
		_battle_map.add_dropped_item(it, pos)
	_grid_view.notify_units_changed()

func _check_battle_end_after_effect() -> void:
	# Spells/abilities can finish a fight; let the engine wrap up
	# immediately rather than waiting for End Turn.
	if _turn_manager != null:
		_turn_manager.check_battle_end_now()

# Register handler for the custom max-HP-fraction damage type so SPELLS_DATA
# spells (Abyss, Infinity) work without touching the global registry.
# Called once per BattleView instance — safe because EffectSystem.register
# is idempotent (last writer wins, and we always write the same callable).
func _enter_tree() -> void:
	EffectSystem.register("dmg_fraction_max_hp", _h_dmg_fraction_max_hp)

func _h_dmg_fraction_max_hp(effect: Dictionary, ctx: Dictionary) -> void:
	var target = ctx.get("target")
	if target == null:
		return
	var raw: int = int(round(target.max_hp * float(effect.get("value", 0))))
	deal_damage(ctx.get("source"), target, raw, effect)

# ----------------------------------------------------------------------
# Picker helpers
# ----------------------------------------------------------------------

func _picker_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return l

func _close_ability_dialog() -> void:
	_ability_dialog.visible = false

func _close_spell_dialog() -> void:
	_spell_dialog.visible = false

# ----------------------------------------------------------------------
# State refresh
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
	_btn_move.disabled = _move_used or _move_remaining <= 0
	_btn_attack.disabled = _action_used
	_btn_defend.disabled = _action_used
	# Cards button: live while plays remain and at least one slotted card
	# still has uses. Per-card use/affordability is gated per-row in
	# `_populate_ability_picker`.
	_btn_ability.disabled = _card_plays_remaining <= 0 or not _has_playable_card()
	_btn_spell.disabled = _spellbook == null or _spellbook.spells.is_empty()
	_btn_dash.disabled = not u.dash_available

func _has_playable_card() -> bool:
	if _loadout == null:
		return false
	for card in _loadout.cards:
		if GameState.get_card_uses(card) > 0:
			return true
	return false

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
		if u.is_alive() and not u.is_player and not u.intent_telegraph.is_empty():
			var tel: Dictionary = u.intent_telegraph
			var val: int = int(tel.get("value", 0))
			var tail: String = " (%d)" % val if val > 0 else ""
			lines.append("    next: %s %s%s" % [
				str(tel.get("icon", "")), str(tel.get("name", "")), tail,
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

	var card_count: int = _loadout.cards.size() if _loadout != null else 0
	var spell_count: int = _spellbook.spells.size() if _spellbook != null else 0
	return (
		"Room: %s  |  Encounter: %s  |  Field: %s (%s)\n"
		+ "Cards slotted: %d/%d  |  Spellbook: %d"
	) % [rect_str, enc_str, size_name, dims, card_count, CombatLoadout.MAX_SLOTS, spell_count]

extends CanvasLayer

# Phase 5+6: the tactical battle UI. Hosts the BattleGridView, an action
# bar, an initiative panel, and the Ability/Spellbook pickers wired to
# Phase-6's `AbilityPool` and `Spellbook`.
#
# Player turn rules (from STRATEGY_COMBAT_PLAN.md):
#   - Move up to `unit.speed` tiles (chained moves allowed).
#   - One of Attack OR Defend (`_action_used`).
#   - One non-basic Ability per turn (`_ability_used`), cooldown-gated.
#   - Any number of Spells while mana lasts.
#   - Dash once per combat: spends `dash_available` for a bonus turn.
#   - End Turn closes out the turn.
# Enemy turns auto-end on a short timer until Phase 7 lands real AI.
#
# Effect resolution: ability and spell effects route through the
# autoloaded `EffectSystem`, with `self` as the `scene` ctx so the
# tactical implementations of deal_damage/gain_block/heal handle the
# actual mutations.

const BattleGridViewScript := preload("res://scripts/strategy/combat/BattleGridView.gd")
const AbilityPoolScript := preload("res://scripts/strategy/combat/AbilityPool.gd")
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

var _ability_pool = null   # AbilityPool
var _spellbook = null      # Spellbook

# Mid-action state: which ability/spell is mid-cast while we wait for a target click.
var _pending_kind: int = Pending.NONE
var _pending_ability = null  # AbilityPool.Ability
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

var _enemy_turn_timer: Timer

# Per-turn state.
var _action_used: bool = false
var _ability_used: bool = false
var _move_remaining: int = 0

# Energy budget — Strategy analog of the deckbuilder energy pool. Each
# `gain_energy:N` adds N to the budget; the budget lets the player cast
# extra abilities beyond the normal one-per-turn cap, with each extra
# cast paying its card cost out of the budget. Resets to 0 at turn
# start (energy is a per-turn resource, same as deckbuilder).
var _energy_budget: int = 0

var _loot_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	layer = 10
	_loot_rng.randomize()
	_build_ui()

func set_encounter(room_data, encounter: Array, battle_map = null, turn_manager = null) -> void:
	_battle_map = battle_map
	_turn_manager = turn_manager
	_units = turn_manager.units if turn_manager != null else []
	_grid_view.set_battle(battle_map, _units)

	_ability_pool = AbilityPoolScript.build_from_deck(GameState.deck)
	_spellbook = SpellbookScript.build_from_ids(GameState.learned_spells)

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
# Turn flow
# ----------------------------------------------------------------------

func _on_unit_turn_started(unit) -> void:
	_grid_view.set_active_unit(unit, unit.speed)
	_refresh_initiative()
	if unit.is_player:
		_action_used = false
		_ability_used = false
		_move_remaining = unit.speed
		_energy_budget = 0
		_pending_kind = Pending.NONE
		_pending_ability = null
		_pending_spell = null
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
	if _move_remaining <= 0:
		_status_label.text = "No movement left."
		return
	_clear_pending()
	_grid_view.enter_move_mode()
	_status_label.text = "Click a highlighted tile to move (%d tiles left)." % _move_remaining

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
# Player actions — Ability
# ----------------------------------------------------------------------

func _on_ability_button() -> void:
	if not _is_player_turn():
		return
	# The energy budget can unlock the picker even after the normal
	# one-ability-per-turn cap has fired, as long as it covers some
	# ability's cost. Picker rows still disable individually based on
	# cooldown / affordability.
	if _ability_used and _energy_budget <= 0:
		return
	_clear_pending()
	_grid_view.enter_idle()
	_populate_ability_picker()
	_ability_dialog.visible = true
	_spell_dialog.visible = false

func _populate_ability_picker() -> void:
	for child in _ability_list_container.get_children():
		child.queue_free()
	if _ability_pool == null or _ability_pool.abilities.is_empty():
		_ability_list_container.add_child(_picker_note(
			"No abilities in your deck. Non-basic cards become abilities."
		))
		return
	var u = _turn_manager.current_unit
	for ability in _ability_pool.abilities:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		var cd: int = _ability_pool.remaining_cooldown(u, ability.id)
		var ready: bool = cd <= 0
		var cost: int = maxi(0, int(ability.card.cost))
		# When the normal one-ability-per-turn cap has been spent, only
		# abilities whose cost the budget covers remain castable.
		var affordable: bool = (not _ability_used) or _energy_budget >= cost
		var castable: bool = ready and affordable
		var status: String = "(CD %d)" % cd if not ready else "(CD %d on use)" % ability.base_cooldown
		if _ability_used:
			status += "  [energy %d/%d]" % [cost, _energy_budget]
		lbl.text = "%s  %s  —  %s" % [ability.display_name, status, ability.description]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(440, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Cast"
		btn.disabled = not castable
		btn.pressed.connect(_on_pick_ability.bind(ability))
		row.add_child(btn)
		_ability_list_container.add_child(row)

func _on_pick_ability(ability) -> void:
	_ability_dialog.visible = false
	_pending_kind = Pending.ABILITY
	_pending_ability = ability
	if ability.wants_target:
		_grid_view.enter_unit_target_mode(BattleGridView.TargetFilter.ENEMY)
		_status_label.text = "Casting %s — click an enemy (right-click to cancel)." % ability.display_name
	else:
		_resolve_ability_against(null)

func _resolve_ability_against(target) -> void:
	if _pending_ability == null:
		return
	var u = _turn_manager.current_unit
	var ability = _pending_ability
	# Pay the one-ability-per-turn cap first; once that's spent, extra
	# casts come out of the energy budget at the card's cost.
	if _ability_used:
		_energy_budget = maxi(0, _energy_budget - maxi(0, int(ability.card.cost)))
	_apply_card_or_spell_effects(ability.card.effects, u, target)
	_ability_pool.set_cooldown(u, ability)
	_ability_used = true
	_pending_kind = Pending.NONE
	_pending_ability = null
	_grid_view.enter_idle()
	_status_label.text = "Cast %s (cooldown %d)." % [ability.display_name, ability.base_cooldown]
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
	_apply_card_or_spell_effects(entry.data.effects, u, target)
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
	# Phase 8: walking over an item collects it (auto-pickup goes to
	# run-scope counters; non-auto goes to the overworld inventory while
	# there's room). Each path step is checked so passing-by loot grabs.
	var pickup_msgs: Array = []
	for step in path:
		_try_pickup_at(step, pickup_msgs)
	_grid_view.set_active_unit(u, _move_remaining)
	if _move_remaining > 0:
		_grid_view.enter_move_mode()
	else:
		_grid_view.enter_idle()
	var line: String = "Moved %d. %d move left." % [cost, _move_remaining]
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
	_pending_ability = null
	_pending_spell = null

# ----------------------------------------------------------------------
# Effect resolution (called by EffectSystem handlers via this scene)
# ----------------------------------------------------------------------

# Public entry point used by both player flows (_apply_card_or_spell_effects)
# and EnemyAI.execute_turn — keeps targeting + dispatch in one place.
func apply_effects(effects: Array, source, target) -> void:
	_apply_card_or_spell_effects(effects, source, target)

func _apply_card_or_spell_effects(effects: Array, source, target) -> void:
	for effect in effects:
		var resolved_targets: Array = _resolve_effect_targets(effect, source, target)
		if resolved_targets.is_empty():
			# self-only effects with no explicit target — treat source as target.
			resolved_targets = [source]
		for t in resolved_targets:
			EffectSystem.apply(effect, {
				"source": source,
				"target": t,
				"scene": self,
				"card": null,
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
	_apply_damage(source, target, raw)

func gain_block(target, value: int) -> void:
	if target == null:
		return
	target.block = maxi(0, target.block) + int(value)

func heal(target, value: int) -> void:
	if target == null:
		return
	target.hp = mini(target.max_hp, target.hp + int(value))

func gain_energy(n: int) -> void:
	# Strategy analog of the deckbuilder energy pool. Adds to a
	# per-turn budget that lets the player cast extra abilities beyond
	# the normal one-per-turn cap, paid out at the card's cost.
	if n <= 0:
		return
	_energy_budget += n
	_refresh_button_states()

func lose_energy(n: int) -> void:
	# Eat the budget first; any remainder locks the normal ability use
	# for the turn (drives `_ability_used` true so the picker is gated
	# until energy is regained).
	if n <= 0:
		return
	var remainder: int = n - _energy_budget
	_energy_budget = maxi(0, _energy_budget - n)
	if remainder > 0:
		_ability_used = true
	_refresh_button_states()

func draw_cards(n: int) -> void:
	# Strategy mode has no hand to draw into. Per design, each "draw"
	# event reduces a random ability's remaining cooldown by 1 instead.
	if _turn_manager == null or _ability_pool == null or n <= 0:
		return
	var unit = _turn_manager.current_unit
	if unit == null:
		return
	for _i in range(n):
		var ids_on_cd: Array = []
		for ability in _ability_pool.abilities:
			if int(unit.cooldowns.get(ability.id, 0)) > 0:
				ids_on_cd.append(ability.id)
		if ids_on_cd.is_empty():
			break
		var pick: StringName = ids_on_cd[randi() % ids_on_cd.size()]
		unit.cooldowns[pick] = maxi(0, int(unit.cooldowns[pick]) - 1)

func discard_cards(n: int, _source_card = null) -> void:
	# Mirror of `draw_cards`: each discard adds 1 to the ability with
	# the LOWEST current cooldown so the effect lands even when
	# everything is ready (a ready ability goes onto a 1-turn CD).
	if _turn_manager == null or _ability_pool == null or n <= 0:
		return
	var unit = _turn_manager.current_unit
	if unit == null or _ability_pool.abilities.is_empty():
		return
	for _i in range(n):
		var best_id: StringName = &""
		var best_cd: int = 99999
		for ability in _ability_pool.abilities:
			var cd: int = int(unit.cooldowns.get(ability.id, 0))
			if cd < best_cd:
				best_cd = cd
				best_id = ability.id
		if best_id == &"":
			return
		unit.cooldowns[best_id] = best_cd + 1

# ----------------------------------------------------------------------
# Damage / death helpers
# ----------------------------------------------------------------------

func _apply_damage(_source, target, raw_dmg: int) -> void:
	if target == null or raw_dmg <= 0:
		return
	var was_alive: bool = target.is_alive()
	var absorbed := mini(target.block, raw_dmg)
	target.block -= absorbed
	var landed := raw_dmg - absorbed
	target.hp = maxi(0, target.hp - landed)
	# Phase 8: enemy death -> roll loot onto the tile it fell on.
	if was_alive and not target.is_alive() and not target.is_player:
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
	_btn_move.disabled = _move_remaining <= 0
	_btn_attack.disabled = _action_used
	_btn_defend.disabled = _action_used
	# Energy budget can keep the Ability button live even after the
	# one-per-turn cap is spent — affordability/cooldown is gated
	# per-row inside `_populate_ability_picker`.
	var ability_locked: bool = _ability_pool == null or _ability_pool.abilities.is_empty()
	_btn_ability.disabled = ability_locked or (_ability_used and _energy_budget <= 0)
	_btn_spell.disabled = _spellbook == null or _spellbook.spells.is_empty()
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

	var abil_count: int = _ability_pool.abilities.size() if _ability_pool != null else 0
	var spell_count: int = _spellbook.spells.size() if _spellbook != null else 0
	return (
		"Room: %s  |  Encounter: %s  |  Field: %s (%s)\n"
		+ "Abilities: %d  |  Spellbook: %d  |  Enemy AI lands in Phase 7."
	) % [rect_str, enc_str, size_name, dims, abil_count, spell_count]

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
#   - Move up to `unit.move_range` tiles, ONE move action per turn (no chaining).
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

# Layout (designed against the 1280x720 base viewport). The board fills the
# big left panel; the turn order + log stack on the right; the action bar runs
# along the bottom.
const BOARD_RECT := Rect2(14, 78, 902, 566)
const TURN_RECT := Rect2(928, 78, 338, 360)
const LOG_RECT := Rect2(928, 446, 338, 198)
const BAR_Y := 656

# Shared palette for the chrome.
const ACCENT := Color(1.0, 0.78, 0.36)
const PANEL_BG := Color(0.09, 0.07, 0.13, 0.96)
const PANEL_BORDER := Color(0.42, 0.33, 0.55, 0.9)
# Full-screen backdrop behind both the battle UI and the loadout screen, so the
# two read as one cohesive screen.
const BACKDROP := Color(0.04, 0.035, 0.07, 1.0)

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

var _loadout = null        # CombatLoadout (the 3 chosen cards + weapon)
var _available_cards: Array = []  # choosable pool for the loadout screen
var _selected_cards: Array = []   # mid-selection on the loadout screen
var _available_weapons: Array = []  # weapon cards in the deck
var _selected_weapon = null         # CardData chosen on the loadout screen
var _weapon_card = null             # CardData equipped for this combat (or null)
var _spellbook = null      # Spellbook

# Mid-action state: which card/spell is mid-cast while we wait for a target click.
var _pending_kind: int = Pending.NONE
var _pending_card = null     # CardData (slotted loadout card)
var _pending_spell = null    # Spellbook.Entry

var _grid_view: BattleGridView
var _initiative_label: Label
var _status_label: Label
var _info_label: Label
var _root_panel: Panel

# Floating Mewgenics-style enemy info card, populated on hover.
var _enemy_tooltip: Panel
var _enemy_tooltip_name: Label
var _enemy_tooltip_body: Label

var _btn_move: Button
var _btn_attack: Button
var _btn_defend: Button
var _btn_ability: Button
var _btn_spell: Button
var _btn_dash: Button
var _btn_item: Button
var _btn_end: Button
var _btn_win: Button
var _btn_lose: Button

var _ability_dialog: Panel
var _ability_list_container: VBoxContainer
var _spell_dialog: Panel
var _spell_list_container: VBoxContainer
var _item_dialog: Panel
var _item_list_container: VBoxContainer
var _inventory_panel: CombatInventory

# Pre-combat loadout screen.
var _loadout_overlay: Panel
var _loadout_enemy_container: VBoxContainer   # styled enemy chips
var _loadout_field_label: Label               # battlefield summary line
var _loadout_slots_label: Label               # "Card slots filled" readout
var _loadout_pips: HBoxContainer              # visual slot pips
var _loadout_pool_container: VBoxContainer    # weapon + card grids
var _loadout_start_btn: Button

var _enemy_turn_timer: Timer
var _fear_turn_timer: Timer

# Per-turn state.
var _action_used: bool = false
var _move_used: bool = false   # one Move action per turn (no chaining)
var _move_remaining: int = 0

# Card plays left this turn. Baseline 1 (one card per turn); discard effects
# subtract plays. Each card play spends one of the card's run-persistent uses
# (GameState.spend_card_use).
var _card_plays_remaining: int = 0
# Ice Cream: did the player resolve an ability card this turn? A turn that
# ends without one banks an empower charge (see _on_unit_turn_ended).
var _ability_used_this_turn: bool = false
# Mummified Hand: a slotted ability INSTANCE that costs no per-turn play this
# turn (it still spends a use). null = none. Reset each turn.
var _free_ability_card = null

# Ethereal -> deactivate_if_idle (Strategy): once the player ends a turn without
# playing any Ethereal ability, every Ethereal ability is locked out for the
# rest of the combat. `_ethereal_used_this_turn` resets each player turn.
var _ethereal_deactivated: bool = false
var _ethereal_used_this_turn: bool = false

# Energy charge banked from gain-energy effects. It persists across turns
# within a combat until spent: the next card play consumes ALL of it and is
# empowered by that amount (+dmg / +block / +status stacks), then it resets
# to 0. gain_energy adds, lose_energy removes. Empower-only — energy grants
# no extra plays.
var _energy_charge: int = 0

# Turn-based -> Strategy concept mapping (energy->empower charge, draw->card-use
# recharge, discard->tempo). Single editable source of truth; see
# StrategyTranslation.gd / data/strategy_translation.tres. Cached in _ready.
var _tr: StrategyTranslation

# Counts the player unit's turns this combat so turn-based items (e.g.
# Horn Cleat: +Block on the 2nd turn) fire on the right turn. Reset per
# encounter; incremented at the start of each player turn.
var _player_turn_count: int = 0

# Curse-of-the-turn (strategy translation of the curse cards): at the start of
# each player turn ONE random owned curse is chosen and telegraphed; only it
# acts this turn. eot curses fire at turn end (status/dmg/Regret); Pain bites per
# action; bricks impose all-stats-down for the turn. _turn_actions counts the
# player's actions this turn (move/attack/spell/card) for Regret/Pain.
var _turn_curse: CardData = null
var _turn_actions: int = 0
var _turn_stat_debuff: bool = false
const _CURSE_STAT_DOWN := ["strength", "dexterity", "intelligence", "charisma"]

var _loot_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	layer = 10
	_loot_rng.randomize()
	_tr = Data.strategy_translation
	if _tr == null:
		_tr = StrategyTranslation.new()  # defensive: never run without the map
	_build_ui()

# The player-controlled unit in this battle, or null. Used by the backpack /
# consumable system to target pill effects at the player.
func get_player_unit():
	for u in _units:
		if u != null and u.is_player:
			return u
	return null

# Shared item-trigger fire for the non-turn triggers (combat start/end, enemy
# kill). turn_started keeps its own direct path (_fire_item_turn_triggers).
func _fire_item_triggers(trigger_name: String, ctx_extras: Dictionary = {}) -> void:
	ItemTriggers.fire(trigger_name, self, get_player_unit(), _living_enemy_units(),
		ctx_extras, _player_turn_count)
	if _grid_view != null:
		_grid_view.notify_units_changed()

func _living_enemy_units() -> Array:
	var out: Array = []
	for u in _units:
		if u != null and u.is_alive() and not u.is_player:
			out.append(u)
	return out

# A card's base effects with item boosts folded in (Strike Dummy) plus any
# appended granted effects (Brass Knuckles etc.). Strategy resolves CardData
# directly, so the shared CardMods pass is applied here (deckbuilder gets it via
# CardInstance.get_effects()).
func _effective_card_effects(card: CardData) -> Array:
	return CardMods.resolved_effects(card.effects, card)

# Card text with live stat scaling AND item boosts folded into the numbers
# (Power / Arcane / Defense / Persistence + Strike Dummy — rich=false since these
# are plain Labels) plus the granted-effect line appended, for display.
func _card_desc(card: CardData) -> String:
	var out: String = CardScaling.scale_text(card.description, get_player_unit(), false, card)
	var extra: String = CardMods.describe(card)
	if extra != "":
		out = "%s %s" % [out, extra]
	return out

func set_encounter(room_data, encounter: Array, battle_map = null, turn_manager = null) -> void:
	_battle_map = battle_map
	_turn_manager = turn_manager
	_units = turn_manager.units if turn_manager != null else []
	_room_data = room_data
	_encounter = encounter
	_grid_view.set_battle(battle_map, _units)
	_layout_board()

	_available_cards = CombatLoadoutScript.available_from_deck(GameState.deck)
	_available_weapons = CombatLoadoutScript.weapon_cards_from_deck(GameState.deck)
	_loadout = CombatLoadoutScript.new()
	_selected_cards = []
	_selected_weapon = null
	_weapon_card = null
	_energy_charge = 0
	_player_turn_count = 0
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
	bg.bg_color = BACKDROP
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	_root_panel = panel

	var title := Label.new()
	title.text = "⚔  TACTICAL BATTLE"
	title.position = Vector2(18, 8)
	title.size = Vector2(520, 36)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	panel.add_child(title)

	_info_label = Label.new()
	_info_label.position = Vector2(20, 48)
	_info_label.size = Vector2(880, 26)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.82))
	panel.add_child(_info_label)

	# Board backdrop.
	panel.add_child(_section_panel(BOARD_RECT))

	_grid_view = BattleGridViewScript.new()
	_grid_view.position = BOARD_RECT.position + Vector2(14, 14)
	_grid_view.move_requested.connect(_on_move_requested)
	_grid_view.attack_requested.connect(_on_attack_requested)
	_grid_view.target_requested.connect(_on_target_requested)
	_grid_view.target_cancelled.connect(_on_target_cancelled)
	_grid_view.hover_changed.connect(_on_grid_hover)
	panel.add_child(_grid_view)

	# Turn-order panel.
	panel.add_child(_section_panel(TURN_RECT))
	panel.add_child(_section_header("TURN ORDER", TURN_RECT))
	_initiative_label = Label.new()
	_initiative_label.position = TURN_RECT.position + Vector2(14, 42)
	_initiative_label.size = Vector2(TURN_RECT.size.x - 28, TURN_RECT.size.y - 56)
	_initiative_label.add_theme_font_size_override("font_size", 13)
	_initiative_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	panel.add_child(_initiative_label)

	# Status / log panel.
	panel.add_child(_section_panel(LOG_RECT))
	panel.add_child(_section_header("STATUS", LOG_RECT))
	_status_label = Label.new()
	_status_label.position = LOG_RECT.position + Vector2(14, 42)
	_status_label.size = Vector2(LOG_RECT.size.x - 28, LOG_RECT.size.y - 56)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	panel.add_child(_status_label)

	_build_action_bar(panel)
	_build_pickers()
	_build_inventory_panel(panel)
	_build_loadout_overlay()
	_build_enemy_tooltip()

	_enemy_turn_timer = Timer.new()
	_enemy_turn_timer.one_shot = true
	_enemy_turn_timer.wait_time = ENEMY_TURN_DELAY
	_enemy_turn_timer.timeout.connect(_auto_end_enemy_turn)
	add_child(_enemy_turn_timer)

	# Fear: a feared unit (player OR enemy) flees at the start of its turn, then
	# its turn ends after this beat — no AI, no player control. Separate from the
	# enemy timer because _auto_end_enemy_turn runs AI and ignores player units.
	_fear_turn_timer = Timer.new()
	_fear_turn_timer.one_shot = true
	_fear_turn_timer.wait_time = ENEMY_TURN_DELAY
	_fear_turn_timer.timeout.connect(_auto_end_feared_turn)
	add_child(_fear_turn_timer)

# --- Chrome helpers ----------------------------------------------------

func _panel_stylebox(fill: Color, border: Color, border_w: int = 2, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	return sb

func _section_panel(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _panel_stylebox(PANEL_BG, PANEL_BORDER))
	return p

func _section_header(text: String, rect: Rect2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position + Vector2(14, 10)
	l.size = Vector2(rect.size.x - 28, 22)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", ACCENT)
	return l

func _build_action_bar(panel: Panel) -> void:
	# Framed strip behind the action buttons so the bar reads as a panel like the
	# rest of the chrome (mouse-ignored, so it doesn't eat button clicks).
	panel.add_child(_section_panel(Rect2(8, BAR_Y - 8, 824, 56)))
	var x := 16
	var spacing := 8
	var btn_h := 40
	var specs := [
		["Move", 84, _on_move_button], ["Attack", 92, _on_attack_button],
		["Defend", 92, _on_defend_button], ["Cards", 92, _on_ability_button],
		["Spellbook", 112, _on_spell_button], ["Dash", 84, _on_dash_button],
		["Item", 84, _on_item_button], ["End Turn", 104, _on_end_turn_button],
	]
	var btns := []
	for spec in specs:
		var b := _make_button(spec[0], x, BAR_Y, spec[1], btn_h, spec[2])
		panel.add_child(b)
		btns.append(b)
		x += spec[1] + spacing
	_btn_move = btns[0]; _btn_attack = btns[1]; _btn_defend = btns[2]
	_btn_ability = btns[3]; _btn_spell = btns[4]; _btn_dash = btns[5]
	_btn_item = btns[6]; _btn_end = btns[7]
	# End Turn is the main per-turn confirm — give it the same gold CTA look as
	# the loadout screen's Start Battle.
	_style_primary(_btn_end)

	# Hovering an action button previews the relevant ranges on the board:
	# Move/Attack show movement + strike reach; Cards/Spellbook show movement +
	# every enemy you could target. Mouse-out clears the preview.
	for b in [_btn_move, _btn_attack]:
		b.mouse_entered.connect(_on_hover_attack_preview)
		b.mouse_exited.connect(_on_hover_preview_end)
	for b in [_btn_ability, _btn_spell]:
		b.mouse_entered.connect(_on_hover_targets_preview)
		b.mouse_exited.connect(_on_hover_preview_end)

	# Debug force win/lose — only mounted in dev mode so they can't be clicked
	# by accident during a normal playthrough.
	if Settings.dev_mode:
		_btn_win = _make_button("Win▸", 1110, BAR_Y, 72, btn_h, _on_force_win, true)
		panel.add_child(_btn_win)
		_btn_lose = _make_button("Lose▸", 1190, BAR_Y, 72, btn_h, _on_force_lose, true)
		panel.add_child(_btn_lose)

func _make_button(text: String, x: int, y: int, w: int, h: int, cb: Callable, subtle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = Vector2(x, y)
	b.size = Vector2(w, h)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	var base: Color = Color(0.15, 0.13, 0.2) if not subtle else Color(0.1, 0.09, 0.12)
	var border: Color = PANEL_BORDER if not subtle else Color(0.3, 0.25, 0.3)
	b.add_theme_stylebox_override("normal", _panel_stylebox(base, border, 1, 10))
	b.add_theme_stylebox_override("hover", _panel_stylebox(base.lightened(0.18), ACCENT, 2, 10))
	b.add_theme_stylebox_override("pressed", _panel_stylebox(base.darkened(0.2), ACCENT, 2, 10))
	var disabled_sb := _panel_stylebox(Color(0.09, 0.08, 0.1), Color(0.2, 0.2, 0.22), 1, 10)
	b.add_theme_stylebox_override("disabled", disabled_sb)
	b.add_theme_color_override("font_color", Color(0.92, 0.9, 0.96))
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.5))
	return b

# --- Enemy hover tooltip ----------------------------------------------

func _build_enemy_tooltip() -> void:
	_enemy_tooltip = Panel.new()
	_enemy_tooltip.size = Vector2(248, 10)
	_enemy_tooltip.visible = false
	_enemy_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_tooltip.add_theme_stylebox_override("panel",
		_panel_stylebox(Color(0.07, 0.06, 0.1, 0.98), ACCENT, 1, 8))
	_enemy_tooltip_name = Label.new()
	_enemy_tooltip_name.position = Vector2(12, 8)
	_enemy_tooltip_name.size = Vector2(224, 22)
	_enemy_tooltip_name.add_theme_font_size_override("font_size", 15)
	_enemy_tooltip_name.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
	_enemy_tooltip.add_child(_enemy_tooltip_name)
	_enemy_tooltip_body = Label.new()
	_enemy_tooltip_body.position = Vector2(12, 34)
	_enemy_tooltip_body.size = Vector2(224, 10)
	_enemy_tooltip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy_tooltip_body.add_theme_font_size_override("font_size", 12)
	_enemy_tooltip_body.add_theme_color_override("font_color", Color(0.86, 0.86, 0.9))
	_enemy_tooltip.add_child(_enemy_tooltip_body)
	add_child(_enemy_tooltip)

func _unit_at_grid(pos: Vector2i):
	for u in _units:
		if u != null and u.is_alive() and u.position == pos:
			return u
	return null

func _on_grid_hover(pos: Vector2i) -> void:
	# Enemies show their stat/intent card; battlefield items (loot, gold, keys,
	# scrolls) show what they are. Anything else hides the tooltip.
	var u = _unit_at_grid(pos)
	if u != null and not u.is_player and u.is_alive():
		_enemy_tooltip_name.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
		_show_tooltip("%s    %d/%d HP" % [str(u.unit_name).capitalize(), u.hp, u.max_hp],
			_enemy_tooltip_text(u), pos)
		return
	var entry := _item_entry_at_grid(pos)
	if not entry.is_empty():
		_enemy_tooltip_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_show_tooltip(str(entry.item.item_name).capitalize(), _item_tooltip_text(entry.item), pos)
		return
	_enemy_tooltip.visible = false

# Sizes the shared tooltip from its body line count and parks it next to the
# hovered tile, clamped on-screen.
func _show_tooltip(name_text: String, body_text: String, pos: Vector2i) -> void:
	_enemy_tooltip_name.text = name_text
	_enemy_tooltip_body.text = body_text
	var n_lines: int = body_text.count("\n") + 1
	var body_h: int = n_lines * 17 + 4
	_enemy_tooltip_body.size.y = body_h
	_enemy_tooltip.size.y = 40 + body_h + 10
	var screen := _grid_view.position + Vector2(
		pos.x * _grid_view.tile_size + _grid_view.tile_size + 8,
		pos.y * _grid_view.tile_size)
	var vp := get_viewport().get_visible_rect().size
	screen.x = clampf(screen.x, 8, vp.x - _enemy_tooltip.size.x - 8)
	screen.y = clampf(screen.y, 8, vp.y - _enemy_tooltip.size.y - 8)
	_enemy_tooltip.position = screen
	_enemy_tooltip.visible = true

# --- Hover range previews ---------------------------------------------

# Movement budget still available for a preview: 0 once the turn's single move
# is spent, otherwise the remaining tiles.
func _hover_move_budget() -> int:
	return 0 if _move_used else _move_remaining

# The player's strike reach in tiles (weapon range, or the basic-attack range,
# default melee/1).
func _player_attack_range() -> int:
	if _weapon_card != null:
		if "range" in _weapon_card.data:
			return maxi(1, int(_weapon_card.data.range))
		return 1
	var u = get_player_unit()
	if u != null and u.basic_attack_def.has("range"):
		return int(u.basic_attack_def.get("range", 1))
	return 1

func _enemy_positions() -> Array:
	var out: Array = []
	for u in _units:
		if u != null and u.is_alive() and not u.is_player:
			out.append(u.position)
	return out

func _on_hover_attack_preview() -> void:
	if not _is_player_turn():
		return
	_grid_view.show_range_preview(_hover_move_budget(), _player_attack_range())

func _on_hover_targets_preview() -> void:
	if not _is_player_turn():
		return
	# Cards/spells target any enemy on the field — flag them all as reachable.
	_grid_view.show_range_preview(_hover_move_budget(), 0, _enemy_positions())

# Card/spell row hover: movement plus the targets that ability could hit.
func _on_hover_card_preview(targets_enemies: bool) -> void:
	if not _is_player_turn():
		return
	var targets: Array = _enemy_positions() if targets_enemies else []
	_grid_view.show_range_preview(_hover_move_budget(), 0, targets)

func _on_hover_preview_end() -> void:
	_grid_view.clear_range_preview()

func _item_entry_at_grid(pos: Vector2i) -> Dictionary:
	if _battle_map == null:
		return {}
	for entry in _battle_map.items:
		if entry.pos == pos:
			return entry
	return {}

# Short "what is this" blurb for a battlefield item, by kind.
func _item_tooltip_text(item) -> String:
	var lines: Array = []
	match item.item_type:
		StrategyItem.ItemType.HEALTH_POTION:
			lines.append("Health potion.")
			lines.append("Restores HP when used.")
		StrategyItem.ItemType.STRENGTH_SCROLL:
			lines.append("Scroll of strength.")
			lines.append("Permanently raises attack.")
		StrategyItem.ItemType.LIGHTNING_SCROLL:
			lines.append("Scroll of lightning.")
			lines.append("Strikes the nearest visible foe.")
		StrategyItem.ItemType.KEY:
			lines.append("Key.")
			lines.append("Opens a locked door.")
		StrategyItem.ItemType.GOLD:
			lines.append("%d gold." % int(item.amount))
		_:
			lines.append(str(item.item_name))
	if item.auto_pickup:
		lines.append("Walk over it to collect.")
	else:
		lines.append("Walk over it to pick up (needs a pack slot).")
	return "\n".join(lines)

# Multi-line body: ranges + the full intent "pattern" with the telegraphed
# next move flagged, then any active statuses.
func _enemy_tooltip_text(u) -> String:
	var lines: Array = []
	lines.append("Move range: %d" % u.move_range)
	lines.append("Attack range: %d" % _grid_view.enemy_attack_range(u))
	lines.append("")
	lines.append("Pattern:")
	var next_id: String = String(u.intent_telegraph.get("id", "")) if not u.intent_telegraph.is_empty() else ""
	if u.ai != null and "intents" in u.ai and not u.ai.intents.is_empty():
		for it in u.ai.intents:
			if it == null:
				continue
			var marker: String = "▶ " if String(it.id) == next_id else "   "
			var val: int = it.headline_value()
			var parts: Array = []
			if val > 0:
				parts.append("%d dmg" % val if it.target_kind != "self" else "%d" % val)
			parts.append("rng %d" % it.range_max)
			if it.cooldown > 0:
				parts.append("cd %d" % it.cooldown)
			lines.append("%s%s  (%s)" % [marker, it.display_name, ", ".join(parts)])
	else:
		lines.append("   Basic attack")
	var statuses: Array = []
	for s in u.statuses.keys():
		if int(u.statuses[s]) > 0:
			statuses.append("%s %d" % [String(s).capitalize(), int(u.statuses[s])])
	if not statuses.is_empty():
		lines.append("")
		lines.append("Status: " + ", ".join(statuses))
	return "\n".join(lines)

# Scale the board to fill the board panel and center it within.
func _layout_board() -> void:
	if _battle_map == null:
		return
	var pad := 16
	var avail_w: int = int(BOARD_RECT.size.x) - pad * 2
	var avail_h: int = int(BOARD_RECT.size.y) - pad * 2
	@warning_ignore("integer_division")
	var ts: int = mini(avail_w / maxi(1, _battle_map.width), avail_h / maxi(1, _battle_map.height))
	ts = clampi(ts, 14, 54)
	_grid_view.set_tile_size(ts)
	var gw: int = _battle_map.width * ts
	var gh: int = _battle_map.height * ts
	_grid_view.position = BOARD_RECT.position + Vector2(
		(BOARD_RECT.size.x - gw) / 2.0, (BOARD_RECT.size.y - gh) / 2.0)

func _build_pickers() -> void:
	_ability_dialog = _make_picker_dialog("Abilities", _close_ability_dialog)
	_ability_list_container = _ability_dialog.get_meta("list")
	add_child(_ability_dialog)
	_ability_dialog.visible = false

	_spell_dialog = _make_picker_dialog("Spellbook", _close_spell_dialog)
	_spell_list_container = _spell_dialog.get_meta("list")
	add_child(_spell_dialog)
	_spell_dialog.visible = false

	_item_dialog = _make_picker_dialog("Items", _close_item_dialog)
	_item_list_container = _item_dialog.get_meta("list")
	add_child(_item_dialog)
	_item_dialog.visible = false

# The pickers dock over the right-hand column (turn order / status) so the
# battlefield stays fully visible while choosing a card or spell — letting the
# on-hover range preview read against the board.
func _make_picker_dialog(title_text: String, close_cb: Callable) -> Panel:
	var p := Panel.new()
	p.position = Vector2(922, 74)
	p.size = Vector2(352, 578)
	p.add_theme_stylebox_override("panel", _panel_stylebox(Color(0.1, 0.08, 0.15, 0.99), ACCENT, 2, 12))

	var t := Label.new()
	t.text = title_text
	t.position = Vector2(16, 12)
	t.size = Vector2(320, 30)
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	p.add_child(t)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(14, 48)
	scroll.size = Vector2(324, 478)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)
	p.set_meta("list", vbox)

	var close := _make_button("Close", 126, 534, 100, 36, close_cb)
	p.add_child(close)
	return p

# Compact item rack pinned to the top-right corner so the player's actives are
# visible at a glance during a tactical battle (charged actives show their bar).
# The full list with Use buttons lives behind the "Item" action button.
func _build_inventory_panel(panel: Panel) -> void:
	_inventory_panel = CombatInventory.new()
	_inventory_panel.columns = 8
	_inventory_panel.tile_px = 26
	_inventory_panel.show_title = false
	_inventory_panel.panel_opacity = 0.92
	_inventory_panel.position = Vector2(940, 44)
	panel.add_child(_inventory_panel)

# ----------------------------------------------------------------------
# Pre-combat loadout screen
# ----------------------------------------------------------------------

# Left column shows the enemy roster; the right column holds the weapon + card
# loadout as a grid of selectable tiles. Both columns are framed with the same
# chrome as the in-combat panels for a consistent look.
const LO_LEFT := Rect2(32, 96, 372, 540)
const LO_RIGHT := Rect2(420, 96, 828, 540)

func _build_loadout_overlay() -> void:
	_loadout_overlay = Panel.new()
	_loadout_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loadout_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = BACKDROP
	_loadout_overlay.add_theme_stylebox_override("panel", bg)

	# Header band.
	var title := Label.new()
	title.text = "⚔  PREPARE FOR BATTLE"
	title.position = Vector2(40, 26)
	title.size = Vector2(820, 36)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", ACCENT)
	_loadout_overlay.add_child(title)

	_loadout_field_label = Label.new()
	_loadout_field_label.position = Vector2(44, 64)
	_loadout_field_label.size = Vector2(1000, 22)
	_loadout_field_label.add_theme_font_size_override("font_size", 13)
	_loadout_field_label.add_theme_color_override("font_color", Color(0.72, 0.74, 0.82))
	_loadout_overlay.add_child(_loadout_field_label)

	# Left column — enemy roster.
	_loadout_overlay.add_child(_section_panel(LO_LEFT))
	_loadout_overlay.add_child(_section_header("ENEMIES", LO_LEFT))
	var enemy_scroll := ScrollContainer.new()
	enemy_scroll.position = LO_LEFT.position + Vector2(16, 40)
	enemy_scroll.size = Vector2(LO_LEFT.size.x - 32, LO_LEFT.size.y - 56)
	enemy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loadout_overlay.add_child(enemy_scroll)
	_loadout_enemy_container = VBoxContainer.new()
	_loadout_enemy_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_enemy_container.add_theme_constant_override("separation", 10)
	enemy_scroll.add_child(_loadout_enemy_container)

	# Right column — loadout.
	_loadout_overlay.add_child(_section_panel(LO_RIGHT))
	_loadout_overlay.add_child(_section_header("YOUR LOADOUT", LO_RIGHT))

	var pips_label := Label.new()
	pips_label.text = "CARD SLOTS"
	pips_label.position = Vector2(LO_RIGHT.end.x - 210, LO_RIGHT.position.y + 12)
	pips_label.size = Vector2(106, 20)
	pips_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pips_label.add_theme_font_size_override("font_size", 12)
	pips_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	_loadout_overlay.add_child(pips_label)

	_loadout_pips = HBoxContainer.new()
	_loadout_pips.position = Vector2(LO_RIGHT.end.x - 90, LO_RIGHT.position.y + 11)
	_loadout_pips.add_theme_constant_override("separation", 6)
	_loadout_overlay.add_child(_loadout_pips)

	_loadout_slots_label = Label.new()
	_loadout_slots_label.position = LO_RIGHT.position + Vector2(16, 42)
	_loadout_slots_label.size = Vector2(LO_RIGHT.size.x - 32, 24)
	_loadout_slots_label.add_theme_font_size_override("font_size", 14)
	_loadout_slots_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_loadout_overlay.add_child(_loadout_slots_label)

	var scroll := ScrollContainer.new()
	scroll.position = LO_RIGHT.position + Vector2(16, 74)
	scroll.size = Vector2(LO_RIGHT.size.x - 32, LO_RIGHT.size.y - 90)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_loadout_overlay.add_child(scroll)
	_loadout_pool_container = VBoxContainer.new()
	_loadout_pool_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_pool_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_loadout_pool_container)

	# Footer.
	var hint := Label.new()
	hint.text = "Uses carry over between fights — spend them wisely.  Hover cards in battle to preview range."
	hint.position = Vector2(40, 650)
	hint.size = Vector2(900, 24)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	_loadout_overlay.add_child(hint)

	_loadout_start_btn = _make_primary_button("Start Battle  ▸", 1040, 648, 208, 48, _on_confirm_loadout)
	_loadout_overlay.add_child(_loadout_start_btn)

	add_child(_loadout_overlay)
	_loadout_overlay.visible = false

# A gold, high-emphasis variant of the action button for the primary CTA.
func _make_primary_button(text: String, x: int, y: int, w: int, h: int, cb: Callable) -> Button:
	var b := _make_button(text, x, y, w, h, cb)
	_style_primary(b, 18)
	return b

# Repaints an existing button as the gold primary CTA. Shared by the loadout's
# "Start Battle" and the in-combat "End Turn" so the main confirm action looks
# the same on both screens.
func _style_primary(b: Button, font_size: int = 16) -> void:
	b.add_theme_stylebox_override("normal", _panel_stylebox(Color(0.5, 0.36, 0.12), ACCENT, 2, 10))
	b.add_theme_stylebox_override("hover", _panel_stylebox(Color(0.64, 0.46, 0.16), Color(1, 0.92, 0.55), 2, 10))
	b.add_theme_stylebox_override("pressed", _panel_stylebox(Color(0.42, 0.3, 0.1), ACCENT, 2, 10))
	b.add_theme_color_override("font_color", Color(1, 0.97, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.92))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.42))
	b.add_theme_font_size_override("font_size", font_size)

func _open_loadout_screen() -> void:
	_loadout_field_label.text = _format_field_summary()
	_rebuild_enemy_chips()
	_populate_loadout_pool()
	_loadout_overlay.visible = true

func _format_field_summary() -> String:
	var enc: Array = []
	for e in _encounter:
		enc.append(str(e))
	var enc_str: String = ", ".join(enc) if not enc.is_empty() else "(none)"
	var size_name := "?"
	var dims := "?"
	if _battle_map != null:
		size_name = ["Small", "Medium", "Large"][clampi(_battle_map.size_class, 0, 2)]
		dims = "%dx%d" % [_battle_map.width, _battle_map.height]
	return "Encounter:  %s        Battlefield:  %s  (%s)" % [enc_str, size_name, dims]

func _rebuild_enemy_chips() -> void:
	for c in _loadout_enemy_container.get_children():
		c.queue_free()
	var any := false
	for u in _units:
		if u.is_player or not u.is_alive():
			continue
		any = true
		_loadout_enemy_container.add_child(_make_enemy_chip(u))
	if not any:
		_loadout_enemy_container.add_child(_picker_note("No enemies in this room."))

# Per-archetype accent for the enemy chip dot.
func _enemy_color(enemy_name: String) -> Color:
	match enemy_name:
		"rat": return Color(0.78, 0.74, 0.6)
		"snake": return Color(0.55, 0.85, 0.45)
		"orc": return Color(0.5, 0.78, 0.42)
		"troll": return Color(0.5, 0.62, 0.85)
		_: return Color(1.0, 0.5, 0.5)

func _enemy_intent_line(u) -> String:
	if u.intent_telegraph.is_empty():
		return "Intends:  waiting…"
	var t: Dictionary = u.intent_telegraph
	var val: int = int(t.get("value", 0))
	var tail: String = "  (%d)" % val if val > 0 else ""
	return "Intends:  %s %s%s" % [str(t.get("icon", "")), str(t.get("name", "")), tail]

# A framed enemy card: name, an HP bar, the key ranges, and the telegraphed
# next move.
func _make_enemy_chip(u) -> Panel:
	const IW := 300  # inner content width
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(316, 96)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override("panel",
		_panel_stylebox(Color(0.14, 0.09, 0.12, 0.96), Color(0.55, 0.3, 0.32, 0.9), 1, 8))

	var dot := ColorRect.new()
	dot.color = _enemy_color(String(u.unit_name))
	dot.position = Vector2(14, 13)
	dot.size = Vector2(14, 14)
	chip.add_child(dot)

	var name_l := Label.new()
	name_l.text = String(u.unit_name).capitalize()
	name_l.position = Vector2(36, 8)
	name_l.size = Vector2(IW - 22, 24)
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.add_theme_color_override("font_color", Color(1, 0.86, 0.84))
	chip.add_child(name_l)

	var frac: float = clampf(float(u.hp) / float(maxi(1, u.max_hp)), 0.0, 1.0)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.22, 0.2, 0.22)
	hp_bg.position = Vector2(14, 38)
	hp_bg.size = Vector2(IW, 9)
	chip.add_child(hp_bg)
	var hp_fg := ColorRect.new()
	hp_fg.color = Color(0.82, 0.32, 0.32)
	hp_fg.position = Vector2(14, 38)
	hp_fg.size = Vector2(IW * frac, 9)
	chip.add_child(hp_fg)

	var stat_l := Label.new()
	stat_l.text = "HP %d/%d     Move %d     Reach %d" % [
		u.hp, u.max_hp, u.move_range, _grid_view.enemy_attack_range(u)]
	stat_l.position = Vector2(14, 50)
	stat_l.size = Vector2(IW, 18)
	stat_l.add_theme_font_size_override("font_size", 11)
	stat_l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.86))
	chip.add_child(stat_l)

	var intent_l := Label.new()
	intent_l.text = _enemy_intent_line(u)
	intent_l.position = Vector2(14, 70)
	intent_l.size = Vector2(IW, 20)
	intent_l.add_theme_font_size_override("font_size", 11)
	intent_l.add_theme_color_override("font_color", Color(1.0, 0.72, 0.5))
	chip.add_child(intent_l)
	return chip

func _populate_loadout_pool() -> void:
	for child in _loadout_pool_container.get_children():
		child.queue_free()
	_refresh_slot_pips()
	var weapon_name: String = _selected_weapon.data.display_name if _selected_weapon != null else "default strike"
	_loadout_slots_label.text = "Weapon:  %s        Cards slotted:  %d / %d" % [
		weapon_name, _selected_cards.size(), CombatLoadout.MAX_SLOTS,
	]

	# Weapon section (single-select; replaces the basic Attack action).
	_loadout_pool_container.add_child(_make_loadout_header("WEAPON — replaces your Attack, usable every turn"))
	if _available_weapons.is_empty():
		_loadout_pool_container.add_child(_picker_note("No weapon cards in your deck — Attack will use the default strike."))
	else:
		var wgrid := _make_tile_grid()
		for wcard in _available_weapons:
			var equipped: bool = _selected_weapon == wcard
			wgrid.add_child(_make_loadout_tile(
				wcard, equipped, _on_toggle_loadout_weapon, false, false, "", "Weapon", "✓ EQUIPPED"))
		_loadout_pool_container.add_child(wgrid)

	# Card section (up to MAX_SLOTS, limited uses).
	_loadout_pool_container.add_child(_make_loadout_header("CARDS — up to %d; each play spends a use" % CombatLoadout.MAX_SLOTS))
	if _available_cards.is_empty():
		_loadout_pool_container.add_child(_picker_note("No cards available. You'll fight with Attack/Defend and spells."))
		return
	# Number duplicate copies so two of the same card read as distinct slots.
	var totals: Dictionary = {}
	for c in _available_cards:
		totals[c.data.id] = int(totals.get(c.data.id, 0)) + 1
	var seen_counts: Dictionary = {}
	var cgrid := _make_tile_grid()
	for card in _available_cards:
		var chosen: bool = _selected_cards.has(card)
		var disabled: bool = (not chosen) and _selected_cards.size() >= CombatLoadout.MAX_SLOTS
		var suffix: String = ""
		if int(totals.get(card.data.id, 1)) > 1:
			var k: int = int(seen_counts.get(card.data.id, 0)) + 1
			seen_counts[card.data.id] = k
			suffix = "  (%d)" % k
		cgrid.add_child(_make_loadout_tile(
			card, chosen, _on_toggle_loadout_card, true, disabled, suffix, "Card", "✓ SLOTTED"))
	_loadout_pool_container.add_child(cgrid)

func _make_tile_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	return grid

func _refresh_slot_pips() -> void:
	for c in _loadout_pips.get_children():
		c.queue_free()
	for i in CombatLoadout.MAX_SLOTS:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(18, 18)
		var filled: bool = i < _selected_cards.size()
		var fill: Color = ACCENT if filled else Color(0.16, 0.14, 0.2)
		var border: Color = ACCENT if filled else PANEL_BORDER
		pip.add_theme_stylebox_override("panel", _panel_stylebox(fill, border, 1, 5))
		_loadout_pips.add_child(pip)

# One selectable loadout tile (weapon or card). The whole tile is a Button so it
# styles its hover/pressed/selected states; the content labels sit on top with
# mouse input ignored so clicks reach the button. `inst` is a CardInstance.
func _make_loadout_tile(inst, chosen: bool, cb: Callable, show_uses: bool, disabled: bool, name_suffix: String, kind_label: String, chosen_tag: String) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(242, 138)
	tile.focus_mode = Control.FOCUS_NONE
	tile.disabled = disabled
	tile.pressed.connect(cb.bind(inst))
	var fill: Color = Color(0.2, 0.16, 0.12) if chosen else Color(0.15, 0.13, 0.2)
	var border: Color = ACCENT if chosen else PANEL_BORDER
	var bw: int = 2 if chosen else 1
	tile.add_theme_stylebox_override("normal", _panel_stylebox(fill, border, bw, 10))
	tile.add_theme_stylebox_override("hover", _panel_stylebox(fill.lightened(0.12), ACCENT, 2, 10))
	tile.add_theme_stylebox_override("pressed", _panel_stylebox(fill.darkened(0.12), ACCENT, 2, 10))
	tile.add_theme_stylebox_override("disabled", _panel_stylebox(Color(0.1, 0.09, 0.12), Color(0.22, 0.22, 0.26), 1, 10))

	var out_of_uses: bool = show_uses and GameState.card_uses_remaining(inst) <= 0 and not chosen
	var dim: bool = disabled or out_of_uses

	# Card art thumbnail down the left edge, with a subtle backing panel so dark
	# / transparent art reads cleanly. When a card has no art the text reclaims
	# the full tile width. `text_x` / `text_w` shift the labels accordingly.
	var text_x: int = 12
	var text_w: int = 218
	var art: Texture2D = inst.data.image
	if art != null:
		var art_bg := Panel.new()
		art_bg.position = Vector2(10, 10)
		art_bg.size = Vector2(70, 118)
		art_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_bg.add_theme_stylebox_override("panel",
			_panel_stylebox(Color(0.1, 0.09, 0.13), Color(border.r, border.g, border.b, 0.5), 1, 6))
		tile.add_child(art_bg)
		var art_rect := TextureRect.new()
		art_rect.texture = art
		art_rect.position = Vector2(15, 15)
		art_rect.size = Vector2(60, 108)
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if dim:
			art_rect.modulate = Color(0.6, 0.6, 0.6)
		tile.add_child(art_rect)
		text_x = 88
		text_w = 142

	var name_l := Label.new()
	name_l.text = inst.get_display_name() + name_suffix
	name_l.position = Vector2(text_x, 10)
	name_l.size = Vector2(text_w, 22)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color",
		Color(0.55, 0.55, 0.6) if dim else (ACCENT if chosen else Color(1, 0.93, 0.82)))
	tile.add_child(name_l)

	var meta_text: String = kind_label
	if show_uses:
		meta_text += "    uses %d/%d" % [GameState.card_uses_remaining(inst), GameState.card_uses_max(inst)]
	var meta_l := Label.new()
	meta_l.text = meta_text
	meta_l.position = Vector2(text_x, 34)
	meta_l.size = Vector2(text_w, 18)
	meta_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_l.add_theme_font_size_override("font_size", 11)
	meta_l.add_theme_color_override("font_color", Color(0.62, 0.64, 0.74))
	tile.add_child(meta_l)

	var desc_l := Label.new()
	desc_l.text = _card_desc(inst.data)
	desc_l.position = Vector2(text_x, 54)
	desc_l.size = Vector2(text_w, 56)
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_l.add_theme_font_size_override("font_size", 11)
	desc_l.add_theme_color_override("font_color",
		Color(0.5, 0.5, 0.55) if dim else Color(0.82, 0.82, 0.88))
	tile.add_child(desc_l)

	if chosen:
		var tag := Label.new()
		tag.text = chosen_tag
		tag.position = Vector2(12, 114)
		tag.size = Vector2(218, 18)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", ACCENT)
		tile.add_child(tag)
	return tile

func _make_loadout_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", ACCENT)
	return l

func _on_toggle_loadout_card(card) -> void:
	if _selected_cards.has(card):
		_selected_cards.erase(card)
	elif _selected_cards.size() < CombatLoadout.MAX_SLOTS:
		_selected_cards.append(card)
	_populate_loadout_pool()

func _on_toggle_loadout_weapon(card) -> void:
	# Single weapon slot: toggling a new weapon replaces any previous pick.
	_selected_weapon = null if _selected_weapon == card else card
	_populate_loadout_pool()

func _on_confirm_loadout() -> void:
	# Unplayable -> requires_equipped (Strategy): block starting until the
	# required number of Unplayable cards are slotted (only when the player
	# actually owns any). Shown on the loadout screen, not the in-combat label.
	var req_err: String = _loadout_requirement_error()
	if req_err != "":
		_loadout_slots_label.text = req_err
		return
	_loadout.cards = _selected_cards.duplicate()
	_loadout.weapon = _selected_weapon
	_weapon_card = _selected_weapon
	_loadout_overlay.visible = false
	_info_label.text = _format_info(_room_data, _encounter)
	_status_label.text = "Waiting for first turn..."
	_fire_item_triggers("combat_started")
	StrategyCombatSession.begin_battle()

# Unplayable -> requires_equipped: if the player owns any card carrying the verb,
# the loadout must slot at least the required count of them. "" = requirement met
# (or none owned). Detected via AddonSystem so it stays data-driven.
func _loadout_requirement_error() -> String:
	var required: int = 0
	for card in _available_cards:
		required = maxi(required, AddonSystem.requires_equipped(card.data, Stats.Mode.STRATEGY))
	if required <= 0:
		return ""
	var slotted: int = 0
	for card in _selected_cards:
		if AddonSystem.requires_equipped(card.data, Stats.Mode.STRATEGY) > 0:
			slotted += 1
	if slotted >= required:
		return ""
	return "Must slot at least %d Unplayable card%s before starting." % [
		required, "s" if required > 1 else "",
	]

# ----------------------------------------------------------------------
# Turn flow
# ----------------------------------------------------------------------

func _on_unit_turn_started(unit) -> void:
	_grid_view.set_active_unit(unit, unit.move_range)
	_refresh_initiative()
	# Fear: too afraid to fight — spend the whole turn fleeing as far from all
	# opposing units as possible, then end the turn. Same rule for player and
	# enemy units (the one symmetric Fear behavior).
	if unit.get_status(&"fear") > 0:
		_set_player_buttons_enabled(false)
		_grid_view.enter_idle()
		_fear_flee(unit)
		_status_label.text = "%s is gripped by Fear and flees!" % str(unit.unit_name).capitalize()
		_fear_turn_timer.start()
		return
	if unit.is_player:
		_player_turn_count += 1
		# Energy (empower charge): unless it banks across turns, leftover charge
		# from last turn is lost at the start of this one — the energy-carryover
		# item (Ice Cream) overrides that, mirroring the deckbuilder.
		if not _tr.energy_banks_across_turns and not GameState.has_energy_carryover_item():
			_energy_charge = 0
		_fire_item_turn_triggers(unit, _player_turn_count)
		# Recurring turn heartbeat through the shared item path (EffectSystem):
		# resets the per-turn attack window and procs Happy Flower's "every N
		# turns" counter, which the custom turn-trigger path above doesn't cover.
		_fire_item_triggers("turn_tick")
		_action_used = false
		_move_used = false
		_move_remaining = unit.move_range
		_card_plays_remaining = 1
		_ability_used_this_turn = false
		_ethereal_used_this_turn = false
		_free_ability_card = null
		# Innate -> free_play (Strategy): on the first player turn, one innate
		# slotted ability is free to play (reuses the Mummified-Hand free slot).
		if _player_turn_count == 1 and _loadout != null:
			for c in _loadout.cards:
				if AddonSystem.free_play_count(c.data, Stats.Mode.STRATEGY) > 0 \
						and GameState.card_uses_remaining(c) > 0:
					_free_ability_card = c
					break
		_pending_kind = Pending.NONE
		_pending_card = null
		_pending_spell = null
		var charge_str: String = "  |  Charge %d" % _energy_charge if _energy_charge > 0 else ""
		_status_label.text = "Your turn. Move %d  |  Plays %d  |  Mana %d/%d%s" % [
			_move_remaining, _card_plays_remaining, unit.mana, unit.max_mana, charge_str,
		]
		_set_player_buttons_enabled(true)
		_refresh_button_states()
		_begin_turn_curse(unit)
	else:
		_status_label.text = "%s acts..." % unit.unit_name
		_set_player_buttons_enabled(false)
		_enemy_turn_timer.start()

func _on_unit_turn_ended(unit) -> void:
	# Ice Cream: a player turn that ends without an ability play banks empower
	# charge. It accumulates with no cap and persists indefinitely — skip any
	# number of turns and bank that many charges — until a card play spends the
	# whole charge at once. Strategy has no per-turn energy pool, so this is its
	# analogue of the deckbuilder's leftover-energy carry-over. The carryover
	# item also forces _energy_charge to survive turn starts (see
	# _on_unit_turn_started), so banked charge is never silently wiped.
	if unit != null and unit.is_player and not _ability_used_this_turn \
			and GameState.has_energy_carryover_item():
		_energy_charge += _tr.empower_per_skipped_turn
		_status_label.text = "Ice Cream: banked an empower charge (now %d)." % _energy_charge
	# Damage-over-time bite (Bleed, Leeches) at the end of the unit's own turn,
	# BEFORE decay so the bite uses the current stack count (then Bleed ramps
	# via decay's grow pass). Mirrors the deckbuilder/action contract.
	if unit != null:
		Stats.tick_actor_statuses(unit, self)
		if unit.is_alive():
			Stats.decay_actor_statuses(unit)
	# The chosen curse's end-of-turn effect lands here — AFTER decay — so a status
	# it grants (Doubt -> Weak) survives into the next turn, and the brick's
	# all-stats-down debuff is lifted now that the turn is over.
	if unit != null and unit.is_player:
		_end_turn_curse(unit)
		# Ethereal -> deactivate_if_idle: a player turn that ends without playing
		# any Ethereal ability locks every Ethereal ability for the rest of combat.
		if not _ethereal_deactivated and not _ethereal_used_this_turn \
				and _has_ethereal_ability():
			_ethereal_deactivated = true
			_status_label.text = "Ethereal abilities deactivated — none was used this turn."
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_check_battle_end_after_effect()

# Applies turn-based item effects to the player unit at the start of its
# turn. Strategy uses the BattleUnit model rather than the deckbuilder's
# CombatActor/EffectSystem, so the common turn-based effect types (block /
# status / heal) are applied directly here. Gated on if_turn like the
# other modes (Horn Cleat: +14 Block on the 2nd turn).
func _fire_item_turn_triggers(unit, turn_number: int) -> void:
	if unit == null:
		return
	var sources: Array = []
	sources.append_array(GameState.inventory)
	if GameState.equipped_weapon != null:
		sources.append(GameState.equipped_weapon)
	for item in sources:
		if not (item is ItemData):
			continue
		for trig in item.triggers:
			if String(trig.get("on", "")) != "turn_started":
				continue
			var turn_gate: int = int(trig.get("if_turn", 0))
			if turn_gate > 0 and turn_number != turn_gate:
				continue
			for effect in trig.get("effects", []):
				_apply_turn_effect_to_unit(unit, effect)
	_grid_view.notify_units_changed()

func _apply_turn_effect_to_unit(unit, effect: Dictionary) -> void:
	match String(effect.get("type", "")):
		"block":
			unit.block += int(effect.get("value", 0))
		"status":
			Stats.apply_status_to(unit, StringName(effect.get("status", "")), int(effect.get("stacks", 1)))
		"heal", "gain_hp":
			var before: int = unit.hp
			unit.hp = mini(unit.max_hp, unit.hp + int(effect.get("value", 0)))
			_float_number(unit, unit.hp - before, FloatingNumbers.HEAL_COLOR)

# ----------------------------------------------------------------------
# Curse-of-the-turn
# ----------------------------------------------------------------------

# Start of the player's turn: choose one random owned curse, telegraph it, and
# apply its during-turn effect (bricks -> all-stats-down). eot / Pain effects
# resolve later (turn end / per action).
func _begin_turn_curse(unit) -> void:
	_clear_turn_stat_debuff()
	_turn_actions = 0
	_turn_curse = _pick_random_owned_curse()
	if _turn_curse == null:
		return
	Notifications.notify("Curse this turn: %s" % _turn_curse.display_name,
		Color(0.85, 0.6, 0.85))
	GameLog.add("Curse active this turn: %s." % _turn_curse.display_name,
		Color(0.85, 0.6, 0.85))
	if _curse_strategy_kind(_turn_curse) == "brick":
		_apply_turn_stat_debuff()

# End of the player's turn: an eot curse fires its effect (status / dmg / Regret).
# Pain already bit per action; the brick debuff is lifted in _begin_turn_curse /
# here. Runs AFTER status decay so a granted status persists to the next turn.
func _end_turn_curse(_unit) -> void:
	if _turn_curse != null and _curse_strategy_kind(_turn_curse) == "eot":
		for trig in _turn_curse.triggers:
			if String(trig.get("on", "")) != "eot":
				continue
			for e in trig.get("effects", []):
				if e is Dictionary:
					_apply_strategy_curse_effect(e, _turn_actions)
	_clear_turn_stat_debuff()
	_turn_curse = null

# Called from each committed player action (move / attack / spell / card). Counts
# the action for Regret and, when Pain is the active curse, bites 1 HP live.
func _register_player_action() -> void:
	if _turn_curse == null:
		return
	_turn_actions += 1
	if _curse_strategy_kind(_turn_curse) == "pain":
		var p = get_player_unit()
		if p != null:
			apply_dot(p, 1, "Curse")

func _pick_random_owned_curse() -> CardData:
	var pool: Array = []
	for c in GameState.deck:
		var cd: CardData = c.data if c is CardInstance else (c as CardData)
		if cd != null and cd.type == CardData.CardType.CURSE:
			pool.append(cd)
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]

# Applies one translated curse effect to the player unit. status -> add_status;
# dmg/lose_hp -> apply_dot. per:card_in_hand is translated to per action taken
# this turn (Regret).
func _apply_strategy_curse_effect(effect: Dictionary, actions: int) -> void:
	var p = get_player_unit()
	if p == null:
		return
	match String(effect.get("type", "")):
		"status":
			Stats.apply_status_to(p, StringName(effect.get("status", "")), int(effect.get("stacks", 1)))
		"dmg":
			var dv := int(effect.get("value", 0))
			if dv > 0:
				apply_dot(p, dv, "Curse")
		"lose_hp":
			var lv := int(effect.get("value", 1))
			if String(effect.get("per", "")) == "card_in_hand":
				lv *= maxi(0, actions)
			if lv > 0:
				apply_dot(p, lv, "Curse")

# Strategy behaviour of a curse: "eot" (status/dmg/Regret at turn end), "pain"
# (per action), or "brick" (no player-affecting trigger -> all-stats-down).
func _curse_strategy_kind(cd: CardData) -> String:
	var has_eot := false
	var has_pain := false
	for trig in cd.triggers:
		if not _curse_trigger_has_player_effect(trig):
			continue
		match String(trig.get("on", "")):
			"eot": has_eot = true
			"on_play_other": has_pain = true
	if has_eot:
		return "eot"
	if has_pain:
		return "pain"
	return "brick"

func _curse_trigger_has_player_effect(trig: Dictionary) -> bool:
	for e in trig.get("effects", []):
		if e is Dictionary and String(e.get("type", "")) in ["status", "dmg", "lose_hp"]:
			return true
	return false

func _apply_turn_stat_debuff() -> void:
	if _turn_stat_debuff:
		return
	for s in _CURSE_STAT_DOWN:
		GameState.add_temp_stat(s, -1)
	_turn_stat_debuff = true
	GameLog.add("Curse: all stats down this turn.", Color(0.85, 0.6, 0.85))

func _clear_turn_stat_debuff() -> void:
	if not _turn_stat_debuff:
		return
	for s in _CURSE_STAT_DOWN:
		GameState.add_temp_stat(s, 1)
	_turn_stat_debuff = false

# Fear flee: move the unit to the reachable tile that maximizes the summed
# Manhattan distance to all living opposing units, then shed 1 Fear (strategy's
# turn-end decay, so N stacks == N turns of forced retreat). Only moves when a
# strictly-farther tile exists, so a cornered/surrounded unit just holds. Shared
# by player and enemy units.
func _fear_flee(unit) -> void:
	var foes: Array = []
	for u in _units:
		if u != null and u.is_alive() and u.is_player != unit.is_player:
			foes.append(u)
	if not foes.is_empty():
		var reachable: Dictionary = _grid_view._reachable_from(unit, unit.move_range)
		var best_tile: Vector2i = unit.position
		var best_score: int = _fear_flee_score(unit.position, foes)
		var best_steps: int = 0
		for tile in reachable.keys():
			var score: int = _fear_flee_score(tile, foes)
			var steps: int = int(reachable[tile])
			# Prefer the farthest tile; on ties take the one that moves the least.
			if score > best_score or (score == best_score and steps < best_steps):
				best_score = score
				best_tile = tile
				best_steps = steps
		if best_tile != unit.position:
			unit.position = best_tile
			_grid_view.notify_units_changed()
	if unit.get_status(&"fear") > 0:
		unit.add_status(&"fear", -1)

# Sum of Manhattan distances from a tile to every living opposing unit.
func _fear_flee_score(tile: Vector2i, foes: Array) -> int:
	var total: int = 0
	for f in foes:
		total += absi(tile.x - f.position.x) + absi(tile.y - f.position.y)
	return total

# End a feared unit's turn after the flee beat — no AI, no player control.
func _auto_end_feared_turn() -> void:
	if _turn_manager == null or _turn_manager.current_unit == null:
		return
	_turn_manager.end_current_turn()

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
	_fire_item_triggers("combat_ended")

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
	var with_what: String = _weapon_card.data.display_name if _weapon_card != null else "your strike"
	_status_label.text = "Click an adjacent enemy to attack with %s." % with_what

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

# True if any slotted ability is Ethereal (deactivate_if_idle) — gates the
# end-of-turn deactivation so it no-ops when the player has no Ethereal cards.
func _has_ethereal_ability() -> bool:
	if _loadout == null:
		return false
	for c in _loadout.cards:
		if AddonSystem.deactivates_if_idle(c.data, Stats.Mode.STRATEGY):
			return true
	return false

# True if `card` is an Ethereal ability that has been locked out for the combat.
func _is_ethereal_locked(card) -> bool:
	return _ethereal_deactivated \
		and AddonSystem.deactivates_if_idle(card.data, Stats.Mode.STRATEGY)

func _populate_ability_picker() -> void:
	for child in _ability_list_container.get_children():
		child.queue_free()
	if _loadout == null or _loadout.cards.is_empty():
		_ability_list_container.add_child(_picker_note(
			"No cards slotted. Pick a loadout before combat to bring cards."
		))
		return
	var totals: Dictionary = {}
	for c in _loadout.cards:
		totals[c.data.id] = int(totals.get(c.data.id, 0)) + 1
	var seen_counts: Dictionary = {}
	for card in _loadout.cards:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		var uses: int = GameState.card_uses_remaining(card)
		var cap: int = GameState.card_uses_max(card)
		var is_free: bool = card == _free_ability_card
		var is_unplayable: bool = card.data != null and card.data.unplayable
		var castable: bool = uses > 0 and (_card_plays_remaining > 0 or is_free) \
			and not _is_ethereal_locked(card) and not is_unplayable
		var free_tag: String = "  [FREE]" if is_free else ""
		if is_unplayable:
			free_tag += "  [UNPLAYABLE]"
		var copy_tag: String = ""
		if int(totals.get(card.data.id, 1)) > 1:
			var k: int = int(seen_counts.get(card.data.id, 0)) + 1
			seen_counts[card.data.id] = k
			copy_tag = "  (copy %d)" % k
		lbl.text = "%s%s%s  (uses %d/%d)  —  %s" % [card.get_display_name(), copy_tag, free_tag, uses, cap, _card_desc(card.data)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(196, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		if uses <= 0:
			lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		# Hovering the row previews movement + this card's targets on the board.
		var hits_enemy: bool = CombatLoadout.wants_enemy_target(card.data)
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.mouse_entered.connect(_on_hover_card_preview.bind(hits_enemy))
		lbl.mouse_exited.connect(_on_hover_preview_end)
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Play"
		btn.disabled = not castable
		btn.pressed.connect(_on_pick_ability.bind(card))
		row.add_child(btn)
		_ability_list_container.add_child(row)

func _on_pick_ability(card) -> void:
	_ability_dialog.visible = false
	# Re-check: the picker may have been left open across state changes. A
	# Mummified-Hand free ability is playable even with no plays remaining.
	var is_free: bool = card == _free_ability_card
	if card.data != null and card.data.unplayable:
		_status_label.text = "%s is unplayable." % card.get_display_name()
		return
	if _is_ethereal_locked(card):
		_status_label.text = "%s is Ethereal and has been deactivated." % card.data.display_name
		return
	if GameState.card_uses_remaining(card) <= 0 or (_card_plays_remaining <= 0 and not is_free):
		_status_label.text = "%s can't be played right now." % card.data.display_name
		return
	_pending_kind = Pending.ABILITY
	_pending_card = card
	if CombatLoadout.wants_enemy_target(card.data):
		_grid_view.enter_unit_target_mode(BattleGridView.TargetFilter.ENEMY)
		_status_label.text = "Playing %s — click an enemy (right-click to cancel)." % card.data.display_name
	else:
		_resolve_ability_against(null)

func _resolve_ability_against(target) -> void:
	if _pending_card == null:
		return
	var u = _turn_manager.current_unit
	var card = _pending_card
	# Spend one of this instance's uses; bail if somehow empty.
	if not GameState.spend_card_use_inst(card):
		_status_label.text = "%s is out of uses." % card.data.display_name
		_pending_kind = Pending.NONE
		_pending_card = null
		_grid_view.enter_idle()
		return
	# Mummified Hand: if this is the ability the item made free, it costs no
	# per-turn play (the use was still spent above); otherwise spend a play.
	if card == _free_ability_card:
		_free_ability_card = null
	else:
		_card_plays_remaining -= 1
	_ability_used_this_turn = true
	# Ethereal -> deactivate_if_idle: playing an Ethereal ability keeps the whole
	# set alive for the turn.
	if AddonSystem.deactivates_if_idle(card.data, Stats.Mode.STRATEGY):
		_ethereal_used_this_turn = true
	_register_player_action()
	# Spend any banked energy charge to empower this card, then clear it.
	var empower: int = _energy_charge
	_energy_charge = 0
	# card_played fires BEFORE the ability's effects resolve (the documented
	# contract, and what the other two modes do) so attack counters / Pen Nib's
	# double-damage window arm in time for this attack. The "Played …" status
	# text is set first so a card_played item that posts its own message
	# (Mummified Hand) still wins.
	var empower_str: String = "  (empowered +%d)" % empower if empower > 0 else ""
	_status_label.text = "Played %s%s. (%d uses left, %d plays left)" % [
		card.data.display_name, empower_str, GameState.card_uses_remaining(card), _card_plays_remaining,
	]
	_fire_item_triggers("card_played", {"card": card.data})
	# Vorpal rides the physical card instance; recover its roll and pass it down.
	var vorpal: Dictionary = {}
	card.roll_vorpal_if_needed()
	if card.vorpal_type >= 0 and card.vorpal_weight > 0:
		vorpal = {"type": card.vorpal_type, "weight": card.vorpal_weight}
	_apply_card_or_spell_effects(_effective_card_effects(card.data), u, target, card.data, empower, vorpal)
	# Destroy: remove the played card from the run deck permanently after it resolves.
	if card.data != null and card.data.destroy:
		GameState.destroy_card_instance(card)
		_status_label.text = "%s is Destroyed — removed from your deck." % card.data.display_name
	_pending_kind = Pending.NONE
	_pending_card = null
	_grid_view.enter_idle()
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
			entry.data.display_name, entry.data.cost, _card_desc(entry.data),
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(196, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		# Hovering the row previews movement + this spell's targets on the board.
		var hits_enemy: bool = entry.wants_target and entry.data.target_kind != "friendly"
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.mouse_entered.connect(_on_hover_card_preview.bind(hits_enemy))
		lbl.mouse_exited.connect(_on_hover_preview_end)
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
	_apply_card_or_spell_effects(_effective_card_effects(entry.data), u, target, entry.data)
	_register_player_action()
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
	_register_player_action()
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
	if _weapon_card != null:
		# Equipped weapon replaces the basic strike: its effects resolve once
		# against the target. Unlimited uses, but once per turn (it's the
		# Attack action, gated by _action_used). Energy empower applies to
		# slotted cards only, not the weapon, so pass empower 0.
		_apply_card_or_spell_effects(_effective_card_effects(_weapon_card.data), attacker, target, _weapon_card.data)
		_status_label.text = "You attack %s with %s." % [target.unit_name, _weapon_card.data.display_name]
	else:
		var dmg := DEFAULT_BASIC_ATTACK
		if attacker.basic_attack_def.has("damage"):
			dmg = int(attacker.basic_attack_def["damage"])
		_apply_damage(attacker, target, dmg)
		_status_label.text = "You strike %s for %d." % [target.unit_name, dmg]
	_action_used = true
	_register_player_action()
	_grid_view.enter_idle()
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_button_states()
	_check_battle_end_after_effect()

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

# Status application entry point (called by EffectSystem._h_status and the shared
# contact reactions). Shared apply (guard + Persistence + add) lives in
# Stats.apply_status_to so all three modes agree; strategy's reaction is a grid
# refresh so the unit's status badges update. Skip it when nothing landed.
func apply_status(target, status: StringName, stacks: int, source = null) -> void:
	if Stats.apply_status_to(target, status, stacks, source) > 0:
		_grid_view.notify_units_changed()

func _apply_card_or_spell_effects(effects: Array, source, target, card = null, empower: int = 0, vorpal: Dictionary = {}) -> void:
	# Replay addon: a card with Replay X resolves its full effect list X extra
	# times. `card` is null for enemy AI moves (CardMods.replay_count(null) is
	# 0), so only player cards / abilities / spells / weapon attacks replay.
	# Duplicator grants Replay 1 to weapon attack cards — the strategy weapon
	# attack (above) routes through here, so it picks the extra play up too.
	# `vorpal` ({type, weight}) carries the played card instance's Vorpal roll,
	# stamped onto each effect so _apply_damage can apply the per-target bonus.
	var plays: int = 1 + CardMods.replay_count(card)
	for _play in plays:
		for raw_effect in effects:
			var effect: Dictionary = Stats.apply_addons_to_effect(raw_effect, card)
			if not vorpal.is_empty():
				effect = effect.duplicate()
				effect["vorpal_type"] = int(vorpal["type"])
				effect["vorpal_weight"] = int(vorpal["weight"])
			if empower > 0:
				effect = _tr.apply_empower(effect, empower)
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

# Pops a floating number over a unit (red for HP lost, green for HP healed),
# parented to the grid view at the unit's tile centre (units carry a Vector2i
# grid position).
func _float_number(target, amount: int, color: Color = FloatingNumbers.DAMAGE_COLOR) -> void:
	if amount <= 0 or _grid_view == null or not _grid_view.is_inside_tree():
		return
	if target == null or not ("position" in target):
		return
	var ts: int = _grid_view.tile_size
	var center := Vector2(
		target.position.x * ts + ts * 0.5,
		target.position.y * ts + ts * 0.5)
	FloatingNumbers.spawn(_grid_view, center, amount, color)

# Floating text ("MISS", etc.) over a unit, reusing the tile-centre math above.
func _float_text(target, text: String, color: Color = FloatingNumbers.DAMAGE_COLOR) -> void:
	if _grid_view == null or not _grid_view.is_inside_tree():
		return
	if target == null or not ("position" in target):
		return
	var ts: int = _grid_view.tile_size
	var center := Vector2(
		target.position.x * ts + ts * 0.5,
		target.position.y * ts + ts * 0.5)
	FloatingNumbers.spawn_text(_grid_view, center, text, color)

func gain_block(target, value: int) -> void:
	if target == null:
		return
	# Shared block math: Defense status adds, Frail cuts gained block 25%
	# (Stats.resolve_block) — same rule as deckbuilder/action so Defense
	# works in every mode.
	target.block = maxi(0, target.block) + Stats.resolve_block(int(value), target, true)

func heal(target, value: int) -> void:
	if target == null:
		return
	var before: int = target.hp
	target.hp = mini(target.max_hp, target.hp + int(value))
	_float_number(target, target.hp - before, FloatingNumbers.HEAL_COLOR)

func gain_energy(n: int) -> void:
	# Energy is empower charge: it banks (across turns within the combat)
	# until the next card play consumes ALL of it as a bonus (+dmg/+block/
	# +status stacks). It grants no extra plays.
	if n <= 0:
		return
	_energy_charge += n
	_status_label.text = "Energy +%d (charge %d). Empowers your next card." % [n, _energy_charge]
	_refresh_button_states()

func lose_energy(n: int) -> void:
	# Symmetric to gain_energy: drains banked empower charge, floored at 0.
	if n <= 0:
		return
	_energy_charge = maxi(0, _energy_charge - n)
	_refresh_button_states()

func draw_cards(n: int) -> void:
	# Strategy mode has no hand to draw into. Per the translator, each "draw"
	# event RECHARGES _tr.draw_recharges_per_point use(s) on a slotted card —
	# restoring the card with the fewest current uses first so it lands
	# meaningfully. Stops if every slotted card is already at max.
	if _loadout == null or n <= 0:
		return
	var restores: int = n * _tr.draw_recharges_per_point
	var restored_any: bool = false
	for _i in range(restores):
		var best_card = null
		var best_uses: int = 1 << 30
		for card in _loadout.cards:
			var uses: int = GameState.card_uses_remaining(card)
			if uses < GameState.card_uses_max(card) and uses < best_uses:
				best_uses = uses
				best_card = card
		if best_card == null:
			break
		if GameState.recharge_card_use_inst(best_card, 1) > 0:
			restored_any = true
	if restored_any:
		_status_label.text = "Recharged a card use."
		_refresh_button_states()

func discard_cards(n: int, _source_card = null, _random: bool = false) -> void:
	# No hand to discard. Strategy treats discard as a tempo cost: it spends
	# _tr.discard_plays_per_point card play(s) this turn, floored at 0.
	if n <= 0:
		return
	_card_plays_remaining = maxi(0, _card_plays_remaining - n * _tr.discard_plays_per_point)
	_refresh_button_states()

# ----------------------------------------------------------------------
# Damage / death helpers
# ----------------------------------------------------------------------

func _apply_damage(source, target, raw_dmg: int, effect: Dictionary = {}) -> void:
	if target == null or raw_dmg <= 0:
		return
	# A player melee/ranged swing is an "attack" for streak items (Dead Eye):
	# fold the active streak bonus in before resolving, same as the other modes.
	var dmg_type: String = String(effect.get("damage_type", "melee"))
	var is_player_attack: bool = (dmg_type == "melee" or dmg_type == "ranged") \
		and source != null and "is_player" in source and source.is_player \
		and not target.is_player
	if is_player_attack:
		raw_dmg += GameState.streak_attack_bonus(target)
	# Vorpal: flat bonus when this swing's bound mode (Strategy) + the target's
	# weight match the weapon's roll. Pre-resolve so Power/Vulnerable layer on top.
	raw_dmg += Stats.vorpal_damage_bonus(effect, target, Stats.Mode.STRATEGY)
	# Canonical damage math in Stats.resolve_damage (Power/Weak, Vulnerable,
	# Blind, Dodge, block soak) so strategy matches deckbuilder/action. The
	# death / Infuse / loot tail below stays strategy-specific.
	var was_alive: bool = target.is_alive()
	var res := Stats.resolve_damage(source, target, raw_dmg, effect, Stats.Mode.STRATEGY)
	if res.missed:
		var who: String = "You" if source.is_player else source.display_name
		GameLog.add("%s swings blind and misses!" % who, Color(0.85, 0.85, 0.55))
		_float_text(target, "MISS", FloatingNumbers.MISS_COLOR)
		# A whiff breaks Dead Eye's streak.
		if is_player_attack:
			TriggerBus.emit_signal("attack_missed",
				{"source": source, "target": target, "scene": self})
			_fire_item_triggers("attack_missed", {"target": target})
		return
	if res.dodged:
		return
	target.hp = maxi(0, target.hp - int(res.hp_loss))
	_float_number(target, int(res.hp_loss))
	# Lifesteal: the attacker heals for the unblocked HP it just dealt. Self-hits
	# and reflected reactions (no_reaction) never lifesteal.
	if bool(effect.get("lifesteal", false)) and source != null and source != target \
			and not bool(effect.get("no_reaction", false)) and int(res.hp_loss) > 0:
		heal(source, int(res.hp_loss))
	# Item reactions to the player taking damage (Prayer Card, Prayer Beads).
	if target.is_player and int(res.hp_loss) > 0:
		_fire_item_triggers("damage_taken", {"target": target})
	# The attack connected (block counts). Dead Eye's streak grows here, skipped
	# on a killing blow (the streak against a corpse is never read).
	if is_player_attack and target.is_alive():
		TriggerBus.emit_signal("attack_landed",
			{"source": source, "target": target, "scene": self})
		_fire_item_triggers("attack_landed", {"target": target})
	if was_alive and not target.is_alive() and not target.is_player:
		# Infuse: strategy mirrors deckbuilder — every killing blow with
		# infuse > 0 grants the player Max HP equal to the stack count.
		var infuse_stacks: int = int(effect.get("infuse", 0))
		if infuse_stacks > 0 and source != null and "is_player" in source and source.is_player:
			GameState.set_max_hp(GameState.max_hp + infuse_stacks, false)
		# Item procs on a kill (Charm of the Vampire, …).
		_fire_item_triggers("enemy_killed")
		# Phase 8: enemy death -> roll loot onto the tile it fell on.
		_drop_enemy_loot(target)

# Raw HP loss from a damage-over-time status (Bleed, Leeches). Bypasses block /
# Weak / Vulnerable and never re-triggers reactions — matches the
# deckbuilder/action DoT contract. Called by Stats.tick_actor_statuses at each
# unit's turn end (see _on_unit_turn_ended).
func apply_dot(target, amount: int, _source_name: String) -> void:
	if target == null or not target.is_alive() or amount <= 0:
		return
	target.hp = maxi(0, target.hp - amount)
	_float_number(target, amount)
	if not target.is_alive() and not target.is_player:
		_fire_item_triggers("enemy_killed")
		_drop_enemy_loot(target)

# Leeches drain -> player heal (Jar of Leeches). Called by
# Stats.tick_actor_statuses when a leeched enemy bleeds HP into the player.
func leech_to_player(amount: int) -> void:
	if amount <= 0:
		return
	var p = get_player_unit()
	if p != null:
		heal(p, amount)

# Mummified Hand (strategy analogue of "a card becomes free"): playing a Power
# ability marks a random OTHER slotted ability free to play this turn — it
# costs no per-turn play, though it still spends one of its uses. `played_card`
# is the power that triggered this and is excluded from the pick.
func make_random_hand_card_free(played_card = null) -> void:
	if _loadout == null:
		return
	# `played_card` is the CardData that triggered this; exclude slotted copies
	# of it from the free pick (with duplicate copies, all copies are excluded —
	# an acceptable edge for a rare item interaction).
	var played_id: String = String(played_card.id) if played_card != null and ("id" in played_card) else ""
	var candidates: Array = []
	for c in _loadout.cards:
		if c != null and c.data != null and String(c.data.id) != played_id:
			candidates.append(c)
	if candidates.is_empty():
		return
	var pick = candidates[randi() % candidates.size()]
	_free_ability_card = pick
	_status_label.text = "Mummified Hand: %s is free to play this turn!" % pick.data.display_name

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

# --- Items: the active-item action button + picker -------------------------

func _on_item_button() -> void:
	if not _is_player_turn():
		return
	_clear_pending()
	_grid_view.enter_idle()
	_populate_item_picker()
	_item_dialog.visible = true
	_ability_dialog.visible = false
	_spell_dialog.visible = false

func _populate_item_picker() -> void:
	for child in _item_list_container.get_children():
		child.queue_free()
	var any: bool = false
	for item in GameState.inventory:
		if not (item is ItemData):
			continue
		if not (item.is_charged() or item.kind == ItemData.ItemKind.USABLE):
			continue
		any = true
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var lbl := Label.new()
		var status: String = ""
		if item.is_charged():
			status = "  (%d/%d)" % [item.current_charge, item.max_charge()]
		lbl.text = "%s%s  —  %s" % [item.display_name, status, item.description]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.custom_minimum_size = Vector2(196, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		if not GameState.can_fire_item(item):
			lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "Use"
		btn.disabled = not GameState.can_fire_item(item)
		btn.pressed.connect(_on_pick_item.bind(item))
		row.add_child(btn)
		_item_list_container.add_child(row)
	if not any:
		_item_list_container.add_child(_picker_note(
			"No active items. Charged items and pills you collect show up here."
		))

func _on_pick_item(item) -> void:
	if GameState.use_item(item):
		_status_label.text = "Used %s." % item.display_name
		_populate_item_picker()
		_refresh_button_states()
	else:
		_status_label.text = "%s isn't ready yet." % item.display_name

func _close_item_dialog() -> void:
	_item_dialog.visible = false

func _has_usable_item() -> bool:
	for item in GameState.inventory:
		if item is ItemData and GameState.can_fire_item(item):
			return true
	return false

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
	_btn_item.disabled = not enabled
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
	_btn_ability.disabled = (_card_plays_remaining <= 0 and _free_ability_card == null) \
		or not _has_playable_card()
	_btn_spell.disabled = _spellbook == null or _spellbook.spells.is_empty()
	_btn_dash.disabled = not u.dash_available
	# Items don't cost the turn's move/action budget — live whenever one is ready.
	_btn_item.disabled = not _has_usable_item()

func _has_playable_card() -> bool:
	if _loadout == null:
		return false
	for card in _loadout.cards:
		if GameState.card_uses_remaining(card) > 0:
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
		lines.append("%s %-8s hp %d/%d  mv %d  ctr %d%s%s%s" % [
			marker, u.unit_name, u.hp, u.max_hp, u.move_range,
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

func _format_info(_room_data, encounter: Array) -> String:
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
		"Encounter: %s   |   Field: %s (%s)   |   Cards slotted: %d/%d   |   Spellbook: %d"
	) % [enc_str, size_name, dims, card_count, CombatLoadout.MAX_SLOTS, spell_count]

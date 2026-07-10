extends CanvasLayer

# The tactical battle UI — now a GRID DECKBUILDER.
#
# Combat starts immediately (no pre-combat loadout). The player's whole run deck
# shuffles into a draw pile; each turn refreshes energy and draws a fresh hand,
# exactly like the deckbuilder mode. The grid adds positioning on top:
#
# Player turn rules:
#   - Energy refreshes to `max_energy` (GameState.max_energy) each turn; draw a
#     full hand (GameState.hand_size), discarding leftovers at end of turn.
#   - MOVEMENT costs energy: each move spends 1 energy and walks up to the unit's
#     move_range (Speed-stat) tiles. Repeatable while energy remains.
#   - Playing a CARD spends its energy cost. Attacks must be aimed at an in-range
#     target/footprint (StrategyAttackLibrary) — out-of-range enemies can't be
#     hit, so you move into range first. AOE hits only units inside the footprint.
#   - Block resets at the START of the player's turn (so Defend soaks the enemy
#     turn), matching the deckbuilder.
#   - Dash once per combat: a bonus full turn (refresh energy + new hand) after
#     this one ends.
#   - Curse cards clog the hand and fire their eot / on_play_other triggers, just
#     like the deckbuilder.
#
# Effect resolution: card effects route through the autoloaded `EffectSystem`,
# with `self` as the `scene` ctx so the tactical implementations of
# deal_damage / gain_block / heal / draw / discard / exhaust / conjure handle the
# actual mutations. The footprint resolver restricts AOE to the aimed tiles.

const BattleGridViewScript := preload("res://scripts/strategy/combat/BattleGridView.gd")

const ENEMY_TURN_DELAY := 0.45

# Layout (designed against the 1280x720 base viewport). The board fills the
# big left panel; the turn order + log stack on the right; the hand + a small
# control strip run along the bottom.
const BOARD_RECT := Rect2(14, 78, 902, 558)
const TURN_RECT := Rect2(928, 78, 338, 360)
const LOG_RECT := Rect2(928, 446, 338, 190)
# Bottom strip: a readout line, the hand row, and the control buttons.
const READOUT_Y := 640
const HAND_RECT := Rect2(14, 660, 902, 56)
const CTRL_X := 930
const CTRL_Y := 666

# Shared palette for the chrome.
const ACCENT := Color(1.0, 0.78, 0.36)
const PANEL_BG := Color(0.09, 0.07, 0.13, 0.96)
const PANEL_BORDER := Color(0.42, 0.33, 0.55, 0.9)
const BACKDROP := Color(0.04, 0.035, 0.07, 1.0)

# Per-archetype gold drop. Rolled when an enemy dies; the gold goes onto the
# battlefield and persists back to the source room on combat end. Enemies never
# drop items. Source of truth is the enemiesS sheet (StrategyEnemyData's gold_
# fields); this const is the fallback for kinds not on the sheet.
const ENEMY_LOOT_TABLE := {
	"snake":       { "gold_chance": 0.50, "gold_min":  3, "gold_max":  8 },
	"rattlesnake": { "gold_chance": 0.60, "gold_min":  5, "gold_max": 10 },
	"hobgoblin":   { "gold_chance": 0.60, "gold_min":  4, "gold_max":  9 },
	"troll":       { "gold_chance": 0.90, "gold_min": 12, "gold_max": 24 },
}

# Gold table for `kind`, preferring the data-driven StrategyEnemyData fields and
# falling back to ENEMY_LOOT_TABLE. Empty dict = no drop.
func _loot_table_for(kind: String) -> Dictionary:
	var d: StrategyEnemyData = Data.get_strategy_enemy(StringName(kind)) if Data else null
	if d != null and (d.gold_chance > 0.0 or d.gold_max > 0):
		return { "gold_chance": d.gold_chance, "gold_min": d.gold_min,
			"gold_max": d.gold_max }
	return ENEMY_LOOT_TABLE.get(kind, {})

# What the player is currently selecting in the grid view.
enum Pending { NONE, AIM, POTION_AIM }

var _battle_map = null
var _turn_manager = null
var _units: Array = []
var _room_data = null
var _encounter: Array = []

# --- Deckbuilder state (the four piles + energy) -----------------------
var draw_pile: Array = []
var hand: Array = []
var discard_pile: Array = []
var exhaust_pile: Array = []
var energy: int = 0
var max_energy: int = 3
# Ice Cream: leftover energy banked at end of turn, poured on next turn start.
var _energy_carryover: int = 0
# Energy spent by the X-cost card currently resolving (Whirlwind / Skewer);
# threaded into effect ctx as x_value so hits_from: "energy" dmg repeats once
# per point. Replay re-uses the same X (paid once).
var _last_x_value: int = 0
# Cards the last `discard:all` (Storm of Steel) sent away this play; read back
# by conjure `count_from: "discarded"` via the effect ctx scene.
var last_discard_count: int = 0
# Cards the last `exhaust:all` (Fiend Fire) sent away this play; read back by
# dmg `hits_from: "exhausted"` via the effect ctx scene.
var last_exhaust_count: int = 0

# Persistent in-combat power triggers (After Image -> on card played gain Block)
# and card boosts (Accuracy -> Shivs). Combat-scoped; cleared in _init_deck.
var power_triggers: Array = []
var card_boosts: Array = []

# Mid-action state: which card is mid-aim while we wait for a target click.
var _pending_kind: int = Pending.NONE
var _pending_card = null     # CardInstance being played
var _pending_aim_spec: Dictionary = {}
# Loot: index into GameState.loot_items for a potion being thrown (POTION_AIM).
var _pending_potion_index: int = -1
var _loot_dialog: Panel = null
var _loot_list_container: VBoxContainer = null
var _btn_loot: Button = null

var _grid_view: BattleGridView
var _initiative_label: Label
var _status_label: Label
var _info_label: Label
var _readout_label: Label
var _root_panel: Panel

# Floating Mewgenics-style enemy info card, populated on hover.
var _enemy_tooltip: Panel
var _enemy_tooltip_name: Label
var _enemy_tooltip_body: Label

var _hand_panel: Panel
var _hand_container: HBoxContainer

var _btn_move: Button
var _btn_dash: Button
var _btn_item: Button
var _btn_end: Button
var _btn_win: Button
var _btn_lose: Button

var _item_dialog: Panel
var _item_list_container: VBoxContainer
var _inventory_panel: CombatInventory

var _enemy_turn_timer: Timer

# Counts the player unit's turns this combat so turn-based items (Horn Cleat,
# Happy Flower) and the turn-1 draw bonus fire correctly. Reset per encounter.
var _player_turn_count: int = 0

# Snapshot of the hand's curse cards at end of turn, so their eot effects can
# fire AFTER status decay (a granted Weak/Blind must survive into next turn).
var _eot_curses: Array = []
var _eot_hand_size: int = 0

var _loot_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	layer = 10
	_loot_rng.randomize()
	max_energy = GameState.max_energy
	_build_ui()

# The player-controlled unit in this battle, or null.
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

# A card's effects with item boosts folded in (Strike Dummy) plus any appended
# granted effects (Brass Knuckles etc.). `upgraded` selects the upgraded_effects.
func _effective_card_effects(card: CardData, upgraded: bool = false) -> Array:
	return CardMods.resolved_effects(card.get_effective_effects(upgraded), card)

# Card text with live stat scaling AND item boosts folded into the numbers, plus
# the granted-effect line appended, for display. In-combat card boosts
# (Accuracy / Glass Knife's self-decay) fold in too.
func _card_desc(card: CardData, upgraded: bool = false) -> String:
	var out: String = CardScaling.scale_text(card.get_effective_description(upgraded), get_player_unit(), false, card, null, card_boosts)
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

	max_energy = GameState.max_energy
	_player_turn_count = 0
	_init_deck()

	_info_label.text = _format_info(room_data, encounter)
	_readout_label.text = ""
	_refresh_hand()

	if turn_manager != null:
		turn_manager.unit_turn_started.connect(_on_unit_turn_started)
		turn_manager.unit_turn_ended.connect(_on_unit_turn_ended)
		turn_manager.battle_ended.connect(_on_battle_ended)

	_refresh_initiative()
	_set_player_buttons_enabled(false)
	_status_label.text = "Battle begins!"
	# No loadout — go straight to combat. The first player turn draws the
	# opening hand and refreshes energy via _on_unit_turn_started.
	_fire_item_triggers("combat_started")
	_apply_pending_scroll_effects()
	StrategyCombatSession.begin_battle()

# Drains the scroll-scheduled carryover (Scare Monster / Aggravate / Fire) into
# this battle via ScrollSystem. Lives here (not CombatSession) so the Scare
# Monster "choose" tier can mount its enemy picker on this UI. Stun is applied as
# a status; a stunned enemy forfeits its turn (see _on_unit_turn_started) and the
# stack decays at its turn end.
func _apply_pending_scroll_effects() -> void:
	var enemies: Array = _units.filter(func(u): return u != null and u.is_alive() and not u.is_player)
	var stun_fn := func(mode: String, count: int) -> void:
		if mode == "all":
			for u in enemies:
				u.add_status(&"stun", 1)
		elif mode == "choose":
			StunPickerModal.new().start(self, enemies, count)
		else: # random
			var pool: Array = enemies.duplicate()
			pool.shuffle()
			for u in pool.slice(0, count):
				u.add_status(&"stun", 1)
	var buff_fn := func(power: int, defense: int) -> void:
		for u in enemies:
			if power != 0:
				u.add_status(&"power", power)
			if defense != 0:
				u.add_status(&"defense", defense)
	var fire_fn := func(amount: int) -> void:
		for u in enemies:
			var dmg: int = amount
			if u.block > 0:
				var blocked: int = mini(u.block, dmg)
				u.block -= blocked
				dmg -= blocked
			u.hp = maxi(0, u.hp - dmg)
			GameLog.add("Scroll of Fire burns %s for %d." % [str(u.unit_name).capitalize(), amount],
				Color(1.0, 0.5, 0.2))
	ScrollSystem.apply_pending_combat_effects(stun_fn, buff_fn, fire_fn)

# Build the four piles from the run deck. Mirrors DeckbuilderCombat._init_deck.
func _init_deck() -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	card_boosts.clear()
	power_triggers.clear()
	GameState.streak_clear()
	_energy_carryover = 0
	energy = 0
	last_discard_count = 0
	last_exhaust_count = 0
	for c in GameState.deck:
		if c is CardData:
			draw_pile.append(CardInstance.from_data(c))
		elif c is CardInstance:
			# Clear any leftover per-combat cost discount (Empty Tome).
			c.combat_cost_delta = 0
			draw_pile.append(c)
	_shuffle(draw_pile)
	_promote_innate()

# Innate cards start in the opening hand. draw_cards pulls from the BACK of the
# draw pile, so moving innate cards to the end after shuffling draws them first.
func _promote_innate() -> void:
	var innate: Array = []
	var rest: Array = []
	for ci in draw_pile:
		if ci != null and ci.data != null and ci.data.innate:
			innate.append(ci)
		else:
			rest.append(ci)
	if innate.is_empty():
		return
	rest.append_array(innate)
	draw_pile = rest

func _shuffle(pile: Array) -> void:
	for i in range(pile.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp = pile[i]
		pile[i] = pile[j]
		pile[j] = tmp

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
	_grid_view.aim_confirmed.connect(_on_aim_confirmed)
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

	# Energy + pile readout above the hand.
	_readout_label = Label.new()
	_readout_label.position = Vector2(20, READOUT_Y)
	_readout_label.size = Vector2(896, 18)
	_readout_label.add_theme_font_size_override("font_size", 13)
	_readout_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	panel.add_child(_readout_label)

	_build_hand_panel(panel)
	_build_control_bar(panel)
	_build_item_dialog()
	_build_loot_dialog()
	_build_inventory_panel(panel)
	_build_enemy_tooltip()

	_enemy_turn_timer = Timer.new()
	_enemy_turn_timer.one_shot = true
	_enemy_turn_timer.wait_time = ENEMY_TURN_DELAY
	_enemy_turn_timer.timeout.connect(_auto_end_enemy_turn)
	add_child(_enemy_turn_timer)

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

# Repaints a button as the gold primary CTA (End Turn).
func _style_primary(b: Button, font_size: int = 16) -> void:
	b.add_theme_stylebox_override("normal", _panel_stylebox(Color(0.5, 0.36, 0.12), ACCENT, 2, 10))
	b.add_theme_stylebox_override("hover", _panel_stylebox(Color(0.64, 0.46, 0.16), Color(1, 0.92, 0.55), 2, 10))
	b.add_theme_stylebox_override("pressed", _panel_stylebox(Color(0.42, 0.3, 0.1), ACCENT, 2, 10))
	b.add_theme_color_override("font_color", Color(1, 0.97, 0.86))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.92))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.42))
	b.add_theme_font_size_override("font_size", font_size)

func _build_control_bar(panel: Panel) -> void:
	var specs := [
		["Move", 76, _on_move_button], ["Dash", 72, _on_dash_button],
		["Item", 64, _on_item_button], ["End Turn", 104, _on_end_turn_button],
	]
	var x := CTRL_X
	var btns := []
	for spec in specs:
		var b := _make_button(spec[0], x, CTRL_Y, spec[1], 40, spec[2])
		panel.add_child(b)
		btns.append(b)
		x += spec[1] + 4
	_btn_move = btns[0]; _btn_dash = btns[1]; _btn_item = btns[2]; _btn_end = btns[3]
	_style_primary(_btn_end)

	# Loot button sits just above the action row. Opens the loot section where
	# potions are drunk (self) or thrown (aimed) — neither costs an action.
	_btn_loot = _make_button("Loot", CTRL_X, CTRL_Y - 44, 120, 36, _on_loot_button)
	panel.add_child(_btn_loot)
	_refresh_loot_button()
	if not GameState.inventory_changed.is_connected(_refresh_loot_button):
		GameState.inventory_changed.connect(_refresh_loot_button)

	# Debug force win/lose — only mounted in dev mode.
	if Settings.dev_mode:
		_btn_win = _make_button("Win▸", 1110, 626, 72, 26, _on_force_win, true)
		panel.add_child(_btn_win)
		_btn_lose = _make_button("Lose▸", 1190, 626, 72, 26, _on_force_lose, true)
		panel.add_child(_btn_lose)

# --- Hand row ----------------------------------------------------------

func _build_hand_panel(panel: Panel) -> void:
	_hand_panel = Panel.new()
	_hand_panel.position = HAND_RECT.position
	_hand_panel.size = HAND_RECT.size
	_hand_panel.add_theme_stylebox_override("panel", _panel_stylebox(PANEL_BG, PANEL_BORDER))
	panel.add_child(_hand_panel)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 5)
	scroll.size = Vector2(HAND_RECT.size.x - 16, HAND_RECT.size.y - 10)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_hand_panel.add_child(scroll)

	_hand_container = HBoxContainer.new()
	_hand_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_hand_container)

func _refresh_hand() -> void:
	if _hand_container == null:
		return
	for c in _hand_container.get_children():
		c.queue_free()
	for card in hand:
		_hand_container.add_child(_make_hand_card_button(card))
	_refresh_readout()

func _refresh_readout() -> void:
	if _readout_label == null:
		return
	_readout_label.text = "⚡ Energy %d/%d        Draw %d  ·  Hand %d  ·  Discard %d  ·  Exhaust %d" % [
		energy, max_energy, draw_pile.size(), hand.size(), discard_pile.size(), exhaust_pile.size(),
	]

# One clickable hand-card tile. Disabled when unaffordable, unplayable, or an
# attack with no enemy in range (so you must move into range first).
func _make_hand_card_button(card) -> Button:
	var data: CardData = card.data
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(132, 46)
	tile.focus_mode = Control.FOCUS_NONE
	tile.clip_text = true

	var cost: int = _card_cost(card)
	var is_attack: bool = _is_attack_card(data)
	# Whether any enemy is actually in range — used only as a soft "no target"
	# hint now. Attacks stay playable regardless so the player can swing into
	# empty tiles (whiff) rather than being forced to move into range first.
	var no_target: bool = is_attack and not _attack_has_target(_attack_spec_for_card(data))
	var playable: bool = _is_player_turn() and not data.unplayable \
		and cost <= energy
	tile.disabled = not playable
	tile.pressed.connect(_on_hand_card_pressed.bind(card))
	tile.mouse_entered.connect(_on_hover_hand_card.bind(card))
	tile.mouse_exited.connect(_on_hover_preview_end)

	var border: Color = ACCENT if (card == _pending_card) else PANEL_BORDER
	var base: Color = Color(0.16, 0.13, 0.2)
	if data.type == CardData.CardType.CURSE:
		base = Color(0.2, 0.12, 0.14)
	# Conditional-payoff glow (Dropkick): green tile while a living enemy
	# satisfies the card's if_target gate, so the player sees the bonus is live.
	elif card != _pending_card \
			and Stats.if_target_gate_live(card.get_effects(), living_enemies()):
		base = Color(0.13, 0.24, 0.16)
		border = Color(0.45, 0.85, 0.55)
	tile.add_theme_stylebox_override("normal", _panel_stylebox(base, border, 1, 8))
	tile.add_theme_stylebox_override("hover", _panel_stylebox(base.lightened(0.14), ACCENT, 2, 8))
	tile.add_theme_stylebox_override("pressed", _panel_stylebox(base.darkened(0.12), ACCENT, 2, 8))
	tile.add_theme_stylebox_override("disabled", _panel_stylebox(Color(0.1, 0.09, 0.12), Color(0.22, 0.22, 0.26), 1, 8))

	var dim: bool = not playable
	var name_l := Label.new()
	name_l.text = card.get_display_name()
	name_l.position = Vector2(8, 4)
	name_l.size = Vector2(118, 18)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color",
		Color(0.55, 0.55, 0.6) if dim else Color(1, 0.93, 0.82))
	tile.add_child(name_l)

	var meta: String = "⚡%d" % cost
	if data.unplayable:
		meta = "—"
	elif no_target:
		meta = "⚡%d · no target" % cost
	var meta_l := Label.new()
	meta_l.text = meta
	meta_l.position = Vector2(8, 24)
	meta_l.size = Vector2(118, 16)
	meta_l.clip_text = true
	meta_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_l.add_theme_font_size_override("font_size", 11)
	meta_l.add_theme_color_override("font_color",
		Color(0.9, 0.55, 0.35) if no_target else Color(0.62, 0.7, 0.9))
	tile.add_child(meta_l)
	return tile

# --- Items: the active-item action button + picker --------------------

func _build_item_dialog() -> void:
	var p := Panel.new()
	p.position = Vector2(922, 74)
	p.size = Vector2(352, 560)
	p.add_theme_stylebox_override("panel", _panel_stylebox(Color(0.1, 0.08, 0.15, 0.99), ACCENT, 2, 12))
	var t := Label.new()
	t.text = "Items"
	t.position = Vector2(16, 12)
	t.size = Vector2(320, 30)
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	p.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(14, 48)
	scroll.size = Vector2(324, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)
	_item_list_container = vbox
	var close := _make_button("Close", 126, 516, 100, 36, _close_item_dialog)
	p.add_child(close)
	add_child(p)
	p.visible = false
	_item_dialog = p

# Compact item rack pinned to the top-right corner so actives are visible.
func _build_inventory_panel(panel: Panel) -> void:
	_inventory_panel = CombatInventory.new()
	_inventory_panel.columns = 8
	_inventory_panel.tile_px = 26
	_inventory_panel.show_title = false
	_inventory_panel.panel_opacity = 0.92
	_inventory_panel.position = Vector2(940, 44)
	panel.add_child(_inventory_panel)

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

func _item_entry_at_grid(pos: Vector2i) -> Dictionary:
	if _battle_map == null:
		return {}
	for entry in _battle_map.items:
		if entry.pos == pos:
			return entry
	return {}

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
			var lbl: String = it.headline_label()
			var parts: Array = []
			if lbl != "":
				parts.append("%s dmg" % lbl if it.target_kind != "self" else lbl)
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

# --- Hover range previews ---------------------------------------------

func _hover_move_budget() -> int:
	var u = get_player_unit()
	if u == null or energy <= 0:
		return 0
	return u.move_range

func _enemy_positions() -> Array:
	var out: Array = []
	for u in _units:
		if u != null and u.is_alive() and not u.is_player:
			out.append(u.position)
	return out

# Hovering a hand card previews movement plus that card's reach (attacks) or
# every enemy it could touch (auto/AOE).
func _on_hover_hand_card(card) -> void:
	if not _is_player_turn() or card == null or card.data == null:
		return
	if not _is_attack_card(card.data):
		_grid_view.show_range_preview(_hover_move_budget(), 0)
		return
	var spec: Dictionary = _attack_spec_for_card(card.data)
	if String(spec.get("aim", "tile")) == "auto":
		_grid_view.show_range_preview(_hover_move_budget(), 0, _enemy_positions())
	else:
		var reach: int = maxi(int(spec.get("range_tiles", 1)), int(spec.get("radius", 0)))
		_grid_view.show_range_preview(_hover_move_budget(), reach)

func _on_hover_preview_end() -> void:
	if _grid_view != null:
		_grid_view.clear_range_preview()

# ----------------------------------------------------------------------
# Turn flow
# ----------------------------------------------------------------------

func _on_unit_turn_started(unit) -> void:
	_grid_view.set_active_unit(unit, unit.move_range)
	_refresh_initiative()
	# Fear: the unit automatically repositions as far from its foes as possible
	# at the start of its turn — a FREE move that costs no movement energy and
	# does NOT consume the turn. After fleeing it takes its normal turn. Same
	# rule for both sides; _fear_flee also decays Fear by 1.
	if unit.get_status(&"fear") > 0:
		_fear_flee(unit)
		_grid_view.set_active_unit(unit, unit.move_range)
		_refresh_initiative()
		GameLog.add("%s is gripped by Fear and flees!" % str(unit.unit_name).capitalize(),
			Color(0.8, 0.7, 1.0))
	if unit.is_player:
		_player_turn_count += 1
		# Turn-scoped skills expire NOW — after the enemy turns, so Flame
		# Barrier's registered retaliation covered every enemy hit. Drops
		# `until: "turn_end"` triggers (Rage / Flame Barrier) and wipes the
		# Skill-type marker icons (rage / flame_barrier / double_tap).
		power_triggers = Stats.expire_turn_triggers(power_triggers)
		Stats.clear_skill_markers(unit)
		# Refresh energy; Ice Cream pours last turn's leftover on top (may exceed
		# max), mirroring the deckbuilder's carry-over.
		energy = max_energy
		if _energy_carryover > 0 and GameState.has_energy_carryover_item():
			energy += _energy_carryover
			GameLog.add("Ice Cream: +%d bonus energy!" % _energy_carryover, Color(0.7, 1.0, 0.7))
		_energy_carryover = 0
		# Next Turn Energy (Flying Knee / Doppelganger): banked stacks pour onto
		# the refreshed pool now, then the status clears ("Lose all when triggered").
		var nt_energy: int = Stats.consume_status(unit, &"next_turn_energy")
		if nt_energy > 0:
			energy += nt_energy
			GameLog.add("Next Turn Energy: +%d energy." % nt_energy, Color(0.7, 1.0, 0.85))
		# Block resets at the start of the player's own turn (deckbuilder
		# rule); Barricade keeps it.
		if not Stats.keeps_block(unit):
			unit.block = 0
		_clear_pending()
		_fire_item_turn_triggers(unit, _player_turn_count)
		_fire_item_triggers("turn_tick")
		# Draw a fresh hand; Speed grants extra cards on the opening hand only.
		var draw_count: int = GameState.hand_size
		if _player_turn_count == 1:
			draw_count += Stats.deckbuilder_bonus_draws_turn_1()
		# Next Turn Draw (Predator / Doppelganger): banked stacks join the
		# turn-start hand, then the status clears.
		var nt_draw: int = Stats.consume_status(unit, &"next_turn_draw")
		if nt_draw > 0:
			draw_count += nt_draw
			GameLog.add("Next Turn Draw: +%d card%s." % [nt_draw, "s" if nt_draw > 1 else ""],
				Color(0.7, 0.95, 1.0))
		draw_cards(maxi(0, draw_count))
		# Confused: re-randomize the whole hand each turn (retained cards included).
		_apply_confused_to_hand()
		TriggerBus.emit_signal("turn_started", {"turn": _player_turn_count, "scene": self})
		_fire_item_triggers("turn_started")
		_fire_power_triggers("turn_started")
		TriggerBus.emit_signal("turn_tick", {"turn": _player_turn_count, "scene": self})
		GameState.charge_all_items(1)
		_set_player_buttons_enabled(true)
		_refresh_initiative()
		_refresh_hand()
		_status_label.text = "Your turn. Energy %d/%d  ·  each Move costs 1 (up to %d tiles)." % [
			energy, max_energy, unit.move_range,
		]
	else:
		# Stunned (Scroll of Scare Monster): the enemy forfeits this turn. The
		# stun stack steps down in the turn-end decay (_on_unit_turn_ended), so a
		# 1-stack stun costs exactly one turn. End the turn deferred to avoid
		# re-entering the initiative engine from inside its own signal.
		if unit.get_status(&"stun") > 0:
			_status_label.text = "%s is Stunned." % unit.unit_name
			_set_player_buttons_enabled(false)
			GameLog.add("%s is Stunned and loses its turn." % str(unit.unit_name).capitalize(),
				Color(0.9, 0.85, 0.5))
			_turn_manager.end_current_turn.call_deferred()
			return
		_status_label.text = "%s acts..." % unit.unit_name
		_set_player_buttons_enabled(false)
		_enemy_turn_timer.start()

func _on_unit_turn_ended(unit) -> void:
	_eot_curses = []
	_eot_hand_size = 0
	# Player end-of-turn: bank leftover energy (Ice Cream) and clear the hand —
	# Retain keeps cards, Sly resolves as it leaves, Ethereal exhausts.
	if unit != null and unit.is_player:
		_eot_curses = hand.duplicate()
		_eot_hand_size = hand.size()
		if energy > 0 and GameState.has_energy_carryover_item():
			_energy_carryover = energy
		var kept: Array = []
		while not hand.is_empty():
			var c = hand.pop_back()
			# Any "free this turn" discount (Mummified Hand) expires now.
			c.temp_cost_override = -999
			if c.data != null and (c.data.retain or c.granted_retain or c.retain_this_turn):
				# granted_retain: Scroll of Enchant Weapon. retain_this_turn:
				# Well-Laid Plans' end-of-turn pick — one turn only, consumed here.
				c.retain_this_turn = false
				kept.append(c)
			elif c.data != null and c.data.sly:
				_resolve_sly_on_discard(c)
				discard_pile.append(c)
			elif c.data != null and c.data.ethereal:
				exhaust_pile.append(c)
				GameLog.add("%s is Ethereal — exhausted." % c.data.display_name, Color(0.75, 0.85, 1.0))
				TriggerBus.emit_signal("card_exhausted", {"card": c, "scene": self})
				_fire_power_triggers("card_exhausted", {"card": c})
			else:
				discard_pile.append(c)
		hand = kept
		TriggerBus.emit_signal("turn_ended", {"turn": _player_turn_count, "scene": self})
		_fire_item_triggers("turn_ended")
		_fire_power_triggers("turn_ended")
		# All Choked is lost at the end of the PLAYER's turn — it only punishes
		# cards played within the turn it was inflicted (mirrors the
		# deckbuilder's wipe alongside Bleed).
		for cu in _units:
			Stats.clear_status_stacks(cu, &"choked")
	# Damage-over-time bite (Bleed, Leeches) BEFORE decay so it uses the current
	# stack count, then decay grows/ticks it down.
	if unit != null:
		Stats.tick_actor_statuses(unit, self)
		if unit.is_alive():
			Stats.decay_actor_statuses(unit)
	# Curse cards' eot effects land here — AFTER decay — so a status they grant
	# (Doubt -> Weak) survives into the next turn.
	if unit != null and unit.is_player:
		_fire_curse_triggers("eot", _eot_curses, _eot_hand_size)
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_hand()
	_check_battle_end_after_effect()

# Applies turn-based item effects to the player unit at the start of its turn.
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
# Curse cards (deckbuilder model: clog the hand, fire eot / on_play_other)
# ----------------------------------------------------------------------

# Fires the matching trigger on every curse card in `cards`. Curse effects are
# applied directly to the player UNIT (not GameState.hp) so they bite the combat
# correctly; hand_size feeds Regret's per-card-in-hand scaling.
func _fire_curse_triggers(trigger: String, cards: Array, hand_size: int) -> void:
	var p = get_player_unit()
	if p == null:
		return
	for c in cards:
		if c == null or c.data == null or c.data.triggers.is_empty():
			continue
		for trig in c.data.triggers:
			if String(trig.get("on", "")) != trigger:
				continue
			for raw in trig.get("effects", []):
				if raw is Dictionary:
					_apply_curse_effect(raw, c, p, hand_size)
	_refresh_hand()

func _apply_curse_effect(effect: Dictionary, card, p, hand_size: int) -> void:
	match String(effect.get("type", "")):
		"status":
			if Stats.apply_status_to(p, StringName(effect.get("status", "")), int(effect.get("stacks", 1))) > 0:
				_grid_view.notify_units_changed()
		"dmg":
			var dv: int = int(effect.get("value", 0))
			if dv > 0:
				apply_dot(p, dv, "Curse")
		"lose_hp", "lose_health":
			var lv: int = int(effect.get("value", 1))
			if String(effect.get("per", "")) == "card_in_hand":
				lv *= maxi(0, hand_size)
			if lv > 0:
				apply_dot(p, lv, "Curse")
		"conjure":
			conjure_card(
				StringName(String(effect.get("card_id", "self"))),
				String(effect.get("destination", "draw")),
				maxi(1, int(effect.get("count", 1))),
				card, bool(effect.get("upgraded", false)))
		_:
			# Anything exotic falls back to the shared dispatch against the player.
			EffectSystem.apply(effect, {"source": p, "target": p, "scene": self, "card": card})

# ----------------------------------------------------------------------
# Fear flee (shared by player + enemy units)
# ----------------------------------------------------------------------

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
			if score > best_score or (score == best_score and steps < best_steps):
				best_score = score
				best_tile = tile
				best_steps = steps
		if best_tile != unit.position:
			unit.position = best_tile
			_grid_view.notify_units_changed()
	if unit.get_status(&"fear") > 0:
		unit.add_status(&"fear", -1)

func _fear_flee_score(tile: Vector2i, foes: Array) -> int:
	var total: int = 0
	for f in foes:
		total += absi(tile.x - f.position.x) + absi(tile.y - f.position.y)
	return total

func _auto_end_enemy_turn() -> void:
	if _turn_manager == null or _turn_manager.current_unit == null:
		return
	var enemy = _turn_manager.current_unit
	if enemy.is_player:
		return
	# Split: a unit at/below half HP spawns its copies on free tiles and is
	# consumed instead of taking its normal turn.
	if Stats.should_split(enemy):
		_perform_strategy_split(enemy)
		if _turn_manager.check_battle_end_now():
			return
		_turn_manager.end_current_turn()
		return
	if enemy.ai != null:
		var msg: String = enemy.ai.execute_turn(self, _units, _battle_map)
		_status_label.text = msg
		_grid_view.notify_units_changed()
		_refresh_initiative()
		if _turn_manager.check_battle_end_now():
			return
		enemy.ai.plan_next(_units)
		_grid_view.notify_units_changed()
	_turn_manager.end_current_turn()

# Spawn a strategy splitter's copies on free tiles around it, each at its
# current HP and with its own AI, then consume the parent. _units aliases
# turn_manager.units (and the grid's list), so appending registers the new unit
# with the initiative engine and the grid in one step.
func _perform_strategy_split(unit) -> void:
	var count: int = int(unit.split_count)
	var child_hp: int = maxi(1, int(unit.hp))
	var kind: String = String(unit.split_into)
	unit.hp = 0   # consume the parent first so its tile reads as free
	var spawned: int = 0
	for _i in count:
		var tile: Vector2i = _free_tile_near(unit.position)
		if tile.x == _NO_TILE.x and tile.y == _NO_TILE.y:
			break
		var child = BattleUnit.from_enemy_kind(kind)
		child.max_hp = child_hp
		child.hp = child_hp
		child.position = tile
		child.ai = EnemyAI.build_for(child, kind)
		_turn_manager.units.append(child)
		child.ai.plan_next(_units)
		spawned += 1
	GameLog.add("%s splits into %d!" % [str(unit.unit_name).capitalize(), spawned],
		Color(0.7, 1.0, 0.7))
	_grid_view.notify_units_changed()
	_refresh_initiative()

const _NO_TILE := Vector2i(-9999, -9999)

# Nearest walkable, unoccupied tile to `origin` (origin itself first), or
# _NO_TILE if the splitter is fully boxed in.
func _free_tile_near(origin: Vector2i) -> Vector2i:
	var candidates: Array = [origin,
		origin + Vector2i(1, 0), origin + Vector2i(-1, 0),
		origin + Vector2i(0, 1), origin + Vector2i(0, -1),
		origin + Vector2i(1, 1), origin + Vector2i(-1, 1),
		origin + Vector2i(1, -1), origin + Vector2i(-1, -1)]
	for c in candidates:
		if _battle_map != null and (not _battle_map.in_bounds(c) or not _battle_map.is_walkable(c)):
			continue
		if _tile_occupied(c):
			continue
		return c
	return _NO_TILE

func _tile_occupied(tile: Vector2i) -> bool:
	for u in _units:
		if u != null and u.is_alive() and u.position == tile:
			return true
	return false

func _on_battle_ended(result) -> void:
	_status_label.text = "Battle ended: %s" % result
	_set_player_buttons_enabled(false)
	_fire_item_triggers("combat_ended")
	# Per-combat card cost discounts (Empty Tome) expire with the fight.
	for c in GameState.deck:
		if c is CardInstance:
			c.combat_cost_delta = 0

# ----------------------------------------------------------------------
# Player actions — movement
# ----------------------------------------------------------------------

func _on_move_button() -> void:
	if not _is_player_turn():
		return
	if energy <= 0:
		_status_label.text = "No energy left to move."
		return
	_clear_pending()
	var u = _turn_manager.current_unit
	_grid_view.set_active_unit(u, u.move_range)
	_grid_view.enter_move_mode()
	_status_label.text = "Click a tile to move (1 energy, up to %d tiles)." % u.move_range

func _on_move_requested(path: Array) -> void:
	if not _is_player_turn() or path.is_empty():
		return
	if energy <= 0:
		_status_label.text = "No energy left to move."
		return
	var u = _turn_manager.current_unit
	if path.size() > u.move_range:
		return
	energy -= 1
	u.position = path[-1]
	# Walking over an item collects it (each path step is checked).
	var pickup_msgs: Array = []
	for step in path:
		_try_pickup_at(step, pickup_msgs)
	var line: String = "Moved %d tile(s)  (−1 energy, %d left)." % [path.size(), energy]
	if not pickup_msgs.is_empty():
		line += "  " + ", ".join(pickup_msgs)
	_status_label.text = line
	# Keep moving while energy remains; otherwise drop back to idle.
	if energy > 0:
		_grid_view.set_active_unit(u, u.move_range)
		_grid_view.enter_move_mode()
	else:
		_grid_view.set_active_unit(u, u.move_range)
		_grid_view.enter_idle()
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_hand()
	_refresh_button_states()

func _try_pickup_at(pos: Vector2i, messages: Array) -> void:
	if _battle_map == null:
		return
	var hits: Array = []
	for entry in _battle_map.items:
		if entry.pos == pos:
			hits.append(entry)
	for entry in hits:
		var msg: String = _collect_item(entry)
		if msg != "":
			messages.append(msg)

func _collect_item(entry: Dictionary) -> String:
	var item = entry.item
	var player_entity = StrategyState.player
	if item.auto_pickup:
		match item.item_type:
			StrategyItem.ItemType.GOLD:
				GameState.change_gold(int(item.amount))
				_battle_map.remove_item_entry(entry)
				Notifications.notify("Picked up %d gold." % int(item.amount), Color(1.0, 0.84, 0.3))
				return "+%d gold" % int(item.amount)
			StrategyItem.ItemType.KEY:
				StrategyState.keys += 1
				_battle_map.remove_item_entry(entry)
				Notifications.notify("Picked up a key.", Color(0.95, 0.85, 0.45))
				return "+key"
			_:
				_battle_map.remove_item_entry(entry)
				Notifications.notify("Picked up %s." % str(item.item_name), Color(0.7, 0.85, 1.0))
				return "+%s" % str(item.item_name)
	if player_entity == null:
		return ""
	if player_entity.inventory.size() >= StrategyEntity.MAX_INVENTORY:
		return "(pack full: %s)" % str(item.item_name)
	player_entity.inventory.append(item)
	_battle_map.remove_item_entry(entry)
	Notifications.notify("Picked up %s." % str(item.item_name), Color(0.7, 0.85, 1.0))
	return "picked up %s" % str(item.item_name)

# ----------------------------------------------------------------------
# Player actions — Dash / End Turn / dev
# ----------------------------------------------------------------------

func _on_dash_button() -> void:
	if not _is_player_turn():
		return
	if _turn_manager.consume_dash():
		_status_label.text = "Dash! End your turn to take a bonus turn (fresh energy + hand)."
		_refresh_initiative()
		_refresh_button_states()

func _on_end_turn_button() -> void:
	if not _is_player_turn():
		return
	_clear_pending()
	_grid_view.enter_idle()
	# Well-Laid Plans (retain-typed turn_ended triggers): before the hand
	# discards, pick up to N cards to keep this turn. The picker is async —
	# the turn actually ends from the confirm callback (same contract as
	# the deckbuilder).
	var wlp: int = Stats.retain_total(power_triggers)
	if wlp > 0 and not hand.is_empty():
		_open_picker({
			"title": "Well-Laid Plans — Retain up to %d" % mini(wlp, hand.size()),
			"candidates": hand.duplicate(),
			"count": mini(wlp, hand.size()),
			"up_to": true,
			"accent": Color(0.6, 0.9, 1.0),
			"confirm_label": "Retain",
			"on_picked": Callable(self, "_apply_wlp_picks"),
		})
		return
	_set_player_buttons_enabled(false)
	_turn_manager.end_current_turn()

# Well-Laid Plans confirm: stamp the picks with a one-turn Retain, then run
# the turn end that was deferred while the picker was open.
func _apply_wlp_picks(picks: Array) -> void:
	for pick in picks:
		if pick is CardInstance:
			pick.retain_this_turn = true
			GameLog.add("Well-Laid Plans: %s is Retained." % pick.get_display_name(),
				Color(0.6, 0.9, 1.0))
	_set_player_buttons_enabled(false)
	_turn_manager.end_current_turn()

func _on_force_win() -> void:
	StrategyCombatSession.resolve_combat("victory")

func _on_force_lose() -> void:
	StrategyCombatSession.resolve_combat("defeat")

# ----------------------------------------------------------------------
# Player actions — playing a card from hand
# ----------------------------------------------------------------------

# A card is an "attack" (needs aiming / an in-range target) if it carries an
# attack shape or any damaging/debuffing effect aimed at enemies.
func _is_attack_card(data: CardData) -> bool:
	if data == null:
		return false
	if data.attack_shape != &"":
		return true
	for e in data.effects:
		if not (e is Dictionary):
			continue
		var t := String(e.get("target", ""))
		var ty := String(e.get("type", ""))
		if (t == "enemy" or t == "all_enemies") and ty in ["dmg", "status", "dmg_fraction_max_hp"]:
			return true
	return false

# The grid attack spec for a card, from its Attack-column archetype (with the
# legacy melee/ranged fallback for un-annotated cards).
func _attack_spec_for_card(card_data) -> Dictionary:
	var spec: Dictionary = Data.strategy_attacks.resolve_for_card(card_data)
	# Range stat extends the player's attack reach: every few points adds a tile.
	Data.strategy_attacks.apply_range_to_spec(spec, Stats.strategy_range_bonus_tiles())
	return spec

# True if at least one living enemy could actually be hit by `spec` from the
# player's current tile — so an attack with no reachable target is disabled and
# you must move into range first. Auto attacks (smite/bounce) reach the whole
# board; tile/self attacks test their real footprint against every legal aim.
func _attack_has_target(spec: Dictionary) -> bool:
	var p = get_player_unit()
	if p == null or spec.is_empty():
		return false
	match String(spec.get("aim", "tile")):
		"auto":
			return not _living_enemy_units().is_empty()
		"self":
			return _footprint_hits_enemy(spec, p, p.position)
		_:  # tile-aimed: any in-range aim whose footprint catches a foe
			var aimable: Dictionary = Data.strategy_attacks.aimable_tiles(spec, p.position, _battle_map)
			for tile in aimable.keys():
				if _footprint_hits_enemy(spec, p, tile):
					return true
			return false

func _footprint_hits_enemy(spec: Dictionary, source, aim: Vector2i) -> bool:
	for unit in _shaped_targets_for(spec, source, aim):
		if not unit.is_player:
			return true
	return false

func _on_hand_card_pressed(card) -> void:
	_play_card(card)

func _play_card(card) -> void:
	if not _is_player_turn() or card == null or card.data == null:
		return
	# Clicking the already-armed card cancels the aim.
	if _pending_kind == Pending.AIM and _pending_card == card:
		_clear_pending()
		_grid_view.enter_idle()
		_refresh_hand()
		return
	_clear_pending()
	_grid_view.enter_idle()
	var data: CardData = card.data
	if data.unplayable:
		_status_label.text = "%s is unplayable." % card.get_display_name()
		return
	var cost: int = _card_cost(card)
	if cost > energy:
		_status_label.text = "Not enough energy for %s." % card.get_display_name()
		return
	if _is_attack_card(data):
		var spec: Dictionary = _attack_spec_for_card(data)
		# No "must have a target" gate: attacks can be used even when nothing is in
		# range. Tile-aimed swings enter aim mode (aim within range, hitting whoever
		# stands there — possibly no one); self/auto attacks resolve on whatever
		# they catch, which may be nothing.
		if String(spec.get("aim", "tile")) == "tile":
			# Aimed attack: gate the cursor to in-range tiles; the footprint rotates
			# to face the aim and resolution hits whoever stands in it.
			_pending_kind = Pending.AIM
			_pending_card = card
			_pending_aim_spec = spec
			_grid_view.set_active_unit(_turn_manager.current_unit, _turn_manager.current_unit.move_range)
			_grid_view.enter_aim_mode(spec)
			_status_label.text = "Playing %s — aim within range (right-click to cancel)." % card.get_display_name()
			_refresh_hand()
			return
		# Self-centred (nova) resolves on the attacker's tile; auto picks its own.
		var shaped: Array = []
		if String(spec.get("aim", "tile")) == "self":
			shaped = _shaped_targets_for(spec, _turn_manager.current_unit, _turn_manager.current_unit.position)
		_resolve_card(card, null, shaped)
	else:
		# Self / skill card — resolves immediately, no targeting.
		_resolve_card(card, null, [])

func _card_cost(card) -> int:
	var c: int = card.get_cost()
	if c < 0:
		return energy  # X-cost: spend all remaining energy
	return maxi(0, c + Stats.fear_card_surcharge(get_player_unit(), card))

# Core play: pay energy, fire triggers, resolve effects against the footprint /
# target, then route the card to discard / exhaust / destroy. Mirrors the
# DeckbuilderCombat contract so the two modes behave identically.
func _resolve_card(card, target, shaped_targets: Array = []) -> void:
	if card == null:
		return
	var u = _turn_manager.current_unit
	var data: CardData = card.data
	# X-cost cards (cost -1) spend ALL remaining energy; the amount becomes X
	# for their hits_from: "energy" effects (_card_cost already returns the
	# whole pool for them, so the deduction empties it either way).
	_last_x_value = maxi(0, energy) if card.get_cost() < 0 else 0
	energy -= _card_cost(card)
	# Power-card triggers fire BEFORE the card's own effects (so a Power being
	# played doesn't self-trigger), then item card_played hooks.
	_fire_power_triggers("card_played", {"card": card})
	# Rage listens on the attack-only sibling event.
	if card.is_attack():
		_fire_power_triggers("attack_played", {"card": card})
	_fire_item_triggers("card_played", {"card": card, "target": target})
	# Choked bites on the card PLAY, before its effects — the play that
	# inflicts Choked never procs itself.
	Stats.choked_on_card_played(living_enemies(), self)
	# Vorpal rides the physical card instance; recover its roll and pass it down.
	card.roll_vorpal_if_needed()
	var vorpal: Dictionary = {}
	if card.vorpal_type >= 0 and card.vorpal_weight > 0:
		vorpal = {"type": card.vorpal_type, "weight": card.vorpal_weight}
	_apply_card_or_spell_effects(_effective_card_effects(data, card.upgraded), u, target, card, vorpal, shaped_targets)
	# Double Tap: the next Attack played this turn resolves its effects twice —
	# one stack per doubled Attack (the upgraded card banks 2).
	if card.is_attack() and u != null and u.get_status(&"double_tap") > 0:
		u.add_status(&"double_tap", -1)
		GameLog.add("Double Tap: %s is played twice!" % card.get_display_name(),
			Color(0.85, 0.7, 1.0))
		_apply_card_or_spell_effects(_effective_card_effects(data, card.upgraded), u, target, card, vorpal, shaped_targets)
	_fire_item_triggers("card_resolved", {"card": card, "target": target})
	# Playing a card fires any on_play_other curse in hand (Pain: lose HP).
	_fire_curse_triggers("on_play_other", hand, hand.size())
	# Fear: playing a Skill steadies the player — shed 1 Fear.
	if card.is_skill() and u.get_status(&"fear") > 0:
		u.add_status(&"fear", -1)
		GameLog.add("Fear -1 (Skill played).", Color(0.7, 0.9, 1.0))
	# Route the played card: Destroy > exhaust (flag or Power) > discard.
	if data.destroy:
		hand.erase(card)
		GameState.destroy_card_instance(card)
		GameLog.add("%s is Destroyed — removed from your deck." % card.get_display_name(),
			Color(0.9, 0.55, 0.55))
		TriggerBus.emit_signal("card_exhausted", {"card": card, "scene": self})
		_fire_power_triggers("card_exhausted", {"card": card})
	elif data.exhaust:
		exhaust_card(card)
	elif card.is_power():
		# Powers are simply used — the effect lives on the player for the
		# combat. No pile, no card_exhausted (Feel No Pain stays quiet).
		hand.erase(card)
		Stats.register_power(u, data)
	else:
		discard_card(card, true)
	_clear_pending()
	_grid_view.enter_idle()
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_hand()
	_refresh_button_states()
	_check_battle_end_after_effect()

# ----------------------------------------------------------------------
# Grid-view callbacks
# ----------------------------------------------------------------------

# A tile was clicked inside an aimed attack's range. Resolve the pending card
# against the footprint anchored at the attacker and oriented toward `pos`.
func _on_aim_confirmed(pos: Vector2i) -> void:
	if not _is_player_turn():
		return
	# Thrown potion: splash its effects over the manhattan footprint at `pos`.
	if _pending_kind == Pending.POTION_AIM:
		_resolve_potion_throw(pos)
		return
	if _pending_kind != Pending.AIM or _pending_card == null:
		return
	var attacker = _turn_manager.current_unit
	var card = _pending_card
	var shaped: Array = _shaped_targets_for(_pending_aim_spec, attacker, pos)
	_resolve_card(card, null, shaped)

func _on_target_cancelled() -> void:
	if _pending_kind == Pending.NONE:
		return
	_clear_pending()
	_grid_view.enter_idle()
	_refresh_hand()
	_status_label.text = "Cancelled."

# Unused now (no range-less unit targeting / basic-attack mode) but the grid view
# still wires the signals — keep harmless stubs.
func _on_target_requested(_target) -> void:
	pass

func _on_attack_requested(_target) -> void:
	pass

func _clear_pending() -> void:
	_pending_kind = Pending.NONE
	_pending_card = null
	_pending_aim_spec = {}
	_pending_potion_index = -1

# The living units standing in `spec`'s footprint when anchored at `source` and
# aimed at `aim`. Friendly fire: every unit in the footprint is returned.
func _shaped_targets_for(spec: Dictionary, source, aim: Vector2i) -> Array:
	if spec.is_empty() or source == null:
		return []
	var stops: Dictionary = {}
	for u in _units:
		if u != source and u.is_alive():
			stops[u.position] = true
	var tiles: Array = Data.strategy_attacks.footprint(spec, source.position, aim, _battle_map, stops)
	var tileset: Dictionary = {}
	for t in tiles:
		tileset[t] = true
	var out: Array = []
	for u in _units:
		if u.is_alive() and tileset.has(u.position):
			out.append(u)
	return out

# ----------------------------------------------------------------------
# Effect resolution (called by EffectSystem handlers via this scene)
# ----------------------------------------------------------------------

# Public entry point used by EnemyAI.execute_turn (and any caller).
func apply_effects(effects: Array, source, target, card = null, shaped_targets: Array = []) -> void:
	# Not a paid card play — no X was spent, so don't leak the last one.
	_last_x_value = 0
	_apply_card_or_spell_effects(effects, source, target, card, {}, shaped_targets)

# Public wrapper so EnemyAI can ask which units an attack spec would hit.
func shaped_targets(spec: Dictionary, source, aim: Vector2i) -> Array:
	return _shaped_targets_for(spec, source, aim)

# Status application entry point (called by EffectSystem._h_status).
func apply_status(target, status: StringName, stacks: int, source = null) -> void:
	if Stats.apply_status_to(target, status, stacks, source) > 0:
		_grid_view.notify_units_changed()

func _apply_card_or_spell_effects(effects: Array, source, target, card = null, vorpal: Dictionary = {}, shaped_targets: Array = []) -> void:
	# `card` is the played CardInstance (or null for enemy AI moves). The addon /
	# boost / replay maths key off the static CardData, while the EffectSystem ctx
	# carries the live INSTANCE so handlers that mutate a specific physical card
	# (exhaust_self, Mummified Hand, discard/exhaust exclusion) target the right one.
	var card_data = card.data if card is CardInstance else card
	# Replay addon: a card with Replay X resolves its full effect list X extra times.
	var plays: int = 1 + CardMods.replay_count(card_data)
	for _play in plays:
		for raw_effect in effects:
			var effect: Dictionary = Stats.apply_addons_to_effect(raw_effect, card_data)
			# Fold active card boosts (Accuracy / Claw) into matching dmg/block.
			effect = Stats.apply_card_boosts(effect, card_data, card_boosts)
			if not vorpal.is_empty():
				effect = effect.duplicate()
				effect["vorpal_type"] = int(vorpal["type"])
				effect["vorpal_weight"] = int(vorpal["weight"])
			# An empty target list means an enemy/AOE effect that landed on no one —
			# it simply does nothing rather than falling back onto the caster.
			var resolved_targets: Array = _resolve_effect_targets(effect, source, target, shaped_targets)
			for t in resolved_targets:
				EffectSystem.apply(effect, {
					"source": source,
					"target": t,
					"scene": self,
					"card": card,
					"x_value": _last_x_value,
				})

func _resolve_effect_targets(effect: Dictionary, source, picked, shaped_targets: Array = []) -> Array:
	var kind: String = str(effect.get("target", "self"))
	# Indiscriminate enemy effects seed a random enemy (EffectSystem re-rolls per
	# hit from there). Blood Magic / Bouncing Flask.
	if bool(effect.get("indiscriminate", false)) and kind == "enemy":
		var seed_target = pick_random_enemy(source)
		return [seed_target] if seed_target != null else []
	# Spatial attack: damaging enemy / AOE effects hit whoever stands in the aimed
	# footprint (friendly fire included). self / ally effects resolve normally.
	if not shaped_targets.is_empty() and (kind == "enemy" or kind == "all_enemies"):
		return shaped_targets
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

func pick_random_enemy(source):
	var foes: Array = []
	for u in _units:
		if u.is_alive() and (source == null or u.is_player != source.is_player):
			foes.append(u)
	if foes.is_empty():
		return null
	return foes[randi() % foes.size()]

# Every enemy-side unit still standing — shared shape with DeckbuilderCombat
# so cross-mode helpers (Fire Breathing) can sweep the field.
func living_enemies() -> Array:
	var out: Array = []
	for u in _units:
		if u.is_alive() and not u.is_player:
			out.append(u)
	return out

func deal_damage(source, target, value: int, effect: Dictionary = {}) -> void:
	if target == null:
		return
	var raw: int = int(value)
	if effect.get("type", "") == "dmg_fraction_max_hp":
		raw = int(round(target.max_hp * float(effect.get("value", 0))))
	_apply_damage(source, target, raw, effect)

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
	target.block = maxi(0, target.block) + Stats.resolve_block(int(value), target, true)
	_grid_view.notify_units_changed()

func heal(target, value: int) -> void:
	if target == null:
		return
	var before: int = target.hp
	target.hp = mini(target.max_hp, target.hp + int(value))
	_float_number(target, target.hp - before, FloatingNumbers.HEAL_COLOR)

# EffectSystem callback for boost_cards (Accuracy / Claw).
func add_card_boost(boost: Dictionary) -> void:
	card_boosts.append(boost)
	GameLog.add("Active boost: %s." % _boost_label(boost), Color(0.7, 1.0, 0.7))

func _boost_label(boost: Dictionary) -> String:
	var who: String = ""
	if String(boost.get("match_tag", "")) != "":
		who = "tag=%s" % boost.match_tag
	elif String(boost.get("match_type", "")) != "":
		who = "type=%s" % boost.match_type
	elif String(boost.get("match_id", "")) != "":
		who = "id=%s" % boost.match_id
	return "%s %s +%d" % [who, boost.get("stat", "dmg"), int(boost.get("value", 0))]

# EffectSystem callback for the `trigger` effect (After Image). Registers a
# persistent in-combat listener; _fire_power_triggers dispatches it.
func register_trigger(on: String, inner_effect: Dictionary, until: String = "") -> void:
	if on == "" or inner_effect.is_empty():
		return
	var entry: Dictionary = {"on": on, "effect": inner_effect}
	# `until: "turn_end"` (Rage / Flame Barrier): expires at the start of the
	# player's NEXT turn — see Stats.expire_turn_triggers in _on_unit_turn_started.
	if until != "":
		entry["until"] = until
	power_triggers.append(entry)
	GameLog.add("Trigger armed on %s%s." % [on,
		" (this turn)" if until == "turn_end" else ""], Color(0.7, 1.0, 0.7))

func _fire_power_triggers(event_name: String, ctx_extras: Dictionary = {}) -> void:
	# Inner-effect targets resolve like a played card's would: `all_enemies`
	# fans out over the living field (Fire Breathing), `enemy` lands on the
	# event's target (Envenom's poison on the struck foe), else the player.
	if power_triggers.is_empty():
		return
	var p = get_player_unit()
	for trig in power_triggers:
		if String(trig.get("on", "")) != event_name:
			continue
		var inner: Dictionary = trig.get("effect", {})
		if inner.is_empty():
			continue
		var targets: Array = []
		match String(inner.get("target", "self")):
			"all_enemies":
				targets = living_enemies()
			"enemy":
				var t: Variant = ctx_extras.get("target")
				if t != null:
					targets = [t]
			_:
				targets = [p]
		for tgt in targets:
			EffectSystem.apply(inner, {
				"source": p, "target": tgt, "scene": self, "card": ctx_extras.get("card"),
			})

# --- Card piles (real draw / discard / exhaust now) -------------------

func draw_cards(n: int) -> void:
	# No Draw (Battle Trance): every further draw this turn is suppressed. The
	# status decays at the unit's turn end, so the next turn-start hand is
	# unaffected.
	var nd_player = get_player_unit()
	if n > 0 and nd_player != null and nd_player.get_status(&"no_draw") > 0:
		GameLog.add("No Draw — no cards drawn.", Color(1.0, 0.7, 0.5))
		return
	for _i in range(n):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			while not discard_pile.is_empty():
				draw_pile.append(discard_pile.pop_back())
			_shuffle(draw_pile)
		var c = draw_pile.pop_back()
		hand.append(c)
		# Confused: roll the drawn card's cost (covers mid-turn draws).
		if _is_confused() and c != null:
			c.temp_cost_override = randi() % (maxi(0, max_energy) + 1)
		TriggerBus.emit_signal("card_drawn", {"card": c, "scene": self})
		_fire_power_triggers("card_drawn", {"card": c})
		# Evolve / Fire Breathing listen on the draw's card type.
		if c != null and c.data != null and c.data.type == CardData.CardType.STATUS:
			_fire_power_triggers("status_drawn", {"card": c})
		if c != null and c.data != null and (c.data.type == CardData.CardType.STATUS
				or c.data.type == CardData.CardType.CURSE):
			_fire_power_triggers("status_or_curse_drawn", {"card": c})
		# Card-level `drawn` triggers (Endless Agony: conjure a copy of itself
		# to hand). Conjured copies arrive without being drawn — no cascade.
		_fire_drawn_triggers(c)
	_check_battle_end_after_effect()
	_refresh_hand()

# Fires a card's own `drawn` triggers the moment it is drawn (Endless Agony).
# Card-level, like the curse eot/on_play_other triggers — the effects resolve
# with the drawn card as ctx.card so conjure:self copies IT.
func _fire_drawn_triggers(c) -> void:
	if c == null or c.data == null or c.data.triggers.is_empty():
		return
	var p = get_player_unit()
	for trig in c.data.triggers:
		if String(trig.get("on", "")) != "drawn":
			continue
		for eff in trig.get("effects", []):
			if eff is Dictionary:
				EffectSystem.apply(eff, {
					"source": p, "target": p, "scene": self, "card": c,
				})

# Confused (Snecko): true while the player unit carries the status.
func _is_confused() -> bool:
	var p = get_player_unit()
	return p != null and p.get_status(&"confused") > 0

# Re-roll every hand card's cost to a random 0..max_energy while Confused; a no-op
# otherwise. Same temp_cost_override slot the hand/play sites already honour.
func _apply_confused_to_hand() -> void:
	if not _is_confused():
		return
	for c in hand:
		if c != null:
			c.temp_cost_override = randi() % (maxi(0, max_energy) + 1)

func discard_card(card, from_play: bool = false) -> void:
	hand.erase(card)
	# "Free this turn" (Mummified Hand / conjure_random's free mint) ends the
	# moment the card leaves hand — without this a played free card would
	# reshuffle back in still costing 0.
	if card != null:
		card.temp_cost_override = -999
	# Sly: resolve effects the moment it would be discarded (unless it just
	# resolved AS a normal play — from_play skips the double-fire).
	if not from_play and card != null and card.data != null and card.data.sly:
		_resolve_sly_on_discard(card)
	# An effect-driven discard (not the played card routing to the pile) is a
	# "Card Discarded this turn" for Eviscerate's discount.
	if not from_play:
		GameState.incremental_on_discard()
	discard_pile.append(card)
	TriggerBus.emit_signal("card_discarded", {"card": card, "scene": self})
	_fire_power_triggers("card_discarded", {"card": card})
	_refresh_hand()

func _resolve_sly_on_discard(card) -> void:
	if card == null:
		return
	var tgt = pick_random_enemy(get_player_unit())
	GameLog.add("%s is Sly — it plays as it's discarded!" % card.get_display_name(),
		Color(0.8, 1.0, 0.8))
	# A Sly resolve isn't a paid play — no energy was spent, so X is 0 here.
	_last_x_value = 0
	_apply_card_or_spell_effects(_effective_card_effects(card.data, card.upgraded), get_player_unit(), tgt, card)
	_check_battle_end_after_effect()

func exhaust_card(card) -> void:
	hand.erase(card)
	# Free-this-turn override ends as the card leaves hand (see discard_card).
	if card != null:
		card.temp_cost_override = -999
	exhaust_pile.append(card)
	TriggerBus.emit_signal("card_exhausted", {"card": card, "scene": self})
	_fire_power_triggers("card_exhausted", {"card": card})
	_fire_card_exhausted_triggers(card)
	_refresh_hand()

# Fires a card's own `exhausted` triggers the moment IT is exhausted
# (Sentinel) — the exhaust sibling of _fire_drawn_triggers. Reads the
# upgrade-effective triggers so Sentinel+ pays its bigger refund.
func _fire_card_exhausted_triggers(c) -> void:
	if c == null or c.data == null:
		return
	var p = get_player_unit()
	for trig in c.data.get_effective_triggers(c.upgraded):
		if String(trig.get("on", "")) != "exhausted":
			continue
		for eff in trig.get("effects", []):
			if eff is Dictionary:
				EffectSystem.apply(eff, {
					"source": p, "target": p, "scene": self, "card": c,
				})

# Havoc: play the top card of the draw pile at no cost, then exhaust it.
# Mirrors the Sly auto-resolve — attacks land on a random living enemy; an
# X-cost card autoplays with X = 0. A Power registers and is consumed.
func autoplay_top_card(exhaust_it: bool, _source_card = null) -> void:
	if draw_pile.is_empty():
		if discard_pile.is_empty():
			GameLog.add("Havoc: no cards left to play.", Color(0.85, 0.85, 0.55))
			return
		while not discard_pile.is_empty():
			draw_pile.append(discard_pile.pop_back())
		_shuffle(draw_pile)
	var c = draw_pile.pop_back()
	if c == null:
		return
	var p = get_player_unit()
	GameLog.add("Havoc plays %s!" % c.get_display_name(), Color(0.85, 0.7, 1.0))
	_fire_power_triggers("card_played", {"card": c})
	if c.is_attack():
		_fire_power_triggers("attack_played", {"card": c})
	var tgt = pick_random_enemy(p)
	var prev_x: int = _last_x_value
	_last_x_value = 0
	_apply_card_or_spell_effects(_effective_card_effects(c.data, c.upgraded), p, tgt, c)
	_last_x_value = prev_x
	if c.is_power():
		Stats.register_power(p, c.data)
	elif exhaust_it or (c.data != null and c.data.exhaust):
		exhaust_pile.append(c)
		TriggerBus.emit_signal("card_exhausted", {"card": c, "scene": self})
		_fire_power_triggers("card_exhausted", {"card": c})
		_fire_card_exhausted_triggers(c)
	else:
		discard_pile.append(c)
	_refresh_hand()
	_check_battle_end_after_effect()

# Dual Wield: pick an Attack or Power card in hand, conjure `count` copies to
# hand (upgrade state preserved).
var _pending_copy_count: int = 1

func copy_from_hand_cards(count: int, filter: String, source_card = null) -> void:
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		if filter == "attack_or_power" and not (c.is_attack() or c.is_power()):
			continue
		pool.append(c)
	if pool.is_empty():
		GameLog.add("No Attack or Power cards in hand to copy.", Color(0.85, 0.85, 0.55))
		return
	_pending_copy_count = maxi(1, count)
	_open_picker({
		"title": "Choose a card to copy (%d cop%s to hand)" % [
			_pending_copy_count, "ies" if _pending_copy_count > 1 else "y"],
		"candidates": pool,
		"count": 1,
		"accent": Color(0.85, 0.7, 1.0),
		"confirm_label": "Copy",
		"on_picked": Callable(self, "_apply_copy_pick"),
	})

func _apply_copy_pick(picks: Array) -> void:
	for pick in picks:
		if not (pick is CardInstance):
			continue
		for _i in range(_pending_copy_count):
			hand.append(CardInstance.from_data(pick.data, pick.upgraded))
		GameLog.add("Conjured %d cop%s of %s to hand." % [
			_pending_copy_count, "ies" if _pending_copy_count > 1 else "y",
			pick.get_display_name()], Color(0.7, 1.0, 0.7))
	_refresh_hand()

# Exhume: pick a card from the exhaust pile back to hand (never another Exhume).
func exhume_cards(n: int, source_card = null) -> void:
	var pool: Array = []
	for c in exhaust_pile:
		if c == source_card:
			continue
		if c.data != null and c.data.id == &"exhume":
			continue
		pool.append(c)
	if pool.is_empty():
		GameLog.add("Exhume: nothing to retrieve from the exhaust pile.",
			Color(0.85, 0.85, 0.55))
		return
	var count: int = mini(n, pool.size())
	_open_picker({
		"title": "Exhume %d card%s to your hand" % [count, "s" if count > 1 else ""],
		"candidates": pool,
		"count": count,
		"accent": Color(0.7, 0.7, 0.8),
		"confirm_label": "Exhume",
		"on_picked": Callable(self, "_apply_exhume_picks"),
	})

func _apply_exhume_picks(picks: Array) -> void:
	for pick in picks:
		exhaust_pile.erase(pick)
		hand.append(pick)
		GameLog.add("Exhumed %s to hand." % pick.get_display_name(),
			Color(0.7, 1.0, 0.7))
	_refresh_hand()

# Everything a pick-from-hand effect may choose from: the hand minus the card
# being played (it's mid-resolve and can't route itself through the pick).
func _hand_pool(source_card) -> Array:
	var pool: Array = []
	for c in hand:
		if c != source_card:
			pool.append(c)
	return pool

# Discard N cards from hand (excludes the playing card). Player-choice opens
# the shared CardPickerModal (Acrobatics); `random` keeps the engine pick
# (All-Out Attack) — same contract as the deckbuilder.
func discard_cards(n: int, source_card = null, random: bool = false) -> void:
	if n <= 0:
		return
	var pool: Array = _hand_pool(source_card)
	if pool.is_empty():
		return
	if random:
		for _i in range(mini(n, pool.size())):
			var pick = pool[randi() % pool.size()]
			pool.erase(pick)
			discard_card(pick)
		_refresh_hand()
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Discard %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": Color(0.95, 0.70, 0.30),
			"confirm_label": "Discard",
			"on_picked": Callable(self, "_apply_discard_picks"),
		})

func _apply_discard_picks(picks: Array) -> void:
	for pick in picks:
		discard_card(pick)
		GameLog.add("Discarded %s." % pick.get_display_name(), Color(0.9, 0.7, 0.4))
	_refresh_hand()

# Exhaust N cards from hand (excludes the playing card). Burning Pact. Same
# picker-by-default / random-flag contract as discard_cards.
func exhaust_cards(n: int, source_card = null, random: bool = false) -> void:
	if n <= 0:
		return
	var pool: Array = _hand_pool(source_card)
	if pool.is_empty():
		return
	if random:
		for _i in range(mini(n, pool.size())):
			var pick = pool[randi() % pool.size()]
			pool.erase(pick)
			exhaust_card(pick)
		_refresh_hand()
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Exhaust %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": Color(0.65, 0.65, 0.72),
			"confirm_label": "Exhaust",
			"on_picked": Callable(self, "_apply_exhaust_picks"),
		})

func _apply_exhaust_picks(picks: Array) -> void:
	for pick in picks:
		exhaust_card(pick)
		GameLog.add("Exhausted %s." % pick.get_display_name(), Color(0.7, 0.7, 0.8))
	_refresh_hand()

# Warcry: put N cards from hand on TOP of the draw pile. Player-choice by
# default; `random` skips the picker.
func topdeck_cards(n: int, source_card = null, random: bool = false, from_pile: String = "hand") -> void:
	# `from_pile: "discard"` (Headbutt) pools the pick from the discard pile
	# instead of hand; the played card is mid-resolve and not yet in discard,
	# so it can't pick itself either way.
	if n <= 0:
		return
	var pool: Array
	if from_pile == "discard":
		pool = discard_pile.duplicate()
		pool.erase(source_card)
	else:
		pool = _hand_pool(source_card)
	if pool.is_empty():
		return
	if random:
		var picks: Array = []
		for _i in range(mini(n, pool.size())):
			var pick = pool[randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_topdeck_picks(picks)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Put %d card%s on top of your draw pile" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": Color(0.40, 0.85, 0.45),
			"confirm_label": "Place on top",
			"on_picked": Callable(self, "_apply_topdeck_picks"),
		})

func _apply_topdeck_picks(picks: Array) -> void:
	# draw_cards pops from the BACK of draw_pile, so appending puts the pick on
	# top (the last appended is drawn first). Picks may come from hand (Warcry)
	# or the discard pile (Headbutt); erase from both — a no-op on the other.
	for pick in picks:
		hand.erase(pick)
		discard_pile.erase(pick)
		draw_pile.append(pick)
		GameLog.add("Put %s on top of the draw pile." % pick.get_display_name(),
			Color(0.6, 1.0, 0.7))
	_refresh_hand()

# Storm of Steel: discard the entire hand (minus the played card) and record
# the count for a following conjure `count_from: "discarded"`.
func discard_hand(source_card = null, only: String = "") -> int:
	var doomed: Array = _hand_pool(source_card)
	# `only: "non_attack"` (Unload) spares the Attacks.
	if only == "non_attack":
		var kept: Array = []
		for c in doomed:
			if not (c.has_method("is_attack") and c.is_attack()):
				kept.append(c)
		doomed = kept
	for c in doomed:
		discard_card(c)
	last_discard_count = doomed.size()
	if last_discard_count > 0:
		GameLog.add("Discarded your hand (%d card%s)." % [
			last_discard_count, "s" if last_discard_count > 1 else ""],
			Color(0.9, 0.7, 0.4))
	_refresh_hand()
	return last_discard_count

# Fiend Fire: exhaust the entire hand (minus the played card) and record the
# count for a following dmg `hits_from: "exhausted"` — one hit per card.
func exhaust_hand(source_card = null, only: String = "") -> int:
	var doomed: Array = _hand_pool(source_card)
	# `only: "non_attack"` (Sever Soul) spares the Attacks.
	if only == "non_attack":
		var kept: Array = []
		for c in doomed:
			if not (c.has_method("is_attack") and c.is_attack()):
				kept.append(c)
		doomed = kept
	for c in doomed:
		exhaust_card(c)
	last_exhaust_count = doomed.size()
	if last_exhaust_count > 0:
		GameLog.add("Exhausted your hand (%d card%s)." % [
			last_exhaust_count, "s" if last_exhaust_count > 1 else ""],
			Color(0.7, 0.7, 0.8))
	_refresh_hand()
	return last_exhaust_count

# One shared picker at a time (same contract as DeckbuilderCombat._open_picker):
# tear down any live modal so chained picks can't stack.
func _open_picker(opts: Dictionary) -> void:
	var prev := get_node_or_null("CardPickerModal")
	if prev != null:
		prev.queue_free()
	var modal := CardPickerModal.new()
	modal.name = "CardPickerModal"
	add_child(modal)
	modal.show_picker(opts)

# Move cards between piles, no copies. All for One: recall 0-cost cards from the
# discard pile to hand.
func recall_cards(from_pile: String, to_pile: String, filter: Dictionary) -> void:
	var src: Array = _pile_for(from_pile)
	var dst: Array = _pile_for(to_pile)
	if src == null or dst == null:
		return
	for c in src.duplicate():
		if filter.has("cost") and (c == null or c.get_cost() != int(filter["cost"])):
			continue
		src.erase(c)
		dst.append(c)
	_refresh_hand()

func _pile_for(name: String) -> Array:
	match name:
		"hand": return hand
		"draw": return draw_pile
		"discard": return discard_pile
		"exhaust": return exhaust_pile
		_: return hand

# Upgrade cards in hand (Armaments). `value` is an int count or "all". The int
# form opens the picker (player chooses) unless `random`; "all" is silent.
func upgrade_hand_cards(value, source_card = null, random: bool = false) -> void:
	var eligible: Array = []
	for c in hand:
		# can_take_upgrade keeps sequential cards (Searing Blow) eligible forever.
		if c != source_card and c is CardInstance and c.can_take_upgrade():
			eligible.append(c)
	if eligible.is_empty():
		return
	if str(value) == "all":
		_apply_upgrade_picks(eligible)
		return
	var n: int = int(value)
	if n <= 0:
		return
	if random:
		var picks: Array = []
		for _i in range(mini(n, eligible.size())):
			var pick = eligible[randi() % eligible.size()]
			eligible.erase(pick)
			picks.append(pick)
		_apply_upgrade_picks(picks)
	else:
		var count: int = mini(n, eligible.size())
		_open_picker({
			"title": "Upgrade %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": eligible,
			"count": count,
			"accent": Color(0.6, 0.9, 1.0),
			"confirm_label": "Upgrade",
			"on_picked": Callable(self, "_apply_upgrade_picks"),
		})

func _apply_upgrade_picks(picks: Array) -> void:
	for pick in picks:
		pick.apply_upgrade()
		GameLog.add("Upgraded %s." % pick.get_display_name(), Color(0.6, 0.9, 1.0))
	_refresh_hand()

# Conjure (Blade Dance, Cloak and Dagger, Anger, Pride) — drop `count` copies of
# `card_id` into the named pile (real piles now).
func conjure_card(card_id: StringName, destination: String, count: int, source_card, force_upgraded: bool = false) -> void:
	var data: CardData = null
	var upgraded: bool = false
	if card_id == &"self":
		if source_card is CardInstance:
			data = source_card.data
			upgraded = source_card.upgraded
		elif source_card is CardData:
			data = source_card
	else:
		var id_str: String = String(card_id)
		if id_str.ends_with("+"):
			upgraded = true
			id_str = id_str.substr(0, id_str.length() - 1)
		if force_upgraded:
			upgraded = true
		data = Data.get_card(StringName(id_str))
		if data != null and upgraded and not data.can_upgrade:
			upgraded = false
	if data == null:
		push_warning("conjure_card (strategy): unknown card id '%s'" % card_id)
		return
	for _i in range(maxi(1, count)):
		var copy: CardInstance = CardInstance.from_data(data, upgraded)
		match destination:
			"hand":
				hand.append(copy)
			# draw_cards pops from the BACK of the pile, so appending puts the copy
			# on TOP (drawn next) — what "draw_top" (Pride) wants.
			"draw", "draw_top":
				draw_pile.append(copy)
			"discard":
				discard_pile.append(copy)
			_:
				discard_pile.append(copy)
	# A plain "draw" conjure shuffles in; "draw_top" must stay on top, unshuffled.
	if destination == "draw":
		_shuffle(draw_pile)
	GameLog.add("Conjured %d %s." % [maxi(1, count), data.display_name], Color(0.7, 1.0, 0.7))
	_refresh_hand()

# Random-mint conjure (White Noise / Infernal Blade / Distraction): mint
# `count` random `card_type` cards from the run's conjure pool — the reward
# pool scoped to the deck picked on the New Run screen (Data.conjure_card_pool)
# — into the named pile. `free` makes a hand conjure cost 0 for THIS turn via
# temp_cost_override (the Mummified Hand slot), cleared when the card leaves
# hand. Same contract as the deckbuilder scene.
func conjure_random_card(card_type: String, destination: String, count: int, free: bool, _source_card) -> void:
	var pool: Array = Data.conjure_card_pool(card_type)
	if pool.is_empty():
		push_warning("conjure_random_card (strategy): no %s cards in the conjure pool" % card_type)
		return
	for _i in range(maxi(1, count)):
		var data: CardData = pool[randi() % pool.size()]
		var copy: CardInstance = CardInstance.from_data(data)
		var made_free: bool = free and destination == "hand"
		if made_free:
			copy.temp_cost_override = 0
		match destination:
			"hand":
				hand.append(copy)
			"draw":
				draw_pile.append(copy)
			_:
				discard_pile.append(copy)
		GameLog.add("Conjured %s%s." % [data.display_name,
			" — it costs 0 this turn" if made_free else ""], Color(0.7, 1.0, 0.7))
	if destination == "draw":
		_shuffle(draw_pile)
	_refresh_hand()

func gain_energy(n: int) -> void:
	if n == 0:
		return
	energy += n
	_status_label.text = "Energy +%d (now %d)." % [n, energy]
	_refresh_hand()
	_refresh_button_states()

func lose_energy(n: int) -> void:
	if n <= 0:
		return
	energy = maxi(0, energy - n)
	_refresh_hand()
	_refresh_button_states()

# Mummified Hand: a random OTHER card in hand becomes free this turn.
func make_random_hand_card_free(played_card = null) -> void:
	var cands: Array = []
	for c in hand:
		if c != played_card and c.get_cost() > 0:
			cands.append(c)
	if cands.is_empty():
		return
	var pick = cands[randi() % cands.size()]
	pick.temp_cost_override = 0
	_status_label.text = "Mummified Hand: %s is free this turn!" % pick.get_display_name()
	_refresh_hand()

func reduce_random_card_cost(count: int, amount: int, tag: String, type: String) -> void:
	# Empty Tome: shave `amount` off the cost of `count` random weapon Attack
	# cards in this fight's deck for the rest of the combat. Mirrors the
	# deckbuilder; the discount rides on the CardInstance and is reset in
	# _init_deck / on battle end.
	var pool: Array = []
	for src in [draw_pile, hand, discard_pile]:
		for c in src:
			if c is CardInstance and c.get_cost() > 0 \
					and ItemTriggers.card_matches(c.data, tag, type) and not pool.has(c):
				pool.append(c)
	if pool.is_empty():
		return
	pool.shuffle()
	for i in mini(count, pool.size()):
		var pick: CardInstance = pool[i]
		pick.combat_cost_delta -= amount
	_status_label.text = "Empty Tome: a weapon costs %d less this combat!" % amount
	_refresh_hand()

# ----------------------------------------------------------------------
# Damage / death helpers
# ----------------------------------------------------------------------

func _apply_damage(source, target, raw_dmg: int, effect: Dictionary = {}) -> void:
	if target == null or raw_dmg <= 0:
		return
	var dmg_type: String = String(effect.get("damage_type", "melee"))
	var is_player_attack: bool = (dmg_type == "melee" or dmg_type == "ranged") \
		and source != null and "is_player" in source and source.is_player \
		and not target.is_player
	if is_player_attack:
		raw_dmg += GameState.streak_attack_bonus(target)
	raw_dmg += Stats.vorpal_damage_bonus(effect, target, Stats.Mode.STRATEGY)
	var was_alive: bool = target.is_alive()
	var res := Stats.resolve_damage(source, target, raw_dmg, effect, Stats.Mode.STRATEGY)
	if res.missed:
		var who: String = "You" if source.is_player else source.display_name
		GameLog.add("%s swings blind and misses!" % who, Color(0.85, 0.85, 0.55))
		_float_text(target, "MISS", FloatingNumbers.MISS_COLOR)
		if is_player_attack:
			TriggerBus.emit_signal("attack_missed",
				{"source": source, "target": target, "scene": self})
			_fire_item_triggers("attack_missed", {"target": target})
		return
	if res.dodged:
		return
	target.hp = maxi(0, target.hp - int(res.hp_loss))
	_float_number(target, int(res.hp_loss))
	# Blood for Blood's counter: strategy hits the player UNIT directly (no
	# change_hp until the battle-end sync), so report each HP loss here.
	if target.is_player and int(res.hp_loss) > 0:
		GameState.incremental_on_player_hp_loss()
	# Gold on hit (King Bomber evolution): a connecting player hit on an enemy
	# grants random gold.
	if is_player_attack:
		GameState.gain_gold_on_hit(effect)
	if bool(effect.get("lifesteal", false)) and source != null and source != target \
			and not bool(effect.get("no_reaction", false)) and int(res.hp_loss) > 0:
		heal(source, int(res.hp_loss))
	if target.is_player and int(res.hp_loss) > 0:
		_fire_item_triggers("damage_taken", {"target": target})
	if is_player_attack and target.is_alive():
		TriggerBus.emit_signal("attack_landed",
			{"source": source, "target": target, "scene": self})
		_fire_item_triggers("attack_landed", {"target": target})
	if target.is_alive():
		var oh: Dictionary = Elements.on_hit_status(effect.get("element", ""), target, null)
		if not oh.is_empty():
			apply_status(target, StringName(oh["status"]), int(oh["stacks"]), source)
	# Envenom-style powers: the player's unblocked Attack damage. The victim
	# rides in as the trigger target. Reactions never re-trigger it.
	if int(res.hp_loss) > 0 and is_player_attack \
			and not bool(effect.get("no_reaction", false)):
		_fire_power_triggers("unblocked_attack", {"target": target})
	# Flame Barrier-style triggers: an ENEMY attack that lands on the player
	# (block counts — it's a contact). The attacker rides in as the trigger
	# target so the retaliation dmg (and its Fire -> Burn rider) lands on it.
	if (int(res.hp_loss) > 0 or int(res.blocked) > 0) \
			and target.is_player \
			and source != null and ("is_player" in source) and not source.is_player \
			and (dmg_type == "melee" or dmg_type == "ranged") \
			and not bool(effect.get("no_reaction", false)):
		_fire_power_triggers("hit_by_attack", {"target": source})
	if was_alive and not target.is_alive() and not target.is_player:
		var infuse_stacks: int = int(effect.get("infuse", 0))
		if infuse_stacks > 0 and source != null and "is_player" in source and source.is_player:
			GameState.set_max_hp(GameState.max_hp + infuse_stacks, false)
		_fire_item_triggers("enemy_killed")
		_drop_enemy_loot(target)

# Raw HP loss from a damage-over-time status (Bleed, Leeches) or a curse — bypasses
# block / Weak / Vulnerable and never re-triggers reactions.
func apply_dot(target, amount: int, _source_name: String) -> void:
	if target == null or not target.is_alive() or amount <= 0:
		return
	# Intangible (Wraith Form): each instance of HP loss clamps to 1.
	amount = Stats.intangible_clamp(target, amount)
	target.hp = maxi(0, target.hp - amount)
	_float_number(target, amount)
	# DoT ticks on the player unit count for Blood for Blood too.
	if target.is_player:
		GameState.incremental_on_player_hp_loss()
	if not target.is_alive() and not target.is_player:
		_fire_item_triggers("enemy_killed")
		_drop_enemy_loot(target)

func leech_to_player(amount: int) -> void:
	if amount <= 0:
		return
	var p = get_player_unit()
	if p != null:
		heal(p, amount)

func _drop_enemy_loot(unit) -> void:
	if _battle_map == null:
		return
	var table = _loot_table_for(str(unit.unit_name))
	if table.is_empty():
		return
	# Enemies drop gold only — never items.
	var pos: Vector2i = unit.position
	if _loot_rng.randf() < float(table.gold_chance):
		var amt: int = _loot_rng.randi_range(int(table.gold_min), int(table.gold_max))
		_battle_map.add_dropped_item(StrategyItem.make_gold(pos, amt), pos)
	_grid_view.notify_units_changed()

func _check_battle_end_after_effect() -> void:
	if _turn_manager != null:
		_turn_manager.check_battle_end_now()

# Register handler for the custom max-HP-fraction damage type (SPELLS_DATA
# spells) — idempotent, mirrors the deckbuilder.
func _enter_tree() -> void:
	EffectSystem.register("dmg_fraction_max_hp", _h_dmg_fraction_max_hp)

func _h_dmg_fraction_max_hp(effect: Dictionary, ctx: Dictionary) -> void:
	var target = ctx.get("target")
	if target == null:
		return
	var raw: int = int(round(target.max_hp * float(effect.get("value", 0))))
	deal_damage(ctx.get("source"), target, raw, effect)

# ----------------------------------------------------------------------
# Items: the active-item picker
# ----------------------------------------------------------------------

func _on_item_button() -> void:
	if not _is_player_turn():
		return
	_clear_pending()
	_grid_view.enter_idle()
	_populate_item_picker()
	_item_dialog.visible = true

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
		_refresh_hand()
		_refresh_button_states()
	else:
		_status_label.text = "%s isn't ready yet." % item.display_name

func _close_item_dialog() -> void:
	_item_dialog.visible = false

# --- Loot (potions): drink / throw, no action cost ---------------------

func _build_loot_dialog() -> void:
	var p := Panel.new()
	p.position = Vector2(922, 74)
	p.size = Vector2(352, 560)
	p.add_theme_stylebox_override("panel", _panel_stylebox(Color(0.1, 0.08, 0.15, 0.99), ACCENT, 2, 12))
	var t := Label.new()
	t.text = "Loot"
	t.position = Vector2(16, 12)
	t.size = Vector2(320, 30)
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(0.7, 0.6, 0.95))
	p.add_child(t)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(14, 48)
	scroll.size = Vector2(324, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)
	_loot_list_container = vbox
	var close := _make_button("Close", 126, 516, 100, 36, _close_loot_dialog)
	p.add_child(close)
	add_child(p)
	p.visible = false
	_loot_dialog = p

func _refresh_loot_button() -> void:
	if _btn_loot != null:
		_btn_loot.text = "Loot (%d)" % GameState.get_loot_count("potion")
	if _loot_dialog != null and _loot_dialog.visible:
		_populate_loot_picker()

func _on_loot_button() -> void:
	if not _is_player_turn():
		return
	_clear_pending()
	_grid_view.enter_idle()
	_populate_loot_picker()
	_loot_dialog.visible = true

func _close_loot_dialog() -> void:
	if _loot_dialog != null:
		_loot_dialog.visible = false

# (loot_items index, entry) pairs for each carried potion.
func _potion_loot_entries() -> Array:
	var out: Array = []
	for i in range(GameState.loot_items.size()):
		var e = GameState.loot_items[i]
		if e is Dictionary and String(e.get("type", "")) == "potion":
			out.append({"index": i, "entry": e})
	return out

func _populate_loot_picker() -> void:
	if _loot_list_container == null:
		return
	for child in _loot_list_container.get_children():
		child.queue_free()
	var entries: Array = _potion_loot_entries()
	if entries.is_empty():
		_loot_list_container.add_child(_picker_note(
			"No potions. Potions you find on the floor or buy show up here."))
		return
	for item in entries:
		_loot_list_container.add_child(_make_loot_row(int(item["index"]), item["entry"]))

func _make_loot_row(loot_index: int, entry: Dictionary) -> Control:
	var potion: PotionData = Data.get_potion(StringName(entry.get("id", "")))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if potion != null:
		icon.texture = PotionSystem.art_texture(potion)
	row.add_child(icon)
	var lbl := Label.new()
	var detail: String = potion.effect_text if (potion != null and PotionSystem.is_identified(potion.id)) else "Unidentified"
	lbl.text = "%s  —  %s" % [PotionSystem.display_name(potion) if potion != null else "Potion", detail]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	var drink := Button.new()
	drink.text = "Drink"
	drink.pressed.connect(_on_drink_potion.bind(loot_index))
	row.add_child(drink)
	var throw := Button.new()
	throw.text = "Throw"
	throw.pressed.connect(_on_throw_potion.bind(loot_index))
	row.add_child(throw)
	return row

func _on_drink_potion(loot_index: int) -> void:
	if not _is_player_turn():
		return
	var potion: PotionData = _potion_at(loot_index)
	if potion == null:
		return
	var u = get_player_unit()
	var ctx := {"source": u, "scene": self, "mode": Stats.Mode.STRATEGY, "rng": _loot_rng}
	var logs: Array = PotionSystem.apply_to_target(potion, u, ctx)
	for line in logs:
		GameLog.add(line, PotionSystem.POTION_COLOR)
	PotionSystem.identify(potion.id)
	PotionSystem.notify_used(potion, "(drank)")
	GameState.remove_loot_at(loot_index)
	_after_potion_used()
	_check_battle_end_after_effect()  # a self-damage drink can drop you to 0
	_populate_loot_picker()

func _on_throw_potion(loot_index: int) -> void:
	if not _is_player_turn():
		return
	var potion: PotionData = _potion_at(loot_index)
	if potion == null:
		return
	_close_loot_dialog()
	_clear_pending()
	var u = get_player_unit()
	if u == null:
		return
	# Reuse the grid's aim UI: a tile-aimed "disc" gated to throw range, with a
	# manhattan footprint (plus for normal, radius-2 diamond for cleave).
	var spec := {
		"family": "disc",
		"aim": "tile",
		"range_tiles": PotionSystem.throw_range(),
		"radius": (2 if potion.cleave else 1),
		"manhattan": true,
		"rotates": false,
	}
	_pending_kind = Pending.POTION_AIM
	_pending_potion_index = loot_index
	_pending_aim_spec = spec
	_grid_view.set_active_unit(u, u.move_range)
	_grid_view.enter_aim_mode(spec)
	_status_label.text = "Throw %s — aim within range (right-click to cancel)." % PotionSystem.display_name(potion)

# Resolve a thrown potion's splash at `pos` (called from _on_aim_confirmed).
func _resolve_potion_throw(pos: Vector2i) -> void:
	var potion: PotionData = _potion_at(_pending_potion_index)
	var loot_index: int = _pending_potion_index
	if potion == null:
		_clear_pending()
		_grid_view.enter_idle()
		return
	var targets: Array = _shaped_targets_for(_pending_aim_spec, get_player_unit(), pos)
	var ctx := {"source": get_player_unit(), "scene": self, "mode": Stats.Mode.STRATEGY, "rng": _loot_rng}
	var logs: Array = PotionSystem.apply_to_targets(potion, targets, ctx)
	for line in logs:
		GameLog.add(line, PotionSystem.POTION_COLOR)
	PotionSystem.identify(potion.id)
	PotionSystem.notify_used(potion, "(thrown)")
	GameState.remove_loot_at(loot_index)
	_clear_pending()
	_grid_view.enter_idle()
	_after_potion_used()
	_check_battle_end_after_effect()

func _potion_at(loot_index: int) -> PotionData:
	if loot_index < 0 or loot_index >= GameState.loot_items.size():
		return null
	var e = GameState.loot_items[loot_index]
	if not (e is Dictionary) or String(e.get("type", "")) != "potion":
		return null
	return Data.get_potion(StringName(e.get("id", "")))

func _after_potion_used() -> void:
	_grid_view.notify_units_changed()
	_refresh_initiative()
	_refresh_hand()
	_refresh_button_states()
	_refresh_loot_button()

# Potion adapter hook (PotionSystem energy op). Strategy has energy, so grant it.
func potion_grant_energy(amount: int) -> bool:
	energy += amount
	_refresh_readout()
	return true

# Player HP changes hit the live unit (the combat truth, synced back to the
# overworld entity at combat end). Self-damage from drinking a harmful potion
# therefore sticks.
func potion_player_hp_delta(delta: int) -> void:
	var u = get_player_unit()
	if u != null:
		u.hp = clampi(u.hp + delta, 0, u.max_hp)
		if _grid_view != null:
			_grid_view.notify_units_changed()

# Fruit Juice's Max HP gain is permanent and SHARED across the run: bump the live
# unit, the overworld StrategyEntity (seeded from GameState), and the shared
# GameState pool so the gain shows everywhere and survives the combat.
func potion_player_maxhp_delta(delta: int) -> void:
	var u = get_player_unit()
	if u != null:
		u.max_hp = maxi(1, u.max_hp + delta)
		u.hp = clampi(u.hp + delta, 0, u.max_hp)
	GameState.change_max_hp(delta)
	GameState.change_hp(delta)
	if StrategyState.player != null:
		StrategyState.player.max_hp = maxi(1, StrategyState.player.max_hp + delta)
		StrategyState.player.hp = clampi(StrategyState.player.hp + delta, 0, StrategyState.player.max_hp)
	if _grid_view != null:
		_grid_view.notify_units_changed()

func _has_usable_item() -> bool:
	for item in GameState.inventory:
		if item is ItemData and GameState.can_fire_item(item):
			return true
	return false

func _picker_note(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return l

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
	_btn_dash.disabled = not enabled
	_btn_item.disabled = not enabled
	_btn_end.disabled = not enabled
	if enabled:
		_refresh_button_states()

func _refresh_button_states() -> void:
	if not _is_player_turn():
		return
	var u = _turn_manager.current_unit
	_btn_move.disabled = energy <= 0
	_btn_dash.disabled = not u.dash_available
	_btn_item.disabled = not _has_usable_item()
	_btn_end.disabled = false

func _refresh_initiative() -> void:
	if _turn_manager == null:
		_initiative_label.text = ""
		return
	var lines: Array = ["Round %d" % _turn_manager.round_num, ""]
	var cur = _turn_manager.current_unit
	for u in _turn_manager.units:
		var marker = ">" if u == cur else " "
		var dead = "" if u.is_alive() else " [DEAD]"
		var block = ""
		if u.block > 0:
			block = "  blk %d" % u.block
		lines.append("%s %-8s hp %d/%d  mv %d  ctr %d%s%s" % [
			marker, u.unit_name, u.hp, u.max_hp, u.move_range,
			u.act_counter, block, dead,
		])
		if u.is_alive() and not u.is_player and not u.intent_telegraph.is_empty():
			var tel: Dictionary = u.intent_telegraph
			var lbl: String = str(tel.get("label", ""))
			if lbl == "" and int(tel.get("value", 0)) > 0:
				lbl = str(int(tel.get("value", 0)))
			# Live re-prediction, same as the grid badge (see EnemyAI.telegraph_label).
			if u.ai != null and u.ai.has_method("telegraph_label"):
				var live: String = u.ai.telegraph_label()
				if live != "":
					lbl = live
			var tail: String = " (%s)" % lbl if lbl != "" else ""
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
	return "Encounter: %s   |   Field: %s (%s)   |   Deck: %d cards" % [
		enc_str, size_name, dims, GameState.deck.size(),
	]

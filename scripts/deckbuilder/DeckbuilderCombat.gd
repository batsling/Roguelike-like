class_name DeckbuilderCombat
extends Control

# Phase 1a deckbuilder combat. Owns per-combat state, runs turn lifecycle,
# resolves card play through the EffectSystem, applies damage/block with
# the full status math (Vulnerable, Weak, Frail, Power, Defense, etc.)
# matching the JS combat-engine rules.
#
# Entry point: pass an Array of EnemyData (or ids) via `enemies_to_spawn`
# before adding to tree, or use `start_combat(enemies)` after _ready.
#
# Enemy AI execution lives in the next commit (commit 7); for now the
# enemy plans a move on turn start but does not execute it.

signal combat_ended(victory: bool)
signal closed(was_victory: bool, target_game_id: StringName)

# Configuration set by the caller before _ready (or via start_combat).
var enemies_to_spawn: Array = []
var target_game_id: StringName = &""
# Elite combats bump enemy HP, give the enemy a starting Power, and pay
# out a larger gold reward. Set by GameMap before add_child.
var is_elite: bool = false

# Tuning constants for the elite multiplier — easy to dial in one place.
const ELITE_HP_MULT := 1.5
const ELITE_POWER_BONUS := 3
const ELITE_GOLD_MULT := 1.5

# ------------------------------------------------------------------
# Combat state — referenced by EffectSystem handlers via ctx.scene
# ------------------------------------------------------------------
var player: CombatActor = null
var enemies: Array[CombatActor] = []

# Pre-combat event carryover. "ambush" (the player got the drop) draws two
# extra cards on turn 1; "ambushed" (the enemy did) draws two fewer. Set from
# GameState.pending_ambush at combat start and spent on the opening hand.
var _ambush_draw_delta: int = 0

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
var exhaust_pile: Array[CardInstance] = []

# Persistent in-combat modifiers registered by `boost_cards` effects.
# Each entry: {match_tag, match_type, match_id, stat, value}. Consulted
# in `_resolve_card` so the bonus folds into the effect's value before
# dispatch. Cleared at the start of each combat.
var card_boosts: Array = []

# Persistent in-combat listeners registered by `trigger` effects
# (After Image, Demon Form, etc). Each entry: {on, effect}. The combat
# emit sites call `_fire_power_triggers(name, ctx_extras)` which walks
# this list and routes matching ones through EffectSystem. Cleared at
# combat start.
var power_triggers: Array = []

# Consecutive-hit streaks (Dead Eye) now live on GameState so every combat
# mode shares them; see GameState.streak_* . deal_damage folds the bonus in via
# GameState.streak_attack_bonus and the attack_landed/attack_missed triggers
# grow/reset it through EffectSystem.

var energy: int = 0
var max_energy: int = 3
# Ice Cream: energy left unspent at end of turn, re-added at the start of the
# next turn (can push energy above max_energy). Cleared at combat start.
var _energy_carryover: int = 0
var turn: int = 0
enum Phase { INIT, PLAYER, ENEMY, WON, LOST }
var phase: Phase = Phase.INIT

# Persistent enemy view widgets (created in start_combat, refreshed by
# _refresh_ui without rebuilding the row).
var _enemy_views: Array[EnemyView] = []
var _hand_views: Array[CardView] = []

# Targeting mode (card selected, waiting for enemy click)
var _selected_card: CardInstance = null
var _selected_item: ItemData = null
var _targeting: bool = false
# Following arrow shown while choosing an enemy target for a card.
var _targeting_arrow: TargetingArrow = null

# Drag-to-play state. _drag_card is the CardInstance being dragged; _drag_ghost
# is a floating CardView clone that follows the cursor (mirrors the HTML build's
# drag clone). Both null when no drag is in progress.
var _drag_card: CardInstance = null
var _drag_ghost: CardView = null
var _drag_hover_enemy: EnemyView = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Status decay list and the Persistence-debuff set both live on Stats now
# (Stats.PERSISTENCE_DEBUFFS / Stats.status_apply_stacks), shared across all
# three combat modes.

# UI refs
@onready var _enemy_area: HBoxContainer = $Layout/Battlefield/EnemyArea
@onready var _player_portrait: TextureRect = $Layout/Battlefield/PlayerArea/PlayerPortrait
@onready var _player_name: Label = $Layout/Battlefield/PlayerArea/PlayerName

# Player HP bar + status badges shown under the portrait (mirrors the enemy
# panels). Built procedurally in _build_player_view, refreshed in _refresh_ui.
var _player_hp_bar: ProgressBar = null
var _player_hp_overlay: Label = null
var _player_status_row: HBoxContainer = null
@onready var _hand_area: HBoxContainer = $Layout/Bottom/HandRow/HandArea
@onready var _end_turn_btn: Button = $Layout/Bottom/HandRow/EndTurnButton
@onready var _energy_label: Label = $Layout/Bottom/StatusBar/EnergyLabel
@onready var _hp_label: Label = $Layout/Bottom/StatusBar/HPLabel
@onready var _draw_btn: Button = $Layout/Bottom/StatusBar/DrawButton
@onready var _discard_btn: Button = $Layout/Bottom/StatusBar/DiscardButton
@onready var _exhaust_btn: Button = $Layout/Bottom/StatusBar/ExhaustButton
@onready var _block_label: Label = $Layout/Bottom/StatusBar/BlockLabel
@onready var _turn_label: Label = $Layout/Top/TurnLabel

func _ready() -> void:
	_rng.randomize()
	# Targeting arrow overlay (added last so it draws on top; ignores mouse so
	# enemy clicks still land).
	_targeting_arrow = TargetingArrow.new()
	add_child(_targeting_arrow)
	_end_turn_btn.pressed.connect(_on_end_turn)
	_draw_btn.pressed.connect(_on_pile_clicked.bind("draw"))
	_discard_btn.pressed.connect(_on_pile_clicked.bind("discard"))
	_exhaust_btn.pressed.connect(_on_pile_clicked.bind("exhaust"))
	_build_inventory_panel()
	# Pre-combat event used to fire here; events now live as dedicated
	# map nodes in the deckbuilder mini-map (Phase 2). Combat starts
	# immediately as long as the caller pre-populated enemies_to_spawn.
	if not enemies_to_spawn.is_empty():
		start_combat(enemies_to_spawn)

# On-screen item rack, pinned to the top of the screen above the battlefield
# (its own CanvasLayer so it draws over the combat UI, like the HTML inventory).
func _build_inventory_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.offset_top = 4
	layer.add_child(bar)
	var inv := CombatInventory.new()
	inv.columns = 12
	inv.tile_px = 40
	inv.show_title = false
	inv.on_use_requested = _on_item_use_requested
	bar.add_child(inv)

func start_combat(spawn_list: Array) -> void:
	# Fold any event-queued extra enemies (e.g. a fruit-fly swarm) into the
	# encounter before actors are built.
	_init_actors(_append_pending_spawns(spawn_list))
	_init_deck()
	_apply_derived_statuses()
	# Register the live context so the backpack can fire consumables into
	# this fight; the player CombatActor is the use target.
	GameState.set_combat_context(self, player)
	_build_player_portrait()
	_build_enemy_views()
	turn = 0
	max_energy = GameState.max_energy
	GameState.phase = GameState.Phase.COMBAT
	TriggerBus.emit_signal("combat_started", {"scene": self})
	_fire_item_triggers("combat_started")
	_fire_power_triggers("combat_started")
	_apply_event_ambush()
	_start_player_turn()

# Consumes GameState.pending_ambush into a turn-1 draw modifier: "ambush" adds
# two cards to the opening hand, "ambushed" removes two.
func _apply_event_ambush() -> void:
	match GameState.pending_ambush:
		"ambush":
			_ambush_draw_delta = 2
			GameLog.add("Ambush! You catch them off guard — draw 2 extra cards.", Color(0.7, 1.0, 0.7))
		"ambushed":
			_ambush_draw_delta = -2
			GameLog.add("Ambushed! Caught off guard — you draw 2 fewer cards.", Color(1.0, 0.6, 0.6))
	GameState.pending_ambush = ""

# Pulls queued event spawns (Array of {enemy, count}) into the spawn list and
# clears the queue so they fire exactly once, for the next combat only.
func _append_pending_spawns(spawn_list: Array) -> Array:
	if GameState.pending_spawn_enemies.is_empty():
		return spawn_list
	var combined: Array = spawn_list.duplicate()
	for entry in GameState.pending_spawn_enemies:
		var id: StringName = StringName(String(entry.get("enemy", "")))
		var count: int = int(entry.get("count", 0))
		for _i in range(count):
			combined.append(id)
	GameState.pending_spawn_enemies.clear()
	return combined

# Shows the player character's full art on the left of the battlefield, facing
# the enemy row. Pulls the portrait off the chosen CharacterData.
func _build_player_portrait() -> void:
	if _player_portrait == null:
		return
	var cd: CharacterData = Data.get_character(GameState.character_id)
	if cd != null:
		_player_portrait.texture = cd.portrait if cd.portrait != null else cd.icon
		_player_name.text = cd.display_name
	else:
		_player_name.text = "You"
	_build_player_view()

# Adds an HP bar (with an "x / y" overlay) and a status-badge row under the
# player portrait so the player can see their own HP / Weak / Frail / Blind /
# Block at a glance, the same way enemy panels do.
func _build_player_view() -> void:
	if _player_status_row != null:
		return
	var area: Node = _player_portrait.get_parent()
	if area == null:
		return

	var hp_holder := Control.new()
	hp_holder.custom_minimum_size = Vector2(0, 20)
	hp_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(hp_holder)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_bar.show_percentage = false
	_player_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.7, 0.35)
	_player_hp_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.05, 0.05)
	_player_hp_bar.add_theme_stylebox_override("background", bg)
	hp_holder.add_child(_player_hp_bar)

	_player_hp_overlay = Label.new()
	_player_hp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_hp_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_hp_overlay.add_theme_font_size_override("font_size", 11)
	_player_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_holder.add_child(_player_hp_overlay)

	_player_status_row = HBoxContainer.new()
	_player_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_player_status_row.custom_minimum_size = Vector2(0, 24)
	_player_status_row.add_theme_constant_override("separation", 4)
	_player_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(_player_status_row)

func _refresh_player_view() -> void:
	if player == null or _player_hp_bar == null:
		return
	_player_hp_bar.max_value = maxi(1, player.max_hp)
	_player_hp_bar.value = player.hp
	if player.block > 0:
		_player_hp_overlay.text = "%d / %d   BLK %d" % [player.hp, player.max_hp, player.block]
	else:
		_player_hp_overlay.text = "%d / %d" % [player.hp, player.max_hp]
	for c in _player_status_row.get_children():
		c.queue_free()
	for s in player.statuses.keys():
		var stacks: int = int(player.statuses[s])
		if stacks <= 0:
			continue
		_player_status_row.add_child(_make_status_badge(s, stacks))

# Small status icon + stack-count badge, mirroring EnemyView's. Falls back to a
# coloured letter when a status has no icon art.
func _make_status_badge(status_name, stacks: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(22, 22)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.tooltip_text = "%s %d" % [String(status_name).capitalize(), stacks]
	var tex: Texture2D = Stats.status_icon(status_name)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(icon)
	else:
		var letter := Label.new()
		letter.text = String(status_name).substr(0, 1).to_upper()
		letter.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", 12)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(letter)
	var count := Label.new()
	count.text = str(stacks)
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 3)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(count)
	return holder

func _build_enemy_views() -> void:
	for child in _enemy_area.get_children():
		child.queue_free()
	_enemy_views.clear()
	for i in range(enemies.size()):
		var view := EnemyView.new()
		var idx: int = i
		view.clicked.connect(func(): _on_enemy_clicked(idx))
		# add_child first so _ready builds the panel before setup() runs.
		_enemy_area.add_child(view)
		view.setup(enemies[i])
		_enemy_views.append(view)

# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

func _init_actors(spawn_list: Array) -> void:
	player = CombatActor.from_player()
	enemies.clear()
	for entry in spawn_list:
		var d: EnemyData = null
		if entry is EnemyData:
			d = entry
		elif entry is StringName or entry is String:
			d = Data.get_enemy(StringName(entry))
		if d != null:
			var actor: CombatActor = CombatActor.from_enemy(d, _rng)
			if is_elite:
				# Bump HP and grant a starting Power. Elite-specific
				# enemy data with bespoke patterns lands later.
				var bumped: int = int(actor.max_hp * ELITE_HP_MULT)
				actor.max_hp = bumped
				actor.hp = bumped
				actor.add_status(&"power", ELITE_POWER_BONUS)
			enemies.append(actor)

func _init_deck() -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	card_boosts.clear()
	power_triggers.clear()
	GameState.streak_clear()
	_energy_carryover = 0
	for c in GameState.deck:
		if c is CardData:
			draw_pile.append(CardInstance.from_data(c))
		elif c is CardInstance:
			draw_pile.append(c)
	_shuffle(draw_pile)
	_promote_innate()

# Innate: cards flagged innate start in the opening hand. draw_cards pulls
# from the BACK of draw_pile (pop_back), so moving the innate cards to the
# end after shuffling guarantees they're the first cards drawn on turn 1.
# Order among innate cards themselves is preserved. If more cards are innate
# than the opening hand size, the overflow stays on top and is simply drawn
# first on later turns — matching the "place on top of deck" wording.
func _promote_innate() -> void:
	var innate: Array[CardInstance] = []
	var rest: Array[CardInstance] = []
	for ci in draw_pile:
		if ci != null and ci.data != null and ci.data.innate:
			innate.append(ci)
		else:
			rest.append(ci)
	if innate.is_empty():
		return
	rest.append_array(innate)
	draw_pile = rest

func _apply_derived_statuses() -> void:
	# Stats autoload owns the universal derived statuses + drains
	# pending event statuses. Per-stat balance changes happen in the
	# StatDefinition .tres files, not here.
	Stats.apply_derived_statuses(player, Stats.Mode.DECKBUILDER)

# ------------------------------------------------------------------
# Turn lifecycle
# ------------------------------------------------------------------

func _start_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER
	energy = max_energy
	# Ice Cream: pour last turn's leftover energy on top (may exceed max).
	if _energy_carryover > 0:
		energy += _energy_carryover
		GameLog.add("Ice Cream: +%d bonus energy!" % _energy_carryover, Color(0.7, 1.0, 0.7))
		_energy_carryover = 0
	player.block = 0
	_cancel_targeting()
	# Pre-roll enemy intents for this turn
	for e in enemies:
		if e.is_alive():
			_roll_intent(e)
	var draw_count: int = GameState.hand_size
	if turn == 1:
		# Speed grants extra cards on the opening hand only.
		draw_count += Stats.deckbuilder_bonus_draws_turn_1()
		# Ambush carryover adjusts the opening hand (+2 ambush / -2 ambushed).
		draw_count += _ambush_draw_delta
	draw_cards(maxi(0, draw_count))
	TriggerBus.emit_signal("turn_started", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_started")
	_fire_power_triggers("turn_started")
	# Recurring turn heartbeat (here it coincides with turn start; Action runs
	# it off a timer). Drives Happy Flower + the per-turn attack-window reset.
	TriggerBus.emit_signal("turn_tick", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_tick")
	# Deckbuilder charges EVERY charged active each turn.
	GameState.charge_all_items(1)
	_refresh_ui()

func _on_end_turn() -> void:
	if phase != Phase.PLAYER:
		return
	_cancel_targeting()
	# Snapshot the curse cards in hand (and the hand size, for Regret) BEFORE
	# discard. Their eot effects are applied AFTER status decay below, so a
	# status they grant (Doubt -> Weak) survives into the next turn instead of
	# being decayed away the instant it's applied.
	var eot_curses: Array = hand.duplicate()
	var eot_hand_size: int = hand.size()
	# Ice Cream: bank whatever energy is still unspent for next turn.
	if energy > 0 and GameState.has_energy_carryover_item():
		_energy_carryover = energy
	# Discard hand. Ethereal cards exhaust instead of discarding if they
	# would still be in hand at end of turn (Carnage). Retain cards stay
	# in hand. The TriggerBus emit lets items react to each exhausted
	# card (mirrors the deckbuilder's normal exhaust_card flow).
	var kept: Array[CardInstance] = []
	while not hand.is_empty():
		var c: CardInstance = hand.pop_back()
		# Mummified Hand's "free this turn" discount expires now (clear it on
		# every card leaving hand, retained ones included).
		c.temp_cost_override = -999
		if c.data != null and c.data.retain:
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
	TriggerBus.emit_signal("turn_ended", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_ended")
	_fire_power_triggers("turn_ended")
	# Per-turn DoT tick (Bleed today) BEFORE decay so the bite uses
	# the carried stack count, then grow/decay applies.
	Stats.tick_actor_statuses(player, self)
	# Decay player statuses BEFORE enemies act so debuffs the player
	# just applied to enemies survive through the enemy turn.
	_decay_statuses(player)
	# Curse cards' end-of-turn effects land here — AFTER decay — so a status they
	# grant the player (Doubt -> Weak, Punctured Eye -> Blind) persists to the next
	# turn. HP-loss curses (Decay/Regret) resolve here too; a lethal one is caught
	# by the combat-end check just below.
	_fire_curse_triggers("eot", eot_curses, eot_hand_size)
	phase = Phase.ENEMY
	_refresh_ui()

	if _check_combat_end():
		return

	_execute_enemy_turn()

	if _check_combat_end():
		return

	# Enemies tick and decay after their actions.
	for e in enemies:
		if e.is_alive():
			Stats.tick_actor_statuses(e, self)
			_decay_statuses(e)

	# An enemy may have died from their own Bleed tick — re-check.
	if _check_combat_end():
		return

	_start_player_turn()

func _execute_enemy_turn() -> void:
	for enemy in enemies:
		if not enemy.is_alive() or not player.is_alive():
			continue
		# Block resets at the start of the enemy's own action phase
		# (matches JS rules; Barricade-style persistence deferred).
		enemy.block = 0
		var move: Dictionary = enemy.planned_move
		if move.is_empty():
			continue
		GameLog.add("%s: %s" % [enemy.display_name, move.get("display", "?")],
			Color(0.9, 0.8, 0.6))
		var effects: Array = move.get("effects", [])
		for effect in effects:
			if not enemy.is_alive() or not player.is_alive():
				break
			var tgt: CombatActor = _resolve_enemy_effect_target(enemy, effect.get("target", "player"))
			var ctx := {
				"source": enemy,
				"target": tgt,
				"scene": self,
				"card": null,
			}
			EffectSystem.apply(effect, ctx)

func _resolve_enemy_effect_target(enemy: CombatActor, target_str: String) -> CombatActor:
	match target_str:
		"player":
			return player
		"self":
			return enemy
		_:
			return player

func _check_combat_end() -> bool:
	if phase == Phase.WON or phase == Phase.LOST:
		return true
	if not player.is_alive():
		phase = Phase.LOST
		GameState.phase = GameState.Phase.DEAD
		GameLog.add("You have been defeated.", Color(1.0, 0.4, 0.4))
		TriggerBus.emit_signal("combat_ended", {"victory": false, "scene": self})
		emit_signal("combat_ended", false)
		# Consumable buffs last one combat — drop them and the live context.
		GameState.clear_combat_context()
		GameState.clear_temp_buffs()
		_show_end_overlay(false)
		_refresh_ui()
		return true
	var any_alive := false
	for e in enemies:
		if e.is_alive():
			any_alive = true
			break
	if not any_alive:
		phase = Phase.WON
		GameLog.add("Victory!", Color(0.4, 1.0, 0.6))
		# Items with combat_ended triggers fire on victory only.
		_fire_item_triggers("combat_ended")
		TriggerBus.emit_signal("combat_ended", {"victory": true, "scene": self})
		emit_signal("combat_ended", true)
		_award_combat_gold()
		# Consumable buffs last one combat — drop them and the live context.
		GameState.clear_combat_context()
		GameState.clear_temp_buffs()
		_refresh_ui()
		_show_reward_modal()
		return true
	return false

# Gold reward tiers match the JS combat-flow (20 / 35 / 55g) keyed on
# total_games_beaten so harder runs pay better. Elite multiplier lands
# alongside the elite floor in Phase 2 commit 10.
var _last_gold_award: int = 0

func _award_combat_gold() -> void:
	var amt: int = 20
	if GameState.total_games_beaten >= 10:
		amt = 55
	elif GameState.total_games_beaten >= 5:
		amt = 35
	if is_elite:
		amt = int(amt * ELITE_GOLD_MULT)
	_last_gold_award = amt
	GameState.change_gold(amt)
	GameLog.add("You loot %d gold." % amt, Color(1.0, 0.9, 0.3))

# ------------------------------------------------------------------
# Item triggers — declarative ItemData.triggers fan-out
# ------------------------------------------------------------------

func _fire_item_triggers(trigger_name: String, ctx_extras: Dictionary = {}) -> void:
	# Delegates to the shared runner so every combat mode fires items the same
	# way. ctx_extras forwards the played card / its target for card_played.
	ItemTriggers.fire(trigger_name, self, player, enemies, ctx_extras, turn)

# ------------------------------------------------------------------
# End-of-combat overlay
# ------------------------------------------------------------------

var _end_overlay: Control = null

func _show_end_overlay(victory: bool) -> void:
	if _end_overlay != null:
		return
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(480, 260)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	overlay.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 24)
	title.size = Vector2(440, 48)
	title.text = "VICTORY!" if victory else "DEFEAT"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if victory else Color(1.0, 0.5, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var info := Label.new()
	info.position = Vector2(20, 92)
	info.size = Vector2(440, 60)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	if victory:
		info.text = "HP %d / %d   Turn %d" % [GameState.hp, GameState.max_hp, turn]
	else:
		info.text = "The run ends. Restart to try again."
	panel.add_child(info)

	var btn := Button.new()
	btn.position = Vector2(120, 180)
	btn.size = Vector2(240, 56)
	btn.text = "Next combat" if victory else "Restart run"
	btn.pressed.connect(func(): _close(victory))
	panel.add_child(btn)

	add_child(overlay)
	_end_overlay = overlay

func _close(was_victory: bool) -> void:
	emit_signal("closed", was_victory, target_game_id)
	queue_free()

# ------------------------------------------------------------------
# Card reward modal — shown after victory, before the end overlay.
# ------------------------------------------------------------------

var _reward_modal: Node = null

func _show_reward_modal() -> void:
	if _reward_modal != null:
		return
	# No offerable cards (empty pool) — skip straight to the victory overlay.
	if Data.reward_card_pool().is_empty():
		_show_end_overlay(true)
		return
	# Shared card-reward UI (rolling, selection, reroll, skip, deck-add all
	# live in CardRewardScreen). Hosted on its own layer above the combat.
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var reward := CardRewardScreen.new()
	layer.add_child(reward)
	_reward_modal = layer
	reward.closed.connect(func():
		if _reward_modal != null:
			_reward_modal.queue_free()
			_reward_modal = null
		_close(true))
	# Scope the offered cards to the player's class (e.g. Ironclad sees
	# ironclad-tagged cards) via the character's class tag. Empty tag (no class
	# pool) falls back to the full reward pool inside reward_card_pool().
	reward.setup(GameState.card_reward_tag())

func _decay_statuses(actor: CombatActor) -> void:
	Stats.decay_actor_statuses(actor)

# ------------------------------------------------------------------
# Card play
# ------------------------------------------------------------------

# Energy a card costs to play right now, including the Fear surcharge
# (+1 per non-Skill card while the player is afraid). All play-time cost gates
# and the energy deduction route through this so the number the player is
# charged matches what the hand shows. CardInstance.get_cost() stays the card's
# own context-free cost (used by shop / rest / collection).
func _card_cost(card: CardInstance) -> int:
	return card.get_cost() + Stats.fear_card_surcharge(player, card)

func _try_play_card(card: CardInstance) -> void:
	if phase != Phase.PLAYER:
		return
	if _card_cost(card) > energy:
		GameLog.add("Not enough energy for %s." % card.get_display_name(), Color(0.9, 0.7, 0.3))
		return
	# If we're already targeting and the same card is clicked, cancel.
	if _targeting and _selected_card == card:
		_cancel_targeting()
		return
	if card.wants_target():
		_selected_card = card
		_targeting = true
		if _targeting_arrow != null:
			# Stem the arrow from the played card itself (top-center of its
			# hand view) so it visibly originates from the card.
			_targeting_arrow.start(_card_arrow_origin(card))
		GameLog.add("Choose a target for %s." % card.get_display_name(), Color(0.7, 0.9, 1.0))
		_refresh_ui()
	else:
		_resolve_card(card, null)

func _on_enemy_clicked(idx: int) -> void:
	if not _targeting:
		return
	if idx < 0 or idx >= enemies.size():
		return
	var tgt: CombatActor = enemies[idx]
	if not tgt.is_alive():
		return
	if _selected_item != null:
		var item := _selected_item
		_cancel_targeting()
		if GameState.use_item(item, tgt):
			GameLog.add("Used %s on %s." % [item.display_name, tgt.display_name],
				Color(0.85, 0.9, 1.0))
		return
	if _selected_card == null:
		return
	var card := _selected_card
	_cancel_targeting()
	_resolve_card(card, tgt)

# Global point the targeting arrow stems from: the top-center (edge facing the
# enemies) of the played card's hand view. Falls back to the hand row's
# bottom-center if the view can't be located.
func _card_arrow_origin(card: CardInstance) -> Vector2:
	for view in _hand_views:
		if view.card == card:
			var r: Rect2 = view.get_global_rect()
			return Vector2(r.position.x + r.size.x * 0.5, r.position.y)
	return global_position + Vector2(size.x * 0.5, size.y - 80.0)

func _cancel_targeting() -> void:
	_selected_card = null
	_selected_item = null
	_targeting = false
	if _targeting_arrow != null:
		_targeting_arrow.stop()
	_refresh_ui()

# Use button on the item rack. Enemy-aimed items (potions that throw at a foe)
# pop the targeting arrow and resolve on the next enemy click; everything else
# fires immediately. Mirrors the card targeting flow.
func _on_item_use_requested(item: ItemData, origin: Vector2) -> void:
	if phase != Phase.PLAYER:
		return
	if not GameState.can_fire_item(item):
		if item.is_charged() and not item.is_fully_charged():
			Notifications.notify("%s is charging (%d/%d)." % [
				item.display_name, item.current_charge, item.max_charge()],
				Color(0.9, 0.8, 0.5))
		return
	if item.wants_target() and _has_living_enemy():
		_cancel_targeting()
		_selected_item = item
		_targeting = true
		if _targeting_arrow != null:
			_targeting_arrow.start(origin)
		GameLog.add("Choose a target for %s." % item.display_name, Color(0.7, 0.9, 1.0))
		_refresh_ui()
		return
	if GameState.use_item(item):
		GameLog.add("Used %s." % item.display_name, Color(0.85, 0.9, 1.0))

func _has_living_enemy() -> bool:
	for e in enemies:
		if e != null and e.is_alive():
			return true
	return false

# ------------------------------------------------------------------
# Drag-to-play — press a card and drag it onto the field. Non-targeting
# cards play when dropped anywhere outside the hand; targeted cards only
# play when dropped on a live enemy. Mirrors the HTML build's drag flow.
# ------------------------------------------------------------------

func _on_card_drag_started(card: CardInstance) -> void:
	if phase != Phase.PLAYER:
		return
	# Unplayable cards (curses) can't be played — don't even start the drag.
	if card.data != null and card.data.unplayable:
		GameLog.add("%s is unplayable." % card.get_display_name(), Color(0.8, 0.6, 0.8))
		return
	if _card_cost(card) > energy:
		GameLog.add("Not enough energy for %s." % card.get_display_name(), Color(0.9, 0.7, 0.3))
		return
	# Drag and click-targeting are mutually exclusive; drop any active pick.
	_cancel_targeting()
	_drag_card = card
	# Dim the source card in hand while its ghost is out on the field.
	for v in _hand_views:
		if v.card == card:
			v.modulate = Color(1, 1, 1, 0.3)
	# Floating clone that tracks the cursor.
	_drag_ghost = CardView.new()
	add_child(_drag_ghost)
	_drag_ghost.setup(card)
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.modulate = Color(1, 1, 1, 0.9)
	_drag_ghost.z_index = 200
	# Targeted cards get the aim arrow + lit-up enemy row.
	if card.wants_target():
		if _targeting_arrow != null:
			_targeting_arrow.start(_card_arrow_origin(card))
		for view in _enemy_views:
			view.set_targetable(true)
	_update_drag(get_global_mouse_position())

func _update_drag(pos: Vector2) -> void:
	if _drag_ghost != null:
		_drag_ghost.global_position = pos - Vector2(CardView.CARD_W, CardView.CARD_H) * 0.5
	# Highlight whichever live enemy sits under the cursor.
	var hovered: EnemyView = _enemy_view_at(pos)
	if hovered != _drag_hover_enemy:
		if _drag_hover_enemy != null and is_instance_valid(_drag_hover_enemy):
			_drag_hover_enemy.modulate = Color.WHITE
		_drag_hover_enemy = hovered
		if hovered != null:
			hovered.modulate = Color(1.3, 1.3, 1.3)

func _finish_drag(pos: Vector2) -> void:
	var card := _drag_card
	_clear_drag_visuals()
	if card == null or phase != Phase.PLAYER or not (card in hand):
		return
	# Unplayable cards (curses) sit in hand but can't be played manually.
	if card.data != null and card.data.unplayable:
		return
	if _card_cost(card) > energy:
		return
	if card.wants_target():
		# Targeted: only resolves when dropped on a live enemy.
		var view: EnemyView = _enemy_view_at(pos)
		if view != null:
			var idx: int = _enemy_views.find(view)
			if idx >= 0 and idx < enemies.size() and enemies[idx].is_alive():
				_resolve_card(card, enemies[idx])
	else:
		# Non-targeting: plays anywhere except dropped back onto the hand.
		if _hand_area != null and _hand_area.get_global_rect().has_point(pos):
			return
		_resolve_card(card, null)

func _cancel_drag() -> void:
	_clear_drag_visuals()

func _clear_drag_visuals() -> void:
	if _drag_ghost != null:
		_drag_ghost.queue_free()
		_drag_ghost = null
	if _drag_hover_enemy != null and is_instance_valid(_drag_hover_enemy):
		_drag_hover_enemy.modulate = Color.WHITE
	_drag_hover_enemy = null
	if _targeting_arrow != null:
		_targeting_arrow.stop()
	_drag_card = null
	# Restores dimmed hand-card modulate + clears enemy targetable highlight.
	_refresh_ui()

func _enemy_view_at(pos: Vector2) -> EnemyView:
	for i in range(_enemy_views.size()):
		var view: EnemyView = _enemy_views[i]
		if not is_instance_valid(view):
			continue
		if i >= enemies.size() or not enemies[i].is_alive():
			continue
		if view.get_global_rect().has_point(pos):
			return view
	return null

func _resolve_card(card: CardInstance, target_enemy: CombatActor) -> void:
	energy -= _card_cost(card)
	TriggerBus.emit_signal("card_played", {
		"card": card, "target": target_enemy, "scene": self,
	})
	# Power-card triggers fire BEFORE the card's own effects resolve.
	# This is the right order for "Whenever you play a card …" Powers
	# because the Power being played hasn't registered its trigger
	# yet, so it doesn't self-trigger.
	_fire_power_triggers("card_played", {"card": card})
	_fire_item_triggers("card_played", {"card": card, "target": target_enemy})

	_apply_card_effects(card, target_enemy)

	# The card has fully resolved its primary play. card_resolved is a
	# general post-resolution hook (after card_played + the effects, before
	# discard/exhaust); fired once, not per Replay.
	TriggerBus.emit_signal("card_resolved", {
		"card": card, "target": target_enemy, "scene": self,
	})
	_fire_item_triggers("card_resolved", {"card": card, "target": target_enemy})

	# Replay addon: the card re-resolves its own effects N extra times.
	# Carried natively (CardData.addons) or granted by an item — Duplicator
	# gives weapon attack cards Replay 1. Resolved through CardMods so the
	# count folds native + granted in one place.
	var replays: int = CardMods.replay_count(card.data)
	for _i in replays:
		replay_card_effects(card, target_enemy)

	# Playing a card fires any on_play_other curse in hand (Pain: lose HP when
	# you play another card). Curse cards are unplayable, so `card` is never a
	# curse here. (Action/strategy translate on_play_other -> on_action.)
	_fire_curse_triggers("on_play_other", hand, hand.size())

	# Fear: playing a Skill card steadies the player — shed 1 Fear stack. Fires
	# once per played Skill (not per Replay), the deckbuilder-side decay rule.
	if card.is_skill() and player.get_status(&"fear") > 0:
		player.add_status(&"fear", -1)
		GameLog.add("Fear -1 (Skill played).", Color(0.7, 0.9, 1.0))

	# Destroy: the card is removed from the run deck permanently when played. It
	# leaves hand (no discard/exhaust pile) and is dropped from GameState.deck so
	# it never returns. Takes precedence over exhaust/discard below.
	if card.data.destroy:
		hand.erase(card)
		GameState.destroy_card_instance(card)
		GameLog.add("%s is Destroyed — removed from your deck." % card.get_display_name(),
			Color(0.9, 0.55, 0.55))
		TriggerBus.emit_signal("card_exhausted", {"card": card, "scene": self})
		_fire_power_triggers("card_exhausted", {"card": card})
	# Powers exhaust on play; cards with the exhaust flag exhaust; else discard.
	elif card.data.exhaust or card.is_power():
		exhaust_card(card)
	else:
		discard_card(card)
	_refresh_ui()
	# Killing the last enemy with a card ends combat immediately.
	_check_combat_end()

func _apply_card_effects(card: CardInstance, target_enemy: CombatActor) -> void:
	# Resolves a card's own effect list against the picked target. Split out
	# of _resolve_card so the Replay addon can re-run JUST the effects (no
	# energy cost, no card_resolved emit, no discard).
	for raw_effect in card.get_effects():
		var effect: Dictionary = _apply_card_boosts(raw_effect, card)
		effect = Stats.apply_addons_to_effect(effect, card.data)
		# Vorpal rides the physical card instance (per-instance roll), so stamp it
		# here where the CardInstance is in scope; deal_damage reads it per target.
		effect = card.apply_vorpal_to_effect(effect)
		var t_str: String = effect.get("target", "enemy")
		# Indiscriminate (Blood Magic) skips the manual picker — re-route
		# enemy-targeted dmg through random_enemy so a seed target lands
		# and _h_dmg can re-roll per hit from there.
		if effect.get("indiscriminate", false) and t_str == "enemy" and target_enemy == null:
			t_str = "random_enemy"
		var targets: Array = []
		match t_str:
			"enemy":
				if target_enemy != null:
					targets = [target_enemy]
			"all_enemies":
				for e in enemies:
					if e.is_alive():
						targets.append(e)
			"self":
				targets = [player]
			"player":
				targets = [player]
			"random_enemy":
				var live: Array = []
				for e in enemies:
					if e.is_alive():
						live.append(e)
				if not live.is_empty():
					targets = [live[_rng.randi() % live.size()]]
			_:
				if target_enemy != null:
					targets = [target_enemy]
				else:
					targets = [player]

		for tgt in targets:
			var ctx := {
				"source": player,
				"target": tgt,
				"scene": self,
				"card": card,
			}
			EffectSystem.apply(effect, ctx)

func replay_card_effects(card: CardInstance, target_enemy) -> void:
	# Replay addon: re-run a card's effects one extra time. Effects only —
	# the card has already paid its cost and fired card_resolved, so this
	# just re-resolves the hit(s)/block/etc. If the first pass already
	# cleared the room, the dmg handlers no-op on the dead target.
	if card == null:
		return
	# Only ever replay damage onto a living enemy. If the first hit cleared
	# the picked target, pass null: single-target effects no-op, while
	# all_enemies effects still sweep whatever enemies remain, and self
	# effects (block/heal) always re-apply. This also guards the case where
	# no enemies are left — we must never replay an attack onto ourselves.
	var tgt: CombatActor = null
	if target_enemy is CombatActor and not target_enemy.is_player and target_enemy.is_alive():
		tgt = target_enemy
	_apply_card_effects(card, tgt)
	GameLog.add("%s replays!" % card.data.display_name, Color(0.7, 1.0, 0.7))
	_check_combat_end()

# ------------------------------------------------------------------
# Curse cards (CardData.triggers)
# ------------------------------------------------------------------

# Fires the triggered effects of every curse card currently in hand whose `on`
# matches `trigger` ("eot" / "on_play_other"). The owning curse is both source
# and target — self-inflicted (target "self"). `per: "card_in_hand"` effects
# (Regret) scale by the cards in hand.
func _fire_curse_triggers(trigger: String, cards: Array, hand_size: int) -> void:
	for c in cards:
		if c == null or c.data == null or c.data.triggers.is_empty():
			continue
		for trig in c.data.triggers:
			if String(trig.get("on", "")) != trigger:
				continue
			for raw in trig.get("effects", []):
				if not (raw is Dictionary):
					continue
				var effect: Dictionary = _resolve_curse_effect(raw, hand_size)
				if effect.is_empty():
					continue
				EffectSystem.apply(effect, {
					"source": player, "target": player, "scene": self, "card": c,
				})
	_refresh_ui()

# Resolves the deckbuilder `per` scaler — Regret's `per: "card_in_hand"` (× cards
# in hand right now). A zero multiplier returns an empty dict so the caller skips
# the no-op hit. on_action / per_action are STRATEGY concepts the translators map
# to; the deckbuilder never sees them.
func _resolve_curse_effect(effect: Dictionary, hand_size: int) -> Dictionary:
	if String(effect.get("per", "")) != "card_in_hand":
		return effect
	var n: int = hand_size
	if n <= 0:
		return {}
	var out: Dictionary = effect.duplicate()
	out.erase("per")
	out["value"] = int(effect.get("value", 1)) * n
	GameLog.add("Regret: %d card(s) in hand — lose %d HP." % [n, int(out["value"])],
		Color(0.9, 0.6, 0.7))
	return out

# ------------------------------------------------------------------
# Effect callbacks (invoked by EffectSystem handlers via ctx.scene)
# ------------------------------------------------------------------

func deal_damage(source: CombatActor, target: CombatActor, base_amount: int, effect: Dictionary) -> void:
	if target == null or not target.is_alive():
		return
	var damage_type: String = String(effect.get("damage_type", "melee"))

	# A player melee/ranged swing at an enemy is an "attack" for streak
	# items (Dead Eye). Fold any active streak bonus into the swing BEFORE
	# resolving so Power/Weak/Vulnerable treat it like the rest of the hit.
	var is_player_attack: bool = source != null and source.is_player \
		and (damage_type == "melee" or damage_type == "ranged") \
		and not target.is_player
	if is_player_attack:
		base_amount += GameState.streak_attack_bonus(target)

	# Vorpal: flat bonus when this swing's bound mode (here, Deckbuilder) and the
	# target's weight match the card's roll. Added to base so Power/Vulnerable/etc.
	# still layer on top, matching the other pre-resolve flat bonuses.
	base_amount += Stats.vorpal_damage_bonus(effect, target, Stats.Mode.DECKBUILDER)

	# Canonical damage math lives in Stats.resolve_damage (Blind whiff,
	# Power/Weak, Vulnerable, Dodge, block soak) so all three modes agree.
	# The scene-specific tail below — logging, triggers, Soul Link, death,
	# Infuse, Thorns — stays here.
	var res := Stats.resolve_damage(source, target, base_amount, effect, Stats.Mode.DECKBUILDER, _rng)
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
		GameLog.add("%s dodges!" % target.display_name, Color(0.7, 0.9, 1.0))
		return
	if res.get("buffered", false):
		var bwho: String = "You" if target.is_player else target.display_name
		GameLog.add("%s's Buffer absorbs the blow!" % bwho, Color(0.8, 0.9, 1.0))
	var amount: int = int(res.hp_loss)
	var absorbed: int = int(res.blocked)

	if amount > 0:
		if target.is_player:
			GameState.change_hp(-amount)
			target.hp = GameState.hp
		else:
			target.hp = maxi(0, target.hp - amount)
		_float_number(target, amount)
		var who := "you" if target.is_player else target.display_name
		GameLog.add("%s takes %d damage." % [who.capitalize(), amount], Color(1.0, 0.6, 0.6))
		TriggerBus.emit_signal("damage_taken", {
			"target": target, "attacker": source, "amount": amount, "scene": self,
		})
		_fire_power_triggers("damage_taken")
		# Lifesteal: the attacker heals for the unblocked HP it just dealt to a
		# foe. `amount` is post-block HP loss, matching the legacy rule. Self-hits
		# (curse cards) and reflected reactions never lifesteal.
		if bool(effect.get("lifesteal", false)) and source != null and source != target \
				and not effect.get("no_reaction", false):
			heal(source, amount)
			var lsy := "You" if source.is_player else source.display_name
			GameLog.add("%s drains %d HP (Lifesteal)." % [lsy, amount], Color(0.7, 1.0, 0.7))
		# Item reactions to the PLAYER taking damage (Prayer Card, Prayer Beads).
		# Gated to the player so "whenever you take damage" never fires off an
		# enemy being hit.
		if target.is_player:
			_fire_item_triggers("damage_taken", {"target": target})
		# Soul Link propagation. Bird Head's status: whenever a soul-linked
		# actor loses HP, every other soul-linked actor takes the same raw
		# loss. Guarded by effect.from_soul_link so the cascade can't loop
		# back through itself.
		if not effect.get("from_soul_link", false) and target.get_status(&"soul_link") > 0:
			_propagate_soul_link(target, amount)
		if target.hp <= 0:
			target.dead = true
			GameLog.add("%s is defeated!" % target.display_name, Color(0.6, 1.0, 0.6))
			# Blood Magic / Infuse addon: when a dmg effect carrying
			# `infuse: N` lands the killing blow, the player gains N
			# Max HP. Deckbuilder + strategy fire on every kill; action
			# rolls a 10% chance per hit in ActionCombat.
			var infuse_stacks: int = int(effect.get("infuse", 0))
			if infuse_stacks > 0 and source != null and source.is_player:
				GameState.set_max_hp(GameState.max_hp + infuse_stacks, false)
				GameLog.add("Infuse: gained %d Max HP." % infuse_stacks,
					Color(0.85, 0.65, 1.0))
			if not target.is_player:
				TriggerBus.emit_signal("enemy_killed", {"enemy": target, "scene": self})
				_fire_item_triggers("enemy_killed")
				_fire_power_triggers("enemy_killed")
	elif absorbed > 0:
		var who := "your" if target.is_player else (target.display_name + "'s")
		GameLog.add("%s block absorbs %d." % [who, absorbed], Color(0.7, 0.8, 1.0))

	# Thorns / Bleed Thorns: triggers on any LANDED melee hit (past
	# miss and dodge), including fully-blocked ones. Routed through the
	# Stats helper so strategy combat can call the same code from its
	# trample / knockback / jump-on events later. no_reaction stops the
	# attacker's own thorns from recursing back when this reflect hits.
	var landed_melee: bool = (amount > 0 or absorbed > 0) \
		and damage_type == "melee" \
		and not effect.get("no_reaction", false) \
		and source != null and source != target
	if landed_melee:
		Stats.fire_contact_reactions(target, source, self)

	TriggerBus.emit_signal("damage_dealt", {
		"source": source, "target": target, "amount": amount, "scene": self,
	})
	_fire_power_triggers("damage_dealt")

	# The attack connected (block counts; miss/dodge already returned above).
	# Dead Eye's streak grows here. Skip a killing blow — the streak against a
	# dead enemy is never read (the next hit is a new target, which resets),
	# and emitting with a corpse would make item target-resolution fall back
	# to a different living enemy.
	if is_player_attack and target.is_alive():
		TriggerBus.emit_signal("attack_landed",
			{"source": source, "target": target, "scene": self})
		_fire_item_triggers("attack_landed", {"target": target})

func apply_dot(target: CombatActor, amount: int, source_name: String) -> void:
	# Direct HP loss from end-of-turn status ticks (Bleed today; Burn /
	# Poison once their ticks land). Bypasses block, Weak, Vulnerable,
	# and never re-triggers thorns — DoTs are NOT contact events.
	if target == null or not target.is_alive() or amount <= 0:
		return
	if target.is_player:
		GameState.change_hp(-amount)
		target.hp = GameState.hp
	else:
		target.hp = maxi(0, target.hp - amount)
	_float_number(target, amount)
	var who := "You" if target.is_player else target.display_name
	GameLog.add("%s takes %d %s damage." % [who, amount, source_name],
		Color(1.0, 0.5, 0.6))
	if target.get_status(&"soul_link") > 0:
		_propagate_soul_link(target, amount)
	if target.hp <= 0:
		target.dead = true
		GameLog.add("%s is defeated!" % target.display_name, Color(0.6, 1.0, 0.6))
		if not target.is_player:
			TriggerBus.emit_signal("enemy_killed", {"enemy": target, "scene": self})
			_fire_item_triggers("enemy_killed")
			_fire_power_triggers("enemy_killed")

func _propagate_soul_link(origin: CombatActor, amount: int) -> void:
	# Bird Head / Soul Link: every other actor carrying soul_link takes
	# the same raw HP loss (block, weak, vulnerable, thorns are all
	# bypassed — it's a sympathetic wound, not a hit). Damage routes
	# through deal_damage with from_soul_link=true so this can't recurse
	# back into the cascade. Block bypass is intentional: a soul-linked
	# tank cannot absorb the chain hit for everyone else.
	if amount <= 0:
		return
	var victims: Array = []
	for e in enemies:
		if e != origin and e.is_alive() and e.get_status(&"soul_link") > 0:
			victims.append(e)
	if player != origin and player.is_alive() and player.get_status(&"soul_link") > 0:
		victims.append(player)
	for v in victims:
		# Bypass block, Weak, Vulnerable, and reactions — sympathetic loss,
		# not a hit. A soul-linked tank cannot eat the chain damage for the
		# rest of the link.
		if v.is_player:
			GameState.change_hp(-amount)
			v.hp = GameState.hp
		else:
			v.hp = maxi(0, v.hp - amount)
		var who_v: String = "you" if v.is_player else v.display_name
		GameLog.add("Soul Link bleeds %d into %s." % [amount, who_v], Color(0.8, 0.5, 1.0))
		TriggerBus.emit_signal("damage_taken", {
			"target": v, "attacker": null, "amount": amount, "scene": self,
		})
		if v.hp <= 0:
			v.dead = true
			GameLog.add("%s is defeated!" % v.display_name, Color(0.6, 1.0, 0.6))
			if not v.is_player:
				TriggerBus.emit_signal("enemy_killed", {"enemy": v, "scene": self})
				_fire_item_triggers("enemy_killed")
				_fire_power_triggers("enemy_killed")

func gain_block(target: CombatActor, base_amount: int) -> void:
	if target == null:
		return
	# Shared block math: Defense status adds, Frail cuts 25% (see Stats).
	target.block += Stats.resolve_block(base_amount, target, true)

# Pops a floating number over an actor: red for HP lost, green for HP healed.
# Enemies float over their EnemyView; the player (no avatar) floats over the HP
# readout.
func _float_number(target: CombatActor, amount: int, color: Color = FloatingNumbers.DAMAGE_COLOR) -> void:
	if amount <= 0 or not is_inside_tree():
		return
	var pos: Variant = _float_anchor_pos(target)
	if pos == null:
		return
	FloatingNumbers.spawn(self, pos, amount, color)

# "MISS" / other floating text over an actor, reusing the same anchor logic.
func _float_text(target: CombatActor, text: String, color: Color = FloatingNumbers.DAMAGE_COLOR) -> void:
	if not is_inside_tree():
		return
	var pos: Variant = _float_anchor_pos(target)
	if pos == null:
		return
	FloatingNumbers.spawn_text(self, pos, text, color)

# Local-space anchor point over `target`'s HP label / enemy view, or null.
func _float_anchor_pos(target: CombatActor) -> Variant:
	var anchor: Control = null
	if target != null and target.is_player:
		anchor = _hp_label
	else:
		var idx: int = enemies.find(target)
		if idx >= 0 and idx < _enemy_views.size():
			anchor = _enemy_views[idx]
	if anchor == null:
		return null
	return anchor.global_position - global_position + anchor.size * 0.5

func heal(target: CombatActor, amount: int) -> void:
	if target == null or amount <= 0:
		return
	var before: int = target.hp
	if target.is_player:
		GameState.change_hp(amount)
		target.hp = GameState.hp
	else:
		target.hp = mini(target.max_hp, target.hp + amount)
	_float_number(target, target.hp - before, FloatingNumbers.HEAL_COLOR)

# Leeches drain -> player heal. Called by Stats.tick_actor_statuses when a
# leeched enemy bleeds HP into the player (Jar of Leeches).
func leech_to_player(amount: int) -> void:
	if amount <= 0:
		return
	heal(player, amount)
	GameLog.add("Leeches drain %d into you." % amount, Color(0.7, 1.0, 0.7))

func apply_status(target, status: StringName, stacks: int, source = null) -> void:
	# Shared apply (guard + Persistence + add) lives in Stats.apply_status_to so
	# all three modes agree; deckbuilder's reaction is the status_applied bus +
	# Power-card triggers. Skip the reaction when nothing actually landed.
	var applied: int = Stats.apply_status_to(target, status, stacks, source)
	if applied == 0:
		return
	TriggerBus.emit_signal("status_applied", {
		"target": target, "status": status, "stacks": applied, "scene": self,
	})
	_fire_power_triggers("status_applied")

# ------------------------------------------------------------------
# Pile helpers — also called from EffectSystem default handlers
# ------------------------------------------------------------------

func draw_cards(n: int) -> void:
	for _i in range(n):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			while not discard_pile.is_empty():
				draw_pile.append(discard_pile.pop_back())
			_shuffle(draw_pile)
		var c: CardInstance = draw_pile.pop_back()
		hand.append(c)
		TriggerBus.emit_signal("card_drawn", {"card": c, "scene": self})
		_fire_power_triggers("card_drawn", {"card": c})
	_refresh_ui()

func discard_card(card: CardInstance) -> void:
	hand.erase(card)
	# Sly: an (unplayable) card resolves its effects the moment it would be
	# discarded, then still heads to the discard pile.
	if card != null and card.data != null and card.data.sly:
		_resolve_sly_on_discard(card)
	discard_pile.append(card)
	TriggerBus.emit_signal("card_discarded", {"card": card, "scene": self})
	_fire_power_triggers("card_discarded", {"card": card})
	_refresh_ui()

func _resolve_sly_on_discard(card: CardInstance) -> void:
	# Sly: play the card's effects as it leaves hand. Auto-targets a random live
	# enemy (Sly cards are unplayable, so there's no manual pick). No energy cost
	# — it triggers off the discard, not a play. The caller files it into the
	# discard pile afterward.
	if card == null:
		return
	var tgt: CombatActor = null
	var live: Array = []
	for e in enemies:
		if e.is_alive():
			live.append(e)
	if not live.is_empty():
		tgt = live[_rng.randi() % live.size()]
	GameLog.add("%s is Sly — it plays as it's discarded!" % card.get_display_name(),
		Color(0.8, 1.0, 0.8))
	_apply_card_effects(card, tgt)
	_check_combat_end()

func exhaust_card(card: CardInstance) -> void:
	hand.erase(card)
	exhaust_pile.append(card)
	TriggerBus.emit_signal("card_exhausted", {"card": card, "scene": self})
	_fire_power_triggers("card_exhausted", {"card": card})
	_refresh_ui()

func conjure_card(card_id: StringName, destination: String, count: int, source_card, force_upgraded: bool = false) -> void:
	# Generic conjure: drop `count` copies of `card_id` into the named
	# pile. `card_id == &"self"` copies the played card (Anger) and
	# preserves its upgrade state — playing an upgraded Anger conjures
	# an upgraded Anger. For any other id we look up the static
	# CardData from `Data` so the same call works for status cards
	# (Dazed, Wound), curses, etc.
	#
	# Upgrade flag for non-self conjures: either pass `force_upgraded`
	# explicitly, or append "+" to the card_id (e.g. `&"shiv+"`).
	# The "+" suffix matches the game's display convention so sheet
	# authors can write `conjure:shiv+:hand:3` and have it Just Work.
	#
	# `destination`: "hand" / "draw" / "discard". An unknown destination
	# logs a warning and is treated as discard so a typo in the sheet
	# doesn't silently swallow the effect. Draw pile additions are
	# shuffled in so the copy isn't deterministically on top.
	var data: CardData = null
	var upgraded := false
	if card_id == &"self":
		if source_card == null or not (source_card is CardInstance):
			return
		data = source_card.data
		upgraded = source_card.upgraded
	else:
		var id_str: String = String(card_id)
		if id_str.ends_with("+"):
			upgraded = true
			id_str = id_str.substr(0, id_str.length() - 1)
		if force_upgraded:
			upgraded = true
		data = Data.get_card(StringName(id_str))
		if data == null:
			push_warning("conjure_card: unknown card id '%s'" % card_id)
			return
		if upgraded and not data.can_upgrade:
			# Asking for an upgraded form of a card that can't upgrade
			# (e.g. status cards) — silently fall back to base form.
			upgraded = false
	for _i in range(count):
		var copy: CardInstance = CardInstance.from_data(data, upgraded)
		match destination:
			"hand":
				hand.append(copy)
			"draw":
				draw_pile.append(copy)
			"discard":
				discard_pile.append(copy)
			_:
				push_warning("conjure_card: unknown destination '%s'" % destination)
				discard_pile.append(copy)
	if destination == "draw":
		_shuffle(draw_pile)
	_refresh_ui()

func gain_energy(amount: int) -> void:
	energy += amount
	_refresh_ui()

func lose_energy(amount: int) -> void:
	energy = maxi(0, energy - amount)
	_refresh_ui()

func make_random_hand_card_free(exclude = null) -> void:
	# Mummified Hand: pick a random card in hand (other than the power that
	# just triggered this) whose cost is above 0 and set it to cost 0 for the
	# rest of the turn. Cleared when the card leaves hand (see _on_end_turn).
	var candidates: Array = []
	for c in hand:
		if c == exclude:
			continue
		if c.get_cost() > 0:
			candidates.append(c)
	if candidates.is_empty():
		return
	var pick: CardInstance = candidates[_rng.randi() % candidates.size()]
	pick.temp_cost_override = 0
	GameLog.add("Mummified Hand: %s costs 0 this turn!" % pick.data.display_name,
		Color(0.7, 1.0, 0.7))
	_refresh_ui()

# ------------------------------------------------------------------
# Discard / card-boost effect plumbing (deckbuilder)
# ------------------------------------------------------------------

const _TYPE_NAMES: Array[String] = ["attack", "skill", "power", "dice", "status", "curse", "training"]

func discard_cards(n: int, source_card = null, random: bool = false) -> void:
	# Two paths: random (All-Out Attack) silently picks; player-choice
	# (Acrobatics et al, the default) opens the CardPickerModal. Both
	# exclude the card being played so a "Deal X. Discard 1." card
	# can't route itself through discard. Silently drops the request
	# when the hand is empty.
	if n <= 0:
		return
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		pool.append(c)
	if pool.is_empty():
		return
	if random:
		var picks: Array = []
		for _i in range(n):
			if pool.is_empty():
				break
			var pick: CardInstance = pool[_rng.randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_discard_picks(picks)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Discard %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": _PILE_COLORS["discard"],
			"confirm_label": "Discard",
			"on_picked": Callable(self, "_apply_discard_picks"),
		})

func _apply_discard_picks(picks: Array) -> void:
	for pick in picks:
		discard_card(pick)
		GameLog.add("Discarded %s." % pick.get_display_name(), Color(0.9, 0.7, 0.4))

func exhaust_cards(n: int, source_card = null, random: bool = false) -> void:
	# Mirror of `discard_cards` but routes picks to the exhaust pile.
	# Same exclusion rule for the card being played.
	if n <= 0:
		return
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		pool.append(c)
	if pool.is_empty():
		return
	if random:
		var picks: Array = []
		for _i in range(n):
			if pool.is_empty():
				break
			var pick: CardInstance = pool[_rng.randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_exhaust_picks(picks)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Exhaust %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": _PILE_COLORS["exhaust"],
			"confirm_label": "Exhaust",
			"on_picked": Callable(self, "_apply_exhaust_picks"),
		})

func _apply_exhaust_picks(picks: Array) -> void:
	for pick in picks:
		exhaust_card(pick)
		GameLog.add("Exhausted %s." % pick.get_display_name(), Color(0.7, 0.7, 0.8))

func recall_cards(from_pile: String, to_pile: String, filter: Dictionary) -> void:
	# Move (not copy) cards matching `filter` from `from_pile` to
	# `to_pile`. The only shipped filter today is `{"cost": N}`
	# (All for One). Extend with tag= / type= / id= when a second
	# consumer needs them.
	var src: Array = _pile_for(from_pile)
	if src.is_empty():
		return
	var matched: Array = []
	for inst in src:
		if _filter_matches(inst, filter):
			matched.append(inst)
	if matched.is_empty():
		return
	for inst in matched:
		src.erase(inst)
		match to_pile:
			"hand":
				hand.append(inst)
			"draw":
				draw_pile.append(inst)
			"discard":
				discard_pile.append(inst)
			_:
				push_warning("recall_cards: unknown destination '%s'" % to_pile)
				discard_pile.append(inst)
	if to_pile == "draw":
		_shuffle(draw_pile)
	GameLog.add("Recalled %d card%s from %s." % [
		matched.size(), "s" if matched.size() > 1 else "", from_pile,
	], Color(0.6, 1.0, 0.8))
	_refresh_ui()

func _filter_matches(inst: CardInstance, filter: Dictionary) -> bool:
	if filter == null or filter.is_empty():
		return true
	if filter.has("cost") and inst.get_cost() != int(filter["cost"]):
		return false
	if filter.has("tag") and not inst.data.tags.has(String(filter["tag"])):
		return false
	if filter.has("type") and inst.data.type != int(filter["type"]):
		return false
	if filter.has("id") and inst.data.id != StringName(String(filter["id"])):
		return false
	return true

func upgrade_hand_cards(count_or_all, source_card = null, random: bool = false) -> void:
	# `count_or_all` is an int (pick N) or the string "all" (skip the
	# picker and upgrade everything eligible). Cards with
	# `can_upgrade = false` (Dazed / Wound / status) are filtered out.
	# Already-upgraded cards are also filtered so the player isn't
	# offered no-op picks.
	var pool: Array = []
	for c in hand:
		if c == source_card:
			continue
		if c.data == null or not c.data.can_upgrade:
			continue
		if c.upgraded:
			continue
		pool.append(c)
	if pool.is_empty():
		return
	var all_mode: bool = (typeof(count_or_all) == TYPE_STRING and String(count_or_all).to_lower() == "all")
	if all_mode:
		_apply_upgrade_picks(pool)
		return
	var n: int = int(count_or_all)
	if n <= 0:
		return
	if random:
		var picks: Array = []
		for _i in range(n):
			if pool.is_empty():
				break
			var pick: CardInstance = pool[_rng.randi() % pool.size()]
			pool.erase(pick)
			picks.append(pick)
		_apply_upgrade_picks(picks)
	else:
		var count: int = mini(n, pool.size())
		_open_picker({
			"title": "Upgrade %d card%s" % [count, "s" if count > 1 else ""],
			"candidates": pool,
			"count": count,
			"accent": Color(0.6, 0.9, 1.0),
			"confirm_label": "Upgrade",
			"on_picked": Callable(self, "_apply_upgrade_picks"),
		})

func _apply_upgrade_picks(picks: Array) -> void:
	for pick in picks:
		pick.upgraded = true
		GameLog.add("Upgraded %s." % pick.get_display_name(), Color(0.6, 0.9, 1.0))
	_refresh_ui()

func _open_picker(opts: Dictionary) -> void:
	# One picker at a time; tear down any pre-existing modal so a
	# chained mid-cast trigger (e.g. Power-armed Discard) can't stack
	# two pickers on top of each other.
	var prev := get_node_or_null("CardPickerModal")
	if prev != null:
		prev.queue_free()
	var modal := CardPickerModal.new()
	modal.name = "CardPickerModal"
	add_child(modal)
	modal.show_picker(opts)

func add_card_boost(boost: Dictionary) -> void:
	card_boosts.append(boost)
	var label: String = _boost_label(boost)
	GameLog.add("Active boost: %s." % label, Color(0.7, 1.0, 0.7))

func register_trigger(on: String, inner_effect: Dictionary) -> void:
	if on == "" or inner_effect.is_empty():
		return
	power_triggers.append({"on": on, "effect": inner_effect})
	GameLog.add("Trigger armed on %s." % on, Color(0.7, 1.0, 0.7))

func _fire_power_triggers(event_name: String, ctx_extras: Dictionary = {}) -> void:
	# Walks the power_triggers list and dispatches every entry whose
	# `on` matches `event_name`. ctx_extras lets the caller pass
	# event-specific bits (e.g. the card that was just played) into
	# the inner effect's context.
	if power_triggers.is_empty():
		return
	for trig in power_triggers:
		if String(trig.get("on", "")) != event_name:
			continue
		var inner: Dictionary = trig.get("effect", {})
		if inner.is_empty():
			continue
		var ctx: Dictionary = {
			"source": player,
			"target": player,
			"scene": self,
			"card": ctx_extras.get("card"),
		}
		EffectSystem.apply(inner, ctx)

func _boost_label(boost: Dictionary) -> String:
	var who := ""
	if String(boost.get("match_tag", "")) != "":
		who = "tag=%s" % boost.match_tag
	elif String(boost.get("match_type", "")) != "":
		who = "type=%s" % boost.match_type
	elif String(boost.get("match_id", "")) != "":
		who = "id=%s" % boost.match_id
	return "%s %s +%d" % [who, boost.get("stat", "dmg"), int(boost.get("value", 0))]

func _apply_card_boosts(effect: Dictionary, card: CardInstance) -> Dictionary:
	# Returns either the original effect or a copy with the value bumped
	# by every matching active boost. Only `dmg` and `block` effects
	# scale today; cost boosts route through CardInstance.temp_cost_override.
	if card_boosts.is_empty():
		return effect
	var effect_type: String = String(effect.get("type", ""))
	if effect_type != "dmg" and effect_type != "block":
		return effect
	var bonus := 0
	for boost in card_boosts:
		if String(boost.get("stat", "")) != effect_type:
			continue
		if not _card_matches_boost(card, boost):
			continue
		bonus += int(boost.get("value", 0))
	if bonus == 0:
		return effect
	var out: Dictionary = effect.duplicate(true)
	out["value"] = int(out.get("value", 0)) + bonus
	return out

func _card_matches_boost(card: CardInstance, boost: Dictionary) -> bool:
	var data: CardData = card.data
	if data == null:
		return false
	var match_tag: String = String(boost.get("match_tag", ""))
	var match_type: String = String(boost.get("match_type", ""))
	var match_id: String = String(boost.get("match_id", ""))
	if match_tag != "":
		return data.tags.has(match_tag)
	if match_type != "":
		var idx: int = data.type
		if idx < 0 or idx >= _TYPE_NAMES.size():
			return false
		return _TYPE_NAMES[idx] == match_type.to_lower()
	if match_id != "":
		return String(data.id) == match_id
	return false

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ------------------------------------------------------------------
# Enemy intent
# ------------------------------------------------------------------

func _roll_intent(enemy: CombatActor) -> void:
	if enemy.data == null or enemy.data.pattern.is_empty():
		enemy.planned_move = {}
		return
	var pattern: Array = enemy.data.pattern

	# Turn 1 special-case: any move marked first_turn_only wins outright.
	if turn == 1:
		for m in pattern:
			if m.get("first_turn_only", false):
				enemy.planned_move = m
				return

	# Weighted random selection ignoring first_turn_only moves.
	var pool: Array = []
	var total_weight := 0
	for m in pattern:
		if m.get("first_turn_only", false):
			continue
		var w: int = m.get("weight", 1)
		pool.append({"move": m, "weight": w})
		total_weight += w
	if total_weight <= 0 or pool.is_empty():
		enemy.planned_move = {}
		return
	var roll := _rng.randi_range(1, total_weight)
	var acc := 0
	for entry in pool:
		acc += entry.weight
		if roll <= acc:
			enemy.planned_move = entry.move
			return
	enemy.planned_move = pool[-1].move

# ------------------------------------------------------------------
# UI
# ------------------------------------------------------------------

# Lowercase phase name for the turn HUD (preserves the pre-enum label text).
func _phase_label() -> String:
	match phase:
		Phase.INIT: return "init"
		Phase.PLAYER: return "player"
		Phase.ENEMY: return "enemy"
		Phase.WON: return "won"
		Phase.LOST: return "lost"
	return "?"

func _refresh_ui() -> void:
	_turn_label.text = "Turn %d   Phase: %s%s" % [
		turn, _phase_label(),
		"   [TARGETING]" if _targeting else "",
	]
	_energy_label.text = "Energy: %d / %d" % [energy, max_energy]
	_hp_label.text = "HP: %d / %d" % [player.hp if player else 0, player.max_hp if player else 0]
	_block_label.text = "Block: %d" % (player.block if player else 0)
	_draw_btn.text = "Draw: %d" % draw_pile.size()
	_discard_btn.text = "Discard: %d" % discard_pile.size()
	_exhaust_btn.text = "Exhaust: %d" % exhaust_pile.size()

	_refresh_player_view()

	# Enemies — refresh existing views instead of rebuilding.
	for view in _enemy_views:
		view.refresh()
		view.set_targetable(_targeting)

	# Hand — reconcile views in place instead of freeing and rebuilding the
	# whole row every refresh (which ran on every draw/discard/status tick).
	# Grow or shrink _hand_views to match the hand, then re-point each
	# surviving view at its current card; setup() -> refresh() repaints it.
	while _hand_views.size() < hand.size():
		var view := CardView.new()
		view.play_requested.connect(_try_play_card)
		view.drag_started.connect(_on_card_drag_started)
		# add_child first so _ready builds the child controls before setup().
		_hand_area.add_child(view)
		_hand_views.append(view)
	while _hand_views.size() > hand.size():
		var extra: CardView = _hand_views.pop_back()
		_hand_area.remove_child(extra)
		extra.queue_free()
	for i in range(hand.size()):
		var card_inst: CardInstance = hand[i]
		var view: CardView = _hand_views[i]
		view.setup(card_inst)
		view.set_enabled((phase == Phase.PLAYER) and (_card_cost(card_inst) <= energy))
		view.set_selected(_targeting and _selected_card == card_inst)


func _input(event: InputEvent) -> void:
	# Drag-to-play takes priority: while a card is being dragged, follow the
	# cursor and resolve / cancel on release.
	if _drag_card != null:
		if event is InputEventMouseMotion:
			_update_drag(event.global_position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_drag(event.global_position)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_drag()
		return
	# Right-click or ESC cancels targeting.
	if not _targeting:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_targeting()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_targeting()

# ------------------------------------------------------------------
# Pile viewer overlay (Draw / Discard / Exhaust)
# ------------------------------------------------------------------

const _PILE_TITLES := {
	"draw": "Draw Pile",
	"discard": "Discard Pile",
	"exhaust": "Exhaust Pile",
}
const _PILE_COLORS := {
	"draw": Color(0.40, 0.85, 0.45),
	"discard": Color(0.95, 0.70, 0.30),
	"exhaust": Color(0.65, 0.65, 0.72),
}

func _pile_for(kind: String) -> Array:
	match kind:
		"draw": return draw_pile
		"discard": return discard_pile
		"exhaust": return exhaust_pile
		_: return []

func _on_pile_clicked(kind: String) -> void:
	# Cancel any in-progress targeting so the modal doesn't trap input.
	if _targeting:
		_cancel_targeting()
	_show_pile_overlay(kind)

func _show_pile_overlay(kind: String) -> void:
	# Tear down any existing overlay so re-clicking refreshes the view.
	var prev := get_node_or_null("PileOverlay")
	if prev != null:
		prev.queue_free()

	var pile: Array = _pile_for(kind)
	var sorted_pile: Array = pile.duplicate()
	# Draw pile is shuffled - sort alphabetically so the player can scan
	# without inferring draw order (matches the JS behavior).
	if kind == "draw":
		sorted_pile.sort_custom(func(a, b):
			return a.get_display_name().to_lower() < b.get_display_name().to_lower())

	var overlay := Control.new()
	overlay.name = "PileOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var color: Color = _PILE_COLORS.get(kind, Color.WHITE)
	var title: String = _PILE_TITLES.get(kind, "Pile")

	# Click outside the panel closes the overlay.
	var panel := ModalScaffold.build_panel(overlay, color, func(): overlay.queue_free())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "%s  (%d)" % [title, pile.size()]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", color)
	vbox.add_child(header)

	if kind == "draw":
		var note := Label.new()
		note.text = "(sorted alphabetically — draw order is hidden)"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		vbox.add_child(note)

	if sorted_pile.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(empty)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(empty_lbl)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(880, 420)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(scroll)

		var grid := HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)

		for inst in sorted_pile:
			var view := CardView.new()
			grid.add_child(view)
			view.setup(inst)
			# Display-only — never enable play from the pile view.
			view.set_enabled(false)
			view.set_selected(false)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(close_row)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 36)
	close_btn.pressed.connect(func(): overlay.queue_free())
	close_row.add_child(close_btn)

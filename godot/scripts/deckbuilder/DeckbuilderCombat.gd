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

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
var exhaust_pile: Array[CardInstance] = []

# Persistent in-combat modifiers registered by `boost_cards` effects.
# Each entry: {match_tag, match_type, match_id, stat, value}. Consulted
# in `_resolve_card` so the bonus folds into the effect's value before
# dispatch. Cleared at the start of each combat.
var card_boosts: Array = []

var energy: int = 0
var max_energy: int = 3
var turn: int = 0
var phase: String = "init"           # "init" | "player" | "enemy" | "won" | "lost"

# Persistent enemy view widgets (created in start_combat, refreshed by
# _refresh_ui without rebuilding the row).
var _enemy_views: Array[EnemyView] = []

# Targeting mode (card selected, waiting for enemy click)
var _selected_card: CardInstance = null
var _targeting: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Status decay set — these statuses tick down by 1 at end of turn.
const _DECAY_STATUSES := [
	&"vulnerable", &"weak", &"frail",
	&"burn", &"poison", &"regeneration",
	&"dodge",   # dodge decays only on use in JS but treat 1/turn as safety
]

# Debuffs that get Persistence bonus when player inflicts them on enemies.
const _DEBUFFS := [
	&"vulnerable", &"weak", &"frail", &"poison", &"burn",
]

# UI refs
@onready var _enemy_area: HBoxContainer = $Layout/EnemyArea
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
	_end_turn_btn.pressed.connect(_on_end_turn)
	_draw_btn.pressed.connect(_on_pile_clicked.bind("draw"))
	_discard_btn.pressed.connect(_on_pile_clicked.bind("discard"))
	_exhaust_btn.pressed.connect(_on_pile_clicked.bind("exhaust"))
	# Pre-combat event used to fire here; events now live as dedicated
	# map nodes in the deckbuilder mini-map (Phase 2). Combat starts
	# immediately as long as the caller pre-populated enemies_to_spawn.
	if not enemies_to_spawn.is_empty():
		start_combat(enemies_to_spawn)

func start_combat(spawn_list: Array) -> void:
	_init_actors(spawn_list)
	_init_deck()
	_apply_derived_statuses()
	_build_enemy_views()
	turn = 0
	max_energy = GameState.max_energy
	GameState.phase = GameState.Phase.COMBAT
	TriggerBus.emit_signal("combat_started", {"scene": self})
	_fire_item_triggers("combat_started")
	_start_player_turn()

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
	for c in GameState.deck:
		if c is CardData:
			draw_pile.append(CardInstance.from_data(c))
		elif c is CardInstance:
			draw_pile.append(c)
	_shuffle(draw_pile)

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
	phase = "player"
	energy = max_energy
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
	draw_cards(draw_count)
	TriggerBus.emit_signal("turn_started", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_started")
	_refresh_ui()

func _on_end_turn() -> void:
	if phase != "player":
		return
	_cancel_targeting()
	# Discard hand. Ethereal cards exhaust instead of discarding if they
	# would still be in hand at end of turn (Carnage). Retain cards stay
	# in hand. The TriggerBus emit lets items react to each exhausted
	# card (mirrors the deckbuilder's normal exhaust_card flow).
	var kept: Array[CardInstance] = []
	while not hand.is_empty():
		var c: CardInstance = hand.pop_back()
		if c.data != null and c.data.retain:
			kept.append(c)
		elif c.data != null and c.data.ethereal:
			exhaust_pile.append(c)
			GameLog.add("%s is Ethereal — exhausted." % c.data.display_name, Color(0.75, 0.85, 1.0))
			TriggerBus.emit_signal("card_exhausted", {"card": c, "scene": self})
		else:
			discard_pile.append(c)
	hand = kept
	TriggerBus.emit_signal("turn_ended", {"turn": turn, "scene": self})
	_fire_item_triggers("turn_ended")
	# Decay player statuses BEFORE enemies act so debuffs the player
	# just applied to enemies survive through the enemy turn.
	_decay_statuses(player)
	phase = "enemy"
	_refresh_ui()

	_execute_enemy_turn()

	if _check_combat_end():
		return

	# Decay enemy statuses after their actions.
	for e in enemies:
		if e.is_alive():
			_decay_statuses(e)

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
	if phase == "won" or phase == "lost":
		return true
	if not player.is_alive():
		phase = "lost"
		GameState.phase = GameState.Phase.DEAD
		GameLog.add("You have been defeated.", Color(1.0, 0.4, 0.4))
		TriggerBus.emit_signal("combat_ended", {"victory": false, "scene": self})
		emit_signal("combat_ended", false)
		_show_end_overlay(false)
		_refresh_ui()
		return true
	var any_alive := false
	for e in enemies:
		if e.is_alive():
			any_alive = true
			break
	if not any_alive:
		phase = "won"
		GameLog.add("Victory!", Color(0.4, 1.0, 0.6))
		# Items with combat_ended triggers fire on victory only.
		_fire_item_triggers("combat_ended")
		TriggerBus.emit_signal("combat_ended", {"victory": true, "scene": self})
		emit_signal("combat_ended", true)
		_award_combat_gold()
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

func _fire_item_triggers(trigger_name: String) -> void:
	var sources: Array = []
	sources.append_array(GameState.inventory)
	if GameState.equipped_weapon != null:
		sources.append(GameState.equipped_weapon)
	for item in sources:
		if not (item is ItemData):
			continue
		for trig in item.triggers:
			if String(trig.get("on", "")) != trigger_name:
				continue
			GameLog.add("(%s triggers)" % item.display_name, Color(0.85, 0.9, 0.7))
			for effect in trig.get("effects", []):
				var t_str: String = effect.get("target", "self")
				var tgt: CombatActor = player
				if t_str == "all_enemies":
					for e in enemies:
						if e.is_alive():
							var ctx_e := {
								"source": player, "target": e, "scene": self, "card": null,
							}
							EffectSystem.apply(effect, ctx_e)
					continue
				var ctx := {
					"source": player, "target": tgt, "scene": self, "card": null,
				}
				EffectSystem.apply(effect, ctx)

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

var _reward_modal: Control = null
const REWARD_PICK_COUNT := 3

func _show_reward_modal() -> void:
	if _reward_modal != null:
		return
	var picks: Array = _roll_card_rewards(REWARD_PICK_COUNT)
	if picks.is_empty():
		_show_end_overlay(true)
		return

	var modal := Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	modal.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(740, 420)
	panel.position = (get_viewport_rect().size - panel.size) / 2.0
	modal.add_child(panel)

	var title := Label.new()
	title.position = Vector2(20, 16)
	title.size = Vector2(700, 32)
	title.text = "Choose a card to add to your deck"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var gold_line := Label.new()
	gold_line.position = Vector2(20, 44)
	gold_line.size = Vector2(700, 18)
	gold_line.text = "+%d gold   (total: %d)" % [_last_gold_award, GameState.gold]
	gold_line.add_theme_font_size_override("font_size", 13)
	gold_line.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	gold_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(gold_line)

	var cards_row := HBoxContainer.new()
	cards_row.position = Vector2(20, 64)
	cards_row.size = Vector2(700, 280)
	cards_row.add_theme_constant_override("separation", 16)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(cards_row)

	for c in picks:
		var card: CardData = c
		var btn := Button.new()
		btn.text = "[%d] %s\n%s\n\n%s" % [
			card.cost, card.display_name, _rarity_label(card.rarity),
			card.description,
		]
		btn.custom_minimum_size = Vector2(210, 260)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.add_theme_color_override("font_color", _rarity_color(card.rarity))
		btn.pressed.connect(func(): _on_reward_picked(card))
		cards_row.add_child(btn)

	var skip_btn := Button.new()
	skip_btn.position = Vector2(290, 360)
	skip_btn.size = Vector2(160, 44)
	skip_btn.text = "Skip reward"
	skip_btn.pressed.connect(func(): _on_reward_picked(null))
	panel.add_child(skip_btn)

	add_child(modal)
	_reward_modal = modal

func _roll_card_rewards(n: int) -> Array:
	# All non-starter cards form the offer pool. Higher Luck biases
	# toward Uncommon/Rare; Phase 1c leaves Luck at 0 so it's uniform.
	var pool: Array = []
	for c in Data.all_cards():
		if c is CardData and c.rarity != CardData.Rarity.STARTER:
			pool.append(c)
	if pool.is_empty():
		return []
	var copy := pool.duplicate()
	var picks: Array = []
	for _i in range(mini(n, copy.size())):
		var idx: int = _rng.randi() % copy.size()
		picks.append(copy[idx])
		copy.remove_at(idx)
	return picks

func _rarity_label(rarity: int) -> String:
	match rarity:
		0: return "Starter"
		1: return "Common"
		2: return "Uncommon"
		3: return "Rare"
		4: return "Legendary"
		_: return "?"

func _rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.75, 0.75, 0.75)   # starter — grey
		1: return Color(0.85, 0.85, 0.85)   # common — light grey
		2: return Color(0.4, 0.75, 1.0)     # uncommon — blue
		3: return Color(1.0, 0.85, 0.3)     # rare — gold
		_: return Color(1.0, 0.5, 1.0)      # legendary — magenta

func _on_reward_picked(card: CardData) -> void:
	if card != null:
		GameState.deck.append(CardInstance.from_data(card))
		GameLog.add("Added %s to your deck." % card.display_name, Color(0.7, 1.0, 0.8))
		GameState.emit_signal("deck_changed")
	else:
		GameLog.add("Skipped the card reward.", Color(0.8, 0.8, 0.8))
	if _reward_modal != null:
		_reward_modal.queue_free()
		_reward_modal = null
	_close(true)

func _decay_statuses(actor: CombatActor) -> void:
	for s in _DECAY_STATUSES:
		if actor.get_status(s) > 0:
			actor.add_status(s, -1)

# ------------------------------------------------------------------
# Card play
# ------------------------------------------------------------------

func _try_play_card(card: CardInstance) -> void:
	if phase != "player":
		return
	if card.get_cost() > energy:
		GameLog.add("Not enough energy for %s." % card.get_display_name(), Color(0.9, 0.7, 0.3))
		return
	# If we're already targeting and the same card is clicked, cancel.
	if _targeting and _selected_card == card:
		_cancel_targeting()
		return
	if card.wants_target():
		_selected_card = card
		_targeting = true
		GameLog.add("Choose a target for %s." % card.get_display_name(), Color(0.7, 0.9, 1.0))
		_refresh_ui()
	else:
		_resolve_card(card, null)

func _on_enemy_clicked(idx: int) -> void:
	if not _targeting or _selected_card == null:
		return
	if idx < 0 or idx >= enemies.size():
		return
	var tgt: CombatActor = enemies[idx]
	if not tgt.is_alive():
		return
	var card := _selected_card
	_cancel_targeting()
	_resolve_card(card, tgt)

func _cancel_targeting() -> void:
	_selected_card = null
	_targeting = false
	_refresh_ui()

func _resolve_card(card: CardInstance, target_enemy: CombatActor) -> void:
	energy -= card.get_cost()
	TriggerBus.emit_signal("card_played", {
		"card": card, "target": target_enemy, "scene": self,
	})

	for raw_effect in card.get_effects():
		var effect: Dictionary = _apply_card_boosts(raw_effect, card)
		var t_str: String = effect.get("target", "enemy")
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

	# Powers exhaust on play; cards with the exhaust flag exhaust; else discard.
	if card.data.exhaust or card.is_power():
		exhaust_card(card)
	else:
		discard_card(card)
	_refresh_ui()
	# Killing the last enemy with a card ends combat immediately.
	_check_combat_end()

# ------------------------------------------------------------------
# Effect callbacks (invoked by EffectSystem handlers via ctx.scene)
# ------------------------------------------------------------------

func deal_damage(source: CombatActor, target: CombatActor, base_amount: int, effect: Dictionary) -> void:
	if target == null or not target.is_alive():
		return
	var amount := base_amount

	# Source outgoing modifiers
	if source != null:
		var damage_type: String = String(effect.get("damage_type", "melee"))
		var power_mult: int = maxi(1, int(effect.get("power_multiplier", 1)))
		amount += Stats.damage_bonus(source, damage_type, Stats.Mode.DECKBUILDER, power_mult)
		if source.get_status(&"weak") > 0:
			amount = int(floor(amount * 0.75))

	# Target incoming modifiers
	if target.get_status(&"vulnerable") > 0:
		amount = int(ceil(amount * 1.5))
	if target.get_status(&"dodge") > 0:
		target.add_status(&"dodge", -1)
		GameLog.add("%s dodges!" % target.display_name, Color(0.7, 0.9, 1.0))
		return
	# (Frail affects block gained, not damage taken — handled in gain_block)

	# Block absorption
	var absorbed := mini(target.block, amount)
	target.block -= absorbed
	amount -= absorbed

	if amount > 0:
		if target.is_player:
			GameState.change_hp(-amount)
			target.hp = GameState.hp
		else:
			target.hp = maxi(0, target.hp - amount)
		var who := "you" if target.is_player else target.display_name
		GameLog.add("%s takes %d damage." % [who.capitalize(), amount], Color(1.0, 0.6, 0.6))
		TriggerBus.emit_signal("damage_taken", {
			"target": target, "attacker": source, "amount": amount, "scene": self,
		})
		if target.hp <= 0:
			target.dead = true
			GameLog.add("%s is defeated!" % target.display_name, Color(0.6, 1.0, 0.6))
			if not target.is_player:
				TriggerBus.emit_signal("enemy_killed", {"enemy": target, "scene": self})
				_fire_item_triggers("enemy_killed")
	elif absorbed > 0:
		var who := "your" if target.is_player else (target.display_name + "'s")
		GameLog.add("%s block absorbs %d." % [who, absorbed], Color(0.7, 0.8, 1.0))

	TriggerBus.emit_signal("damage_dealt", {
		"source": source, "target": target, "amount": amount, "scene": self,
	})

func gain_block(target: CombatActor, base_amount: int) -> void:
	if target == null:
		return
	var amount := base_amount
	amount += target.get_status(&"defense")
	if target.get_status(&"frail") > 0:
		amount = int(floor(amount * 0.75))
	amount = maxi(0, amount)
	target.block += amount

func heal(target: CombatActor, amount: int) -> void:
	if target == null or amount <= 0:
		return
	if target.is_player:
		GameState.change_hp(amount)
		target.hp = GameState.hp
	else:
		target.hp = mini(target.max_hp, target.hp + amount)

func apply_status(target: CombatActor, status: StringName, stacks: int, source: CombatActor = null) -> void:
	if target == null or stacks == 0:
		return
	var actual_stacks := stacks
	# Player Persistence boosts debuffs the player applies to enemies.
	if source != null and source.is_player and not target.is_player and status in _DEBUFFS:
		var pers := source.get_status(&"persistence")
		if pers > 0 and stacks > 0:
			actual_stacks += pers
	target.add_status(status, actual_stacks)
	TriggerBus.emit_signal("status_applied", {
		"target": target, "status": status, "stacks": actual_stacks, "scene": self,
	})

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
	_refresh_ui()

func discard_card(card: CardInstance) -> void:
	hand.erase(card)
	discard_pile.append(card)
	TriggerBus.emit_signal("card_discarded", {"card": card, "scene": self})
	_refresh_ui()

func exhaust_card(card: CardInstance) -> void:
	hand.erase(card)
	exhaust_pile.append(card)
	TriggerBus.emit_signal("card_exhausted", {"card": card, "scene": self})
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

# ------------------------------------------------------------------
# Discard / card-boost effect plumbing (deckbuilder)
# ------------------------------------------------------------------

const _TYPE_NAMES: Array[String] = ["attack", "skill", "power", "dice", "status", "curse", "training"]

func discard_cards(n: int, source_card = null) -> void:
	# Random discard, excluding the card currently being played so a
	# "Deal X. Discard 1." card doesn't double-route itself through
	# discard. Skip silently when hand is empty / depleted.
	for _i in range(n):
		var pool: Array = []
		for c in hand:
			if c == source_card:
				continue
			pool.append(c)
		if pool.is_empty():
			return
		var pick: CardInstance = pool[_rng.randi() % pool.size()]
		discard_card(pick)
		GameLog.add("Discarded %s." % pick.get_display_name(), Color(0.9, 0.7, 0.4))

func add_card_boost(boost: Dictionary) -> void:
	card_boosts.append(boost)
	var label: String = _boost_label(boost)
	GameLog.add("Active boost: %s." % label, Color(0.7, 1.0, 0.7))

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

func _refresh_ui() -> void:
	_turn_label.text = "Turn %d   Phase: %s%s" % [
		turn, phase,
		"   [TARGETING]" if _targeting else "",
	]
	_energy_label.text = "Energy: %d / %d" % [energy, max_energy]
	_hp_label.text = "HP: %d / %d" % [player.hp if player else 0, player.max_hp if player else 0]
	_block_label.text = "Block: %d" % (player.block if player else 0)
	_draw_btn.text = "Draw: %d" % draw_pile.size()
	_discard_btn.text = "Discard: %d" % discard_pile.size()
	_exhaust_btn.text = "Exhaust: %d" % exhaust_pile.size()

	# Enemies — refresh existing views instead of rebuilding.
	for view in _enemy_views:
		view.refresh()
		view.set_targetable(_targeting)

	# Hand — rebuild each refresh since draws / discards shuffle the row.
	# add_child first so each CardView's _ready runs and builds its child
	# controls before setup() / set_enabled() / set_selected() touch them.
	for child in _hand_area.get_children():
		child.queue_free()
	for c in hand:
		var card_inst := c     # capture per-iteration
		var view := CardView.new()
		view.play_requested.connect(_try_play_card)
		_hand_area.add_child(view)
		view.setup(card_inst)
		view.set_enabled((phase == "player") and (card_inst.get_cost() <= energy))
		view.set_selected(_targeting and _selected_card == card_inst)


func _input(event: InputEvent) -> void:
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

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.72)
	overlay.add_child(backdrop)

	# Click outside the panel closes the overlay.
	var dismiss := Button.new()
	dismiss.set_anchors_preset(Control.PRESET_FULL_RECT)
	dismiss.flat = true
	dismiss.focus_mode = Control.FOCUS_NONE
	dismiss.pressed.connect(func(): overlay.queue_free())
	overlay.add_child(dismiss)

	var color: Color = _PILE_COLORS.get(kind, Color.WHITE)
	var title: String = _PILE_TITLES.get(kind, "Pile")

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 560)
	panel.size = Vector2(900, 560)
	panel.position = -panel.size * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.12, 0.98)
	sb.border_color = color
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

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

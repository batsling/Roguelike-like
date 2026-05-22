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

# Configuration set by the caller before _ready (or via start_combat).
var enemies_to_spawn: Array = []

# ------------------------------------------------------------------
# Combat state — referenced by EffectSystem handlers via ctx.scene
# ------------------------------------------------------------------
var player: CombatActor = null
var enemies: Array[CombatActor] = []

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
var exhaust_pile: Array[CardInstance] = []

var energy: int = 0
var max_energy: int = 3
var turn: int = 0
var phase: String = "init"           # "init" | "player" | "enemy" | "won" | "lost"

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
@onready var _draw_label: Label = $Layout/Bottom/StatusBar/DrawLabel
@onready var _discard_label: Label = $Layout/Bottom/StatusBar/DiscardLabel
@onready var _block_label: Label = $Layout/Bottom/StatusBar/BlockLabel
@onready var _turn_label: Label = $Layout/Top/TurnLabel

func _ready() -> void:
	_rng.randomize()
	_end_turn_btn.pressed.connect(_on_end_turn)
	if not enemies_to_spawn.is_empty():
		start_combat(enemies_to_spawn)

func start_combat(spawn_list: Array) -> void:
	_init_actors(spawn_list)
	_init_deck()
	_apply_derived_statuses()
	turn = 0
	max_energy = GameState.max_energy
	GameState.phase = GameState.Phase.COMBAT
	TriggerBus.emit_signal("combat_started", {"scene": self})
	_start_player_turn()

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
			enemies.append(CombatActor.from_enemy(d, _rng))

func _init_deck() -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	for c in GameState.deck:
		if c is CardData:
			draw_pile.append(CardInstance.from_data(c))
		elif c is CardInstance:
			draw_pile.append(c)
	_shuffle(draw_pile)

func _apply_derived_statuses() -> void:
	player.add_status(&"power", GameState.strength / 3)
	player.add_status(&"defense", GameState.dexterity / 3)
	player.add_status(&"arcane", GameState.intelligence / 3)
	player.add_status(&"persistence", GameState.charisma / 5)
	for s in GameState.pending_combat_statuses:
		player.add_status(s.get("status", &""), s.get("stacks", 0))
	GameState.pending_combat_statuses.clear()

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
	draw_cards(GameState.hand_size)
	TriggerBus.emit_signal("turn_started", {"turn": turn, "scene": self})
	_refresh_ui()

func _on_end_turn() -> void:
	if phase != "player":
		return
	_cancel_targeting()
	# Discard hand (Ethereal exhausts; defer until those cards exist)
	while not hand.is_empty():
		discard_pile.append(hand.pop_back())
	TriggerBus.emit_signal("turn_ended", {"turn": turn, "scene": self})
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
	if not player.is_alive():
		phase = "lost"
		GameState.phase = GameState.Phase.DEAD
		GameLog.add("You have been defeated.", Color(1.0, 0.4, 0.4))
		TriggerBus.emit_signal("combat_ended", {"victory": false, "scene": self})
		emit_signal("combat_ended", false)
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
		TriggerBus.emit_signal("combat_ended", {"victory": true, "scene": self})
		emit_signal("combat_ended", true)
		_refresh_ui()
		return true
	return false

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

	for effect in card.get_effects():
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

func deal_damage(source: CombatActor, target: CombatActor, base_amount: int, _effect: Dictionary) -> void:
	if target == null or not target.is_alive():
		return
	var amount := base_amount

	# Source outgoing modifiers
	if source != null:
		amount += source.get_status(&"power")
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

func gain_energy(amount: int) -> void:
	energy += amount
	_refresh_ui()

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
	_draw_label.text = "Draw: %d" % draw_pile.size()
	_discard_label.text = "Discard: %d" % discard_pile.size()

	# Enemies
	for child in _enemy_area.get_children():
		child.queue_free()
	for i in range(enemies.size()):
		var e: CombatActor = enemies[i]
		if not e.is_alive():
			continue
		var btn := Button.new()
		var intent_text: String = e.planned_move.get("display", "?") if not e.planned_move.is_empty() else "?"
		var status_str := _status_str(e)
		btn.text = "%s\nHP %d/%d  Block %d\nIntent: %s%s" % [
			e.display_name, e.hp, e.max_hp, e.block, intent_text,
			("\n" + status_str) if status_str != "" else "",
		]
		btn.custom_minimum_size = Vector2(220, 140)
		btn.disabled = not _targeting
		if _targeting:
			# Capture i (int) so the lambda doesn't bind a stale loop var.
			var idx := i
			btn.pressed.connect(func(): _on_enemy_clicked(idx))
		_enemy_area.add_child(btn)

	# Hand
	for child in _hand_area.get_children():
		child.queue_free()
	for c in hand:
		var card := c     # capture per-iteration
		var btn := Button.new()
		var status_marker: String = " ←" if (_targeting and _selected_card == card) else ""
		btn.text = "[%d] %s%s\n%s" % [
			card.get_cost(), card.get_display_name(), status_marker, card.get_description(),
		]
		btn.custom_minimum_size = Vector2(160, 110)
		btn.disabled = (phase != "player") or (card.get_cost() > energy)
		btn.pressed.connect(func(): _try_play_card(card))
		_hand_area.add_child(btn)

func _status_str(actor: CombatActor) -> String:
	if actor.statuses.is_empty():
		return ""
	var parts: Array = []
	for s in actor.statuses.keys():
		parts.append("%s:%d" % [String(s), actor.statuses[s]])
	return "[" + "  ".join(parts) + "]"

func _input(event: InputEvent) -> void:
	# Right-click or ESC cancels targeting.
	if not _targeting:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_targeting()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_targeting()

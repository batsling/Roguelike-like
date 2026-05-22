class_name DeckbuilderCombat
extends Control

# Phase 1a combat scene skeleton. Owns the per-combat state, lays out
# the UI, and runs the draw/discard pile bookkeeping. Card play, effect
# resolution, enemy AI, and win/lose are added in the next commits.
#
# Entry point: pass an Array of EnemyData (or ids) via `enemies_to_spawn`
# before adding to tree, or use `start_combat(enemies)` after _ready.

signal combat_ended(victory: bool)

# Configuration set by the caller before _ready (or via start_combat).
var enemies_to_spawn: Array = []     # Array[EnemyData] or Array[StringName]

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

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# UI refs (assigned in _ready from the scene tree)
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
	# STR/3 → Power, DEX/3 → Defense, INT/3 → Arcane, CHA/5 → Persistence
	# Applied to player at combat start. Per the design spec these apply
	# in every combat mode, but the deckbuilder is the only mode where
	# they're authored right now.
	player.add_status(&"power", GameState.strength / 3)
	player.add_status(&"defense", GameState.dexterity / 3)
	player.add_status(&"arcane", GameState.intelligence / 3)
	player.add_status(&"persistence", GameState.charisma / 5)
	# Pending statuses carried in from pre-combat events
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
	# Player turn ends: discard hand, run enemy turn
	while not hand.is_empty():
		discard_pile.append(hand.pop_back())
	TriggerBus.emit_signal("turn_ended", {"turn": turn, "scene": self})
	# Enemy AI executes in the next commit; for now we just go back to
	# the player's next turn after a brief log line so the loop is alive.
	phase = "enemy"
	_refresh_ui()
	GameLog.add("(enemies act — AI lands in the next commit)", Color(0.7, 0.7, 0.7))
	# Loop back to next player turn
	_start_player_turn()

# ------------------------------------------------------------------
# Pile helpers — used by EffectSystem and card-play
# ------------------------------------------------------------------

func draw_cards(n: int) -> void:
	for _i in range(n):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			# Reshuffle discard into draw
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
# Enemy intent — picks the next planned move
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

	# Otherwise weighted random selection ignoring first_turn_only moves.
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
# UI refresh (placeholder text-only rendering for the skeleton)
# ------------------------------------------------------------------

func _refresh_ui() -> void:
	_turn_label.text = "Turn %d   Phase: %s" % [turn, phase]
	_energy_label.text = "Energy: %d / %d" % [energy, max_energy]
	_hp_label.text = "HP: %d / %d" % [player.hp if player else 0, player.max_hp if player else 0]
	_block_label.text = "Block: %d" % (player.block if player else 0)
	_draw_label.text = "Draw: %d" % draw_pile.size()
	_discard_label.text = "Discard: %d" % discard_pile.size()

	# Enemies — placeholder labels
	for child in _enemy_area.get_children():
		child.queue_free()
	for e in enemies:
		if not e.is_alive():
			continue
		var lbl := Label.new()
		var intent_text: String = e.planned_move.get("display", "?") if not e.planned_move.is_empty() else "?"
		var status_str := ""
		for s in e.statuses.keys():
			status_str += " [%s:%d]" % [String(s), e.statuses[s]]
		lbl.text = "%s\nHP %d/%d  Block %d\nIntent: %s%s" % [
			e.display_name, e.hp, e.max_hp, e.block, intent_text, status_str
		]
		lbl.add_theme_font_size_override("font_size", 14)
		_enemy_area.add_child(lbl)

	# Hand — placeholder labels for now (real card views in the next commit)
	for child in _hand_area.get_children():
		child.queue_free()
	for c in hand:
		var btn := Button.new()
		btn.text = "[%d] %s\n%s" % [c.get_cost(), c.get_display_name(), c.get_description()]
		btn.custom_minimum_size = Vector2(140, 100)
		btn.disabled = true     # play wiring lands in the next commit
		_hand_area.add_child(btn)

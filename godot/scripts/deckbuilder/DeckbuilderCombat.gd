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

# Persistent in-combat listeners registered by `trigger` effects
# (After Image, Demon Form, etc). Each entry: {on, effect}. The combat
# emit sites call `_fire_power_triggers(name, ctx_extras)` which walks
# this list and routes matching ones through EffectSystem. Cleared at
# combat start.
var power_triggers: Array = []

# Named consecutive-hit streaks (Dead Eye). key -> {count, target,
# attack_bonus, label}. Grown by `streak_hit` effects on attack_landed,
# wiped by `streak_reset` on attack_missed, and read in deal_damage so an
# attack_bonus streak adds its count to outgoing player attacks vs the
# tracked target. Cleared at combat start.
var _streaks: Dictionary = {}

var energy: int = 0
var max_energy: int = 3
var turn: int = 0
enum Phase { INIT, PLAYER, ENEMY, WON, LOST }
var phase: Phase = Phase.INIT

# Persistent enemy view widgets (created in start_combat, refreshed by
# _refresh_ui without rebuilding the row).
var _enemy_views: Array[EnemyView] = []
var _hand_views: Array[CardView] = []

# Targeting mode (card selected, waiting for enemy click)
var _selected_card: CardInstance = null
var _targeting: bool = false
# Following arrow shown while choosing an enemy target for a card.
var _targeting_arrow: TargetingArrow = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Status decay list and the Persistence-debuff set both live on Stats now
# (Stats.PERSISTENCE_DEBUFFS / Stats.status_apply_stacks), shared across all
# three combat modes.

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
	# Targeting arrow overlay (added last so it draws on top; ignores mouse so
	# enemy clicks still land).
	_targeting_arrow = TargetingArrow.new()
	add_child(_targeting_arrow)
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
	# Register the live context so the backpack can fire consumables into
	# this fight; the player CombatActor is the use target.
	GameState.set_combat_context(self, player)
	_build_enemy_views()
	turn = 0
	max_energy = GameState.max_energy
	GameState.phase = GameState.Phase.COMBAT
	TriggerBus.emit_signal("combat_started", {"scene": self})
	_fire_item_triggers("combat_started")
	_fire_power_triggers("combat_started")
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
	power_triggers.clear()
	_streaks.clear()
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
	phase = Phase.PLAYER
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
	_fire_power_triggers("turn_started")
	_refresh_ui()

func _on_end_turn() -> void:
	if phase != Phase.PLAYER:
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
	# Full reward pool — combat rewards aren't class-scoped (no deck choice
	# in the Godot port yet); pass a tag here to narrow them later.
	reward.setup()

func _decay_statuses(actor: CombatActor) -> void:
	Stats.decay_actor_statuses(actor)

# ------------------------------------------------------------------
# Card play
# ------------------------------------------------------------------

func _try_play_card(card: CardInstance) -> void:
	if phase != Phase.PLAYER:
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
		if _targeting_arrow != null:
			# Stem the arrow from the played card itself (top-center of its
			# hand view) so it visibly originates from the card.
			_targeting_arrow.start(_card_arrow_origin(card))
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
	_targeting = false
	if _targeting_arrow != null:
		_targeting_arrow.stop()
	_refresh_ui()

func _resolve_card(card: CardInstance, target_enemy: CombatActor) -> void:
	energy -= card.get_cost()
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

	# Powers exhaust on play; cards with the exhaust flag exhaust; else discard.
	if card.data.exhaust or card.is_power():
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
# Streak tracking (Dead Eye)
# ------------------------------------------------------------------

func streak_register_hit(key: String, target, attack_bonus: bool, label: String) -> void:
	# A landed player attack grows the named streak. Switching targets
	# resets the count first (so the bonus only rewards staying on one
	# enemy), then this hit counts as 1.
	if key == "" or target == null:
		return
	var s: Dictionary = _streaks.get(key, {"count": 0, "target": null})
	if s.get("target") != target:
		s["count"] = 0
	s["target"] = target
	s["attack_bonus"] = attack_bonus
	s["label"] = label
	s["count"] = int(s.get("count", 0)) + 1
	_streaks[key] = s

func streak_reset(key: String) -> void:
	# A whiff (Blind) wipes the streak entirely.
	if key == "":
		return
	_streaks.erase(key)

func _streak_attack_bonus(target) -> int:
	# Sum every attack_bonus streak currently locked onto `target`. Logged
	# here so the player sees the exact bonus that just landed.
	if _streaks.is_empty():
		return 0
	var bonus: int = 0
	for key in _streaks:
		var s: Dictionary = _streaks[key]
		if not bool(s.get("attack_bonus", false)) or s.get("target") != target:
			continue
		var n: int = int(s.get("count", 0))
		if n <= 0:
			continue
		bonus += n
		var label: String = String(s.get("label", ""))
		if label == "":
			label = String(key)
		GameLog.add("%s: +%d Dmg (streak %d)!" % [label, n, n], Color(0.7, 1.0, 0.7))
	return bonus

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
		base_amount += _streak_attack_bonus(target)

	# Canonical damage math lives in Stats.resolve_damage (Blind whiff,
	# Power/Weak, Vulnerable, Dodge, block soak) so all three modes agree.
	# The scene-specific tail below — logging, triggers, Soul Link, death,
	# Infuse, Thorns — stays here.
	var res := Stats.resolve_damage(source, target, base_amount, effect, Stats.Mode.DECKBUILDER, _rng)
	if res.missed:
		var who: String = "You" if source.is_player else source.display_name
		GameLog.add("%s swings blind and misses!" % who, Color(0.85, 0.85, 0.55))
		# A whiff breaks Dead Eye's streak.
		if is_player_attack:
			TriggerBus.emit_signal("attack_missed",
				{"source": source, "target": target, "scene": self})
			_fire_item_triggers("attack_missed", {"target": target})
		return
	if res.dodged:
		GameLog.add("%s dodges!" % target.display_name, Color(0.7, 0.9, 1.0))
		return
	var amount: int = int(res.hp_loss)
	var absorbed: int = int(res.blocked)

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
		_fire_power_triggers("damage_taken")
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
	# Player Persistence boosts debuffs the player applies to enemies
	# (shared rule in Stats.status_apply_stacks). Buffs to self pass through.
	var actual_stacks := stacks
	if not target.is_player:
		actual_stacks = Stats.status_apply_stacks(source, status, stacks)
	target.add_status(status, actual_stacks)
	TriggerBus.emit_signal("status_applied", {
		"target": target, "status": status, "stacks": actual_stacks, "scene": self,
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
	discard_pile.append(card)
	TriggerBus.emit_signal("card_discarded", {"card": card, "scene": self})
	_fire_power_triggers("card_discarded", {"card": card})
	_refresh_ui()

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
		view.set_enabled((phase == Phase.PLAYER) and (card_inst.get_cost() <= energy))
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

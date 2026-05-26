class_name AbilityPool
extends RefCounted

# Phase 6: the tactical Ability picker, built from the player's deck at
# combat start. Basic strikes/defends (tagged "strike" / "defend") are
# filtered out because they live on the basic Attack/Defend actions.
# Each remaining card becomes an Ability with a precomputed cooldown
# (formula in `AbilityCooldownConfig`, overridden by the card's
# `cooldown_override` when set).
#
# Casting:
#   1. UI picks an Ability and resolves targeting if needed.
#   2. Effects route through the shared EffectSystem with the tactical
#      BattleView as `scene` (it implements deal_damage/gain_block/heal).
#   3. `set_cooldown(unit, ability)` writes into BattleUnit.cooldowns;
#      BattleTurnManager ticks those at end-of-turn.

const AbilityCooldownConfigScript := preload("res://scripts/resources/AbilityCooldownConfig.gd")

class Ability extends RefCounted:
	var id: StringName
	var display_name: String
	var description: String
	var card: CardData
	var base_cooldown: int
	var wants_target: bool

var abilities: Array = []  # Array[Ability]
var config: AbilityCooldownConfig

static func build_from_deck(deck: Array, cfg: AbilityCooldownConfig = null) -> AbilityPool:
	var pool := AbilityPool.new()
	pool.config = cfg if cfg != null else AbilityCooldownConfigScript.new()
	var seen: Dictionary = {}  # dedupe by id; the deck holds many copies
	for entry in deck:
		var card: CardData = _extract_card(entry)
		if card == null or _is_basic(card):
			continue
		if seen.has(card.id):
			continue
		seen[card.id] = true
		var a := Ability.new()
		a.id = card.id
		a.display_name = card.display_name
		a.description = card.description
		a.card = card
		a.base_cooldown = pool.config.compute(card)
		a.wants_target = _wants_enemy_target(card)
		pool.abilities.append(a)
	return pool

static func _extract_card(entry) -> CardData:
	if entry == null:
		return null
	if entry is CardData:
		return entry
	if entry is CardInstance and entry.data is CardData:
		return entry.data
	return null

static func _is_basic(card: CardData) -> bool:
	return card.tags.has("strike") or card.tags.has("defend")

static func _wants_enemy_target(card: CardData) -> bool:
	for e in card.effects:
		var t = str(e.get("target", ""))
		if t == "enemy":
			return true
	return false

func find(id: StringName) -> Ability:
	for a in abilities:
		if a.id == id:
			return a
	return null

func is_ready(unit: BattleUnit, ability_id: StringName) -> bool:
	return int(unit.cooldowns.get(ability_id, 0)) <= 0

func remaining_cooldown(unit: BattleUnit, ability_id: StringName) -> int:
	return int(unit.cooldowns.get(ability_id, 0))

func set_cooldown(unit: BattleUnit, ability: Ability) -> void:
	# +1 because BattleTurnManager.tick_cooldowns runs at end-of-turn —
	# without the bump, a 2-cd ability would be ready next turn (1 tick),
	# making the formula effectively "cooldown - 1".
	unit.cooldowns[ability.id] = ability.base_cooldown + 1

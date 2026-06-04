class_name CombatActor
extends RefCounted

# Per-combat runtime state for the player or an enemy. Aggregates the
# fields combat scenes and effect handlers actually read/write —
# HP, block, statuses, planned action.
#
# The Player is constructed from GameState at combat init; enemies are
# constructed from EnemyData.

var is_player: bool = false
var display_name: String = "actor"
var max_hp: int = 0
var hp: int = 0
var block: int = 0

# Stat snapshot used for damage scaling. For the player these come from
# GameState; for enemies they start at 0 and are modified by statuses
# like "strength".
var strength: int = 0
var dexterity: int = 0
var intelligence: int = 0
var charisma: int = 0

# Statuses are a flat Dictionary: status_id -> stacks (int).
# Sign convention: positive stacks for buffs/debuffs alike.
# Stack-decay rules (e.g., Vulnerable -1 per turn) are implemented in the
# combat scene's turn lifecycle, not here.
var statuses: Dictionary = {}

# Enemies only: data-ref + planned move
var data: EnemyData = null
var planned_move: Dictionary = {}     # one entry of EnemyData.pattern

# Misc
var dead: bool = false

# ------------------------------------------------------------------
# Construction
# ------------------------------------------------------------------

static func from_player() -> CombatActor:
	var a := CombatActor.new()
	a.is_player = true
	a.display_name = "Player"
	a.max_hp = GameState.max_hp
	a.hp = GameState.hp
	# Route through Stats so item_stat_bonus folds in. Max hp/energy go
	# through the GameState setters and are already in max_hp above.
	a.strength = Stats.get_value(&"strength")
	a.dexterity = Stats.get_value(&"dexterity")
	a.intelligence = Stats.get_value(&"intelligence")
	a.charisma = Stats.get_value(&"charisma")
	return a

static func from_enemy(d: EnemyData, rng: RandomNumberGenerator) -> CombatActor:
	var a := CombatActor.new()
	a.is_player = false
	a.display_name = d.display_name
	a.data = d
	a.max_hp = rng.randi_range(d.hp_min, d.hp_max)
	a.hp = a.max_hp
	# Apply spawn-time item modifiers (Alien Baby's +3 HP, future
	# "all enemies start with X" items). Runs against every consumer
	# of from_enemy automatically, so action/strategy modes pick it
	# up the moment they wire CombatActor in.
	_apply_enemy_spawn_triggers(a)
	TriggerBus.emit_signal("enemy_spawned", {"enemy": a})
	return a

static func _apply_enemy_spawn_triggers(actor: CombatActor) -> void:
	# Walk inventory + equipped_weapon and run every effect whose trigger
	# is `enemy_spawned`. Scene is intentionally null — handlers used
	# here (add_max_hp, status, …) all support a scene-less code path
	# so they apply to the new actor without needing a combat scene.
	var sources: Array = []
	sources.append_array(GameState.inventory)
	if GameState.equipped_weapon != null:
		sources.append(GameState.equipped_weapon)
	for item in sources:
		if not (item is ItemData):
			continue
		for trig in item.triggers:
			if String(trig.get("on", "")) != "enemy_spawned":
				continue
			for effect in trig.get("effects", []):
				EffectSystem.apply(effect, {
					"source": null, "target": actor, "scene": null, "card": null,
				})

# ------------------------------------------------------------------
# Mutation helpers
# ------------------------------------------------------------------

func is_alive() -> bool:
	return not dead and hp > 0

func add_status(status: StringName, stacks: int) -> void:
	if stacks == 0:
		return
	# Status-amplify items (Empty Syringe): inflicting positive stacks of a
	# matching status on a non-player actor adds the item's bonus. Reads the
	# player's inventory, so only the player's amplifiers count, and never
	# fires on decay (stacks < 0) or on the player's own buffs.
	if stacks > 0 and not is_player:
		stacks += GameState.status_amplify_bonus(status)
	var cur := int(statuses.get(status, 0))
	var new_val := cur + stacks
	if new_val <= 0:
		statuses.erase(status)
	else:
		statuses[status] = new_val

func get_status(status: StringName) -> int:
	return int(statuses.get(status, 0))

func clear_status(status: StringName) -> void:
	statuses.erase(status)

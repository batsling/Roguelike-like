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

# Statuses flagged Permanent (addonsnew `permanent` hook): they tick like normal
# but never decay. Keyed StringName -> true; consulted by
# Stats.decay_actor_statuses via is_status_permanent().
var permanent_statuses: Dictionary = {}

# Enemies only: data-ref + planned move
var data: EnemyData = null
var planned_move: Dictionary = {}     # one entry of EnemyData.pattern

# Enemy weight class (1-5). Drives spawn frequency (future) and Vorpal matching.
# Copied off the source EnemyData/ActionEnemyData at spawn so every mode reads it
# the same way (actor.weight) regardless of which data resource built the actor.
var weight: int = 0

# Misc
var dead: bool = false

# Damage taken since this actor's last turn boundary. Accumulated from the
# TriggerBus.damage_taken signal (see Stats), read by the Shifting status, and
# reset each time Stats.tick_actor_statuses processes this actor.
var damage_taken_this_turn: int = 0

# Curl Up: cleared each turn so the gain-block-on-first-hit fires once per turn.
var curl_up_used_this_turn: bool = false

# Turns this actor has completed (bumped at its turn boundary by Stats). Drives
# per-turn damage scaling (Transient's "+10 each turn").
var turns_taken: int = 0

# Determined (addon): values rolled ONCE at first use and fixed for the rest of
# combat. key -> rolled int. Lives on the actor so a fresh CombatActor each
# combat re-rolls. Populated/read by Stats.resolve_determined.
var determined_rolls: Dictionary = {}

# Split (status): the enemy this actor splits into and how many copies, copied
# off EnemyData at spawn so the combat scene can read it without the resource.
# Empty / 0 = does not split. Set by whoever wires the split status.
var split_into: StringName = &""
var split_count: int = 0

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
	a.weight = d.weight
	a.max_hp = rng.randi_range(d.hp_min, d.hp_max)
	a.hp = a.max_hp
	# Split (status): copy the split config off the data and stamp the marker
	# status so every mode reads it the same way (Stats.should_split). Set the
	# stack directly to skip add_status's player-amplify path — it's a marker.
	a.split_into = d.split_into
	a.split_count = d.split_count
	if d.split_count > 0 and d.split_into != &"":
		a.statuses[&"split"] = 1
	# Starting statuses (e.g. Transient's Shifting, a Louse's Curl Up). Set
	# directly to skip the player-amplify path in add_status — it's the enemy's
	# own kit. A value of [lo, hi] is a Determined roll resolved once at spawn
	# (Curl Up Determined(3-7)); a plain int is the literal stack count.
	for sk in d.starting_statuses:
		var st := StringName(sk)
		var raw: Variant = d.starting_statuses[sk]
		var sv: int
		if raw is Array and raw.size() == 2:
			sv = rng.randi_range(int(raw[0]), int(raw[1]))
		else:
			sv = int(raw)
		if st != &"" and sv != 0:
			a.statuses[st] = sv
	# Flag Permanent starting statuses (addonsnew `permanent`): they tick like
	# any other status but Stats.decay_actor_statuses skips them, so the stacks
	# never erode. Same hook the strategy Troll uses, applied here so a flagged
	# status behaves identically in the deckbuilder engine.
	for ps in d.permanent_statuses:
		var pid := StringName(ps)
		if pid != &"" and a.statuses.has(pid):
			a.set_status_permanent(pid, true)
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

# Permanent statuses (addonsnew `permanent`): flagged here, skipped by decay.
func set_status_permanent(status: StringName, on: bool = true) -> void:
	if on:
		permanent_statuses[status] = true
	else:
		permanent_statuses.erase(status)

func is_status_permanent(status: StringName) -> bool:
	return permanent_statuses.has(status)

extends Node

# Mode-aware stat dispatcher. Loads StatDefinitions at startup and
# exposes the queries combat scenes / events / HUD use to read stats.
# See godot/docs/stat-dispatcher.md for the full design.

enum Mode { DECKBUILDER, ACTION, STRATEGY }

const ACTION_DASH_REGEN_SECONDS := 4.0

var _stat_defs: Dictionary = {}     # StringName -> StatDefinition

func _ready() -> void:
	_load_stat_defs()

func _load_stat_defs() -> void:
	var dir := DirAccess.open("res://data/stats/")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".tres") or fname.ends_with(".res")):
			var res: Resource = load("res://data/stats/" + fname)
			if res is StatDefinition and res.id != &"":
				_stat_defs[res.id] = res
		fname = dir.get_next()
	print("[Stats] Loaded %d stat definitions" % _stat_defs.size())

# ---------------------------------------------------------------------------
# Universal lookups
# ---------------------------------------------------------------------------

func get_value(stat_id: StringName) -> int:
	# Reads the matching field on GameState by name. The stat id must
	# match the GameState field exactly (strength / dexterity / etc.).
	return int(GameState.get(String(stat_id)))

func get_definition(stat_id: StringName) -> StatDefinition:
	return _stat_defs.get(stat_id)

func event_roll_bonus(stat_id: StringName) -> int:
	var def: StatDefinition = _stat_defs.get(stat_id)
	if def == null or not def.grants_event_roll_bonus:
		return 0
	return get_value(stat_id)

# ---------------------------------------------------------------------------
# Combat-start hook — applies universal derived statuses + drains the
# event-queued pending statuses into the actor. Called by every combat
# scene at start_combat() time.
# ---------------------------------------------------------------------------

func apply_derived_statuses(actor: CombatActor, _mode: Mode) -> void:
	for stat_id in _stat_defs:
		var def: StatDefinition = _stat_defs[stat_id]
		if def.derived_status == &"":
			continue
		var per: int = maxi(1, def.derived_per)
		@warning_ignore("integer_division")
		var stacks: int = get_value(stat_id) / per
		if stacks > 0:
			actor.add_status(def.derived_status, stacks)
	for s in GameState.pending_combat_statuses:
		actor.add_status(s.get("status", &""), s.get("stacks", 0))
	GameState.pending_combat_statuses.clear()

# ---------------------------------------------------------------------------
# Damage-type bonus — query during damage resolution. Adds the right
# extras on top of source.power based on damage_type + current mode.
# ---------------------------------------------------------------------------

func damage_bonus(source: CombatActor, damage_type: String, mode: Mode, power_multiplier: int = 1) -> int:
	if source == null:
		return 0
	var bonus: int = source.get_status(&"power") * power_multiplier
	match damage_type:
		"magic":
			bonus += source.get_status(&"arcane")
		"ranged":
			# Dexterity drives ranged damage in both Action and Strategy.
			# Deckbuilder has no ranged distinction — Power covers it.
			if mode == Mode.STRATEGY:
				bonus += _knob_int(&"dexterity", "strategy_ranged_dmg_per_point", 1) * get_value(&"dexterity")
			elif mode == Mode.ACTION:
				bonus += _knob_int(&"dexterity", "action_ranged_dmg_per_point", 1) * get_value(&"dexterity")
		_:
			# melee — Power already counted; STR per-point bonuses in
			# action / strategy land when those modes do.
			pass
	return bonus

# ---------------------------------------------------------------------------
# Speed — mode-specific accessors
# ---------------------------------------------------------------------------

func deckbuilder_bonus_draws_turn_1() -> int:
	var per_3: int = _knob_int(&"speed", "deckbuilder_draws_per_3", 1)
	@warning_ignore("integer_division")
	return (get_value(&"speed") / 3) * per_3

func action_movement_speed() -> float:
	var base: float = _knob_float(&"speed", "action_base_movespeed", 200.0)
	var per: float = _knob_float(&"speed", "action_movespeed_per_point", 10.0)
	return base + get_value(&"speed") * per

func strategy_tiles_per_turn() -> int:
	var base: int = _knob_int(&"speed", "strategy_base_tiles", 1)
	var per: int = _knob_int(&"speed", "strategy_tiles_per_point", 1)
	return base + get_value(&"speed") * per

# ---------------------------------------------------------------------------
# Dash (action mode — others spend the GameState counter directly)
# ---------------------------------------------------------------------------

func action_max_dash_charges() -> int:
	return GameState.dash_charges

# ---------------------------------------------------------------------------
# Luck
# ---------------------------------------------------------------------------

func roll_d20_with_luck(rng: RandomNumberGenerator) -> int:
	return _luck_roll(rng, 20)

func roll_chance_with_luck(rng: RandomNumberGenerator, percent: int) -> bool:
	var r1: bool = rng.randi_range(0, 99) < percent
	var luck: int = get_value(&"luck")
	if luck == 0:
		return r1
	var adv_pct: int = clampi(absi(luck) * 10, 0, 100)
	if rng.randi_range(0, 99) >= adv_pct:
		return r1
	var r2: bool = rng.randi_range(0, 99) < percent
	return (r1 or r2) if luck > 0 else (r1 and r2)

func _luck_roll(rng: RandomNumberGenerator, sides: int) -> int:
	var r1: int = rng.randi_range(1, sides)
	var luck: int = get_value(&"luck")
	if luck == 0:
		return r1
	var adv_pct: int = clampi(absi(luck) * 10, 0, 100)
	if rng.randi_range(0, 99) >= adv_pct:
		return r1
	var r2: int = rng.randi_range(1, sides)
	return maxi(r1, r2) if luck > 0 else mini(r1, r2)

# ---------------------------------------------------------------------------
# Constitution auto-gain — call when max_hp grows mid-run
# ---------------------------------------------------------------------------

func note_max_hp_change(new_max: int, old_max: int) -> void:
	var delta: int = new_max - old_max
	if delta <= 0:
		return
	@warning_ignore("integer_division")
	var gained: int = delta / 5
	if gained > 0:
		GameState.constitution += gained
		GameState.emit_signal("stats_changed")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _knob_int(stat_id: StringName, key: String, default: int) -> int:
	var def: StatDefinition = _stat_defs.get(stat_id)
	if def == null:
		return default
	return int(def.mode_data.get(key, default))

func _knob_float(stat_id: StringName, key: String, default: float) -> float:
	var def: StatDefinition = _stat_defs.get(stat_id)
	if def == null:
		return default
	return float(def.mode_data.get(key, default))

extends Node

# Stat dispatcher (post games-first cut, §11). The simulated-combat surface of
# this autoload (damage/status resolution, addons, vorpal, bleed, crit, per-mode
# combat knobs) is gone with the combat scenes. What remains is the run-stat
# machinery the surviving layers still read:
#   * StatDefinition loading + get_value (base + item bonuses + mirror/floor/
#     multiplier folding) for the HUD / Collection / RewardScreen display.
#   * event dice rolls (EventModal) + the luck-weighted chance roll (EffectSystem).
#   * note_max_hp_change (Constitution auto-gain) + the harvesting gold payout.
# See docs/stat-dispatcher.md for the original design.

var _stat_defs: Dictionary = {}     # StringName -> StatDefinition

func _ready() -> void:
	_load_stat_defs()
	# Harvesting payout: beating a game grants gold equal to the stat.
	TriggerBus.game_beaten.connect(_on_game_beaten)

func _on_game_beaten(_ctx: Dictionary) -> void:
	var harvest: int = get_value(&"harvesting")
	if harvest <= 0:
		return
	GameState.change_gold(harvest)
	GameLog.add("Harvesting: +%d gold." % harvest, Color(1.0, 0.85, 0.3))

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
	# The fully-resolved stat: base + flats + mirror + floor, then any
	# Cricket's-Head multiplier folded in last so it scales every other source.
	var total: int = value_premultiplier(stat_id)
	if GameState.stat_multiplier_active:
		var mult: float = float(GameState.stat_multiplier.get(String(stat_id), 1.0))
		if mult != 1.0:
			total = int(floor(total * mult))
	return total

# Everything get_value resolves EXCEPT the final stat_multiplier step. Exposed so
# the backpack can show the flat breakdown and the multiplier as separate parts.
func value_premultiplier(stat_id: StringName) -> int:
	var total: int = _natural_stat_value(stat_id)
	if GameState.stat_mirror_active:
		for peer in GameState.stat_mirror_pool(stat_id):
			total = maxi(total, _natural_stat_value(peer))
	if GameState.stat_floor_active:
		var field := String(stat_id)
		if GameState.stat_floor_stats.has(field):
			var hw: int = int(GameState.stat_high_water.get(field, total))
			if total > hw:
				hw = total
			GameState.stat_high_water[field] = hw
			total = hw
	return total

# A stat's stored value: its GameState field + flat item bonus + temporary buff.
func _natural_stat_value(stat_id: StringName) -> int:
	var field := String(stat_id)
	var raw = GameState.get(field)
	var base: int = int(raw) if raw != null else 0
	var bonus: int = int(GameState.item_stat_bonus.get(field, 0))
	var temp: int = int(GameState.temp_stat_bonus.get(field, 0))
	return base + bonus + temp

func get_definition(stat_id: StringName) -> StatDefinition:
	return _stat_defs.get(stat_id)

func event_roll_bonus(stat_id: StringName) -> int:
	var def: StatDefinition = _stat_defs.get(stat_id)
	if def == null or not def.grants_event_roll_bonus:
		return 0
	return get_value(stat_id)

# ---------------------------------------------------------------------------
# Luck-weighted rolls (EffectSystem chance procs, EventModal dice)
# ---------------------------------------------------------------------------

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

func roll_die_with_luck(rng: RandomNumberGenerator, sides: int) -> int:
	return _luck_roll(rng, sides)

# Decide whether this roll earns Luck advantage / disadvantage. A 10%-per-point
# chance, the sign of Luck setting the direction.
func event_luck_mode(rng: RandomNumberGenerator) -> String:
	if not GameState.active_affliction_effects("dice_disadvantage").is_empty():
		return "disadvantage"
	var lv: int = get_value(&"luck")
	if lv > 0 and rng.randi_range(0, 99) < clampi(lv * 10, 0, 100):
		return "advantage"
	if lv < 0 and rng.randi_range(0, 99) < clampi(absi(lv) * 10, 0, 100):
		return "disadvantage"
	return "normal"

# Roll a d20 under a known luck mode, exposing both dice so the event modal can
# render them. Returns { "rolls": [a] (normal) or [a, b], "used": int }.
func roll_d20_event(rng: RandomNumberGenerator, mode: String) -> Dictionary:
	var a: int = rng.randi_range(1, 20)
	if mode == "advantage" or mode == "disadvantage":
		var b: int = rng.randi_range(1, 20)
		var used: int = maxi(a, b) if mode == "advantage" else mini(a, b)
		return {"rolls": [a, b], "used": used}
	return {"rolls": [a], "used": a}

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

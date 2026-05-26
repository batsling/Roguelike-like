class_name BattleTurnManager
extends RefCounted

# Phase 4: speed-based initiative engine for a single tactical combat.
#
# Lifecycle (driven by CombatSession + battle UI):
#   1. Caller builds a list of `BattleUnit` instances and positions them
#      on a `BattleMap`.
#   2. `setup(units)` then `start_battle()` — the engine emits
#      `battle_started`, advances initiative ticks until one unit
#      overflows `ACT_THRESHOLD`, and emits `unit_turn_started(unit)`.
#   3. Whoever controls that unit (player UI or enemy AI) takes actions
#      and calls `end_current_turn()` when done. The engine ticks the
#      unit's cooldowns, emits `unit_turn_ended(unit)`, then runs
#      end-of-battle checks and either emits `battle_ended(result)` or
#      advances to the next turn.
#
# Speed model: each "tick" of the inner loop adds `speed` to every
# living unit's `act_counter`. The first counter to reach or exceed
# `ACT_THRESHOLD` is picked (highest counter wins ties, then highest
# speed); the threshold is *subtracted* (not zeroed) so excess speed
# carries into the next turn.

signal battle_started
signal battle_ended(result: String)  # "victory" | "defeat" | "draw"
signal unit_turn_started(unit: BattleUnit)
signal unit_turn_ended(unit: BattleUnit)
signal round_started(round_num: int)

const ACT_THRESHOLD := 100
# Bonus turn from Dash: queue the unit again before any normal initiative.
const DASH_BONUS_COUNTER := ACT_THRESHOLD

var units: Array[BattleUnit] = []
var current_unit: BattleUnit = null
var round_num: int = 0
var _running: bool = false
var _bonus_queue: Array[BattleUnit] = []  # Dash bonus turns

func setup(unit_list: Array) -> void:
	units.clear()
	for u in unit_list:
		units.append(u)
		u.act_counter = 0
	current_unit = null
	round_num = 0
	_running = false
	_bonus_queue.clear()

func start_battle() -> void:
	if _running:
		return
	_running = true
	emit_signal("battle_started")
	_begin_round()
	_advance()

func end_current_turn() -> void:
	if current_unit == null:
		return
	current_unit.tick_cooldowns()
	# Mid-turn block decays at end of turn (defensive stance is a one-turn buy).
	current_unit.block = 0
	var done := current_unit
	current_unit = null
	emit_signal("unit_turn_ended", done)
	if _check_battle_end():
		return
	_advance()

# Player API: spend the per-combat Dash to queue a bonus turn immediately
# after the current one. Returns true if Dash was available and consumed.
# Run the victory/defeat check now (rather than only at end-of-turn).
# Callers invoke this after damage resolves so combat can wrap up
# immediately when the last enemy or the player drops to 0 hp.
# Returns true if the battle has ended (and `battle_ended` was emitted).
func check_battle_end_now() -> bool:
	if not _running:
		return false
	return _check_battle_end()

func consume_dash() -> bool:
	if current_unit == null or not current_unit.dash_available:
		return false
	current_unit.dash_available = false
	_bonus_queue.append(current_unit)
	return true

func living_units() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in units:
		if u.is_alive():
			out.append(u)
	return out

# --- Internal ----------------------------------------------------------

func _advance() -> void:
	if not _running:
		return
	if _check_battle_end():
		return
	# Dash bonus turns trump natural initiative.
	while not _bonus_queue.is_empty():
		var bonus = _bonus_queue.pop_front()
		if bonus != null and bonus.is_alive():
			_begin_turn(bonus)
			return
	# Tick units until someone overflows.
	# Safety cap on ticks per advance: a unit with speed=1 needs 100 ticks.
	# If somehow no one moves in 10k ticks the engine is broken; bail.
	var safety := 0
	while safety < 10000:
		var ready = _pick_ready_unit()
		if ready != null:
			ready.act_counter -= ACT_THRESHOLD
			_begin_turn(ready)
			return
		_tick_all()
		safety += 1
	push_error("BattleTurnManager._advance: no unit became ready after 10k ticks")

func _pick_ready_unit() -> BattleUnit:
	var best: BattleUnit = null
	for u in units:
		if not u.is_alive():
			continue
		if u.act_counter < ACT_THRESHOLD:
			continue
		if best == null:
			best = u
			continue
		if u.act_counter > best.act_counter:
			best = u
		elif u.act_counter == best.act_counter and u.speed > best.speed:
			best = u
	return best

func _tick_all() -> void:
	for u in units:
		if u.is_alive():
			u.act_counter += u.speed

func _begin_round() -> void:
	round_num += 1
	emit_signal("round_started", round_num)

func _begin_turn(unit: BattleUnit) -> void:
	current_unit = unit
	if unit.is_player:
		unit.mana = mini(unit.mana + unit.mana_regen, unit.max_mana)
	emit_signal("unit_turn_started", unit)

func _check_battle_end() -> bool:
	var player_alive := false
	var enemy_alive := false
	for u in units:
		if not u.is_alive():
			continue
		if u.is_player:
			player_alive = true
		else:
			enemy_alive = true
	if not player_alive and not enemy_alive:
		_finish("draw")
		return true
	if not player_alive:
		_finish("defeat")
		return true
	if not enemy_alive:
		_finish("victory")
		return true
	return false

func _finish(result: String) -> void:
	_running = false
	current_unit = null
	emit_signal("battle_ended", result)

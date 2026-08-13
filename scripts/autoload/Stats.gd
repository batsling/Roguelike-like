extends Node

# Stat dispatcher (post games-first cut, §11). The simulated-combat surface of
# this autoload (damage/status resolution, addons, vorpal, bleed, crit, per-mode
# combat knobs) is gone with the combat scenes. What remains is the run-stat
# machinery the surviving layers still read:
#   * StatDefinition loading + get_value (base + item bonuses + mirror/floor/
#     multiplier folding) for the HUD / Collection / RewardScreen display.
#   * LUCK — every random decision in the run rolls through one of the four
#     functions in the Luck section below. See the comment there; it is the one
#     stat that touches everything else.
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

# LUCK — one guaranteed reroll per point, and you keep the better result.
#
# Every random decision in the run goes through one of the four rolls below, and
# every one of them works the same way: make the roll, then make `Luck` MORE
# rolls, and keep the best of them. At 1 Luck a 25% chance is really 43.75%
# (1 - 0.75²); at 3 Luck it is 68%. Negative Luck is the same machine pointed the
# other way — |Luck| extra rolls, keep the WORST — so a run carrying -2 sees that
# same 25% land at 1.6%.
#
# This replaced a 10%-per-point chance of ADVANTAGE (roll twice, sometimes). The
# difference is not a tuning change: the old one did nothing at all nine times in
# ten at a single point, so Luck was a stat you could hold and never see. A
# guaranteed reroll is a thing the player can feel on the first roll after they
# pick up the Clover.
#
# --- which way is "better" -------------------------------------------------
#
# The reroll is only meaningful when the roll has a side the player wants, and
# most do not say so on their own. So every call site DECLARES its direction and
# the ones with no honest answer opt out:
#
#   Favour.HIGH  a bigger number / a success is what the player wants. The
#                rarity ladder, a chest gamble, the Donation Machine's 5% Luck
#                payout, how many pickups a bombed machine scatters.
#   Favour.LOW   success is the bad outcome. The Donation Machine's jam, Curse
#                of Decay's item downgrade.
#   Favour.NONE  there is no better side, so Luck stays out of it. Which of the
#                twelve Commons you drew; whether the Blood Donation Machine
#                burst a Blood Bag or an IV Bag; heads or tails on a pickup.
#
# The one that reads backwards is worth spelling out: the Blood Donation
# Machine's 6.7% explosion is Favour.HIGH. Bursting pays an Event relic and one
# gold does not, so Luck makes the machine MORE likely to blow up in your face,
# which is the outcome you were feeding it for.
enum Favour { HIGH, LOW, NONE }

# How many EXTRA rolls Luck buys, and which way they point. Split out so a caller
# can quote the real odds on a button (EventSystem.chance_percent) with the same
# numbers the roll will use.
func luck_rerolls() -> int:
	return absi(get_value(&"luck"))

func luck_keeps_high() -> bool:
	return get_value(&"luck") >= 0

# A percentage roll. `percent` is a float because odds are the one quantity in
# this build that may be fractional — one-in-fifteen is 6.7%, and an int would
# make the number on the button not the number the machine rolls.
func roll_chance(rng: RandomNumberGenerator, percent: float, favour: int = Favour.HIGH) -> bool:
	var hit: bool = rng.randf() * 100.0 < percent
	if favour == Favour.NONE:
		return hit
	# Keeping the best of N booleans is "any of them hit" when hitting is good,
	# and "all of them hit" when hitting is bad — the second is what makes Luck
	# steer you AWAY from a jam rather than into it.
	var wants_hit: bool = (favour == Favour.HIGH) == luck_keeps_high()
	for _i in range(luck_rerolls()):
		var again: bool = rng.randf() * 100.0 < percent
		hit = (hit or again) if wants_hit else (hit and again)
	return hit

# The odds `roll_chance` will actually apply, as a percentage — what a button
# quotes so the number the player reads is the number that gets rolled. Luck
# compounds multiplicatively, which is why this is not `percent * (1 + luck)`.
func effective_chance(percent: float, favour: int = Favour.HIGH) -> float:
	if favour == Favour.NONE:
		return clampf(percent, 0.0, 100.0)
	var p: float = clampf(percent, 0.0, 100.0) / 100.0
	var tries: int = luck_rerolls() + 1
	var wants_hit: bool = (favour == Favour.HIGH) == luck_keeps_high()
	# "any of `tries` hit" = 1 - (1-p)^tries; "all of them hit" = p^tries.
	var out: float = (1.0 - pow(1.0 - p, tries)) if wants_hit else pow(p, tries)
	return clampf(out * 100.0, 0.0, 100.0)

# An integer in [lo, hi] — how many pickups a burst machine scatters, how much
# gold comes back out of a bombed bank.
func roll_range(rng: RandomNumberGenerator, lo: int, hi: int, favour: int = Favour.HIGH) -> int:
	if hi < lo:
		var swap: int = lo
		lo = hi
		hi = swap
	var best: int = rng.randi_range(lo, hi)
	if favour == Favour.NONE or lo == hi:
		return best
	var keep_high: bool = (favour == Favour.HIGH) == luck_keeps_high()
	for _i in range(luck_rerolls()):
		var again: int = rng.randi_range(lo, hi)
		best = (maxi(best, again) if keep_high else mini(best, again))
	return best

# A step on the 75/20/5 rarity ladder. Always Favour.HIGH — a rarer thing is the
# better thing, everywhere this is asked. This is the roll that carries Luck to
# most of the build: item rewards, chest sizes, scrolls, shop stock and the
# object pools all walk this ladder, so they all inherit the reroll without
# knowing Luck exists.
func roll_rarity_step_with_luck(rng: RandomNumberGenerator) -> int:
	var best: int = Data.roll_rarity_step(rng)
	for _i in range(luck_rerolls()):
		var again: int = Data.roll_rarity_step(rng)
		best = (maxi(best, again) if luck_keeps_high() else mini(best, again))
	return best

# Kept for the legacy 1.0 callers that pass an int percent; success is good.
func roll_chance_with_luck(rng: RandomNumberGenerator, percent: int) -> bool:
	return roll_chance(rng, float(percent), Favour.HIGH)

func roll_die_with_luck(rng: RandomNumberGenerator, sides: int) -> int:
	return roll_range(rng, 1, sides, Favour.HIGH)

# Decide whether this roll earns Luck advantage / disadvantage — the EventModal's
# d20, which shows its dice and so needs the mode named rather than folded in.
# Now that a reroll is guaranteed, "advantage" is simply the sign of Luck; the
# affliction still forces disadvantage over the top of it.
func event_luck_mode(_rng: RandomNumberGenerator) -> String:
	if not GameState.active_affliction_effects("dice_disadvantage").is_empty():
		return "disadvantage"
	var lv: int = get_value(&"luck")
	if lv > 0:
		return "advantage"
	if lv < 0:
		return "disadvantage"
	return "normal"

# Roll a d20 under a known luck mode, exposing every die so the event modal can
# render them. One extra die PER POINT of Luck, not a single second die: the d20
# is a roll like any other and gets the same rerolls everything else does.
# Returns { "rolls": [a, …], "used": int }.
func roll_d20_event(rng: RandomNumberGenerator, mode: String) -> Dictionary:
	var rolls: Array = [rng.randi_range(1, 20)]
	if mode == "advantage" or mode == "disadvantage":
		for _i in range(maxi(1, luck_rerolls())):
			rolls.append(rng.randi_range(1, 20))
	var used: int = int(rolls[0])
	for r in rolls:
		used = maxi(used, int(r)) if mode == "advantage" else mini(used, int(r))
	return {"rolls": rolls, "used": used}

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

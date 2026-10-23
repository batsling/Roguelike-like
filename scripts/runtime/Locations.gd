class_name Locations
extends RefCounted

# LOCATIONS — the floor the run stands on between two difficulty steps
# (docs/locations-design.md; the owner, 23 Oct 2026).
#
# A run is dealt a Low location when it starts and a new one, of the new tier, at
# every DIFFICULTY UP. Nobody chooses it: it arrives with a popup showing its art
# and what it does, and it sits beside the difficulty on the board's strip, where
# hovering it says the same again. A location has no goal. It does three kinds of
# thing, all authored in the sheet (LocationData):
#
#   arrive    once, when it is dealt: bodies walk on, tiles are lit, units stand up
#   standing  for as long as you are there: hits are doubled, a rift sits in the
#             offering
#   actions   a button on its card, usable a few times while you are there
#
# …and it LEANS THE ROLLS: anything carrying one of its tags weighs (1 + tag_up)
# in whatever roll it is in — an enemy, a boss, a relic in a chest, a piece of
# loot, a unit a location lays. `pick` is that, and every roll that should feel a
# location goes through it.
#
# Static and stateless: the run's location is GameLoop2's (`location_id`, saved
# with the board), because what it does lands on the board.

# The location the run is standing in, or null — before a run, or with an empty
# roster (the suite's, test/pre_run_hook.gd).
static func current() -> LocationData:
	if GameLoop2.location_id == &"":
		return null
	return Data.get_location(GameLoop2.location_id)

# --- the tag boost (§4) -----------------------------------------------------

# Whether anything is being leaned right now. The cheap question every roll asks
# first, so a run with no lean keeps its rolls EXACTLY as they were — the same
# random draws, in the same order — rather than a weighted draw that happens to
# come out uniform.
static func is_leaning() -> bool:
	var loc: LocationData = current()
	return loc != null and loc.tag_up > 0.0 and not loc.tag_types.is_empty()

# The tags a candidate carries, whatever kind of thing it is. An enemy keeps a
# comma list in one field (`has_tag` reads it); everything else that has tags
# keeps a PackedStringArray called `tags`.
static func tags_of(thing) -> PackedStringArray:
	if thing is GoalEnemyData:
		return (thing as GoalEnemyData).tag_list()
	if thing is Object and "tags" in thing:
		var out := PackedStringArray()
		for t in thing.get("tags"):
			out.append(String(t).strip_edges().to_lower())
		return out
	return PackedStringArray()

# How much `thing` weighs in a roll here: 1, or 1 + tag_up when it carries any of
# the location's tags. Several matching tags count once — "+20% for fire things",
# not +20% per tag.
static func weight_of(thing) -> float:
	var loc: LocationData = current()
	if loc == null or loc.tag_up <= 0.0:
		return 1.0
	for t in tags_of(thing):
		if loc.tag_types.has(t):
			return 1.0 + loc.tag_up
	return 1.0

# ONE OF `bucket`, leaned. With nothing to lean it is exactly the uniform pick it
# replaced — `rng.randi_range` when the caller rolls on its own stream, the global
# `randi()` when it does not — so seeded tests and saves draw what they always did.
static func pick(bucket: Array, rng: RandomNumberGenerator = null) -> Variant:
	if bucket.is_empty():
		return null
	if not is_leaning():
		if rng != null:
			return bucket[rng.randi_range(0, bucket.size() - 1)]
		return bucket[randi() % bucket.size()]
	var weights: Array = []
	for x in bucket:
		weights.append(weight_of(x))
	return pick_weighted(bucket, weights, rng)

# One of `bucket` by explicit `weights` (same length). A weight of 0 is never
# drawn; all-zero falls back to the uniform pick.
static func pick_weighted(bucket: Array, weights: Array, rng: RandomNumberGenerator = null) -> Variant:
	if bucket.is_empty():
		return null
	var total: float = 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	var roll: float
	if total <= 0.0:
		return bucket[rng.randi_range(0, bucket.size() - 1)] if rng != null \
			else bucket[randi() % bucket.size()]
	roll = (rng.randf() if rng != null else randf()) * total
	var last: Variant = null
	for i in range(bucket.size()):
		var w: float = maxf(0.0, float(weights[i]))
		if w <= 0.0:
			continue
		last = bucket[i]
		roll -= w
		if roll < 0.0:
			return bucket[i]
	return last

# --- what the location makes true while you are there -----------------------

# Every hit that lands on you is worth this many times as much (Dark Room, The
# Chest). Folded into GameState.combat_totals, so the swing, a status's bill and
# every preview of them read the same number.
static func damage_taken_mult() -> float:
	var loc: LocationData = current()
	return loc.standing_value(&"damage_taken_mult", 1.0) if loc != null else 1.0

# How many cards of every offering are a free rift card (The Void).
static func offering_rifts() -> int:
	var loc: LocationData = current()
	return int(loc.standing_value(&"offering_rift", 0.0)) if loc != null else 0

# How many times as far every push goes (The Moon): the Push verb's one cell and a
# weapon's shove alike. A whole number, because a body stands on whole squares.
static func push_mult() -> int:
	var loc: LocationData = current()
	return maxi(1, int(loc.standing_value(&"push_mult", 1.0))) if loc != null else 1

# --- the deal ---------------------------------------------------------------

# The location dealt at `tier`: a random one authored there. A tier with none
# authored steps DOWN to the nearest one that has some, the way an enemy roll
# widens — the roster is six rows and growing, and an empty rung must not leave
# the run without a floor. `avoid` (the one the run is leaving) is skipped when
# anything else is on offer. Null only with an empty roster.
static func deal(tier: int, rng: RandomNumberGenerator = null, avoid: StringName = &"") -> LocationData:
	for step in range(clampi(tier, 0, RunDifficulty.MAX_TIER), -1, -1):
		var here: Array = Data.locations_at(step)
		if here.is_empty():
			continue
		var fresh: Array = here.filter(func(l): return (l as LocationData).id != avoid)
		var pool: Array = fresh if not fresh.is_empty() else here
		return pool[rng.randi_range(0, pool.size() - 1)] if rng != null \
			else pool[randi() % pool.size()]
	return null

# --- words ------------------------------------------------------------------

static func tier_name(loc: LocationData) -> String:
	return RunDifficulty.tier_name(loc.tier) if loc != null else ""

# The lean in words — "Fire things turn up 20% more often here." — or "".
static func lean_text(loc: LocationData) -> String:
	if loc == null or loc.tag_up <= 0.0 or loc.tag_types.is_empty():
		return ""
	var names: PackedStringArray = []
	for t in loc.tag_types:
		names.append(String(t).capitalize())
	return "%s things turn up %d%% more often here — enemies, bosses, relics and loot." % [
		" and ".join(names), roundi(loc.tag_up * 100.0)]

# What a `spend` cost is called on a button, where the field's own name is not
# the game's word for it.
const SPEND_WORDS := {"bonus_shields": "Shields", "shields": "Temporary Shields", "gold": "Gold"}

# An action's button text: "Lose 2 Max Health: +1 Devilish Small Chest (3 left)".
static func action_text(action: Dictionary, used: int) -> String:
	var cost: Dictionary = action.get("cost", {})
	var pay: Dictionary = action.get("pay", {})
	var c: String = ""
	match String(cost.get("op", "")):
		"lose_max_hp":
			c = "Lose %d Max Health" % int(cost.get("value", 1))
		"spend":
			var n: int = int(cost.get("value", 1))
			var stat: String = String(cost.get("stat", ""))
			var word: String = String(SPEND_WORDS.get(stat, stat.capitalize()))
			c = "Spend %d %s" % [n, word.trim_suffix("s") if n == 1 else word]
	var p: String = "a reward"
	if String(pay.get("op", "")) == "effect":
		p = String((pay.get("effect", {}) as Dictionary).get("type", "a reward")).replace("_", " ")
	elif String(pay.get("op", "")) == "gain_chest":
		var size: String = String(Data.CHEST_SIZE_NAMES.get(int(pay.get("size", 0)), "Small"))
		var pool: String = String(pay.get("pool", ""))
		p = "+1 %s%s Chest" % [(pool.capitalize() + " ") if pool != "" else "", size]
	var left: int = maxi(0, int(action.get("limit", 1)) - used)
	return "%s: %s (%d left)" % [c, p, left]

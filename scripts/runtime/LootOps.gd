class_name LootOps
extends RefCounted

# THE EFFECT OPS MORE THAN ONE LOOT KIND CARRIES, written once.
#
# Pills, potions and scrolls each resolve their own op list (`_apply_one` in
# PillSystem, PotionSystem and ScrollSystem), and most of each list is that kind's
# own business. These few are not: a pill's and a potion's `gain_hp` were the same
# five lines, character for character, and so were their `gain_max_hp` and the
# Sacred Bark scaling under both. Two copies of a rule is one place to fix it and
# one place to forget, so the shared half lives here and each system keeps only
# the `match` arm that calls it.

# One field of an op as it resolves for THIS player, Sacred Bark folded in.
# `scaled_fields` is the calling kind's own table (op -> the fields that scale),
# because which numbers double is a per-kind decision.
static func scaled_value(op: Dictionary, field: String, fallback: int,
		scaled_fields: Dictionary) -> int:
	var raw: int = int(op.get(field, fallback))
	var fields: Array = scaled_fields.get(String(op.get("op", "")), [])
	if not fields.has(field):
		return raw
	var mult: int = GameState.loot_multiplier()
	if mult <= 1:
		return raw
	# A field the loot never authored takes its own default times the multiplier,
	# which is what "doubled" means for a count nobody wrote down.
	return maxi(1, raw) * mult

static func gain_hp(amount: int, out: Dictionary) -> bool:
	GameState.change_hp(amount)
	out["logs"].append("You gain +%d Health." % amount)
	return true

# Raising the cap heals by the same amount (spec §3) — the container arrives full,
# which is what makes Health Up worth taking at full Health.
static func gain_max_hp(amount: int, out: Dictionary) -> bool:
	var up: int = GameState.max_hp_gain(amount)
	GameState.change_max_hp(up)
	GameState.change_hp(up, GameState.HEALTH_SOURCE_MAX_HP_FILL)
	out["logs"].append("You gain +%d Max Health." % up)
	return true

# A teleport as the overworld's request (movement belongs to the overworld, so
# loot asks rather than reaching into the map). `amulet` lands 1-3 from the
# Amulet (Telepills' bad roll); anything else keeps you about where you were.
static func teleport_request(op: Dictionary) -> Dictionary:
	var req := {"kind": "teleport", "dir": String(op.get("dir", "same"))}
	if req["dir"] == "amulet":
		req["min"] = int(op.get("min", 1))
		req["max"] = int(op.get("max", 3))
	else:
		req["spread"] = int(op.get("spread", 1))
	return req

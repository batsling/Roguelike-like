class_name CardInstance
extends RefCounted

# Runtime wrapper around a CardData. Holds per-card transient state
# (upgraded form, temporary cost overrides, etc.). The deck stores
# CardInstance refs; saves serialize them back to ids + upgrade flag.

var data: CardData = null
var upgraded: bool = false
var temp_cost_override: int = -999      # -999 sentinel = no override

# Persistent additive bonuses to specific effect fields, set by weapon
# verification (and any future "this card permanently gains +N" hook).
# Shape: { effect_index(int) -> { field(String) -> bonus(int) } }
# For Bag o' Glitter after a +1 Blind verification:
#   { 0: { "stacks": 1 } }
var effect_bonuses: Dictionary = {}

# If this card was granted by a weapon item, the item's instance_id.
# Drives the bidirectional pairing — removing the weapon removes this
# card; removing this card removes the weapon. 0 = not weapon-linked.
var source_weapon_id: int = 0

static func from_data(d: CardData, is_upgraded: bool = false) -> CardInstance:
	var c := CardInstance.new()
	c.data = d
	c.upgraded = is_upgraded
	return c

func get_cost() -> int:
	if temp_cost_override != -999:
		return temp_cost_override
	return data.get_effective_cost(upgraded)

func get_effects() -> Array:
	# Layer per-instance effect_bonuses on top of CardData's effects
	# without mutating the shared Resource. Empty bonuses path returns
	# the base array directly so the hot path stays allocation-free.
	var base: Array = data.get_effective_effects(upgraded)
	if effect_bonuses.is_empty():
		return base
	var out: Array = []
	for i in range(base.size()):
		var e: Dictionary = (base[i] as Dictionary).duplicate()
		if effect_bonuses.has(i):
			for field in effect_bonuses[i].keys():
				e[field] = int(e.get(field, 0)) + int(effect_bonuses[i][field])
		out.append(e)
	return out

func get_description() -> String:
	var base: String = data.get_effective_description(upgraded)
	if effect_bonuses.is_empty():
		return base
	# Annotate with a compact bonus summary so the player sees what the
	# weapon has gained. Format mirrors a quick "Bag o' Glitter +1 stacks"
	# style; the underlying effects already use the bumped numbers.
	var parts: Array = []
	for i in effect_bonuses.keys():
		for field in effect_bonuses[i].keys():
			var v: int = int(effect_bonuses[i][field])
			parts.append("+%d %s" % [v, field] if v >= 0 else "%d %s" % [v, field])
	if parts.is_empty():
		return base
	return "%s  [%s]" % [base, ", ".join(parts)]

func bump_effect(effect_index: int, field: String, amount: int) -> void:
	# Mutate this instance's persistent bonus. Adds to any existing bonus
	# on the same (effect, field) pair so multiple verifications stack.
	if amount == 0:
		return
	if not effect_bonuses.has(effect_index):
		effect_bonuses[effect_index] = {}
	var f: Dictionary = effect_bonuses[effect_index]
	f[field] = int(f.get(field, 0)) + amount

func get_display_name() -> String:
	if upgraded:
		return data.display_name + "+"
	return data.display_name

func is_attack() -> bool:
	return data.is_attack()

func is_skill() -> bool:
	return data.is_skill()

func is_power() -> bool:
	return data.is_power()

func wants_target() -> bool:
	# A card needs a single-enemy target if any of its effects has
	# target = "enemy" (i.e., single-target) without being AoE.
	for e in get_effects():
		var t = e.get("target", "")
		if t == "enemy":
			return true
	return false

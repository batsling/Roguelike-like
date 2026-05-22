class_name CardInstance
extends RefCounted

# Runtime wrapper around a CardData. Holds per-card transient state
# (upgraded form, temporary cost overrides, etc.). The deck stores
# CardInstance refs; saves serialize them back to ids + upgrade flag.

var data: CardData = null
var upgraded: bool = false
var temp_cost_override: int = -999      # -999 sentinel = no override

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
	return data.get_effective_effects(upgraded)

func get_description() -> String:
	return data.get_effective_description(upgraded)

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

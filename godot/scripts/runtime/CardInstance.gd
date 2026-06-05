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
	# without mutating the shared Resource, then append any item-granted
	# effects (Brass Knuckles etc.). Empty bonuses + no grants returns the
	# base array directly so the hot path stays allocation-free.
	var base: Array = data.get_effective_effects(upgraded)
	var grants: Array = CardMods.granted_effects(data)
	if effect_bonuses.is_empty() and grants.is_empty():
		return base
	var out: Array = []
	for i in range(base.size()):
		var e: Dictionary = (base[i] as Dictionary).duplicate()
		if effect_bonuses.has(i):
			for field in effect_bonuses[i].keys():
				e[field] = int(e.get(field, 0)) + int(effect_bonuses[i][field])
		out.append(e)
	out.append_array(grants)
	return out

func get_description() -> String:
	var base: String = data.get_effective_description(upgraded)
	# Tack on any item-driven card_played triggers whose filter matches
	# this card, so e.g. Bird Head ("strikes inflict Soul Link") makes
	# every Strike-tagged card visibly read "Deal 6 Dmg Melee. Inflict
	# Soul Link." in hand, shop, rest site, etc.
	var trigger_extra: String = _format_card_played_trigger_addendum()
	if trigger_extra != "":
		base = "%s %s" % [base, trigger_extra]
	# Item "card gains effect" grants (Brass Knuckles -> "Inflict Bruise.").
	var grant_extra: String = CardMods.describe(data)
	if grant_extra != "":
		base = "%s %s" % [base, grant_extra]
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

# Walks GameState.inventory + equipped_weapon and returns a description
# fragment for every card_played item trigger whose `if_card_tag` /
# `if_card_id` filter would let it fire on this card. Returns "" if
# nothing applies. Mirrors the gate logic in
# DeckbuilderCombat._fire_item_triggers — keep the two in sync.
func _format_card_played_trigger_addendum() -> String:
	if data == null:
		return ""
	var sources: Array = []
	sources.append_array(GameState.inventory)
	if GameState.equipped_weapon != null:
		sources.append(GameState.equipped_weapon)
	if sources.is_empty():
		return ""
	var fragments: PackedStringArray = PackedStringArray()
	for item in sources:
		if not (item is ItemData):
			continue
		for trig in item.triggers:
			if String(trig.get("on", "")) != "card_played":
				continue
			var tag_gate: String = String(trig.get("if_card_tag", ""))
			if tag_gate != "" and not data.tags.has(tag_gate):
				continue
			var id_gate: String = String(trig.get("if_card_id", ""))
			if id_gate != "" and String(data.id) != id_gate:
				continue
			for effect in trig.get("effects", []):
				var phrase: String = CardMods._effect_to_phrase(effect)
				if phrase != "":
					fragments.append(phrase)
	if fragments.is_empty():
		return ""
	return " ".join(fragments)

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
	# Indiscriminate (Blood Magic) re-rolls the target per hit, so the
	# play UI doesn't need to ask — the engine picks for you.
	if data != null and (data.addons.has("indiscriminate") or data.addons.has("cleave")):
		return false
	for e in get_effects():
		var t = e.get("target", "")
		if t == "enemy":
			return true
	return false

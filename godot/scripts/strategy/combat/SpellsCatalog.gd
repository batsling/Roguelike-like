class_name SpellsCatalog
extends RefCounted

# Phase 6: ports the legacy `data/spells-data.js` (SPELLS_DATA) into Godot
# SpellData resources for the strategy spellbook. The original effects
# were raw text parsed at runtime; here we map each spell to the
# structured EffectSystem form, simplifying exotic keywords (Cleave,
# Cooldown, Engage, Channel) to nearest tactical equivalents. Designers
# can later replace inline defs with `.tres` files under `res://data/spells/`
# and load them via the Data autoload — `all()` already exposes the same
# shape an external loader would.

const SpellDataScript := preload("res://scripts/resources/SpellData.gd")

# Each def keeps the legacy ordering for parity with SPELLS_DATA.
const _DEFS: Array = [
	{
		"id": &"abyss", "name": "Abyss", "cost": 6, "rarity": SpellData.Rarity.RARE,
		"desc": "Deal damage equal to half the target's max HP.",
		"effects": [{"type": "dmg_fraction_max_hp", "value": 0.5, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"balance", "name": "Balance", "cost": 3, "rarity": SpellData.Rarity.UNCOMMON,
		"desc": "Deal 1 to all enemies, heal 1.",
		"effects": [
			{"type": "dmg", "value": 1, "target": "all_enemies"},
			{"type": "heal", "value": 1, "target": "self"},
		],
		"target": "none",
	},
	{
		"id": &"bind", "name": "Bind", "cost": 3, "rarity": SpellData.Rarity.RARE,
		"desc": "Target gains 1 Buffer (block).",
		"effects": [{"type": "block", "value": 1, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"blaze", "name": "Blaze", "cost": 6, "rarity": SpellData.Rarity.RARE,
		"desc": "Deal 13 fire damage to a target.",
		"effects": [{"type": "dmg", "value": 13, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"burn", "name": "Burn", "cost": 1, "rarity": SpellData.Rarity.UNCOMMON,
		"desc": "Deal 1 fire damage.",
		"effects": [{"type": "dmg", "value": 1, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"crush", "name": "Crush", "cost": 3, "rarity": SpellData.Rarity.RARE,
		"desc": "Deal 3 damage to all enemies.",
		"effects": [{"type": "dmg", "value": 3, "target": "all_enemies"}],
		"target": "none",
	},
	{
		"id": &"flick", "name": "Flick", "cost": 1, "rarity": SpellData.Rarity.UNCOMMON,
		"desc": "Deal 1 magic damage.",
		"effects": [{"type": "dmg", "value": 1, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"gaze", "name": "Gaze", "cost": 2, "rarity": SpellData.Rarity.COMMON,
		"desc": "Foresight: gain 2 block (placeholder).",
		"effects": [{"type": "block", "value": 2, "target": "self"}],
		"target": "self",
	},
	{
		"id": &"harvest", "name": "Harvest", "cost": 1, "rarity": SpellData.Rarity.RARE,
		"desc": "Deal 4 damage. If it kills, refund 3 mana.",
		"effects": [{"type": "dmg", "value": 4, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"infinity", "name": "Infinity", "cost": 15, "rarity": SpellData.Rarity.RARE,
		"desc": "Deal damage equal to the target's max HP.",
		"effects": [{"type": "dmg_fraction_max_hp", "value": 1.0, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"mend", "name": "Mend", "cost": 2, "rarity": SpellData.Rarity.COMMON,
		"desc": "Heal 10.",
		"effects": [{"type": "heal", "value": 10, "target": "self"}],
		"target": "self",
	},
	{
		"id": &"miasma", "name": "Miasma", "cost": 3, "rarity": SpellData.Rarity.RARE,
		"desc": "Deal 1 to all enemies (poison-flavored).",
		"effects": [{"type": "dmg", "value": 1, "target": "all_enemies"}],
		"target": "none",
	},
	{
		"id": &"poke", "name": "Poke", "cost": 1, "rarity": SpellData.Rarity.COMMON,
		"desc": "Deal 1 magic damage.",
		"effects": [{"type": "dmg", "value": 1, "target": "enemy"}],
		"target": "enemy",
	},
	{
		"id": &"poultice", "name": "Poultice", "cost": 2, "rarity": SpellData.Rarity.COMMON,
		"desc": "Heal 2.",
		"effects": [{"type": "heal", "value": 2, "target": "self"}],
		"target": "self",
	},
	{
		"id": &"remedy", "name": "Remedy", "cost": 2, "rarity": SpellData.Rarity.COMMON,
		"desc": "Heal 2 (cleanse not yet modeled).",
		"effects": [{"type": "heal", "value": 2, "target": "self"}],
		"target": "self",
	},
	{
		"id": &"scald", "name": "Scald", "cost": 3, "rarity": SpellData.Rarity.UNCOMMON,
		"desc": "Deal 2 to all enemies.",
		"effects": [{"type": "dmg", "value": 2, "target": "all_enemies"}],
		"target": "none",
	},
	{
		"id": &"scorch", "name": "Scorch", "cost": 3, "rarity": SpellData.Rarity.COMMON,
		"desc": "Deal 1 to all enemies (fire).",
		"effects": [{"type": "dmg", "value": 1, "target": "all_enemies"}],
		"target": "none",
	},
	{
		"id": &"sprout", "name": "Sprout", "cost": 4, "rarity": SpellData.Rarity.COMMON,
		"desc": "Heal 3.",
		"effects": [{"type": "heal", "value": 3, "target": "self"}],
		"target": "self",
	},
	{
		"id": &"zap", "name": "Zap", "cost": 2, "rarity": SpellData.Rarity.UNCOMMON,
		"desc": "Deal 2 damage.",
		"effects": [{"type": "dmg", "value": 2, "target": "enemy"}],
		"target": "enemy",
	},
]

static func all() -> Array:
	var out: Array = []
	for d in _DEFS:
		out.append(_build(d))
	return out

static func by_id(id: StringName) -> SpellData:
	for d in _DEFS:
		if StringName(d["id"]) == id:
			return _build(d)
	return null

static func default_starter_ids() -> Array[StringName]:
	# Loadout used when a strategy run starts with no learned spells.
	# Mix of one self-heal, one single-target, and one AOE for the
	# tactical demo to feel meaningful immediately.
	return [&"poke", &"poultice", &"scorch"] as Array[StringName]

static func _build(def: Dictionary) -> SpellData:
	var s: SpellData = SpellDataScript.new()
	s.id = StringName(def["id"])
	s.display_name = def["name"]
	s.cost = int(def["cost"])
	s.rarity = int(def["rarity"])
	s.description = def["desc"]
	s.effects = def["effects"].duplicate(true)
	s.target_kind = def.get("target", "enemy")
	return s

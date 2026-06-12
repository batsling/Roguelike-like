class_name Spellbook
extends RefCounted

# Phase 6: the player's mana-driven spell list inside a tactical combat.
# Built from `GameState.learned_spells` (StringName ids resolved via
# `SpellsCatalog`). Unlike abilities, spells have no cooldown — only
# mana cost (`SpellData.cost`). Casting any number per turn is fine as
# long as mana lasts; turn-start regen is handled by BattleTurnManager.

const SpellsCatalogScript := preload("res://scripts/strategy/combat/SpellsCatalog.gd")

class Entry extends RefCounted:
	var data: SpellData
	var wants_target: bool

var spells: Array = []  # Array[Entry]

static func build_from_ids(ids: Array) -> Spellbook:
	var sb := Spellbook.new()
	for id in ids:
		var sd: SpellData = SpellsCatalogScript.by_id(StringName(id))
		if sd == null:
			continue
		var e := Entry.new()
		e.data = sd
		e.wants_target = sd.wants_target()
		sb.spells.append(e)
	return sb

func find(id: StringName) -> Entry:
	for e in spells:
		if e.data.id == id:
			return e
	return null

func can_cast(unit: BattleUnit, entry: Entry) -> bool:
	return entry != null and unit.mana >= entry.data.cost

func spend_mana(unit: BattleUnit, entry: Entry) -> void:
	unit.mana = maxi(0, unit.mana - entry.data.cost)

class_name Entity
extends RefCounted

var grid_pos: Vector2i = Vector2i.ZERO
var glyph: String = "?"
var color: Color = Color.WHITE
var name: String = "unknown"
var blocks_movement: bool = true

# Combat stats
var max_hp: int = 10
var hp: int = 10
var attack: int = 2
var defense: int = 0

# Inventory (player only)
var inventory: Array = []  # Array of Item
const MAX_INVENTORY = 26

# AI
var is_player: bool = false

func is_alive() -> bool:
	return hp > 0

func take_damage(amount: int) -> int:
	var dmg = max(0, amount - defense)
	hp -= dmg
	return dmg

func attack_entity(target: Entity) -> void:
	var dmg = take_hit(target)
	var attacker = name.capitalize()
	var defender = target.name.capitalize()
	if dmg > 0:
		MessageLog.add("%s hits %s for %d damage." % [attacker, defender, dmg], Color.WHITE)
	else:
		MessageLog.add("%s attacks %s but does no damage." % [attacker, defender], Color.GRAY)

	if not target.is_alive():
		MessageLog.add("%s is slain!" % defender, Color.RED)
		GameState.remove_entity(target)

func take_hit(target: Entity) -> int:
	var dmg = max(0, attack - target.defense)
	target.hp -= dmg
	return dmg

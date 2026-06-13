class_name StrategyRoomData
extends RefCounted

# Per-room metadata generated alongside StrategyMap.rooms.

var rect: Rect2i
var tag: String = "combat"  # start, combat, treasure, shop, stairs
var encounter: Array = []   # Array of enemy archetype name strings
var cleared: bool = true    # combat rooms start uncleared; non-combat rooms cleared

func contains(pos: Vector2i) -> bool:
	return rect.has_point(pos)

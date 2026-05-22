class_name StrategyItem
extends RefCounted

enum ItemType { HEALTH_POTION, STRENGTH_SCROLL, LIGHTNING_SCROLL }

var grid_pos: Vector2i = Vector2i.ZERO
var glyph: String = "?"
var color: Color = Color.YELLOW
var item_name: String = "item"
var item_type: ItemType = ItemType.HEALTH_POTION

static func make_health_potion(pos: Vector2i) -> StrategyItem:
	var it = StrategyItem.new()
	it.grid_pos = pos
	it.glyph = "!"
	it.color = Color(0.8, 0.2, 0.8)
	it.item_name = "health potion"
	it.item_type = ItemType.HEALTH_POTION
	return it

static func make_strength_scroll(pos: Vector2i) -> StrategyItem:
	var it = StrategyItem.new()
	it.grid_pos = pos
	it.glyph = "?"
	it.color = Color(0.9, 0.9, 0.2)
	it.item_name = "scroll of strength"
	it.item_type = ItemType.STRENGTH_SCROLL
	return it

static func make_lightning_scroll(pos: Vector2i) -> StrategyItem:
	var it = StrategyItem.new()
	it.grid_pos = pos
	it.glyph = "?"
	it.color = Color(0.3, 0.7, 1.0)
	it.item_name = "scroll of lightning"
	it.item_type = ItemType.LIGHTNING_SCROLL
	return it

func use(user: StrategyEntity) -> String:
	match item_type:
		ItemType.HEALTH_POTION:
			var healed = mini(user.max_hp - user.hp, 15)
			user.hp += healed
			return "You drink the %s and recover %d HP." % [item_name, healed]
		ItemType.STRENGTH_SCROLL:
			user.attack += 2
			return "You read the %s. Your arms feel stronger!" % item_name
		ItemType.LIGHTNING_SCROLL:
			# Hits nearest visible enemy
			return _cast_lightning(user)
	return ""

func _cast_lightning(user: StrategyEntity) -> String:
	var nearest: StrategyEntity = null
	var best_dist = INF
	for e in StrategyState.entities:
		if e == user:
			continue
		var d = user.grid_pos.distance_to(e.grid_pos)
		var map_idx = StrategyState.map.idx(e.grid_pos.x, e.grid_pos.y)
		if StrategyState.map.visible[map_idx] and d < best_dist:
			best_dist = d
			nearest = e
	if nearest == null:
		return "The scroll crackles and fizzles — no target in sight."
	var dmg = 20
	nearest.hp -= dmg
	var msg = "A bolt of lightning strikes the %s for %d damage!" % [nearest.name, dmg]
	if not nearest.is_alive():
		msg += " It is slain!"
		StrategyState.remove_entity(nearest)
	return msg

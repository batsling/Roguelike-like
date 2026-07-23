class_name StrategyItem
extends RefCounted

enum ItemType {
	HEALTH_POTION,
	STRENGTH_SCROLL,
	LIGHTNING_SCROLL,
	KEY,
	GOLD,
	POTION_LOOT,   # a real PotionData loot drop (carries `potion_id`)
	SCROLL_LOOT,   # a real ScrollData loot drop (carries `scroll_id`)
}

var grid_pos: Vector2i = Vector2i.ZERO
var glyph: String = "?"
var color: Color = Color.YELLOW
var item_name: String = "item"
var item_type: ItemType = ItemType.HEALTH_POTION
var amount: int = 1  # for GOLD piles
# For POTION_LOOT: the PotionData id this floor drop grants when collected.
var potion_id: StringName = &""
# For SCROLL_LOOT: the ScrollData id this floor drop grants when collected.
var scroll_id: StringName = &""

# Walking onto an auto-pickup item collects it without needing an inventory slot.
var auto_pickup: bool = false

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

static func make_key(pos: Vector2i) -> StrategyItem:
	var it = StrategyItem.new()
	it.grid_pos = pos
	it.glyph = "k"
	it.color = Color(1.0, 0.85, 0.2)
	it.item_name = "key"
	it.item_type = ItemType.KEY
	it.auto_pickup = true
	return it

static func make_gold(pos: Vector2i, amt: int) -> StrategyItem:
	var it = StrategyItem.new()
	it.grid_pos = pos
	it.glyph = "$"
	it.color = Color(1.0, 0.9, 0.3)
	it.item_name = "%d gold" % amt
	it.item_type = ItemType.GOLD
	it.amount = amt
	it.auto_pickup = true
	return it

static func make_potion_loot(pos: Vector2i, potion: PotionData) -> StrategyItem:
	var it = StrategyItem.new()
	it.grid_pos = pos
	it.glyph = "!"
	it.color = Color(0.7, 0.5, 0.95)
	it.item_name = "potion"
	it.item_type = ItemType.POTION_LOOT
	it.potion_id = potion.id
	it.auto_pickup = true   # walked-over potions go straight into the loot belt
	return it

static func make_scroll_loot(pos: Vector2i, scroll: ScrollData) -> StrategyItem:
	var it = StrategyItem.new()
	it.grid_pos = pos
	it.glyph = "?"
	it.color = Color(0.6, 0.5, 0.85)
	it.item_name = "scroll"
	it.item_type = ItemType.SCROLL_LOOT
	it.scroll_id = scroll.id
	it.auto_pickup = true   # walked-over scrolls go straight into the loot belt
	return it

# A random real consumable ground drop — 50/50 a potion or a scroll from the
# ported loot tables, mirroring GameState.grant_random_consumable_loot. Falls
# back to the other type (or a prototype health potion) if a roll comes up empty,
# so this never returns null. Shared by the dungeon floor spawner and the
# tactical-combat enemy-loot drop so both drop the same real consumables.
static func make_random_consumable_loot(pos: Vector2i, rng: RandomNumberGenerator) -> StrategyItem:
	if rng.randf() < 0.5:
		var p: PotionData = Data.roll_potion(rng)
		if p != null:
			return make_potion_loot(pos, p)
		var s2: ScrollData = Data.roll_scroll(rng)
		if s2 != null:
			return make_scroll_loot(pos, s2)
		return make_health_potion(pos)
	var s: ScrollData = Data.roll_scroll(rng)
	if s != null:
		return make_scroll_loot(pos, s)
	var p2: PotionData = Data.roll_potion(rng)
	if p2 != null:
		return make_potion_loot(pos, p2)
	return make_health_potion(pos)

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
			return _cast_lightning(user)
		ItemType.KEY:
			return "You can't use a key directly. Walk into a locked door."
		ItemType.GOLD:
			return ""
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

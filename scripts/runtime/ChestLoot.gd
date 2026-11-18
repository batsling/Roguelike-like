class_name ChestLoot
extends RefCounted

# A CHEST IS A PIECE OF LOOT (the owner, 18 Nov 2026: "Chests will now be treated
# as loot in the sense that you can move it around in your inventory", and, asked,
# "pack item, open any time"). It lies on the reward screen's table beside the
# loot a game paid, can be dragged into the pack and carried for as long as you
# like, and its Open button opens it wherever it is.
#
# The entry, JSON-safe like every pack entry so a save keeps it:
#   {"type": "chest", "id": "chest", "choices": int, "boss": bool, "pool": String,
#    "offer": [item ids]}
# Its relics are ROLLED WHEN IT IS EARNED, as they always were, and kept on the
# entry as ids: the seeded run's stream is drawn in the same order it was, and a
# Reroll asks the same roll again. They are not shown until it is opened.
#
# Its GOLD (Data.chest_gold) is paid as it OPENS, whatever is taken out of it.

const TYPE := "chest"
const ART := {
	0: "res://images2.0/general/ChestSmall.png",
	1: "res://images2.0/general/ChestMedium.png",
	2: "res://images2.0/general/ChestLarge.png",
	3: "res://images2.0/general/ChestHuge.png",
}
const BOSS_ART := "res://images2.0/general/ChestBoss.png"

static func make(items: Array, boss: bool = false, pool: String = "") -> Dictionary:
	var ids: Array = []
	for it in items:
		if it is ItemData:
			ids.append(String((it as ItemData).id))
	return {"type": TYPE, "id": TYPE, "choices": ids.size(), "boss": boss,
		"pool": pool, "offer": ids}

static func is_chest(entry) -> bool:
	return entry is Dictionary and String((entry as Dictionary).get("type", "")) == TYPE

# 0 Small … 3 Huge, off how many relics it offers.
static func rank(entry: Dictionary) -> int:
	return ItemDropModal.chest_rank(int(entry.get("choices", 1)))

static func is_boss(entry: Dictionary) -> bool:
	return bool(entry.get("boss", false))

static func display_name(entry: Dictionary) -> String:
	if is_boss(entry):
		return "Boss Chest"
	return "%s Chest" % String(Data.CHEST_SIZE_NAMES.get(rank(entry), "Small"))

static func gold(entry: Dictionary) -> int:
	return Data.chest_gold(int(entry.get("choices", 0)))

static func description(entry: Dictionary) -> String:
	var n: int = int(entry.get("choices", 1))
	return "Open it to take 1 of %d %s. +%d gold when it opens." % [n,
		"boss relics" if is_boss(entry) else ("relic" if n == 1 else "relics"), gold(entry)]

# The picture: the chest icon the player wears (Customization), picked by size,
# or the game's own pixel chest in the size's colour.
static func art_texture(entry: Dictionary) -> Texture2D:
	var level: int = CosmeticCatalog.BOSS_CHEST if is_boss(entry) else rank(entry)
	var worn: Texture2D = Cosmetics.glyph_texture("🎁", level)
	if worn != null:
		return worn
	var path: String = BOSS_ART if is_boss(entry) else String(ART.get(rank(entry), ART[0]))
	return load(path) as Texture2D

# The size's colour, for its stars.
static func tint(entry: Dictionary) -> Color:
	return UITheme.ITEM_CLASS_COLORS[5] if is_boss(entry) else RarityStyle.color(rank(entry))

static func stars(entry: Dictionary) -> String:
	return ItemDropModal.STAR_GLYPH.repeat(rank(entry) + 1)

# The relics it holds.
static func items(entry: Dictionary) -> Array:
	var out: Array = []
	for id in entry.get("offer", []):
		var it: ItemData = Data.get_item2(StringName(String(id)))
		if it != null:
			out.append(it)
	return out

# OPEN IT: pay its gold and ask which relic to take, on `layer` (above whatever
# screen it was opened from). `page` is the run page, which grants the relic.
# `on_done` is called once it has been answered, taken or not. Returns the chest's
# modal, or null when it held nothing (it is still spent, and pays its gold).
static func open(page: Node, entry: Dictionary, layer: int, on_done: Callable = Callable()) -> ItemDropModal:
	var paid: int = gold(entry)
	if paid > 0:
		GameState.change_gold(paid)
		GameLog.add("%s: +%d gold." % [display_name(entry), paid], Color(1.0, 0.9, 0.3))
	var offer: Array = items(entry)
	if offer.is_empty():
		if on_done.is_valid():
			on_done.call()
		return null
	var held := {"offer": offer}
	# The modal spends the Reroll charge itself before it calls this.
	var again := func() -> Array:
		var fresh: Array = Data.roll_chest(page.drop_rng(), offer.size(),
			String(entry.get("pool", "")), is_boss(entry))
		held["offer"] = fresh
		return fresh
	var modal := ItemDropModal.open(page, offer, again, layer)
	modal.answered.connect(func(taken: bool, chosen: ItemData):
		if taken and chosen != null:
			page.collect_drop_item(chosen)
		else:
			page.skip_drop_items(held["offer"])
		if on_done.is_valid():
			on_done.call())
	return modal

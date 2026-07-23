extends GutTest

# Consumables (potions / scrolls) now drop on the ground in strategy combat (the
# mewgenics-like tactical grid) and are collected into the shared loot belt —
# these tests cover the StrategyItem loot helpers and the BattleView drop +
# pickup path.

const BattleViewScript = preload("res://scripts/strategy/combat/BattleView.gd")
const BattleMapScript = preload("res://scripts/strategy/combat/BattleMap.gd")

var bv

func before_each() -> void:
	GameState.reset_run()
	GameState.loot_items = []
	bv = BattleViewScript.new()
	add_child_autofree(bv)   # runs _ready -> builds _grid_view

func _enemy() -> BattleUnit:
	var u := BattleUnit.new()
	u.is_player = false
	u.max_hp = 30
	u.hp = 30
	u.position = Vector2i(2, 1)
	return u

# --- StrategyItem loot helpers --------------------------------------------

func test_make_scroll_loot_carries_id_and_auto_pickup() -> void:
	var scrolls: Array = Data.all_scrolls()
	if scrolls.is_empty():
		pass_test("no scrolls loaded; skipping")
		return
	var s: ScrollData = scrolls[0]
	var it = StrategyItem.make_scroll_loot(Vector2i(3, 4), s)
	assert_eq(it.item_type, StrategyItem.ItemType.SCROLL_LOOT)
	assert_eq(it.scroll_id, s.id, "carries the scroll id for pickup")
	assert_true(it.auto_pickup, "scroll loot is walked-over auto-pickup")
	assert_eq(it.grid_pos, Vector2i(3, 4))

func test_random_consumable_loot_is_a_real_consumable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var saw_potion := false
	var saw_scroll := false
	for _i in range(40):
		var it = StrategyItem.make_random_consumable_loot(Vector2i(0, 0), rng)
		assert_true(it != null, "never returns null")
		var t: int = it.item_type
		assert_true(
			t == StrategyItem.ItemType.POTION_LOOT
			or t == StrategyItem.ItemType.SCROLL_LOOT
			or t == StrategyItem.ItemType.HEALTH_POTION,
			"drop is a consumable type")
		if t == StrategyItem.ItemType.POTION_LOOT:
			saw_potion = true
		elif t == StrategyItem.ItemType.SCROLL_LOOT:
			saw_scroll = true
	# With both tables loaded, the 50/50 split should surface both kinds.
	assert_true(saw_potion, "some rolls drop a potion")
	assert_true(saw_scroll, "some rolls drop a scroll")

# --- Combat drop + pickup --------------------------------------------------

func _consumable_entries(bm) -> Array:
	return bm.items.filter(func(e):
		var t: int = e.item.item_type
		return t == StrategyItem.ItemType.POTION_LOOT or t == StrategyItem.ItemType.SCROLL_LOOT)

func test_enemy_death_can_drop_a_consumable_capped_at_one() -> void:
	bv._battle_map = BattleMapScript.new()
	bv._loot_rng.seed = 99
	# The 40% drop is capped at one per combat; roll several deaths and confirm a
	# consumable lands and the cap holds.
	var got_one := false
	for _i in range(30):
		bv._dropped_consumable = false
		bv._battle_map.items.clear()
		bv._drop_enemy_loot(_enemy())
		if _consumable_entries(bv._battle_map).size() > 0:
			got_one = true
			# The cap flag is now set; a further death drops no second consumable.
			bv._drop_enemy_loot(_enemy())
			assert_eq(_consumable_entries(bv._battle_map).size(), 1,
				"only one consumable drops per combat")
			break
	assert_true(got_one, "an enemy death drops a consumable within many rolls")

func test_picking_up_a_dropped_potion_enters_the_loot_belt() -> void:
	bv._battle_map = BattleMapScript.new()
	var potions: Array = Data.all_potions()
	if potions.is_empty():
		pass_test("no potions loaded; skipping")
		return
	var pos := Vector2i(5, 5)
	bv._battle_map.add_dropped_item(StrategyItem.make_potion_loot(pos, potions[0]), pos)
	var before: int = GameState.loot_potions().size()
	var msgs: Array = []
	bv._try_pickup_at(pos, msgs)
	assert_eq(GameState.loot_potions().size(), before + 1,
		"the collected potion enters the loot belt")
	assert_eq(_consumable_entries(bv._battle_map).size(), 0,
		"the drop is removed from the battlefield after pickup")

func test_picking_up_a_dropped_scroll_enters_the_loot_belt() -> void:
	bv._battle_map = BattleMapScript.new()
	var scrolls: Array = Data.all_scrolls()
	if scrolls.is_empty():
		pass_test("no scrolls loaded; skipping")
		return
	var pos := Vector2i(6, 6)
	bv._battle_map.add_dropped_item(StrategyItem.make_scroll_loot(pos, scrolls[0]), pos)
	var before: int = GameState.loot_scrolls().size()
	var msgs: Array = []
	bv._try_pickup_at(pos, msgs)
	assert_eq(GameState.loot_scrolls().size(), before + 1,
		"the collected scroll enters the loot belt")

extends GutTest

# THE SHOP BAR (docs/games-first-redesign.md §19.10): every enemy defeated fills
# it by one; full, it opens a shop at any game without one, and that shop stays
# there for the rest of the run. The first shop costs ShopSystem.BAR_BASE kills
# and every shop after it one kill more. It replaced the node kinds, whose Shop
# nodes were dealt across the map at run start.

const Fixtures := preload("res://test/helpers/fixtures.gd")
const Page := preload("res://test/helpers/run_page.gd")

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()
	GameState.max_hp = 10
	GameState.hp = 10
	GameState.run_seed = 20261024

func _enemy(boss := false) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = 1
	e.health = 1
	e.difficulty = GoalEnemyData.Difficulty.LOW
	e.boss = boss
	return e

# Two on-map games to open shops at; which they are matters to no test here.
func _games(n: int) -> Array:
	var out: Array = []
	for g in Data.all_games():
		if g is GameData and not RunGraph.is_off_map(g.id):
			out.append(g.id)
			if out.size() == n:
				break
	return out


func test_the_first_shop_costs_four_kills() -> void:
	assert_eq(ShopSystem.BAR_BASE, 4, "the owner's number (24 Oct 2026)")
	assert_eq(ShopSystem.bar_target(), 4)
	assert_eq(GameState.shop_bar, 0, "a run opens on an empty bar")

func test_each_kill_fills_it_and_a_full_bar_stays_full() -> void:
	for i in range(3):
		ShopSystem.add_kill()
	assert_eq(GameState.shop_bar, 3)
	assert_false(ShopSystem.bar_full())
	ShopSystem.add_kill()
	assert_true(ShopSystem.bar_full(), "the fourth kill fills it")
	ShopSystem.add_kill()
	assert_eq(GameState.shop_bar, 4, "kills past a full bar are lost")

func test_defeating_a_body_fills_it_boss_or_not() -> void:
	GameLoop2.choose_game(_enemy())
	GameLoop2.beat_game(true)
	assert_eq(GameState.shop_bar, 1, "an enemy is one kill")
	GameLoop2.choose_game(_enemy(true))
	GameLoop2.beat_game(true)
	assert_eq(GameState.shop_bar, 2, "and so is a boss")

func test_a_missed_goal_or_a_bomb_does_not_fill_it() -> void:
	GameLoop2.choose_game(_enemy())
	GameLoop2.beat_game(false)
	assert_eq(GameState.shop_bar, 0, "the enemy is still standing")
	GameLoop2.reset()
	GameState.bombs = 1
	var inst: int = GameLoop2.spawn_to_stack(_enemy())
	GameLoop2.bomb(inst)
	assert_eq(GameState.shop_bar, 0, "a bomb is no kill, as it pays no gold")

func test_a_shop_opens_only_off_a_full_bar() -> void:
	var here: StringName = _games(1)[0]
	assert_false(ShopSystem.can_open_at(here))
	assert_false(ShopSystem.open_at(here), "an empty bar opens nothing")
	assert_false(ShopSystem.is_shop(here))
	GameState.shop_bar = ShopSystem.bar_target()
	assert_true(ShopSystem.can_open_at(here))
	assert_true(ShopSystem.open_at(here))
	assert_true(ShopSystem.is_shop(here), "the shop stands there now")
	assert_eq(GameState.shop_bar, 0, "and opening it emptied the bar")
	assert_false(ShopSystem.stock(here).is_empty(), "its shelf is rolled at once")

func test_one_shop_a_game() -> void:
	var here: StringName = _games(1)[0]
	Fixtures.open_shop(here)
	GameState.shop_bar = ShopSystem.bar_target()
	assert_false(ShopSystem.can_open_at(here), "a game holds one shop")
	assert_false(ShopSystem.open_at(here))
	assert_true(ShopSystem.bar_full(), "and the full bar is kept for another game")
	assert_false(ShopSystem.can_open_at(&""), "nor can one open nowhere")

func test_each_shop_puts_the_next_a_kill_further_off() -> void:
	var games: Array = _games(2)
	Fixtures.open_shop(games[0])
	assert_eq(ShopSystem.bar_target(), 5, "the second shop costs five")
	Fixtures.open_shop(games[1])
	assert_eq(ShopSystem.bar_target(), 6, "the third six")
	assert_eq(ShopSystem.shop_nodes(), [StringName(games[0]), StringName(games[1])] as Array[StringName],
		"the shops, in the order they were opened")

func test_the_bar_and_the_shops_survive_a_save() -> void:
	var here: StringName = _games(1)[0]
	Fixtures.open_shop(here)
	GameState.shop_bar = 3
	var blob: Dictionary = JSON.parse_string(JSON.stringify(GameState.serialize_shops()))
	GameState.reset_run()
	assert_eq(GameState.shop_bar, 0, "a new run empties the bar")
	assert_false(ShopSystem.is_shop(here), "and takes the shops")
	GameState.restore_shops(blob)
	assert_eq(GameState.shop_bar, 3)
	assert_true(ShopSystem.is_shop(here))

func test_no_shop_stands_anywhere_at_the_start_of_a_run() -> void:
	var ui = Page.build(self)
	ui.choose_start(0)
	assert_true(ShopSystem.shop_nodes().is_empty(), "every shop is the player's to open")

# The map marks a shop the player opened, and only that (§19.10).
func test_the_map_marks_a_shop_and_nothing_else() -> void:
	var games: Array = _games(2)
	var rect := Rect2(0, 0, 150, 48)
	assert_null(RouteLadder.shop_marker(games[0], rect), "no shop, no marker")
	Fixtures.open_shop(games[0])
	var marker: Control = RouteLadder.shop_marker(games[0], rect)
	assert_not_null(marker, "a shop's box wears the cart")
	if marker != null:
		assert_eq((marker.get_node("ShopMark") as Label).text, RouteLadder.SHOP_MARK)
		marker.free()
	var card: VBoxContainer = RouteLadder.node_card_body({"id": games[0]})
	assert_not_null(card.find_child("ShopMarker", true, false), "and so does its card")
	card.free()
	var plain: VBoxContainer = RouteLadder.node_card_body({"id": games[1]})
	assert_null(plain.find_child("ShopMarker", true, false))
	plain.free()

# THE BAR, PRESSED, on the page: full, it opens a shop where the run stands and
# walks in; standing in one, it walks back in.
func test_pressing_a_full_bar_opens_a_shop_where_the_run_stands() -> void:
	var ui = Page.build(self)
	Page.open_at_first_offering(ui)
	var here: StringName = GameState.current_game_id
	assert_null(ui.press_shop_bar(), "an empty bar opens nothing")
	assert_false(ShopSystem.is_shop(here))
	GameState.shop_bar = ShopSystem.bar_target()
	ui._paint_shop_bar()
	assert_false(ui._shop_bar_chip.disabled, "a full bar is a live button")
	var modal = ui.press_shop_bar()
	assert_not_null(modal, "the shop opens")
	assert_true(ShopSystem.is_shop(here), "at the game the run stands at")
	assert_eq(ui._shop_here, here, "with its button up by the offering")
	modal.queue_free()
	ui._shop_modal = null
	assert_not_null(ui.press_shop_bar(), "and pressing again walks back in")

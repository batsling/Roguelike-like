extends GutTest

const Fixtures := preload("res://test/helpers/fixtures.gd")

# PADDING (Brotato; the owner, 20 Nov 2026): +1 Max Health, and +1 Max Health for
# every 10 Gold held — live, as in Brotato. More Gold adds EMPTY Max Health;
# spending below a step takes it back, Health above the new max with it.

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _start(gold: int, hp: int, max_hp: int) -> void:
	GameState.set_gold(gold)
	GameState.max_hp = max_hp
	GameState.hp = hp

func test_padding_is_brotatos() -> void:
	var it: ItemData = Data.get_item2(&"padding")
	assert_not_null(it, "regenerate with tools/generate_item2_tres.py")
	assert_eq(it.source_game, "Brotato")
	assert_eq(int(it.rarity), int(ItemData.Rarity.UNCOMMON))
	assert_eq(it.scaling, [{"stat": "max_hp", "value": 1, "per": 10, "of": "gold"}])

func test_it_gives_one_plus_one_per_ten_gold_held() -> void:
	_start(25, 7, 7)
	Fixtures.give(self, &"padding")
	assert_eq(GameState.max_hp, 10, "7, +1 flat, +2 for 25 Gold")
	assert_eq(GameState.hp, 7, "the new Max Health arrives empty")

func test_more_gold_adds_empty_max_health_as_it_comes() -> void:
	_start(9, 5, 7)
	Fixtures.give(self, &"padding")
	assert_eq(GameState.max_hp, 8, "9 Gold is not a step yet")
	GameState.change_gold(1)
	assert_eq(GameState.max_hp, 9, "10 Gold is")
	assert_eq(GameState.hp, 5, "and Health has room, not more")
	GameState.change_gold(20)
	assert_eq(GameState.max_hp, 11)

func test_spending_below_a_step_takes_it_back_and_health_with_it() -> void:
	_start(20, 7, 7)
	Fixtures.give(self, &"padding")
	GameState.hp = GameState.max_hp   # 10 of 10
	GameState.change_gold(-11)        # 9 Gold left
	assert_eq(GameState.max_hp, 8, "back to the flat +1")
	assert_eq(GameState.hp, 8, "Health above the new max is lost")
	GameState.change_gold(11)
	assert_eq(GameState.max_hp, 10, "earned back")
	assert_eq(GameState.hp, 8, "but not healed: no healing by spending and earning")

func test_a_purse_in_debt_counts_as_empty() -> void:
	_start(0, 7, 7)
	Fixtures.give(self, &"padding")
	GameState.set_gold(-15, true)
	assert_eq(GameState.max_hp, 8, "only the flat +1, never less")

func test_losing_padding_takes_its_max_health_away() -> void:
	_start(30, 7, 7)
	var pad: ItemData = Fixtures.give(self, &"padding")
	assert_eq(GameState.max_hp, 11)
	GameState.remove_item(pad)
	assert_eq(GameState.max_hp, 7)

func test_without_padding_gold_leaves_max_health_alone() -> void:
	_start(0, 7, 7)
	GameState.change_gold(50)
	assert_eq(GameState.max_hp, 7)

# --- what it shows ---------------------------------------------------------------

func test_its_pip_shows_the_max_health_it_gives_right_now() -> void:
	_start(25, 7, 7)
	var pad: ItemData = Fixtures.give(self, &"padding")
	assert_eq(GameState.scaling_now(pad), {"max_hp": 3})
	var pip: Control = PackStrip.scaling_badge(pad)
	assert_not_null(pip, "a pip on the relic")
	add_child_autofree(pip)
	assert_eq((pip.get_child(0) as Label).text, "+3")
	GameState.change_gold(-25)
	assert_eq(GameState.scaling_now(pad), {"max_hp": 1}, "follows the purse")

func test_its_hover_says_it_in_words_only_when_owned() -> void:
	_start(25, 7, 7)
	var template: ItemData = Data.get_item2(&"padding")
	assert_eq(PackStrip.scaling_line(template), "", "a shop's Padding gives nothing yet")
	var pad: ItemData = Fixtures.give(self, &"padding")
	assert_eq(PackStrip.scaling_line(pad), "Giving +3 Max Health right now.")
	var hover: Dictionary = PackStrip.item_hover(pad, false, false, false)
	assert_true((hover["lines"] as Array).has("Giving +3 Max Health right now."))

func test_a_relic_that_does_not_scale_has_no_pip() -> void:
	var cross: ItemData = Fixtures.give(self, &"pummarola")
	assert_null(PackStrip.scaling_badge(cross))

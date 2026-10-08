extends GutTest

# Plural: a count and its noun, agreeing. "1 drop(s)", "1 games" and "1 x 1 — 1
# cells of the board" all shipped before it existed.

func test_one_is_singular() -> void:
	assert_eq(Plural.count(1, "drop"), "1 drop")
	assert_eq(Plural.word(1, "game"), "game")

func test_everything_else_is_plural() -> void:
	assert_eq(Plural.count(0, "drop"), "0 drops")
	assert_eq(Plural.count(3, "drop"), "3 drops")
	assert_eq(Plural.word(2, "game"), "games")

func test_an_irregular_plural_is_given() -> void:
	assert_eq(Plural.count(1, "piece of loot", "pieces of loot"), "1 piece of loot")
	assert_eq(Plural.count(2, "piece of loot", "pieces of loot"), "2 pieces of loot")

# The in-run event button and the Collection both name a gated resource through
# EventSystem.gate_stat_name, so "Needs 1 Bomb" is said the same way in both.
func test_a_gate_on_one_of_something_says_one() -> void:
	assert_eq(EventSystem.gate_stat_name("bombs", 1), "Bomb")
	assert_eq(EventSystem.gate_stat_name("bombs", 2), "Bombs")
	assert_eq(EventSystem.gate_stat_name("gold", 1), "Gold")

func test_a_scroll_that_forgets_one_piece_says_one() -> void:
	var one: String = ScrollSystem.op_text({"op": "forget", "count": 1, "kind": "loot"})
	assert_eq(one, "Forget 1 random identified piece of loot.")
	var two: String = ScrollSystem.op_text({"op": "forget", "count": 2, "kind": "scroll"})
	assert_eq(two, "Forget 2 random identified scrolls.")
	var ident: String = ScrollSystem.op_text({"op": "identify_loot", "count": 1})
	assert_eq(ident, "Choose 1 carried piece of loot to identify.")

func test_an_evolution_that_needs_one_thing_reads_as_a_phrase() -> void:
	for evo in Data.all_evolutions():
		if evo is EvolutionData and evo.need_id == &"" and evo.need_count == 1:
			assert_true(WeaponSystem.need_words(evo).begins_with("an item or trinket"),
				WeaponSystem.need_words(evo))
			return
	pending("no one-thing tag evolution in the data")

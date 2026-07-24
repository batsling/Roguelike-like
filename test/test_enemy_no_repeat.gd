extends GutTest

# Enemy behavior modifier: EnemyData.no_repeat_limit caps how many turns in a
# row the same move may run. The Louses / larger Slimes can't repeat ANY move a
# third time; Snecko can't Bite three times running but is free to repeat other
# moves. These exercise the pure helpers on DeckbuilderCombat that enforce it.

const CombatScene := preload("res://scenes/deckbuilder/DeckbuilderCombat.tscn")

var _combat

func before_each() -> void:
	# .new() (not the scene) avoids the whole _ready wiring — the no-repeat
	# helpers only read the passed actor + its EnemyData.
	_combat = load("res://scripts/deckbuilder/DeckbuilderCombat.gd").new()

func after_each() -> void:
	if _combat != null:
		_combat.free()
		_combat = null

func _enemy(limit: int, scope: String) -> CombatActor:
	var d := EnemyData.new()
	d.no_repeat_limit = limit
	d.no_repeat_move = scope
	var a := CombatActor.new()
	a.data = d
	return a

func _move(display: String) -> Dictionary:
	return {"display": display, "weight": 10, "effects": []}

# --- Global cap (Louse / big Slime) ----------------------------------------

func test_global_cap_locks_out_a_move_after_two_in_a_row() -> void:
	var e := _enemy(2, "")
	var bite := _move("Bite (5-7)")
	assert_false(_combat._violates_no_repeat(e, bite), "fresh move is fine")
	_combat._record_move(e, bite)
	assert_false(_combat._violates_no_repeat(e, bite), "second in a row still allowed")
	_combat._record_move(e, bite)
	assert_true(_combat._violates_no_repeat(e, bite), "third in a row is blocked")

func test_a_different_move_resets_the_streak() -> void:
	var e := _enemy(2, "")
	var bite := _move("Bite (5-7)")
	var web := _move("Spit Web (2 Weak)")
	_combat._record_move(e, bite)
	_combat._record_move(e, bite)
	assert_true(_combat._violates_no_repeat(e, bite), "two bites lock the third")
	_combat._record_move(e, web)   # streak breaks
	assert_false(_combat._violates_no_repeat(e, bite), "bite is free again after a web")

func test_weighted_pool_drops_the_blocked_move_but_not_others() -> void:
	var e := _enemy(2, "")
	var bite := _move("Bite (5-7)")
	var web := _move("Spit Web (2 Weak)")
	_combat._record_move(e, bite)
	_combat._record_move(e, bite)
	var pool: Array = _combat._weighted_pool(e, [bite, web], true)
	var displays: Array = []
	for entry in pool:
		displays.append(String(entry.move.get("display", "")))
	assert_does_not_have(displays, "Bite (5-7)", "blocked move excluded")
	assert_has(displays, "Spit Web (2 Weak)", "other move still available")

# --- Scoped cap (Snecko: Bite only) ----------------------------------------

func test_scoped_cap_only_restricts_the_named_move() -> void:
	var e := _enemy(2, "Bite")
	var bite := _move("Bite (15)")            # scope matches by prefix
	var tail := _move("Tail Whip (8 dmg, 2 Vulnerable)")
	_combat._record_move(e, bite)
	_combat._record_move(e, bite)
	assert_true(_combat._violates_no_repeat(e, bite), "three Bites blocked")
	# Tail Whip is unrestricted no matter how often it repeats.
	_combat._record_move(e, tail)
	_combat._record_move(e, tail)
	_combat._record_move(e, tail)
	assert_false(_combat._violates_no_repeat(e, tail), "scoped cap ignores other moves")

func test_no_cap_never_restricts() -> void:
	var e := _enemy(0, "")
	var bite := _move("Bite (5-7)")
	_combat._record_move(e, bite)
	_combat._record_move(e, bite)
	_combat._record_move(e, bite)
	assert_false(_combat._violates_no_repeat(e, bite), "limit 0 = unlimited")
	assert_eq(e.move_history.size(), 0, "uncapped enemies don't accumulate history")

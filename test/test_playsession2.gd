extends GutTest

# Smoke + drive tests for the PlaySession2 harness — it must build its UI headless
# and drive a full games-first run through the same public methods its buttons
# call (pick -> beat -> verbs), staying in sync with GameLoop2 / GameState.

const SCENE := preload("res://scenes/redesign2/PlaySession2.tscn")

var _ui

func before_each() -> void:
	_ui = SCENE.instantiate()
	add_child_autofree(_ui)   # runs _ready -> builds UI + starts an isaac run

func after_each() -> void:
	# The harness shrinks GameState.hp/max_hp to a character's tiny 2.0 pool;
	# restore run defaults so later suites that assume the big combat pool (e.g.
	# test_potions' set_hp(50)) aren't polluted by our leftover state.
	GameState.reset_run()
	GameLoop2.reset()

# Pick a game and take the ESCORT (§7.5) straight back off the board. Picking
# spawns two bodies now; the escort's own rules are tested in test_gameloop2.gd,
# and the tests below are about what the HARNESS does with the one you picked, so
# they clear the board down to it rather than carrying a random second enemy
# through their damage arithmetic.
func _pick_solo(game_type: StringName) -> void:
	_ui.pick(game_type)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())

func test_harness_builds_and_opens_a_run() -> void:
	assert_false(GameLoop2.run_over, "a fresh run is live")
	assert_eq(GameState.max_hp, 6, "default harness run is Isaac (Health 6)")
	assert_false(GameLoop2.has_arrivals(), "no game chosen yet")

func test_pick_spawns_enemy_and_beat_resolves() -> void:
	_ui.restart(&"ironclad")           # Health 10, no bombs
	assert_eq(GameState.max_hp, 10)
	_ui.pick(&"action")                # rolls an action / low enemy
	assert_true(GameLoop2.has_arrivals())
	var enemy: GoalEnemyData = GameLoop2.arrival()["enemy"]
	assert_eq(String(enemy.game_type), "action", "picked an action enemy")
	assert_false(enemy.is_boss(), "a normal pick is not a boss")
	# Picking spawns an escort alongside it (§7.5). Taken off here so the damage
	# arithmetic below is ONE enemy's — see _pick_solo.
	assert_eq(GameLoop2.stack_size(), 2, "the picked enemy, and the escort with it")
	GameLoop2.despawn(GameLoop2.escort_instance())
	var dmg: int = enemy.damage
	_ui.beat(false)                    # fails goal -> spawn column, one-game grace
	assert_eq(GameLoop2.stack_size(), 1)
	assert_eq(GameState.hp, 10, "grace: no hit the game it stacked")
	# It closes one column per game and only strikes once it reaches the front
	# (§grid). Marched directly here so no extra picked enemies muddy the hp math.
	while int(GameLoop2.stack[0].get("col", 1)) > 1:
		GameLoop2.beat_game(false)     # closes one column per game
	assert_eq(GameState.hp, 10, "no hit while closing in")
	GameLoop2.beat_game(false)         # the front-line enemy now hits for dmg
	assert_eq(GameState.hp, 10 - dmg, "the front-line enemy hits for its damage")
	assert_eq(GameLoop2.stack_size(), 1)

func test_pick_gated_until_current_resolved() -> void:
	_ui.pick(&"action")
	var first_instance: int = int(GameLoop2.arrival()["instance"])
	_ui.pick(&"deckbuilder")           # ignored: a game is already chosen
	assert_eq(int(GameLoop2.arrival()["instance"]), first_instance)

func test_bomb_button_removes_first_follower() -> void:
	_ui.restart(&"ironclad")
	GameState.bombs = 1
	_pick_solo(&"action") ; _ui.beat(false)
	assert_eq(GameLoop2.stack_size(), 1)
	_ui.bomb_first()
	assert_eq(GameLoop2.stack_size(), 0)
	assert_eq(GameState.bombs, 0)

func test_boss_button_spawns_a_boss() -> void:
	_ui.pick_boss()
	assert_true(GameLoop2.has_arrivals())
	assert_true(GameLoop2.arrival()["enemy"].is_boss(), "the boss button spawns a boss")
	_ui._refresh()
	assert_string_contains(_ui._enemy.text, "BOSS")

func test_hud_label_renders_current_state() -> void:
	_ui.pick(&"deckbuilder")
	_ui._refresh()
	assert_string_contains(_ui._hud.text, "Health")
	assert_string_contains(_ui._enemy.text, "GOAL")

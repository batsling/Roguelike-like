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

func test_harness_builds_and_opens_a_run() -> void:
	assert_false(GameLoop2.run_over, "a fresh run is live")
	assert_eq(GameState.max_hp, 6, "default harness run is Isaac (Health 6)")
	assert_false(GameLoop2.has_current(), "no game chosen yet")

func test_pick_spawns_enemy_and_beat_resolves() -> void:
	_ui.restart(&"ironclad")           # Health 10, no bombs
	assert_eq(GameState.max_hp, 10)
	_ui.pick(&"action")                # rolls Baby Alien (action / low)
	assert_true(GameLoop2.has_current())
	assert_eq(String(GameLoop2.current["enemy"].id), "baby_alien")
	_ui.beat(false)                    # fails goal -> stacks, one-game grace
	assert_eq(GameLoop2.stack_size(), 1)
	assert_eq(GameState.hp, 10, "grace: no hit the game it stacked")
	_ui.pick(&"deckbuilder")           # Spike Slime
	_ui.beat(false)                    # Baby Alien (dmg 1) now hits
	assert_eq(GameState.hp, 9)
	assert_eq(GameLoop2.stack_size(), 2)

func test_pick_gated_until_current_resolved() -> void:
	_ui.pick(&"action")
	var first_instance: int = int(GameLoop2.current["instance"])
	_ui.pick(&"deckbuilder")           # ignored: a game is already chosen
	assert_eq(int(GameLoop2.current["instance"]), first_instance)

func test_bomb_button_removes_first_follower() -> void:
	_ui.restart(&"ironclad")
	GameState.bombs = 1
	_ui.pick(&"action") ; _ui.beat(false)
	assert_eq(GameLoop2.stack_size(), 1)
	_ui.bomb_first()
	assert_eq(GameLoop2.stack_size(), 0)
	assert_eq(GameState.bombs, 0)

func test_hud_label_renders_current_state() -> void:
	_ui.pick(&"deckbuilder")
	_ui._refresh()
	assert_string_contains(_ui._hud.text, "Health")
	assert_string_contains(_ui._enemy.text, "GOAL")

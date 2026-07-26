extends GutTest

# Drive tests for the Overworld2 panel — the click-to-choose games-first
# overworld. It must build headless, boot a real start/amulet graph, and drive a
# run through the same public methods its cards call (pick -> report), plus the
# board verbs (bash/transmute) and the difficulty-gate boss round.

const SCENE := preload("res://scenes/redesign2/Overworld2.tscn")

var _ui

func before_each() -> void:
	_ui = SCENE.instantiate()
	add_child_autofree(_ui)   # _ready -> builds UI + boots a run

func after_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func test_boots_a_run_with_a_graph_and_choices() -> void:
	assert_false(GameLoop2.run_over, "a fresh run is live")
	assert_ne(String(GameState.current_game_id), "", "player placed on a start game")
	assert_ne(String(GameState.amulet_game_id), "", "an amulet was picked")
	assert_gt(_ui._choices.size(), 0, "the start's neighbours are offered as choices")

func test_each_choice_has_a_game_and_a_previewable_enemy() -> void:
	for c in _ui._choices:
		assert_true(c["game"] is GameData, "choice carries a real game")
		assert_true(c["enemy"] is GoalEnemyData, "choice pre-rolled an enemy for hover")

func test_pick_then_report_advances_the_loop() -> void:
	var target: StringName = _ui._choices[0]["game"].id
	_ui.pick(0)
	assert_true(GameLoop2.has_current(), "picking spawns the enemy")
	assert_eq(GameState.current_game_id, target, "player travelled to the picked game")
	var gp_before: int = GameState.games_played
	_ui.report(false)             # miss -> the enemy stacks and follows
	assert_eq(GameState.games_played, gp_before + 1, "the game counts as played")
	assert_eq(GameLoop2.stack_size(), 1, "a missed goal leaves a following enemy")
	assert_gt(_ui._choices.size(), 0, "a fresh offering is drawn from the new position")

func test_report_goal_met_defeats_and_drops() -> void:
	var chests_before: int = GameState.pending_chests
	_ui.pick(0)
	_ui.report(true)              # met -> defeat + chest drop, nothing stacks
	assert_eq(GameLoop2.stack_size(), 0, "a met goal leaves nothing following")
	assert_eq(GameState.pending_chests, chests_before + 1, "the drop banked a chest")

func test_boss_round_on_difficulty_gate() -> void:
	# The tier steps every GAMES_PER_TIER games; that crossing is a boss round.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	_ui._build_choices()
	assert_true(_ui._boss_round, "a games-played multiple of the tier step is a boss round")
	for c in _ui._choices:
		assert_true(bool(c["boss"]), "every boss-round choice spawns a boss")

func test_bash_removes_a_choice_from_the_pool() -> void:
	GameState.bash = 1
	_ui._build_choices()
	var bashed_id: StringName = _ui._choices[0]["slot"]
	_ui.bash_choice(0)
	assert_true(GameLoop2.is_bashed(bashed_id), "the game is destroyed out of the pool")
	assert_eq(GameState.bash, 0, "bash spent a charge")
	# The bashed game no longer appears in the offering (a limited offering may
	# backfill the freed slot from the reachable pool).
	for c in _ui._choices:
		assert_ne(c["slot"], bashed_id, "bashed game not re-offered")

func test_bash_disabled_on_boss_round() -> void:
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	GameState.bash = 1
	_ui._build_choices()
	_ui.bash_choice(0)
	assert_eq(GameState.bash, 1, "bosses are unskippable — bash does nothing")

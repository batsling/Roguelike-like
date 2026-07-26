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

func test_fulfilling_a_follower_goal_defeats_and_drops_it() -> void:
	# Miss a goal so an enemy follows, then on the next game tick its fulfilment
	# checkbox: it should be defeated (and drop) before it can hit (§2).
	_ui.pick(0)
	_ui.report(false)
	assert_eq(GameLoop2.stack_size(), 1, "a missed goal leaves a follower")
	var hp_before: int = GameState.hp
	var chests_before: int = GameState.pending_chests
	_ui.pick(0)                                  # play another game
	assert_eq(_ui._fulfil_checks.size(), 1, "the follower is offered for fulfilment")
	_ui._fulfil_checks[0]["check"].button_pressed = true
	_ui.report(false)                            # miss current, but fulfil the follower
	assert_eq(GameState.pending_chests, chests_before + 1, "the fulfilled follower dropped")
	assert_eq(GameState.hp, hp_before, "fulfilling it before it hit means no damage")
	# The only follower now is this game's freshly-stacked enemy, not the old one.
	assert_eq(GameLoop2.stack_size(), 1, "old follower gone; current game's enemy stacked")

func test_report_accepts_an_explicit_fulfilment_list() -> void:
	_ui.pick(0)
	_ui.report(false)
	var inst: int = int(GameLoop2.stack[0]["instance"])
	_ui.pick(0)
	_ui.report(false, [inst])                    # explicit list bypasses the checkboxes
	for entry in GameLoop2.stack:
		assert_ne(int(entry["instance"]), inst, "the explicitly-fulfilled follower is gone")

func test_boss_round_on_difficulty_gate() -> void:
	# The tier steps every GAMES_PER_TIER games; that crossing is a boss round.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	_ui._build_choices()
	assert_true(_ui._boss_round, "a games-played multiple of the tier step is a boss round")
	for c in _ui._choices:
		assert_true(bool(c["boss"]), "every boss-round choice spawns a boss")

func test_boss_is_the_capstone_of_the_tier_just_played() -> void:
	# Boss rounds are every GAMES_PER_TIER games; each boss rolls at the tier the
	# player just cleared (game-4 boss is Low), then the run advances. Once on
	# Insane, bosses stay Insane.
	var T := RunDifficulty.Tier
	# Normal games use the plain tier.
	GameState.games_played = 2
	assert_eq(_ui._current_tier(), T.LOW, "games 1-3 are Low")
	GameState.games_played = 4
	assert_eq(_ui._current_tier(), T.MEDIUM, "games after the first boss are Medium")
	# Boss rounds cap the tier just played.
	GameState.games_played = 3   # game 4 boss
	assert_true(_ui._is_boss_round())
	assert_eq(_ui._current_tier(), T.LOW, "the game-4 boss is a Low boss")
	GameState.games_played = 6   # game 7 boss
	assert_eq(_ui._current_tier(), T.MEDIUM, "the next boss is Medium")
	GameState.games_played = 9   # game 10 boss
	assert_eq(_ui._current_tier(), T.HIGH, "then High")
	GameState.games_played = 12  # game 13 boss
	assert_eq(_ui._current_tier(), T.INSANE, "then Insane")
	GameState.games_played = 15  # every 3 games on Insane
	assert_true(_ui._is_boss_round())
	assert_eq(_ui._current_tier(), T.INSANE, "Insane bosses keep coming every 3 games")

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

func test_bash_allowed_on_boss_round_still_faces_a_boss() -> void:
	# The boss is tied to the difficulty gate, not the game: you may bash the
	# offered game, but whatever backfills the slot still spawns a boss.
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	GameState.bash = 1
	_ui._build_choices()
	var bashed_id: StringName = _ui._choices[0]["slot"]
	_ui.bash_choice(0)
	assert_eq(GameState.bash, 0, "bash is allowed on a boss round")
	assert_true(GameLoop2.is_bashed(bashed_id), "the game was destroyed")
	assert_true(_ui._boss_round, "still a boss round after bashing")
	for c in _ui._choices:
		assert_true(bool(c["boss"]), "every remaining choice still spawns a boss")

func test_transmute_on_boss_round_still_faces_a_boss() -> void:
	GameState.games_played = RunDifficulty.GAMES_PER_TIER
	GameState.transmute = 1
	_ui._build_choices()
	if _ui._choices.size() < 2:
		pass_test("graph too sparse for an off-map transmute target")
		return
	var slot: StringName = _ui._choices[0]["slot"]
	_ui.transmute_choice(0)
	# The slot's game may have been swapped for an off-graph game...
	for c in _ui._choices:
		if c["slot"] == slot:
			assert_true(bool(c["boss"]), "the transmuted game still spawns a boss")

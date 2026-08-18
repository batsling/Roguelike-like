extends GutTest

# Tests for the games-first (2.0) ScrollSystem (docs/games-first-redesign.md §4.1):
# global per-type identification, mystery-vs-identified display, and read_scroll's
# six effects wired into GameLoop2 + GameState. Pure logic, no UI: interactive
# effects (identify / scare / teleport) surface as `requests` the tests assert on.

const SCROLL_IDS := [
	"scroll_of_aggravate_monsters", "scroll_of_amnesia", "scroll_of_create_monster",
	"scroll_of_identify", "scroll_of_scare_monster", "scroll_of_teleportation",
]

# Choose a game and take its ESCORT straight back off the board.
#
# Committing to a game stands a second, randomly-rolled body beside the game's
# own enemy (§7.5, and test_gameloop2.gd, which is where that rule is tested).
# These tests are about something else, and a stranger from the authored roster
# standing on the board would put content they never asked about inside their
# assertions.
func _choose_solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	return r

func _enemy(dmg: int) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = dmg
	return e

# --- Data ------------------------------------------------------------------

func test_all_scrolls2_load() -> void:
	for id in SCROLL_IDS:
		assert_not_null(Data.get_scroll(StringName(id)), "scroll '%s' loads" % id)

# --- Identification --------------------------------------------------------

func test_identify_is_global_per_type() -> void:
	assert_false(ScrollSystem.is_identified(&"scroll_of_identify"))
	assert_true(ScrollSystem.identify(&"scroll_of_identify"), "first identify is new")
	assert_false(ScrollSystem.identify(&"scroll_of_identify"), "re-identify is a no-op")
	ScrollSystem.unidentify(&"scroll_of_identify")
	assert_false(ScrollSystem.is_identified(&"scroll_of_identify"))

func test_display_name_hides_unidentified() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	assert_eq(ScrollSystem.display_name(s), "Unidentified Scroll")
	ScrollSystem.identify(s.id)
	assert_eq(ScrollSystem.display_name(s), s.display_name)

func test_reading_learns_by_use() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	assert_false(ScrollSystem.is_identified(s.id))
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_true(ScrollSystem.is_identified(s.id), "reading a scroll identifies its type")

# --- Effects ---------------------------------------------------------------

func test_aggravate_puts_strength_on_every_body() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	# Bring an enemy to the front line first, so the buffed hit lands this game
	# rather than several games of walking later.
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)   # spawn column
	while int(GameLoop2.stack[0].get("col", 1)) > 1:
		GameLoop2.beat_game(false)                                  # -> front column
	var s: ScrollData = Data.get_scroll(&"scroll_of_aggravate_monsters")
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	var entry: Dictionary = GameLoop2.stack[0]
	assert_eq(int((entry["statuses"] as Dictionary).get(&"strength", 0)), 1,
		"Aggravate is +1 Strength, on the body")
	assert_eq(GameLoop2.enemy_damage(entry), 3, "which is 2 base + 1")
	# And it lands: the front-line enemy hits for the buffed number.
	GameLoop2.beat_game(false)
	assert_eq(GameState.hp, 7, "front-line enemy hit for 3")

func test_aggravate_does_not_wear_off() -> void:
	# The whole reason it was moved onto a status: the old bonus expired after a
	# game, which made a Negative scroll a bad couple of minutes rather than a
	# lasting mistake.
	GameState.max_hp = 20
	GameState.hp = 20
	_choose_solo(_enemy(2)) ; GameLoop2.beat_game(false)
	while int(GameLoop2.stack[0].get("col", 1)) > 1:
		GameLoop2.beat_game(false)
	ScrollSystem.read_scroll(Data.get_scroll(&"scroll_of_aggravate_monsters"),
		{"rng": _rng()})
	GameLoop2.beat_game(false)
	var after_one: int = GameState.hp
	GameLoop2.beat_game(false)
	assert_eq(after_one - GameState.hp, 3, "still hitting for the buffed number")

func test_create_monster_grows_the_stack() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_create_monster")
	var before: int = GameLoop2.stack_size()
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(GameLoop2.stack_size(), before + 1, "Create Monster adds a following enemy")

func test_amnesia_forgets_a_known_scroll() -> void:
	ScrollSystem.identify(&"scroll_of_teleportation")
	assert_eq(GameState.identified_scroll_types.size(), 1)
	var s: ScrollData = Data.get_scroll(&"scroll_of_amnesia")
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	# Reading identifies Amnesia (learn-by-use), taking the known set to 2, then it
	# forgets one random known scroll — so exactly one type remains identified.
	assert_eq(GameState.identified_scroll_types.size(), 1, "net one scroll forgotten")

func test_identify_returns_a_choice_request() -> void:
	# A carried, still-unidentified scroll is a candidate to identify.
	GameState.add_scroll_loot(&"scroll_of_teleportation")
	var s: ScrollData = Data.get_scroll(&"scroll_of_identify")
	var out: Dictionary = ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(out["requests"].size(), 1, "Identify surfaces a choose request")
	assert_eq(String(out["requests"][0]["kind"]), "identify_scrolls")

func test_scare_monster_returns_a_stun_request() -> void:
	GameLoop2.spawn_to_stack(_enemy(2))
	var s: ScrollData = Data.get_scroll(&"scroll_of_scare_monster")
	var out: Dictionary = ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(out["requests"].size(), 1, "Scare Monster surfaces a choose request")
	assert_eq(String(out["requests"][0]["kind"]), "stun_enemies")

func test_teleport_returns_a_teleport_request() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_teleportation")
	var out: Dictionary = ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(out["requests"].size(), 1)
	assert_eq(String(out["requests"][0]["kind"]), "teleport")

# --- Fulfilment helpers ----------------------------------------------------

func test_stun_enemies_chosen_stuns_the_target() -> void:
	var inst: int = GameLoop2.spawn_to_stack(_enemy(2))
	ScrollSystem.stun_enemies_chosen([inst])
	assert_eq(int(GameLoop2.stack[0]["stun"]), 1, "the chosen enemy is stunned")

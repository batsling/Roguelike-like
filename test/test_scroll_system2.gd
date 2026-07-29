extends GutTest

# Tests for the games-first (2.0) ScrollSystem (docs/games-first-redesign.md §4.1):
# global per-type identification, mystery-vs-identified display, and read_scroll's
# six effects wired into GameLoop2 + GameState. Pure logic, no UI: interactive
# effects (identify / scare / teleport) surface as `requests` the tests assert on.

const SCROLL_IDS := [
	"scroll_of_aggravate_monsters", "scroll_of_amnesia", "scroll_of_create_monster",
	"scroll_of_identify", "scroll_of_scare_monster", "scroll_of_teleportation",
]

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

func test_aggravate_arms_enemy_damage_bonus() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	# Bring an enemy to the front line first — Aggravate lasts only one game, and
	# an enemy needs several games to close from the spawn column (§grid), so the
	# buff must be armed once the enemy is already in melee for it to land.
	GameLoop2.choose_game(_enemy(2)) ; GameLoop2.beat_game(false)   # spawn column
	GameLoop2.beat_game(false) ; GameLoop2.beat_game(false)         # -> front column
	var s: ScrollData = Data.get_scroll(&"scroll_of_aggravate_monsters")
	ScrollSystem.read_scroll(s, {"rng": _rng()})
	assert_eq(GameLoop2.enemy_damage_bonus, 1, "Aggravate is +1 damage")
	assert_gt(GameLoop2.enemy_damage_bonus_games, 0, "for at least one game")
	# The bonus lands: the front-line enemy hits for damage + bonus = 3.
	GameLoop2.beat_game(false)
	assert_eq(GameState.hp, 7, "front-line enemy hit for 2 + 1 aggravate")

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

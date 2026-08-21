extends GutTest

# Tests for the games-first (2.0) PILL system (docs/games-first-redesign.md §4.3):
# the per-run colour deal, horse doses, colour-scoped identification, the ten
# pills' effects, Bad Trip's health-dependent name, Lucky Foot's reroll, Bonus
# Shields, and Echo Chamber's replay through LootSystem. Pure logic, no UI —
# movement surfaces as a `request` the tests assert on, as the scrolls' do.

const PILL_IDS := [
	"luck_up", "luck_down", "telepills", "48_hour_energy", "health_up",
	"health_down", "bad_trip", "full_health", "balls_of_steel", "amnesia",
]

func before_each() -> void:
	GameState.reset_run()
	GameLoop2.reset()

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	return r

func _entry(id: StringName, horse: bool = false) -> Dictionary:
	return {"type": "pill", "id": id, "horse": horse}

func _take(id: StringName, horse: bool = false) -> Dictionary:
	return PillSystem.take_pill(_entry(id, horse), {"rng": _rng()})

func _enemy(dmg: int) -> GoalEnemyData:
	var e := GoalEnemyData.new()
	e.id = &"synthetic"
	e.display_name = "Synthetic"
	e.damage = dmg
	return e

# Choose a game and take its escort straight back off the board (§7.5) — these
# tests are not about the escort, and a stranger from the roster standing on the
# board would put content they never asked about inside their assertions.
func _choose_solo(enemy: GoalEnemyData) -> int:
	var inst: int = GameLoop2.choose_game(enemy)
	if GameLoop2.escort_instance() > 0:
		GameLoop2.despawn(GameLoop2.escort_instance())
	return inst

# --- Data ------------------------------------------------------------------

func test_all_pills_load() -> void:
	assert_eq(Data.all_pills().size(), PILL_IDS.size())
	for id in PILL_IDS:
		var p: PillData = Data.get_pill(StringName(id))
		assert_not_null(p, "pill %s loads" % id)
		if p == null:
			continue
		assert_ne(p.display_name, "", "%s is named" % id)
		assert_false(p.effect.is_empty(), "%s does something" % id)
		assert_false(p.horse_effect.is_empty(), "%s has a horse dose" % id)

func test_every_colour_in_the_list_is_on_disk_with_its_horse_twin() -> void:
	# The const list is what the deal draws from, so art that isn't in it is art no
	# run can ever show — and a name in it with no file behind it is a broken tile.
	for color in PillSystem.COLORS:
		assert_true(ResourceLoader.exists("res://images2.0/pills/%s.png" % color),
			"%s.png ships" % color)
		assert_true(ResourceLoader.exists("res://images2.0/pills/%sHorse.png" % color),
			"%sHorse.png ships beside it" % color)

func test_the_horse_dose_is_the_bigger_one() -> void:
	# Not a rule the code enforces — it is a content claim, and it is the whole
	# reason the 5% roll is worth anything. Checked on the four pills that are a
	# NUMBER; the other four say something the normal dose can't.
	for id in ["luck_up", "luck_down", "health_up", "health_down", "bad_trip",
			"balls_of_steel"]:
		var p: PillData = Data.get_pill(StringName(id))
		assert_gt(int(p.horse_effect[0].get("value", 0)), int(p.effect[0].get("value", 0)),
			"the horse %s hits harder" % id)

# --- The colour deal -------------------------------------------------------

func test_every_pill_is_dealt_a_distinct_colour() -> void:
	PillSystem.ensure_colors()
	var seen := {}
	for id in PILL_IDS:
		var color: String = PillSystem.color_for(StringName(id))
		assert_ne(color, "", "%s wears a capsule" % id)
		assert_false(seen.has(color), "%s is not sharing %s" % [id, color])
		seen[color] = true

func test_three_colours_sit_out_every_run() -> void:
	# The fact the whole design rests on: nine known colours do not tell you what
	# the tenth is, because three of the thirteen mean nothing at all.
	PillSystem.ensure_colors()
	assert_eq(PillSystem.unused_colors().size(),
		PillSystem.COLORS.size() - PILL_IDS.size())

func test_the_deal_is_stable_within_a_run_and_redealt_between_them() -> void:
	PillSystem.ensure_colors()
	var first: Dictionary = GameState.pill_color_map.duplicate()
	PillSystem.ensure_colors()
	assert_eq(GameState.pill_color_map, first, "a second call changes nothing")
	# A reload must not redeal underneath a player who spent the run learning it.
	var differs: bool = false
	for _i in range(12):
		GameState.pill_color_map.clear()
		PillSystem.ensure_colors()
		if GameState.pill_color_map != first:
			differs = true
			break
	assert_true(differs, "a fresh run deals a different alphabet")

func test_a_colour_reads_back_to_its_pill() -> void:
	var color: String = PillSystem.color_for(&"luck_up")
	var back: PillData = PillSystem.pill_for_color(color)
	assert_not_null(back)
	assert_eq(back.id, &"luck_up")

# --- The horse dose is DRAWN oversized (§4.3) ------------------------------
#
# "Because the art is visibly oversized, the player always knows a horse pill is a
# horse pill." That was true of the art files and false of everything that drew
# them: every surface fitted loot into a FIXED box, which renders a 19px capsule
# and a 25px one at identical size. These are about the tell surviving the UI.

func test_a_horse_dose_reports_a_bigger_art_scale_than_a_normal_one() -> void:
	assert_eq(PillSystem.art_scale(_entry(&"luck_up")), 1.0,
		"a normal dose draws at the size it is asked for")
	assert_gt(PillSystem.art_scale(_entry(&"luck_up", true)), 1.0,
		"and a horse dose draws BIGGER — the one tell you can always read")

func test_the_horse_scale_is_measured_from_the_art_rather_than_hardcoded() -> void:
	var color: String = PillSystem.color_for(&"luck_up")
	var normal: Texture2D = load("res://images2.0/pills/%s.png" % color)
	var horse: Texture2D = load("res://images2.0/pills/%sHorse.png" % color)
	assert_not_null(normal)
	assert_not_null(horse)
	if normal == null or horse == null:
		return
	assert_almost_eq(PillSystem.art_scale(_entry(&"luck_up", true)),
		float(horse.get_height()) / float(normal.get_height()), 0.001,
		"the ratio comes from the two files, so redrawing the art bigger "
		+ "draws it bigger")

func test_every_surface_sizes_loot_art_through_one_rule() -> void:
	# LootSystem.art_box is what the window, both modals and the card all call.
	var base: int = 40
	assert_eq(LootSystem.art_box(_entry(&"luck_up"), base), base)
	assert_gt(LootSystem.art_box(_entry(&"luck_up", true), base), base,
		"the horse dose comes back bigger wherever it is drawn")
	assert_eq(LootSystem.art_box({"type": "scroll", "id": &"scroll_of_fire"}, base), base,
		"a scroll has one size and is unaffected")

# --- Identification --------------------------------------------------------

func test_a_pill_starts_unknown_and_is_learned_by_taking_it() -> void:
	assert_false(PillSystem.is_identified(&"luck_up"))
	assert_eq(PillSystem.display_name(_entry(&"luck_up")), "Unidentified Pill")
	_take(&"luck_up")
	assert_true(PillSystem.is_identified(&"luck_up"), "taking it teaches it")
	assert_eq(PillSystem.display_name(_entry(&"luck_up")), "Luck Up")

func test_identification_belongs_to_the_colour_so_either_dose_teaches_both() -> void:
	_take(&"luck_up", true)                       # take the HORSE dose
	assert_true(PillSystem.is_identified(&"luck_up"))
	assert_eq(PillSystem.display_name(_entry(&"luck_up")), "Luck Up",
		"the normal dose is known too")
	assert_eq(PillSystem.display_name(_entry(&"luck_up", true)), "Horse Luck Up")

func test_an_unknown_pill_shows_its_capsule_but_not_its_preference() -> void:
	# Unlike a scroll, a pill never hides its ART — the capsule is the thing being
	# learned. What it hides is the name and the Preference.
	assert_not_null(PillSystem.art_texture(_entry(&"bad_trip")), "the capsule shows")
	assert_eq(PillSystem.preference(_entry(&"bad_trip")), "", "its flavour does not")
	_take(&"bad_trip")
	assert_eq(PillSystem.preference(_entry(&"bad_trip")), "Negative")

func test_the_horse_dose_wears_the_same_colour_at_a_bigger_size() -> void:
	var color: String = PillSystem.color_for(&"telepills")
	var horse: Texture2D = PillSystem.art_texture(_entry(&"telepills", true))
	assert_not_null(horse)
	assert_eq(horse.resource_path, "res://images2.0/pills/%sHorse.png" % color)

# --- The ten pills ---------------------------------------------------------

func test_luck_up_and_down_move_the_stat_both_ways() -> void:
	GameState.luck = 0
	_take(&"luck_up")
	assert_eq(GameState.luck, 1)
	_take(&"luck_up", true)
	assert_eq(GameState.luck, 3, "the horse dose is +2")
	_take(&"luck_down")
	assert_eq(GameState.luck, 2)
	_take(&"luck_down", true)
	assert_eq(GameState.luck, 0, "and -2")

func test_health_up_arrives_full_and_health_down_takes_only_the_room() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	_take(&"health_up")
	assert_eq(GameState.max_hp, 12)
	assert_eq(GameState.hp, 12, "the container arrives full (§3)")
	GameState.hp = 5
	_take(&"health_down")
	assert_eq(GameState.max_hp, 10)
	assert_eq(GameState.hp, 5, "losing the cap does not cost Health while it fits")

func test_health_down_only_moves_health_when_it_no_longer_fits() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	_take(&"health_down", true)                   # -4 Max Health
	assert_eq(GameState.max_hp, 6)
	assert_eq(GameState.hp, 6, "Health follows the cap down only when it must")

func test_full_health_heals_and_its_horse_dose_also_banks_shields() -> void:
	GameState.max_hp = 10
	GameState.hp = 3
	_take(&"full_health")
	assert_eq(GameState.hp, 10)
	assert_eq(GameState.bonus_shields, 0)
	GameState.hp = 3
	_take(&"full_health", true)
	assert_eq(GameState.hp, 10)
	assert_eq(GameState.bonus_shields, 3, "+3 Bonus Shields on the horse dose")

func test_balls_of_steel_pays_the_pool_that_does_not_expire() -> void:
	_take(&"balls_of_steel")
	assert_eq(GameState.bonus_shields, 2)
	assert_eq(GameState.shields, 0, "not the per-game tries")
	_take(&"balls_of_steel", true)
	assert_eq(GameState.bonus_shields, 6)

func test_bad_trip_costs_health() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	_take(&"bad_trip")
	assert_eq(GameState.hp, 8)
	_take(&"bad_trip", true)
	assert_eq(GameState.hp, 4)

func test_bad_trip_becomes_full_health_when_it_would_kill_you() -> void:
	GameState.max_hp = 10
	GameState.hp = 2                              # the dose is 2 — this is lethal
	var out: Dictionary = _take(&"bad_trip")
	assert_eq(GameState.hp, 10, "it heals to full instead of killing you")
	assert_true(str(out["logs"]).contains("full"), "and says so: %s" % str(out["logs"]))

func test_bad_trip_names_itself_from_your_health() -> void:
	# The label follows what the pill would DO right now, which is why two colours
	# can both claim to be Full Health.
	PillSystem.identify(&"bad_trip")
	GameState.max_hp = 10
	GameState.hp = 10
	assert_eq(PillSystem.display_name(_entry(&"bad_trip")), "Bad Trip")
	GameState.hp = 2
	assert_eq(PillSystem.display_name(_entry(&"bad_trip")), "Full Health",
		"in death range it says what it would do")
	GameState.hp = 3
	assert_eq(PillSystem.display_name(_entry(&"bad_trip")), "Bad Trip",
		"and stops the moment the dose stops being lethal")

func test_the_horse_dose_moves_bad_trips_threshold_with_it() -> void:
	PillSystem.identify(&"bad_trip")
	GameState.max_hp = 10
	GameState.hp = 3
	assert_eq(PillSystem.display_name(_entry(&"bad_trip")), "Bad Trip",
		"3 Health survives a 2-Health dose")
	assert_eq(PillSystem.display_name(_entry(&"bad_trip", true)), "Horse Full Health",
		"but not a 4-Health one")

func test_telepills_asks_the_overworld_to_move_you() -> void:
	var out: Dictionary = _take(&"telepills")
	assert_eq(out["requests"].size(), 1)
	var req: Dictionary = out["requests"][0]
	assert_eq(String(req["kind"]), "teleport")
	assert_eq(String(req["dir"]), "same")
	assert_eq(int(req["spread"]), 2)

func test_the_horse_telepills_lands_by_distance_from_the_amulet() -> void:
	var out: Dictionary = _take(&"telepills", true)
	var req: Dictionary = out["requests"][0]
	assert_eq(String(req["dir"]), "amulet", "the only movement that can reach the goal")
	assert_eq(int(req["min"]), 1)
	assert_eq(int(req["max"]), 3)

func test_amnesia_hands_out_a_curse_goal() -> void:
	var before: int = GameState.curse_goals.size()
	_take(&"amnesia")
	assert_eq(GameState.curse_goals.size(), before + 1)

func test_the_horse_amnesia_forgets_every_identified_piece_of_loot() -> void:
	ScrollSystem.identify(&"scroll_of_identify")
	PillSystem.identify(&"luck_up")
	PillSystem.identify(&"health_up")
	_take(&"amnesia", true)
	assert_false(ScrollSystem.is_identified(&"scroll_of_identify"), "scrolls too")
	assert_false(PillSystem.is_identified(&"luck_up"))
	assert_false(PillSystem.is_identified(&"health_up"))
	# Forgetting is not redealing: the capsule still means what it meant, and taking
	# one is how you find out again.
	assert_ne(PillSystem.color_for(&"luck_up"), "", "the alphabet is intact")

func test_the_horse_amnesia_forgets_itself_too() -> void:
	# "Every identified piece of loot" includes the lesson taking it just taught:
	# the dose that erases the run's knowledge erases its own name with it. So the
	# horse dose can never leave itself known, and the colour is learned from the
	# NORMAL dose instead — which forgets a curse's worth of other things and not
	# this.
	PillSystem.identify(&"luck_up")
	_take(&"amnesia", true)
	assert_false(PillSystem.is_identified(&"amnesia"), "it takes its own name with it")
	assert_false(PillSystem.is_identified(&"luck_up"), "along with everything else")
	_take(&"amnesia")
	assert_true(PillSystem.is_identified(&"amnesia"),
		"the normal dose is how the colour is learned")

func test_48_hour_energy_charges_relics_and_says_so_when_there_are_none() -> void:
	var out: Dictionary = _take(&"48_hour_energy")
	assert_true(str(out["logs"]).contains("charge"), "an empty pack says so: %s" % str(out["logs"]))
	GameState.add_item(Data.get_item2(&"d6"))
	var d6: ItemData = GameState.inventory[GameState.inventory.size() - 1]
	d6.current_charge = 0
	_take(&"48_hour_energy")
	assert_eq(d6.current_charge, d6.max_charge(),
		"three separate charges all land somewhere — here, on the only relic there is")

func test_the_horse_48_hour_energy_fills_the_relics_it_picks() -> void:
	GameState.add_item(Data.get_item2(&"d6"))
	var d6: ItemData = GameState.inventory[GameState.inventory.size() - 1]
	d6.current_charge = 0
	_take(&"48_hour_energy", true)
	assert_eq(d6.current_charge, d6.max_charge())

# --- Bonus Shields (§4.3) --------------------------------------------------

func test_a_lost_run_spends_the_games_own_tries_before_the_bonus_pool() -> void:
	GameState.shields = 1
	GameState.bonus_shields = 2
	var _a: int = _choose_solo(_enemy(1))
	GameState.shields = 1                        # choosing granted more; pin it
	assert_eq(GameLoop2.log_attempt(), "shield", "the per-game pool goes first")
	assert_eq(GameState.bonus_shields, 2, "the bonus pool is untouched while it lasts")
	assert_eq(GameLoop2.log_attempt(), "bonus", "then the pool that would have survived")
	assert_eq(GameState.bonus_shields, 1)

func test_a_bonus_shield_pays_before_health_does() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	var _a: int = _choose_solo(_enemy(1))
	GameState.shields = 0
	GameState.bonus_shields = 1
	assert_eq(GameLoop2.log_attempt(), "bonus")
	assert_eq(GameState.hp, 10, "Health is the last thing a lost run reaches")
	assert_eq(GameLoop2.log_attempt(), "health")
	assert_lt(GameState.hp, 10)

func test_undoing_a_try_refunds_the_pool_it_actually_spent() -> void:
	var _a: int = _choose_solo(_enemy(1))
	GameState.shields = 0
	GameState.bonus_shields = 1
	GameLoop2.log_attempt()
	assert_eq(GameState.bonus_shields, 0)
	GameLoop2.undo_attempt()
	assert_eq(GameState.bonus_shields, 1, "it goes back where it came from")

func test_bonus_shields_absorb_damage_after_the_per_game_pool() -> void:
	# Straight through the resolver every hit on the player goes through, rather
	# than through a game: an enemy does not swing on the game it spawned at (§7.2),
	# so a beat_game here would be testing the timing model instead of the order.
	GameState.max_hp = 10
	GameState.hp = 10
	GameState.shields = 1
	GameState.bonus_shields = 1
	GameLoop2.damage_player(3)
	assert_eq(GameState.shields, 0, "the tries went first")
	assert_eq(GameState.bonus_shields, 0, "then the bonus pool")
	assert_eq(GameState.hp, 9, "and only the last point reached Health")

func test_bonus_shields_survive_the_game_that_did_not_spend_them() -> void:
	GameState.bonus_shields = 2
	var _a: int = _choose_solo(_enemy(0))
	GameState.shields = 3
	GameLoop2.beat_game(true)
	assert_eq(GameState.shields, 0, "the game's own tries expire with it")
	assert_eq(GameState.bonus_shields, 2, "the bonus pool does not")

# --- Lucky Foot ------------------------------------------------------------

func test_lucky_foot_rerolls_a_negative_pill_into_a_positive_one() -> void:
	GameState.max_hp = 10
	GameState.hp = 10
	GameState.add_item(Data.get_item2(&"lucky_foot"))
	var out: Dictionary = _take(&"bad_trip")
	assert_eq(GameState.hp, 10, "the negative dose never landed")
	assert_true(str(out["logs"]).contains("Lucky Foot"),
		"and it says what happened: %s" % str(out["logs"]))

func test_lucky_foot_leaves_the_colour_identified_as_what_it_really_is() -> void:
	# The relic changes the OUTCOME, never the fact — any other reading starts
	# lying to the player the moment the Foot leaves the pack.
	GameState.add_item(Data.get_item2(&"lucky_foot"))
	_take(&"luck_down")
	assert_true(PillSystem.is_identified(&"luck_down"))
	assert_eq(PillSystem.display_name(_entry(&"luck_down")), "Luck Down")

func test_lucky_foot_leaves_neutral_pills_alone() -> void:
	GameState.add_item(Data.get_item2(&"lucky_foot"))
	var out: Dictionary = _take(&"telepills")
	assert_eq(out["requests"].size(), 1, "Telepills still teleports")
	assert_false(str(out["logs"]).contains("Lucky Foot"),
		"a Neutral pill is not an upgrade waiting to happen")

func test_lucky_foot_rerolls_a_horse_dose_into_a_horse_dose() -> void:
	# The size of the capsule is what you were handed; the Foot is not holding a
	# smaller one. Balls of Steel is the only Positive that pays a countable pool,
	# so run it until the reroll lands there and check the number is the big one.
	GameState.add_item(Data.get_item2(&"lucky_foot"))
	var horse_sized: bool = false
	for _i in range(40):
		GameState.bonus_shields = 0
		PillSystem.take_pill(_entry(&"luck_down", true))
		if GameState.bonus_shields == 4:
			horse_sized = true
			break
		assert_ne(GameState.bonus_shields, 2, "a horse pill never pays the small dose")
	assert_true(horse_sized, "the reroll pays the horse dose of whatever it rolled")

# --- Sacred Bark -----------------------------------------------------------

func test_sacred_bark_doubles_a_pill() -> void:
	GameState.luck = 0
	_take(&"luck_up")
	assert_eq(GameState.luck, 1)
	GameState.add_item(Data.get_item2(&"sacred_bark"))
	_take(&"luck_up")
	assert_eq(GameState.luck, 3, "the second one landed for two")

func test_sacred_bark_doubles_the_negative_rows_too() -> void:
	GameState.add_item(Data.get_item2(&"sacred_bark"))
	GameState.max_hp = 20
	GameState.hp = 20
	_take(&"bad_trip")
	assert_eq(GameState.hp, 16, "a relic that only doubled the upside would break the gamble")

func test_sacred_bark_does_not_double_a_teleports_spread() -> void:
	GameState.add_item(Data.get_item2(&"sacred_bark"))
	var out: Dictionary = _take(&"telepills")
	assert_eq(int(out["requests"][0]["spread"]), 2,
		"doubling how far a landing may VARY is not twice the pill, it is a worse one")

# --- The pack --------------------------------------------------------------

func test_the_pack_holds_nine() -> void:
	GameState.add_loot("pill", 20)
	assert_eq(GameState.loot_items.size(), GameState.LOOT_CAPACITY)
	assert_true(GameState.loot_is_full())
	assert_eq(GameState.loot_space(), 0)

func test_a_kind_blind_grant_rolls_between_the_two() -> void:
	var kinds := {}
	for _i in range(60):
		GameState.loot_items.clear()
		GameState.add_loot("loot", 1)
		if not GameState.loot_items.is_empty():
			kinds[String(GameState.loot_items[0].get("type", ""))] = true
	assert_true(kinds.has("scroll"), "scrolls come up")
	assert_true(kinds.has("pill"), "and so do pills")

func test_a_rolled_drop_is_sometimes_a_horse_pill() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var horses: int = 0
	for _i in range(400):
		if bool(PillSystem.roll_pill_loot(rng).get("horse", false)):
			horses += 1
	assert_gt(horses, 0, "the 5% roll happens")
	assert_lt(horses, 80, "and it is a 5% roll, not a coin")

func test_a_full_pack_refuses_a_taken_drop_rather_than_swallowing_it() -> void:
	GameState.add_loot("pill", GameState.LOOT_CAPACITY)
	assert_false(GameState.take_loot_entry(GameState.roll_loot_entry("pill")))
	assert_eq(GameState.loot_items.size(), GameState.LOOT_CAPACITY)

# --- LootSystem: spending, and Echo Chamber --------------------------------

func test_using_loot_consumes_it() -> void:
	GameState.add_pill_loot(&"luck_up")
	GameState.luck = 0
	LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(GameState.loot_items.size(), 0, "the pill is gone")
	assert_eq(GameState.luck, 1, "and it did what it says")

func test_echo_chamber_replays_the_last_three_used() -> void:
	GameState.luck = 0
	for _i in range(3):
		GameState.add_pill_loot(&"luck_up")
	LootSystem.use_loot(0)                       # 1st: nothing to echo yet
	LootSystem.use_loot(0)                       # 2nd
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	assert_eq(GameState.luck, 2, "two ordinary uses so far")
	LootSystem.use_loot(0)                       # 3rd, now with the relic
	assert_eq(GameState.luck, 5,
		"the use itself plus the two it remembers")

func test_nothing_echoes_itself() -> void:
	# Isaac's ordering: the copies fire off the memory as it stood BEFORE this use,
	# and only then does this use join it. Without that, one pill on a fresh memory
	# would already be two.
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	GameState.add_pill_loot(&"luck_up")
	GameState.luck = 0
	LootSystem.use_loot(0)
	assert_eq(GameState.luck, 1, "the first use with an empty memory is just itself")

func test_an_echoed_copy_is_not_itself_remembered() -> void:
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	for _i in range(2):
		GameState.add_pill_loot(&"luck_up")
	LootSystem.use_loot(0)
	LootSystem.use_loot(0)
	assert_eq(LootSystem.used_memory().size(), 2,
		"two uses, two memories — the echo did not add a third")

func test_the_echo_memory_is_the_runs_and_survives_a_second_relic() -> void:
	GameState.add_pill_loot(&"luck_up")
	LootSystem.use_loot(0)
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	assert_eq(GameState.loot_echo_depth(), 3,
		"two Echo Chambers are one three-deep memory, not six")

func test_echoes_carry_their_requests_back_too() -> void:
	# A doubled Telepills has to ask the overworld to move you twice; a path that
	# merged only the logs would silently drop half of what it just did.
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	for _i in range(2):
		GameState.add_pill_loot(&"telepills")
	LootSystem.use_loot(0)
	var out: Dictionary = LootSystem.use_loot(0)
	assert_eq(out["requests"].size(), 2, "the use and its echo both want to move you")

func test_sacred_bark_and_echo_chamber_compose() -> void:
	# One pill, both relics: two doses of it plus one echo at two doses. It is
	# deliberately a lot — a Boss relic meeting a Rare one.
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	GameState.luck = 0
	GameState.add_pill_loot(&"luck_up")
	GameState.add_pill_loot(&"luck_up")
	LootSystem.use_loot(0)                       # +1, memory now holds one
	GameState.add_item(Data.get_item2(&"sacred_bark"))
	LootSystem.use_loot(0)
	assert_eq(GameState.luck, 5, "1, then a doubled use (2) and a doubled echo (2)")

func test_loot_of_either_kind_goes_through_one_door() -> void:
	GameState.add_scroll_loot(&"scroll_of_teleportation")
	var out: Dictionary = LootSystem.use_loot(0, {"rng": _rng()})
	assert_eq(out["requests"].size(), 1, "a scroll still resolves through LootSystem")
	assert_eq(GameState.loot_items.size(), 0)

func test_a_pill_echoing_a_scroll_fires_the_scrolls_own_effect() -> void:
	GameState.add_item(Data.get_item2(&"echo_chamber"))
	GameState.add_scroll_loot(&"scroll_of_teleportation")
	GameState.add_pill_loot(&"luck_up")
	GameState.luck = 0
	LootSystem.use_loot(0, {"rng": _rng()})      # the scroll
	var out: Dictionary = LootSystem.use_loot(0, {"rng": _rng()})   # the pill
	assert_eq(GameState.luck, 1, "the pill landed")
	assert_eq(out["requests"].size(), 1, "and the scroll it echoed asked to move you")

# --- Naming for the window -------------------------------------------------

func test_loot_names_and_art_come_back_for_both_kinds() -> void:
	var scroll := {"type": "scroll", "id": &"scroll_of_identify", "rarity": "Common"}
	assert_eq(LootSystem.display_name(scroll), "Unidentified Scroll")
	assert_eq(LootSystem.glyph(scroll), "📜")
	assert_eq(LootSystem.display_name(_entry(&"luck_up", true)), "Unidentified Horse Pill")
	assert_eq(LootSystem.glyph(_entry(&"luck_up")), "💊")
	assert_not_null(LootSystem.art_texture(_entry(&"luck_up")))

func test_the_dev_panel_grants_a_pill_without_giving_the_answer_away() -> void:
	# A debug grant that identified what it handed over could not be used to test
	# the finding out, which is the only thing a pill does.
	DevTools._grant_horse = true
	GameState.add_pill_loot(&"bad_trip", DevTools._grant_horse)
	assert_eq(GameState.loot_pills().size(), 1)
	assert_true(bool(GameState.loot_pills()[0].get("horse", false)), "at the dose asked for")
	assert_false(PillSystem.is_identified(&"bad_trip"), "and still a mystery")
	DevTools._grant_horse = false

# --- Save / load -----------------------------------------------------------

func test_the_alphabet_and_what_is_known_survive_a_save() -> void:
	PillSystem.ensure_colors()
	_take(&"luck_up")
	GameState.bonus_shields = 3
	var alphabet: Dictionary = GameState.pill_color_map.duplicate()
	var payload: Dictionary = {
		"identified_pill_types": ["luck_up"],
		"pill_color_map": alphabet.duplicate(),
		"bonus_shields": 3,
	}
	GameState.reset_run()
	assert_eq(GameState.bonus_shields, 0, "a fresh run holds none of it")
	# The restore path's own reading of those three keys, without booting a whole
	# run around them.
	GameState.bonus_shields = int(payload["bonus_shields"])
	for id in payload["identified_pill_types"]:
		GameState.identified_pill_types.append(StringName(id))
	for k in payload["pill_color_map"].keys():
		GameState.pill_color_map[String(k)] = String(payload["pill_color_map"][k])
	assert_eq(GameState.pill_color_map, alphabet, "the same capsules mean the same pills")
	assert_true(PillSystem.is_identified(&"luck_up"))
	assert_eq(GameState.bonus_shields, 3)

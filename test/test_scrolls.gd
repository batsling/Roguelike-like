extends GutTest

# Covers the scroll loot foundation: data load + DSL-parsed outcome effects, the
# two-roll Intelligence resolver, global identification, carried-loot bookkeeping
# on GameState, and ScrollSystem's non-interactive effect application + the
# pending-combat carryover applier shared by every combat mode.

const EXPECTED_SCROLLS := [
	"blank_scroll", "scroll_of_aggravate_monsters", "scroll_of_amnesia",
	"scroll_of_create_food", "scroll_of_create_monster", "scroll_of_enchant_weapon",
	"scroll_of_fire", "scroll_of_identify", "scroll_of_scare_monster",
	"scroll_of_sleep", "scroll_of_teleportation", "scroll_of_vorpalize_weapon",
]

func before_each() -> void:
	GameState.identified_scroll_types.clear()
	GameState.identified_potion_types.clear()
	GameState.loot_items.clear()
	GameState.learned_spells.clear()
	GameState.pending_enemy_buff = {}
	GameState.pending_enemy_start_stun = {}
	GameState.pending_fire_damage_all = 0
	GameState.pending_spawn_enemies.clear()
	GameState.pending_combat_statuses.clear()
	GameState.pending_ambush = ""

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 42
	return r

# --- Data --------------------------------------------------------------------

func test_all_scrolls_load_with_four_tiers() -> void:
	for id in EXPECTED_SCROLLS:
		var s: ScrollData = Data.get_scroll(StringName(id))
		assert_not_null(s, "scroll '%s' should load" % id)
		if s != null:
			for tier in ScrollData.TIER_KEYS:
				assert_true(s.outcomes.has(tier), "%s has tier %s" % [id, tier])

func test_effect_dsl_parsed_into_structured_ops() -> void:
	var aggravate: ScrollData = Data.get_scroll(&"scroll_of_aggravate_monsters")
	var eff: Array = aggravate.outcome_effects("good")
	assert_eq(eff.size(), 1)
	assert_eq(String(eff[0]["op"]), "buff_enemies")
	assert_eq(int(eff[0]["power"]), 2, "Success tier is +2 Power")
	# Blank Scroll's "nothing" parses to an empty effect list on every tier.
	var blank: ScrollData = Data.get_scroll(&"blank_scroll")
	assert_eq(blank.outcome_effects("crit_good").size(), 0, "Blank does nothing")

func test_roll_scroll_returns_a_scroll() -> void:
	assert_not_null(Data.roll_scroll(_rng()), "roll_scroll returns a scroll")

# --- Resolver ----------------------------------------------------------------

func test_resolve_outcome_tier_matches_rolls() -> void:
	# With a fixed seed the resolver is deterministic; assert the tier is one of
	# the four and is internally consistent with success/crit.
	var saved: int = GameState.intelligence
	GameState.intelligence = 0
	var res: Dictionary = ScrollSystem.resolve_outcome(_rng())
	assert_true(ScrollData.TIER_KEYS.has(String(res["tier"])), "tier is valid")
	var ok: bool = bool(res["success"])
	var crit: bool = bool(res["is_crit"])
	var expected := ("crit_good" if (ok and crit) else "good") if ok \
		else ("crit_bad" if crit else "bad")
	assert_eq(String(res["tier"]), expected, "tier follows success+crit")
	GameState.intelligence = saved

func test_high_intelligence_guarantees_success() -> void:
	var saved: int = GameState.intelligence
	GameState.intelligence = 20  # d20 + 20 always >= DC 10
	for _i in range(20):
		var res: Dictionary = ScrollSystem.resolve_outcome(null)
		assert_true(bool(res["success"]), "INT 20 always clears DC 10")
	GameState.intelligence = saved

# --- Identification ----------------------------------------------------------

func test_identify_is_global_per_type() -> void:
	assert_false(ScrollSystem.is_identified(&"scroll_of_identify"))
	assert_true(ScrollSystem.identify(&"scroll_of_identify"), "first identify is new")
	assert_false(ScrollSystem.identify(&"scroll_of_identify"), "re-identify is a no-op")
	ScrollSystem.unidentify(&"scroll_of_identify")
	assert_false(ScrollSystem.is_identified(&"scroll_of_identify"))

func test_display_name_hides_unidentified() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_fire")
	assert_eq(ScrollSystem.display_name(s), "Unidentified Scroll")
	ScrollSystem.identify(&"scroll_of_fire")
	assert_eq(ScrollSystem.display_name(s), "Scroll of Fire")

# --- Loot bookkeeping --------------------------------------------------------

func test_add_and_remove_scroll_loot() -> void:
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_scroll_loot(&"scroll_of_identify")
	assert_eq(GameState.get_loot_count("scroll"), 2)
	assert_eq(GameState.loot_scrolls().size(), 2)
	GameState.remove_loot_at(0)
	assert_eq(GameState.get_loot_count("scroll"), 1)

# --- Non-interactive effects -------------------------------------------------

func test_aggravate_schedules_enemy_buff() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_aggravate_monsters")
	ScrollSystem.apply_outcome(s, "crit_bad", {"rng": _rng()})  # +3 Power +3 Defense
	assert_eq(int(GameState.pending_enemy_buff.get("power", 0)), 3)
	assert_eq(int(GameState.pending_enemy_buff.get("defense", 0)), 3)

func test_fire_schedules_damage_and_hurts_player() -> void:
	var hp0: int = GameState.hp
	var s: ScrollData = Data.get_scroll(&"scroll_of_fire")
	ScrollSystem.apply_outcome(s, "crit_good", {"rng": _rng()})  # self 10, enemies 10
	assert_eq(GameState.hp, hp0 - 10, "Scroll of Fire burns the reader for 10")
	assert_eq(GameState.pending_fire_damage_all, 10, "and schedules 10 to all enemies")

func test_scare_monster_schedules_start_stun() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_scare_monster")
	ScrollSystem.apply_outcome(s, "crit_good", {"rng": _rng()})  # stun all
	assert_true(bool(GameState.pending_enemy_start_stun.get("all", false)))

func test_sleep_schedules_ambush_and_fear() -> void:
	var s: ScrollData = Data.get_scroll(&"scroll_of_sleep")
	ScrollSystem.apply_outcome(s, "crit_bad", {"rng": _rng()})  # +3 Fear, ambush
	assert_eq(GameState.pending_ambush, "ambushed")
	var fear := 0
	for e in GameState.pending_combat_statuses:
		if String(e.get("status", "")) == "fear":
			fear = int(e.get("stacks", 0))
	assert_eq(fear, 3, "crit-fail Sleep inflicts 3 Fear next combat")

func test_create_monster_queues_spawns() -> void:
	# Raise the run tier so the difficulty filter admits weight<=5 enemies of any
	# (non-boss) tier — keeps the count assertion independent of the saved tier.
	var saved: int = GameState.games_played
	GameState.games_played = 99
	var s: ScrollData = Data.get_scroll(&"scroll_of_create_monster")
	ScrollSystem.apply_outcome(s, "crit_bad", {"rng": _rng()})  # 2 enemies w<=5
	assert_eq(GameState.pending_spawn_enemies.size(), 2, "two enemies queued")
	GameState.games_played = saved

func test_identify_all_reveals_carried_scrolls() -> void:
	GameState.add_scroll_loot(&"scroll_of_fire")
	GameState.add_scroll_loot(&"scroll_of_sleep")
	var s: ScrollData = Data.get_scroll(&"scroll_of_identify")
	ScrollSystem.apply_outcome(s, "crit_good", {"rng": _rng()})  # identify all
	assert_true(ScrollSystem.is_identified(&"scroll_of_fire"))
	assert_true(ScrollSystem.is_identified(&"scroll_of_sleep"))

func test_amnesia_forgets_identified() -> void:
	ScrollSystem.identify(&"scroll_of_fire")
	PotionSystem.identify(&"fire_potion")
	GameState.learned_spells.append(&"spark")
	GameState.learned_spells.append(&"frost")
	var s: ScrollData = Data.get_scroll(&"scroll_of_amnesia")
	ScrollSystem.apply_outcome(s, "crit_bad", {"rng": _rng()})  # forget all + 2 spells
	assert_eq(GameState.identified_scroll_types.size(), 0, "all scroll knowledge forgotten")
	assert_eq(GameState.identified_potion_types.size(), 0, "all potion knowledge forgotten")
	assert_eq(GameState.learned_spells.size(), 0, "both spells forgotten")

func test_choose_effects_return_requests() -> void:
	# Tiers that need a player choice surface a request instead of applying blind.
	var identify: ScrollData = Data.get_scroll(&"scroll_of_identify")
	GameState.add_scroll_loot(&"scroll_of_fire")
	var out: Dictionary = ScrollSystem.apply_outcome(identify, "good", {"rng": _rng()})
	assert_eq(out["requests"].size(), 1, "choose-identify yields one request")
	assert_eq(String(out["requests"][0]["kind"]), "identify_scrolls")

# --- Pending carryover applier -----------------------------------------------

func test_apply_pending_combat_effects_invokes_closures() -> void:
	GameState.pending_enemy_buff = {"power": 2, "defense": 1}
	GameState.pending_enemy_start_stun = {"all": true, "count": 2}
	GameState.pending_fire_damage_all = 7
	var seen := {"buff": null, "stun": [], "fire": 0}
	var buff_fn := func(p, d): seen["buff"] = [p, d]
	var stun_fn := func(mode, count): seen["stun"].append([mode, count])
	var fire_fn := func(amt): seen["fire"] = amt
	ScrollSystem.apply_pending_combat_effects(stun_fn, buff_fn, fire_fn)
	assert_eq(seen["buff"], [2, 1], "buff closure got power/defense")
	assert_eq(seen["fire"], 7, "fire closure got the amount")
	assert_true(seen["stun"].has(["all", 0]), "all-stun dispatched")
	assert_true(seen["stun"].has(["random", 2]), "count-stun dispatched")
	# The carryover is drained so it never double-applies next combat.
	assert_true(GameState.pending_enemy_buff.is_empty())
	assert_eq(GameState.pending_fire_damage_all, 0)
	assert_true(GameState.pending_enemy_start_stun.is_empty())

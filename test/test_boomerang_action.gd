extends GutTest

# Sword Boomerang's action-mode flight model: the blade is a LIVE body whose
# hitbox is active for the entire flight — enemies it merely passes through get
# clipped (so it can land more than its N designated hits) — and the next
# random enemy is chosen one at a time, on arrival at the current target.
# The ticks drive _process_boomerangs directly with a fixed delta so the
# flight is deterministic.

const ACTION_COMBAT := preload("res://scenes/action/ActionCombat.tscn")

var arena

func before_each() -> void:
	GameState.reset_run()
	GameState.apply_character(Data.get_character(&"ironclad"))
	arena = ACTION_COMBAT.instantiate()
	arena.target_game_id = &""
	arena.enemies_to_spawn = []
	add_child_autofree(arena)

func _add_enemy(pos: Vector2) -> Dictionary:
	var data: ActionEnemyData = Data.get_action_enemy(&"gaper")
	var inst: Dictionary = arena._make_enemy_inst(data, pos)
	inst.actor.max_hp = 100
	inst.actor.hp = 100
	arena.enemies.append(inst)
	return inst

func _fly_until_done(max_ticks: int = 600) -> void:
	for _i in range(max_ticks):
		if arena._boomerangs.is_empty():
			return
		arena._process_boomerangs(1.0 / 60.0)
	fail_test("boomerang never finished its flight")

func test_pass_through_enemies_get_clipped_beyond_the_three_hits() -> void:
	# A sits far east; B sits exactly on the flight path between the player and
	# A. Cast while ONLY A lives (so the first pick is forced), then drop B in:
	#   leg 1  player -> A  : B pass-through, A arrival        (A 1, B 1)
	#   leg 2  A -> B       : arrival                          (B 2)
	#   leg 3  B -> A       : arrival, hops spent              (A 2)
	#   return A -> player  : B pass-through on the way home   (B 3)
	# 5 hits total from a 3-hit card — the always-on hitbox at work.
	var a: Dictionary = _add_enemy(arena.player_pos + Vector2(400, 0))
	arena._resolve_card_effects(Data.get_card(&"sword_boomerang"))
	assert_eq(arena._boomerangs.size(), 1, "one live blade in flight")
	var b: Dictionary = _add_enemy(arena.player_pos + Vector2(200, 0))
	_fly_until_done()
	assert_eq(100 - a.actor.hp, 6, "A: leg-1 + leg-3 arrivals = 2 hits")
	assert_eq(100 - b.actor.hp, 9, "B: pass-through + arrival + return pass = 3 hits")
	assert_eq(arena._boomerangs.size(), 0, "blade came home and despawned")

func test_lone_enemy_still_takes_all_designated_hits() -> void:
	var lone: Dictionary = _add_enemy(arena.player_pos + Vector2(300, 0))
	arena._resolve_card_effects(Data.get_card(&"sword_boomerang"))
	_fly_until_done()
	assert_eq(100 - lone.actor.hp, 9, "3 hits land even with a single target")

func test_next_target_is_chosen_on_arrival_not_at_cast() -> void:
	# Cast at a lone enemy, then kill it before the blade arrives. The blade
	# re-targets in flight: the late-spawned enemy — unknown at cast time —
	# soaks the remaining hits. Pre-planned hops could never do this.
	var first: Dictionary = _add_enemy(arena.player_pos + Vector2(400, 0))
	arena._resolve_card_effects(Data.get_card(&"sword_boomerang"))
	first.actor.hp = 0
	var late: Dictionary = _add_enemy(arena.player_pos + Vector2(-300, 0))
	_fly_until_done()
	assert_eq(100 - late.actor.hp, 9, "late spawn soaked all 3 hits (retargeted mid-flight)")

func test_blade_returns_home_when_everyone_dies_mid_flight() -> void:
	var only: Dictionary = _add_enemy(arena.player_pos + Vector2(400, 0))
	arena._resolve_card_effects(Data.get_card(&"sword_boomerang"))
	only.actor.hp = 0
	_fly_until_done()
	assert_eq(arena._boomerangs.size(), 0, "no targets left -> the blade flew home")

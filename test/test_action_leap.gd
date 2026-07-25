extends GutTest

# Guards the LEAP attack-kind schema added to ActionEnemyData for jump/slam bosses
# (Monstro's big jump). The leap's runtime state machine lives in ActionCombat
# (crouch -> airborne/untargetable -> land + tear burst); this covers the data
# contract that drives it, so a hand-authored or generated leap boss keeps loading
# with the fields the engine reads.

func _leaper() -> ActionEnemyData:
	var d := ActionEnemyData.new()
	d.id = &"test_leaper"
	d.display_name = "Test Leaper"
	d.behavior = ActionEnemyData.BehaviorKind.STATIONARY
	# One LEAP attack: kind 2, its own landing damage / cooldown / trigger range.
	d.attack_kinds = PackedInt32Array([ActionEnemyData.AttackKind.LEAP])
	d.attack_damages = PackedInt32Array([12])
	d.attack_cooldowns = PackedFloat32Array([3.0])
	d.attack_ranges = PackedFloat32Array([400.0])
	return d

func test_leap_kind_enum_is_distinct() -> void:
	# LEAP is a third kind, not aliased onto MELEE/RANGED.
	assert_eq(int(ActionEnemyData.AttackKind.LEAP), 2)
	assert_ne(int(ActionEnemyData.AttackKind.LEAP),
		int(ActionEnemyData.AttackKind.MELEE))
	assert_ne(int(ActionEnemyData.AttackKind.LEAP),
		int(ActionEnemyData.AttackKind.RANGED))

func test_attacks_carries_leap_kind_through() -> void:
	var atks: Array = _leaper().attacks()
	assert_eq(atks.size(), 1, "the single LEAP attack round-trips through attacks()")
	var a: Dictionary = atks[0]
	assert_eq(int(a["kind"]), ActionEnemyData.AttackKind.LEAP)
	assert_eq(int(a["damage"]), 12, "landing damage is carried on the attack entry")
	assert_eq(float(a["cooldown"]), 3.0)
	assert_eq(float(a["range"]), 400.0, "trigger range is how close the player must be to leap")

func test_leap_tuning_fields_default_to_engine_placeholders() -> void:
	# 0 means "use ActionCombat's LEAP_DEFAULT_*", so a leap can be authored with
	# just the attack entry and tuned later without any code change.
	var d := _leaper()
	assert_eq(d.leap_telegraph, 0.0)
	assert_eq(d.leap_air_time, 0.0)
	assert_eq(d.leap_height, 0.0)
	assert_eq(d.leap_land_radius, 0.0)
	assert_eq(d.leap_burst_count, 0, "no landing tear burst unless authored")

func test_leap_tuning_fields_are_settable() -> void:
	var d := _leaper()
	d.leap_telegraph = 0.6
	d.leap_air_time = 0.9
	d.leap_height = 80.0
	d.leap_land_radius = 50.0
	d.leap_burst_count = 8
	d.leap_burst_speed = 220.0
	d.leap_burst_lifetime = 2.0
	assert_eq(d.leap_telegraph, 0.6)
	assert_eq(d.leap_air_time, 0.9)
	assert_eq(d.leap_height, 80.0)
	assert_eq(d.leap_land_radius, 50.0)
	assert_eq(d.leap_burst_count, 8)
	assert_eq(d.leap_burst_speed, 220.0)
	assert_eq(d.leap_burst_lifetime, 2.0)

func test_leap_counts_toward_max_attack_range() -> void:
	# max_attack_range feeds firing/kiting distance; a LEAP's range should register.
	assert_eq(_leaper().max_attack_range(), 400.0)

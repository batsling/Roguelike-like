extends GutTest

# Covers the four sheet-authored items added with new engine vocabulary:
#   * Ginger / Turnip — status_immunity: the PLAYER can no longer GAIN a status
#     (Weak / Frail). Blocked at the per-actor add_status choke point, so it
#     covers every source through the shared CombatActor add_status path.
#   * Toy Ornithopter — the run-scope `potion_used` trigger (heal on potion use).
#   * Darkstone Periapt — the curse_applied heal (mirrors Vitality Orb).

func before_each() -> void:
	GameState.reset_run()

func _trigger_for(item: ItemData, on_name: String) -> Dictionary:
	for t in item.triggers:
		if String(t.get("on", "")) == on_name:
			return t
	return {}

# --- Data load ---------------------------------------------------------------

func test_all_four_items_load() -> void:
	for id in ["ginger", "turnip", "toy_ornithopter", "darkstone_periapt"]:
		assert_not_null(Data.get_item(StringName(id)), "%s.tres should load" % id)

func test_ginger_and_turnip_declare_immunity() -> void:
	var ginger: ItemData = Data.get_item(&"ginger")
	assert_true("weak" in ginger.status_immunity, "Ginger blocks Weak")
	var turnip: ItemData = Data.get_item(&"turnip")
	assert_true("frail" in turnip.status_immunity, "Turnip blocks Frail")

# --- Status immunity (Ginger / Turnip) --------------------------------------

func test_immunity_blocks_status_on_player_combat_actor() -> void:
	GameState.add_item(Data.get_item(&"ginger"))
	var player := CombatActor.from_player()
	player.add_status(&"weak", 2)
	assert_eq(player.get_status(&"weak"), 0, "Ginger drops Weak applied to the player")
	# An unrelated status still lands — immunity is per-status, not a blanket ward.
	player.add_status(&"poison", 3)
	assert_eq(player.get_status(&"poison"), 3, "non-immune statuses still apply")

func test_immunity_does_not_protect_enemies() -> void:
	GameState.add_item(Data.get_item(&"ginger"))
	var enemy := CombatActor.new()  # is_player == false
	enemy.add_status(&"weak", 2)
	assert_eq(enemy.get_status(&"weak"), 2, "immunity is the player's, not the enemy's")

func test_no_immunity_without_the_item() -> void:
	var player := CombatActor.from_player()
	player.add_status(&"weak", 2)
	assert_eq(player.get_status(&"weak"), 2, "without Ginger, Weak applies normally")

# --- Toy Ornithopter (potion_used heal) -------------------------------------

func test_toy_ornithopter_heals_on_potion_used() -> void:
	var it: ItemData = Data.get_item(&"toy_ornithopter")
	var trig: Dictionary = _trigger_for(it, "potion_used")
	assert_false(trig.is_empty(), "Toy Ornithopter listens for potion_used")
	GameState.add_item(it)
	GameState.change_hp(-20)  # open up headroom so the heal isn't capped away
	var before: int = GameState.hp
	# Drive the real choke point: notify_used fires the potion_used trigger once.
	PotionSystem.notify_used(Data.get_potion(&"block_potion"), "(drank)")
	assert_eq(GameState.hp, before + 5, "using a potion heals +5 HP")

func test_toy_ornithopter_only_fires_when_owned() -> void:
	GameState.change_hp(-20)
	var before: int = GameState.hp
	PotionSystem.notify_used(Data.get_potion(&"block_potion"), "(drank)")
	assert_eq(GameState.hp, before, "no heal without the item")

# --- Darkstone Periapt (curse_applied max-HP) -------------------------------

func test_darkstone_periapt_grants_max_hp_on_curse() -> void:
	var it: ItemData = Data.get_item(&"darkstone_periapt")
	var trig: Dictionary = _trigger_for(it, "curse_applied")
	assert_false(trig.is_empty(), "Darkstone Periapt listens for curse_applied")
	GameState.add_item(it)
	var before: int = GameState.max_hp
	GameState.add_active_curse(Data.get_curse(&"curse_of_guilt"))
	assert_eq(GameState.max_hp, before + 6, "gaining a curse grants +6 Max HP")
